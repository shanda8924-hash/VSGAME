extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")
const ELEMENTS := ["fire", "ice", "lightning", "light", "dark"]
var failures: Array[String] = []
var measured: Dictionary = {}

func _ready() -> void:
	GameManager.selected_character_id = "swordsman"
	var game := GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		var node := game.get_node_or_null(node_name)
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	await _clear_enemies()
	var combat := game.get_node("ElementCombatSystem") as ElementCombatSystem
	var player := game.get_node("Player") as Player
	for fragment_id in ELEMENTS:
		var values: Array[float] = []
		for level in range(1, 4):
			GameManager.set_active_element(GameManager.ELEMENT_NONE)
			combat.reset_runtime()
			for _rank in level:
				GameManager.add_fragment(fragment_id)
			var enemy := _spawn_enemy(game, player.global_position + Vector2(100, 0), "%s_%d" % [fragment_id, level])
			var result := combat.apply_element_damage(enemy.hurtbox_component, 100.0, player.global_position)
			values.append(float(result["total_damage"]))
			enemy.queue_free()
			await get_tree().process_frame
		measured[fragment_id] = values
		_check(values[0] < values[1] and values[1] < values[2], "%s direct damage rises Lv1 < Lv2 < Lv3" % fragment_id)
		_check(values[2] >= values[0] * 2.95, "%s Lv3 is approximately three times Lv1" % fragment_id)
		_check(values[1] >= values[0] * 1.70, "%s Lv2 is approximately 1.75 times Lv1" % fragment_id)
	for failure in failures:
		push_error(failure)
	print("ELEMENT_DAMAGE_SCALING_CHECK failures=%d measured=%s" % [failures.size(), measured])
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	AudioManager.stop_all()
	await get_tree().create_timer(0.2, true, false, true).timeout
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _spawn_enemy(game: Node, position: Vector2, id: String) -> EnemyBasic:
	var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.id = id
	data.display_name = "Scaling Target"
	data.max_hp = 10000.0
	data.move_speed = 0.0
	data.contact_damage = 0.0
	data.attack_interval = 99.0
	data.attack_windup = 99.0
	enemy.enemy_data = data
	game.add_child(enemy)
	enemy.global_position = position
	return enemy

func _clear_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
