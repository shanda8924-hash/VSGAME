extends Node
## 装備の流れの実画面：床ドロップ（各レア度）、アイテムボックスの詳細、鍛造。
## xvfb-run などの実レンダラで実行し、artifacts/item_flow/ へ保存する。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	DirAccess.make_dir_recursive_absolute("res://artifacts/item_flow")
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
	var templates := drop_system.debug_get_templates()
	# 床ドロップ：プレイヤーの周りへ各レア度を 1 個ずつ
	var rarities := ["uncommon", "rare", "epic", "legendary", "mythic"]
	var dropped: Array[EquipmentData] = []
	for index in rarities.size():
		var rarity: String = rarities[index]
		var pick: Dictionary = {}
		for template in templates:
			if String(template.rarity) == rarity and String(template.slot) == "weapon":
				pick = template
				break
		var item := drop_system.debug_generate_equipment(String(pick.id), rarity)
		dropped.append(item)
		drop_system.debug_drop_equipment(item, player.global_position + Vector2(-220 + index * 110, 70 if index % 2 == 0 else -40))
	for frame in 10:
		await get_tree().process_frame
	await capture("drops_fresh")
	for frame in 50:
		await get_tree().process_frame
	await capture("drops_settled")
	# 所持品を埋める（各レア度を混ぜる）
	var equipment := player.equipment_component
	var count := 0
	for template in templates:
		if count >= 34:
			break
		if int(template.art_cell) % 3 != 0:
			continue
		var item := drop_system.debug_generate_equipment(String(template.id), String(template.rarity))
		if item:
			equipment.add_item(item)
			count += 1
			if equipment.get_equipped(item.slot) == null:
				equipment.equip(item)
	var screen := game.get_node("EquipmentScreen") as EquipmentScreen
	screen._open()
	for frame in 8:
		await get_tree().process_frame
	var items := equipment.get_all_inventory()
	var weapon: EquipmentData = null
	for item in items:
		if item.slot == "weapon" and not equipment.is_equipped(item):
			weapon = item
			break
	if weapon:
		screen._on_inventory_item_pressed(weapon)
	await capture("box_detail")
	screen._set_right_mode("forge")
	for frame in 4:
		await get_tree().process_frame
	if screen.has_method("_autofill_materials"):
		screen._autofill_materials()
	await capture("box_forge")
	screen._close()
	AudioManager.stop_all(false)
	get_tree().quit()

func capture(filename: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/item_flow/%s.png" % filename)
