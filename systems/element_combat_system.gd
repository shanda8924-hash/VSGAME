extends Node2D
class_name ElementCombatSystem
## ベースHit確定後の5属性Gameplayと、成立済みFusionの継承Trait・第3Traitを担当する。
## UI/VFXの取得イベントからは呼ばれず、二次Damageはこの入口へ戻らない。

signal chain_link_spawned(from: Vector2, to: Vector2, jump_index: int, damage: float)
signal element_echo_triggered(element_id: String, target: Node2D)
signal fusion_echo_triggered(fusion_id: String, target: Node2D)

var _burning_targets: Dictionary = {}
var _burn_death_connections: Dictionary = {}
var _light_trigger_progress: int = 0
var _fusion_runtime: FusionCombatRuntime
var _proc_rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("element_combat_system")
	_proc_rng.randomize()
	_fusion_runtime = FusionCombatRuntime.new()
	_fusion_runtime.name = "FusionCombatRuntime"
	add_child(_fusion_runtime)
	_fusion_runtime.setup(self)
	EventBus.run_started.connect(reset_runtime)
	EventBus.run_ended.connect(func(_seconds, _kills): reset_runtime())

func set_proc_seed(seed_value: int) -> void:
	_proc_rng.seed = seed_value

func reset_runtime() -> void:
	for id_variant in _burn_death_connections.keys():
		_disconnect_burn_death_callback(int(id_variant))
	_burning_targets.clear()
	_light_trigger_progress = 0
	if _fusion_runtime:
		_fusion_runtime.reset_runtime()

func get_fusion_debug_snapshot() -> Dictionary:
	return _fusion_runtime.get_debug_snapshot() if _fusion_runtime else {}

func is_target_burning(target: Node2D) -> bool:
	return target != null and _burning_targets.has(target.get_instance_id())

func _process(delta: float) -> void:
	for id_variant in _burning_targets.keys():
		var id := int(id_variant)
		var entry: Dictionary = _burning_targets.get(id, {})
		if entry.is_empty():
			continue
		var health_ref: Variant = entry.get("health")
		if health_ref == null or not is_instance_valid(health_ref):
			_retire_burning_target(id)
			continue
		var health := health_ref as HealthComponent
		if health == null or health.current_hp <= 0.0:
			_retire_burning_target(id)
			continue
		entry["remaining"] = float(entry["remaining"]) - delta
		if float(entry["remaining"]) <= 0.0:
			_retire_burning_target(id)
			continue
		entry["tick_timer"] = float(entry["tick_timer"]) - delta
		if float(entry["tick_timer"]) <= 0.0:
			entry["tick_timer"] = float(entry["tick_interval"])
			var target_ref: Variant = entry.get("target")
			if target_ref == null or not is_instance_valid(target_ref):
				_retire_burning_target(id)
				continue
			var target := target_ref as Node2D
			var burn_meta: Dictionary = entry.get("combat_metadata", {})
			var actual := health.apply_secondary_damage(float(entry["tick_damage"]), _element_damage_meta("element_fire", burn_meta, "burn"))
			if actual > 0.0:
				EventBus.element_damage_dealt.emit(actual, target.global_position, "element_fire", int(entry["stack"]), 0)
			if health.current_hp <= 0.0:
				_retire_burning_target(id)
				continue
		# A Burn death explosion can synchronously remove another ID still present in
		# this frame's key snapshot. Never resurrect an entry removed by that callback.
		if _burning_targets.has(id):
			_burning_targets[id] = entry

