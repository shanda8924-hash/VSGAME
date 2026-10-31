extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")
const OUTPUT_DIR := "res://artifacts/equipment_merge_overhaul"

var failures: Array[String] = []
var _expected_close := false
var _phase := "startup"

func _ready() -> void:
	SaveManager.begin_ephemeral_session() # End-run UI must not persist fixture progress.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Only the automatic fixture declines OS focus. Input.parse_input_event still tests GUI input.
	get_window().unfocusable = true
	print("EQUIPMENT_INPUT_ISOLATION enabled")
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
	# This fixture verifies successful transactions; live failure rates remain unchanged.
	for rarity in ["uncommon", "rare", "epic", "legendary"]:
		merge_system._drop_table["merge_rules"][rarity]["success_rate"] = 1.0
		screen._merge_system._drop_table["merge_rules"][rarity]["success_rate"] = 1.0
	screen.closed.connect(func():
		if not _expected_close:
			var close_actions: Array[String] = []
			for action: String in ["character_screen", "equipment_menu", "ui_cancel"]:
				if Input.is_action_just_pressed(action):
					close_actions.append(action)
			print("EQUIPMENT_UNEXPECTED_CLOSE phase=%s actions=%s stack=%s" % [_phase, close_actions, get_stack()])
			_check(false, "equipment screen closed unexpectedly during %s" % _phase)
	)
	_phase = "merge checks"

	# Different names and slots may be merged as long as all three share a rarity.
	var uncommon_materials := _generate_distinct(drop_system, "uncommon", 3)
	for item in uncommon_materials:
		component.add_item(item)
	_check(uncommon_materials.size() == 3 and uncommon_materials[0].template_id != uncommon_materials[1].template_id, "three different Uncommon templates generated")
	var valid := merge_system.get_merge_validation(component, uncommon_materials)
	_check(bool(valid.get("valid", false)), "three different Uncommon items pass validation")
	_check(String(valid.get("output_rarity", "")) == "rare", "Uncommon preview advances to Rare")

	# Item box opens on equipment details; forge remains available as the right-side tab.
	screen._open()
	_check(screen.character_stage.visible and screen.detail_view.visible and not screen.forge_view.visible and screen.comparison.visible, "equipment, inventory and detail comparison are visible by default")
	_check(screen.inventory_list is GridContainer and screen.inventory_list.columns == 7, "inventory uses the seven-column compact item-box grid")
	screen._on_inventory_item_pressed(uncommon_materials[0])
	_check(screen._selected == uncommon_materials[0] and screen._merge_materials.is_empty(), "single click selects for comparison without consuming or staging")
	screen._set_mode("merge")
	_check(screen.forge_view.visible and not screen.detail_view.visible, "forge tab replaces the right detail pane without hiding equipment or inventory")
	for item in uncommon_materials:
		screen._on_inventory_item_pressed(item)
		screen.add_material_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check_workspace_bounds(screen)
	_check(screen._merge_materials.size() == 3, "three inventory selections fill the three material slots")
	_check(not screen.merge_button.disabled and screen.merge_button.text == "合成する", "merge button activates only for a valid three-item set")
	_check("アンコモン" in screen._material_slot_buttons[0].tooltip_text and uncommon_materials[0].display_name in screen._material_slot_buttons[0].tooltip_text and screen._material_slot_buttons[0].icon != null, "material slot shows its physical icon with full name and rarity on hover")
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
	# Renderer load can make wall-clock fixture waits shorter than tween time.
	for frame in 600:
		if not screen._merge_in_progress:
			break
		await get_tree().process_frame
	var rare_result := screen._merge_result
	_check(rare_result != null and rare_result.rarity == "rare", "Uncommon x3 creates one Rare result")
	_check(rare_result != null and _template_has_rarity(drop_system, rare_result.template_id, "rare"), "output comes from the existing Rare equipment pool")
	_check(screen._merge_materials.is_empty() and not screen._merge_in_progress, "material slots clear only after result reveal")
	_check(rare_result != null and rare_result.display_name in screen.merge_preview.text, "result card reveals output name, rarity and stats")
	_check(screen.forge_view.visible and not screen.detail_view.visible and screen._is_open, "completed merge stays in forge for consecutive crafting")
	_check_workspace_bounds(screen)
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
	screen._input(skip_event)
	var epic_result := screen._merge_result
	_check(epic_result != null and epic_result.rarity == "epic", "Rare x3 creates Epic and second animation accepts skip")
	_check(not screen._merge_in_progress and screen.forge_view.visible and screen._is_open, "second merge skip stays in forge without another transaction")

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
	_check(rare_button != null and not rare_button.disabled, "other rarities stay visible and inspectable when materials are staged")

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
	_check(equipped_button != null and not equipped_button.disabled and _button_has_badge(equipped_button, "E"), "equipped item remains marked and selectable in the shared inventory")
	screen._on_inventory_item_pressed(equipped_set[0])
	_check(screen.add_material_button.disabled and not screen.unequip_button.disabled, "selected equipped item can be removed, but cannot become a material")
	screen.unequip_button.pressed.emit()
	_check(not component.is_equipped(equipped_set[0]) and not screen.add_material_button.disabled, "unequipping immediately enables adding a material without any mode switch")
	screen.add_material_button.pressed.emit()
	_check(equipped_set[0] in screen._merge_materials, "the freshly unequipped item can be staged directly")
	screen.equip_button.pressed.emit()
	_check(component.is_equipped(equipped_set[0]) and equipped_set[0] not in screen._merge_materials, "equipping a staged material removes it from the forge safely")

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
	_check(locked_button != null and not locked_button.disabled and _button_has_badge(locked_button, "◆"), "protected item stays marked and available to inspect and equip")
	screen._on_inventory_item_pressed(locked_set[1])
	_check(screen.add_material_button.disabled, "locked item cannot be added to the forge")
	screen.lock_button.pressed.emit()
	_check(not locked_set[1].is_locked and not screen.add_material_button.disabled, "detail-pane protection button releases the item for forging")
	screen.lock_button.pressed.emit()
	_check(locked_set[1].is_locked and screen.add_material_button.disabled, "detail-pane protection button restores forge protection")

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

	# The presentation sorter and convenience selector never mutate or consume inventory.
	component.clear_all()
	var protected_items := _generate_distinct(drop_system, "uncommon", 3)
	var safe_items := _generate_distinct(drop_system, "uncommon", 3)
	var high_items := _generate_distinct(drop_system, "rare", 3)
	for item in protected_items + high_items + safe_items:
		component.add_item(item)
	protected_items[1].is_locked = true
	protected_items[2].is_locked = true
	component.equip(protected_items[0])
	screen._clear_merge_materials()
	screen._rarity_filter = ""
	var original_inventory := component.inventory.duplicate()
	screen._cycle_inventory_sort()
	screen._cycle_inventory_sort()
	screen._cycle_inventory_sort()
	_check(component.inventory == original_inventory, "sorting changes presentation order only")
	var visual_items := screen._visible_inventory()
	_check(visual_items[0].rarity == "rare", "rarity sorting places higher tiers first")
	screen._autofill_materials()
	_check(component.inventory == original_inventory, "auto set does not consume or rearrange inventory")
	_check(screen._merge_materials.size() == 3 and screen._merge_materials[0].rarity == "uncommon", "auto set chooses the lowest complete eligible rarity")
	_check(protected_items[0] not in screen._merge_materials and protected_items[1] not in screen._merge_materials and protected_items[2] not in screen._merge_materials, "auto set excludes equipped and locked items")
	_check(screen._visible_inventory().size() == original_inventory.size(), "staging materials does not force a rarity filter or hide other inventory")
	screen._clear_merge_materials()
	screen._set_rarity_filter(2)
	screen._autofill_materials()
	_check(screen._merge_materials.size() == 3 and screen._merge_materials[0].rarity == "rare", "explicit rarity filter controls the auto set")
	_check(not screen.rarity_filter.disabled, "equipment filter remains usable while merge materials are staged")
	screen._set_rarity_filter(1)
	_check(screen._selected != null and screen._selected.rarity == "uncommon", "equipment comparison follows the visible rarity filter")
	screen._set_rarity_filter(5)
	_check(screen._selected == null and screen.equip_button.disabled, "empty equipment filter clears hidden selection and disables equip")
	screen._clear_merge_materials()
	screen._set_rarity_filter(5)
	_check(screen._autofill_candidates().is_empty() and screen.autofill_button.disabled, "highest-tier filter never offers invalid promotion")
	screen._set_rarity_filter(0)
	_phase = "keyboard accept"
	# Keyboard accept reaches the same selection action without staging or consuming.
	await get_tree().process_frame
	await get_tree().process_frame
	var keyboard_button := screen.inventory_list.get_child(1) as Button
	var keyboard_item := keyboard_button.get_meta("inventory_item") as EquipmentData
	keyboard_button.grab_focus()
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	Input.parse_input_event(accept)
	await get_tree().process_frame
	var release := InputEventAction.new()
	release.action = "ui_accept"
	Input.parse_input_event(release)
	await get_tree().process_frame
	_check(screen._selected == keyboard_item and screen._merge_materials.is_empty(), "keyboard accept selects a different item without triggering a forge transaction")
	_phase = "crowded inventory"
	await _check_crowded_inventory(screen, component, drop_system)

	_expected_close = true
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
		if child is Button and not child.is_queued_for_deletion():
			var item := child.get_meta("inventory_item", null) as EquipmentData
			if item and item.display_name == item_name:
				return child as Button
	return null

