extends Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	GameManager.selected_character_id = "swordsman"
	_run.call_deferred()

func _run() -> void:
	var map_config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/exploration_run.json"))
	for theme in [1, 2, 3]:
		var entry: Dictionary = map_config.maps[theme - 1]
		for floor_index in [1, 10, 20]:
			for sample in 5:
				var rng := RandomNumberGenerator.new()
				rng.seed = 62000 + theme * 1000 + floor_index * 10 + sample
				var map := DungeonGenerator.generate(int(entry.width), int(entry.height), int(entry.room_count),0,rng,true)
				assert(DungeonGenerator.validate_reachability(map).get("reachable", false), "Unreachable floor")
				assert(map.rooms.size() >= 4, "Too few wide rooms")
				assert(map.get_meta("survival_layout", false))
				assert(map.has_navigation_clearance(map.rooms[map.boss_room_index].get_center()))
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	var controller := game.get_node("MapRunController") as MapRunController
	var stage := game.get_node("StageEnvironment") as StageEnvironment
	var player := game.get_node("Player") as Player
	var wave := game.get_node("WaveSpawner") as WaveSpawner
	var boss := game.get_node("BossSpawner") as BossSpawner
	var shop := game.get_node("ShopScreen") as ShopScreen
	GameManager.map_mode_active = true
	GameManager.current_floor_index = 1
	GameManager.current_depth = 1
	GameManager.generate_exploration_map(1)
	await stage.build_dungeon_async(GameManager.dungeon_map, 5)
	player.position = GameManager.dungeon_map.grid_to_world(GameManager.dungeon_map.spawn_point)
	player.health_component.max_hp = 1000000.0
	player.health_component.current_hp = 1000000.0
	controller.begin_run()
	await _wait_encounters(wave)
	assert(wave._map_enemy_cap == 64 and wave.exploration_placed_count == 0, "First floor must use timed horde")
	var shop_system := game.get_node("ShopSystem") as ShopSystem
	shop_system.begin_visit(1)
	var first_stock := shop_system.get_stock()
	for product in first_stock:
		if String(product.get("category")) == "generic": assert(int(product.get("price")) <= 60, "First boss could not afford a generic upgrade after five kills")
	assert(shop_system.get_reroll_cost() == 25, "Early reroll remains too expensive")
	await _defeat_boss_and_descend(controller, boss, shop, player, 1, 1, 1, 2)
	await _switch_to(controller, 1, 20)
	await _wait_encounters(wave)
	assert(wave._map_enemy_cap > 64, "Floor 20 must allow more enemies")
	assert(float(controller._current_config.get("enemy_hp_multiplier")) > 0.38)
	var count_20 := wave._map_enemy_cap
	var hp_20 := float(controller._current_config.get("enemy_hp_multiplier"))
	await _defeat_boss_and_descend(controller, boss, shop, player, 1, 20, 2, 1)
	await _wait_encounters(wave)
	assert(wave._map_enemy_cap >= count_20, "MAP2 first floor lost enemy density")
	assert(float(controller._current_config.get("enemy_hp_multiplier")) >= hp_20, "MAP2 first floor got weaker")
	await _switch_to(controller, 2, 20)
	await _wait_encounters(wave)
	var count_40 := wave._map_enemy_cap
	var hp_40 := float(controller._current_config.get("enemy_hp_multiplier"))
	await _defeat_boss_and_descend(controller, boss, shop, player, 2, 20, 3, 1)
	await _wait_encounters(wave)
	assert(wave._map_enemy_cap >= count_40, "MAP3 first floor lost enemy density")
	assert(float(controller._current_config.get("enemy_hp_multiplier")) >= hp_40, "MAP3 first floor got weaker")
	await _switch_to(controller, 3, 20)
	await _wait_encounters(wave)
	await _defeat_boss_and_descend(controller, boss, shop, player, 3, 20, 3, 20)
	for frame in 30:
		if GameManager.run_state == GameManager.RunState.RESULT: break
		await get_tree().process_frame
	print("FLOOR60 state=", GameManager.run_state, " depth=", GameManager.current_depth, " active=", controller._active, " pending=", controller._boss_reward_pending, " shop=", shop.visible)
	assert(GameManager.run_state == GameManager.RunState.RESULT, "Floor 60 did not clear run")
	var merge := EquipmentMergeSystem.new()
	for rarity in ["uncommon", "rare", "epic", "legendary"]:
		assert(EquipmentMergeSystem.required_count(rarity) == 3, "Merge count not three: " + rarity)
	print("FLOOR_RUN_CHECK PASS: 45 geometry seeds; 1->2, 20->21, 40->41, 60->clear; chest/stairs/shop and three-item merges")
	get_tree().quit()

