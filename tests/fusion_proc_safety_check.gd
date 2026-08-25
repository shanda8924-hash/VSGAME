extends Node

const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")
var failures: Array[String] = []

func _ready() -> void:
	var combat := ElementCombatSystem.new()
	add_child(combat)
	await get_tree().process_frame
	combat.set_proc_seed(20260810)
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	for _rank in 3:
		GameManager.add_general_mastery("echo")
	for _rank in 3:
		GameManager.add_fragment("fire")
	for _rank in 3:
		GameManager.add_fragment("lightning")
	for _rank in 3:
		GameManager.add_fusion_mastery("echo")
	var targets: Array[EnemyBasic] = []
	for index in 5:
		targets.append(_spawn_enemy(Vector2(100 + index * 55, 100), index))
	var total_element_echoes := 0
	var total_fusion_echoes := 0
	for _iteration in 120:
		var result := combat.apply_element_damage(targets[0].hurtbox_component, 20.0, Vector2.ZERO)
		total_element_echoes += int(result["element_echoes"])
		total_fusion_echoes += int(result["fusion_echoes"])
		_check(int(result["element_echoes"]) <= 2, "one primary hit can echo each source at most once")
		_check(int(result["fusion_echoes"]) <= 1, "one primary hit can echo fusion at most once")
		_check(int(result["fusion_procs"]) <= 2, "fusion signature cannot recursively proc")
	_check(total_element_echoes > 0 and total_fusion_echoes > 0, "seeded run exercises both element and fusion echo")
	await get_tree().create_timer(2.2, true, false, true).timeout
	await get_tree().process_frame
	var snapshot := combat.get_fusion_debug_snapshot()
	_check(int(snapshot.get("plasma_cores", -1)) == 0, "delayed Plasma cores resolve without recursive leftovers")
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	for _rank in 3:
		GameManager.add_fragment("lightning")
	for _rank in 3:
		GameManager.add_fragment("light")
	combat.apply_element_damage(targets[0].hurtbox_component, 20.0, Vector2.ZERO)
	snapshot = combat.get_fusion_debug_snapshot()
	_check(int(snapshot.get("afterglow_segments", 0)) > 0, "Radiant Arc queues short residual lines")
	await get_tree().create_timer(0.5, true, false, true).timeout
	snapshot = combat.get_fusion_debug_snapshot()
	_check(int(snapshot.get("afterglow_segments", -1)) == 0, "Radiant Arc residual lines resolve without leftovers")
	combat.reset_runtime()
	snapshot = combat.get_fusion_debug_snapshot()
	_check(int(snapshot.get("plasma_cores", -1)) == 0 and int(snapshot.get("inferno_souls", -1)) == 0 and int(snapshot.get("eclipse_gauge", -1)) == 0 and int(snapshot.get("afterglow_segments", -1)) == 0, "runtime reset clears all fusion state")
	for failure in failures:
		push_error(failure)
	print("FUSION_PROC_SAFETY_CHECK failures=%d element_echoes=%d fusion_echoes=%d snapshot=%s" % [failures.size(), total_element_echoes, total_fusion_echoes, snapshot])
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	for target in targets:
		if is_instance_valid(target):
			target.queue_free()
	combat.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _spawn_enemy(position: Vector2, index: int) -> EnemyBasic:
	var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.id = "proc_safety_%d" % index
	data.display_name = "Proc Safety Target"
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

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
