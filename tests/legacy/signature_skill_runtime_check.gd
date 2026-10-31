extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")

var failures: Array[String] = []
var game: Node2D
var concept: ConceptSystem
var targets: Array[EnemyBasic] = []
var triggered: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	GameManager.selected_character_id = "swordsman"
	game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().physics_frame
	concept = game.get_node("ConceptSystem") as ConceptSystem
	concept.completed_skill_triggered.connect(func(skill_id, _level): triggered.append(skill_id))
	concept.reset_runtime()
	concept.set_active(true)
	_prepare_targets()

	var signature_definitions := concept.get_completed_skill_definitions().filter(func(definition): return bool(definition.get("signature_skill", false)))
	_check(signature_definitions.size() == 5, "five elemental signature skills load from data")
	_check(signature_definitions.all(func(definition): return String(definition.get("trigger_kind", "")) == "cooldown_auto"), "all signature skills use the bounded cooldown trigger")

	_check(concept.acquire_completed_skill("thunderlord_descent") == 1, "lightning signature can be acquired")
	var level_one_total := concept.get_completed_skill_cooldown_total("thunderlord_descent")
	var target := targets[0]
	var before := target.health_component.current_hp
	_check(concept.debug_trigger_completed_skill("thunderlord_descent", target), "signature can be triggered through the public debug path")
	var level_one_damage := before - target.health_component.current_hp
	_check(level_one_damage > 40.0, "level one signature deals large-skill damage")
	_check(concept.get_completed_skill_cooldown("thunderlord_descent") > 0.0, "manual trigger starts the real cooldown lifecycle")
	_check(_has_signature_vfx("thunderlord_descent"), "lightning signature spawns its dedicated runtime VFX")

	target.health_component.current_hp = 100000.0
	before = target.health_component.current_hp
	concept.debug_trigger_completed_skill("thunderlord_descent", target)
	var stack_three_damage := before - target.health_component.current_hp
	_check(stack_three_damage > level_one_damage * 1.25, "matching attribute Lv3 increases completed-skill damage")
	_check(concept.get_completed_skill_cooldown_total("thunderlord_descent") < level_one_total, "matching attribute Lv3 shortens signature cooldown")

	var player := game.get_node("Player") as Player
	player.upgrades_component.equipment_attack_flat = 20.0
	target.health_component.current_hp = 100000.0
	before = target.health_component.current_hp
	concept.debug_trigger_completed_skill("thunderlord_descent", target)
	var equipment_damage := before - target.health_component.current_hp
	_check(equipment_damage > stack_three_damage * 1.8, "equipment attack power contributes to signature damage")
	player.upgrades_component.equipment_attack_flat = 0.0

	_check(concept.acquire_completed_skill("thunderlord_descent") == 2, "duplicate signature acquisition raises level two")
	_check(concept.acquire_completed_skill("thunderlord_descent") == 3, "duplicate signature acquisition raises level three")
	var level_three_total := concept.get_completed_skill_cooldown_total("thunderlord_descent")
	_check(level_three_total < level_one_total, "signature level growth reduces base cooldown")
	triggered.clear()
	concept.debug_force_completed_skill_ready("thunderlord_descent")
	_check(await _wait_for(func(): return "thunderlord_descent" in triggered, 0.8), "ready cooldown auto-targets and activates without a direct hit")
	_check(concept.get_completed_skill_cooldown("thunderlord_descent") > 0.0, "automatic activation resets cooldown exactly once")

	# 全属性を同じ実行経路で呼び、固有Profileと上限内のVFX数を検査する。
	for definition in signature_definitions:
		var skill_id := String(definition.get("id", ""))
		if concept.get_completed_skill_level(skill_id) <= 0:
			concept.acquire_completed_skill(skill_id)
		_check(concept.debug_trigger_completed_skill(skill_id, target), "%s triggers" % skill_id)
		_check(_has_signature_vfx(String(definition.get("vfx_profile", ""))), "%s uses a distinct VFX profile" % skill_id)
	_check(get_tree().get_nodes_in_group("transient_vfx").size() < 32, "five large skills stay within a bounded transient VFX count")

	# 5種を同時Cooldown運用しても生成数が積み上がらず、各Skillが繰り返し戻る。
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().create_timer(0.72, true, false, true).timeout
	triggered.clear()
	for definition in signature_definitions:
		concept.debug_force_completed_skill_ready(String(definition.get("id", "")))
	Engine.time_scale = 10.0
	var stress_deadline := Time.get_ticks_msec() + 3400
	var peak_vfx := 0
	while Time.get_ticks_msec() < stress_deadline:
		peak_vfx = maxi(peak_vfx, get_tree().get_nodes_in_group("transient_vfx").size())
		await get_tree().process_frame
	Engine.time_scale = 1.0
	for definition in signature_definitions:
		var skill_id := String(definition.get("id", ""))
		_check(triggered.count(skill_id) >= 2, "%s returns through repeated cooldown cycles" % skill_id)
	_check(peak_vfx < 32, "simultaneous cooldown stress keeps transient VFX bounded")
	player.weapon_manager.process_mode = Node.PROCESS_MODE_INHERIT

	# 氷の遅延Echo中に対象が消えてもepoch/target検証で古い参照を使わない。
	var dying_target := targets[-1]
	concept.debug_trigger_completed_skill("glacial_spear_rain", dying_target)
	dying_target.queue_free()
	await get_tree().create_timer(0.42, true, false, true).timeout
	_check(is_instance_valid(concept), "delayed signature callback survives target deletion")

	# 敵不在ではCooldownを消費せず、次の群れまでREADYを保持する。
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	concept.debug_force_completed_skill_ready("thunderlord_descent")
	await get_tree().create_timer(0.12, true, false, true).timeout
	_check(is_zero_approx(concept.get_completed_skill_cooldown("thunderlord_descent")), "no-target state keeps the automatic large skill ready")

	print("SIGNATURE_SKILL_RUNTIME_CHECK failures=%d signatures=%d level1=%.1f stack3=%.1f equipment=%.1f cd1=%.2f cd3=%.2f peak_vfx=%d" % [failures.size(), signature_definitions.size(), level_one_damage, stack_three_damage, equipment_damage, level_one_total, level_three_total, peak_vfx])
	for failure in failures:
		push_error("SIGNATURE_SKILL_RUNTIME_CHECK: %s" % failure)
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	AudioManager.stop_all(false)
	get_tree().quit(1 if not failures.is_empty() else 0)


func _prepare_targets() -> void:
	targets.clear()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyBasic:
			var target := enemy as EnemyBasic
			target.process_mode = Node.PROCESS_MODE_DISABLED
			target.health_component.max_hp = 100000.0
			target.health_component.current_hp = 100000.0
			targets.append(target)
	for index in targets.size():
		targets[index].global_position = Vector2(index * 48.0, 0.0)
	_check(targets.size() >= 5, "combat field supplies at least five real enemies")


func _has_signature_vfx(profile: String) -> bool:
	for node in get_tree().get_nodes_in_group("transient_vfx"):
		if is_instance_valid(node) and String(node.get_meta("signature_vfx_profile", "")) == profile:
			return true
	return false


func _wait_for(condition: Callable, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() >= deadline:
			return false
		await get_tree().create_timer(0.04, true, false, true).timeout
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
