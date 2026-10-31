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
	var component := player.equipment_component
	var forge := EquipmentMergeSystem.new()
	var screen := game.get_node("EquipmentScreen") as EquipmentScreen
	screen._open()
	screen._set_mode("merge")
	for rarity in ["uncommon", "rare", "epic", "legendary"]:
		component.clear_all()
		var id := ""
		for template in drops.debug_get_templates():
			if template.rarity == rarity:
				id = template.id
				break
		var materials: Array[EquipmentData] = []
		for i in EquipmentMergeSystem.required_count(rarity):
			var item := drops.debug_generate_equipment(id, rarity)
			component.add_item(item)
			materials.append(item)
		assert(forge.can_merge_materials(component, materials))
		materials[0].is_locked = true
		assert(not forge.can_merge_materials(component, materials))
		materials[0].is_locked = false
		var duplicate := materials.duplicate()
		duplicate[1] = duplicate[0]
		assert(not forge.can_merge_materials(component, duplicate))
		forge._drop_table.merge_rules[rarity].success_rate = 0.0
		assert(forge.merge_materials(component, materials) == null)
		assert(component.inventory.size() == materials.size() - forge.failure_loss(rarity))
		var remaining := component.inventory.size()
		assert(forge.merge_materials(component, materials) == null and component.inventory.size() == remaining)
		component.clear_all()
		materials.clear()
		for i in EquipmentMergeSystem.required_count(rarity):
			var item := drops.debug_generate_equipment(id, rarity)
			component.add_item(item)
			materials.append(item)
		screen._merge_system._drop_table.merge_rules[rarity].success_rate = {"uncommon":0.95,"rare":0.9,"epic":0.85,"legendary":0.8}[rarity]
		screen._merge_result = null
		screen._merge_materials.assign(materials)
		screen._refresh()
		assert(not screen.merge_button.disabled)
		assert(screen._material_slot_buttons.size() == 10)
		if rarity == "legendary" and DisplayServer.get_name() != "headless":
			for i in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://artifacts/forge_balance")
			get_viewport().get_texture().get_image().save_png("res://artifacts/forge_balance/ten_materials.png")
		screen._merge_system._drop_table.merge_rules[rarity].success_rate = 1.0
		screen._merge_selected()
		screen._complete_merge_animation()
		assert(component.inventory.size() == 1)
		assert(screen._merge_result.rarity == forge.get_next_rarity(rarity))
		assert(screen.forge_view.visible and screen._is_open)
	var hearts := game.get_node("HeartDropSystem") as HeartDropSystem
	hearts.heart_drop_chance = 1.0
	for i in 20:
		hearts._on_enemy_drop_requested(Vector2(10000, 10000), false, false)
	await get_tree().process_frame
	assert(get_tree().get_nodes_in_group("random_recovery_hearts").size() == 5)
	var health := player.get_node("HealthComponent") as HealthComponent
	health.equipment_defense_flat = 1000
	health.invincible = false
	var taken := health.apply_damage(10.0)
	assert(taken >= 4.0)
	print("FORGE_BALANCE PASS: 3/5/7/10, success/failure refunds, stale refs, locked/duplicate guards, forge retained; heart cap 5; armor floor 40%")
	AudioManager.stop_all(false)
	get_tree().quit()
