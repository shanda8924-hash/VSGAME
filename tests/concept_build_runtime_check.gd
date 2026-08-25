extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")
const REFERENCE_DAMAGE := 14.0

var failures: Array[String] = []
var game: Node2D
var controller: RoomRunController
var concept: ConceptSystem
var combo: ComboSystem
var targets: Array[EnemyBasic] = []
var triggered: Array[Dictionary] = []
var completed_triggered: Array[String] = []
var confirmed: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	GameManager.debug_request_room_mode_for_next_game()
	game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().physics_frame
	controller = game.get_node("RoomRunController") as RoomRunController
	concept = game.get_node("ConceptSystem") as ConceptSystem
	combo = game.get_node("ComboSystem") as ComboSystem
	concept.skill_triggered.connect(func(chain_index, skill_id, depth): triggered.append({"chain": chain_index, "skill": skill_id, "depth": depth}))
	concept.completed_skill_triggered.connect(func(skill_id, _level): completed_triggered.append(skill_id))
	EventBus.enemy_damage_confirmed.connect(_on_confirmed)

	_check(await _wait_for(func(): return controller.state == RoomRunController.RoomState.COMBAT, 4.0), "ROOM runtime reaches COMBAT")
	_check(controller.total_rooms == 36, "Run uses 36 configurable rooms")
	_check(DataLoader.get_all_concepts().size() == 14, "legacy Concept parts plus Light/Dark runtime skills load")
	_check(_concept_type_count("trigger") == 4 and _concept_type_count("skill") == 6 and _concept_type_count("modifier") == 4, "Concept pool keeps four triggers/modifiers and six internal skills")
	_check(_reference_hits("bat") >= 2.0 and _reference_hits("bat") <= 3.0, "small enemy is a 2-3 reference-hit target")
	_check(_reference_hits("basic_enemy") >= 5.0 and _reference_hits("basic_enemy") <= 7.0, "standard enemy is a 5-7 reference-hit target")
	_check(_reference_hits("werebear") >= 10.0 and _reference_hits("werebear") <= 14.0, "large enemy is a 10-14 reference-hit target")
	var hp_curve: Array = controller._config.get("enemy_hp_multipliers", [])
	var damage_curve: Array = controller._config.get("enemy_damage_multipliers", [])
	var hp_growth := float(hp_curve[34]) / float(hp_curve[0]) if hp_curve.size() == 36 else 0.0
	var damage_growth := float(damage_curve[34]) / float(damage_curve[0]) if damage_curve.size() == 36 else INF
	_check(hp_growth > damage_growth, "36 ROOM HP growth is stronger than damage growth")
	var enemy_counts: Array = controller._config.get("enemy_counts", [])
	_check(enemy_counts.size() == 36 and int(enemy_counts.max()) <= 15, "late ROOM enemy count stays capped at fifteen")

	var player := game.get_node("Player") as Player
	player.health_component.current_hp = player.health_component.max_hp * 0.4
	var before_heal := player.health_component.current_hp
	controller._apply_room_clear_recovery()
	_check(is_equal_approx(player.health_component.current_hp - before_heal, player.health_component.max_hp * 0.075), "ROOM CLEAR recovery heals configurable 7.5% max HP")

	_prepare_targets()
	_acquire_all()
	# Chain AのCritical落雷が低HPの別敵を倒し、Chain BのON KILLへ1段だけ連携する。
	_equip(0, "trigger_on_critical", "skill_thunder_strike", "modifier_chain")
	_equip(1, "trigger_on_kill", "skill_fire_burst", "modifier_echo")
	targets[0].health_component.current_hp = 1000.0
	targets[1].health_component.current_hp = 10.0
	triggered.clear()
	confirmed.clear()
	var real_hitbox := HitboxComponent.new()
	real_hitbox.damage = 1.0
	real_hitbox.is_critical = true
	real_hitbox.applies_player_elements = true
	real_hitbox.destroy_on_hit = false
	game.add_child(real_hitbox)
	targets[0].hurtbox_component.apply_hitbox_damage(real_hitbox)
	real_hitbox.queue_free()
	await get_tree().create_timer(0.35, true, false, true).timeout
	_check(_has_trigger("skill_thunder_strike", 1), "ON CRITICAL triggers THUNDER STRIKE")
	_check(_has_trigger("skill_fire_burst", 2), "triggered kill can activate the other Chain at generation 2")
	_check(_max_trigger_depth() <= 2 and triggered.size() < 10, "generation depth and lineage keep chained triggers bounded")
	_check(_confirmed_metadata_complete(), "confirmed damage events carry event/source/chain/depth/tags/direct/trigger/combo metadata")

	# 新しい対象では4Hitまで発動せず、設定値の5Hit目だけ発動する。
	concept.unequip_concept(1, "trigger")
	concept.unequip_concept(1, "skill")
	concept.unequip_concept(1, "modifier")
	_equip(0, "trigger_fifth_hit", "skill_wind_blade", "modifier_area")
	var fifth_target := targets[3]
	fifth_target.global_position = Vector2(500.0, 0.0)
	targets[5].global_position = Vector2(600.0, 0.0) # Wind基礎76pxの外、AREA適用後117.8pxの内側。
	fifth_target.health_component.current_hp = 1000.0
	targets[5].health_component.current_hp = 1000.0
	var area_edge_before := targets[5].health_component.current_hp
	triggered.clear()
	for i in 4:
		fifth_target.health_component.apply_secondary_damage(1.0, CombatEventMeta.create_direct("test_fifth"))
	_check(triggered.is_empty(), "FIFTH HIT does not trigger before the configured count")
	fifth_target.health_component.apply_secondary_damage(1.0, CombatEventMeta.create_direct("test_fifth"))
	_check(_has_trigger("skill_wind_blade", 1), "FIFTH HIT triggers on the fifth direct hit to the same enemy")
	_check(targets[5].health_component.current_hp < area_edge_before, "AREA expands Wind Blade beyond its base radius")

	# COMBO 20到達でIce Nova、ECHOは1回だけ遅延再発動し再帰しない。
	_equip(0, "trigger_combo", "skill_ice_nova", "modifier_echo")
	combo.reset_combo()
	triggered.clear()
	confirmed.clear()
	var combo_target := targets[4]
	combo_target.health_component.current_hp = 1000.0
	for i in 20:
		combo_target.health_component.apply_secondary_damage(1.0, CombatEventMeta.create_direct("test_combo"))
	await get_tree().create_timer(0.4, true, false, true).timeout
	_check(combo.combo >= 20, "confirmed direct hits advance COMBO to the trigger threshold")
	_check(_has_trigger("skill_ice_nova", 1), "COMBO TRIGGER activates at 20 COMBO")
	_check(_count_source_suffix(":repeat") > 0, "ECHO creates one delayed repeated Skill event")
	_check(_count_source_suffix(":repeat") < 8, "ECHO does not recursively repeat itself")

	# FOCUSは別敵へ渡さず、同じ生存Targetだけを遅延再Hitする。
	_equip(0, "trigger_on_critical", "skill_thunder_strike", "modifier_focus")
	var focus_target := targets[5]
	focus_target.global_position = Vector2(1200.0, 0.0)
	focus_target.health_component.current_hp = 1000.0
	confirmed.clear()
	triggered.clear()
	focus_target.health_component.apply_secondary_damage(1.0, CombatEventMeta.create_direct("test_focus", true))
	await get_tree().create_timer(0.3, true, false, true).timeout
	_check(_has_trigger("skill_thunder_strike", 1), "FOCUS build receives its direct Critical trigger")
	_check(_count_source_suffix(":repeat") == 1 and _repeat_only_hits_target(focus_target), "FOCUS repeats once on the same target instead of chaining away")

	# 通常プレイヤー向け完成済みスキルは、旧Boardと独立して最大6種・重複Lv.UPで動く。
	GameManager.debug_force_element_state({"element_fire": 3, "element_lightning": 3})
	for skill_id in ["thunder_chain", "conductive_flame", "lightning_charge", "overload", "burning_burst", "burn_spread"]:
		_check(concept.acquire_completed_skill(skill_id) == 1, "%s can be acquired as a completed skill" % skill_id)
	_check(concept.acquire_completed_skill("thunder_chain") == 2, "duplicate completed skill increases its level")
	_check(concept.acquire_completed_skill("scorching_followup") == 0 and concept.get_completed_skill_count() == 6, "completed skill ownership is capped at six distinct skills")
	_check(concept.get_completed_skill_display_name("thunder_chain") == "雷鳴連鎖" and not concept.get_completed_skill_description("thunder_chain", 2).is_empty(), "completed skill ID is separated from Japanese display text")
	var smart_candidates := controller._build_completed_skill_candidates()
	_check(smart_candidates.size() == 3 and smart_candidates.all(func(entry): return concept.is_completed_skill_available_for_build(entry, GameManager.get_active_element_ids())), "smart treasure candidates are all usable by the current build")
	completed_triggered.clear()
	var completed_target := targets[0]
	completed_target.health_component.current_hp = 1000.0
	var element_system := game.get_node("ElementCombatSystem") as ElementCombatSystem
	element_system._apply_fire_role(completed_target, completed_target.health_component, 20.0, 20.0, 3, CombatEventMeta.create_direct("test_fire", false, ["element_fire"]))
	completed_target.health_component.apply_secondary_damage(1.0, CombatEventMeta.create_direct("test_lightning", true, ["element_lightning"]))
	await get_tree().create_timer(0.12, true, false, true).timeout
	_check("thunder_chain" in completed_triggered, "雷鳴連鎖 triggers from a real Lightning critical event")
	_check("conductive_flame" in completed_triggered, "導電炎 triggers only after Fire burn and Lightning critical conditions meet")
	_check(completed_triggered.size() < 10, "completed skills do not recurse through their own triggered damage")

	# 取得と装備は分離され、Boardは任意のROOM間編集UIとして開閉できる。
	_check(concept.acquired_ids.size() == 14 and concept.get_chain(0).get("trigger") == "trigger_on_critical" and concept.get_chain(0).get("modifier") == "modifier_focus", "legacy Concept inventory and equipped Board state remain available for developer tools")
	controller.concept_board.show_board("TEST CONCEPT BOARD")
	_check(await _wait_for(func(): return controller.concept_board.visible, 2.0), "Concept Board opens through the modal system")
	controller.concept_board.done_button.emit_signal("pressed")
	_check(await _wait_for(func(): return not controller.concept_board.visible, 2.0), "Concept Board closes without altering combat state")

	print("CONCEPT_BUILD_RUNTIME_CHECK failures=%d concepts=%d triggers=%s combo=%d" % [failures.size(), concept.acquired_ids.size(), str(triggered), combo.combo])
	for failure in failures:
		push_error("CONCEPT_BUILD_RUNTIME_CHECK: %s" % failure)
	if EventBus.enemy_damage_confirmed.is_connected(_on_confirmed):
		EventBus.enemy_damage_confirmed.disconnect(_on_confirmed)
	get_tree().paused = false
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	AudioManager.stop_all(false)
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(1 if not failures.is_empty() else 0)


