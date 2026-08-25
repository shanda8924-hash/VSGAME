extends Node
## game.tscnを通常のMain Runtimeとして起動したまま、3MAP→各Boss→Boss宝箱→
## 次MAP→Run Clearを実経路で短縮確認する。`-- --map-runtime-check`でのみ動く。

var failures: Array[String] = []
var controller: MapRunController
var boss_spawner: BossSpawner
var player: Player
var _combat_target_id := 0
var _combat_ignored_target_id := 0
var _combat_last_target_distance := INF
var _combat_stuck_ticks := 0

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
	if "--map-combat-check" in OS.get_cmdline_user_args():
		await _run_combat_gate_check()
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

func _run_combat_gate_check() -> void:
	await _wait_frames(8)
	player.health_component.max_hp = 1000000000.0
	player.health_component.current_hp = 1000000000.0
	Engine.time_scale = 4.0
	await _open_regular_chests()
	var kill_requirement := int(controller._current_config.get("boss_kill_requirement", 420))
	var local_started := GameManager.elapsed_seconds
	var next_wall_status := Time.get_ticks_msec() + 10000
	# 無成長のSoldier通常攻撃だけでもMAP1想定上限（14分）内に条件へ届くことを確認する。
	while int(controller.debug_get_map_state().get("kills", 0)) < kill_requirement and GameManager.elapsed_seconds - local_started < 840.0:
		await _close_visible_reward_modals()
		_drive_soak_combat()
		await _wait_frames(4)
		if Time.get_ticks_msec() >= next_wall_status:
			next_wall_status += 10000
			print("MAP_EXPLORATION_COMBAT progress kills=%d/%d elapsed=%.1f scale=%.2f paused=%s modals=%d" % [int(controller.debug_get_map_state().get("kills", 0)), kill_requirement, GameManager.elapsed_seconds - local_started, Engine.time_scale, get_tree().paused, GameManager.active_modal_count])
	_release_soak_movement()
	var natural_kills := int(controller.debug_get_map_state().get("kills", 0))
	_expect(natural_kills >= kill_requirement, "MAP1の自然撃破数がBoss条件未達です: %d/%d" % [natural_kills, kill_requirement])
	Engine.time_scale = 1.0
	if failures.is_empty():
		_finish_test(0, "MAP_EXPLORATION_COMBAT_CHECK: PASS natural_kills=%d required=%d logical_seconds=%.1f" % [natural_kills, kill_requirement, GameManager.elapsed_seconds - local_started])
	else:
		for message in failures:
			push_error("MAP_EXPLORATION_COMBAT_CHECK: %s" % message)
		_finish_test(1, "")

func _run_soak() -> void:
	await _wait_frames(8)
	player.health_component.max_hp = 1000000000.0
	player.health_component.current_hp = 1000000000.0
	# 論理30分のLifecycleを短時間化する。自然Spawn/移動/攻撃のHitbox確認は同じ
	# Testを4倍でMAP1解放条件まで別途実測し、Soak本体は20倍で全3MAPを回す。
	Engine.time_scale = 20.0
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	player.set_movement_locked(true)
	var run_started_at := GameManager.elapsed_seconds
	for expected_map in [1, 2, 3]:
		# 直前MAPのBoss撃破Hit Stopは正常に1倍へ復帰するため、Test短縮倍率だけ
		# 各MAP開始時に張り直す。
		Engine.time_scale = 20.0
		_expect(GameManager.current_map_index == expected_map, "Soak MAP %d開始に失敗" % expected_map)
		await _open_regular_chests()
		var required := float(controller._current_config.get("target_duration_seconds", 660.0))
		var local_started := GameManager.elapsed_seconds
		var next_combat_status := local_started + 20.0
		while GameManager.elapsed_seconds - local_started < required + 1.0:
			await _close_visible_reward_modals()
			_resolve_soak_elites()
			await _wait_frames(4)
			if GameManager.elapsed_seconds >= next_combat_status:
				next_combat_status += 120.0
				_print_soak_combat_status(expected_map)
		_release_soak_movement()
		var enemy_cap := int(controller._current_config.get("enemy_cap", 60))
		var kill_requirement := int(controller._current_config.get("boss_kill_requirement", 60))
		var natural_kills := int(controller.debug_get_map_state().get("kills", 0))
		var living_enemies := get_tree().get_nodes_in_group("enemies").size()
		print("MAP_EXPLORATION_SOAK map=%d natural_kills=%d required=%d living=%d" % [expected_map, natural_kills, kill_requirement, living_enemies])
		_expect(living_enemies > 0, "MAP %dで自然Spawnが動いていません" % expected_map)
		# 通常上限外に、部屋Elite最大2×複数Triggerと巡回Eliteが一時共存し得る。
		_expect(living_enemies <= enemy_cap + 6, "MAP %d enemy cap超過" % expected_map)
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
	_release_soak_movement()
	var chests: Array[TreasureChest] = []
	for node in get_tree().get_nodes_in_group("map_content"):
		if node is TreasureChest and not node.is_boss_chest and not node.is_opened:
			chests.append(node as TreasureChest)
	for chest in chests:
		chest._on_body_entered(player)
		chest.interact(player)
		await _wait_frames(2)
		await _close_visible_reward_modals()

