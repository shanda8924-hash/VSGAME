extends Node

const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")
const MATRIX := [
	["fire", "ice", "frostfire"], ["fire", "lightning", "plasma"], ["fire", "light", "solar"], ["fire", "dark", "inferno"],
	["ice", "lightning", "superconductor"], ["ice", "light", "aurora"], ["ice", "dark", "void_frost"],
	["lightning", "light", "judgment"], ["lightning", "dark", "voidstorm"], ["light", "dark", "eclipse"],
]
var failures: Array[String] = []
var events: Array[Dictionary] = []

func _ready() -> void:
	var combat := ElementCombatSystem.new()
	add_child(combat)
	await get_tree().process_frame
	(combat.get_node("FusionCombatRuntime") as FusionCombatRuntime).signature_triggered.connect(_on_signature)
	EventBus.element_damage_dealt.connect(_on_damage)
	for entry in MATRIX:
		await _check_fusion(combat, entry[0], entry[1], entry[2])
	for failure in failures:
		push_error(failure)
	print("FUSION_TRAIT_CHECK failures=%d fusions=%d" % [failures.size(), MATRIX.size()])
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	combat.reset_runtime()
	if EventBus.element_damage_dealt.is_connected(_on_damage):
		EventBus.element_damage_dealt.disconnect(_on_damage)
	await _clear_enemies()
	combat.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_fusion(combat: ElementCombatSystem, first: String, second: String, fusion_id: String) -> void:
	await _clear_enemies()
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	combat.reset_runtime()
	events.clear()
	for _rank in 3:
		GameManager.add_fragment(first)
	for _rank in 3:
		GameManager.add_fragment(second)
	var enemies: Array[EnemyBasic] = []
	for index in 6:
		var enemy := _spawn_enemy(Vector2(80 + index * 38, 100), "%s_%d" % [fusion_id, index])
		enemies.append(enemy)
		if index > 0:
			(enemy.get_node("StatusEffectComponent") as StatusEffectComponent).apply_effect("slow", 5.0, 0.4)
	var result := combat.apply_element_damage(enemies[0].hurtbox_component, 40.0, Vector2.ZERO)
	if fusion_id == "judgment":
		await get_tree().create_timer(0.24, true, false, true).timeout
	var typed_ids := {}
	for event in events:
		typed_ids[event["element_id"]] = true
	_check(typed_ids.has("element_%s" % first), "%s inherits %s trait damage" % [fusion_id, first])
	_check(typed_ids.has("element_%s" % second), "%s inherits %s trait damage" % [fusion_id, second])
	_check(int(result["fusion_procs"]) >= 1, "%s triggers its third signature trait" % fusion_id)
	_check(events.any(func(event): return event["element_id"] == "fusion_%s" % fusion_id) or fusion_id in ["plasma", "solar", "inferno", "eclipse"], "%s produces signature state or damage" % fusion_id)
	_check(GameManager.get_active_element_ids().size() == 2, "%s keeps both inherited source elements" % fusion_id)

func _spawn_enemy(position: Vector2, id: String) -> EnemyBasic:
	var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.id = id
	data.display_name = "Fusion Trait Target"
	data.max_hp = 5000.0
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

func _on_signature(fusion_id: String, signature_id: String, affected: int, is_echo: bool) -> void:
	events.append({"element_id": "signature:%s:%s" % [fusion_id, signature_id], "affected": affected, "echo": is_echo})

func _on_damage(amount: float, position: Vector2, element_id: String, stack: int, chain: int) -> void:
	events.append({"amount": amount, "position": position, "element_id": element_id, "stack": stack, "chain": chain})

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
