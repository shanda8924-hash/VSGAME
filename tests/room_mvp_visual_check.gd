extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")
const OUTPUT_DIR := "res://artifacts/room_mvp"

var _failures: Array[String] = []
var _game: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	GameManager.debug_request_room_mode_for_next_game()
	_game = GAME_SCENE.instantiate()
	add_child(_game)

	var controller := _game.get_node("RoomRunController")
	var wave := _game.get_node("WaveSpawner")
	var fragment_select := _game.get_node("FragmentSelect")
	var concept_select := _game.get_node("ConceptSelect")
	var item_select := _game.get_node("ItemSelect")
	var concept_board := _game.get_node("ConceptBoard")
	var concept_system := _game.get_node("ConceptSystem") as ConceptSystem
	var player := _game.get_node("Player")
	player.experience_component.exp_to_next_level = 1000000

	await _wait_until(func() -> bool: return controller.state == RoomRunController.RoomState.COMBAT, 5.0, "ROOM 1 did not enter COMBAT")
	var room_one_enemies := get_tree().get_nodes_in_group("enemies")
	if room_one_enemies.is_empty():
		_failures.append("ROOM 1 has no enemy for COMBO capture")
	else:
		var combo_target := room_one_enemies[0] as EnemyBasic
		for i in range(24):
			combo_target.health_component.apply_secondary_damage(1.0, CombatEventMeta.create_direct("visual_combo"))
	await _capture("01_room_combat_combo.png")

	wave.debug_defeat_room_wave()
	await _wait_until(func() -> bool: return fragment_select.visible, 5.0, "attribute reward did not open")
	await _capture("02_attribute_reward.png")
	var attribute_button := _first_enabled_button(fragment_select)
	if attribute_button == null:
		_failures.append("attribute reward has no enabled choice")
	else:
		attribute_button.emit_signal("pressed")
	await _wait_until(func() -> bool: return is_instance_valid(controller._active_chest), 5.0, "treasure chest did not spawn")
	await _capture("03_treasure_chest.png")

	var chest: Node = controller._active_chest
	if chest != null:
		chest.call("_on_body_entered", player)
		await get_tree().process_frame
		await _capture("03b_treasure_interaction_guide.png")
		chest.call("interact", player)
		await _wait_until(func() -> bool: return concept_select.visible or item_select.visible, 5.0, "treasure reward selection did not open")
		await _capture("04_treasure_reward.png")
		var reward_root: Node = concept_select if concept_select.visible else item_select
		var reward_button := _first_enabled_button(reward_root)
		if reward_button == null:
			_failures.append("treasure reward has no enabled choice")
		else:
			reward_button.emit_signal("pressed")

	await _wait_until(func() -> bool: return controller.current_room == 2 and controller.state == RoomRunController.RoomState.COMBAT, 6.0, "automatic ROOM 2 did not start")
	concept_system.acquire_concept("trigger_on_critical")
	concept_system.acquire_concept("skill_thunder_strike")
	concept_system.acquire_concept("modifier_chain")
	concept_system.equip_concept(0, "trigger", "trigger_on_critical")
	concept_system.equip_concept(0, "skill", "skill_thunder_strike")
	concept_system.equip_concept(0, "modifier", "modifier_chain")
	concept_board.show_board("コンセプト構築")
	await get_tree().process_frame
	await _capture("05_concept_board.png")
	concept_board.done_button.emit_signal("pressed")
	await get_tree().process_frame
	var vfx_targets := get_tree().get_nodes_in_group("enemies")
	if vfx_targets.is_empty():
		_failures.append("ROOM 2 has no enemy for Concept VFX")
	else:
		var vfx_target := vfx_targets[0] as EnemyBasic
		vfx_target.health_component.apply_secondary_damage(1.0, CombatEventMeta.create_direct("visual_concept", true))
		await get_tree().process_frame
		await _capture("06_concept_thunder_chain.png")
	AudioManager.stop_all(false)
	if is_instance_valid(_game):
		_game.queue_free()
	await get_tree().process_frame

	print("ROOM_MVP_VISUAL_CHECK failures=%d output=%s" % [_failures.size(), ProjectSettings.globalize_path(OUTPUT_DIR)])
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_DIR.path_join(file_name)))
	if error != OK:
		_failures.append("failed to save %s (%d)" % [file_name, error])


func _wait_until(predicate: Callable, timeout: float, failure: String) -> void:
	var elapsed := 0.0
	while elapsed < timeout:
		if predicate.call():
			return
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	_failures.append(failure)


func _find_button_by_meta(root: Node, key: StringName, expected: String) -> Button:
	for child in root.find_children("*", "Button", true, false):
		var value: Variant = child.get_meta(key, "")
		if value is Dictionary and String(value.get("type", "")) == expected:
			return child as Button
		if value is String and value == expected:
			return child as Button
	return null


func _first_concept_choice(root: Node) -> Button:
	for child in root.find_children("*", "Button", true, false):
		var button := child as Button
		if button != null and button.visible and button.disabled == false and button.has_meta("concept_id"):
			return button
	return null

func _first_enabled_button(root: Node) -> Button:
	for child in root.find_children("*", "Button", true, false):
		var button := child as Button
		if button != null and button.visible and not button.disabled:
			return button
	return null


func _close_modal_route(room_select: Node, concept_board: Node) -> void:
	if concept_board.visible:
		concept_board.done_button.emit_signal("pressed")
		await get_tree().process_frame
	if room_select.visible:
		var room_button := _find_button_by_meta(room_select, "room_choice", "attribute")
		if room_button != null:
			room_button.emit_signal("pressed")
			await get_tree().process_frame