func _prepare_targets() -> void:
	targets.clear()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyBasic:
			var target := enemy as EnemyBasic
			target.process_mode = Node.PROCESS_MODE_DISABLED
			target.health_component.max_hp = 1000.0
			target.health_component.current_hp = 1000.0
			targets.append(target)
	for index in targets.size():
		targets[index].global_position = Vector2(index * 34.0, 0.0)
	_check(targets.size() >= 5, "test ROOM provides at least five targets")


func _acquire_all() -> void:
	for data in DataLoader.get_all_concepts():
		concept.acquire_concept(data.id)


func _equip(chain_index: int, trigger_id: String, skill_id: String, modifier_id: String) -> void:
	concept.equip_concept(chain_index, "trigger", trigger_id)
	concept.equip_concept(chain_index, "skill", skill_id)
	concept.equip_concept(chain_index, "modifier", modifier_id)


func _on_confirmed(target: Node, amount: float, critical: bool, metadata: Dictionary) -> void:
	confirmed.append({"target": target, "amount": amount, "critical": critical, "meta": metadata.duplicate(true)})


func _has_trigger(skill_id: String, depth: int) -> bool:
	for entry in triggered:
		if entry.get("skill") == skill_id and int(entry.get("depth", -1)) == depth:
			return true
	return false


