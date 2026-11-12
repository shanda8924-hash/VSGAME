extends Node
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	GameManager.selected_character_id = "swordsman"
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	for name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		game.get_node(name).process_mode = Node.PROCESS_MODE_DISABLED
	var player := game.get_node("Player") as Player
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	var drops := game.get_node("EquipmentDropSystem") as EquipmentDropSystem
	for template in drops.debug_get_templates():
		var item := drops.debug_generate_equipment(template.id, template.rarity)
		player.equipment_component.add_item(item)
		if player.equipment_component.get_equipped(item.slot) == null:
			player.equipment_component.equip(item)
		if player.equipment_component.inventory.size() >= 50: break
	var screen := game.get_node("EquipmentScreen") as EquipmentScreen
	screen._open()
	await snap("bag")
	assert(not screen.forge_panel.visible)
	var button := screen.inventory_list.get_child(5) as Button
	button.mouse_entered.emit()
	assert(screen.forge_panel.visible)
	assert(screen._selected == button.get_meta("inventory_item"))
	# Hold pointer over the actual card while capturing its hover state.
	Input.warp_mouse(button.get_global_rect().get_center())
	await snap("hover")
	assert(screen.forge_panel.visible)
	Input.warp_mouse(screen.forge_panel.get_global_rect().get_center())
	await get_tree().create_timer(0.3, true).timeout
	assert(screen.forge_panel.visible)
	Input.warp_mouse(Vector2(1590, 890))
	await get_tree().create_timer(0.4, true).timeout
	assert(not screen.forge_panel.visible)
	screen._bag_forge_button.pressed.emit()
	assert(screen.forge_view.visible)
	screen._close()
	assert(game.get_node("HUD").visible)
	print("COMPACT_HOVER PASS: 50 items, hover comparison, hover grace, forge access, HUD restored")
	get_tree().quit()
func snap(name: String) -> void:
	for i in 5: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts/compact_hover")
	get_viewport().get_texture().get_image().save_png("res://artifacts/compact_hover/" + name + ".png")
