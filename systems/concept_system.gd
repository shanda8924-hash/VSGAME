extends Node
class_name ConceptSystem

signal inventory_changed()
signal board_changed()
signal skill_triggered(chain_index: int, skill_id: String, generation_depth: int)
signal completed_skill_changed(skill_id: String, level: int)
signal completed_skill_triggered(skill_id: String, level: int)

const CONFIG_PATH := "res://data/balance/concept_system.json"
const COMPLETED_SKILLS_PATH := "res://data/skills/completed_skills.json"
const SLOT_TYPES := ["trigger", "skill", "modifier"]
const MAX_COMPLETED_SKILLS := 6

@export var combo_system_path: NodePath

@onready var combo_system: ComboSystem = get_node(combo_system_path)

var acquired_ids: Array[String] = []
var chains: Array[Dictionary] = [
	{"trigger": "", "skill": "", "modifier": ""},
	{"trigger": "", "skill": "", "modifier": ""},
]
var _config: Dictionary = {}
var _completed_skill_definitions: Dictionary = {}
var _completed_skill_order: Array[String] = []
var completed_skill_levels: Dictionary = {}
var _active: bool = false
var _direct_hit_counts: Dictionary = {}
var _completed_hit_counts: Dictionary = {}
var _completed_charge_counts: Dictionary = {}
var _processed_trigger_keys: Dictionary = {}
var _completed_skill_cooldowns: Dictionary = {}
var _runtime_epoch: int = 0


func _ready() -> void:
	_config = _load_config()
	_load_completed_skills()
	EventBus.enemy_damage_confirmed.connect(_on_enemy_damage_confirmed)
	combo_system.combo_advanced.connect(_on_combo_advanced)
	EventBus.run_started.connect(reset_runtime)
	EventBus.run_ended.connect(func(_seconds, _kills): reset_runtime())


func set_active(active: bool) -> void:
	_active = active
	if not active:
		_direct_hit_counts.clear()


func _process(delta: float) -> void:
	if not _active or GameManager.run_state != GameManager.RunState.PLAYING or completed_skill_levels.is_empty():
		return
	for skill_id_variant in completed_skill_levels.keys():
		var skill_id := String(skill_id_variant)
		var definition: Dictionary = _completed_skill_definitions.get(skill_id, {})
		if String(definition.get("trigger_kind", "")) != "cooldown_auto":
			continue
		var remaining := maxf(float(_completed_skill_cooldowns.get(skill_id, 0.0)) - delta, 0.0)
		_completed_skill_cooldowns[skill_id] = remaining
		if remaining > 0.0:
			continue
		var target := _signature_auto_target(definition)
		if target:
			_activate_signature_skill(skill_id, definition, get_completed_skill_level(skill_id), target)


func reset_runtime() -> void:
	_runtime_epoch += 1
	acquired_ids.clear()
	chains = [
		{"trigger": "", "skill": "", "modifier": ""},
		{"trigger": "", "skill": "", "modifier": ""},
	]
	_direct_hit_counts.clear()
	_completed_hit_counts.clear()
	_completed_charge_counts.clear()
	completed_skill_levels.clear()
	_completed_skill_cooldowns.clear()
	_processed_trigger_keys.clear()
	inventory_changed.emit()
	board_changed.emit()


func acquire_concept(concept_id: String) -> bool:
	if concept_id in acquired_ids or DataLoader.get_concept(concept_id) == null:
		return false
	acquired_ids.append(concept_id)
	inventory_changed.emit()
	return true


func equip_concept(chain_index: int, slot_type: String, concept_id: String) -> bool:
	if chain_index < 0 or chain_index >= chains.size() or slot_type not in SLOT_TYPES or concept_id not in acquired_ids:
		return false
	var data := DataLoader.get_concept(concept_id)
	if data == null or data.concept_type != slot_type:
		return false
	chains[chain_index][slot_type] = concept_id
	board_changed.emit()
	return true


func unequip_concept(chain_index: int, slot_type: String) -> void:
	if chain_index < 0 or chain_index >= chains.size() or slot_type not in SLOT_TYPES:
		return
	chains[chain_index][slot_type] = ""
	board_changed.emit()


