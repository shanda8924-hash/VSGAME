extends Node2D
## First strong-enemy move: authored frames, fixed aim, brief physical step.
const EYE_DURATION := 0.40
const EYE_HOLD := 0.28
const EYE_SCALE := 1.6
const WINDUP := 0.55
const HIT_TIME := 0.61
const SLASH_END := 0.67
const END_TIME := 1.10
const REACH := 58.0
const STEP := 22.0
var enemy: EnemyBasic
var active := false
var elapsed := 0.0
var cooldown := 2.0
var direction := Vector2.RIGHT
var hit_resolved := false
var eye: Node2D

func setup(owner_enemy: EnemyBasic) -> void:
	enemy = owner_enemy
	add_to_group("strong_specials")
	eye = Node2D.new()
	eye.z_index = 10
	eye.scale = Vector2.ONE * EYE_SCALE
	enemy.animated_sprite.add_child(eye)
	eye.draw.connect(_draw_eye)
	eye.visible = false

func tick(delta: float) -> bool:
	if enemy._is_dead or not is_instance_valid(enemy.ai_component.target):
		cancel()
		return false
	if enemy.status_effect_component.has_effect("stun"):
		cancel()
		return false
	if not active:
		if enemy._movement_locked_by_attack: return false
		cooldown = maxf(0.0, cooldown - delta)
		if cooldown > 0.0 or enemy._normal_attack_state == EnemyBasic.NormalAttackState.WINDUP:
			return false
		var offset := enemy.ai_component.target.global_position - enemy.global_position
		if offset.length() > 85.0 or not _clear_path(enemy.ai_component.target) or not _slot_available():
			return false
		direction = offset.normalized() if offset.length() > 1.0 else (Vector2.LEFT if enemy.animated_sprite.flip_h else Vector2.RIGHT)
		active = true
		elapsed = 0.0
		hit_resolved = false
		enemy.set_movement_locked(true)
		enemy.animation_component.set_pose_controlled(true)
		enemy.animated_sprite.flip_h = direction.x < 0.0
		enemy.animated_sprite.animation = "attack1"
		enemy.animated_sprite.pause()
	var previous := elapsed
	elapsed += delta
	enemy.movement_component.direction = Vector2.ZERO
	# Advance using move_and_collide, never teleport through walls or crystals.
	var step_part := clampf((elapsed - WINDUP) / (SLASH_END - WINDUP), 0.0, 1.0)
	var previous_part := clampf((previous - WINDUP) / (SLASH_END - WINDUP), 0.0, 1.0)
	if step_part > previous_part:
		enemy.move_and_collide(direction * STEP * (step_part - previous_part) * enemy.status_effect_component.slow_multiplier)
	var pose := 0
	if elapsed >= 0.12: pose = 1
	if elapsed >= 0.30: pose = 2
	if elapsed >= 0.48: pose = 3
	if elapsed >= 0.55: pose = 4
	if elapsed >= 0.61: pose = 5
	if elapsed >= 0.72: pose = 6
	if elapsed >= 0.94:
		enemy.animated_sprite.animation = "idle"
		pose = 0
	enemy.animated_sprite.set_frame_and_progress(pose, 0.0)
	# The glint stays on the helmet's visible eye, including mirrored sprites.
	eye.position = Vector2(0.0, -4.0)
	update_eye_glint(elapsed)
	queue_redraw()
	if elapsed >= HIT_TIME and not hit_resolved:
		hit_resolved = true
		_resolve_hit()
	if elapsed >= END_TIME:
		cancel()
		cooldown = 6.0
	return true

func time_until_next_hit() -> float:
	return HIT_TIME - elapsed if active and not hit_resolved else INF

func _clear_path(target: Node2D) -> bool:
	var query := PhysicsRayQueryParameters2D.create(enemy.global_position, target.global_position, 1)
	var excluded: Array[RID] = [enemy.get_rid()]
	if target is CollisionObject2D:
		excluded.append(target.get_rid())
	query.exclude = excluded
	return enemy.get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func _resolve_hit() -> void:
	var target := enemy.ai_component.target
	if not is_instance_valid(target): return
	var offset := target.global_position - enemy.global_position
	if offset.length() > REACH or (offset.length() > 1.0 and direction.dot(offset.normalized()) < 0.5): return
	if not _clear_path(target): return
	var hurtbox := target.get_node_or_null("HurtboxComponent") as HurtboxComponent
	if hurtbox:
		var original := enemy.contact_hitbox.damage
		enemy.contact_hitbox.damage = original * 1.35
		hurtbox.apply_hitbox_damage(enemy.contact_hitbox)
		enemy.contact_hitbox.on_hit(hurtbox)
		enemy.contact_hitbox.damage = original

func cancel() -> void:
	if not active: return
	active = false
	eye.visible = false
	queue_redraw()
	enemy.set_movement_locked(false)
	enemy.animation_component.set_pose_controlled(false)
	enemy._normal_attack_state = EnemyBasic.NormalAttackState.COOLDOWN
	enemy._normal_attack_timer = 0.7
	cooldown = 6.0

func _draw_eye() -> void:
	eye.draw_rect(Rect2(-2, -1, 5, 3), Color(0.7, 0.02, 0.01, 0.5))
	eye.draw_rect(Rect2(-1, 0, 3, 1), Color(1.0, 0.06, 0.02))
	eye.draw_rect(Rect2(0, 0, 1, 1), Color(1.0, 0.85, 0.65))

func _slot_available() -> bool:
	var nearby := 0
	for other in get_tree().get_nodes_in_group("strong_specials"):
		if other != self and other.active and other.global_position.distance_to(global_position) < 280.0:
			nearby += 1
	return nearby < 2

func update_eye_glint(tell_elapsed: float) -> void:
	eye.visible = tell_elapsed >= 0.0 and tell_elapsed < EYE_DURATION
	eye.modulate.a = 1.0 - clampf((tell_elapsed - EYE_HOLD) / (EYE_DURATION - EYE_HOLD), 0.0, 1.0)
	eye.queue_redraw()

func _draw() -> void:
	if active and elapsed < HIT_TIME:
		draw_attack_tell(REACH, 0.0, acos(0.5), elapsed / HIT_TIME)

func draw_attack_tell(reach: float, width: float, half_angle: float, progress: float) -> void:
	# Same direction and extent as the hit test. The edge never grows beyond reach.
	var points := PackedVector2Array()
	if width > 0.0:
		points = PackedVector2Array([Vector2(0,-width), Vector2(reach,-width), Vector2(reach,width), Vector2(0,width)])
	elif is_equal_approx(half_angle, PI):
		for index in 32:
			points.append(Vector2.from_angle(TAU*float(index)/32.0)*reach)
	else:
		points.append(Vector2.ZERO)
		for index in 25:
			points.append(Vector2.from_angle(lerpf(-half_angle,half_angle,float(index)/24.0))*reach)
	for index in points.size(): points[index] = points[index].rotated(direction.angle())
	draw_colored_polygon(points, Color(1.0,0.22,0.12,0.08+0.10*clampf(progress,0,1)))
	points.append(points[0])
	draw_polyline(points, Color(1.0,0.38,0.25,0.85), 1.5, false)
