extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")

var failures: Array[String] = []
var game: Node2D
var controller: RoomRunController
var wave: WaveSpawner
var combo: ComboSystem
var player: Player

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	seed(260814)
	GameManager.debug_request_room_mode_for_next_game()
	game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().physics_frame
	controller = game.get_node("RoomRunController") as RoomRunController
	wave = game.get_node("WaveSpawner") as WaveSpawner
	combo = game.get_node("ComboSystem") as ComboSystem
	player = game.get_node("Player") as Player
	player.experience_component.exp_to_next_level = 999999
	var interact_events := InputMap.action_get_events("interact")
	_check(InputMap.has_action("interact"), "shared interact InputMap action exists")
	_check(interact_events.any(func(event): return event is InputEventKey and event.physical_keycode == KEY_E), "interact is bound to physical E")
	_check(interact_events.any(func(event): return event is InputEventJoypadButton and event.button_index == JOY_BUTTON_X), "interact is bound to non-conflicting controller X")

	_check(await _wait_for(func(): return controller.state == RoomRunController.RoomState.COMBAT, 4.0), "ROOM 1 enters COMBAT")
	_check(GameManager.room_mode_active, "normal runtime enables ROOM mode")
	_check(GameManager.dungeon_map != null and GameManager.dungeon_map.rooms.size() == 1 and GameManager.dungeon_map.width < 70, "small one-room map replaces the long dungeon")
	_check(game.get_node("BossSpawner").process_mode == Node.PROCESS_MODE_DISABLED, "independent Boss progression is disabled")
	_check(game.get_node("EliteRoomManager").process_mode == Node.PROCESS_MODE_DISABLED, "independent Elite progression is disabled")
	_check(wave.get_room_alive_count() > 0, "ROOM 1 finite enemy wave spawned")

	combo.configure_timeout(0.15)
	var combo_target := get_tree().get_nodes_in_group("enemies")[0] as EnemyBasic
	combo_target.health_component.apply_secondary_damage(1.0, CombatEventMeta.create_direct("test_direct"))
	combo_target.health_component.apply_secondary_damage(1.0, CombatEventMeta.create_direct("test_direct"))
	combo_target.health_component.apply_secondary_damage(1.0, CombatEventMeta.create_secondary("element_lightning:chain", ["element_lightning"]))
	_check(combo.combo == 3, "physical and chain damage add one COMBO per confirmed enemy damage")
	EventBus.damage_dealt.emit(99.0, player.global_position, false)
	_check(combo.combo == 3, "generic/player damage notification does not add COMBO")
	await get_tree().create_timer(0.22, true, false, true).timeout
	_check(combo.combo == 0, "COMBO resets after the configurable no-hit timeout")
	combo.configure_timeout(2.5)

	var skill_snapshot: Dictionary = {}
	var treasure_count := 0
	var skill_level_ups := 0
	var defeated_boss_ids: Array[String] = []
	for expected_room in range(1, controller.total_rooms + 1):
		_check(await _wait_for(func(): return controller.state == RoomRunController.RoomState.COMBAT and controller.current_room == expected_room, 5.0), "ROOM %d starts" % expected_room)
		var is_boss_room := expected_room % 4 == 0
		if is_boss_room:
			var boss := controller.boss_spawner.debug_get_current_boss() as EnemyBasic
			_check(wave.get_room_alive_count() == 0, "BOSS ROOM %d does not start a normal wave" % expected_room)
			_check(is_instance_valid(boss) and boss.enemy_data is BossData, "BOSS ROOM %d starts one existing BossData encounter" % expected_room)
			if is_instance_valid(boss):
				defeated_boss_ids.append(boss.enemy_data.id)
				_check(boss.status_effect_component.duration_multiplier < 1.0, "BOSS ROOM %d shortens status duration without immunity" % expected_room)
			controller.boss_spawner.debug_defeat_current_boss()
		else:
			_check(wave.get_room_alive_count() > 0, "ROOM %d has a finite tracked wave" % expected_room)
			wave.debug_defeat_room_wave()
		if expected_room >= controller.total_rooms:
			_check(await _wait_for(func(): return controller.state == RoomRunController.RoomState.RUN_CLEAR, 5.0), "FINAL ROOM reaches RUN CLEAR")
			break

		_check(await _wait_for(func(): return controller.fragment_select.visible, 3.0), "every ROOM opens the Attribute reward modal")
		_check(await _press_required_element_reward(), "Attribute reward advances the intended two-element build with keyboard confirm")
		_check(await _wait_for(func(): return is_instance_valid(controller._active_chest), 3.0), "every ROOM spawns a treasure chest after Attribute selection")
		if is_instance_valid(controller._active_chest):
			var chest := controller._active_chest
			_check(chest.is_boss_chest == is_boss_room, "BOSS rooms use the dedicated boss chest and normal rooms do not")
			_check(chest.rarity in ["normal", "rare", "legendary"], "treasure chest has a supported rarity")
			_check(not chest.label.text.contains("宝箱を開く"), "interaction guide stays hidden outside range")
			_check(not chest.interact(player) and not chest.is_opened, "treasure cannot be opened from outside its interaction range")
			var opened_events := [0]
			chest.opened.connect(func(_rarity): opened_events[0] += 1)
			_check(not get_tree().paused and player.process_mode != Node.PROCESS_MODE_DISABLED, "Player input remains active during treasure reward phase")
			chest.global_position = player.global_position + Vector2(170.0, 0.0)
			var movement_start := player.global_position
			Input.action_press("ui_right")
			var reached_chest := await _wait_for(func(): return chest.label.text.contains("【E】宝箱を開く"), 1.5)
			Input.action_release("ui_right")
			_check(player.global_position.x > movement_start.x and reached_chest, "keyboard movement reaches treasure interaction range")
			_check(chest.label.text.contains("【E】宝箱を開く"), "treasure shows the Japanese E guide only inside range")
			Input.action_press("interact")
			player._process(0.0)
			Input.action_release("interact")
			_check(chest.is_opened and opened_events[0] == 1, "E interact opens treasure exactly once")
			_check(not chest.interact(player) and opened_events[0] == 1, "repeated interaction cannot duplicate treasure reward")
		_check(await _wait_for(func(): return controller.concept_select.visible or controller.item_select.visible, 3.0), "treasure opens the skill or capped fallback reward modal")
		var before_levels := controller.concept_system.completed_skill_levels.duplicate(true)
		var reward_pressed := false
		if controller.concept_select.visible:
			reward_pressed = await _press_completed_skill_reward()
			_check(reward_pressed, "completed Japanese skill can be acquired with keyboard confirm")
		else:
			reward_pressed = await _press_first_enabled(controller.item_select.grid_container)
			_check(reward_pressed, "capped skill inventory uses the existing fallback reward")
		await get_tree().process_frame
		treasure_count += 1
		for skill_id in controller.concept_system.completed_skill_levels:
			if int(before_levels.get(skill_id, 0)) > 0 and int(controller.concept_system.completed_skill_levels[skill_id]) > int(before_levels[skill_id]):
				skill_level_ups += 1
		skill_snapshot = controller.concept_system.completed_skill_levels.duplicate(true)
		_check(not controller.concept_board.visible, "normal player is not sent to the Concept Board")

		_check(not controller.room_select.visible, "meaningless next-ROOM choice remains hidden")
		_check(await _wait_for(func(): return controller.current_room == expected_room + 1 and controller.state == RoomRunController.RoomState.COMBAT, 6.0), "reward completion advances automatically to ROOM %d" % (expected_room + 1))
		if not skill_snapshot.is_empty():
			if controller.concept_system.completed_skill_levels != skill_snapshot:
				print("ROOM_SKILL_PERSISTENCE room=%d before=%s after=%s" % [expected_room, skill_snapshot, controller.concept_system.completed_skill_levels])
			_check(controller.concept_system.completed_skill_levels == skill_snapshot, "completed skills persist across ROOM transition")

	_check(GameManager.active_fusion_id != "", "repeated Attribute rewards reach two Lv3 elements and form Fusion")
	_check(controller.concept_system.completed_skill_levels.size() <= ConceptSystem.MAX_COMPLETED_SKILLS, "completed skill ownership respects the six-skill cap")
	_check(treasure_count == controller.total_rooms - 1, "every non-final ROOM grants one treasure skill reward")
	_check(defeated_boss_ids.size() == 9 and defeated_boss_ids.duplicate().reduce(func(unique, id): return unique if id in unique else unique + [id], []).size() == 9, "ROOM 4 through 36 use nine non-duplicate bosses")
	_check(get_tree().get_nodes_in_group("boss_projectiles").is_empty() and get_tree().get_nodes_in_group("boss_attack_transient").is_empty() and get_tree().get_nodes_in_group("boss_summons").is_empty(), "boss death cleanup releases boss projectiles, warnings and summons")
	_check(skill_level_ups > 0, "duplicate completed skill rewards produce at least one level-up")
	var has_cross_skill := controller.concept_system.completed_skill_levels.keys().any(func(skill_id): return (controller.concept_system.get_completed_skill_definition(String(skill_id)).get("required_elements", []) as Array).size() >= 2)
	_check(has_cross_skill, "a compatible cross-attribute completed skill is acquired during the run")
	var result_screen := game.get_node("ResultScreen") as ResultScreen
	_check(result_screen.visible and result_screen.title_label.text == "クリア！", "Japanese clear result UI is displayed")
	_check(wave.get_room_alive_count() == 0, "no ROOM enemies remain after RUN CLEAR")
	_check(get_tree().get_nodes_in_group("ground_equipment").size() <= 1, "uncollected equipment is cleaned between ROOMs; only Final Boss drop may remain")
	_check(combo.combo == 0, "COMBO does not remain after ROOM/RUN transition")
	var small_hits := _average_baseline_hits(["bat", "slime", "skeleton_archer"], 1)
	var standard_hits := _average_baseline_hits(["armored_skeleton", "orc_rider", "armored_orc"], 1)
	var large_hits := _average_baseline_hits(["greatsword_skeleton", "elite_orc", "werebear"], 1)
	_check(small_hits >= 3.0 and small_hits <= 5.0, "ROOM 1 small enemies require the target 3-5 baseline hits")
	_check(standard_hits >= 7.0 and standard_hits <= 10.0, "ROOM 1 standard enemies require the target 7-10 baseline hits")
	_check(large_hits >= 12.0 and large_hits <= 18.0, "ROOM 1 large enemies require the target 12-18 baseline hits")
	print("ROOM_HIT_PROFILE damage=14 room1_small=%.2f room1_standard=%.2f room1_large=%.2f standard_r1=%.1f standard_r5=%.1f standard_r9=%.1f standard_r11=%.1f" % [small_hits, standard_hits, large_hits, _baseline_hits("armored_skeleton", 1), _baseline_hits("armored_skeleton", 5), _baseline_hits("armored_skeleton", 9), _baseline_hits("armored_skeleton", 11)])
	get_tree().paused = false
	print("ROOM_COMBO_MVP_CHECK failures=%d rooms=%d fusion=%s kills=%d" % [failures.size(), controller.current_room, GameManager.active_fusion_id, GameManager.kill_count])
	for failure in failures:
		push_error("ROOM_COMBO_MVP_CHECK: %s" % failure)
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	AudioManager.stop_all(false)
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(1 if not failures.is_empty() else 0)