func apply_element_damage(hit_hurtbox: HurtboxComponent, base_damage: float, origin_position: Vector2 = Vector2.ZERO, proc_context: Dictionary = {}) -> Dictionary:
	var result := {"total_damage": 0.0, "hits": 0, "chains": 0, "element_echoes": 0, "fusion_procs": 0, "fusion_echoes": 0}
	if hit_hurtbox == null or base_damage <= 0.0:
		return result
	var target := hit_hurtbox.get_owner_entity() as Node2D
	if target == null or not is_instance_valid(target) or not target.is_in_group("enemies"):
		return result
	var health := target.get_node_or_null("HealthComponent") as HealthComponent
	if health == null:
		return result
	var target_was_defeated := health.current_hp <= 0.0
	var active_ids := GameManager.get_active_element_ids()
	var fusion_id := GameManager.active_fusion_id
	var can_echo := not bool(proc_context.get("is_secondary_proc", false)) and bool(proc_context.get("can_trigger_echo", true))
	for element_id in active_ids:
		# ベースHitで起点が倒れた場合もLightning Chainだけは生存中の次Targetへ進める。
		if target_was_defeated and element_id != "element_lightning":
			continue
		_merge_result(result, _apply_element_once(element_id, target, health, base_damage, origin_position, fusion_id, proc_context))
		if can_echo and health.current_hp > 0.0 and _proc_rng.randf() < GameManager.get_element_echo_chance(element_id):
			_merge_result(result, _apply_element_once(element_id, target, health, base_damage, origin_position, fusion_id, proc_context))
			result["element_echoes"] = int(result["element_echoes"]) + 1
			element_echo_triggered.emit(element_id, target)
	if fusion_id != "" and not target_was_defeated and health.current_hp > 0.0:
		var parent_metadata: Dictionary = proc_context.get("combat_metadata", {})
		var fusion_result := _fusion_runtime.apply_signature(fusion_id, target, health, base_damage, origin_position, false, parent_metadata)
		result["fusion_procs"] = int(result["fusion_procs"]) + int(fusion_result.get("fusion_procs", 0))
		_play_fusion_attack(fusion_id, origin_position, target.global_position, false)
		if can_echo and _proc_rng.randf() < GameManager.get_fusion_echo_chance():
			var echo_result := _fusion_runtime.apply_signature(fusion_id, target, health, base_damage, origin_position, true, parent_metadata)
			result["fusion_procs"] = int(result["fusion_procs"]) + int(echo_result.get("fusion_procs", 0))
			result["fusion_echoes"] = int(result["fusion_echoes"]) + 1
			fusion_echo_triggered.emit(fusion_id, target)
			_play_fusion_attack(fusion_id, origin_position, target.global_position, true)
	return result

func _apply_element_once(element_id: String, target: Node2D, health: HealthComponent, base_damage: float, origin_position: Vector2, fusion_id: String, proc_context: Dictionary = {}) -> Dictionary:
	var result := {"total_damage": 0.0, "hits": 0, "chains": 0}
	var stack := GameManager.get_element_stack(element_id)
	var ratio := _damage_ratio(element_id, stack) * GameManager.get_element_damage_multiplier(element_id)
	if fusion_id != "":
		ratio *= GameManager.get_fusion_damage_multiplier()
	if ratio <= 0.0:
		return result
	var requested := base_damage * ratio
	var parent_meta: Dictionary = proc_context.get("combat_metadata", {})
	var damage_meta := _element_damage_meta(element_id, parent_meta, "hit")
	var actual := health.apply_secondary_damage(requested, damage_meta)
	if actual > 0.0:
		result["total_damage"] = actual
		result["hits"] = 1
		EventBus.element_damage_dealt.emit(actual, target.global_position, element_id, stack, 0)
		if fusion_id == "":
			var element_vfx := get_tree().get_first_node_in_group("attack_vfx_manager") as AttackVFXManager
			if element_vfx:
				element_vfx.play_element_hit(target.global_position, DataLoader.element_vfx_effects.get(element_id), stack)
	var applied_damage := actual if actual > 0.0 else requested
	match element_id:
		"element_fire": _apply_fire_role(target, health, base_damage, applied_damage, stack, damage_meta)
		"element_ice": _apply_ice_role(target, stack)
		"element_lightning": result["chains"] = _apply_lightning_chain(target, applied_damage, stack, fusion_id, damage_meta)
		"element_light": _apply_light_role(target, health, base_damage, stack, fusion_id == "", damage_meta)
		"element_dark": _apply_dark_role(health, stack)
	return result

func _merge_result(total: Dictionary, addition: Dictionary) -> void:
	for key in ["total_damage", "hits", "chains"]:
		total[key] = total.get(key, 0) + addition.get(key, 0)

func _damage_ratio(element_id: String, stack: int) -> float:
	var ratios: Array = _element_config(element_id).get("damage_ratios", [])
	if ratios.is_empty() or stack <= 0:
		return 0.0
	return float(ratios[clampi(stack - 1, 0, ratios.size() - 1)])

func _element_config(element_id: String) -> Dictionary:
	var elements: Dictionary = DataLoader.element_combat_config.get("elements", {})
	return elements.get(element_id, {})

