extends Node
## Focused architecture regression: production generation, renderer and MAP boss path.
## No production code/data mutation. Only fixture placement and camera are controlled.
const GAME := preload("res://scenes/game.tscn")
const MAP_SIZES := [Vector4i(78, 78, 10, 1), Vector4i(86, 86, 11, 2), Vector4i(94, 94, 12, 2)]
const OUTPUT_DIR := "res://artifacts/map_architecture"
const RETIRED_GRATES := [Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0)]
const NO_CELL := Vector2i(999999, 999999)
var game: Node2D
var environment: StageEnvironment
var controller: MapRunController
var player: Player
var failures: Array[String] = []
var failure_count := 0
var _stage := "boot"
var _save_session := false
var _seed_count := 0
var _overlay_wall_cells := 0
var _pillar_cells := 0
var _vertical_cells := 0
var _visual_map: DungeonMap

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	_save_session = true
	get_tree().create_timer(90.0, true, false, true).timeout.connect(_watchdog)
	_run.call_deferred()

func _exit_tree() -> void:
	if _save_session:
		SaveManager.end_ephemeral_session()

func _watchdog() -> void:
	push_error("MAP_ARCHITECTURE_CHECK timeout: " + _stage)
	get_tree().quit(1)

func _check(ok: bool, message: String) -> void:
	if ok:
		return
	failure_count += 1
	# Preserve the total, but avoid repeating thousands of identical tile failures.
	if failures.size() < 24:
		failures.append(message)
		push_error("MAP_ARCHITECTURE_CHECK: " + message)

func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	game = GAME.instantiate() as Node2D
	game.tree_entered.connect(func(): get_tree().current_scene = game)
	get_tree().root.add_child(game)
	player = game.get_node("Player") as Player
	player.health_component.invincible = true
	environment = game.get_node("StageEnvironment") as StageEnvironment
	controller = game.get_node("MapRunController") as MapRunController
	var deadline := Time.get_ticks_msec() + 20000
	while not controller._active and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(controller._active and GameManager.map_mode_active, "game.tscn starts actual MAP controller")
	if not controller._active:
		get_tree().quit(1)
		return
	_disable_automatic_combat()
	player.set_movement_locked(true)
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(3)
	_check(get_tree().get_nodes_in_group("map_hazard").is_empty(), "normal MAP startup has no environmental damage hazard")
	_stage = "seed topology"
	_check_chokepoint_orientations()
	_check_seeded_maps()
	_check_overlay_image()
	_stage = "sync and async production build"
	var chosen: DungeonMap
	for index in MAP_SIZES.size():
		var size: Vector4i = MAP_SIZES[index]
		var rng := RandomNumberGenerator.new()
		rng.seed = 90205 + index * 93
		var map := DungeonGenerator.generate(size.x, size.y, size.z, size.w, rng)
		if index == 0 and _visual_map != null:
			map = _visual_map
		var floors := map.get_floor_cells()
		var obstacles := map.terrain_obstacle_cells.duplicate()
		seed(731 + index)
		environment.build_dungeon(map)
		_check_render(map, "sync map%d" % (index + 1))
		_check(map.get_floor_cells() == floors and map.terrain_obstacle_cells == obstacles, "sync renderer never edits map graph")
		seed(731 + index)
		await environment.build_dungeon_async(map, 5)
		_check_render(map, "async map%d" % (index + 1))
		_check(map.get_floor_cells() == floors and map.terrain_obstacle_cells == obstacles, "async renderer never edits map graph")
		if index == 0:
			chosen = map
	_check(_pillar_cells > 0, "physical 2x2 pillars remain present")
	_check(_vertical_cells > 0, "vertical chokepoint walls remain present")
	_check(_overlay_wall_cells > 0, "transparent wall decorations are actually used")
	await _activate_visual_map(chosen)
	await _check_visuals_and_boss(chosen)
	_check(SaveManager.is_ephemeral_session_active(), "normal save remained protected")
	print("MAP_ARCHITECTURE_CHECK failures=%d seeds=%d sync_builds=3 async_builds=4 overlay_wall_cells=%d pillar_cells=%d vertical_cells=%d" % [failure_count, _seed_count, _overlay_wall_cells, _pillar_cells, _vertical_cells])
	get_tree().quit(0 if failure_count == 0 else 1)

