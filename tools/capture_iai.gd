extends Node
## 居合の実画面：構え → 斬り抜け途中 → 終わり。敵を進路上へ置いて命中演出も撮る。
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	DirAccess.make_dir_recursive_absolute("res://artifacts/iai")
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
	var world := GameManager.get_runtime_world(player)
	var enemy_data: EnemyData = DataLoader.enemies.values()[0]
	for index in 3:
		var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
		enemy.enemy_data = enemy_data
		world.add_child(enemy)
		enemy.global_position = player.global_position + Vector2(70 + index * 50, (index - 1) * 12)
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
	for frame in 6:
		await get_tree().process_frame
	await capture("iai_0_idle")
	player.face_direction(Vector2.RIGHT)
	player.active_skill_component.try_activate()
	await get_tree().create_timer(0.08).timeout
	await capture("iai_1_windup")
	await get_tree().create_timer(0.14).timeout
	await capture("iai_2_dash")
	await get_tree().create_timer(0.12).timeout
	await capture("iai_3_late")
	await get_tree().create_timer(0.35).timeout
	await capture("iai_4_after")
	AudioManager.stop_all(false)
	get_tree().quit()

func capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/iai/%s.png" % filename)