func get_owned_concepts(concept_type: String = "") -> Array[ConceptData]:
	var result: Array[ConceptData] = []
	for concept_id in acquired_ids:
		var data := DataLoader.get_concept(concept_id)
		if data and (concept_type == "" or data.concept_type == concept_type):
			result.append(data)
	return result


func get_unowned_concepts() -> Array[ConceptData]:
	var result: Array[ConceptData] = []
	for data in DataLoader.get_all_concepts():
		if data.id not in acquired_ids:
			result.append(data)
	return result


func get_chain(chain_index: int) -> Dictionary:
	return chains[chain_index].duplicate(true) if chain_index >= 0 and chain_index < chains.size() else {}


func get_balance_value(key: String, fallback: Variant) -> Variant:
	return _config.get(key, fallback)


func get_completed_skill_definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for skill_id in _completed_skill_order:
		result.append((_completed_skill_definitions.get(skill_id, {}) as Dictionary).duplicate(true))
	return result


func get_completed_skill_definition(skill_id: String) -> Dictionary:
	return (_completed_skill_definitions.get(skill_id, {}) as Dictionary).duplicate(true)


func get_completed_skill_level(skill_id: String) -> int:
	return int(completed_skill_levels.get(skill_id, 0))


func get_completed_skill_count() -> int:
	return completed_skill_levels.size()


func get_completed_skill_cooldown(skill_id: String) -> float:
	return maxf(float(_completed_skill_cooldowns.get(skill_id, 0.0)), 0.0)


func get_completed_skill_cooldown_total(skill_id: String) -> float:
	var definition: Dictionary = _completed_skill_definitions.get(skill_id, {})
	if definition.is_empty():
		return 0.0
	return _signature_cooldown_total(definition, maxi(get_completed_skill_level(skill_id), 1))


func acquire_completed_skill(skill_id: String) -> int:
	var definition: Dictionary = _completed_skill_definitions.get(skill_id, {})
	if definition.is_empty():
		return 0
	var current := get_completed_skill_level(skill_id)
	var maximum := maxi(int(definition.get("max_level", 3)), 1)
	if current <= 0 and completed_skill_levels.size() >= MAX_COMPLETED_SKILLS:
		return 0
	if current >= maximum:
		return current
	var next_level := current + 1
	completed_skill_levels[skill_id] = next_level
	if String(definition.get("trigger_kind", "")) == "cooldown_auto":
		var total := _signature_cooldown_total(definition, next_level)
		if current <= 0:
			_completed_skill_cooldowns[skill_id] = minf(total, float(_config.get("signature_initial_delay", 1.1)))
		else:
			_completed_skill_cooldowns[skill_id] = minf(get_completed_skill_cooldown(skill_id), total)
	inventory_changed.emit()
	completed_skill_changed.emit(skill_id, next_level)
	return next_level


## 属性システム廃止に伴い、所持属性による解放条件を撤廃した。現在は全ての完成大技が
## 常に候補になる。
## TODO: 将来、天賦図の取得状況(どの状態異常を付与できるビルドか)で候補を絞る。
## 引数は呼び出し元(map_run_controller)の互換のために残してある。
func is_completed_skill_available_for_build(_definition: Dictionary, _unused: Array = []) -> bool:
	return true


func get_completed_skill_display_name(skill_id: String) -> String:
	var definition := get_completed_skill_definition(skill_id)
	return UiText.get_text(String(definition.get("name_key", skill_id)), skill_id)


func get_completed_skill_description(skill_id: String, level: int) -> String:
	var definition := get_completed_skill_definition(skill_id)
	var keys: Array = definition.get("description_keys", [])
	if keys.is_empty():
		return ""
	var key := String(keys[clampi(level - 1, 0, keys.size() - 1)])
	return UiText.get_text(key, key)