func _defeat_boss_and_descend(controller: MapRunController, boss: BossSpawner, shop: ShopScreen, player: Player, expected_theme: int, expected_floor: int, next_theme: int, next_floor: int) -> void:
	assert(GameManager.current_map_index == expected_theme and GameManager.current_floor_index == expected_floor)
	if GameManager.dungeon_map.get_meta("isolated_room", false):
		await controller._load_isolated_room(controller._sector_total)
	controller._boss_unlocked = true
	controller._boss_gate.set_available(true)
	controller.debug_start_boss()
	for frame in 5: await get_tree().physics_frame
	assert(is_instance_valid(boss.debug_get_current_boss()), "Boss missing")
	boss.debug_defeat_current_boss()
	for frame in 8: await get_tree().physics_frame
	await _close_reward_modals(controller.get_parent())
	var chest := controller._boss_chest
	var stairs := controller._stairs
	assert(is_instance_valid(chest) and is_instance_valid(stairs), "Chest/stairs missing")
	assert(not stairs.available, "Stairs should wait for boss chest")
	assert(chest.global_position.distance_to(stairs.global_position) >= 96.0, "Chest overlaps stairs")
	assert(not shop.visible, "Boss death prematurely opened shop")
	chest._on_body_entered(player)
	assert(chest.interact(player), "Boss chest could not open")
	for frame in 5: await get_tree().physics_frame
	await _close_reward_modals(controller.get_parent())
	assert(stairs.available and not controller._boss_reward_pending, "Chest failed to unlock stairs")
	assert(not shop.visible and GameManager.current_map_index == expected_theme and GameManager.current_floor_index == expected_floor, "Chest prematurely descended")
	stairs._on_body_entered(player)
	assert(stairs.interact(player), "Stairs could not descend")
	for frame in 30:
		if shop.visible or (expected_theme == 3 and expected_floor == 20): break
		await get_tree().process_frame
	if expected_theme == 3 and expected_floor == 20:
		return
	assert(shop.visible, "Boss shop did not open after stairs")
	shop.debug_close_shop()
	for frame in 300:
		if not controller._transitioning and GameManager.current_map_index == next_theme and GameManager.current_floor_index == next_floor:
			return
		await get_tree().process_frame
	assert(false, "Did not reach next floor")

func _switch_to(controller: MapRunController, theme: int, floor_index: int) -> void:
	controller._transition_to_map(theme, floor_index)
	for frame in 300:
		if not controller._transitioning and GameManager.current_map_index == theme and GameManager.current_floor_index == floor_index:
			return
		await get_tree().process_frame
	assert(false, "Direct test floor transition failed")

func _wait_encounters(wave: WaveSpawner) -> void:
	for frame in 160:
		if wave.encounters_ready:
			return
		await get_tree().physics_frame
	assert(false, "Encounter placement did not finish")

func _close_reward_modals(game: Node) -> void:
	for attempt in 15:
		var handled := false
		for ui_name in ["LevelUpSelect", "ConceptSelect", "ItemSelect"]:
			var ui := game.get_node_or_null(ui_name) as CanvasLayer
			if ui == null or not ui.visible: continue
			for node in ui.find_children("*", "Button", true, false):
				var button := node as Button
				if button and button.visible and not button.disabled:
					button.emit_signal("pressed")
					handled = true
					break
			if handled: break
		if not handled: return
		for frame in 3: await get_tree().process_frame