func _max_trigger_depth() -> int:
	var result := 0
	for entry in triggered:
		result = maxi(result, int(entry.get("depth", 0)))
	return result


func _confirmed_metadata_complete() -> bool:
	for entry in confirmed:
		var meta: Dictionary = entry.get("meta", {})
		for key in ["event_id", "source_kind", "chain_id", "generation_depth", "element_tags", "is_direct", "is_triggered", "combo_eligible"]:
			if not meta.has(key):
				return false
	return not confirmed.is_empty()


func _count_source_suffix(suffix: String) -> int:
	var result := 0
	for entry in confirmed:
		if String(entry.get("meta", {}).get("source_kind", "")).ends_with(suffix):
			result += 1
	return result


func _repeat_only_hits_target(expected: Node) -> bool:
	var found := false
	for entry in confirmed:
		if not String(entry.get("meta", {}).get("source_kind", "")).ends_with(":repeat"):
			continue
		found = true
		if entry.get("target") != expected:
			return false
	return found


func _reference_hits(enemy_id: String) -> float:
	var data: EnemyData = DataLoader.enemies.get(enemy_id)
	return data.max_hp / REFERENCE_DAMAGE if data else 0.0


func _concept_type_count(concept_type: String) -> int:
	var result := 0
	for data in DataLoader.get_all_concepts():
		if data.concept_type == concept_type:
			result += 1
	return result


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