func _on_enemy_damage_confirmed(target: Node, _amount: float, is_critical: bool, metadata: Dictionary) -> void:
	if not _active or GameManager.run_state != GameManager.RunState.PLAYING:
		return
	var source_kind := String(metadata.get("source_kind", ""))
	if source_kind in ["non_player_hit", "debug_room_clear"]:
		return
	var direct_hit_count := 0
	if bool(metadata.get("is_direct", false)) and not bool(metadata.get("is_triggered", false)) and is_instance_valid(target):
		var target_id := target.get_instance_id()
		direct_hit_count = int(_direct_hit_counts.get(target_id, 0)) + 1
		_direct_hit_counts[target_id] = direct_hit_count
	if bool(metadata.get("killed", false)) and is_instance_valid(target):
		_direct_hit_counts.erase(target.get_instance_id())
	for chain_index in chains.size():
		var trigger := _concept_for_slot(chain_index, "trigger")
		if trigger == null:
			continue
		var kind := String(trigger.params.get("trigger_kind", ""))
		var should_trigger := false
		match kind:
			"on_critical": should_trigger = is_critical and bool(metadata.get("is_direct", false)) and not bool(metadata.get("is_triggered", false))
			"fifth_hit": should_trigger = direct_hit_count > 0 and direct_hit_count % maxi(int(_config.get("fifth_hit_count", 5)), 1) == 0
			"on_kill": should_trigger = bool(metadata.get("killed", false))
		if should_trigger:
			_try_trigger(chain_index, target, metadata)
	_process_completed_skills_on_hit(target as Node2D, is_critical, direct_hit_count, metadata)


func _on_combo_advanced(value: int, target: Node, metadata: Dictionary) -> void:
	if not _active:
		return
	var interval := maxi(int(_config.get("combo_trigger_interval", 20)), 1)
	if value % interval != 0:
		return
	for chain_index in chains.size():
		var trigger := _concept_for_slot(chain_index, "trigger")
		if trigger and String(trigger.params.get("trigger_kind", "")) == "combo":
			_try_trigger(chain_index, target, metadata)


func _try_trigger(chain_index: int, target: Node, parent_metadata: Dictionary) -> void:
	var skill := _concept_for_slot(chain_index, "skill")
	if skill == null:
		return
	var depth := int(parent_metadata.get("generation_depth", 0))
	if depth >= maxi(int(_config.get("max_trigger_depth", 2)), 0):
		return
	var lineage: Array = parent_metadata.get("triggered_chain_indices", [])
	if chain_index in lineage:
		return
	var guard_key := "%s:%d" % [str(parent_metadata.get("event_id", 0)), chain_index]
	if _processed_trigger_keys.has(guard_key):
		return
	_processed_trigger_keys[guard_key] = true
	if _processed_trigger_keys.size() > 2048:
		_processed_trigger_keys.clear()
	var position: Vector2 = parent_metadata.get("impact_position", Vector2.ZERO)
	if target is Node2D and is_instance_valid(target):
		position = (target as Node2D).global_position
	var skill_meta := CombatEventMeta.create_triggered(parent_metadata, "concept:%s" % skill.id, skill.element_tags, chain_index, true)
	var modifier := _concept_for_slot(chain_index, "modifier")
	_execute_skill(chain_index, skill, modifier, target as Node2D, position, skill_meta, false)
	skill_triggered.emit(chain_index, skill.id, int(skill_meta.get("generation_depth", 0)))


func _execute_skill(chain_index: int, skill: ConceptData, modifier: ConceptData, preferred_target: Node2D, position: Vector2, skill_meta: Dictionary, is_echo: bool, skill_level: int = 1) -> void:
	var target := _resolve_target(preferred_target, position)
	var center := target.global_position if target else position
	var radius := float(skill.params.get("radius", _config.get("skill_base_radius", 82.0)))
	var modifier_kind := String(modifier.params.get("modifier_kind", "")) if modifier else ""
	if modifier_kind == "area":
		radius *= float(_config.get("area_multiplier", 1.55))
	radius *= 1.0 + 0.14 * float(maxi(skill_level - 1, 0))
	var completed_definition := _completed_definition_from_metadata(skill_meta)
	if not completed_definition.is_empty():
		radius *= _definition_level_value(completed_definition, "radius_multiplier_by_level", skill_level, 1.0)
	_apply_skill_at(skill, center, radius, skill_meta, skill_level)
	if is_echo:
		return
	match modifier_kind:
		"chain":
			var excluded := {target.get_instance_id(): true} if target else {}
			var chain_count := int(_config.get("chain_target_count", 2)) + maxi(skill_level - 1, 0)
			for chained_target in _nearest_enemies(center, float(_config.get("chain_range", 260.0)), chain_count, excluded):
				_apply_skill_at(skill, chained_target.global_position, radius, CombatEventMeta.fork_event(skill_meta, "concept:%s:chain" % skill.id), skill_level)
		"echo":
			_schedule_repeat(chain_index, skill, target, center, skill_meta, float(_config.get("echo_delay", 0.22)), "echo", skill_level)
		"focus":
			_schedule_repeat(chain_index, skill, target, center, skill_meta, float(_config.get("focus_delay", 0.18)), "focus", skill_level)