func _press_required_element_reward() -> bool:
	if GameManager.active_fusion_id != "":
		return await _press_first_enabled(controller.fragment_select.grid_container)
	var owned := GameManager.get_active_element_ids()
	var target_id := ""
	if owned.is_empty():
		target_id = "new"
	elif owned.size() == 1:
		target_id = owned[0] if GameManager.get_element_stack(owned[0]) < 3 else "new"
	else:
		for element_id in owned:
			if GameManager.get_element_stack(element_id) < 3:
				target_id = element_id
				break
	for child in controller.fragment_select.grid_container.get_children():
		if not child is Button or child.is_queued_for_deletion() or child.disabled:
			continue
		var choice: Dictionary = child.get_meta("reward_choice", {})
		if choice.get("kind", "") != "element":
			continue
		var element_id := String(choice.get("element_id", ""))
		var is_core_second := element_id in ["element_fire", "element_ice", "element_lightning"] and element_id not in owned
		if target_id == "new" and is_core_second or element_id == target_id:
			return await _press_button_with_keyboard(child)
	if target_id == "new":
		for child in controller.fragment_select.grid_container.get_children():
			if child is Button and not child.disabled:
				var fallback_choice: Dictionary = child.get_meta("reward_choice", {})
				if fallback_choice.get("kind", "") == "element" and String(fallback_choice.get("element_id", "")) not in owned:
					return await _press_button_with_keyboard(child)
	return false