func _disable_automatic_combat() -> void:
	for name in ["WaveSpawner", "EliteRoomManager", "BossSpawner", "MapRunController"]:
		game.get_node(name).process_mode = Node.PROCESS_MODE_DISABLED
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()

func _check_chokepoint_orientations() -> void:
	for room: Rect2i in [Rect2i(-6, -4, 12, 8), Rect2i(-4, -6, 8, 12)]:
		var map := DungeonMap.new(32, 32)
		for y in range(room.position.y, room.end.y):
			for x in range(room.position.x, room.end.x):
				map.set_floor(Vector2i(x, y), true)
		map.spawn_point = room.position
		DungeonGenerator._apply_chokepoint(map, room)
		var center := room.position + room.size / 2
		if room.size.x >= room.size.y:
			_check(not map.terrain_obstacle_cells.is_empty(), "wide-room vertical chokepoint is retained")
			for cell: Vector2i in map.terrain_obstacle_cells:
				_check(cell.x == center.x and absi(cell.y - center.y) > 1, "retained chokepoint is vertical with three-cell opening")
		else:
			_check(map.terrain_obstacle_cells.is_empty(), "tall-room horizontal small walls are removed")
		_check(bool(DungeonGenerator.validate_reachability(map).get("reachable", false)), "chokepoint fixture remains reachable")

func _check_seeded_maps() -> void:
	for size: Vector4i in MAP_SIZES:
		for number in 12:
			var rng := RandomNumberGenerator.new()
			rng.seed = 5200 + _seed_count * 97 + number
			var map := DungeonGenerator.generate(size.x, size.y, size.z, size.w, rng)
			_check(bool(DungeonGenerator.validate_reachability(map).get("reachable", false)), "seed %d remains fully reachable" % rng.seed)
			_check(map.hazard_regions.is_empty(), "seed %d has no hazard rectangles" % rng.seed)
			for cell in map.get_combat_region_cells():
				_check(map.get_combat_region_type(cell) != DungeonMap.REGION_HAZARD, "seed %d has no hazard region cells" % rng.seed)
			var boss_index := int(map.get("boss_room_index"))
			_check(boss_index > 0 and boss_index < map.rooms.size(), "seed %d has a dedicated non-start boss room" % rng.seed)
			if boss_index > 0 and boss_index < map.rooms.size():
				_check_boss_room(map, boss_index, "seed %d" % rng.seed)
			for index: int in map.combat_region_by_room:
				if String(map.combat_region_by_room[index]) != DungeonMap.REGION_CHOKEPOINT:
					continue
				var room: Rect2i = map.rooms[index]
				if size.x == 78 and room.size.x >= room.size.y and _visual_map == null:
					_visual_map = map
					print("MAP_ARCHITECTURE_VISUAL_SEED ", rng.seed)
				var center := room.position + room.size / 2
				for cell: Vector2i in map.terrain_obstacle_cells:
					if room.has_point(cell):
						_check(room.size.x >= room.size.y and cell.x == center.x, "seed %d has no horizontal chokepoint obstacle" % rng.seed)
			_seed_count += 1

