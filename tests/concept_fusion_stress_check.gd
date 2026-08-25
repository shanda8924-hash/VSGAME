extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")
const TARGET_COUNT := 24

var failures: Array[String] = []
var game: Node2D
var controller: RoomRunController
var concept: ConceptSystem
var combo: ComboSystem
var combat: ElementCombatSystem
var targets: Array[EnemyBasic] = []
var trigger_count := 0
var max_trigger_depth := 0
var peak_nodes := 0
var peak_vfx := 0
var peak_projectiles := 0
var min_fps := 10000.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	GameManager.selected_character_id = "soldier"
	GameManager.debug_request_room_mode_for_next_game()
	game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().physics_frame
	controller = game.get_node("RoomRunController") as RoomRunController
	concept = game.get_node("ConceptSystem") as ConceptSystem
	combo = game.get_node("ComboSystem") as ComboSystem
	combat = game.get_node("ElementCombatSystem") as ElementCombatSystem
	concept.skill_triggered.connect(_on_skill_triggered)
	_check(await _wait_for(func(): return controller.state == RoomRunController.RoomState.COMBAT, 4.0), "ROOM runtime reaches COMBAT")

	var player := game.get_node("Player") as Player
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	_prepare_targets(player.global_position)
	_acquire_and_equip()
	_activate_plasma()
	await get_tree().create_timer(2.0, true, false, true).timeout

	var warm_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	peak_nodes = warm_nodes
	combo.reset_combo()
	# One primary critical hit must remain bounded even when Plasma chain and Echo
	# are both active. The second chain supplies the AREA path on fifth hit.
	_apply_primary_hit(targets[0], true)
	await _sample_for(0.7)
	var one_primary_combo := combo.combo
	_check(one_primary_combo <= 30, "one primary origin cannot inflate COMBO into hundreds")
	for _index in 4:
		targets[0].health_component.apply_secondary_damage(1.0, CombatEventMeta.create_direct("stress_fifth"))
	await _sample_for(0.7)
	var fifth_sequence_combo := combo.combo

	# Burst 24 real player-origin hits several times while all requested systems
	# are active: Plasma chain, Echo, AREA and both Concept chains.
	for iteration in 6:
		for target in targets:
			target.health_component._iframe_remaining = 0.0
			_apply_primary_hit(target, iteration % 2 == 0)
		await _sample_for(0.18)
	await _sample_for(2.5)

	_check(max_trigger_depth <= 2, "Concept generation depth remains at MAX_TRIGGER_DEPTH 2")
	_check(trigger_count < 700, "trigger count remains bounded under 24-target burst")
	_check(peak_nodes < warm_nodes + 1800, "runtime node peak remains bounded")
	_check(peak_vfx < 700, "transient VFX peak remains bounded")
	_check(peak_projectiles < 300, "projectile peak remains bounded")
	_check(min_fps == 10000.0 or min_fps >= 30.0, "stress sample does not drop below 30 FPS")

	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	combat.reset_runtime()
	controller._clear_transient_room_nodes()
	for target in targets:
		if is_instance_valid(target):
			target.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(3.0, true, false, true).timeout
	var snapshot := combat.get_fusion_debug_snapshot()
	var remaining_vfx := get_tree().get_nodes_in_group("transient_vfx").size()
	var remaining_projectiles := get_tree().get_nodes_in_group("projectiles").size()
	_check(remaining_vfx == 0, "ROOM cleanup releases all transient VFX")
	_check(remaining_projectiles == 0, "ROOM cleanup releases all projectiles")
	_check(int(snapshot.get("plasma_cores", -1)) == 0, "Plasma core dictionary returns to zero")
	_check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0, "stress cleanup leaves no orphan nodes")

	print("CONCEPT_FUSION_STRESS_CHECK failures=%d targets=%d triggers=%d max_depth=%d one_primary_combo=%d fifth_sequence_combo=%d final_combo=%d warm_nodes=%d peak_nodes=%d peak_vfx=%d peak_projectiles=%d min_fps=%.1f remaining_vfx=%d remaining_projectiles=%d snapshot=%s" % [failures.size(), TARGET_COUNT, trigger_count, max_trigger_depth, one_primary_combo, fifth_sequence_combo, combo.combo, warm_nodes, peak_nodes, peak_vfx, peak_projectiles, 0.0 if min_fps == 10000.0 else min_fps, remaining_vfx, remaining_projectiles, snapshot])
	for failure in failures:
		push_error("CONCEPT_FUSION_STRESS_CHECK: %s" % failure)
	get_tree().paused = false
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	AudioManager.stop_all(false)
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if failures.is_empty() else 1)


