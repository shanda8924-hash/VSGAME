extends HitboxComponent
class_name MeleeHit
## 近接/AoE系の職業攻撃パターン(melee_arc/wide_cleave/self_pulse/holy_pulse_heal/
## piercing_thrust/charge_dash)が使う、移動しない瞬間ヒット判定。
## Projectileと違って飛ばないだけで、命中時の属性VFX発火・HitboxComponent経由の
## ダメージ適用(会心・damage_dealt通知・hit_impact SE)は既存パイプラインをそのまま使う。

var animation_strike := false
var target_range_limit := INF
var target_range_origin := Vector2.INF
var vfx_theme_id: String = ""
var character_level: int = 1
var _origin_position: Vector2 = Vector2.ZERO
var _facing: Vector2 = Vector2.RIGHT
var _half_angle_degrees: float = 180.0
var _line_length: float = 0.0
var _line_half_width: float = 0.0
var _hit_ids: Dictionary = {}
var _knockback_distance: float = 0.0
var _lifesteal_percent: float = 0.0
var _lifesteal_cap_per_hit: float = 0.0
var _attacker_health: HealthComponent = null

func setup(theme_id: String, level: int, origin: Vector2) -> void:
	vfx_theme_id = theme_id
	character_level = level
	_origin_position = origin

func configure_arc(radius: float, facing: Vector2, half_angle_degrees: float, active_seconds: float, knockback_distance: float, lifesteal_percent: float = 0.0, lifesteal_cap_per_hit: float = 0.0, attacker_health: HealthComponent = null) -> void:
	_facing = facing.normalized() if facing != Vector2.ZERO else Vector2.RIGHT
	_half_angle_degrees = half_angle_degrees
	_knockback_distance = knockback_distance
	_lifesteal_percent = lifesteal_percent
	_lifesteal_cap_per_hit = lifesteal_cap_per_hit
	_attacker_health = attacker_health
	var shape := CircleShape2D.new()
	shape.radius = radius
	$CollisionShape2D.shape = shape
	_expire_after(active_seconds)

func configure_line(length: float, half_width: float, facing: Vector2, active_seconds: float, knockback_distance: float, lifesteal_percent: float = 0.0, lifesteal_cap_per_hit: float = 0.0, attacker_health: HealthComponent = null) -> void:
	_facing = facing.normalized() if facing != Vector2.ZERO else Vector2.RIGHT
	_line_length = length
	_line_half_width = half_width
	_knockback_distance = knockback_distance
	_lifesteal_percent = lifesteal_percent
	_lifesteal_cap_per_hit = lifesteal_cap_per_hit
	_attacker_health = attacker_health
	var shape := CircleShape2D.new()
	shape.radius = length
	$CollisionShape2D.shape = shape
	_expire_after(active_seconds)

func can_hit(hurtbox: HurtboxComponent) -> bool:
	if not damage_enabled or hurtbox == null:
		return false
	var target := hurtbox.get_owner_entity() as Node2D
	if target == null or not is_instance_valid(target):
		return false
	var range_origin := target_range_origin if target_range_origin.is_finite() else _origin_position
	if range_origin.distance_to(target.global_position) > target_range_limit:
		return false
	if _half_angle_degrees < 179.0 or _line_length > 0.0:
		var ray := PhysicsRayQueryParameters2D.create(_origin_position, target.global_position, 1)
		var player := get_tree().get_first_node_in_group("player") as CollisionObject2D
		if player:
			ray.exclude = [player.get_rid()]
		if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
			return false
	var target_id := target.get_instance_id()
	if _hit_ids.has(target_id):
		return false
	var offset := target.global_position - _origin_position
	if _line_length > 0.0:
		var forward := offset.dot(_facing)
		var side := absf(offset.cross(_facing))
		return forward >= 0.0 and forward <= _line_length and side <= _line_half_width
	if offset != Vector2.ZERO:
		var angle := rad_to_deg(absf(_facing.angle_to(offset.normalized())))
		if angle > _half_angle_degrees:
			return false
	return true

func on_hit(hurtbox: HurtboxComponent) -> void:
	var contact_target := hurtbox.get_owner_entity() as Node2D
	if is_instance_valid(contact_target) and (_half_angle_degrees < 179.0 or _line_length > 0.0) and _hit_ids.size() < 3:
		# 接触印（pixelfx impacts/blunt-hit）。会心は1.5倍。
		var mark := PixelSpriteVFX.spawn(GameManager.get_runtime_world(self), contact_target.global_position - (contact_target.global_position - _origin_position).normalized() * 5.0, "contact_mark", Vector2.ZERO, 0.0, (contact_target.global_position - _origin_position).angle())
		if mark:
			mark.z_index = 70
			if is_critical:
				mark.scale *= 1.5
	var target := hurtbox.get_owner_entity() as Node2D
	if target:
		_hit_ids[target.get_instance_id()] = true
		if _lifesteal_percent > 0.0 and _attacker_health:
			var heal_amount := damage * _lifesteal_percent
			if _lifesteal_cap_per_hit > 0.0:
				heal_amount = minf(heal_amount, _lifesteal_cap_per_hit)
			_attacker_health.heal(heal_amount)
		if target.has_method("apply_knockback"):
			var push := _knockback_distance
			if target is EnemyBasic and (target as EnemyBasic).enemy_data is BossData:
				push *= 0.1
			if push > 0.0:
				target.apply_knockback((target.global_position - _origin_position).normalized(), push)
	var manager: Node = get_tree().get_first_node_in_group("effect_theme_manager")
	if manager:
		var effect_position := target.global_position if target else global_position
		manager.play_weapon_hit(vfx_theme_id, effect_position, character_level, hurtbox, _origin_position, is_critical, vfx_theme_id == "lightning")
	landed.emit(hurtbox)

func _expire_after(seconds: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(maxf(seconds, 0.02), false).timeout
	if is_instance_valid(self):
		queue_free()
