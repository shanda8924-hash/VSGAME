extends Node2D
## 試作と同じ白〜氷青の三日月剣撃。扇全体ではなく、刃が通った角度だけを描く。

const SEGMENTS := 64
const PEAK_HOLD := 0.04
const BREAKUP_DURATION := 0.24
const LIFETIME := 1.0

var origin := Vector2.ZERO
var direction := Vector2.RIGHT
var radius := 145.0
var half_angle := deg_to_rad(70.0)
var reverse_sweep := false
var age := 0.0
var sweep_progress := 0.0
var finished := false
var breakup_age := 0.0

func _ready() -> void:
	add_to_group("boss_attack_transient")
	global_position = origin
	global_rotation = direction.angle()
	z_index = 7
	queue_redraw()

func set_sweep_progress(value: float) -> void:
	if finished:
		return
	sweep_progress = maxf(sweep_progress, clampf(value, 0.0, 1.0))
	queue_redraw()

func finish_sweep() -> void:
	if finished:
		return
	finished = true
	breakup_age = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	age += delta
	if finished:
		breakup_age += delta
		if breakup_age >= BREAKUP_DURATION:
			queue_free()
			return
		queue_redraw()
	elif age >= LIFETIME:
		queue_free()

func _draw() -> void:
	if sweep_progress <= 0.0:
		return
	var collapse := smoothstep(PEAK_HOLD, BREAKUP_DURATION, breakup_age) if finished else 0.0
	var front := sweep_progress * (1.0 - collapse * 0.06)
	var rear := sweep_progress * collapse * 0.88
	var remaining := 1.0 - collapse
	var width := radius * 0.16 * smoothstep(0.0, 0.45, sweep_progress) * remaining
	for index in SEGMENTS:
		var a := maxf(float(index) / float(SEGMENTS), rear)
		var b := minf(float(index + 1) / float(SEGMENTS), front)
		if b <= a:
			continue
		_draw_ribbon(a, b, rear, front, radius, width, 0.0, 0.22, Color("f4fdff", remaining))
		_draw_ribbon(a, b, rear, front, radius, width, 0.22, 0.70, Color("90ddff", remaining))
		_draw_ribbon(a, b, rear, front, radius, width, 0.70, 1.0, Color("4f9ccc", remaining * 0.92))
		var echo_rear := lerpf(rear, front, 0.14)
		var echo_front := lerpf(rear, front, 0.88)
		var echo_a := maxf(a, echo_rear)
		var echo_b := minf(b, echo_front)
		if echo_b > echo_a:
			_draw_ribbon(echo_a, echo_b, echo_rear, echo_front, radius * 0.81, width * 0.14, 0.0, 1.0, Color("f4fdff", remaining * 0.88))

func _crescent_profile(fraction: float) -> float:
	return pow(maxf(0.0, sin(clampf(fraction, 0.0, 1.0) * PI)), 1.4)

func _draw_ribbon(a: float, b: float, rear: float, front: float, outer: float, width: float, from_band: float, to_band: float, color: Color) -> void:
	var span := maxf(front - rear, 0.0001)
	var width_a := width * _crescent_profile((a - rear) / span)
	var width_b := width * _crescent_profile((b - rear) / span)
	var first_outer := _point(a, outer - width_a * from_band)
	var first_inner := _point(a, outer - width_a * to_band)
	var second_inner := _point(b, outer - width_b * to_band)
	var second_outer := _point(b, outer - width_b * from_band)
	_draw_triangle(first_outer, first_inner, second_inner, color)
	_draw_triangle(first_outer, second_inner, second_outer, color)

func _draw_triangle(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	if absf((b - a).cross(c - a)) <= 0.01:
		return
	draw_colored_polygon(PackedVector2Array([a, b, c]), color)

func _point(fraction: float, distance: float) -> Vector2:
	var angle := lerpf(-half_angle, half_angle, 1.0 - fraction if reverse_sweep else fraction)
	return Vector2.from_angle(angle) * distance
