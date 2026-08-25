extends Node
class_name FusionCombatRuntime
## 全10Fusionの第3Traitだけを担当する非再帰Runtime。継承2TraitはElementCombatSystem側で適用する。

signal signature_triggered(fusion_id: String, signature_id: String, affected_targets: int, is_echo: bool)

var _host: ElementCombatSystem
var _plasma_cores: Dictionary = {}
var _solar_marks: Dictionary = {}
var _inferno_marks: Dictionary = {}
var _inferno_souls: int = 0
var _eclipse_gauge: int = 0
var _eclipse_remaining: float = 0.0
var _cooldowns: Dictionary = {}
var _afterglow_segments: Array[Dictionary] = []
var _damage_metadata: Dictionary = {}

func setup(host: ElementCombatSystem) -> void:
	_host = host
	process_mode = Node.PROCESS_MODE_ALWAYS

func reset_runtime() -> void:
	for id_variant in _plasma_cores.keys():
		var core: Dictionary = _plasma_cores.get(int(id_variant), {})
		_disconnect_plasma_death_callback(core)
	_plasma_cores.clear()
	_solar_marks.clear()
	_inferno_marks.clear()
	_inferno_souls = 0
	_eclipse_gauge = 0
	_eclipse_remaining = 0.0
	_cooldowns.clear()
	_afterglow_segments.clear()
	_damage_metadata.clear()

func _process(delta: float) -> void:
	if _eclipse_remaining > 0.0:
		_eclipse_remaining = maxf(_eclipse_remaining - delta, 0.0)
	for key in _cooldowns.keys():
		_cooldowns[key] = maxf(float(_cooldowns[key]) - delta, 0.0)
	for index in range(_afterglow_segments.size() - 1, -1, -1):
		var segment := _afterglow_segments[index]
		segment["remaining"] = float(segment.get("remaining", 0.0)) - delta
		if float(segment["remaining"]) <= 0.0:
			_afterglow_segments.remove_at(index)
			_resolve_afterglow_segment(segment)
		else:
			_afterglow_segments[index] = segment
	# Core detonation can synchronously kill another marked enemy. Its `died` signal
	# removes that other core, so ticking and detonating must be separate phases.
	var invalid_plasma_ids: Array[int] = []
	var expired_plasma_ids: Array[int] = []
	for id_variant in _plasma_cores.keys():
		var id := int(id_variant)
		var core: Dictionary = _plasma_cores.get(id, {})
		if core.is_empty():
			continue
		var target_ref: Variant = core.get("target")
		if target_ref == null or not is_instance_valid(target_ref):
			invalid_plasma_ids.append(id)
			continue
		core["remaining"] = float(core["remaining"]) - delta
		_plasma_cores[id] = core
		if float(core["remaining"]) <= 0.0:
			expired_plasma_ids.append(id)
	for id in invalid_plasma_ids:
		_retire_plasma_core(id)
	for id in expired_plasma_ids:
		_detonate_plasma(id, false)

func apply_signature(fusion_id: String, target: Node2D, health: HealthComponent, base_damage: float, origin: Vector2, is_echo: bool = false, parent_metadata: Dictionary = {}) -> Dictionary:
	var result := {"fusion_procs": 0, "affected": 0}
	if fusion_id == "" or target == null or health == null or base_damage <= 0.0:
		return result
	var previous_metadata := _damage_metadata
	_damage_metadata = CombatEventMeta.normalize(parent_metadata) if not parent_metadata.is_empty() else CombatEventMeta.create_secondary("fusion_%s" % fusion_id, _fusion_element_tags(fusion_id), true)
	var affected := 0
	match fusion_id:
		"frostfire": affected = _thermal_collapse(target, base_damage)
		"plasma": affected = _attach_plasma_core(target, health, base_damage)
		"solar": affected = _mark_solar_corona(target, health, base_damage)
		"inferno": affected = _soul_devour(target, health, base_damage)
		"superconductor": affected = _resonance_shatter(target, base_damage)
		"aurora": affected = _aurora_refraction(target, base_damage)
		"void_frost": affected = _gravity_collapse(target, base_damage)
		"judgment": affected = _afterglow_circuit(origin, target.global_position, base_damage)
		"voidstorm": affected = _space_jump(target, base_damage)
		"eclipse": affected = _total_eclipse(target, base_damage)
	if affected > 0:
		result["fusion_procs"] = 1
		result["affected"] = affected
		var signature_id := String(_fusion_data(fusion_id).get("signature", fusion_id))
		signature_triggered.emit(fusion_id, signature_id, affected, is_echo)
		var vfx_mode := "trail" if fusion_id == "judgment" else "signature"
		_play_vfx(fusion_id, origin, target.global_position, vfx_mode, 1.08 if is_echo else 0.94)
	_damage_metadata = previous_metadata
	return result

