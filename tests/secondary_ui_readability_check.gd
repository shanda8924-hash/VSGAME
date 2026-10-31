extends Node
## Actual Game -> Pause / ItemSelect, then actual Title. No production test hooks.
var failures: Array[String] = []
var game: Node

func _ready() -> void:
	SaveManager.begin_ephemeral_session() # Keep fixture rewards out of the player's save.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(1)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(4)

func _capture(name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image.save_png("res://artifacts/secondary_readability_%s.png" % name) == OK, "save " + name)

func _check_labels(root: Node, bounds: Rect2, description: String) -> void:
	for node in root.find_children("*", "Label", true, false):
		var label := node as Label
		if not label.is_visible_in_tree():
			continue
		_check(label.get_theme_font_size("font_size") >= 18, description + " tiny text: " + label.text)
		_check(bounds.grow(1).encloses(label.get_global_rect()), description + " text outside bounds: " + label.text)
		_check(label.size.y + 1 >= label.get_combined_minimum_size().y, description + " clipped text: " + label.text)

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_check(get_viewport().get_visible_rect().size == Vector2(1600, 900), "run at 1600x900")
	GameManager.selected_character_id = "swordsman"
	game = load("res://scenes/game.tscn").instantiate()
	game.tree_entered.connect(func(): get_tree().current_scene = game)
	get_tree().root.add_child(game)
	await _frames(180)
	game.get_node("WaveSpawner").process_mode = Node.PROCESS_MODE_DISABLED
	game.get_node("MapRunController").process_mode = Node.PROCESS_MODE_DISABLED
	game.get_node("Player").weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await _frames(3)
	var weapons := game.get_node("Player").weapon_manager as WeaponManagerComponent
	_check(weapons.get_class_character_id() == "swordsman", "real Swordsman class initialized")
	# Swordsman deliberately has only its class attack, not a starting WeaponInstance.
	# Acquire real relic data via the same public method used by ShopSystem purchases.
	_check(weapons.get_weapon_instances().is_empty(), "Swordsman does not auto-equip a projectile weapon")
	var relic := DataLoader.weapons.get("steam_burst_weapon") as WeaponData
	_check(relic != null, "real relic weapon fixture exists")
	if relic:
		weapons.add_weapon(relic)

	for upgrade in DataLoader.get_all_upgrades():
		_check(upgrade.icon_path.begins_with("res://assets/ui/icons/battle_skills/upgrades/"), "upgrade has semantic battle icon: " + upgrade.id)
		_check(ResourceLoader.exists(upgrade.icon_path), "upgrade icon exists: " + upgrade.id)
	var level_up := game.get_node("LevelUpSelect") as LevelUpSelect
	level_up._open()
	await _frames(6)
	_check(level_up.visible and level_up.grid_container.get_child_count() == 3, "real three-choice level-up modal")
	for child in level_up.grid_container.get_children():
		var card := child as Button
		var has_battle_icon := false
		if card:
			_check_labels(card, card.get_global_rect(), "level-up card")
			for picture in card.find_children("*", "TextureRect", true, false):
				var texture_rect := picture as TextureRect
				if texture_rect.texture and texture_rect.texture.resource_path.begins_with("res://assets/ui/icons/battle_skills/upgrades/"):
					has_battle_icon = true
		_check(has_battle_icon, "level-up card uses its UpgradeData icon")
	await _capture("level_up_icons")
	await _press("ui_accept")
	_check(not level_up.visible and not get_tree().paused, "keyboard level-up selection closes modal")

	var pause := game.get_node("PauseMenu") as PauseMenu
	await _press("ui_cancel")
	_check(pause.visible and get_tree().paused, "Escape opens real PauseMenu")
	_check(pause.weapon_list.get_child_count() == 1, "acquired relic produces one real weapon row")
	var pause_panel := pause.get_node("CenterContainer/Panel") as Control
	_check(get_viewport().get_visible_rect().encloses(pause_panel.get_global_rect()), "weapon pause frame inside viewport")
	_check_labels(pause.weapon_list, pause_panel.get_global_rect(), "weapon")
	await _capture("pause_weapons")

	pause.talent_tab_button.grab_focus()
	await _press("ui_accept")
	var book = pause.talent_book
	_check(book.visible, "keyboard opens current talent atlas")
	_check(book.nodes.size() == 9, "Swordsman talent tree has root and eight levels")
	_check_labels(book, get_viewport().get_visible_rect(), "talent atlas")
	for node in book.nodes:
		_check(get_viewport().get_visible_rect().encloses(node.get_global_rect()), "talent seal inside viewport")
		_check(node.art != null, "talent seal has skill artwork")
	await _capture("talent_top")
	var first_index: int = book.selected_index
	await _press("ui_down")
	_check(book.selected_index != first_index, "arrow key moves talent selection")
	_check(book.nodes[book.selected_index].has_focus(), "selected talent has keyboard focus")
	await _capture("talent_bottom")
	await _press("ui_cancel")
	_check(not pause.visible and not get_tree().paused, "Escape closes talent pause")

	var rewards := game.get_node("ItemSelect") as ItemSelect
	var items: Array[ItemData] = []
	for id in ["blood_vial", "vitality_ring", "long_reach_charm"]:
		var item := DataLoader.items.get(id) as ItemData
		_check(item != null, "real item data: " + id)
		if item:
			items.append(item)
	rewards.show_choices(items)
	await _frames(6)
	_check(rewards.visible and rewards.grid_container.get_child_count() == 3, "real three-item reward modal")
	for child in rewards.grid_container.get_children():
		var card := child as Button
		_check(card != null, "reward child is card")
		if card:
			_check(get_viewport().get_visible_rect().encloses(card.get_global_rect()), "reward card inside viewport")
			_check_labels(card, card.get_global_rect(), "reward card")
			_check(card.find_children("*", "TextureRect", true, false).size() == 1, "reward card has one item icon")
	await _capture("item_select")
	await _press("ui_accept")
	_check(not rewards.visible and not get_tree().paused and GameManager.active_modal_count == 0, "keyboard reward selection closes modal")

	var skill_rewards := game.get_node("ConceptSelect") as ConceptSelect
	var completed_candidates: Array[Dictionary] = []
	for definition in game.get_node("ConceptSystem").get_completed_skill_definitions():
		completed_candidates.append(definition)
		if completed_candidates.size() == 3:
			break
	skill_rewards.show_completed_skill_choices(completed_candidates, "ボス宝箱：完成スキルを1つ選択")
	await _frames(6)
	_check(skill_rewards.visible and skill_rewards.choices.get_child_count() == 3, "real three-skill boss reward modal")
	for child in skill_rewards.choices.get_children():
		var card := child as Button
		_check(card != null, "completed skill child is card")
		if card:
			_check(get_viewport().get_visible_rect().encloses(card.get_global_rect()), "completed skill card inside viewport")
			_check_labels(card, card.get_global_rect(), "completed skill card")
			_check(card.find_children("*", "TextureRect", true, false).size() == 1, "completed skill card has one icon")
			var pictures := card.find_children("*", "TextureRect", true, false)
			if not pictures.is_empty():
				var texture := (pictures[0] as TextureRect).texture
				_check(texture != null and texture.resource_path.begins_with("res://assets/ui/icons/battle_skills/completed/"), "completed skill uses magic battle icon")
	await _capture("completed_skill_select")
	await _press("ui_accept")
	_check(not skill_rewards.visible and not get_tree().paused and GameManager.active_modal_count == 0, "keyboard completed skill selection closes modal")

	# Free the fixture only; never change scenes from the runner or it would free itself.
	game.queue_free()
	await _frames(4)
	var title := load("res://scenes/title.tscn").instantiate() as TitleScreen
	title.tree_entered.connect(func(): get_tree().current_scene = title)
	get_tree().root.add_child(title)
	await _frames(5)
	var frame := title.get_node("MenuFrame") as Control
	_check_labels(title, get_viewport().get_visible_rect(), "title start")
	await _capture("title")
	await _press("ui_accept")
	_check(title.mode_select.visible, "keyboard GAME START shows modes")
	_check_labels(title, get_viewport().get_visible_rect(), "title modes")
	await _capture("title_modes")
	AudioManager.stop_all()
	for failure in failures:
		push_error(failure)
	print("SECONDARY_UI_READABILITY_CHECK ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
