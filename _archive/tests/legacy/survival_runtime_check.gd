extends Node

var game: Node2D
var player: Player
var wave: WaveSpawner
var controller: MapRunController
var fired := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	game = get_parent()
	player = game.get_node("Player")
	wave = game.get_node("WaveSpawner")
	controller = game.get_node("MapRunController")
	player.health_component.invincible = true
	player.weapon_manager.weapon_fired.connect(func(): fired += 1)
	assert(GameManager.map_mode_active and controller._active, "Must use the real game entry")
	if "--maps-only" in OS.get_cmdline_user_args():
		for theme in [2,3]:
			controller._transition_to_map(theme,1)
			while controller._transitioning: await get_tree().process_frame
			controller._update_progress()
			await _capture("map%d" % theme)
		var exit_capture := preload("res://tests/runtime_exit_cleanup.gd").new()
		get_tree().root.add_child(exit_capture)
		exit_capture.begin(0,"SURVIVAL_MAP_CAPTURE PASS")
		return
	var map := GameManager.dungeon_map
	assert(map.get_meta("survival_layout", false) and not map.get_meta("exploration_layout", false))
	assert(map.elite_room_indices.is_empty() and controller._exploration_chests.is_empty(), "Old guard/key progression still active")
	assert(controller._exploration_map_ui != null, "Map key lost")
	assert(not Input.is_action_pressed("primary_attack"))
	# Geometry includes the real three-cell navigation clearance, not only connected pixels.
	for theme in [1,2,3]:
		for sample in 10:
			var rng := RandomNumberGenerator.new()
			rng.seed = 93000 + theme*100 + sample
			var generated := DungeonGenerator.generate(100+(theme-1)*8,100+(theme-1)*8,7+theme,0,rng,true)
			assert(generated.rooms.size() >= 4, "Too few large rooms")
			assert(DungeonGenerator.validate_reachability(generated).reachable)
			for room in generated.rooms:
				assert(room.size.x >= 18 and room.size.y >= 18, "Small encounter room survived")
			# The agent search is intentionally budgeted; topology check uses BFS below.
			var seen := {generated.spawn_point:true}
			var queue: Array[Vector2i] = [generated.spawn_point]
			var cursor := 0
			while cursor < queue.size():
				var cell := queue[cursor]
				cursor += 1
				for offset: Vector2i in [Vector2i.RIGHT,Vector2i.LEFT,Vector2i.UP,Vector2i.DOWN]:
					var next := cell+offset
					if not seen.has(next) and generated.has_navigation_clearance(next):
						seen[next] = true
						queue.append(next)
			for room in generated.rooms: assert(seen.has(room.get_center()), "Disconnected movement clearance")
	print("SURVIVAL geometry PASS: 30 seeds, broad rooms and connected clearance")
	var original_character := GameManager.selected_character_id
	# All six playable classes actually acquire nearby targets and attack with J released.
	wave.set_spawning_paused(true)
	for character_id: String in GameManager.PLAYABLE_CHARACTER_IDS:
		player.weapon_manager.cancel_current_attack()
		GameManager.selected_character_id = character_id
		player._apply_character_data()
		player.weapon_manager._setup_class_attack_pattern()
		player.weapon_manager._class_attack_cooldown = 0.0
		player.global_position = map.grid_to_world(map.spawn_point)
		player.face_direction(Vector2.LEFT)
		var dummy := wave.enemy_scene.instantiate() as EnemyBasic
		dummy.enemy_data = DataLoader.enemies.get("slime")
		dummy.position = player.position + Vector2(56,0)
		game.add_child(dummy)
		dummy.set_room_activation_locked(true)
		dummy.health_component.max_hp = 10000
		dummy.health_component.current_hp = 10000
		var before := fired
		for frame in 240:
			await get_tree().physics_frame
			if fired > before: break
		assert(fired > before, "No automatic attack: "+character_id)
		assert(player.get_facing_direction().x > 0.0, "Auto aim ignored target: "+character_id)
		for frame in 70: await get_tree().physics_frame
		assert(dummy.health_component.current_hp < 10000, "Automatic attack caused no damage: "+character_id)
		player.weapon_manager.cancel_current_attack()
		dummy.queue_free()
		for frame in 8: await get_tree().physics_frame
	GameManager.selected_character_id = original_character
	player._apply_character_data()
	player.weapon_manager._setup_class_attack_pattern()
	player.global_position = map.grid_to_world(map.spawn_point)
	print("SURVIVAL auto attack PASS: all six playable classes, no J, real target damage")
	# Natural spawning/AI/auto damage in the actual runtime, including menu pause.
	wave.configure_map_phase(controller._current_config)
	controller._map_started_at = GameManager.elapsed_seconds
	var start_kills := GameManager.kill_count
	var start_fired := fired
	var peak := 0
	var initial_time := GameManager.elapsed_seconds
	while GameManager.elapsed_seconds - initial_time < 32.0:
		await get_tree().physics_frame
		await _close_modals()
		peak = maxi(peak, wave._active_enemy_count())
		assert(wave._active_enemy_count() <= wave._map_enemy_cap, "Enemy cap exceeded")
	assert(peak >= 24, "No sustained horde; peak=%d" % peak)
	assert(fired > start_fired and GameManager.kill_count > start_kills, "Idle player did not auto-fight incoming enemies")
	assert(not controller._boss_unlocked, "Boss opened before threshold")
	for enemy: EnemyBasic in get_tree().get_nodes_in_group("enemies"):
		assert(not enemy.exploration_guard, "Wave enemy returns home")
	# Safe spawn candidates include real prop collision and minimum distance.
	for sample in 30:
		var point := wave._pick_spawn_position(player.position)
		if not point.is_finite(): continue
		assert(point.distance_to(player.position) >= wave.min_spawn_distance-24)
		assert(map.has_navigation_clearance(map.world_to_grid(point)))
		var shape := CircleShape2D.new()
		shape.radius = 26
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.collision_mask = 9
		query.transform = Transform2D(0,point)
		assert(game.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty())
	var old_fired := fired
	var old_timer := wave._timer
	GameManager.open_modal()
	await get_tree().create_timer(0.3,true).timeout
	assert(fired == old_fired and wave._timer == old_timer, "Combat continued under inventory")
	GameManager.close_modal()
	# K cancels an automatic strike; the next attack resumes after dodge recovery.
	wave.set_spawning_paused(true)
	player.dodge_cooldown = 0
	assert(player.try_dodge())
	assert(not player.weapon_manager._class_attack_in_progress and player.weapon_manager._sword_pending.is_empty())
	await get_tree().create_timer(0.3).timeout
	print("SURVIVAL horde PASS: peak=%d kills=%d; safe spawn, automatic damage, pause and K" % [peak,GameManager.kill_count-start_kills])
	await _capture("horde")
	# Replenishment and distant culling never award kills or loot.
	var kills_before := GameManager.kill_count
	for enemy: EnemyBasic in get_tree().get_nodes_in_group("enemies"):
		if enemy.get_meta("survival_wave",false):
			enemy.position = player.position + Vector2(2000,0)
			enemy.process_mode = Node.PROCESS_MODE_DISABLED
	player.weapon_manager.cancel_current_attack()
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	wave._recycle_distant_enemies()
	await get_tree().process_frame
	assert(GameManager.kill_count == kills_before)
	wave.set_spawning_paused(false)
	await get_tree().create_timer(1.4).timeout
	assert(wave._active_enemy_count() > 0, "Wave did not replenish")
	var elite_manager := game.get_node("EliteRoomManager") as EliteRoomManager
	elite_manager._next_roaming_spawn_at = GameManager.elapsed_seconds
	for frame in 4: await get_tree().physics_frame
	assert(not get_tree().get_nodes_in_group("elite_enemies").is_empty(), "Timed elite did not join wave")
	for elite: EnemyBasic in get_tree().get_nodes_in_group("elite_enemies"):
		assert(elite.enemy_data.id in WaveSpawner.MAP_ENEMY_ROSTERS[1].strong)
		assert(not elite.exploration_guard)
		assert(is_equal_approx(elite.room_hp_multiplier,wave._map_hp_multiplier))
	# Deterministic economy check exercises the same death reward handler.
	var economy := game.get_node("RunEconomySystem") as RunEconomySystem
	var old_gold := GameManager.run_gold
	economy._ordinary_kills = 0
	for index in 4: economy._on_enemy_drop_requested(Vector2.ZERO,false,false)
	assert(GameManager.run_gold == old_gold+1, "Horde gold inflated")
	assert(player.experience_component._requirement_multiplier == 2.0)
	assert(game.get_node("HeartDropSystem").max_ground_hearts == 3)
	# Kill gate and timed rescue both work without keys.
	controller._map_kills = int(controller._current_config.boss_kill_requirement)
	controller._update_progress()
	assert(controller._boss_unlocked and controller._boss_gate.available)
	controller._boss_unlocked = false
	controller._map_kills = 0
	controller._map_started_at = GameManager.elapsed_seconds - float(controller._current_config.boss_fallback_seconds)
	controller._update_progress()
	assert(controller._boss_unlocked)
	controller._start_map_boss()
	for frame in 5: await get_tree().physics_frame
	assert(controller._boss_active and wave.is_map_spawn_suppressed())
	assert(not game.get_node("StageEnvironment")._boss_floor_seal.visible)
	for enemy: EnemyBasic in get_tree().get_nodes_in_group("enemies"):
		assert(enemy.enemy_data is BossData, "Wave survived boss entry")
	game.get_node("BossSpawner").debug_defeat_current_boss()
	for frame in 10: await get_tree().physics_frame
	await _close_modals()
	assert(wave.is_map_spawn_suppressed() and is_instance_valid(controller._stairs), "Unsafe reward phase")
	assert(not controller._stairs.available)
	controller._boss_chest._on_body_entered(player)
	assert(controller._boss_chest.interact(player))
	assert(controller._stairs.available and GameManager.current_depth == 1)
	# All theme/floor transitions retain horde configuration and safe density progression.
	for phase in [Vector2i(1,2),Vector2i(1,20),Vector2i(2,1),Vector2i(2,20),Vector2i(3,1),Vector2i(3,20)]:
		controller._transition_to_map(phase.x,phase.y)
		while controller._transitioning: await get_tree().process_frame
		assert(GameManager.dungeon_map.get_meta("survival_layout",false))
		assert(GameManager.current_map_index==phase.x and GameManager.current_floor_index==phase.y)
		assert(wave._map_enemy_cap>=64 and not wave.is_map_spawn_suppressed())
		assert(not controller._boss_unlocked and controller._stairs==null)
		assert(controller._exploration_map_ui.map == GameManager.dungeon_map)
	print("SURVIVAL progression PASS: kill/time unlock, boss/loot quiet, all theme boundaries")
	# Probe the deepest horde cap using the actual timed loop, no manual enemy injection.
	wave._map_started_elapsed = GameManager.elapsed_seconds - 150.0
	var deep_start := GameManager.elapsed_seconds
	while GameManager.elapsed_seconds - deep_start < 13.0:
		await get_tree().physics_frame
		assert(wave._active_enemy_count() <= 128)
	assert(wave._active_enemy_count() >= 100, "Deep floor did not build a large horde")
	var samples: Array[float] = []
	for frame in 180:
		await get_tree().physics_frame
		samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
	samples.sort()
	print("SURVIVAL density PASS: living=%d physics_p95_ms=%.2f" % [wave._active_enemy_count(),samples[int(samples.size()*0.95)]])
	var cleanup := preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	cleanup.begin(0,"SURVIVAL_RUNTIME PASS")

func _close_modals() -> void:
	for attempt in 15:
		var handled := false
		for name in ["LevelUpSelect","ConceptSelect","ItemSelect"]:
			var ui := game.get_node(name) as CanvasLayer
			if not ui.visible: continue
			for button in ui.find_children("*","Button",true,false):
				if button.visible and not button.disabled:
					button.pressed.emit()
					if ui is LevelUpSelect: ui.confirm_selection()
					handled = true
					break
			if handled: break
		if not handled: return
		for frame in 3: await get_tree().process_frame

func _capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	get_tree().paused = true
	for frame in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/survival_%s.png" % label)
	if label != "horde":
		get_tree().paused = false
		return
	controller._exploration_map_ui.opened = true
	controller._exploration_map_ui.panel.show()
	controller._exploration_map_ui.panel.queue_redraw()
	for frame in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/survival_map.png")
	controller._exploration_map_ui.panel.hide()
	controller._exploration_map_ui.opened = false
	get_tree().paused = false