func _check_boss_room(map: DungeonMap, index: int, context: String) -> void:
	var room: Rect2i = map.rooms[index]
	var center := room.position + room.size / 2
	_check(room.size.x >= 14 and room.size.y >= 14, context + ": production boss chamber has 14x14 combat space")
	_check(index not in map.elite_room_indices, context + ": boss room is not also elite")
	_check(map.has_navigation_clearance(center), context + ": boss gate center has navigation clearance")
	_check(map.has_navigation_clearance(center + Vector2i(3, 0)), context + ": actual boss spawn offset has navigation clearance")
	var entrances := 0
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			var cell := Vector2i(x, y)
			_check(map.is_floor(cell) and not map.is_terrain_obstacle(cell), context + ": boss floor is unobstructed")
			if x == room.position.x and map.is_floor(cell + Vector2i.LEFT): entrances += 1
			if x == room.end.x - 1 and map.is_floor(cell + Vector2i.RIGHT): entrances += 1
			if y == room.position.y and map.is_floor(cell + Vector2i.UP): entrances += 1
			if y == room.end.y - 1 and map.is_floor(cell + Vector2i.DOWN): entrances += 1
	_check(entrances >= 3, context + ": boss chamber has a usable entry")

func _check_render(map: DungeonMap, context: String) -> void:
	var overlay := environment.get_node_or_null("WallOverlayTileMapLayer") as TileMapLayer
	_check(overlay != null, context + ": separate transparent overlay layer exists")
	if overlay == null:
		return
	for cell in environment._combat_terrain_layer.get_used_cells():
		_check(environment._combat_terrain_layer.get_cell_atlas_coords(cell) not in RETIRED_GRATES, context + ": no retired damage grate tiles")
	for cell in overlay.get_used_cells():
		_check(overlay.get_cell_source_id(cell) == 3, context + ": generated overlay atlas connected")
		var overlay_data := overlay.get_cell_tile_data(cell)
		_check(overlay_data != null and overlay_data.get_collision_polygons_count(0) == 0, context + ": decoration adds no collision")
		if not map.is_floor(cell):
			var base := environment._tile_map_layer.get_cell_tile_data(cell)
			_check(base != null and base.get_collision_polygons_count(0) == 1, context + ": wall/pillar under decoration keeps solid base collision")
			_overlay_wall_cells += 1
	for cell: Vector2i in map.terrain_obstacle_cells:
		var base := environment._tile_map_layer.get_cell_tile_data(cell)
		_check(base != null and base.get_collision_polygons_count(0) == 1, context + ": obstacle collision remains")
		if map.get_combat_region_type(cell) == DungeonMap.REGION_PILLAR_FIELD:
			_check(environment._tile_map_layer.get_cell_source_id(cell) == 0 and environment._tile_map_layer.get_cell_alternative_tile(cell) == 3, context + ": pillar has floor-texture blocker base")
			_check(overlay.get_cell_source_id(cell) == 3, context + ": transparent physical pillar overlays every footprint cell")
			_pillar_cells += 1
		elif map.get_combat_region_type(cell) == DungeonMap.REGION_CHOKEPOINT:
			_vertical_cells += 1
	# Wall overlays must never be installed as opaque replacement wall tiles.
	for cell in environment._tile_map_layer.get_used_cells():
		var source := environment._tile_map_layer.get_cell_source_id(cell)
		_check(source != 3, context + ": base tile layer is not overwritten by decoration atlas")
	var seal := environment.get_node_or_null("BossFloorSeal") as Sprite2D
	_check(seal != null and seal.visible and seal.texture != null, context + ": generated boss floor seal is connected")
	if seal:
		var room: Rect2i = map.rooms[map.boss_room_index]
		_check(seal.position == map.grid_to_world(room.position + room.size / 2), context + ": seal follows reserved boss chamber")
		var border_cells := 0
		for cell in environment._decoration_layer.get_used_cells():
			if environment._decoration_layer.get_cell_source_id(cell) != 4:
				continue
			border_cells += 1
			_check(room.has_point(cell) and map.is_floor(cell), context + ": boss border stays inside clear combat floor")
		_check(border_cells == 2 * (room.size.x - 2) + 2 * (room.size.y - 4), context + ": complete boss inner perimeter uses generated border image")