## Lightning FusionのChain到達点だけを受け取る補助入口。
## Damageはapply_secondary_damage経路に限定し、Element/Fusion入口へ戻さない。
func apply_chain_reaction(fusion_id: String, from: Vector2, to: Vector2, target: Node2D, health: HealthComponent, chain_damage: float, parent_metadata: Dictionary = {}) -> int:
	if target == null or health == null or chain_damage <= 0.0:
		return 0
	var previous_metadata := _damage_metadata
	_damage_metadata = CombatEventMeta.normalize(parent_metadata) if not parent_metadata.is_empty() else CombatEventMeta.create_secondary("fusion_%s" % fusion_id, _fusion_element_tags(fusion_id), true)
	var affected := 0
	match fusion_id:
		"plasma":
			affected = _attach_plasma_core(target, health, chain_damage)
		"judgment":
			affected = _afterglow_circuit(from, to, chain_damage)
	_damage_metadata = previous_metadata
	return affected

func get_debug_snapshot() -> Dictionary:
	return {
		"plasma_cores": _plasma_cores.size(),
		"solar_marks": _solar_marks.size(),
		"inferno_marks": _inferno_marks.size(),
		"inferno_souls": _inferno_souls,
		"eclipse_gauge": _eclipse_gauge,
		"eclipse_active": _eclipse_remaining > 0.0,
		"afterglow_segments": _afterglow_segments.size(),
	}

func _thermal_collapse(target: Node2D, base_damage: float) -> int:
	var status := target.get_node_or_null("StatusEffectComponent") as StatusEffectComponent
	if not _host.is_target_burning(target) or status == null or not (status.has_effect("slow") or status.has_effect("stun")):
		return 0
	var data := _fusion_data("frostfire")
	var rank := _signature_rank()
	return _apply_aoe(target.global_position, base_damage * float(data.get("base_ratio", 0.7)) * (1.0 + rank * 0.25), float(data.get("radius", 118.0)) * (1.0 + rank * 0.18), "frostfire", target)

func _attach_plasma_core(target: Node2D, health: HealthComponent, base_damage: float) -> int:
	var id := target.get_instance_id()
	var data := _fusion_data("plasma")
	var first_attach := not _plasma_cores.has(id)
	if first_attach:
		var death_callable := _on_plasma_target_died.bind(id)
		_plasma_cores[id] = {
			"target": target,
			"health": health,
			"death_callable": death_callable,
			"base_damage": base_damage,
			"remaining": float(data.get("delay", 1.2)),
			"position": target.global_position,
			"combat_metadata": _damage_metadata.duplicate(true),
		}
		health.died.connect(death_callable, CONNECT_ONE_SHOT)
	else:
		# Reapplying refreshes the active core without adding another death callback.
		var core: Dictionary = _plasma_cores.get(id, {})
		core["target"] = target
		core["base_damage"] = base_damage
		core["remaining"] = float(data.get("delay", 1.2))
		core["position"] = target.global_position
		core["combat_metadata"] = _damage_metadata.duplicate(true)
		_plasma_cores[id] = core
	return 1

func _on_plasma_target_died(id: int) -> void:
	_detonate_plasma(id, true)

func _detonate_plasma(id: int, from_death: bool) -> void:
	var core: Dictionary = _plasma_cores.get(id, {})
	if core.is_empty():
		return
	_plasma_cores.erase(id)
	if not from_death:
		_disconnect_plasma_death_callback(core)
	var target_ref: Variant = core.get("target")
	var position := Vector2(core.get("position", Vector2.ZERO))
	if target_ref != null and is_instance_valid(target_ref):
		position = (target_ref as Node2D).global_position
	var data := _fusion_data("plasma")
	var rank := _signature_rank()
	var previous_metadata := _damage_metadata
	_damage_metadata = core.get("combat_metadata", {}).duplicate(true)
	var affected := _apply_aoe(position, float(core.get("base_damage", 0.0)) * float(data.get("base_ratio", 0.9)) * (1.0 + rank * 0.30), float(data.get("radius", 105.0)) * (1.0 + rank * 0.25), "plasma")
	signature_triggered.emit("plasma", "overcharge_explosion", affected, false)
	_play_vfx("plasma", position, position, "burst", 1.25)
	if rank >= 3 and affected > 0 and not from_death:
		var spread_target := _nearest_enemy(position, 180.0, {id: true})
		if spread_target:
			var spread_health := spread_target.get_node_or_null("HealthComponent") as HealthComponent
			if spread_health:
				_attach_plasma_core(spread_target, spread_health, float(core.get("base_damage", 0.0)) * 0.65)
	_damage_metadata = previous_metadata

