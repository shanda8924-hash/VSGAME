extends Node
## A real Godot scene capture of the imported chest, guard and short burst VFX.

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
	var chest := (load("res://entities/pickups/treasure_chest.tscn") as PackedScene).instantiate() as TreasureChest
	chest.position = game.player.position + Vector2(-130, 0)
	game.add_child(chest)
	var boss_chest := (load("res://entities/pickups/treasure_chest.tscn") as PackedScene).instantiate() as TreasureChest
	boss_chest.configure("legendary", Color.GOLD, true)
	boss_chest.position = game.player.position + Vector2(-10, 105)
	game.add_child(boss_chest)
	var guard := (load("res://entities/enemies/enemy_basic.tscn") as PackedScene).instantiate() as EnemyBasic
	guard.enemy_data = DataLoader.enemies["shield_guard"]
	guard.position = game.player.position + Vector2(130, 0)
	game.add_child(guard)
	guard.set_room_activation_locked(true)
	var camera := Camera2D.new()
	camera.position = game.player.position + Vector2(0, -15)
	camera.zoom = Vector2(2.4, 2.4)
	game.add_child(camera)
	camera.make_current()
	for i in 20:
		await get_tree().process_frame
	guard.animation_component.play_block()
	ImportedBurstVFX.spawn(game, game.player.position + Vector2(0, -12), "dodge")
	ImportedBurstVFX.spawn(game, boss_chest.position + Vector2(0, -24), "chest")
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/new_assets_ingame.png")
	get_tree().quit()
