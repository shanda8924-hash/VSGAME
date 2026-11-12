extends Node
func _ready() -> void:
	SaveManager.begin_ephemeral_session()
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	GameManager.start_run(true)
	game.stage_environment.build_dungeon(GameManager.dungeon_map)
	game.player.global_position = GameManager.dungeon_map.grid_to_world(GameManager.dungeon_map.spawn_point)
	game.map_run_controller.begin_run()
	var wave := game.get_node("WaveSpawner") as WaveSpawner
	for frame in 900:
		await get_tree().process_frame
		if wave.exploration_placed_count > 0:
			break
	assert(wave.exploration_placed_count >= 12, "Enough finite enemies to unlock boss")
	var enemies := get_tree().get_nodes_in_group("enemies")
	var guards: Array[EnemyBasic] = []
	for enemy in enemies:
		if enemy.exploration_guard:
			guards.append(enemy)
	assert(guards.size() == wave.exploration_placed_count)
	var player := game.get_node("Player") as Player
	for guard in guards:
		assert(guard.global_position.distance_to(player.global_position) >= 300)
		assert(GameManager.dungeon_map.has_navigation_clearance(GameManager.dungeon_map.world_to_grid(guard.global_position)))
		assert(not guard.exploration_alert)
	var count := guards.size()
	for tick in 120:
		wave._process(10)
	assert(get_tree().get_nodes_in_group("enemies").size() == enemies.size(), "Waiting cannot replenish enemies")
	var guard := guards[0]
	guard.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = guard.global_position + Vector2(20,0)
	await get_tree().physics_frame
	assert(guard._update_exploration_awareness(), "Near clear line of sight activates")
	player.global_position = guard.global_position + Vector2(500,0)
	assert(not guard._update_exploration_awareness(), "Escape breaks pursuit")
	guard.queue_free()
	await get_tree().process_frame
	wave._process(100)
	wave._populate_exploration_map()
	assert(get_tree().get_nodes_in_group("enemies").size() == enemies.size()-1, "Cleared enemies stay cleared")
	assert(DataLoader.characters["swordsman"].base_damage == 7.0)
	print("EXPLORATION PASS: ",count," finite guards, safe cells, idle, aggro, escape, no refill, low base damage")
	get_tree().quit()

