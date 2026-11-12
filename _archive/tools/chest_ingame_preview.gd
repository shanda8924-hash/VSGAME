extends Node
func _ready() -> void:
	SaveManager.begin_ephemeral_session()
	GameManager.selected_character_id = "swordsman"
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	GameManager.start_run(true)
	game.stage_environment.build_dungeon(GameManager.dungeon_map)
	game.player.global_position = GameManager.dungeon_map.grid_to_world(GameManager.dungeon_map.spawn_point)
	for name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		game.get_node(name).process_mode = Node.PROCESS_MODE_DISABLED
	game.player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	for i in 2:
		var chest := (load("res://entities/pickups/treasure_chest.tscn") as PackedScene).instantiate()
		chest.position = game.player.position + Vector2(-90 + i*180,0)
		game.add_child(chest)
		if i == 1:
			chest._on_body_entered(game.player)
			chest.interact(game.player)
	var camera := Camera2D.new()
	camera.position = game.player.position + Vector2(0,-10)
	camera.zoom = Vector2(2.5,2.5)
	game.add_child(camera)
	camera.make_current()
	for i in 30: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/chest_ingame.png")
	get_tree().quit()
