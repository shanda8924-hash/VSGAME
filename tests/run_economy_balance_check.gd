extends Node
## 実Game Runtimeの自然Spawn・Player自動攻撃・実Enemy死亡経路でMAP1/2収支を測る。

var controller: MapRunController
var boss_spawner: BossSpawner
var player: Player
var _income_by_source: Dictionary = {}
var _failures: Array[String] = []
var _target_id := 0
var _stuck_frames := 0
var _last_distance := INF

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	controller = get_parent().get_node("MapRunController") as MapRunController
	boss_spawner = get_parent().get_node("BossSpawner") as BossSpawner
	player = get_parent().get_node("Player") as Player
	EventBus.run_gold_changed.connect(_on_run_gold_changed)
	_run.call_deferred()

func _on_run_gold_changed(_current_gold: int, delta: int, source: String) -> void:
	if delta > 0:
		_income_by_source[source] = int(_income_by_source.get(source, 0)) + delta

func _run() -> void:
	await _wait_frames(8)
	player.health_component.max_hp = 1000000000.0
	player.health_component.current_hp = 1000000000.0
	Engine.time_scale = 4.0
	var concept := get_parent().get_node("ConceptSystem") as ConceptSystem
	concept.acquire_completed_skill("thunderlord_descent")
	concept.set_active(true)

	for map_index in [1, 2]:
		# Boss撃破Hit Stopは正常終了時に1倍へ戻るため、検証短縮倍率をMAPごとに張り直す。
		Engine.time_scale = 4.0
		_expect(GameManager.current_map_index == map_index, "MAP %d開始に失敗" % map_index)
		await _clear_all_elite_rooms()
		await _fight_until_boss_ready(map_index)
		controller.debug_start_boss()
		await _wait_frames(4)
		_expect(is_instance_valid(boss_spawner.debug_get_current_boss()), "MAP %d Boss生成失敗" % map_index)
		boss_spawner.debug_defeat_current_boss()
		await _wait_frames(8)
		await _close_visible_reward_modals()
		_print_snapshot(map_index)
		if map_index == 1:
			var chest := _find_boss_chest()
			_expect(is_instance_valid(chest), "MAP1 Boss宝箱がありません")
			if is_instance_valid(chest):
				chest._on_body_entered(player)
				chest.interact(player)
				await _wait_frames(4)
				await _close_visible_reward_modals()
			await _wait_until_map(2, 480)

	_release_movement()
	Engine.time_scale = 1.0
	if _failures.is_empty():
		_finish(0, "RUN_ECONOMY_BALANCE_CHECK PASS")
	else:
		for failure in _failures:
			push_error("RUN_ECONOMY_BALANCE_CHECK: %s" % failure)
		_finish(1, "")

func _clear_all_elite_rooms() -> void:
	var room_indices := GameManager.dungeon_map.elite_room_indices.duplicate()
	for room_index in room_indices:
		controller.elite_room_manager._on_body_entered(player, int(room_index))
		await _wait_frames(4)
		for enemy_variant in get_tree().get_nodes_in_group("elite_enemies"):
			var enemy := enemy_variant as EnemyBasic
			if enemy == null or not is_instance_valid(enemy) or enemy.enemy_data is BossData:
				continue
			enemy.health_component.current_hp = minf(enemy.health_component.current_hp, 1.0)
			enemy.health_component.apply_secondary_damage(99999999.0, CombatEventMeta.create_secondary("economy_balance_elite", [], false))
		await _wait_frames(5)

func _fight_until_boss_ready(map_index: int) -> void:
	var required := int(controller._current_config.get("boss_kill_requirement", 420))
	var started := GameManager.elapsed_seconds
	var next_report := Time.get_ticks_msec() + 15000
	while not bool(controller.debug_get_map_state().get("boss_unlocked", false)) and GameManager.elapsed_seconds - started < 1000.0:
		await _close_visible_reward_modals()
		_drive_player_to_nearest_enemy()
		await _wait_frames(4)
		if Time.get_ticks_msec() >= next_report:
			next_report += 15000
			print("RUN_ECONOMY_PROGRESS map=%d kills=%d/%d gold=%d logical=%.1f" % [map_index, int(controller.debug_get_map_state().get("kills", 0)), required, GameManager.run_gold, GameManager.elapsed_seconds - started])
	_release_movement()
	_expect(bool(controller.debug_get_map_state().get("boss_unlocked", false)), "MAP %d Boss解放条件に到達しません" % map_index)

