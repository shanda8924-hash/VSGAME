extends Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	var game := get_parent()
	var controller := game.get_node("MapRunController") as MapRunController
	var wave := game.get_node("WaveSpawner") as WaveSpawner
	var player := game.get_node("Player") as Player
	var stage := game.get_node("StageEnvironment") as StageEnvironment
	var controls := game.mobile_controls as MobileControls
	var touch_preview := DisplayServer.is_touchscreen_available() or "--touch-preview" in OS.get_cmdline_user_args()
	player.health_component.invincible = true
	for sound_id in ["wizard_cast", "melee_swing", "combat_hit", "room_door", "chest_open", "heart_collect", "equipment_pickup"]:
		assert(AudioManager.sfx_table.has(sound_id), "Imported sound is not loaded: %s" % sound_id)
	assert(controller._sector_mode and controller._sector_index == 0)
	assert(wave._sector_active and wave._spawning_paused)
	if touch_preview:
		assert(controls.visible, "Touch controls are hidden in preview")
		controls._update_stick(Vector2(204, 102))
		assert(Input.get_action_strength("ui_right") > 0.8, "Touch joystick did not move")
		controls._release_stick()
		assert(Input.get_action_strength("ui_right") == 0.0)
		for child in controls.get_children():
			if child is Button and child.text == "回避":
				child.button_down.emit()
				assert(Input.is_action_pressed("dodge"), "Touch dodge is not wired")
				child.button_up.emit()
				assert(not Input.is_action_pressed("dodge"))
	var equipment := EquipmentData.new()
	equipment.instance_id = "sector_mobile_probe"
	equipment.slot = "weapon"
	equipment.display_name = "旅鉄の剣"
	equipment.icon_path = "res://assets/items/painted_200/wanderer_iron_sword.tres"
	assert(player.equipment_component.add_item(equipment))
	var pickup_sound_routed := false
	for sound_player in AudioManager._sfx_players:
		if sound_player.stream == AudioManager.sfx_table["equipment_pickup"]:
			pickup_sound_routed = true
	assert(pickup_sound_routed, "Real equipment acquisition did not use the new sound")
	assert(player.equipment_component.equip(equipment))
	assert(player.floating_weapons._sprites.has("equipment"), "Equipped weapon art missing")
	for frame in 2: await get_tree().process_frame
	assert(player.floating_weapons.get_muzzle("equipment") != player.global_position, "Projectile origin not on floating weapon")
	assert(player.equipment_component.unequip("weapon"))
	assert(not player.floating_weapons._sprites.has("equipment"), "Weapon art persisted after unequip")
	player.weapon_manager.grant_sector_style()
	player.weapon_manager.grant_sector_style()
	player.weapon_manager.grant_sector_style()
	player.weapon_manager.grant_sector_style()
	assert(player.weapon_manager.sector_arc_width_level == 2 and player.weapon_manager.sector_follow_up_level == 2)
	assert(player.weapon_manager.sector_pierce_level == 0 and player.weapon_manager.sector_chain_level == 0)
	for frame in 120:
		await get_tree().physics_frame
		if wave._active_sector_enemy_count() > 0:
			break
	assert(wave._active_sector_enemy_count() > 0, "Sector did not spawn enemies")
	_assert_imported_props(stage, player)
	if "--asset-capture" in OS.get_cmdline_user_args(): await _capture_imported_props(stage, player, 1)
	var wizard_data := DataLoader.characters.get("wizard") as CharacterData
	var wizard_attack := HomingBoltAttack.new()
	wizard_attack.execute(player, wizard_data, player.weapon_manager)
	var wizard_sound_routed := false
	for sound_player in AudioManager._sfx_players:
		if sound_player.stream == AudioManager.sfx_table["wizard_cast"]:
			wizard_sound_routed = true
	assert(wizard_sound_routed, "Wizard attack did not use the new cast sound")
	var magic_bolt: Projectile = null
	for node in get_tree().get_nodes_in_group("projectiles"):
		if node is Projectile and node.get_node_or_null("WizardMagic") != null:
			magic_bolt = node as Projectile
			break
	assert(magic_bolt != null and not magic_bolt.get_node("Visual").visible, "Wizard still uses the generic arrow")
	assert((magic_bolt.get_node("WizardMagic") as AnimatedSprite2D).sprite_frames.get_frame_count("default") == 5)
	magic_bolt.set_physics_process(false)
	if "--asset-capture" in OS.get_cmdline_user_args():
		magic_bolt.global_position = player.global_position + Vector2(100, -80)
		magic_bolt.rotation = 0.0
		await _capture("imported_wizard_magic")
	magic_bolt.queue_free()
	if "--capture" in OS.get_cmdline_user_args(): await _capture("mobile_sector")
	var bag := game.get_node("EquipmentScreen") as EquipmentScreen
	bag._open()
	for frame in 3: await get_tree().process_frame
	if touch_preview: assert(not controls.visible, "Touch combat controls overlap the inventory")
	if "--capture" in OS.get_cmdline_user_args(): await _capture("mobile_inventory")
	bag._on_inventory_item_pressed(equipment)
	for frame in 3: await get_tree().process_frame
	_assert_popup_within_screen(bag)
	if "--capture" in OS.get_cmdline_user_args(): await _capture("mobile_inventory_detail")
	bag._set_right_mode("forge")
	for frame in 3: await get_tree().process_frame
	_assert_popup_within_screen(bag)
	if "--capture" in OS.get_cmdline_user_args(): await _capture("mobile_inventory_forge")
	bag._close()
	for frame in 2: await get_tree().process_frame
	if touch_preview: assert(controls.visible, "Touch combat controls did not resume")
	assert(controller._sector_room_order.size() >= 3, "Several normal rooms required before boss")
	assert(controller._sector_chest_rooms.size() > 0 and controller._sector_chest_rooms.size() < controller._sector_total, "Each floor needs both chest and empty rooms")
	var chests_seen := 0
	var carried_loot := game.get_node("EquipmentDropSystem").spawn_treasure_drop(player.global_position + Vector2(-96, -64), "rare") as GroundEquipmentItem
	assert(carried_loot != null)
	var exit_captured := false
	for sector in range(controller._sector_total):
		if GameManager.dungeon_map.get_meta("isolated_room", false):
			assert(GameManager.dungeon_map.rooms.size() == 1)
			assert(int(GameManager.dungeon_map.get_meta("room_ordinal")) == sector)
			assert(not stage._tile_set.has_source(8), "New terrain must be reserved for a new MAP")
			for cell in GameManager.dungeon_map.get_floor_cells():
				assert(stage._tile_map_layer.get_cell_source_id(cell) == 0, "MAP1 must use its original stone floor")
			assert(is_instance_valid(carried_loot) and not carried_loot.is_queued_for_deletion(), "Leaving the room discarded earned equipment")
			assert(GameManager.dungeon_map.has_navigation_clearance(GameManager.dungeon_map.world_to_grid(carried_loot.global_position)))
			if "--capture" in OS.get_cmdline_user_args(): await _capture("isolated_room_%d" % sector)
		assert(controller._sector_index == sector and controller._sector_exit != null)
		assert(not controller._sector_exit.available, "Exit was open before all enemies died")
		var room := GameManager.dungeon_map.rooms[controller._sector_room_index]
		assert(room.has_point(GameManager.dungeon_map.world_to_grid(player.global_position)), "Player did not enter combat room")
		if sector == 0: _assert_room_sealed(controller, player)
		await _clear_sector(controller, wave)
		if sector == 0:
			await get_tree().create_timer(2.8).timeout
			assert(controller._sector_index == 0 and GameManager.active_modal_count == 0, "Old timed route popup returned after combat")
		assert(GameManager.active_modal_count == 0 and not get_tree().paused, "Clearing room opened an unwanted selection modal")
		assert(controller._sector_index == sector, "Room advanced without explicit exit interaction")
		var chest := controller._sector_chest
		if is_instance_valid(chest):
			chests_seen += 1
			assert(chest.available and not controller._sector_exit.available, "Exit must wait for the room chest")
			controller._sector_exit._on_body_entered(player)
			assert(controller._sector_exit.interact(player), "Locked exit did not respond")
			assert(controller._sector_index == sector, "Locked exit skipped unopened chest")
			chest._on_body_entered(player)
			assert(chest.interact(player), "Room chest failed to open")
			assert(controller._sector_exit.available, "Opening chest did not unlock exit")
		else:
			assert(controller._sector_exit.available, "Empty room exit did not unlock after combat")
		if "--capture" in OS.get_cmdline_user_args() and is_instance_valid(chest) and not exit_captured:
			await _capture("mobile_room_exit")
			exit_captured = true
		assert(controller._sector_index == sector, "Opening chest caused automatic room transition")
		var exit := controller._sector_exit
		exit._on_body_entered(player)
		assert(exit.interact(player), "Explicit exit interaction failed")
		for frame in 300:
			await get_tree().physics_frame
			if not controller._transitioning: break
	assert(chests_seen == controller._sector_chest_rooms.size(), "Random room chest pattern was not used")
	assert(controller._boss_unlocked and controller._boss_gate.available)
	if "--capture" in OS.get_cmdline_user_args(): await _capture("isolated_boss_room")
	assert(not wave._sector_active and wave.is_map_spawn_suppressed())
	assert(GameManager.dungeon_map.rooms[GameManager.dungeon_map.boss_room_index].has_point(GameManager.dungeon_map.world_to_grid(player.global_position)))
	controller.debug_start_boss()
	for frame in 4: await get_tree().physics_frame
	assert(controller._boss_active, "Boss room did not start boss")
	for theme in [2, 3]:
		controller._transition_to_map(theme, 1)
		for frame in 300:
			if not controller._transitioning and GameManager.current_map_index == theme:
				break
			await get_tree().process_frame
		assert(not controller._transitioning and GameManager.current_map_index == theme, "Theme transition failed")
		_assert_imported_props(stage, player)
		if "--asset-capture" in OS.get_cmdline_user_args():
			if theme == 2: await get_tree().create_timer(2.2).timeout
			await _capture_imported_props(stage, player, theme)
		assert(controller._sector_room_order.size() >= 3 and wave._sector_active, "Theme has no combat rooms")
		_assert_room_sealed(controller, player)
		await _clear_sector(controller, wave)
		if is_instance_valid(controller._sector_chest):
			assert(not controller._sector_exit.available, "Theme exit skipped chest")
			controller._sector_chest._on_body_entered(player)
			assert(controller._sector_chest.interact(player))
		assert(controller._sector_exit.available, "Theme exit remained locked")
		controller._sector_exit._on_body_entered(player)
		assert(controller._sector_exit.interact(player))
		assert(controller._transitioning, "Exit must walk through gate before changing rooms")
		for frame in 300:
			await get_tree().physics_frame
			if not controller._transitioning: break
		assert(controller._sector_index == 1 and wave._sector_active, "Theme room did not advance")
	print("SECTOR_RUNTIME_CHECK PASS: controls, imported magic/audio/props, four locked rooms, random chests, manual exits, boss, MAP2/3")
	get_tree().quit(0)

