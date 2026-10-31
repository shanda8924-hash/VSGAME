extends Node
## Presentation capture only: loads the actual game and actual equipment catalog.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
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
	var drop_system := game.get_node("EquipmentDropSystem") as EquipmentDropSystem
	var equipment := player.equipment_component
	var items: Array[EquipmentData] = []
	for template in drop_system.debug_get_templates():
		var item := drop_system.debug_generate_equipment(String(template.id), String(template.rarity))
		if item:
			items.append(item)
	items.reverse()
	for item in items:
		equipment.add_item(item)
	items.reverse()
	for item in items:
		if equipment.get_equipped(item.slot) == null:
			equipment.equip(item)
	var screen := game.get_node("EquipmentScreen") as EquipmentScreen
	screen._sort_mode = 2
	screen._open()
	for item in items:
		if item.rarity == "rare" and item.slot == "weapon":
			screen._on_inventory_item_pressed(item)
			break
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var capture := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://artifacts/item_box_crafted")
	capture.save_png("res://artifacts/item_box_crafted/implemented.png")
	AudioManager.stop_all(false)
	get_tree().quit()
