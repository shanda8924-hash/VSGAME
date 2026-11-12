extends Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	GameManager.selected_character_id = "swordsman"
	seed(2000913)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		var background := game.get_node_or_null(node_name)
		if background:
			background.process_mode = Node.PROCESS_MODE_DISABLED
	var player := game.get_node("Player") as Player
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	var drops := game.get_node("EquipmentDropSystem") as EquipmentDropSystem
	var templates := drops.debug_get_templates()
	assert(templates.size() == 200)
	var ids := {}
	var rarities := {}
	var items: Array[EquipmentData] = []
	DirAccess.make_dir_recursive_absolute("res://artifacts/equipment_200/icons")
	for template in templates:
		assert(not ids.has(template.id))
		ids[template.id] = true
		rarities[template.rarity] = int(rarities.get(template.rarity, 0)) + 1
		var item := drops.debug_generate_equipment(String(template.id), String(template.rarity))
		assert(item != null and item.template_id == template.id and item.slot == template.slot)
		assert(not item.stats.is_empty())
		# 実行時は 64px の ember_v5 版（readable_v4 と同じ原画・同じ手順）を使う。
		var pixel_path := "res://assets/visuals/ember_v5/equipment/%s.png" % item.template_id
		assert(item.icon_path == pixel_path and ResourceLoader.exists(pixel_path), "regenerated icon must reach inventory, world drops and floating weapon")
		assert((load(pixel_path) as Texture2D).get_size() == Vector2(64,64))
		var texture := (game.get_node("EquipmentScreen") as EquipmentScreen)._load_trimmed_icon(item.icon_path)
		assert(texture != null)
		var picture := texture.get_image()
		assert(picture != null and not picture.get_used_rect().size == Vector2i.ZERO)
		assert(picture.save_png("res://artifacts/equipment_200/icons/%s.png" % item.template_id) == OK)
		items.append(item)
	for rarity in rarities:
		assert(rarities[rarity] == 40)
	# Show one complete mine collection plus the refreshed original collection.
	for index in range(50, 75):
		player.equipment_component.add_item(items[index])
	for index in range(25):
		player.equipment_component.add_item(items[index])
	for index in range(50,75):
		var item := items[index]
		if player.equipment_component.get_equipped(item.slot) == null:
			player.equipment_component.equip(item)
	var screen := game.get_node("EquipmentScreen") as EquipmentScreen
	screen._open()
	screen._on_inventory_item_pressed(items[50])
	for frame in 12:
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/equipment_200/implemented.png")
	print("EQUIPMENT_CATALOG_200 PASS: 200 generated, 200 actual UI icons loaded/exported, rarity 40x5, six slots equipped")
	game.queue_free()
	for frame in 4:
		await get_tree().process_frame
	AudioManager.stop_all(false)
	get_tree().quit()