func _retire_plasma_core(id: int) -> void:
	var core: Dictionary = _plasma_cores.get(id, {})
	if core.is_empty():
		return
	_plasma_cores.erase(id)
	_disconnect_plasma_death_callback(core)

func _disconnect_plasma_death_callback(core: Dictionary) -> void:
	var health_ref: Variant = core.get("health")
	if health_ref == null or not is_instance_valid(health_ref):
		return
	var health := health_ref as HealthComponent
	var death_callable: Callable = core.get("death_callable", Callable())
	if health != null and death_callable.is_valid() and health.died.is_connected(death_callable):
		health.died.disconnect(death_callable)

func _mark_solar_corona(target: Node2D, health: HealthComponent, base_damage: float) -> int:
	if not _host.is_target_burning(target):
		return 0
	var id := target.get_instance_id()
	_solar_marks[id] = {"target": target, "base_damage": base_damage, "position": target.global_position, "combat_metadata": _damage_metadata.duplicate(true)}
	if not bool(target.get_meta("solar_corona_connected", false)):
		target.set_meta("solar_corona_connected", true)
		health.died.connect(_solar_flare.bind(id), CONNECT_ONE_SHOT)
	return 1

func _solar_flare(id: int) -> void:
	var mark_value: Variant = _solar_marks.get(id)
	if not mark_value is Dictionary:
		return
	var mark: Dictionary = mark_value
	_solar_marks.erase(id)
	var position := Vector2(mark.get("position", Vector2.ZERO))
	var target_ref: Variant = mark.get("target")
	if target_ref != null and is_instance_valid(target_ref):
		position = (target_ref as Node2D).global_position
	var data := _fusion_data("solar")
	var rank := _signature_rank()
	var previous_metadata := _damage_metadata
	_damage_metadata = mark.get("combat_metadata", {}).duplicate(true)
	var affected := _apply_aoe(position, float(mark.get("base_damage", 0.0)) * float(data.get("base_ratio", 0.8)) * (1.0 + rank * 0.2), float(data.get("radius", 145.0)) * (1.0 + rank * 0.18), "solar")
	signature_triggered.emit("solar", "corona_flare", affected, false)
	_play_vfx("solar", position, position, "burst", 1.2 + rank * 0.08)
	_damage_metadata = previous_metadata

func _soul_devour(target: Node2D, health: HealthComponent, base_damage: float) -> int:
	var data := _fusion_data("inferno")
	var cap := maxi(2, int(data.get("soul_cap", 5)) - _signature_rank())
	if _inferno_souls >= cap:
		_inferno_souls = 0
		return _apply_aoe(target.global_position, base_damage * float(data.get("base_ratio", 1.25)) * (1.0 + _signature_rank() * 0.35), float(data.get("radius", 135.0)) * (1.0 + _signature_rank() * 0.15), "inferno")
	var id := target.get_instance_id()
	if not _inferno_marks.has(id):
		_inferno_marks[id] = {"target": target, "position": target.global_position}
		health.died.connect(_collect_inferno_soul.bind(id), CONNECT_ONE_SHOT)
	return 1

func _collect_inferno_soul(id: int) -> void:
	var mark_value: Variant = _inferno_marks.get(id)
	if not mark_value is Dictionary:
		return
	var mark: Dictionary = mark_value
	_inferno_marks.erase(id)
	_inferno_souls += 1 + (1 if _signature_rank() >= 1 else 0)
	var position := Vector2(mark.get("position", Vector2.ZERO))
	_play_vfx("inferno", position, _player_position(), "soul", 1.0)

