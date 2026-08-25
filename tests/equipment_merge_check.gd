extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")
const OUTPUT_DIR := "res://artifacts/equipment_merge_overhaul"

var failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run_checks()
	for failure in failures:
		push_error(failure)
	print("EQUIPMENT_MERGE_CHECK failures=%d" % failures.size())
	AudioManager.stop_all(false)
	await get_tree().create_timer(0.2, true, false, true).timeout
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _run_checks() -> void:
	GameManager.selected_character_id = "swordsman"
	var game := GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		var background := game.get_node_or_null(node_name)
		if background:
			background.process_mode = Node.PROCESS_MODE_DISABLED
	var player := game.get_node("Player") as Player
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	var component := player.equipment_component
	var drop_system := game.get_node("EquipmentDropSystem") as EquipmentDropSystem
	var merge_system := EquipmentMergeSystem.new()
	var screen := game.get_node("EquipmentScreen") as EquipmentScreen

	# Different names and slots may be merged as long as all three share a rarity.
	var uncommon_materials := _generate_distinct(drop_system, "uncommon", 3)
	for item in uncommon_materials:
		component.add_item(item)
	_check(uncommon_materials.size() == 3 and uncommon_materials[0].template_id != uncommon_materials[1].template_id, "three different Uncommon templates generated")
	var valid := merge_system.get_merge_validation(component, uncommon_materials)
	_check(bool(valid.get("valid", false)), "three different Uncommon items pass validation")
	_check(String(valid.get("output_rarity", "")) == "rare", "Uncommon preview advances to Rare")

	# The merge screen exposes explicit material slots and never adds per-item 1/3 badges.
	screen._open()
	screen._set_mode("merge")
	for item in uncommon_materials:
		screen._toggle_merge_material(item)
	await get_tree().process_frame
	_check(screen._merge_materials.size() == 3, "three inventory selections fill the three material slots")
	_check(not screen.merge_button.disabled and screen.merge_button.text == "合成する", "merge button activates only for a valid three-item set")
	_check("アンコモン" in screen._material_slot_buttons[0].text and uncommon_materials[0].display_name in screen._material_slot_buttons[0].text, "material slot shows rarity and equipment name")
	_check("レア" in screen.merge_preview.text and "×3" in screen.merge_preview.text, "preview shows rarity 3-to-1 progression")
	var has_old_badge := false
	for child in screen.inventory_list.get_children():
		if child is Button and ("/ 3" in child.text or "合成可能!" in child.text):
			has_old_badge = true
	_check(not has_old_badge, "inventory list has no legacy per-item 1/3 badge")

	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
		await get_tree().process_frame
		await get_tree().process_frame
		_capture_viewport("equipment_merge_three_slots.png")

	var inventory_before := component.inventory.size()
	screen._merge_selected()
	screen._merge_selected() # guarded while the first animation is active
	_check(screen._merge_in_progress, "merge animation starts after the atomic transaction")
	_check(component.inventory.size() == inventory_before - 2, "double click still performs one 3-to-1 transaction")
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(0.42, true, false, true).timeout
		_capture_viewport("equipment_merge_convergence.png")
		await get_tree().create_timer(1.55, true, false, true).timeout
	else:
		await get_tree().create_timer(1.9, true, false, true).timeout
	var rare_result := screen._merge_result
	_check(rare_result != null and rare_result.rarity == "rare", "Uncommon x3 creates one Rare result")
	_check(rare_result != null and _template_has_rarity(drop_system, rare_result.template_id, "rare"), "output comes from the existing Rare equipment pool")
	_check(screen._merge_materials.is_empty() and not screen._merge_in_progress, "material slots clear only after result reveal")
	_check(rare_result != null and rare_result.display_name in screen.merge_preview.text, "result card reveals output name, rarity and stats")
	_check(screen.equip_button.visible, "completed equipment can be equipped immediately")
	if DisplayServer.get_name() != "headless":
		_capture_viewport("equipment_merge_result.png")
	if rare_result:
		screen._equip_selected()
		_check(component.get_equipped(rare_result.slot) == rare_result, "result equip button uses the existing equipment path")
		component.unequip(rare_result.slot)

	# Rare -> Epic works with another three different templates and second animation can be skipped.
	var rare_materials := _generate_distinct(drop_system, "rare", 3)
	for item in rare_materials:
		component.add_item(item)
		screen._toggle_merge_material(item)
	_check(not screen.merge_button.disabled, "three Rare materials activate merge")
	screen._merge_selected()
	var skip_event := InputEventAction.new()
	skip_event.action = "ui_accept"
	skip_event.pressed = true
	screen._unhandled_input(skip_event)
	var epic_result := screen._merge_result
	_check(epic_result != null and epic_result.rarity == "epic", "Rare x3 creates Epic and second animation accepts skip")
	_check(not screen._merge_in_progress, "skip completes only presentation, not a second transaction")

	# Mixed rarity, equipped and locked materials fail without consuming anything.
	component.clear_all()
	var mixed_uncommon := _generate_distinct(drop_system, "uncommon", 2)
	var mixed_rare := _generate_distinct(drop_system, "rare", 1)
	var mixed: Array[EquipmentData] = [mixed_uncommon[0], mixed_uncommon[1], mixed_rare[0]]
	for item in mixed:
		component.add_item(item)
	var count_before_invalid := component.inventory.size()
	var mixed_validation := merge_system.get_merge_validation(component, mixed)
	_check(not bool(mixed_validation.get("valid", false)) and "レアリティを統一" in String(mixed_validation.get("reason", "")), "mixed rarity is rejected with a Japanese reason")
	_check(merge_system.merge_materials(component, mixed) == null and component.inventory.size() == count_before_invalid, "mixed-rarity failure consumes no material")
	screen._merge_materials.assign(mixed)
	screen._refresh()
	_check(screen.merge_button.disabled and "レアリティを統一" in screen.merge_notice.text, "merge screen explains mixed-rarity rejection in Japanese")
	var rare_button := _find_inventory_button(screen, mixed_rare[0].display_name)
	_check(rare_button != null and rare_button.modulate.a < 1.0, "non-matching rarity is dimmed after the first material selection")

	component.clear_all()
	var equipped_set := _generate_distinct(drop_system, "uncommon", 3)
	for item in equipped_set:
		component.add_item(item)
	component.equip(equipped_set[0])
	var equipped_validation := merge_system.get_merge_validation(component, equipped_set)
	_check(not bool(equipped_validation.get("valid", false)) and "装備中" in String(equipped_validation.get("reason", "")), "equipped material is rejected explicitly")
	_check(merge_system.merge_materials(component, equipped_set) == null and component.inventory.size() == 3, "equipped-material failure consumes nothing")
	screen._merge_materials.clear()
	screen._refresh()
	var equipped_button := _find_inventory_button(screen, equipped_set[0].display_name)
	_check(equipped_button != null and equipped_button.disabled and "装備中" in equipped_button.text, "equipped item is labeled and unavailable in merge inventory")
	component.unequip(equipped_set[0].slot)

	component.clear_all()
	var locked_set := _generate_distinct(drop_system, "uncommon", 3)
	for item in locked_set:
		component.add_item(item)
	locked_set[1].is_locked = true
	var locked_validation := merge_system.get_merge_validation(component, locked_set)
	_check(not bool(locked_validation.get("valid", false)) and "ロック中" in String(locked_validation.get("reason", "")), "locked material is rejected explicitly")
	_check(merge_system.merge_materials(component, locked_set) == null and component.inventory.size() == 3, "locked-material failure consumes nothing")
	screen._refresh()
	var locked_button := _find_inventory_button(screen, locked_set[1].display_name)
	_check(locked_button != null and locked_button.disabled and "ロック" in locked_button.text, "locked item is labeled and unavailable in merge inventory")

	locked_set[1].is_locked = false
	var missing_pool_system := EquipmentMergeSystem.new()
	missing_pool_system._templates.clear()
	var before_missing_pool := component.inventory.size()
	_check(missing_pool_system.merge_materials(component, locked_set) == null and component.inventory.size() == before_missing_pool, "missing output pool fails before consuming materials")

	# A second call with already-consumed references cannot consume the output.
	var one_result := merge_system.merge_materials(component, locked_set)
	var count_after_success := component.inventory.size()
	var duplicate_result := merge_system.merge_materials(component, locked_set)
	_check(one_result != null and duplicate_result == null, "already-consumed references cannot execute twice")
	_check(component.inventory.size() == count_after_success and one_result in component.inventory, "double merge guard preserves the first output")

	screen._close()
	component._on_run_ended(0.0, 0)
	_check(component.get_all_inventory().is_empty(), "restart/run reset clears merge output and equipment state")
	GameManager.end_run()
	await get_tree().process_frame
	game.queue_free()
	await get_tree().process_frame

func _generate_distinct(drop_system: EquipmentDropSystem, rarity: String, count: int) -> Array[EquipmentData]:
	var result: Array[EquipmentData] = []
	for template in drop_system.debug_get_templates():
		if String(template.get("rarity", "")) != rarity:
			continue
		var item := drop_system.debug_generate_equipment(String(template.get("id", "")), rarity)
		if item:
			result.append(item)
		if result.size() >= count:
			break
	return result

func _template_has_rarity(drop_system: EquipmentDropSystem, template_id: String, rarity: String) -> bool:
	for template in drop_system.debug_get_templates():
		if String(template.get("id", "")) == template_id:
			return String(template.get("rarity", "")) == rarity
	return false

func _find_inventory_button(screen: EquipmentScreen, item_name: String) -> Button:
	for child in screen.inventory_list.get_children():
		if child is Button and item_name in child.text:
			return child as Button
	return null

func _capture_viewport(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	if image:
		image.save_png("%s/%s" % [OUTPUT_DIR, file_name])

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