func _prepare_targets(center: Vector2) -> void:
	# 最初の標的は実際のBossData/EnemyBasic経路にし、Fusion + Chain + Echo +
	# Area + COMBOの単体BuildチェックがBossでも同じDamage pipelineを通ることを確認する。
	var stress_boss := ENEMY_SCENE.instantiate() as EnemyBasic
	stress_boss.enemy_data = DataLoader.bosses.get("flame_golem")
	stress_boss.room_hp_multiplier = 6.0
	stress_boss.boss_status_duration_multiplier = 0.25
	game.add_child(stress_boss)
	targets.append(stress_boss)
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyBasic and node != stress_boss:
			targets.append(node as EnemyBasic)
	while targets.size() < TARGET_COUNT:
		var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
		var data := EnemyData.new()
		data.id = "concept_fusion_stress_%d" % targets.size()
		data.display_name = "Stress Target"
		data.max_hp = 100000000.0
		data.move_speed = 0.0
		data.contact_damage = 0.0
		data.attack_interval = 99.0
		data.attack_windup = 99.0
		data.sprite_folder = "enemies/Orc"
		enemy.enemy_data = data
		game.add_child(enemy)
		targets.append(enemy)
	for index in targets.size():
		var target := targets[index]
		target.process_mode = Node.PROCESS_MODE_DISABLED
		target.health_component.max_hp = 100000000.0
		target.health_component.current_hp = 100000000.0
		var angle := float(index) * TAU / float(TARGET_COUNT)
		var radius := 72.0 + float(index % 4) * 28.0
		target.global_position = center + Vector2.from_angle(angle) * radius
	_check(targets[0].enemy_data is BossData, "stress primary target uses the real BossData combat path")
	_check(targets[0].status_effect_component.duration_multiplier < 1.0, "stress Boss keeps shortened status effects instead of immunity")


func _acquire_and_equip() -> void:
	for data in DataLoader.get_all_concepts():
		concept.acquire_concept(data.id)
	concept.equip_concept(0, "trigger", "trigger_on_critical")
	concept.equip_concept(0, "skill", "skill_thunder_strike")
	concept.equip_concept(0, "modifier", "modifier_echo")
	concept.equip_concept(1, "trigger", "trigger_fifth_hit")
	concept.equip_concept(1, "skill", "skill_fire_burst")
	concept.equip_concept(1, "modifier", "modifier_area")


func _activate_plasma() -> void:
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	for _rank in 3:
		GameManager.add_fragment("fire")
	for _rank in 3:
		GameManager.add_fragment("lightning")
	_check(GameManager.active_fusion_id == "plasma", "Fire Lv3 + Lightning Lv3 activates Plasma")


func _apply_primary_hit(target: EnemyBasic, critical: bool) -> void:
	var hitbox := HitboxComponent.new()
	hitbox.damage = 14.0
	hitbox.is_critical = critical
	hitbox.applies_player_elements = true
	hitbox.destroy_on_hit = false
	hitbox.combat_metadata = CombatEventMeta.create_direct("stress_primary", critical)
	game.add_child(hitbox)
	target.hurtbox_component.apply_hitbox_damage(hitbox)
	hitbox.queue_free()


func _sample_for(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		peak_nodes = maxi(peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		peak_vfx = maxi(peak_vfx, get_tree().get_nodes_in_group("transient_vfx").size())
		peak_projectiles = maxi(peak_projectiles, get_tree().get_nodes_in_group("projectiles").size())
		var fps := Engine.get_frames_per_second()
		if fps > 0:
			min_fps = minf(min_fps, fps)
		await get_tree().process_frame


func _on_skill_triggered(_chain_index: int, _skill_id: String, depth: int) -> void:
	trigger_count += 1
	max_trigger_depth = maxi(max_trigger_depth, depth)


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