func _button_has_badge(button: Button, badge_text: String) -> bool:
	for child in button.get_children():
		if child is Label and (child as Label).text == badge_text:
			return true
	return false

func _check_crowded_inventory(screen: EquipmentScreen, component: EquipmentComponent, drop_system: EquipmentDropSystem) -> void:
	screen._set_mode("details")
	component.clear_all()
	# Two passes of the original 25 cover every rarity and slot, independent of catalog growth.
	var crowded: Array[EquipmentData] = []
	for pass_index in 2:
		for template in drop_system.debug_get_templates().slice(0, 25):
			var item := drop_system.debug_generate_equipment(String(template.get("id", "")), String(template.get("rarity", "")))
			if item:
				crowded.append(item)
				component.add_item(item)
				if pass_index == 0 and component.get_equipped(item.slot) == null:
					component.equip(item)
	_check(crowded.size() == 50, "crowded UI fixture contains fifty independent equipment items")
	var overflow_item := crowded[0].duplicate(true) as EquipmentData
	_check(not component.add_item(overflow_item) and component.inventory.size() == EquipmentComponent.MAX_INVENTORY_SIZE, "the displayed fifty-slot capacity is enforced without deleting the overflow item")
	var detailed: EquipmentData = crowded.back()
	detailed.display_name = "忘れ去られた王家の守護者が遺した星詠みの聖遺物"
	detailed.stats = {"attack_power":25.0, "defense":8.0, "max_hp":30.0, "crit_rate":0.12, "crit_damage":0.4, "attack_speed":0.15, "move_speed":0.12}
	detailed.special_effects = ["kill_heal", "negate_hit", "low_hp_power"]
	detailed.special_effect_values = {"kill_heal":{"heal_flat":8.0}, "negate_hit":{"chance":0.1}, "low_hp_power":{"hp_threshold":0.35, "damage_bonus":0.35}}
	screen._set_rarity_filter(0)
	screen._on_inventory_item_pressed(detailed)
	screen._autofill_materials()
	await get_tree().process_frame
	await get_tree().process_frame
	_check_workspace_bounds(screen)
	_check(screen.inventory_list.get_child_count() == 50 and screen.inventory_list.columns == 7, "fifty item icons retain a seven-column compact grid without widening the workspace")
	_check(screen.detail_name.text == detailed.display_name and screen.detail_name.tooltip_text == detailed.display_name and screen.comparison.text.contains("パッシブ効果") and screen.comparison.text.contains("命喰らい"), "long item names remain available by tooltip and all affixes reach the readable comparison panel")
	var scroll := screen.inventory_list.get_parent() as ScrollContainer
	scroll.scroll_vertical = 0
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		_capture_viewport("equipment_unified_full_inventory.png")
	# Follow-focus makes the end of a large stash reachable using standard GUI navigation.
	var last_button := screen.inventory_list.get_child(49) as Button
	last_button.grab_focus()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(scroll.scroll_vertical > 0, "keyboard focus scrolls to the last inventory row")
	_check(scroll.get_global_rect().intersects(last_button.get_global_rect()), "last-row focused item is in the visible inventory window")
	var detail_scroll := screen.comparison.get_v_scroll_bar()
	_check(detail_scroll.max_value > detail_scroll.page, "long comparison uses readable scrolling instead of shrinking text")
	detail_scroll.value = detail_scroll.max_value
	await get_tree().process_frame
	_check_workspace_bounds(screen)
	if DisplayServer.get_name() != "headless":
		_capture_viewport("equipment_unified_long_comparison.png")
	var previous_scroll := detail_scroll.value
	screen._refresh()
	await get_tree().process_frame
	_check(previous_scroll > 0.0 and is_equal_approx(detail_scroll.value, previous_scroll), "refreshing the same equipment preserves the comparison reading position")
	# Another long item prevents a short description from masking a stale-scroll bug.
	var other_detailed: EquipmentData = crowded[crowded.size() - 2]
	other_detailed.display_name = "別の守護者が遺した、詳細比較を必要とする長い装備名"
	other_detailed.stats = detailed.stats.duplicate()
	other_detailed.special_effects = detailed.special_effects.duplicate()
	other_detailed.special_effect_values = detailed.special_effect_values.duplicate(true)
	screen._on_inventory_item_pressed(other_detailed)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(is_zero_approx(detail_scroll.value) and detail_scroll.max_value > detail_scroll.page, "selecting a different long item scrolls to its name, not the previous item's last affix")
	_check(screen.detail_meta.get_theme_color("font_color").is_equal_approx(other_detailed.get_rarity_color().lightened(0.2)), "rarity text uses a brighter display color without modifying item data")
	if DisplayServer.get_name() != "headless":
		_capture_viewport("equipment_unified_new_selection.png")

