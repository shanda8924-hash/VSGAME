extends Node
## game.tscnを通常のMain Runtimeとして起動したまま、3MAP→各Boss→Boss宝箱→
## 次MAP→Run Clearを実経路で短縮確認する。`-- --map-runtime-check`でのみ動く。

var failures: Array[String] = []
var controller: MapRunController
var boss_spawner: BossSpawner
var player: Player

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	controller = get_parent().get_node("MapRunController") as MapRunController
	boss_spawner = get_parent().get_node("BossSpawner") as BossSpawner
	player = get_parent().get_node("Player") as Player
	_run.call_deferred()

func _run() -> void:
	if "--map-gui-capture" in OS.get_cmdline_user_args():
		await _run_gui_capture()
		return
	if "--map-soak-check" in OS.get_cmdline_user_args():
		await _run_soak()
		return
	await _wait_frames(8)
	_expect(GameManager.map_mode_active, "通常起動がMAP modeではありません")
	_expect(GameManager.current_map_index == 1, "MAP 1から開始していません")
	_expect(get_tree().get_nodes_in_group("map_content").size() >= 7, "MAP配置物が不足しています")
	player.health_component.max_hp = 1000000.0
	player.health_component.current_hp = 1000000.0
	# XP Level Upが旧汎用強化ではなくAttribute 3択へ接続されることを確認。
	EventBus.player_leveled_up.emit(2)
	await _wait_frames(2)
	var fragment_select := get_parent().get_node("FragmentSelect") as FragmentSelect
	_expect(fragment_select.visible, "Level UpでAttribute選択が開きません")
	_press_first_enabled_button(fragment_select)
	await _wait_frames(2)
	_expect(not GameManager.get_active_element_ids().is_empty(), "Attribute選択がElement Stackへ反映されません")

	for expected_map in [1, 2, 3]:
		_expect(GameManager.current_map_index == expected_map, "MAP %dへ遷移していません" % expected_map)
		controller.debug_force_boss_ready()
		controller.debug_start_boss()
		await _wait_frames(3)
		_expect(is_instance_valid(boss_spawner.debug_get_current_boss()), "MAP %d Bossが生成されません" % expected_map)
		boss_spawner.debug_defeat_current_boss()
		await _wait_frames(5)
		await _close_visible_reward_modals()
		var boss_chest := _find_boss_chest()
		_expect(is_instance_valid(boss_chest), "MAP %d Boss宝箱が生成されません" % expected_map)
		if not is_instance_valid(boss_chest):
			break
		boss_chest._on_body_entered(player)
		_expect(boss_chest.interact(player), "MAP %d Boss宝箱をE相当で開けません" % expected_map)
		await _wait_frames(3)
		await _close_visible_reward_modals()
		if expected_map < 3:
			await _wait_until_map(expected_map + 1, 240)
			var profile: Dictionary = controller.debug_get_map_state().get("transition_profile", {})
			var max_slice := float(profile.get("max_slice_ms", 999.0))
			print("MAP_RUNTIME_TRANSITION map=%d total_ms=%.3f max_slice_ms=%.3f max_phase=%s frames=%d" % [expected_map + 1, float(profile.get("total_ms", 0.0)), max_slice, String(profile.get("max_phase", "")), int(profile.get("frames", 0))])
			_expect(max_slice < 50.0, "MAP transition frame sliceが50ms以上です: %.3fms" % max_slice)
		else:
			await _wait_frames(6)

	_expect(GameManager.run_state == GameManager.RunState.RESULT, "MAP 3後にRun Clearへ到達しません")
	if failures.is_empty():
		_finish_test(0, "MAP_EXPLORATION_RUNTIME_CHECK: PASS")
	else:
		for message in failures:
			push_error("MAP_EXPLORATION_RUNTIME_CHECK: %s" % message)
		_finish_test(1, "")

func _run_gui_capture() -> void:
	player.health_component.max_hp = 1000000.0
	player.health_component.current_hp = 1000000.0
	await _wait_frames(90)
	_capture_viewport("res://artifacts/map_exploration_start.png")
	controller.debug_force_boss_ready()
	if is_instance_valid(controller._boss_gate):
		player.global_position = controller._boss_gate.global_position + Vector2(-72, 0)
	await _wait_frames(20)
	_capture_viewport("res://artifacts/map_exploration_boss_gate.png")
	controller.debug_start_boss()
	await _wait_frames(25)
	_capture_viewport("res://artifacts/map_exploration_boss_fight.png")
	_finish_test(0, "MAP_EXPLORATION_GUI_CAPTURE: PASS")