func _press_room_choice(room_type: String) -> bool:
	for child in controller.room_select.choices.get_children():
		if not child is Button or child.is_queued_for_deletion():
			continue
		var choice: Dictionary = child.get_meta("room_choice", {})
		if choice.get("type", "") == room_type:
			return await _press_button_with_keyboard(child)
	return false

func _press_first_enabled(container: Control) -> bool:
	for child in container.get_children():
		if child is Button and not child.disabled and not child.is_queued_for_deletion():
			child.emit_signal("pressed")
			return true
	return false

func _press_concept_type(concept_type: String) -> bool:
	var fallback: Button = null
	for child in controller.concept_select.choices.get_children():
		if not child is Button or child.disabled or child.is_queued_for_deletion():
			continue
		if fallback == null:
			fallback = child as Button
		var concept_id := String(child.get_meta("concept_id", ""))
		var data := DataLoader.get_concept(concept_id)
		if data and data.concept_type == concept_type:
			return await _press_button_with_keyboard(child)
	# Smart Weight raises missing categories without forcing them. A valid reward
	# route must still be playable when the preferred category is not offered.
	return await _press_button_with_keyboard(fallback) if fallback else false

func _press_completed_skill_reward() -> bool:
	var fallback: Button = null
	var upgrade: Button = null
	for child in controller.concept_select.choices.get_children():
		if not child is Button or child.disabled or child.is_queued_for_deletion():
			continue
		if fallback == null:
			fallback = child as Button
		var skill_id := String(child.get_meta("completed_skill_id", ""))
		var required: Array = controller.concept_system.get_completed_skill_definition(skill_id).get("required_elements", [])
		if required.size() >= 2:
			return await _press_button_with_keyboard(child)
		if controller.concept_system.get_completed_skill_level(skill_id) > 0:
			upgrade = child as Button
	var chosen := upgrade if upgrade else fallback
	return await _press_button_with_keyboard(chosen) if chosen else false

