extends Node

func _ready() -> void:
	SaveManager.begin_ephemeral_session()
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	for name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		game.get_node(name).process_mode = Node.PROCESS_MODE_DISABLED
	var player := game.get_node("Player") as Player
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	var enemy := (load("res://entities/enemies/enemy_basic.tscn") as PackedScene).instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.id = "impact_fixture"
	data.max_hp = 1000
	data.move_speed = 0
	data.attack_range = 24
	enemy.enemy_data = data
	game.add_child(enemy)
	enemy.global_position = player.global_position + Vector2(20,0)
	var scale_before := Engine.time_scale
	enemy.health_component.apply_damage(10, CombatEventMeta.create_direct("player_direct_attack"))
	assert(enemy._impact_paused)
	assert(enemy.process_mode == Node.PROCESS_MODE_DISABLED)
	assert(player.process_mode != Node.PROCESS_MODE_DISABLED and Engine.time_scale == scale_before)
	var until := enemy._impact_cooldown_until
	enemy.receive_hit_impact(CombatEventMeta.create_direct("player_direct_attack", true))
	assert(enemy._impact_cooldown_until == until)
	var hit_position := enemy.global_position
	enemy.apply_knockback(Vector2.RIGHT, 5.0)
	assert(enemy.global_position == hit_position and enemy._impact_push >= 5.0)
	await get_tree().create_timer(0.12).timeout
	assert(not enemy._impact_paused)
	enemy._impact_cooldown_until = 0
	enemy.health_component.apply_secondary_damage(1, CombatEventMeta.create_secondary("element_burning"))
	assert(not enemy._impact_paused)
	enemy._normal_attack_state = EnemyBasic.NormalAttackState.COOLDOWN
	enemy.global_position = player.global_position + Vector2(15,0)
	enemy.movement_component.direction = Vector2.LEFT
	enemy._keep_melee_spacing(1.0/60.0)
	assert(enemy.movement_component.direction == Vector2.ZERO)
	# Spacing helper never pushes either body; physical collision resolves contacts.
	var before := player.global_position
	enemy.global_position = before
	enemy._keep_melee_spacing(1.0/60.0)
	assert(enemy.global_position == before and player.global_position == before)
	enemy._impact_cooldown_until = 0
	enemy.receive_hit_impact(CombatEventMeta.create_direct("player_direct_attack", true))
	assert(enemy._impact_paused)
	enemy.health_component.current_hp = 1
	enemy.health_component.apply_secondary_damage(10, CombatEventMeta.create_secondary("element_burning"))
	assert(enemy._is_dead and not enemy._impact_paused and enemy.process_mode != Node.PROCESS_MODE_DISABLED)
	print("IMPACT_CHECK PASS: local pause/resume, player unaffected, cooldown, DOT excluded, melee spacing, no artificial spacing push")
	AudioManager.stop_all(false)
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit()