func _activate_visual_map(map: DungeonMap) -> void:
	_stage = "real MAP content on seeded map"
	controller._clear_map_nodes()
	await _frames(2)
	GameManager.dungeon_map = map
	await environment.build_dungeon_async(map, 5)
	player.global_position = map.grid_to_world(map.spawn_point)
	player.setup_camera_limits(map)
	controller._start_map(1)
	_disable_automatic_combat()
	await _frames(4)
	_check(get_tree().get_nodes_in_group("map_hazard").is_empty(), "real MAP content path creates no damage hazard nodes")
	var boss_index := int(map.get("boss_room_index"))
	var room: Rect2i = map.rooms[boss_index]
	for content in get_tree().get_nodes_in_group("map_content"):
		if not content is Node2D or content == controller._boss_gate:
			continue
		_check(not room.has_point(map.world_to_grid((content as Node2D).global_position)), "boss chamber excludes treasure/recovery landmarks")
	_check(is_instance_valid(controller._boss_gate) and room.has_point(map.world_to_grid(controller._boss_gate.global_position)), "boss gate uses reserved room")

func _check_visuals_and_boss(map: DungeonMap) -> void:
	_stage = "normal/banner/vertical screenshots"
	await _capture_room(map, 0, "normal_room")
	var overlay := environment.get_node_or_null("WallOverlayTileMapLayer") as TileMapLayer
	var banner_cell := NO_CELL
	if overlay:
		for cell in overlay.get_used_cells():
			var coords := overlay.get_cell_atlas_coords(cell)
			if coords.y == 1 and coords.x in [0, 1, 2] and not map.is_floor(cell):
				banner_cell = cell
				break
	_check(banner_cell != NO_CELL, "runtime contains a banner over intact wall")
	if banner_cell != NO_CELL:
		await _capture_at(map.grid_to_world(banner_cell + Vector2i.DOWN * 3), "banner_wall")
	var vertical_room := -1
	for index: int in map.combat_region_by_room:
		if String(map.combat_region_by_room[index]) == DungeonMap.REGION_CHOKEPOINT and map.rooms[index].size.x >= map.rooms[index].size.y:
			vertical_room = index
			break
	_check(vertical_room >= 0, "visual seed includes retained vertical wall")
	if vertical_room >= 0:
		await _capture_room(map, vertical_room, "vertical_wall")
	var boss_index := int(map.get("boss_room_index"))
	await _capture_room(map, boss_index, "boss_chamber")
	await _capture_overview(map, boss_index, "boss_chamber_overview")
	_stage = "actual boss interaction"
	var gate := controller._boss_gate
	if not is_instance_valid(gate):
		_check(false, "boss gate missing before interaction")
		return
	player.global_position = gate.global_position + Vector2(0, 36)
	await _frames(2)
	gate._on_body_entered(player)
	_check(not gate.available and gate.can_interact(player), "locked gate exposes condition feedback nearby")
	_check(gate.interact(player) and not gate.used and not controller._boss_active, "locked interaction does not consume gate or spawn boss")
	# Force only the kill/time condition, then use the actual E interaction method.
	controller.debug_force_boss_ready()
	gate._on_body_entered(player)
	_check(gate.can_interact(player) and gate.available, "player can use unlocked boss entry")
	_check(gate.interact(player), "boss entry accepts E-equivalent interaction")
	await _frames(4)
	var boss := (game.get_node("BossSpawner") as BossSpawner).debug_get_current_boss() as EnemyBasic
	_check(boss != null, "actual MAP boss spawns through BossSpawner")
	if boss:
		boss.set_movement_locked(true)
		var boss_cell := map.world_to_grid(boss.global_position)
		_check(map.rooms[boss_index].has_point(boss_cell) and map.is_floor(boss_cell), "actual boss spawn is inside dedicated clear room")
		_check(not map.is_terrain_obstacle(boss_cell), "boss never spawns in pillar")
	_check(not gate.interact(player), "boss gate cannot activate twice")
	await get_tree().create_timer(1.4, true, false, true).timeout
	(game.get_node("ScreenEffects") as ScreenEffects).restore_runtime_state()
	_check(is_instance_valid(boss) and boss.health_component.current_hp > 0.0, "boss remains alive after intro before QA defeat")
	await _capture_room(map, boss_index, "boss_active")
	await _capture_overview(map, boss_index, "boss_alive_overview")
	_check(player.health_component.current_hp > 0.0, "test player remains alive")
	_check(not game.get_node("ResultScreen").visible, "game world stays rendered")
	_stage = "actual boss defeat reward"
	(game.get_node("BossSpawner") as BossSpawner).debug_defeat_current_boss()
	await _frames(6)
	var boss_chests := 0
	for content in get_tree().get_nodes_in_group("map_content"):
		if content is TreasureChest and content.is_boss_chest:
			boss_chests += 1
			var cell := map.world_to_grid(content.global_position)
			_check(map.rooms[boss_index].has_point(cell) and map.is_floor(cell), "boss reward appears inside reachable chamber")
	_check(boss_chests == 1 and not controller._boss_active, "real boss death completes combat and creates exactly one reward chest")