func _clear_sector(controller: MapRunController, wave: WaveSpawner) -> void:
	wave._sector_remaining = 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.get_meta("sector_wave", false): enemy.queue_free()
	for frame in 8: await get_tree().physics_frame
	assert(controller._sector_cleared, "Wave clear did not unlock the room objective")

func _assert_imported_props(stage: StageEnvironment, player: Player) -> void:
	var root := stage.get_node_or_null("ImportedRuinProps") as Node2D
	assert(root != null and int(root.get_meta("placed_count", 0)) >= 3, "Imported MAP props are missing")
	var kinds := {"rock": false, "bones": false, "ruin": false}
	var solid: StaticBody2D = null
	for child in root.get_children():
		if child is Sprite2D:
			for kind in kinds:
				if child.name.to_lower().begins_with(kind): kinds[kind] = true
		elif child is StaticBody2D and solid == null:
			solid = child as StaticBody2D
	assert(not kinds.values().has(false) and solid != null, "Rock, bone, and ruin must all appear")
	var query := PhysicsPointQueryParameters2D.new()
	query.position = solid.global_position
	query.collision_mask = 1
	var hits := player.get_world_2d().direct_space_state.intersect_point(query, 16)
	var collided := false
	for hit in hits:
		if hit.collider == solid: collided = true
	assert(collided, "The imported solid prop can be walked through")