func _capture_viewport(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	_expect(error == OK, "GUI capture保存失敗: %s" % path)

func _run_soak() -> void:
	await _wait_frames(8)
	player.health_component.max_hp = 1000000000.0
	player.health_component.current_hp = 1000000000.0
	Engine.time_scale = 20.0
	var run_started_at := GameManager.elapsed_seconds
	for expected_map in [1, 2, 3]:
		_expect(GameManager.current_map_index == expected_map, "Soak MAP %d開始に失敗" % expected_map)
		await _open_regular_chests()
		var required := float(controller._current_config.get("boss_unlock_seconds", 600.0))
		var local_started := GameManager.elapsed_seconds
		while GameManager.elapsed_seconds - local_started < required + 1.0:
			await _close_visible_reward_modals()
			await _wait_frames(4)
		var enemy_cap := int(controller._current_config.get("enemy_cap", 60))
		_expect(get_tree().get_nodes_in_group("enemies").size() <= enemy_cap + 3, "MAP %d enemy cap超過" % expected_map)
		controller.debug_force_boss_ready()
		controller.debug_start_boss()
		await _wait_frames(3)
		_expect(is_instance_valid(boss_spawner.debug_get_current_boss()), "Soak MAP %d Boss生成失敗" % expected_map)
		boss_spawner.debug_defeat_current_boss()
		await _wait_frames(5)
		await _close_visible_reward_modals()
		var boss_chest := _find_boss_chest()
		if is_instance_valid(boss_chest):
			boss_chest._on_body_entered(player)
			boss_chest.interact(player)
			await _wait_frames(3)
			await _close_visible_reward_modals()
		else:
			_expect(false, "Soak MAP %d Boss宝箱なし" % expected_map)
		if expected_map < 3:
			await _wait_until_map(expected_map + 1, 360)
		else:
			await _wait_frames(8)
	var logical_duration := GameManager.elapsed_seconds - run_started_at
	_expect(logical_duration >= 1800.0, "30分未満で終了しました: %.1f秒" % logical_duration)
	_expect(GameManager.run_state == GameManager.RunState.RESULT, "Soak完走後にResultへ到達しません")
	Engine.time_scale = 1.0
	if failures.is_empty():
		_finish_test(0, "MAP_EXPLORATION_SOAK_CHECK: PASS logical_seconds=%.1f" % logical_duration)
	else:
		for message in failures:
			push_error("MAP_EXPLORATION_SOAK_CHECK: %s" % message)
		_finish_test(1, "")

func _open_regular_chests() -> void:
	var chests: Array[TreasureChest] = []
	for node in get_tree().get_nodes_in_group("map_content"):
		if node is TreasureChest and not node.is_boss_chest and not node.is_opened:
			chests.append(node as TreasureChest)
	for chest in chests:
		chest._on_body_entered(player)
		chest.interact(player)
		await _wait_frames(2)
		await _close_visible_reward_modals()

func _close_visible_reward_modals() -> void:
	for _attempt in 12:
		var pressed := false
		for ui_name in ["FragmentSelect", "ConceptSelect", "LevelUpSelect", "ItemSelect"]:
			var ui := get_parent().get_node_or_null(ui_name) as CanvasLayer
			if ui and ui.visible:
				pressed = _press_first_enabled_button(ui) or pressed
		if not pressed:
			return
		await _wait_frames(2)

func _press_first_enabled_button(root: Node) -> bool:
	for node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button.visible and not button.disabled:
			button.pressed.emit()
			return true
	return false

func _find_boss_chest() -> TreasureChest:
	for node in get_tree().get_nodes_in_group("map_content"):
		if node is TreasureChest and node.is_boss_chest and not node.is_opened:
			return node as TreasureChest
	return null

func _wait_until_map(map_index: int, maximum_frames: int) -> void:
	for _frame in maximum_frames:
		if GameManager.current_map_index == map_index and not bool(controller.debug_get_map_state().get("transitioning", false)):
			return
		await get_tree().process_frame
	_expect(false, "MAP %d transitionがtimeoutしました" % map_index)

func _wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish_test(exit_code: int, success_message: String) -> void:
	var cleanup := preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	cleanup.begin(exit_code, success_message)
