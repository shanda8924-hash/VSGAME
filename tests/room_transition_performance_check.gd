extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")

var failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	seed(361315)
	GameManager.selected_character_id = "soldier"
	GameManager.debug_request_room_mode_for_next_game()
	var game := GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().physics_frame
	var controller := game.get_node("RoomRunController") as RoomRunController
	_check(await _wait_for(func(): return controller.state == RoomRunController.RoomState.COMBAT, 5.0), "ROOM 1 enters combat")
	await _measure_components(controller)
	for sample in [
		{"room": 2, "template": "wide"},
		{"room": 4, "template": "large"},
		{"room": 12, "template": "large"},
		{"room": 13, "template": "tall"},
		{"room": 24, "template": "large"},
		{"room": 25, "template": "pillars"},
		{"room": 36, "template": "large"},
	]:
		await _measure_transition(controller, int(sample["room"]), String(sample["template"]))
	var stress_result := await controller.debug_transition_stress(36)
	print("ROOM_TRANSITION_STRESS iterations=%d max_stage_slice_ms=%.3f nodes_start=%d nodes_end=%d" % [
		int(stress_result.get("iterations", 0)),
		float(stress_result.get("max_stage_slice_ms", 0.0)),
		int(stress_result.get("nodes_start", 0)),
		int(stress_result.get("nodes_end", 0)),
	])
	_check(int(stress_result.get("iterations", 0)) == 36, "36 ROOM transition stress completes")
	# Windows headless runnerには数msのscheduler揺れがあるため、同期35〜45msの
	# 半分前後まで分割できていることを25ms上限で回帰監視する。
	_check(float(stress_result.get("max_stage_slice_ms", INF)) < 25.0, "stage generation slice stays below 25 ms")
	print("ROOM_TRANSITION_PERFORMANCE_CHECK failures=%d" % failures.size())
	for failure in failures:
		push_error("ROOM_TRANSITION_PERFORMANCE_CHECK: %s" % failure)
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	AudioManager.stop_all(false)
	get_tree().quit(0 if failures.is_empty() else 1)

func _measure_components(controller: RoomRunController) -> void:
	controller.wave_spawner.clear_room_wave()
	await get_tree().process_frame
	var map_start := Time.get_ticks_usec()
	var map := RoomTemplateFactory.build_map("wide")
	var map_ms := float(Time.get_ticks_usec() - map_start) / 1000.0
	GameManager.dungeon_map = map
	var stage_start := Time.get_ticks_usec()
	controller.stage_environment.build_dungeon(map)
	var stage_ms := float(Time.get_ticks_usec() - stage_start) / 1000.0
	controller.player.global_position = map.grid_to_world(map.spawn_point)
	var wave_start := Time.get_ticks_usec()
	var spawned := controller.wave_spawner.start_room_wave(2, 10, 1.5, 0.25, 0.03)
	var wave_ms := float(Time.get_ticks_usec() - wave_start) / 1000.0
	print("ROOM_TRANSITION_COMPONENT_PROFILE map_ms=%.3f stage_ms=%.3f wave_ms=%.3f spawned=%d" % [map_ms, stage_ms, wave_ms, spawned])
	controller.wave_spawner.clear_room_wave()
	await get_tree().process_frame

func _measure_transition(controller: RoomRunController, room_number: int, template_id: String) -> void:
	controller.wave_spawner.clear_room_wave()
	controller.boss_spawner.clear_room_boss()
	await get_tree().process_frame
	await get_tree().process_frame
	# 本番ではAttribute/宝箱/Skill選択中にこの準備を開始する。0.9秒の装備整理時間より
	# 短い30 frameを与え、初回Sprite/Equipment resource loadを遷移計測から分離する。
	controller._prepare_next_room(room_number, template_id)
	for _frame in 30:
		await get_tree().process_frame
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects_before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var sync_start := Time.get_ticks_usec()
	controller._begin_room(room_number, "boss" if room_number % 4 == 0 else "combat", template_id)
	var synchronous_ms := float(Time.get_ticks_usec() - sync_start) / 1000.0
	var max_frame_ms := 0.0
	var max_frame_phase := "entry"
	var frame_count := 0
	var previous_tick := Time.get_ticks_usec()
	while controller.state != RoomRunController.RoomState.COMBAT:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - previous_tick) / 1000.0
		if frame_ms > max_frame_ms:
			max_frame_ms = frame_ms
			max_frame_phase = "stage" if not controller.stage_environment.visible else ("enemy_prepare" if controller.wave_spawner.get_room_alive_count() > 0 and not controller.wave_spawner._room_wave_prepared else "transition_wait")
		previous_tick = now
		frame_count += 1
		if frame_count > 300:
			failures.append("ROOM %d transition timed out" % room_number)
			return
	await get_tree().process_frame
	var combat_frame_ms := float(Time.get_ticks_usec() - previous_tick) / 1000.0
	if combat_frame_ms > max_frame_ms:
		max_frame_ms = combat_frame_ms
		max_frame_phase = "combat_first"
	var nodes_after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects_after := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var profile := controller.last_transition_profile
	print("ROOM_TRANSITION_PROFILE room=%d template=%s sync_ms=%.3f max_frame_ms=%.3f max_phase=%s combat_frame_ms=%.3f stage_max_slice_ms=%.3f stage_frames=%d prepare_total_ms=%.3f nodes_before=%d nodes_after=%d objects_before=%d objects_after=%d enemies=%d" % [
		room_number, template_id, synchronous_ms, max_frame_ms, max_frame_phase, combat_frame_ms,
		float(profile.get("stage_max_slice_ms", 0.0)), int(profile.get("stage_frames", 0)), float(profile.get("prepare_total_ms", 0.0)),
		nodes_before, nodes_after, objects_before, objects_after,
		controller.wave_spawner.get_room_alive_count(),
	])
	_check(synchronous_ms < 5.0, "ROOM %d synchronous transition entry stays below 5 ms" % room_number)
	_check(float(profile.get("stage_max_slice_ms", INF)) < 20.0, "ROOM %d stage slice stays below 20 ms" % room_number)

func _wait_for(condition: Callable, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() >= deadline:
			return false
		await get_tree().create_timer(0.04, true, false, true).timeout
	return true

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
