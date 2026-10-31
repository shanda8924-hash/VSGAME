extends Node2D
## Actual terrain collider + production spawn routes. Protect the normal save.
const GAME := preload("res://scenes/game.tscn")
const OUTPUT := "res://artifacts/fountain_spawn"
var game: Node2D
var player: Player
var stage: StageEnvironment
var elites: EliteRoomManager
var wave: WaveSpawner
var bosses: BossSpawner
var map: DungeonMap
var room_index := -1
var fountain_anchor := Vector2i.ZERO
var failures := 0
var selected_seed := -1
var query: PhysicsShapeQueryParameters2D

func _ready() -> void:
	SaveManager.begin_ephemeral_session()
	get_tree().create_timer(90.0, true, false, true).timeout.connect(func():
		push_error("FOUNTAIN_SPAWN_CHECK timeout")
		get_tree().quit(1)
	)
	_run.call_deferred()

func _exit_tree() -> void:
	SaveManager.end_ephemeral_session()

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	game = GAME.instantiate() as Node2D
	game.tree_entered.connect(func(): get_tree().current_scene = game)
	get_tree().root.add_child(game)
	var controller := game.get_node("MapRunController") as MapRunController
	while not controller._active:
		await get_tree().process_frame
	player = game.get_node("Player") as Player
	stage = game.get_node("StageEnvironment") as StageEnvironment
	_check(stage._tile_set != null, "production Stage TileSet exists before physics verification")
	if stage._tile_set == null:
		get_tree().quit(1)
		return
	elites = game.get_node("EliteRoomManager") as EliteRoomManager
	wave = game.get_node("WaveSpawner") as WaveSpawner
	bosses = game.get_node("BossSpawner") as BossSpawner
	player.health_component.invincible = true
	player.set_movement_locked(true)
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	for name in ["MapRunController", "WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		game.get_node(name).process_mode = Node.PROCESS_MODE_DISABLED
	await _clear_enemies()
	_find_generated_fountain_room()
	_check(map != null, "production generation has an elite room containing a fountain")
	if map == null:
		get_tree().quit(1)
		return
	GameManager.dungeon_map = map
	stage.build_dungeon(map)
	elites.setup(map)
	wave.configure_map_phase({})
	player.global_position = map.grid_to_world(map.spawn_point)
	await _physics_frames(3)
	query = PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0 * elites.elite_visual_scale
	query.shape = circle
	query.collision_mask = 1
	query.collide_with_areas = false
	query.exclude = [player.get_rid()]
	_check_fountain_collider()
	if OS.get_cmdline_user_args().has("--pillar-only"):
		print("PILLAR_SURFACE_CHECK failures=%d seed=%d" % [failures, selected_seed])
		get_tree().quit(0 if failures == 0 else 1)
		return
	_sample_spawn_routes()
	_check_generated_candidates()
	_check_spawn_cache()
	await _test_actual_normal_spawns()
	await _test_actual_room_spawns()
	await _test_actual_summons()
	await _test_no_safe_cells()
	_check(SaveManager.is_ephemeral_session_active(), "normal save remains protected")
	print("FOUNTAIN_SPAWN_CHECK failures=%d seed=%d room=%d fountain=%s" % [failures, selected_seed, room_index, fountain_anchor])
	get_tree().quit(0 if failures == 0 else 1)

func _find_generated_fountain_room() -> void:
	for seed_value in range(200):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var candidate := DungeonGenerator.generate(78, 78, 10, 1, rng)
		for index in candidate.elite_room_indices:
			if candidate.combat_region_by_room.get(index, "") != DungeonMap.REGION_PILLAR_FIELD:
				continue
			for key in candidate.terrain_obstacle_cells:
				var cell: Vector2i = key
				if not candidate.rooms[index].has_point(cell): continue
				if candidate.is_terrain_obstacle(cell + Vector2i.LEFT) or candidate.is_terrain_obstacle(cell + Vector2i.UP): continue
				# Keep the same generated room as the original fountain regression so
				# spawn-route expectations remain comparable after its art is removed.
				if stage._hash_index(cell.x, cell.y, 1601, 2593, 2) != 1: continue
				map = candidate
				room_index = index
				fountain_anchor = cell
				selected_seed = seed_value
				return

func _check_fountain_collider() -> void:
	for offset: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
		var cell := fountain_anchor + offset
		_check(not map.is_floor(cell) and map.is_terrain_obstacle(cell), "fountain cells are already excluded from floor data")
		_check(stage._tile_map_layer.get_cell_source_id(cell) == StageEnvironment.WALL_JUNCTION_SOURCE_ID, "pillar obstacle uses the same visible stone wall as the map")
		_check(stage._wall_overlay_layer.get_cell_source_id(cell) == -1, "pillar obstacle has no floating orb overlay")
		var physical_center := stage._tile_map_layer.to_global(stage._tile_map_layer.map_to_local(cell))
		_check(_blocked(physical_center), "fountain quadrant blocks the actual enemy body")
	print("FOUNTAIN_COLLISION four_blocked_cells=4 radius=%.1f" % (query.shape as CircleShape2D).radius)

func _sample_spawn_routes() -> void:
	seed(772001)
	var room := map.rooms[room_index]
	var near_position := map.grid_to_world(fountain_anchor) + Vector2(0, 320)
	var blocked_counts := {"room_elite": 0, "roaming_elite": 0, "normal_surge": 0, "boss_legacy": 0}
	var interior_counts := blocked_counts.duplicate()
	for _index in range(1024):
		var positions := {
			"room_elite": elites._pick_position_in_room(room),
			"roaming_elite": elites._pick_roaming_position(near_position),
			"normal_surge": wave._pick_spawn_position(near_position),
			"boss_legacy": bosses._pick_spawn_position(near_position),
		}
		for route in positions:
			var position: Vector2 = positions[route]
			if _blocked(position): blocked_counts[route] += 1
			if not map.is_floor(map.world_to_grid(position)): interior_counts[route] += 1
	print("FOUNTAIN_SPAWN_SAMPLING samples_per_route=1024 blocked=%s nonfloor=%s" % [JSON.stringify(blocked_counts), JSON.stringify(interior_counts)])
	for route in blocked_counts:
		_check(blocked_counts[route] == 0, "%s never overlaps actual wall/fountain collider (%d/1024)" % [route, blocked_counts[route]])

func _check_generated_candidates() -> void:
	var count := 0
	var elite_rooms := 0
	for config: Vector4i in [Vector4i(78, 78, 10, 1), Vector4i(86, 86, 11, 2), Vector4i(94, 94, 12, 2)]:
		for seed_value in range(12):
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var candidate := DungeonGenerator.generate(config.x, config.y, config.z, config.w, rng)
			var floors := candidate.get_floor_cells()
			var obstacles := candidate.terrain_obstacle_cells.duplicate()
			_check(not candidate.get_spawn_cells().is_empty(), "normal production map has safe spawn candidates")
			for index in candidate.elite_room_indices:
				_check(not candidate.get_spawn_cells(candidate.rooms[index].grow(-1)).is_empty(), "production elite room has safe candidates")
				elite_rooms += 1
			_check(candidate.get_floor_cells() == floors and candidate.terrain_obstacle_cells == obstacles, "safe spawn queries do not change terrain")
			count += 1
	print("FOUNTAIN_GENERATED_CANDIDATES maps=%d elite_rooms=%d" % [count, elite_rooms])

func _test_actual_normal_spawns() -> void:
	player.global_position = map.grid_to_world(fountain_anchor) + Vector2(0, 320)
	for _index in range(16):
		wave._spawn_enemy()
	var enemies := get_tree().get_nodes_in_group("enemies")
	_check(enemies.size() == 16, "actual normal spawn keeps count")
	for enemy: EnemyBasic in enemies:
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		_check(not _blocked(enemy.global_position), "actual normal enemy body starts outside terrain")
	print("FOUNTAIN_REAL_NORMAL count=%d" % enemies.size())
	await _clear_enemies()

func _check_spawn_cache() -> void:
	var fixture := DungeonMap.new(12, 12)
	_check(fixture.get_spawn_cells().is_empty(), "empty spawn cache builds once without candidates")
	for y in range(-2, 3):
		for x in range(-2, 3): fixture.set_floor(Vector2i(x, y), true)
	var cells := fixture.get_spawn_cells()
	_check(cells.size() == 9, "set_floor invalidates and rebuilds safe spawn cache")
	cells.clear()
	_check(fixture.get_spawn_cells().size() == 9, "caller cannot mutate shared safe spawn cache")
	fixture.mark_terrain_obstacle(Vector2i.ZERO)
	_check(fixture.get_spawn_cells().is_empty(), "new obstacle invalidates all intersecting clearance cells")
	print("FOUNTAIN_SPAWN_CACHE rebuild_on_terrain_change=true returned_arrays_isolated=true")

func _test_actual_room_spawns() -> void:
	elites.elite_min_count = 1
	elites.elite_max_count = 1
	seed(8811)
	var blocked_count := 0
	var target: EnemyBasic
	var nearest := INF
	for _index in range(40):
		elites._spawn_elite_enemies(room_index)
		var alive: Array = elites._elite_enemies_alive.get(room_index, [])
		_check(alive.size() == 1, "actual elite spawn preserves count")
		if alive.is_empty(): continue
		var enemy := alive[0] as EnemyBasic
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		if _blocked(enemy.global_position): blocked_count += 1
		var distance := enemy.global_position.distance_to(map.grid_to_world(fountain_anchor + Vector2i.ONE))
		if distance < nearest and not _blocked(enemy.global_position):
			target = enemy
			nearest = distance
	_check(blocked_count == 0, "actual room elite spawns never overlap terrain (%d/40)" % blocked_count)
	print("FOUNTAIN_REAL_ELITES count=40 blocked=%d nearest_safe=%.1f" % [blocked_count, nearest])
	if target == null: return
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy != target: enemy.queue_free()
	# A real generated-room elite follows around the fountain toward the open center lane.
	player.global_position = map.grid_to_world(map.rooms[room_index].position + map.rooms[room_index].size / 2)
	player.camera.position_smoothing_enabled = false
	player.camera.reset_smoothing()
	player.camera.force_update_scroll()
	await _physics_frames(3)
	var start_distance := target.global_position.distance_to(player.global_position)
	await _capture("elite_spawn")
	target.process_mode = Node.PROCESS_MODE_INHERIT
	await _physics_frames(240)
	var end_distance := target.global_position.distance_to(player.global_position)
	_check(end_distance < start_distance - 24.0 or end_distance <= target.enemy_data.attack_range + 2.0, "real elite can leave spawn and pursue player around fountain")
	_check(not _blocked(target.global_position), "pursuing elite does not enter fountain collider")
	await _capture("elite_pursuit")
	print("FOUNTAIN_REAL_CHASE start=%.1f end=%.1f" % [start_distance, end_distance])
	await _clear_enemies()

func _test_actual_summons() -> void:
	var summoner := wave.enemy_scene.instantiate() as EnemyBasic
	summoner.enemy_data = DataLoader.enemies.get("basic_enemy")
	GameManager.get_runtime_world(self).add_child(summoner)
	summoner.global_position = map.grid_to_world(fountain_anchor + Vector2i.ONE) + Vector2(-130, 0)
	summoner.process_mode = Node.PROCESS_MODE_DISABLED
	var summons := SummonStrategy.new()
	summons.summon_count_min = 3
	summons.summon_count_max = 3
	var finished := {"value": false}
	seed(7364)
	_run_summon(summons, summoner, finished)
	while not finished["value"]:
		# Freeze each real summoned body before it can separate out of a bad spawn.
		for enemy in get_tree().get_nodes_in_group("boss_summons"):
			enemy.process_mode = Node.PROCESS_MODE_DISABLED
		await get_tree().process_frame
	var count := 0
	var blocked_count := 0
	for enemy in get_tree().get_nodes_in_group("boss_summons"):
		count += 1
		if _blocked(enemy.global_position): blocked_count += 1
	_check(count == 3, "actual boss summon retains configured enemy count")
	_check(blocked_count == 0, "actual summon ring avoids fountain collision")
	print("FOUNTAIN_REAL_SUMMONS count=%d blocked=%d" % [count, blocked_count])
	await _clear_enemies()

func _run_summon(strategy: SummonStrategy, summoner: EnemyBasic, result: Dictionary) -> void:
	await strategy.execute(summoner, player)
	result["value"] = true

func _test_no_safe_cells() -> void:
	var empty := DungeonMap.new(24, 24)
	empty.rooms.append(Rect2i(-3, -3, 6, 6))
	# A one-cell corridor is floor, but cannot safely hold the current enemy body.
	for x in range(-3, 3): empty.set_floor(Vector2i(x, 0), true)
	GameManager.dungeon_map = empty
	elites.setup(empty)
	wave.configure_map_phase({})
	_check(empty.get_spawn_cells().is_empty(), "narrow corridor exercises no-clearance fallback")
	_check(empty.find_spawn_position_near(Vector2.ZERO) == Vector2.INF, "no safe point returns sentinel without random retries")
	_check(wave._pick_spawn_position(Vector2.ZERO) == Vector2.INF, "normal spawn refuses unsafe ring fallback")
	wave._spawn_enemy()
	_check(get_tree().get_nodes_in_group("enemies").is_empty(), "normal spawn aborts before instantiation")
	_check(not elites._spawn_roaming_elite(), "roaming elite failure permits existing timed retry")
	elites._rooms_active[0] = true
	elites._spawn_elite_enemies(0)
	_check(not elites._rooms_active.get(0, false) and elites._rooms_cleared.get(0, false), "empty elite encounter completes without a deadlocked active room")
	var count_before := bosses._boss_spawn_count
	var epoch_before := bosses._encounter_epoch
	var boss := bosses.start_room_boss(1, {"candidates": ["minotaur"]}, Vector2.ZERO)
	_check(boss == null and not bosses._room_encounter_active and not bosses._prepared_room_boss, "no-safe-cell Boss failure clears pending encounter")
	_check(bosses._boss_spawn_count == count_before and bosses._encounter_epoch == epoch_before, "failed Boss spawn does not consume count or epoch")
	var controller := game.get_node("MapRunController") as MapRunController
	controller._boss_unlocked = true
	controller._boss_active = false
	controller._boss_gate.used = true
	controller._start_map_boss()
	_check(not controller._boss_active and controller._boss_gate.visible and not controller._boss_gate.used, "MAP Boss failure restores gate interaction and clears fight state")
	_check(not wave._spawning_paused, "MAP Boss failure restores normal spawning mode")
	GameManager.dungeon_map = map
	elites.setup(map)
	wave.configure_map_phase({})
	# Correct terrain supplied again: an explicit bad override is relocated, not discarded.
	boss = bosses.start_room_boss(1, {"candidates": ["minotaur"]}, map.grid_to_world(fountain_anchor + Vector2i.ONE))
	_check(boss != null and not _blocked((boss as EnemyBasic).global_position), "Boss can retry successfully at a relocated safe position")
	if boss != null:
		bosses.clear_room_boss()
	await _physics_frames(3)
	print("FOUNTAIN_EMPTY_FALLBACK normal=abort roaming=retry elite=complete room=complete boss=retryable")

func _blocked(position: Vector2) -> bool:
	if not position.is_finite(): return true
	query.transform = Transform2D(0.0, position)
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT + "/" + name + ".png")

func _clear_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"): enemy.queue_free()
	await _physics_frames(2)

func _physics_frames(count: int) -> void:
	for _index in count: await get_tree().physics_frame

func _check(ok: bool, message: String) -> void:
	if ok: return
	failures += 1
	if failures <= 24: push_error("FOUNTAIN_SPAWN_CHECK: " + message)