func _apply_fire_role(target: Node2D, health: HealthComponent, base_damage: float, hit_damage: float, stack: int, parent_metadata: Dictionary = {}) -> void:
	if stack <= 0 or hit_damage <= 0.0:
		return
	var burn: Dictionary = _element_config("element_fire").get("burn", {})
	var signature_rank := GameManager.get_element_mastery_rank("element_fire", "signature")
	var reach := GameManager.get_element_reach_multiplier("element_fire")
	var radii: Array = burn.get("aoe_radius", [])
	var aoe_radius := float(radii[clampi(stack - 1, 0, radii.size() - 1)]) * reach if not radii.is_empty() else 0.0
	if aoe_radius > 0.0:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy == target or not is_instance_valid(enemy) or not (enemy is Node2D):
				continue
			var enemy_node := enemy as Node2D
			if enemy_node.global_position.distance_to(target.global_position) > aoe_radius:
				continue
			var other_health := enemy.get_node_or_null("HealthComponent") as HealthComponent
			var splash := other_health.apply_secondary_damage(hit_damage * float(burn.get("aoe_damage_ratio", 0.5)), _element_damage_meta("element_fire", parent_metadata, "aoe")) if other_health else 0.0
			if splash > 0.0:
				EventBus.element_damage_dealt.emit(splash, enemy_node.global_position, "element_fire", stack, 0)
	var tick_ratios: Array = burn.get("tick_damage_ratios", [])
	var durations: Array = burn.get("duration", [])
	if tick_ratios.is_empty() or durations.is_empty():
		return
	var tick_damage := base_damage * float(tick_ratios[clampi(stack - 1, 0, tick_ratios.size() - 1)]) * (1.0 + signature_rank * 0.15) * GameManager.get_element_damage_multiplier("element_fire")
	var duration := float(durations[clampi(stack - 1, 0, durations.size() - 1)]) + signature_rank * 0.4
	var tick_interval := float(burn.get("tick_interval", 0.5)) * GameManager.get_element_haste_multiplier()
	var id := target.get_instance_id()
	_burning_targets[id] = {"target": target, "health": health, "remaining": duration, "tick_timer": tick_interval, "tick_interval": tick_interval, "tick_damage": tick_damage, "stack": stack, "base_damage": base_damage, "combat_metadata": parent_metadata.duplicate(true)}
	if stack >= 3 and not _burn_death_connections.has(id):
		var callback := _on_burning_target_died.bind(id)
		if not health.died.is_connected(callback):
			health.died.connect(callback, CONNECT_ONE_SHOT)
		_burn_death_connections[id] = {"health": health, "callback": callback}
	elif stack < 3 and _burn_death_connections.has(id):
		_disconnect_burn_death_callback(id)

func _on_burning_target_died(id: int) -> void:
	_burn_death_connections.erase(id)
	var entry: Dictionary = _burning_targets.get(id, {})
	if entry.is_empty():
		return
	_burning_targets.erase(id)
	var target_ref: Variant = entry.get("target")
	if target_ref == null or not is_instance_valid(target_ref):
		return
	var target := target_ref as Node2D
	var burn: Dictionary = _element_config("element_fire").get("burn", {})
	var radius := float(burn.get("death_explosion_radius", 105.0)) * GameManager.get_element_reach_multiplier("element_fire")
	var signature_rank := GameManager.get_element_mastery_rank("element_fire", "signature")
	var damage := float(entry.get("base_damage", 100.0)) * _damage_ratio("element_fire", int(entry.get("stack", 3))) * float(burn.get("death_explosion_damage_ratio", 0.75)) * (1.0 + signature_rank * 0.2)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == target or not is_instance_valid(enemy) or not (enemy is Node2D) or (enemy as Node2D).global_position.distance_to(target.global_position) > radius:
			continue
		var other_health := enemy.get_node_or_null("HealthComponent") as HealthComponent
		var actual := other_health.apply_secondary_damage(damage, _element_damage_meta("element_fire", entry.get("combat_metadata", {}), "death_burst")) if other_health else 0.0
		if actual > 0.0:
			EventBus.element_damage_dealt.emit(actual, (enemy as Node2D).global_position, "element_fire", int(entry.get("stack", 3)), 0)

func _retire_burning_target(id: int) -> void:
	_burning_targets.erase(id)
	_disconnect_burn_death_callback(id)

func _disconnect_burn_death_callback(id: int) -> void:
	var connection: Dictionary = _burn_death_connections.get(id, {})
	_burn_death_connections.erase(id)
	if connection.is_empty():
		return
	var health_ref: Variant = connection.get("health")
	if health_ref == null or not is_instance_valid(health_ref):
		return
	var health := health_ref as HealthComponent
	var callback: Callable = connection.get("callback", Callable())
	if health != null and callback.is_valid() and health.died.is_connected(callback):
		health.died.disconnect(callback)

