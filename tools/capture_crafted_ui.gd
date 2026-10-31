extends Node
## Presentation images of actual screens. No assertions or gameplay test suite.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	DirAccess.make_dir_recursive_absolute("res://artifacts/crafted_ui")
	var title := (load("res://scenes/title.tscn") as PackedScene).instantiate()
	add_child(title)
	await capture("title")
	remove_child(title)
	title.queue_free()
	var home := (load("res://ui/home/home.tscn") as PackedScene).instantiate()
	add_child(home)
	await capture("characters")
	remove_child(home)
	home.queue_free()
	GameManager.selected_character_id = "swordsman"
	seed(7112026)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		var background := game.get_node_or_null(node_name)
		if background:
			background.process_mode = Node.PROCESS_MODE_DISABLED
	var player := game.get_node("Player") as Player
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	var hud := game.get_node("HUD") as HUD
	hud.gold_label.visible = true
	hud.set_combo(24)
	hud.set_map_status(1, 3, "忘却の地下回廊", 52, 900, 15, 420, false)
	await capture("hud")
	var drop_system := game.get_node("EquipmentDropSystem") as EquipmentDropSystem
	var equipment := player.equipment_component
	for template in drop_system.debug_get_templates():
		var item := drop_system.debug_generate_equipment(String(template.id), String(template.rarity))
		if item:
			equipment.add_item(item)
			if equipment.get_equipped(item.slot) == null:
				equipment.equip(item)
	var screen := game.get_node("EquipmentScreen") as EquipmentScreen
	screen._open()
	await capture("equipment")
	screen._close()
	var level := game.get_node("LevelUpSelect") as LevelUpSelect
	level._open()
	await capture("level_up")
	level.hide()
	GameManager.close_modal()
	var rewards: Array[ItemData] = []
	for item in DataLoader.items.values():
		if rewards.size() < 3:
			rewards.append(item)
	var reward := game.get_node("ItemSelect") as ItemSelect
	reward.show_choices(rewards)
	await capture("boss_rewards")
	AudioManager.stop_all(false)
	get_tree().quit()

func capture(filename: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/crafted_ui/%s.png" % filename)