func _schedule_repeat(chain_index: int, skill: ConceptData, target: Node2D, position: Vector2, metadata: Dictionary, delay: float, repeat_kind: String, skill_level: int = 1) -> void:
	var epoch := _runtime_epoch
	await get_tree().create_timer(maxf(delay, 0.02), false).timeout
	if epoch != _runtime_epoch or not _active:
		return
	if repeat_kind == "focus":
		if not is_instance_valid(target):
			return
		var health := target.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.current_hp <= 0.0:
			return
	# EchoはTarget消滅後も元の着弾地点で成立するが、解放済みObjectを型付き引数へ
	# 渡してはいけない。await終了時点で有効な参照だけを再構成する。
	var repeat_target: Node2D = null
	if is_instance_valid(target):
		repeat_target = target
	_execute_skill(chain_index, skill, null, repeat_target, position, CombatEventMeta.fork_event(metadata, "concept:%s:repeat" % skill.id), true, skill_level)


func _apply_skill_at(skill: ConceptData, center: Vector2, radius: float, skill_meta: Dictionary, skill_level: int = 1) -> void:
	_play_skill_vfx(skill, center, radius, skill_meta, skill_level)
	var damage := _player_skill_damage_basis() * float(skill.params.get("damage_multiplier", 1.0)) * (1.0 + 0.28 * float(maxi(skill_level - 1, 0)))
	var completed_definition := _completed_definition_from_metadata(skill_meta)
	if not completed_definition.is_empty():
		damage *= _definition_level_value(completed_definition, "damage_multiplier_by_level", skill_level, 1.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not (enemy is Node2D) or (enemy as Node2D).global_position.distance_to(center) > radius:
			continue
		var health := enemy.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.current_hp <= 0.0:
			continue
		var hit_meta := CombatEventMeta.fork_event(skill_meta)
		var actual := health.apply_secondary_damage(damage, hit_meta)
		if actual <= 0.0:
			continue
		EventBus.damage_dealt.emit(actual, (enemy as Node2D).global_position, false)
		if String(skill.params.get("skill_kind", "")) == "ice_nova":
			var status := enemy.get_node_or_null("StatusEffectComponent") as StatusEffectComponent
			if status:
				status.apply_effect("slow", float(skill.params.get("slow_duration", 1.1)), float(skill.params.get("slow_multiplier", 0.58)))


func _play_skill_vfx(skill: ConceptData, center: Vector2, radius: float, skill_meta: Dictionary, skill_level: int) -> void:
	var kind := String(skill.params.get("skill_kind", ""))
	var colors := {
		"thunder_strike": Color("#a56dff"),
		"fire_burst": Color("#ff6b2f"),
		"ice_nova": Color("#71dcff"),
		"wind_blade": Color("#8ff5c0"),
		"light_burst": Color("#fff1a8"),
		"dark_rift": Color("#b56cff"),
	}
	var vfx_color: Color = colors.get(kind, Color.WHITE)
	var completed_definition := _completed_definition_from_metadata(skill_meta)
	if not completed_definition.is_empty() and String(completed_definition.get("color", "")) != "":
		vfx_color = Color(String(completed_definition.get("color")))
	ConceptSkillVFX.spawn(
		GameManager.get_runtime_world(self),
		center,
		kind,
		radius * 0.72,
		vfx_color,
		skill_level,
		String(skill_meta.get("signature_profile", ""))
	)


func _concept_for_slot(chain_index: int, slot_type: String) -> ConceptData:
	if chain_index < 0 or chain_index >= chains.size():
		return null
	var concept_id := String(chains[chain_index].get(slot_type, ""))
	return DataLoader.get_concept(concept_id) if concept_id != "" else null


func _resolve_target(preferred: Node2D, fallback_position: Vector2) -> Node2D:
	if is_instance_valid(preferred):
		var health := preferred.get_node_or_null("HealthComponent") as HealthComponent
		if health and health.current_hp > 0.0:
			return preferred
	var nearest := _nearest_enemies(fallback_position, INF, 1, {})
	return nearest[0] if not nearest.is_empty() else null


func _nearest_enemies(center: Vector2, max_range: float, count: int, excluded: Dictionary) -> Array[Node2D]:
	var candidates: Array[Node2D] = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not (enemy is Node2D) or excluded.has(enemy.get_instance_id()):
			continue
		var health := enemy.get_node_or_null("HealthComponent") as HealthComponent
		if health and health.current_hp > 0.0 and (enemy as Node2D).global_position.distance_to(center) <= max_range:
			candidates.append(enemy as Node2D)
	candidates.sort_custom(func(a: Node2D, b: Node2D): return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
	return candidates.slice(0, mini(count, candidates.size()))


func _process_completed_skills_on_hit(target: Node2D, is_critical: bool, _direct_hit_count: int, metadata: Dictionary) -> void:
	if completed_skill_levels.is_empty() or not bool(metadata.get("is_direct", false)) or bool(metadata.get("is_triggered", false)):
		return
	var element_tags: Array = metadata.get("element_tags", [])
	for skill_id_variant in completed_skill_levels.keys():
		var skill_id := String(skill_id_variant)
		var definition: Dictionary = _completed_skill_definitions.get(skill_id, {})
		var level := get_completed_skill_level(skill_id)
		if definition.is_empty() or level <= 0 or not _completed_trigger_matches(definition, target, is_critical, element_tags, metadata, level):
			continue
		_trigger_completed_skill(skill_id, definition, level, target, metadata)


## 旧仕様は「与えたダメージが火属性か」をmetadataのelement_tagsで判定していたが、
## 属性システム廃止に伴い「対象に該当の状態異常が乗っているか」で判定する形へ変更した。
func _completed_trigger_matches(definition: Dictionary, target: Node2D, is_critical: bool, _unused_tags: Array, metadata: Dictionary, level: int) -> bool:
	var trigger_state := String(definition.get("trigger_state", ""))
	if trigger_state != "" and not _target_has_state(target, trigger_state):
		return false
	if not _target_condition_matches(String(definition.get("target_condition", "")), target):
		return false
	var trigger_kind := String(definition.get("trigger_kind", "on_hit"))
	match trigger_kind:
		"on_hit":
			return true
		"on_critical":
			return is_critical
		"on_kill":
			return bool(metadata.get("killed", false))
		"charge_critical":
			if not is_critical:
				return false
			var charge_id := String(definition.get("id", ""))
			var charge := int(_completed_charge_counts.get(charge_id, 0)) + 1
			var threshold := _completed_trigger_count(definition, level)
			if charge < threshold:
				_completed_charge_counts[charge_id] = charge
				return false
			_completed_charge_counts[charge_id] = 0
			return true
		"nth_hit":
			if target == null or not is_instance_valid(target):
				return false
			var count_key := "%s:%d" % [String(definition.get("id", "")), target.get_instance_id()]
			var count := int(_completed_hit_counts.get(count_key, 0)) + 1
			var threshold := _completed_trigger_count(definition, level)
			if count < threshold:
				_completed_hit_counts[count_key] = count
				return false
			_completed_hit_counts[count_key] = 0
			return true
		"cooldown_auto":
			return false
	return false


func _completed_trigger_count(definition: Dictionary, level: int) -> int:
	var counts: Array = definition.get("trigger_count_by_level", [5])
	return maxi(int(counts[clampi(level - 1, 0, counts.size() - 1)]), 1)


## 対象に指定の状態異常が乗っているか。StatusEffectComponentを直接見る
## (旧属性システム経由の判定は廃止に伴い撤去)。
func _target_has_state(target: Node2D, state_id: String) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var status := target.get_node_or_null("StatusEffectComponent") as StatusEffectComponent
	return status != null and status.has_state(state_id)


func _target_condition_matches(condition: String, target: Node2D) -> bool:
	if condition == "":
		return true
	if target == null or not is_instance_valid(target):
		return false
	if condition == "burning":
		return _target_has_state(target, "burning")
	if condition == "cold":
		return _target_has_state(target, "frozen")
	return true


func _trigger_completed_skill(skill_id: String, definition: Dictionary, level: int, target: Node2D, parent_metadata: Dictionary) -> void:
	var skill := DataLoader.get_concept(String(definition.get("skill_id", "")))
	if skill == null:
		return
	var modifier := DataLoader.get_concept(String(definition.get("modifier_id", "")))
	var completed_index := 100 + _completed_skill_order.find(skill_id)
	var position: Vector2 = target.global_position if is_instance_valid(target) else parent_metadata.get("impact_position", Vector2.ZERO)
	var skill_meta := CombatEventMeta.create_triggered(parent_metadata, "completed_skill:%s" % skill_id, skill.element_tags, completed_index, true)
	skill_meta["completed_skill_id"] = skill_id
	skill_meta["signature_profile"] = String(definition.get("vfx_profile", ""))
	if bool(definition.get("apply_freeze", false)) and is_instance_valid(target):
		var freeze_status := target.get_node_or_null("StatusEffectComponent") as StatusEffectComponent
		if freeze_status:
			freeze_status.apply_effect("stun", 0.45 + 0.2 * level, 0.0)
	if bool(definition.get("consume_cold", false)) and is_instance_valid(target):
		var cold_status := target.get_node_or_null("StatusEffectComponent") as StatusEffectComponent
		if cold_status:
			cold_status.remove_effect("slow")
			cold_status.remove_effect("stun")
	_execute_skill(completed_index, skill, modifier, target, position, skill_meta, false, level)
	completed_skill_triggered.emit(skill_id, level)
	skill_triggered.emit(completed_index, skill.id, int(skill_meta.get("generation_depth", 0)))


func debug_trigger_completed_skill(skill_id: String, preferred_target: Node2D = null) -> bool:
	var definition: Dictionary = _completed_skill_definitions.get(skill_id, {})
	var level := get_completed_skill_level(skill_id)
	if definition.is_empty() or level <= 0:
		return false
	var target := preferred_target if is_instance_valid(preferred_target) else _signature_auto_target(definition)
	if target == null:
		return false
	if String(definition.get("trigger_kind", "")) == "cooldown_auto":
		_activate_signature_skill(skill_id, definition, level, target)
	else:
		var metadata := CombatEventMeta.create_secondary("developer_completed_skill", [], false)
		metadata["impact_position"] = target.global_position
		_trigger_completed_skill(skill_id, definition, level, target, metadata)
	return true


func debug_force_completed_skill_ready(skill_id: String) -> bool:
	var definition: Dictionary = _completed_skill_definitions.get(skill_id, {})
	if definition.is_empty() or get_completed_skill_level(skill_id) <= 0 or String(definition.get("trigger_kind", "")) != "cooldown_auto":
		return false
	_completed_skill_cooldowns[skill_id] = 0.0
	return true


func _activate_signature_skill(skill_id: String, definition: Dictionary, level: int, target: Node2D) -> void:
	_completed_skill_cooldowns[skill_id] = _signature_cooldown_total(definition, level)
	var skill := DataLoader.get_concept(String(definition.get("skill_id", "")))
	var tags: Array = skill.element_tags if skill else []
	# 秘技は段階ごとに「同時に何か所へ落とすか」が増える（2026-10-31）。1か所目は従来の
	# 最寄りの敵、残りは離れた別の敵へ0.12秒ずつずらして落とし、増えたことを画面で見せる。
	var strikes := maxi(int(_definition_level_value(definition, "strike_count_by_level", level, 1.0)), 1)
	var targets: Array[Node2D] = [target]
	if strikes > 1:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player:
			for extra in _nearest_enemies(player.global_position, float(definition.get("auto_target_range", 740.0)), strikes * 3, {target.get_instance_id(): true}):
				if targets.size() >= strikes:
					break
				var spaced := true
				for chosen in targets:
					if chosen.global_position.distance_to(extra.global_position) < 90.0:
						spaced = false
						break
				if spaced:
					targets.append(extra)
	var epoch := _runtime_epoch
	for index in targets.size():
		if index > 0:
			await get_tree().create_timer(0.12, false).timeout
			if epoch != _runtime_epoch or not _active:
				return
		var strike_target := targets[index]
		if not is_instance_valid(strike_target):
			continue
		var metadata := CombatEventMeta.create_secondary("completed_skill_auto:%s" % skill_id, tags, false)
		metadata["impact_position"] = strike_target.global_position
		_trigger_completed_skill(skill_id, definition, level, strike_target, metadata)


func _signature_auto_target(definition: Dictionary) -> Node2D:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not is_instance_valid(player):
		return null
	var candidates := _nearest_enemies(player.global_position, float(definition.get("auto_target_range", 740.0)), 1, {})
	return candidates[0] if not candidates.is_empty() else null


func _signature_cooldown_total(definition: Dictionary, level: int) -> float:
	# 属性Lv/熟練度/Fusionによるクールダウン短縮は属性システム廃止に伴い撤去した。
	# 基礎値(cooldown_by_level)とビルド由来のhasteのみで決まる。
	var total := _definition_level_value(definition, "cooldown_by_level", level, 8.0)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var upgrades := player.get_node_or_null("PlayerUpgradesComponent") as PlayerUpgradesComponent
		if upgrades:
			var build_haste := upgrades.attack_interval_multiplier + upgrades.equipment_attack_speed_bonus
			total *= maxf(0.65, 1.0 - build_haste * 0.35)
	return maxf(total, float(_config.get("signature_minimum_cooldown", 2.0)))


func _completed_definition_from_metadata(metadata: Dictionary) -> Dictionary:
	var skill_id := String(metadata.get("completed_skill_id", ""))
	return _completed_skill_definitions.get(skill_id, {}) if skill_id != "" else {}


func _definition_level_value(definition: Dictionary, key: String, level: int, fallback: float) -> float:
	var values: Array = definition.get(key, [])
	if values.is_empty():
		return fallback
	return float(values[clampi(level - 1, 0, values.size() - 1)])


func _player_skill_damage_basis() -> float:
	var damage := float(_config.get("reference_damage", 14.0))
	var character: CharacterData = DataLoader.characters.get(GameManager.selected_character_id)
	if character:
		damage = maxf(character.base_damage, damage)
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return damage
	var stat_modifier := player.get_node_or_null("StatModifierComponent") as StatModifierComponent
	if stat_modifier:
		damage += stat_modifier.get_damage_flat_bonus()
	var upgrades := player.get_node_or_null("PlayerUpgradesComponent") as PlayerUpgradesComponent
	if upgrades:
		damage += upgrades.equipment_attack_flat
		damage *= upgrades.damage_multiplier * upgrades.get_equipment_conditional_damage_multiplier()
	return damage


func _load_completed_skills() -> void:
	_completed_skill_definitions.clear()
	_completed_skill_order.clear()
	var file := FileAccess.open(COMPLETED_SKILLS_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text()) if file else null
	if typeof(parsed) != TYPE_ARRAY:
		push_warning("ConceptSystem: completed skill data could not be loaded")
		return
	for value in parsed:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var definition: Dictionary = value
		var skill_id := String(definition.get("id", ""))
		if skill_id == "":
			continue
		_completed_skill_definitions[skill_id] = definition.duplicate(true)
		_completed_skill_order.append(skill_id)


func _load_config() -> Dictionary:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text()) if file else null
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