func _apply_ice_role(target: Node2D, stack: int) -> void:
	var status := target.get_node_or_null("StatusEffectComponent") as StatusEffectComponent
	if stack <= 0 or status == null:
		return
	var slow: Dictionary = _element_config("element_ice").get("slow", {})
	var durations: Array = slow.get("duration", [])
	var multipliers: Array = slow.get("speed_multiplier", [])
	if not durations.is_empty() and not multipliers.is_empty():
		status.apply_effect("slow", float(durations[clampi(stack - 1, 0, durations.size() - 1)]), float(multipliers[clampi(stack - 1, 0, multipliers.size() - 1)]))
	var freeze: Dictionary = _element_config("element_ice").get("freeze", {})
	var chances: Array = freeze.get("chance", [])
	var freeze_durations: Array = freeze.get("duration_by_stack", [])
	if chances.is_empty():
		return
	var signature_rank := GameManager.get_element_mastery_rank("element_ice", "signature")
	var chance := minf(0.95, float(chances[clampi(stack - 1, 0, chances.size() - 1)]) + signature_rank * 0.12)
	if _proc_rng.randf() < chance:
		var duration := float(freeze_durations[clampi(stack - 1, 0, freeze_durations.size() - 1)]) if not freeze_durations.is_empty() else 0.6
		status.apply_effect("stun", duration + signature_rank * 0.15)

func _apply_lightning_chain(first_target: Node2D, initial_damage: float, stack: int, fusion_id: String, parent_metadata: Dictionary = {}) -> int:
	var chain: Dictionary = _element_config("element_lightning").get("chain", {})
	var jump_counts: Array = chain.get("jump_counts", [1, 2, 4])
	var decay_ratios: Array = chain.get("decay_ratios", [0.75, 0.55, 0.4])
	var ranges: Array = chain.get("range_by_stack", [])
	var max_jumps := int(jump_counts[clampi(stack - 1, 0, jump_counts.size() - 1)]) + GameManager.get_element_mastery_rank("element_lightning", "signature")
	var chain_range := (float(ranges[clampi(stack - 1, 0, ranges.size() - 1)]) if not ranges.is_empty() else 220.0) * GameManager.get_element_reach_multiplier("element_lightning")
	var visited := {first_target.get_instance_id(): true}
	var previous := first_target
	var made := 0
	for jump_index in max_jumps:
		var next_target := _find_chain_target(previous.global_position, chain_range, visited)
		if next_target == null:
			break
		visited[next_target.get_instance_id()] = true
		var decay := float(decay_ratios[mini(jump_index, decay_ratios.size() - 1)]) if not decay_ratios.is_empty() else pow(0.7, jump_index + 1)
		var next_health := next_target.get_node_or_null("HealthComponent") as HealthComponent
		var actual := next_health.apply_secondary_damage(initial_damage * decay, _element_damage_meta("element_lightning", parent_metadata, "chain")) if next_health else 0.0
		if actual > 0.0:
			made += 1
			EventBus.element_damage_dealt.emit(actual, next_target.global_position, "element_lightning", stack, jump_index + 1)
			chain_link_spawned.emit(previous.global_position, next_target.global_position, jump_index + 1, actual)
			# Lightning FusionはChain先でも相方属性の攻撃文法を継承する。
			# 追加Damageはsecondary経路だけを使うため、Element/Fusion Procへ再帰しない。
			if fusion_id == "plasma":
				var fire_stack := GameManager.get_element_stack("element_fire")
				_apply_fire_role(next_target, next_health, initial_damage, actual, fire_stack, parent_metadata)
			elif fusion_id == "judgment":
				var light_stack := GameManager.get_element_stack("element_light")
				_apply_light_role(next_target, next_health, initial_damage, light_stack, false)
			if _fusion_runtime and fusion_id in ["plasma", "judgment"]:
				_fusion_runtime.apply_chain_reaction(fusion_id, previous.global_position, next_target.global_position, next_target, next_health, actual, parent_metadata)
			var vfx := get_tree().get_first_node_in_group("attack_vfx_manager") as AttackVFXManager
			if vfx:
				if fusion_id == "":
					vfx.play_lightning_chain(previous.global_position, next_target.global_position, stack, jump_index + 1)
				else:
					vfx.play_fusion_effect(fusion_id, previous.global_position, next_target.global_position, "trail", 0.9)
					vfx.play_fusion_effect(fusion_id, next_target.global_position, next_target.global_position, "hit", 0.82)
		previous = next_target
	return made

