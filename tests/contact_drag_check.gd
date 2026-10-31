extends Node
var screen: EquipmentScreen
var equipment: EquipmentComponent
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	await get_tree().process_frame
	for name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		game.get_node(name).process_mode = Node.PROCESS_MODE_DISABLED
	var player := game.get_node("Player") as Player
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	var enemy := (load("res://entities/enemies/enemy_basic.tscn") as PackedScene).instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.max_hp = 1000
	data.move_speed = 0
	data.attack_range = 24
	enemy.enemy_data = data
	enemy.position = player.position + Vector2(65,0)
	game.add_child(enemy)
	await get_tree().physics_frame
	player.move_and_collide(Vector2(100,0))
	assert(player.position.distance_to(enemy.position) >= 39, "Player body cannot pass through enemy")
	assert(player.position.x < enemy.position.x, "No crossing")
	assert(enemy._normal_reach() > player.position.distance_to(enemy.position), "Enemy still has reach at contact")
	enemy.queue_free()
	await get_tree().process_frame
	equipment = player.equipment_component
	equipment.clear_all()
	var drops := game.get_node("EquipmentDropSystem") as EquipmentDropSystem
	var weapons: Array[EquipmentData] = []
	for template in drops.debug_get_templates():
		if template.slot == "weapon":
			var item := drops.debug_generate_equipment(template.id, template.rarity)
			equipment.add_item(item)
			weapons.append(item)
			if weapons.size() == 2: break
	screen = game.get_node("EquipmentScreen") as EquipmentScreen
	screen._open()
	await frames()
	assert(not screen.equip_button.visible and not screen.unequip_button.visible)
	await drag(inventory_button(weapons[0]), slot_button("weapon"))
	assert(equipment.get_equipped("weapon") == weapons[0], "Mouse drag equips empty slot")
	await drag(inventory_button(weapons[1]), slot_button("head"))
	assert(equipment.get_equipped("head") == null and equipment.get_equipped("weapon") == weapons[0], "Wrong slot rejects")
	await drag(inventory_button(weapons[1]), slot_button("weapon"))
	assert(equipment.get_equipped("weapon") == weapons[1], "Mouse drag replaces")
	await drag(slot_button("weapon"), inventory_button(weapons[0]))
	assert(equipment.get_equipped("weapon") == null and equipment.inventory.size() == 2, "Mouse drag unequips without loss")
	print("CONTACT_DRAG PASS: physical contact/reach, actual mouse empty equip/wrong-slot/replace/unequip, no loss")
	get_tree().quit()
func inventory_button(item: EquipmentData) -> Control:
	for child in screen.inventory_list.get_children():
		if child.get_meta("inventory_item", null) == item: return child
	return null
func slot_button(slot: String) -> Control:
	for container in [screen.left_slots, screen.right_slots, screen.top_slot, screen.bottom_slot]:
		for child in container.get_children():
			if child.get_meta("equipment_slot", "") == slot: return child
	return null
func frames() -> void:
	for i in 8: await get_tree().process_frame
func motion(point: Vector2, relative: Vector2, held: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	get_viewport().push_input(event, true)
func button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	get_viewport().push_input(event, true)
func drag(source: Control, target: Control) -> void:
	var a := source.get_global_rect().get_center()
	var b := target.get_global_rect().get_center()
	motion(a,Vector2.ZERO,false)
	await frames()
	button(a,true)
	await frames()
	motion(a+Vector2(15,0),Vector2(15,0),true)
	await frames()
	assert(get_viewport().gui_is_dragging(), "Native drag began")
	assert(not screen.forge_panel.visible, "Tooltip must not cover drop targets")
	motion(b,b-a-Vector2(15,0),true)
	await frames()
	if DisplayServer.get_name() != 'headless':
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute('res://artifacts/contact_drag')
		get_viewport().get_texture().get_image().save_png('res://artifacts/contact_drag/drag.png')
	button(b,false)
	await frames()