func _drive_soak_combat() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies").filter(func(enemy):
		return is_instance_valid(enemy) and enemy.get_node_or_null("HealthComponent") != null and (enemy.get_node("HealthComponent") as HealthComponent).current_hp > 0.0
	)
	if enemies.is_empty():
		_release_soak_movement()
		return
	var nearest: Node2D = null
	var nearest_distance := INF
	for enemy_variant in enemies:
		var enemy := enemy_variant as Node2D
		if enemy.get_instance_id() == _combat_target_id:
			nearest = enemy
			nearest_distance = player.global_position.distance_to(enemy.global_position)
			break
	if nearest == null:
		for enemy_variant in enemies:
			var enemy := enemy_variant as Node2D
			if enemy.get_instance_id() == _combat_ignored_target_id and enemies.size() > 1:
				continue
			var distance := player.global_position.distance_to(enemy.global_position)
			if distance < nearest_distance:
				nearest = enemy
				nearest_distance = distance
		_combat_target_id = nearest.get_instance_id()
		_combat_last_target_distance = INF
		_combat_stuck_ticks = 0
		_combat_ignored_target_id = 0
	if nearest_distance > 58.0 and nearest_distance >= _combat_last_target_distance - 1.5:
		_combat_stuck_ticks += 1
	else:
		_combat_stuck_ticks = 0
	_combat_last_target_distance = nearest_distance
	if _combat_stuck_ticks >= 90:
		_combat_ignored_target_id = _combat_target_id
		_combat_target_id = 0
		_combat_last_target_distance = INF
		_combat_stuck_ticks = 0
		_set_soak_movement(Vector2.ZERO)
		return
	var direction := (nearest.global_position - player.global_position).normalized() if nearest_distance > 42.0 else Vector2.ZERO
	_set_soak_movement(direction)

func _resolve_soak_elites() -> void:
	# 20倍速では0.08秒近接Hitboxが物理1Frame未満になるため、Elite Encounterの
	# Cleanup/Signal/確定装備経路だけはDebug damageで完了させる。
	for enemy_variant in get_tree().get_nodes_in_group("elite_enemies"):
		var enemy := enemy_variant as EnemyBasic
		if enemy == null or not is_instance_valid(enemy) or enemy.enemy_data is BossData:
			continue
		enemy.health_component.current_hp = minf(enemy.health_component.current_hp, 1.0)
		enemy.health_component.apply_secondary_damage(99999999.0, CombatEventMeta.create_secondary("map_soak_elite_clear", [], false))

func _print_soak_combat_status(map_index: int) -> void:
	var nearest_distance := INF
	var living := 0
	for enemy_variant in get_tree().get_nodes_in_group("enemies"):
		var enemy := enemy_variant as Node2D
		if not is_instance_valid(enemy):
			continue
		var health := enemy.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.current_hp <= 0.0:
			continue
		living += 1
		nearest_distance = minf(nearest_distance, player.global_position.distance_to(enemy.global_position))
	print("MAP_EXPLORATION_SOAK combat map=%d kills=%d living=%d nearest=%.1f player=%s room_mode=%s elite=%d boss=%s floor=%d timer=%.2f state=%d" % [map_index, int(controller.debug_get_map_state().get("kills", 0)), living, nearest_distance, player.global_position, controller.wave_spawner._room_mode_enabled, controller.wave_spawner._active_elite_rooms, controller.wave_spawner._boss_fight_active, controller.wave_spawner._floor_cells.size(), controller.wave_spawner._timer, GameManager.run_state])

func _set_soak_movement(direction: Vector2) -> void:
	if direction.x < -0.18: Input.action_press("ui_left", -direction.x)
	else: Input.action_release("ui_left")
	if direction.x > 0.18: Input.action_press("ui_right", direction.x)
	else: Input.action_release("ui_right")
	if direction.y < -0.18: Input.action_press("ui_up", -direction.y)
	else: Input.action_release("ui_up")
	if direction.y > 0.18: Input.action_press("ui_down", direction.y)
	else: Input.action_release("ui_down")

func _release_soak_movement() -> void:
	for action in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		Input.action_release(action)

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
