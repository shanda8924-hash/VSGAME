extends Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	GameManager.selected_character_id = "swordsman"
	_run.call_deferred()

func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	for name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		game.get_node(name).process_mode = Node.PROCESS_MODE_DISABLED
	var player := game.get_node("Player") as Player
	var manager := player.weapon_manager
	var strikes := 0
	manager.animation_strike_resolved.connect(func(_anim, _frame): strikes += 1)
	await get_tree().create_timer(1.0, true).timeout
	Input.action_press("primary_attack")
	for frame in 80:
		if manager._class_attack_in_progress: break
		await get_tree().process_frame
	assert(manager._class_attack_in_progress, "Sword motion did not start")
	var before := strikes
	assert(player.try_dodge(), "K did not cancel J attack")
	Input.action_release("primary_attack")
	assert(not manager._class_attack_in_progress and manager._sword_pending.is_empty(), "Canceled sword still armed")
	await get_tree().create_timer(0.6, true).timeout
	assert(strikes == before, "Canceled attack landed late strike")
	player.dodge_remaining = 0.0
	player.dodge_cooldown = 0.0
	var enemy := (load("res://entities/enemies/enemy_basic.tscn") as PackedScene).instantiate() as EnemyBasic
	enemy.enemy_data = DataLoader.enemies.get("basic_enemy")
	enemy.position = player.position + Vector2(42.0, 0.0)
	game.add_child(enemy)
	await get_tree().physics_frame
	enemy.ai_component.target = player
	enemy._normal_attack_state = EnemyBasic.NormalAttackState.WINDUP
	enemy._normal_attack_timer = 0.08
	assert(player.try_dodge(), "Perfect-window K failed")
	assert(is_equal_approx(Engine.time_scale, 1.0), "Perfect dodge still slows the player/world")
	assert(player._counter_ready_until > Time.get_ticks_msec(), "J counter window did not open")
	var effects := game.get_node("ScreenEffects") as ScreenEffects
	effects.hit_stop(0.08)
	assert(is_equal_approx(Engine.time_scale, 0.05), "Hit stop did not apply")
	await get_tree().create_timer(0.16, true, false, true).timeout
	assert(is_equal_approx(Engine.time_scale, 1.0), "Hit stop did not restore normal speed")
	player.dodge_remaining = 0.0
	Input.action_press("primary_attack")
	player._process(0.0)
	Input.action_release("primary_attack")
	assert(player._counter_returning, "First J did not start side return")
	await get_tree().create_timer(0.28, true, false, true).timeout
	assert(not player._counter_returning, "Counter return did not finish")
	assert(manager._counter_haste_until > Time.get_ticks_msec(), "J attack-speed window did not begin")
	assert(manager.get_melee_attack_interval_multiplier() < manager.get_attack_interval_multiplier(), "J was not accelerated")
	manager.counter_strikes_remaining = 1
	assert(is_equal_approx(manager.consume_counter_bonus(), 1.35), "Counter strike did not gain damage")
	assert(is_equal_approx(manager.consume_counter_bonus(), 1.0), "Counter bonus applied twice")
	enemy.queue_free()
	player.dodge_remaining = 0.0
	player.dodge_cooldown = 0.0
	var strong_enemy := (load("res://entities/enemies/enemy_basic.tscn") as PackedScene).instantiate() as EnemyBasic
	strong_enemy.enemy_data = DataLoader.enemies.get("basic_enemy")
	strong_enemy.position = player.position + Vector2(48.0, 0.0)
	game.add_child(strong_enemy)
	await get_tree().physics_frame
	strong_enemy.ai_component.target = player
	var strong_move := (load("res://systems/orc_step_slash.gd") as GDScript).new() as Node2D
	strong_enemy.add_child(strong_move)
	strong_move.call("setup", strong_enemy)
	strong_enemy.strong_attack = strong_move
	var lane_clear := false
	for offset in [Vector2(48, 0), Vector2(-48, 0), Vector2(0, 48), Vector2(0, -48), Vector2(30, 30), Vector2(-30, -30)]:
		strong_enemy.global_position = player.global_position + offset
		await get_tree().physics_frame
		if bool(strong_move.call("_clear_path", player)):
			lane_clear = true
			break
	assert(lane_clear, "Strong-special fixture lacks a clear hit lane")
	strong_enemy.ai_component.target = player
	strong_move.set("active", true)
	strong_move.set("elapsed", 0.55)
	assert(player._has_precise_attack_window(), "Strong special did not open its actual hit-frame dodge window")
	strong_move.set("elapsed", 0.30)
	assert(not player._has_precise_attack_window(), "Strong-special dodge window opened too early")
	strong_move.set("direction", strong_enemy.global_position.direction_to(player.global_position))
	var hp_before_special := player.health_component.current_hp
	strong_move.call("_resolve_hit")
	assert(player.health_component.current_hp < hp_before_special, "Strong special attack ray still blocks an unobstructed hit")
	strong_enemy.queue_free()
	var skill := DataLoader.characters.get("swordsman") as CharacterData
	assert(float(skill.active_skill_params.get("damage_multiplier")) == 2.0, "L remains overpowered")
	var drops := game.get_node("EquipmentDropSystem") as EquipmentDropSystem
	var equipment := player.equipment_component
	var item: EquipmentData
	for template in drops.debug_get_templates():
		if template.slot == "weapon":
			item = drops.debug_generate_equipment(template.id, template.rarity)
			break
	assert(item != null and equipment.add_item(item), "No inventory item")
	var screen := game.get_node("EquipmentScreen") as EquipmentScreen
	screen._open()
	var double_click := InputEventMouseButton.new()
	double_click.button_index = MOUSE_BUTTON_LEFT
	double_click.pressed = true
	double_click.double_click = true
	screen._on_equipment_double_click(double_click, item, "")
	for frame in 3: await get_tree().process_frame
	assert(equipment.is_equipped(item), "Double click did not equip")
	screen._on_equipment_double_click(double_click, item, "")
	for frame in 3: await get_tree().process_frame
	assert(not equipment.is_equipped(item), "Double click did not unequip")
	screen._close()
	player.dodge_remaining = 0.0
	player.dodge_cooldown = 0.0
	var knight_data := DataLoader.characters.get("knight") as CharacterData
	var dash_attack := ChargeDashAttack.new()
	dash_attack.ability_level = 5
	manager._class_attack = dash_attack
	var original_speed := player.movement_component.base_speed
	dash_attack.execute(player, knight_data, manager)
	for frame in 30:
		if player._movement_locked_by_attack: break
		await get_tree().physics_frame
	assert(player._movement_locked_by_attack, "Knight dash did not lock movement")
	assert(player.try_dodge(), "K could not cancel knight J dash")
	for frame in 4: await get_tree().physics_frame
	assert(not player._movement_locked_by_attack and is_equal_approx(player.movement_component.base_speed, original_speed), "Knight dash remained locked or fast after K")
	await get_tree().create_timer(0.45, true, false, true).timeout
	assert(not player._movement_locked_by_attack, "Knight dash restarted after K cancellation")
	player.dodge_remaining = 0.0
	player.dodge_cooldown = 0.0
	player.set_movement_locked(true)
	assert(not player.try_dodge(), "K bypassed a non-attack movement lock")
	player.set_movement_locked(false)
	print("DODGE_COUNTER_INVENTORY PASS: cancel no late hits, J side return/haste, L balance, double-click equip/unequip")
	get_tree().quit()
