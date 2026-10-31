extends "res://systems/orc_step_slash.gd"
## Per-species authored poses. Timings are seconds, not animation speed guesses.
const MOVES := {
	"skeleton_thrust": {"name":"迎撃突き", "anim":"attack1", "poses":[[0.0,0],[0.12,1],[0.32,2],[0.50,3],[0.60,4],[0.65,5],[0.74,6],[0.88,7]], "hits":[0.60], "end":1.12, "step":8.0, "move_start":0.54, "move_end":0.66, "range":64.0, "width":14.0, "damage":1.35, "eye":Vector2(3,-3)},
	"greatsword_sweep": {"name":"大薙ぎ払い", "anim":"attack1", "poses":[[0.0,0],[0.12,1],[0.28,2],[0.46,3],[0.59,4],[0.68,5],[0.73,6],[0.81,7],[1.00,8]], "hits":[0.68], "end":1.30, "step":6.0, "move_start":0.62, "move_end":0.74, "range":68.0, "dot":0.0, "damage":1.45, "eye":Vector2(3,-3)},
	"blood_spear": {"name":"血槍", "anim":"attack2", "poses":[[0.0,0],[0.12,1],[0.30,2],[0.47,3],[0.62,4],[0.68,5],[0.77,6],[0.91,7],[1.02,8]], "hits":[0.62], "end":1.25, "step":0.0, "move_start":0.60, "move_end":0.70, "range":78.0, "width":12.0, "damage":1.3, "eye":Vector2(2,-4)},
	"orc_double_slash": {"name":"二連斬り", "anim":"attack1", "poses":[[0.0,0],[0.12,1],[0.30,2],[0.56,3],[0.62,4],[0.73,5],[0.86,6],[0.94,1],[1.04,2],[1.17,3],[1.23,4],[1.34,5],[1.48,6]], "hits":[0.56,1.17], "end":1.80, "step":10.0, "move_start":0.52, "move_end":0.64, "range":62.0, "dot":0.5, "damage":0.85, "eye":Vector2(1,-5)},
	"bear_pounce": {"name":"跳びかかり叩きつけ", "anim":"attack3", "poses":[[0.0,0],[0.12,1],[0.28,2],[0.45,3],[0.58,4],[0.79,5],[0.86,6],[1.00,7],[1.16,8]], "hits":[0.79], "end":1.42, "step":34.0, "move_start":0.55, "move_end":0.79, "range":40.0, "radial":true, "damage":1.45, "eye":Vector2(2,-5)}
}
var move: Dictionary
var hit_index := 0
var sprite_origin := Vector2.ZERO
var landing := Vector2.ZERO

func setup(owner_enemy: EnemyBasic) -> void:
	super.setup(owner_enemy)
	move = MOVES[enemy.enemy_data.special_attack_id]
	sprite_origin = enemy.animated_sprite.position
	cooldown = randf_range(2.0,3.0)