func _drive_player_to_nearest_enemy() -> void:
	var nearest: Node2D = null
	var nearest_distance := INF
	for enemy_variant in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy_variant) or not (enemy_variant is Node2D):
			continue
		var enemy := enemy_variant as Node2D
		var health := enemy.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.current_hp <= 0.0:
			continue
		var distance := player.global_position.distance_to(enemy.global_position)
		if enemy.get_instance_id() == _target_id:
			nearest = enemy
			nearest_distance = distance
			break
		if distance < nearest_distance:
			nearest = enemy
			nearest_distance = distance
	if nearest == null:
		_target_id = 0
		_release_movement()
		return
	if nearest.get_instance_id() != _target_id:
		_target_id = nearest.get_instance_id()
		_stuck_frames = 0
		_last_distance = INF
	if nearest_distance >= _last_distance - 1.0:
		_stuck_frames += 4
	else:
		_stuck_frames = 0
	_last_distance = nearest_distance
	if _stuck_frames >= 180 and nearest_distance > 90.0:
		player.global_position = nearest.global_position + Vector2(54.0, 0.0)
		_stuck_frames = 0
		_last_distance = INF
		return
	_set_movement((nearest.global_position - player.global_position).normalized() if nearest_distance > 44.0 else Vector2.ZERO)

func _print_snapshot(map_index: int) -> void:
	var normal := int(_income_by_source.get("enemy_kill", 0))
	var elite_kill := int(_income_by_source.get("elite_kill", 0))
	var elite_room := int(_income_by_source.get("elite_room_clear", 0))
	var surge := int(_income_by_source.get("surge_clear", 0))
	var boss := int(_income_by_source.get("boss_kill", 0)) + int(_income_by_source.get("boss_clear", 0))
	var summed := normal + elite_kill + elite_room + surge + boss
	_expect(summed == GameManager.run_gold, "MAP%d 内訳合計%dと残高%dが不一致" % [map_index, summed, GameManager.run_gold])
	print("RUN_ECONOMY_SNAPSHOT map=%d total=%d normal=%d elite_kill=%d elite_room=%d surge=%d boss=%d kills=%d surge_count=%d" % [
		map_index, GameManager.run_gold, normal, elite_kill, elite_room, surge, boss,
		GameManager.kill_count, int(controller.debug_get_map_state().get("surge_index", 0)),
	])

func _close_visible_reward_modals() -> void:
	for _attempt in 12:
		var pressed := false
		var shop := get_parent().get_node_or_null("ShopScreen") as ShopScreen
		if shop and shop.visible:
			shop.debug_close_shop()
			pressed = true
		for ui_name in ["ConceptSelect", "LevelUpSelect", "ItemSelect"]:
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
			if root is LevelUpSelect: root.confirm_selection()
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
	_expect(false, "MAP %d transition timeout" % map_index)

func _set_movement(direction: Vector2) -> void:
	if direction.x < -0.18: Input.action_press("ui_left", -direction.x)
	else: Input.action_release("ui_left")
	if direction.x > 0.18: Input.action_press("ui_right", direction.x)
	else: Input.action_release("ui_right")
	if direction.y < -0.18: Input.action_press("ui_up", -direction.y)
	else: Input.action_release("ui_up")
	if direction.y > 0.18: Input.action_press("ui_down", direction.y)
	else: Input.action_release("ui_down")

func _release_movement() -> void:
	for action in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		Input.action_release(action)

func _wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish(exit_code: int, message: String) -> void:
	var cleanup := preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	cleanup.begin(exit_code, message)
