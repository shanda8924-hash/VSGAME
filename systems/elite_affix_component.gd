extends Node
class_name EliteAffixComponent
## 1体の精鋭が持つ複数属性を実行・表示する再利用コンポーネント。

var affix_ids: Array[String] = []
var definitions: Dictionary = {}
var elite: EnemyBasic
var _timers: Dictionary = {}
var _shield_generation := 0

func configure(owner_elite: EnemyBasic, ids: Array[String], configs: Dictionary) -> void:
	elite = owner_elite
	affix_ids = ids
	definitions = configs

func _ready() -> void:
	if elite == null:
		return
	for id in affix_ids:
		_timers[id] = randf_range(0.5, float(definitions.get(id, {}).get("interval", 3.0)))
	elite.contact_hitbox.landed.connect(_on_elite_attack_landed)
	_build_affix_label()

func _process(delta: float) -> void:
	if elite == null or not is_instance_valid(elite) or elite.health_component.current_hp <= 0.0:
		return
	for id in affix_ids:
		if id not in ["fire", "lightning", "poison", "fortified"]:
			continue
		_timers[id] = float(_timers.get(id, 0.0)) - delta
		if _timers[id] <= 0.0:
			_activate_periodic(id)
			_timers[id] = float(definitions.get(id, {}).get("interval", 4.0))

func _activate_periodic(id: String) -> void:
	var config: Dictionary = definitions.get(id, {})
	match id:
		"fire":
			_spawn_hazard(elite.global_position, config, 0.35, true)
		"lightning":
			var player := get_tree().get_first_node_in_group("player") as Node2D
			if player:
				_spawn_delayed_lightning(player.global_position, config)
		"poison":
			var player := get_tree().get_first_node_in_group("player") as Node2D
			if player:
				_spawn_hazard(player.global_position, config, float(config.get("duration", 5.0)), false)
		"fortified":
			_grant_shield(config)

func _spawn_hazard(position: Vector2, config: Dictionary, lifetime: float, once: bool) -> void:
	var hazard := EliteHazard.new()
	hazard.radius = float(config.get("radius", 64.0))
	hazard.damage = float(config.get("damage", 5.0))
	hazard.duration = lifetime
	hazard.tick_interval = float(config.get("tick_interval", 1.0))
	hazard.color = _parse_color(config.get("color", "ffffff"))
	hazard.warning_only = once
	GameManager.get_runtime_world(self).add_child(hazard)
	hazard.global_position = position
	if once:
		hazard.trigger_once()

func _spawn_delayed_lightning(position: Vector2, config: Dictionary) -> void:
	var hazard := EliteHazard.new()
	hazard.radius = float(config.get("radius", 58.0))
	hazard.damage = float(config.get("damage", 16.0))
	var warning_time := float(config.get("warning_time", 0.8))
	hazard.duration = warning_time + 0.1
	hazard.warning_only = true
	hazard.color = _parse_color(config.get("color", "ffe34d"))
	GameManager.get_runtime_world(self).add_child(hazard)
	hazard.global_position = position
	await get_tree().create_timer(warning_time).timeout
	if is_instance_valid(hazard):
		hazard.trigger_once()

func _grant_shield(config: Dictionary) -> void:
	var amount := elite.health_component.max_hp * float(config.get("shield_ratio", 0.15))
	elite.health_component.grant_temporary_shield(amount)
	_shield_generation += 1
	var generation := _shield_generation
	await get_tree().create_timer(float(config.get("duration", 5.0))).timeout
	if is_instance_valid(elite) and generation == _shield_generation:
		elite.health_component.clear_shield()

func _on_elite_attack_landed(hurtbox: HurtboxComponent) -> void:
	var target := hurtbox.get_owner_entity()
	if target == null:
		return
	if "freeze" in affix_ids:
		var status := target.get_node_or_null("StatusEffectComponent") as StatusEffectComponent
		if status:
			status.apply_effect("slow", float(definitions.get("freeze", {}).get("slow_duration", 2.0)))
	if "vampiric" in affix_ids:
		var ratio := float(definitions.get("vampiric", {}).get("heal_ratio", 0.3))
		elite.health_component.heal(elite.contact_hitbox.damage * ratio)

func _build_affix_label() -> void:
	var label := Label.new()
	label.position = Vector2(-100, -72)
	label.size = Vector2(200, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var names: Array[String] = []
	for id in affix_ids:
		names.append(String(definitions.get(id, {}).get("display_name", id)))
	label.text = "精鋭 [ %s ]" % " / ".join(names)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	elite.add_child.call_deferred(label)

func _parse_color(hex_value) -> Color:
	return Color.from_string(String(hex_value), Color.WHITE)