func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	var actions: Array[String] = []
	for action: String in ["character_screen", "equipment_menu", "ui_cancel", "ui_accept", "interact"]:
		if event.is_action_pressed(action):
			actions.append(action)
	if not actions.is_empty():
		print("EQUIPMENT_INPUT phase=%s type=%s actions=%s" % [_phase, event.get_class(), actions])

func _capture_viewport(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	if image:
		image.save_png("%s/%s" % [OUTPUT_DIR, file_name])

func _check_workspace_bounds(screen: EquipmentScreen) -> void:
	var viewport_rect := screen.get_viewport().get_visible_rect()
	var columns := screen.get_node("Background/Margin/Main/Columns") as HBoxContainer
	for panel_name in ["CharacterPanel", "InventoryPanel"]:
		var panel := columns.get_node(panel_name) as Control
		var rect := panel.get_global_rect()
		_check(viewport_rect.encloses(rect), "%s fits within the viewport: %s / %s" % [panel_name, rect, viewport_rect])
	# The current compact item box reparents the right pane as a floating popup.
	if screen.forge_panel.visible:
		_check(viewport_rect.encloses(screen.forge_panel.get_global_rect()), "floating detail/forge pane fits the viewport")
		for control: Control in [screen.detail_tab, screen.forge_tab]:
			_check(control.is_visible_in_tree() and viewport_rect.encloses(control.get_global_rect()), "right-side tab stays visible: %s" % control.name)
		var active_actions: Array = [screen.add_material_button, screen.merge_button, screen.autofill_button, screen.clear_materials_button] if screen.forge_view.visible else [screen.lock_button]
		for control: Control in active_actions:
			_check(control.is_visible_in_tree() and viewport_rect.encloses(control.get_global_rect()), "active right-pane action stays visible: %s" % control.name)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
