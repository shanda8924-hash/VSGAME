extends Node
class_name EliteAffixComponent
## 1体の精鋭が持つ複数属性を実行・表示する再利用コンポーネント。

var affix_ids: Array[String] = []
var definitions: Dictionary = {}
var elite: EnemyBasic
const MIN_WARNING := 0.75
const ABILITY_RECOVERY := 0.45
var _ability_left := 0.0
var _timers: Dictionary = {}
var _shield_generation := 0
var _visual: EliteAffixVisual
var _label: Label

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
	_visual = EliteAffixVisual.new()
	_visual.configure(affix_ids)
	elite.add_child(_visual)
	elite.health_component.shield_changed.connect(_on_shield_changed)
	_build_affix_label()

func _exit_tree() -> void:
	if is_instance_valid(_visual):
		_visual.queue_free()
	if is_instance_valid(_label):
		_label.queue_free()

func _process(delta: float) -> void:
	if elite == null or not is_instance_valid(elite) or elite.health_component.current_hp <= 0.0:
		return
	if elite.exploration_guard and (not elite.exploration_alert or elite._returning_home):
		if _ability_left > 0.0:
			_ability_left = 0.0
			elite.set_movement_locked(false)
		return
	if _ability_left > 0.0:
		_ability_left = maxf(_ability_left-delta,0.0)
		if _ability_left == 0.0:
			elite.set_movement_locked(false)
		return
	if elite._movement_locked_by_attack or (elite.strong_attack and elite.strong_attack.active) or elite._normal_attack_state == EnemyBasic.NormalAttackState.WINDUP:
		return
	for id in affix_ids:
		if id not in ["fire", "lightning", "poison", "fortified"]:
			continue
		_timers[id] = float(_timers.get(id, 0.0)) - delta
		if _timers[id] <= 0.0:
			_activate_periodic(id)
			_timers[id] = float(definitions.get(id, {}).get("interval", 4.0))
			break # One periodic ability at a time; leave a reaction and counter window.

func _activate_periodic(id: String) -> void:
	var config: Dictionary = definitions.get(id, {})
	var warning_time := maxf(float(config.get("warning_time",0.65)),MIN_WARNING)
	_ability_left = warning_time + 0.18 + ABILITY_RECOVERY
	elite.set_movement_locked(true)
	elite.movement_component.direction = Vector2.ZERO
	if _visual:
		_visual.pulse_affix(id, warning_time)
	match id:
		"fire":
			_spawn_hazard(elite.global_position, id, config, 0.18, true)
		"lightning":
			var player := get_tree().get_first_node_in_group("player") as Node2D
			if player:
				_spawn_hazard(player.global_position, id, config, 0.18, true)
		"poison":
			var player := get_tree().get_first_node_in_group("player") as Node2D
			if player:
				_spawn_hazard(player.global_position, id, config, float(config.get("duration", 5.0)), false)
		"fortified":
			await get_tree().create_timer(warning_time, false).timeout
			if is_instance_valid(elite) and not elite._is_dead and (not elite.exploration_guard or (elite.exploration_alert and not elite._returning_home)):
				_grant_shield(config)

func _spawn_hazard(position: Vector2, id: String, config: Dictionary, lifetime: float, once: bool) -> void:
	var hazard := EliteHazard.new()
	hazard.source = elite
	hazard.effect_id = id
	hazard.radius = float(config.get("radius", 64.0))
	hazard.damage = float(config.get("damage", 5.0))
	hazard.duration = lifetime
	hazard.tick_interval = float(config.get("tick_interval", 1.0))
	hazard.warning_duration = maxf(float(config.get("warning_time", 0.65)), MIN_WARNING)
	hazard.color = _parse_color(config.get("color", "ffffff"))
	hazard.warning_only = once
	GameManager.get_runtime_world(self).add_child(hazard)
	hazard.global_position = position

func _grant_shield(config: Dictionary) -> void:
	var amount := elite.health_component.max_hp * float(config.get("shield_ratio", 0.15))
	elite.health_component.grant_temporary_shield(amount)
	var shield_effect := PixelSpriteVFX.spawn(elite, elite.global_position, "active_shield", Vector2.ONE * 72.0, 0.55)
	if shield_effect:
		shield_effect.z_index = 6
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
		PixelSpriteVFX.spawn(GameManager.get_runtime_world(self), hurtbox.global_position, "hit_ice", Vector2.ONE * 54.0, 0.35)
		var status := target.get_node_or_null("StatusEffectComponent") as StatusEffectComponent
		if status:
			status.apply_effect("slow", float(definitions.get("freeze", {}).get("slow_duration", 2.0)))
	if "vampiric" in affix_ids:
		PixelSpriteVFX.spawn(GameManager.get_runtime_world(self), hurtbox.global_position, "hit_dark", Vector2.ONE * 48.0, 0.32)
		PixelSpriteVFX.spawn(elite, elite.global_position, "hit_dark", Vector2.ONE * 42.0, 0.32)
		var ratio := float(definitions.get("vampiric", {}).get("heal_ratio", 0.3))
		elite.health_component.heal(elite.contact_hitbox.damage * ratio)

func _on_shield_changed(current_shield: float, _max_shield: float) -> void:
	if _visual:
		_visual.set_shield_active(current_shield > 0.0)

func _build_affix_label() -> void:
	var label := Label.new()
	_label = label
	label.position = Vector2(-100, -66)
	label.size = Vector2(200, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var names: Array[String] = []
	for id in affix_ids:
		names.append(String(definitions.get(id, {}).get("display_name", id)))
	label.text = "◆ 精鋭  %s" % "・".join(names)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	elite.add_child.call_deferred(label)

func _parse_color(hex_value) -> Color:
	return Color.from_string(String(hex_value), Color.WHITE)