func _check_overlay_image() -> void:
	var texture := load("res://assets/tiles/royal/wall_overlays.png") as Texture2D
	_check(texture != null and texture.get_size() == Vector2(128, 64), "transparent decoration atlas is imported at contract size")
	if texture == null:
		return
	# QA-only image inspection: never runs on the gameplay hot path.
	var image := texture.get_image()
	for rect: Rect2i in [Rect2i(0, 0, 16, 32), Rect2i(16, 0, 16, 32), Rect2i(32, 0, 16, 32), Rect2i(48, 0, 16, 32), Rect2i(64, 0, 16, 16), Rect2i(80, 0, 16, 16), Rect2i(0, 32, 32, 32), Rect2i(32, 32, 32, 32)]:
		var transparent := false
		var opaque := false
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var alpha := image.get_pixel(x, y).a
				transparent = transparent or alpha == 0.0
				opaque = opaque or alpha == 1.0
		_check(transparent and opaque, "overlay object %s has real transparent background, not a baked wall rectangle" % rect)

func _capture_room(map: DungeonMap, index: int, suffix: String) -> void:
	var room: Rect2i = map.rooms[index]
	await _capture_at(map.grid_to_world(room.position + room.size / 2), suffix)

func _capture_overview(map: DungeonMap, index: int, suffix: String) -> void:
	# Screenshot fixture only: restore native player camera and HUD immediately.
	var camera := player.camera
	var old_zoom := camera.zoom
	var old_limits := Vector4i(camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom)
	var hud := game.get_node("HUD") as CanvasLayer
	var old_visible := hud.visible
	hud.hide()
	camera.zoom = Vector2.ONE
	camera.limit_left = -100000
	camera.limit_top = -100000
	camera.limit_right = 100000
	camera.limit_bottom = 100000
	await _capture_room(map, index, suffix)
	await _frames(2)
	camera.zoom = old_zoom
	camera.limit_left = old_limits.x
	camera.limit_top = old_limits.y
	camera.limit_right = old_limits.z
	camera.limit_bottom = old_limits.w
	hud.visible = old_visible
	camera.reset_smoothing()
	camera.force_update_scroll()
	await _frames(3)

func _capture_at(position: Vector2, suffix: String) -> void:
	player.global_position = position
	player.camera.reset_smoothing()
	player.camera.force_update_scroll()
	await _frames(4)
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image != null and not image.is_empty(), suffix + ": Vulkan image exists")
	if image:
		_check(image.save_png(OUTPUT_DIR + "/" + suffix + ".png") == OK, suffix + ": screenshot saved")
	print("MAP_ARCHITECTURE_CAPTURE ", suffix)
	# Do not mutate boss health / HUD inside the same render completion callback.
	await _frames(2)