func tick(delta: float) -> bool:
	if enemy._is_dead or not is_instance_valid(enemy.ai_component.target) or enemy.status_effect_component.has_effect("stun"):
		cancel()
		return false
	if not active:
		if enemy._movement_locked_by_attack: return false
		cooldown = maxf(0.0,cooldown-delta)
		if cooldown > 0.0 or enemy._normal_attack_state == EnemyBasic.NormalAttackState.WINDUP: return false
		var offset := enemy.ai_component.target.global_position-enemy.global_position
		if offset.length() > minf(float(move.range)+float(move.step)-4.0,90.0): return false
		if not _clear_path(enemy.ai_component.target) or not _slot_available(): return false
		active = true
		elapsed = 0.0
		hit_index = 0
		direction = offset.normalized() if offset.length() > 1.0 else (Vector2.LEFT if enemy.animated_sprite.flip_h else Vector2.RIGHT)
		landing = enemy.global_position + direction * float(move.step)
		enemy.set_movement_locked(true)
		enemy.animation_component.set_pose_controlled(true)
		enemy.animated_sprite.flip_h = direction.x < 0.0
		enemy.animated_sprite.animation = String(move.anim)
		enemy.animated_sprite.pause()
	var previous := elapsed
	elapsed += delta
	enemy.movement_component.direction = Vector2.ZERO
	var travel_duration := float(move.move_end)-float(move.move_start)
	var a := clampf((previous-float(move.move_start))/travel_duration,0,1)
	var b := clampf((elapsed-float(move.move_start))/travel_duration,0,1)
	if b > a:
		enemy.move_and_collide(direction * float(move.step) * (b-a) * enemy.status_effect_component.slow_multiplier)
	var pose := 0
	for entry in move.poses:
		if elapsed >= float(entry[0]): pose = int(entry[1])
	enemy.animated_sprite.set_frame_and_progress(pose,0.0)
	if enemy.enemy_data.special_attack_id == "bear_pounce":
		enemy.animated_sprite.position = sprite_origin + Vector2(0,-sin(b*PI)*6.0)
	var eye_offset: Vector2 = move.eye
	if enemy.animated_sprite.flip_h: eye_offset.x = -eye_offset.x
	eye.position = eye_offset
	var tell_start := 0.0 if hit_index == 0 else float(move.hits[hit_index]) - EYE_DURATION if hit_index < move.hits.size() else float(move.end)
	update_eye_glint(elapsed - tell_start)
	while hit_index < move.hits.size() and elapsed >= float(move.hits[hit_index]):
		_resolve_hit()
		hit_index += 1
	queue_redraw()
	if elapsed >= float(move.end): cancel()
	return true

func time_until_next_hit() -> float:
	if not active or hit_index >= move.hits.size(): return INF
	return float(move.hits[hit_index]) - elapsed

func _resolve_hit() -> void:
	var target := enemy.ai_component.target
	if not is_instance_valid(target): return
	var offset := target.global_position-enemy.global_position
	if move.has("width"):
		var forward := offset.dot(direction)
		if forward < 0.0 or forward > float(move.range) or absf(offset.cross(direction)) > float(move.width): return
	else:
		if offset.length() > float(move.range): return
		if not bool(move.get("radial",false)) and offset.length() > 1.0 and offset.normalized().dot(direction) < float(move.dot): return
	if not _clear_path(target): return
	var hurtbox := target.get_node_or_null("HurtboxComponent") as HurtboxComponent
	if hurtbox:
		var original := enemy.contact_hitbox.damage
		enemy.contact_hitbox.damage = original * float(move.damage)
		hurtbox.apply_hitbox_damage(enemy.contact_hitbox)
		enemy.contact_hitbox.on_hit(hurtbox)
		enemy.contact_hitbox.damage = original

func cancel() -> void:
	if is_instance_valid(enemy): enemy.animated_sprite.position = sprite_origin
	super.cancel()
	queue_redraw()

func _draw() -> void:
	if not active: return
	if hit_index < move.hits.size():
		var hit_time := float(move.hits[hit_index])
		var tell_start := 0.0 if hit_index == 0 else hit_time - EYE_DURATION
		if elapsed >= tell_start and elapsed < hit_time:
			var angle := PI if bool(move.get("radial",false)) else acos(float(move.get("dot",0.5)))
			draw_attack_tell(float(move.range), float(move.get("width",0.0)), angle, (elapsed-tell_start)/maxf(hit_time-tell_start,0.01))
	if enemy.enemy_data.special_attack_id == "blood_spear" and elapsed >= 0.62 and elapsed < 0.74:
		var length := float(move.range) * clampf((0.74-elapsed)/0.08,0,1)
		var side := direction.orthogonal()*2.5
		draw_colored_polygon(PackedVector2Array([direction*10+side,direction*length,direction*10-side]),Color("b84558"))