func _resonance_shatter(target: Node2D, base_damage: float) -> int:
	var status := target.get_node_or_null("StatusEffectComponent") as StatusEffectComponent
	if status == null or not (status.has_effect("slow") or status.has_effect("stun")):
		return 0
	var data := _fusion_data("superconductor")
	var rank := _signature_rank()
	var candidates := _enemies_in_radius(target.global_position, float(data.get("radius", 155.0)) * (1.0 + rank * 0.16), target)
	var affected := 0
	for enemy in candidates:
		var other_status := enemy.get_node_or_null("StatusEffectComponent") as StatusEffectComponent
		if other_status == null or not (other_status.has_effect("slow") or other_status.has_effect("stun")):
			continue
		affected += _damage_target(enemy, base_damage * float(data.get("base_ratio", 0.68)) * (1.0 + rank * 0.22), "superconductor")
		if affected >= 2 + rank * 2:
			break
	return affected

func _aurora_refraction(target: Node2D, base_damage: float) -> int:
	var data := _fusion_data("aurora")
	var rank := _signature_rank()
	var visited := {target.get_instance_id(): true}
	var from := target
	var affected := 0
	for split_index in 1 + rank:
		var next := _nearest_enemy(from.global_position, float(data.get("range", 285.0)), visited)
		if next == null:
			break
		visited[next.get_instance_id()] = true
		affected += _damage_target(next, base_damage * float(data.get("base_ratio", 0.55)) * (1.0 + rank * 0.16), "aurora")
		_play_vfx("aurora", from.global_position, next.global_position, "trail", 1.0)
		from = next
	return affected

func _gravity_collapse(target: Node2D, base_damage: float) -> int:
	var status := target.get_node_or_null("StatusEffectComponent") as StatusEffectComponent
	if status == null or not (status.has_effect("slow") or status.has_effect("stun")):
		return 0
	var data := _fusion_data("void_frost")
	var rank := _signature_rank()
	var enemies := _enemies_in_radius(target.global_position, float(data.get("radius", 170.0)) * (1.0 + rank * 0.2), target)
	var affected := 0
	for enemy in enemies:
		enemy.global_position = enemy.global_position.lerp(target.global_position, minf(0.48, 0.24 + rank * 0.08))
		affected += _damage_target(enemy, base_damage * float(data.get("base_ratio", 0.64)) * (1.0 + rank * 0.2), "void_frost")
	return affected

func _afterglow_circuit(from: Vector2, to: Vector2, base_damage: float) -> int:
	if from.distance_squared_to(to) <= 4.0:
		return 0
	var data := _fusion_data("judgment")
	var rank := _signature_rank()
	if _afterglow_segments.size() >= 32:
		_afterglow_segments.pop_front()
	_afterglow_segments.append({
		"from": from,
		"to": to,
		"base_damage": base_damage,
		"remaining": float(data.get("residual_delay", 0.16)) * GameManager.get_fusion_haste_multiplier(),
		"line_width": float(data.get("line_width", 13.0)) * (1.0 + rank * 0.14),
		"max_targets": int(data.get("max_residual_targets", 2)) + rank,
		"combat_metadata": _damage_metadata.duplicate(true),
	})
	return 1

func _resolve_afterglow_segment(segment: Dictionary) -> void:
	var from := Vector2(segment.get("from", Vector2.ZERO))
	var to := Vector2(segment.get("to", Vector2.ZERO))
	var width := float(segment.get("line_width", 13.0))
	var data := _fusion_data("judgment")
	var damage := float(segment.get("base_damage", 0.0)) * float(data.get("base_ratio", 0.42)) * (1.0 + _signature_rank() * 0.18)
	var center := from.lerp(to, 0.5)
	var search_radius := from.distance_to(to) * 0.5 + width
	var affected := 0
	var previous_metadata := _damage_metadata
	_damage_metadata = segment.get("combat_metadata", {}).duplicate(true)
	for enemy in _enemies_in_radius(center, search_radius, null):
		if _distance_to_segment(enemy.global_position, from, to) > width:
			continue
		if _damage_target(enemy, damage, "judgment") > 0:
			affected += 1
			_play_vfx("judgment", enemy.global_position, enemy.global_position, "hit", 0.78)
		if affected >= int(segment.get("max_targets", 2)):
			break
	_damage_metadata = previous_metadata

