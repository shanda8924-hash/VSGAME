extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")

var failures: Array[String] = []
var _attack_events := 0
var _damage_events := 0
var _element_damage_events := 0
var _combat_nodes_added := 0
var _feedback_events: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run_checks()
	for failure in failures:
		push_error(failure)
	print("ELEMENT_LEVEL_NO_ATTACK_CHECK failures=%d feedback=%d" % [failures.size(), _feedback_events.size()])
	AudioManager.stop_all()
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func _run_checks() -> void:
	GameManager.selected_character_id = "swordsman"
	var game := GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	_disable_background(game)
	await _remove_enemies()
	var player := game.get_node("Player") as Player
	var manager := game.get_node("AttackVFXManager") as AttackVFXManager
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	player.weapon_manager.weapon_fired.connect(func(): _attack_events += 1)
	manager.element_level_feedback_spawned.connect(_on_feedback)
	EventBus.damage_dealt.connect(_on_damage)
	EventBus.element_damage_dealt.connect(_on_element_damage)
	get_tree().node_added.connect(_on_node_added)
	var enemy := _spawn_enemy(game, player)
	await get_tree().physics_frame
	var initial_hp := enemy.health_component.current_hp

	for entry in [["light", "element_light"], ["dark", "element_dark"]]:
		GameManager.set_active_element(GameManager.ELEMENT_NONE)
		GameManager.held_fragment_ids.clear()
		_feedback_events.clear()
		_attack_events = 0
		_damage_events = 0
		_element_damage_events = 0
		_combat_nodes_added = 0
		var projectiles_before := _count_type(game, "Projectile")
		var weapons_before := player.weapon_manager.get_weapon_instances().size()
		for expected_level in range(1, 4):
			var feedback_before := _feedback_events.size()
			GameManager.add_fragment(entry[0])
			await get_tree().create_timer(0.05, true, false, true).timeout
			_check(GameManager.get_element_stack(entry[1]) == expected_level, "%s reaches Lv%d" % [entry[0], expected_level])
			_check(_count_type(game, "Projectile") == projectiles_before, "%s Lv%d creates no Projectile" % [entry[0], expected_level])
			_check(player.weapon_manager.get_weapon_instances().size() == weapons_before, "%s Lv%d creates no WeaponInstance" % [entry[0], expected_level])
			_check(_attack_events == 0, "%s Lv%d fires no attack event" % [entry[0], expected_level])
			_check(_damage_events == 0 and _element_damage_events == 0, "%s Lv%d emits no damage event" % [entry[0], expected_level])
			_check(is_equal_approx(enemy.health_component.current_hp, initial_hp), "%s Lv%d does not damage a nearby enemy" % [entry[0], expected_level])
			_check(_combat_nodes_added == 0, "%s Lv%d adds no Hitbox/MeleeHit/Projectile" % [entry[0], expected_level])
			var expected_feedback_delta := 0 if expected_level == 1 else 1
			_check(_feedback_events.size() - feedback_before == expected_feedback_delta, "%s Lv%d emits only the expected visual feedback" % [entry[0], expected_level])
			if expected_level >= 2 and not _feedback_events.is_empty():
				_check_feedback(_feedback_events.back()["effect"] as Node2D, entry[0], expected_level)

	get_tree().node_added.disconnect(_on_node_added)
	EventBus.damage_dealt.disconnect(_on_damage)
	EventBus.element_damage_dealt.disconnect(_on_element_damage)
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	GameManager.held_fragment_ids.clear()
	game.queue_free()
	await get_tree().process_frame

func _check_feedback(effect: Node2D, element_name: String, level: int) -> void:
	_check(effect != null and is_instance_valid(effect), "%s Lv%d feedback exists" % [element_name, level])
	if effect == null or not is_instance_valid(effect):
		return
	_check(bool(effect.get_meta("visual_only", false)), "%s Lv%d feedback is marked visual-only" % [element_name, level])
	_check(_count_type(effect, "Projectile") == 0 and _count_type(effect, "MeleeHit") == 0, "%s Lv%d feedback contains no attack object" % [element_name, level])
	_check(_count_collision_nodes(effect) == 0, "%s Lv%d feedback contains no collision/attack area" % [element_name, level])
	var burst := effect.get_node_or_null("LevelBurstParticles") as CPUParticles2D
	_check(burst != null and burst.initial_velocity_max <= 17.0, "%s Lv%d feedback particles remain local" % [element_name, level])

func _disable_background(game: Node) -> void:
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		var node := game.get_node_or_null(node_name)
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED

func _remove_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame

func _spawn_enemy(game: Node, player: Player) -> EnemyBasic:
	var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.id = "element_level_no_attack_target"
	data.display_name = "No Attack Target"
	data.max_hp = 5000.0
	data.move_speed = 0.0
	data.contact_damage = 0.0
	data.attack_range = 0.0
	data.attack_interval = 99.0
	data.attack_windup = 99.0
	data.sprite_folder = "enemies/Orc"
	enemy.enemy_data = data
	game.add_child(enemy)
	enemy.global_position = player.global_position + Vector2(44, 0)
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	return enemy

func _on_feedback(element_id: String, level: int, effect: Node2D) -> void:
	_feedback_events.append({"element_id": element_id, "level": level, "effect": effect})

func _on_damage(_amount: float, _position: Vector2, _critical: bool) -> void:
	_damage_events += 1

func _on_element_damage(_amount: float, _position: Vector2, _element_id: String, _stack: int, _chain: int) -> void:
	_element_damage_events += 1

func _on_node_added(node: Node) -> void:
	if node is Projectile or node is MeleeHit or node is HitboxComponent:
		_combat_nodes_added += 1

func _count_type(root: Node, type_name: String) -> int:
	var count := 1 if root.is_class(type_name) else 0
	for child in root.get_children():
		count += _count_type(child, type_name)
	return count

func _count_collision_nodes(root: Node) -> int:
	var count := 1 if root is CollisionObject2D or root is CollisionShape2D else 0
	for child in root.get_children():
		count += _count_collision_nodes(child)
	return count

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
