extends Node
var hits := 0
var strokes := 0
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	GameManager.selected_character_id = "swordsman"
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	await get_tree().process_frame
	for name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		game.get_node(name).process_mode = Node.PROCESS_MODE_DISABLED
	var player := game.get_node("Player") as Player
	var manager := player.weapon_manager
	var enemy := (load("res://entities/enemies/enemy_basic.tscn") as PackedScene).instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.max_hp = 1000
	data.move_speed = 0
	data.contact_damage = 0
	enemy.enemy_data = data
	enemy.position = player.position + Vector2(65,0)
	game.add_child(enemy)
	enemy._normal_attack_state = EnemyBasic.NormalAttackState.COOLDOWN
	enemy._normal_attack_timer = 1000
	var origin := enemy.position
	for i in 180:
		player.move_and_collide(Vector2(3,0))
		await get_tree().physics_frame
	assert(enemy.position.distance_to(origin) < 0.2, "Walking must not push enemy")
	assert(player.position.distance_to(enemy.position) >= 39, "Walking must stop at body")
	enemy.health_component.damaged.connect(func(_a,_b,_c): hits += 1)
	manager.animation_strike_resolved.connect(func(_a,_b): strokes += 1)
	for variant in [1,2,3]:
		player.position = origin - Vector2(48,0)
		enemy.position = origin
		enemy._impact_push = 0
		enemy._impact_recovery = 0
		player.face_direction(Vector2.RIGHT)
		hits = 0
		strokes = 0
		manager.debug_next_sword_variant = variant
		manager._start_melee_attack(player)
		if variant == 3:
			await get_tree().create_timer(0.15).timeout
			GameManager.open_modal()
			var stopped_frame := player.animated_sprite.frame
			await get_tree().create_timer(0.5,true).timeout
			assert(player.animated_sprite.frame == stopped_frame)
			GameManager.close_modal()
		await get_tree().create_timer(1.1).timeout
		print("STRIKES variant=",variant," events=",strokes," damage=",hits)
		assert(hits == [1,3,4][variant-1] and strokes == hits, "Visible strikes must each damage exactly once")
	var chest := (load("res://entities/pickups/treasure_chest.tscn") as PackedScene).instantiate()
	game.add_child(chest)
	chest.position = player.position + Vector2(0,65)
	assert(chest.CHEST_SHEET.get_width() == 160 and chest.CHEST_SHEET.get_height() == 192 and chest.has_node("ChestBody"))
	assert(chest._source_region().size == Vector2(20,19))
	assert(chest.CHEST_SHEET.get_image().get_pixel(0,0).a == 0)
	chest._on_body_entered(player)
	assert(chest.interact(player) and chest.is_opened)
	assert(chest._source_region().size == Vector2(20,24))
	assert(not chest.interact(player), "Reward only once")
	var guard := (load("res://entities/enemies/enemy_basic.tscn") as PackedScene).instantiate() as EnemyBasic
	guard.enemy_data = DataLoader.enemies["shield_guard"]
	guard.position = player.position + Vector2(300, 0)
	game.add_child(guard)
	assert(guard.animated_sprite.sprite_frames.has_animation("block"), "Shield guard block frames were not loaded")
	var hp_before := guard.health_component.current_hp
	guard.health_component.apply_damage(10.0, CombatEventMeta.create_direct("player_direct_attack"))
	assert(is_equal_approx(guard.health_component.current_hp, hp_before - 8.0), "Shield guard must reduce damage by 20%")
	assert(guard.animated_sprite.animation == "block", "Shield guard must show its block motion")
	ImportedBurstVFX.spawn(game, player.global_position, "dodge")
	assert(game.get_node_or_null("ImportedBurst_dodge") != null, "Perfect dodge cue was not spawned")
	var boss_chest := (load("res://entities/pickups/treasure_chest.tscn") as PackedScene).instantiate() as TreasureChest
	boss_chest.configure("legendary", Color.GOLD, true)
	game.add_child(boss_chest)
	boss_chest._on_body_entered(player)
	assert(boss_chest.interact(player) and boss_chest._source_region().position.y >= 160.0)
	assert(game.get_node_or_null("ImportedBurst_chest") != null, "Boss chest burst was not spawned")
	print("CHEST_STRIKES PASS: original combat, imported chest, shield guard and both imported VFX")
	get_tree().quit()


