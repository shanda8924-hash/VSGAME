extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")

var failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameManager.selected_character_id = "swordsman"
	var game := GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().physics_frame
	_disable_automatic_systems(game)
	await _clear_enemies()
	var player := game.get_node("Player") as Player
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	var combat := game.get_node("ElementCombatSystem") as ElementCombatSystem
	GameManager.debug_force_element_state({"element_fire": 3})

	await _check_reentrant_burn_death_aoe(game, player, combat)
	await _check_expiry_and_reset_disconnect(game, player, combat)
	await _check_freed_target_cleanup(game, player, combat)

	for failure in failures:
		push_error(failure)
	print("BURN_LIFECYCLE_CHECK failures=%d burning=%d connections=%d" % [failures.size(), combat._burning_targets.size(), combat._burn_death_connections.size()])
	combat.reset_runtime()
	game.queue_free()
	GameManager.debug_force_element_state({})
	await get_tree().process_frame
	await get_tree().process_frame
	AudioManager.stop_all()
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_reentrant_burn_death_aoe(game: Node, player: Player, combat: ElementCombatSystem) -> void:
	combat.reset_runtime()
	var targets: Array[EnemyBasic] = []
	for index in 4:
		targets.append(_spawn_enemy(game, player.global_position + Vector2(56 + index * 18, 0), "burn_race_%d" % index, 20.0))
	for target in targets:
		combat._apply_fire_role(target, target.health_component, 100.0, 1.0, 3)
		var id := target.get_instance_id()
		var entry: Dictionary = combat._burning_targets.get(id, {})
		entry["tick_timer"] = 0.0
		entry["tick_damage"] = 50.0
		combat._burning_targets[id] = entry
	await get_tree().process_frame
	await get_tree().process_frame
	_check(targets.all(func(target): return target.health_component.current_hp <= 0.0), "one Burn tick death AoE can defeat multiple marked enemies")
	_check(combat._burning_targets.is_empty(), "reentrant Burn death callbacks leave no stale target IDs")
	_check(combat._burn_death_connections.is_empty(), "reentrant Burn death callbacks leave no stale Signal ownership")

func _check_expiry_and_reset_disconnect(game: Node, player: Player, combat: ElementCombatSystem) -> void:
	combat.reset_runtime()
	var target := _spawn_enemy(game, player.global_position + Vector2(90, 40), "burn_expiry", 1000000.0)
	var baseline_connections := target.health_component.died.get_connections().size()
	combat._apply_fire_role(target, target.health_component, 1.0, 1.0, 3)
	_check(target.health_component.died.get_connections().size() == baseline_connections + 1, "one active Lv3 Burn owns one death callback")
	var id := target.get_instance_id()
	var entry: Dictionary = combat._burning_targets.get(id, {})
	entry["remaining"] = 0.0
	combat._burning_targets[id] = entry
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not combat._burning_targets.has(id), "expired Burn retires its target data")
	_check(target.health_component.died.get_connections().size() == baseline_connections, "expired Burn disconnects its obsolete death callback")
	for _iteration in 4:
		combat._apply_fire_role(target, target.health_component, 1.0, 1.0, 3)
		entry = combat._burning_targets.get(id, {})
		entry["remaining"] = 0.0
		combat._burning_targets[id] = entry
		await get_tree().process_frame
	_check(target.health_component.died.get_connections().size() == baseline_connections, "repeated Burn expiry does not accumulate duplicate callbacks")
	combat._apply_fire_role(target, target.health_component, 1.0, 1.0, 3)
	combat.reset_runtime()
	_check(combat._burning_targets.is_empty() and combat._burn_death_connections.is_empty(), "runtime reset clears Burn data and Signal ownership")
	_check(target.health_component.died.get_connections().size() == baseline_connections, "runtime reset disconnects the active Burn callback")
	target.queue_free()
	await get_tree().process_frame

func _check_freed_target_cleanup(game: Node, player: Player, combat: ElementCombatSystem) -> void:
	combat.reset_runtime()
	var target := _spawn_enemy(game, player.global_position + Vector2(130, -40), "burn_freed", 1000000.0)
	var id := target.get_instance_id()
	combat._apply_fire_role(target, target.health_component, 1.0, 1.0, 3)
	target.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not combat._burning_targets.has(id), "queue-freed Burn target retires without reading a freed HealthComponent")
	_check(not combat._burn_death_connections.has(id), "queue-freed Burn target leaves no callback record")

func _spawn_enemy(game: Node, position: Vector2, enemy_id: String, max_hp: float) -> EnemyBasic:
	var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.id = enemy_id
	data.display_name = enemy_id
	data.max_hp = max_hp
	data.move_speed = 0.0
	data.contact_damage = 0.0
	data.attack_range = 0.0
	data.attack_interval = 99.0
	data.attack_windup = 99.0
	data.sprite_folder = "enemies/Orc"
	enemy.enemy_data = data
	game.add_child(enemy)
	enemy.global_position = position
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	return enemy

func _disable_automatic_systems(game: Node) -> void:
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		var node := game.get_node_or_null(node_name)
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED

func _clear_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
