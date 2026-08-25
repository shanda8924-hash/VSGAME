extends Node

const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")

var failures: Array[String] = []
var damage_events: Array[Dictionary] = []

func _ready() -> void:
	var combat := ElementCombatSystem.new()
	add_child(combat)
	await get_tree().process_frame
	EventBus.element_damage_dealt.connect(_on_damage)

	var targets := await _prepare_targets("plasma")
	for _rank in 3:
		GameManager.add_fragment("fire")
	for _rank in 3:
		GameManager.add_fragment("lightning")
	combat.apply_element_damage(targets[0].hurtbox_component, 100.0, Vector2.ZERO)
	var snapshot := combat.get_fusion_debug_snapshot()
	_check(int(snapshot.get("plasma_cores", 0)) >= 2, "Plasma leaves Overcharge cores on chained enemies")
	await get_tree().create_timer(0.58, true, false, true).timeout
	_check(damage_events.any(func(event): return event["element_id"] == "element_fire" and Vector2(event["position"]).x >= 240.0), "Plasma chain destinations inherit Fire burn/AoE grammar")

	combat.reset_runtime()
	targets = await _prepare_targets("radiant")
	for _rank in 3:
		GameManager.add_fragment("lightning")
	for _rank in 3:
		GameManager.add_fragment("light")
	damage_events.clear()
	combat.apply_element_damage(targets[0].hurtbox_component, 100.0, Vector2.ZERO)
	snapshot = combat.get_fusion_debug_snapshot()
	_check(int(snapshot.get("afterglow_segments", 0)) >= 2, "Radiant Arc preserves chained paths as short afterglow segments")
	await get_tree().create_timer(0.42, true, false, true).timeout
	snapshot = combat.get_fusion_debug_snapshot()
	_check(int(snapshot.get("afterglow_segments", -1)) == 0, "Radiant Arc afterglow resolves and leaves no segment state")
	_check(damage_events.any(func(event): return event["element_id"] == "fusion_judgment"), "Radiant Arc residual lines deal non-recursive Fusion damage")

	for failure in failures:
		push_error(failure)
	print("FUSION_CHAIN_GRAMMAR_CHECK failures=%d" % failures.size())
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	combat.queue_free()
	await _clear_enemies()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _prepare_targets(prefix: String) -> Array[EnemyBasic]:
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	await _clear_enemies()
	var targets: Array[EnemyBasic] = []
	for index in 6:
		targets.append(_spawn_enemy(Vector2(100.0 + index * 140.0, 100.0), "%s_%d" % [prefix, index]))
	return targets

func _spawn_enemy(position: Vector2, id: String) -> EnemyBasic:
	var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.id = id
	data.display_name = "Fusion Chain Grammar Target"
	data.max_hp = 1000000000.0
	data.move_speed = 0.0
	data.contact_damage = 0.0
	data.attack_interval = 99.0
	data.attack_windup = 99.0
	enemy.enemy_data = data
	add_child(enemy)
	enemy.global_position = position
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	return enemy

func _clear_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame

func _on_damage(amount: float, position: Vector2, element_id: String, stack: int, chain: int) -> void:
	damage_events.append({"amount": amount, "position": position, "element_id": element_id, "stack": stack, "chain": chain})

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