func _find_chain_target(from_position: Vector2, chain_range: float, visited: Dictionary) -> Node2D:
	var nearest: Node2D
	var nearest_distance := chain_range
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if candidate == null or not is_instance_valid(candidate) or visited.has(candidate.get_instance_id()):
			continue
		var health := candidate.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.current_hp <= 0.0:
			continue
		var distance := from_position.distance_to((candidate as Node2D).global_position)
		if distance <= nearest_distance:
			nearest = candidate as Node2D
			nearest_distance = distance
	return nearest

func _apply_light_role(target: Node2D, health: HealthComponent, base_damage: float, stack: int, show_element_vfx: bool, parent_metadata: Dictionary = {}) -> void:
	var holy: Dictionary = _element_config("element_light").get("holy_strike", {})
	var trigger_counts: Array = holy.get("trigger_counts", [])
	if stack <= 0 or trigger_counts.is_empty():
		return
	_light_trigger_progress += 1
	var signature_rank := GameManager.get_element_mastery_rank("element_light", "signature")
	var needed := maxi(1, int(trigger_counts[clampi(stack - 1, 0, trigger_counts.size() - 1)]) - signature_rank)
	if _light_trigger_progress < needed:
		return
	_light_trigger_progress = 0
	var bonus_ratios: Array = holy.get("bonus_damage_ratio", [])
	var bonus_ratio := float(bonus_ratios[clampi(stack - 1, 0, bonus_ratios.size() - 1)]) if not bonus_ratios.is_empty() else 0.0
	var actual := health.apply_secondary_damage(base_damage * bonus_ratio * (1.0 + signature_rank * 0.2), _element_damage_meta("element_light", parent_metadata, "holy"))
	if actual > 0.0:
		EventBus.element_damage_dealt.emit(actual, target.global_position, "element_light", stack, 0)
	var shield_ratios: Array = holy.get("shield_max_hp_ratio", [])
	var player := get_tree().get_first_node_in_group("player") as Node
	if player and not shield_ratios.is_empty():
		var player_health := player.get_node_or_null("HealthComponent") as HealthComponent
		if player_health:
			player_health.grant_temporary_shield(player_health.max_hp * float(shield_ratios[clampi(stack - 1, 0, shield_ratios.size() - 1)]) * (1.0 + signature_rank * 0.15))
	if show_element_vfx:
		var vfx := get_tree().get_first_node_in_group("attack_vfx_manager") as AttackVFXManager
		if vfx:
			vfx.play_element_hit(target.global_position, DataLoader.element_vfx_effects.get("element_light"), mini(stack + 1, 3))

func _apply_dark_role(health: HealthComponent, stack: int) -> void:
	var curse: Dictionary = _element_config("element_dark").get("curse", {})
	var durations: Array = curse.get("duration", [])
	var ratios: Array = curse.get("bonus_damage_taken_ratio", [])
	if stack <= 0 or durations.is_empty() or ratios.is_empty():
		return
	var signature_rank := GameManager.get_element_mastery_rank("element_dark", "signature")
	var duration := float(durations[clampi(stack - 1, 0, durations.size() - 1)]) + signature_rank * 0.75
	var ratio := float(ratios[clampi(stack - 1, 0, ratios.size() - 1)]) + signature_rank * 0.08
	health.apply_curse(1.0 + ratio, duration)

func _play_fusion_attack(fusion_id: String, from: Vector2, to: Vector2, is_echo: bool) -> void:
	var vfx := get_tree().get_first_node_in_group("attack_vfx_manager") as AttackVFXManager
	if vfx:
		vfx.play_fusion_effect(fusion_id, from, to, "attack", 1.12 if is_echo else 1.0)

func _element_damage_meta(element_id: String, parent_metadata: Dictionary, suffix: String) -> Dictionary:
	var combo_eligible := suffix != "burn"
	var metadata := CombatEventMeta.fork_event(parent_metadata, "%s:%s" % [element_id, suffix]) if not parent_metadata.is_empty() else CombatEventMeta.create_secondary("%s:%s" % [element_id, suffix], [element_id], combo_eligible)
	metadata["is_direct"] = false
	metadata["is_triggered"] = true
	metadata["element_tags"] = [element_id]
	metadata["is_critical"] = false
	metadata["combo_eligible"] = combo_eligible and bool(metadata.get("combo_eligible", true))
	return metadata