func _press_button_with_keyboard(button: Button) -> bool:
	if button == null or button.disabled or not button.visible:
		return false
	# UI側の初期grab_focus.call_deferred()を先に完了させてから、方向入力後の対象Focusを再現する。
	await get_tree().process_frame
	button.grab_focus()
	var focused := get_viewport().gui_get_focus_owner() == button
	var press := InputEventAction.new()
	press.action = &"ui_accept"
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	var release := InputEventAction.new()
	release.action = &"ui_accept"
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().process_frame
	return focused

func _upgrade_snapshot() -> Dictionary:
	return {
		"damage": player.upgrades_component.damage_multiplier,
		"speed": player.upgrades_component.move_speed_multiplier,
		"hp": player.health_component.max_hp,
		"crit": player.upgrades_component.crit_rate_bonus,
		"range": player.upgrades_component.attack_range_multiplier,
		"lifesteal": player.upgrades_component.lifesteal_percent,
	}

func _wait_for(condition: Callable, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() >= deadline:
			return false
		await get_tree().create_timer(0.05, true, false, true).timeout
	return true

func _average_baseline_hits(enemy_ids: Array[String], room_number: int) -> float:
	var total := 0.0
	var count := 0
	for enemy_id in enemy_ids:
		if not DataLoader.enemies.has(enemy_id):
			continue
		total += _baseline_hits(enemy_id, room_number)
		count += 1
	return total / maxf(float(count), 1.0)

func _baseline_hits(enemy_id: String, room_number: int) -> float:
	var data: EnemyData = DataLoader.enemies.get(enemy_id)
	if data == null:
		return 0.0
	return float(ceili(data.max_hp * controller._room_value("enemy_hp_multipliers", room_number, 1.0) / 14.0))

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