func _capture_imported_props(stage: StageEnvironment, player: Player, theme: int) -> void:
	var original := player.global_position
	for child in stage.get_node("ImportedRuinProps").get_children():
		if child is Sprite2D and child.name.to_lower().begins_with("ruin"):
			player.global_position = child.global_position + Vector2(56, 32)
			break
	await _capture("imported_map%d_props" % theme)
	player.global_position = original

func _assert_room_sealed(controller: MapRunController, player: Player) -> void:
	var map := GameManager.dungeon_map
	var room: Rect2i = map.rooms[controller._sector_room_index]
	if map.get_meta("isolated_room", false):
		assert(map.rooms.size() == 1 and map.width <= 32, "Only the active compact room should be loaded")
		var query := PhysicsPointQueryParameters2D.new()
		query.position = map.grid_to_world(Vector2i(0, room.position.y - 1)) + Vector2(16, 16)
		query.collision_mask = 1
		assert(not player.get_world_2d().direct_space_state.intersect_point(query, 16).is_empty(), "Room perimeter wall has no collision")
		return
	var tested := false
	for side in 4:
		var horizontal := side < 2
		var count := room.size.x if horizontal else room.size.y
		var outward := Vector2i.UP if side == 0 else Vector2i.DOWN if side == 1 else Vector2i.LEFT if side == 2 else Vector2i.RIGHT
		for offset in count:
			var inside := Vector2i(room.position.x + offset, room.position.y if side == 0 else room.end.y - 1) if horizontal else Vector2i(room.position.x if side == 2 else room.end.x - 1, room.position.y + offset)
			if not map.is_floor(inside) or not map.is_floor(inside + outward): continue
			var query := PhysicsPointQueryParameters2D.new()
			query.position = (map.grid_to_world(inside) + map.grid_to_world(inside + outward)) * 0.5
			query.collision_mask = 1
			for hit in player.get_world_2d().direct_space_state.intersect_point(query, 16):
				if hit.collider.get_parent() == controller._sector_seals:
					tested = true
					break
			if tested: break
		if tested: break
	assert(tested, "The room can be left through an unsealed corridor")

func _capture(name: String) -> void:
	for frame in 3: await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var path := "res://artifacts/%s.png" % name
	print("CAPTURE %s code=%d" % [path, image.save_png(path)])

func _assert_popup_within_screen(bag: EquipmentScreen) -> void:
	var rect := bag.forge_panel.get_global_rect()
	var screen := bag.get_viewport().get_visible_rect()
	assert(rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= screen.end.x and rect.end.y <= screen.end.y, "Mobile equipment popup is clipped")
