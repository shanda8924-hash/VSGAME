extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")

var failures: Array[String] = []
var game: Node2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	GameManager.debug_request_room_mode_for_next_game()
	game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().physics_frame
	# Keep the audit deterministic: invalidate Game's deferred first ROOM transition
	# and stop automatic attacks while individual runtime paths are exercised below.
	var controller := game.get_node("RoomRunController") as RoomRunController
	controller._transition_epoch += 1
	controller.process_mode = Node.PROCESS_MODE_DISABLED
	game.get_node("WaveSpawner").call("clear_room_wave")
	game.get_node("Player/WeaponManagerComponent").process_mode = Node.PROCESS_MODE_DISABLED
	_check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0, "Music/SFX Audio buses exist")
	_check(game.get_node_or_null("FusionSystem") == null, "legacy fragment FusionSystem is absent from normal runtime")
	_check(game.get_node("WaveSpawner").process_mode == Node.PROCESS_MODE_DISABLED, "legacy timed Wave processing starts disabled")
	_check(game.get_node("BossSpawner").process_mode == Node.PROCESS_MODE_DISABLED, "legacy automatic Boss processing starts disabled")
	_check(game.get_node("EliteRoomManager").process_mode == Node.PROCESS_MODE_DISABLED, "legacy automatic Elite processing starts disabled")
	await _check_combo_rules()
	_check_fusion_tags()
	await _check_screen_effect_lifecycle()
	_check_smart_concept_weight()
	await _check_room_cleanup()
	print("GLOBAL_AUDIT_CHECK failures=%d" % failures.size())
	for failure in failures:
		push_error("GLOBAL_AUDIT_CHECK: %s" % failure)
	Engine.time_scale = 1.0
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	AudioManager.stop_all(false)
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_combo_rules() -> void:
	var combo := game.get_node("ComboSystem") as ComboSystem
	combo.set_active(true)
	combo.configure_timeout(0.3)
	combo.configure_triggered_chain_cap(12)
	var target := _spawn_target(Vector2(100, 100), 10000.0)
	var direct := CombatEventMeta.create_direct("audit_direct")
	target.health_component.apply_secondary_damage(1.0, direct)
	var direct_remaining := combo._remaining
	var triggered := CombatEventMeta.create_triggered(direct, "audit_triggered", [], 0, true)
	await get_tree().create_timer(0.03, true, false, true).timeout
	target.health_component.apply_secondary_damage(1.0, triggered)
	_check(combo.combo == 2, "Triggered Hit adds one COMBO")
	_check(combo._remaining < direct_remaining, "Triggered Hit does not refresh COMBO timer")
	var burn := triggered.duplicate(true)
	burn["source_kind"] = "element_fire:burn"
	burn["combo_eligible"] = false
	target.health_component.apply_secondary_damage(1.0, burn)
	_check(combo.combo == 2, "DoT does not add COMBO")
	for index in 20:
		target.health_component.apply_secondary_damage(1.0, CombatEventMeta.fork_event(triggered, "audit_triggered_%d" % index))
	_check(combo.combo == 13, "one Trigger chain is capped at 12 COMBO contributions")
	combo.reset_combo()
	target.queue_free()

func _check_fusion_tags() -> void:
	var element := game.get_node("ElementCombatSystem") as ElementCombatSystem
	var tags: Array = element._fusion_runtime._fusion_element_tags("plasma")
	_check(["fusion", "plasma", "fire", "lightning"].all(func(tag): return tag in tags), "Plasma metadata retains Fusion/Plasma/Fire/Lightning tags")

func _check_screen_effect_lifecycle() -> void:
	var screen := game.get_node("ScreenEffects") as ScreenEffects
	screen.hit_stop(0.16)
	await get_tree().create_timer(0.025, true, false, true).timeout
	screen.hit_stop(0.035)
	await get_tree().create_timer(0.055, true, false, true).timeout
	_check(Engine.time_scale < 0.1, "overlapping Hit Stop does not restore time early")
	await get_tree().create_timer(0.12, true, false, true).timeout
	_check(is_equal_approx(Engine.time_scale, 1.0), "Screen time scale always restores to 1")
	screen.flash(Color.WHITE, 0.2)
	await get_tree().create_timer(0.28, true, false, true).timeout
	_check(get_tree().get_nodes_in_group("transient_vfx").all(func(node): return not (node is CanvasLayer and node.get_parent() == screen)), "screen overlay retires after its Tween")

func _check_smart_concept_weight() -> void:
	var controller := game.get_node("RoomRunController") as RoomRunController
	var concept := game.get_node("ConceptSystem") as ConceptSystem
	concept.reset_runtime()
	seed(41027)
	var saw_non_forced_mix := false
	for _index in 80:
		var candidates := controller._build_concept_candidates()
		var types := candidates.map(func(data): return data.concept_type)
		if types.duplicate().size() == 3 and (types.count("trigger") != 1 or types.count("skill") != 1 or types.count("modifier") != 1):
			saw_non_forced_mix = true
			break
	_check(saw_non_forced_mix, "Concept candidates use weighted randomness instead of forced one-per-category")
	for id in ["trigger_on_critical", "trigger_fifth_hit", "trigger_on_kill", "skill_thunder_strike", "skill_fire_burst", "skill_ice_nova"]:
		concept.acquire_concept(id)
	var type_hits := {"trigger": 0, "skill": 0, "modifier": 0}
	for _index in 120:
		for data in controller._build_concept_candidates():
			type_hits[data.concept_type] = int(type_hits.get(data.concept_type, 0)) + 1
	_check(int(type_hits["modifier"]) > int(type_hits["trigger"]), "missing Concept category receives a Smart Weight bias")
	concept.reset_runtime()

func _check_room_cleanup() -> void:
	var controller := game.get_node("RoomRunController") as RoomRunController
	for group_name in ["projectiles", "transient_vfx", "ground_equipment", "room_transient"]:
		var node := Node2D.new()
		node.add_to_group(group_name)
		game.add_child(node)
	controller._clear_transient_room_nodes()
	await get_tree().process_frame
	for group_name in ["projectiles", "transient_vfx", "ground_equipment", "room_transient"]:
		_check(get_tree().get_nodes_in_group(group_name).is_empty(), "ROOM cleanup removes %s" % group_name)

func _spawn_target(position: Vector2, hp: float) -> EnemyBasic:
	var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.id = "global_audit_target_%d" % Time.get_ticks_usec()
	data.display_name = "AUDIT TARGET"
	data.max_hp = hp
	data.move_speed = 0.0
	data.contact_damage = 0.0
	data.sprite_folder = "enemies/Orc"
	enemy.enemy_data = data
	game.add_child(enemy)
	enemy.global_position = position
	return enemy

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
