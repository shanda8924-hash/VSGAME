extends Node
## 1600x900の実Game scene上でキャラクター画面を開き、主要領域の収まりを検証する。

var failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	var player := game.get_node("Player") as Player
	var equipment := player.equipment_component
	var templates = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment/templates.json"))
	for i in 6:
		var template: Dictionary = templates[i]
		var item := EquipmentData.new()
		item.instance_id = "layout_%d" % i
		item.template_id = template.get("id", "")
		item.display_name = template.get("display_name", "装備")
		item.slot = EquipmentComponent.SLOTS[i]
		item.rarity = ["uncommon", "rare", "epic", "legendary", "mythic", "epic"][i]
		item.icon_path = template.get("icon_path", "")
		item.stats = {"attack_power":10.0 + i, "max_hp":30.0 + i * 5.0, "crit_rate":0.01 * i}
		equipment.add_item(item)
		equipment.equip(item)
	var screen := game.get_node("EquipmentScreen") as EquipmentScreen
	screen._open()
	await get_tree().process_frame
	await get_tree().process_frame
	var viewport_size := get_viewport().get_visible_rect().size
	_check(viewport_size == Vector2(1600, 900), "viewport is 1600x900: %s" % viewport_size)
	_check(_inside_viewport(screen.character_portrait, viewport_size), "character portrait fits")
	_check(_inside_viewport(screen.stats, viewport_size), "stats panel fits")
	_check(_inside_viewport(screen.inventory_list.get_parent(), viewport_size), "inventory fits")
	_check(_inside_viewport(screen.comparison, viewport_size), "comparison fits")
	_check(_slot_count(screen) == 6, "six slots visible")
	for container in [screen.left_slots, screen.top_slot, screen.bottom_slot, screen.right_slots]:
		for child in container.get_children():
			_check(_inside_viewport(child, viewport_size), "slot fits: %s" % child.name)
	# headlessのdummy rendererでは画像読取自体がエラーになる。GUI実行時だけ保存する。
	if DisplayServer.get_name() != "headless":
		var image := get_viewport().get_texture().get_image()
		if image:
			image.save_png("res://.godot/character-screen-check.png")
	for failure in failures:
		push_error(failure)
	print("CHARACTER_SCREEN_LAYOUT_CHECK failures=%d viewport=%s slots=%d" % [failures.size(), viewport_size, _slot_count(screen)])
	screen._close()
	game.queue_free()
	await get_tree().process_frame
	AudioManager.stop_all()
	await get_tree().create_timer(0.2, true, false, true).timeout
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _inside_viewport(control: Control, viewport_size: Vector2) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= viewport_size.x and rect.end.y <= viewport_size.y

func _slot_count(screen: EquipmentScreen) -> int:
	return screen.left_slots.get_child_count() + screen.top_slot.get_child_count() + screen.bottom_slot.get_child_count() + screen.right_slots.get_child_count()

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