func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(from)
	var ratio := clampf((point - from).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(from + segment * ratio)

func _space_jump(target: Node2D, base_damage: float) -> int:
	var data := _fusion_data("voidstorm")
	var rank := _signature_rank()
	var visited := {target.get_instance_id(): true}
	var from := target
	var affected := 0
	for jump_index in 2 + rank:
		var next := _nearest_enemy(from.global_position, float(data.get("range", 360.0)), visited)
		if next == null:
			break
		visited[next.get_instance_id()] = true
		affected += _damage_target(next, base_damage * float(data.get("base_ratio", 0.58)) * pow(0.88, jump_index), "voidstorm")
		_play_vfx("voidstorm", from.global_position, next.global_position, "portal", 1.0)
		from = next
	return affected

func _total_eclipse(target: Node2D, base_damage: float) -> int:
	var data := _fusion_data("eclipse")
	var rank := _signature_rank()
	if _eclipse_remaining <= 0.0:
		_eclipse_gauge += 1
		var needed := maxi(3, int(data.get("gauge_required", 6)) - rank)
		if _eclipse_gauge < needed:
			return 1
		_eclipse_gauge = 0
		_eclipse_remaining = float(data.get("duration", 4.0)) + rank * 1.25
		_play_vfx("eclipse", target.global_position, target.global_position, "state", 1.4)
	var affected := _apply_aoe(target.global_position, base_damage * float(data.get("base_ratio", 0.72)) * (1.0 + rank * 0.22), float(data.get("radius", 175.0)) * (1.0 + rank * 0.15), "eclipse")
	return maxi(affected, 1)

func _apply_aoe(position: Vector2, damage: float, radius: float, fusion_id: String, excluded: Node2D = null) -> int:
	var affected := 0
	for enemy in _enemies_in_radius(position, radius, excluded):
		affected += _damage_target(enemy, damage, fusion_id)
	return affected

func _damage_target(target: Node2D, damage: float, fusion_id: String) -> int:
	var health := target.get_node_or_null("HealthComponent") as HealthComponent
	if health == null or health.current_hp <= 0.0:
		return 0
	var metadata := CombatEventMeta.fork_event(_damage_metadata, "fusion_%s" % fusion_id) if not _damage_metadata.is_empty() else CombatEventMeta.create_secondary("fusion_%s" % fusion_id, _fusion_element_tags(fusion_id), true)
	metadata["is_direct"] = false
	metadata["is_triggered"] = true
	metadata["element_tags"] = _fusion_element_tags(fusion_id)
	var actual := health.apply_secondary_damage(damage * GameManager.get_fusion_damage_multiplier(), metadata)
	if actual <= 0.0:
		return 0
	EventBus.element_damage_dealt.emit(actual, target.global_position, "fusion_%s" % fusion_id, 3, 0)
	return 1

func _fusion_element_tags(fusion_id: String) -> Array:
	var tags: Array = ["fusion", fusion_id]
	for element_id in _fusion_data(fusion_id).get("elements", []):
		var full_id := String(element_id)
		for tag in [full_id, full_id.trim_prefix("element_")]:
			if tag not in tags:
				tags.append(tag)
	return tags

func _enemies_in_radius(position: Vector2, radius: float, excluded: Node2D) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if candidate == excluded or candidate == null or not is_instance_valid(candidate) or not (candidate is Node2D):
			continue
		var health := candidate.get_node_or_null("HealthComponent") as HealthComponent
		if health and health.current_hp > 0.0 and (candidate as Node2D).global_position.distance_to(position) <= radius:
			result.append(candidate as Node2D)
	return result

func _nearest_enemy(position: Vector2, radius: float, visited: Dictionary) -> Node2D:
	var nearest: Node2D
	var nearest_distance := radius
	for enemy in _enemies_in_radius(position, radius, null):
		if visited.has(enemy.get_instance_id()):
			continue
		var distance := enemy.global_position.distance_to(position)
		if distance <= nearest_distance:
			nearest = enemy
			nearest_distance = distance
	return nearest

func _target_priority(target: Node2D) -> float:
	var health := target.get_node_or_null("HealthComponent") as HealthComponent
	var priority := health.max_hp if health else 0.0
	var data: Variant = target.get("enemy_data")
	if data is BossData:
		priority += 1000000.0
	elif bool(target.get_meta("is_elite", false)):
		priority += 100000.0
	return priority

func _fusion_data(fusion_id: String) -> Dictionary:
	return Dictionary(DataLoader.element_combat_config.get("fusions", {})).get(fusion_id, {})

func _signature_rank() -> int:
	return GameManager.get_fusion_mastery_rank("signature")

func _player_position() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	return player.global_position if player else Vector2.ZERO

func _play_vfx(fusion_id: String, from: Vector2, to: Vector2, mode: String, intensity: float) -> void:
	var vfx := get_tree().get_first_node_in_group("attack_vfx_manager") as AttackVFXManager
	if vfx:
		vfx.play_fusion_effect(fusion_id, from, to, mode, intensity)
