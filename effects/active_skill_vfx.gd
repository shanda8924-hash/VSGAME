extends Node2D
class_name ActiveSkillVFX
## Spaceスキル用の軽量な局所VFX。全画面フラッシュは使わず、発動地点周辺だけを描く。

var radius: float = 120.0
var color: Color = Color.WHITE
var facing: Vector2 = Vector2.RIGHT
var half_angle: float = 180.0
var style: String = "burst"

func setup(effect_radius: float, effect_color: Color, direction: Vector2 = Vector2.RIGHT, arc_half_angle: float = 180.0, effect_style: String = "burst") -> void:
	radius = effect_radius
	color = effect_color
	facing = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	half_angle = arc_half_angle
	style = effect_style

func _ready() -> void:
	z_index = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("transient_vfx")
	modulate.a = 1.0
	scale = Vector2(0.35, 0.35)
	queue_redraw()
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.10)
	# 主形状を薄くせず、端が潰れる短いPixel collapseで終了する。
	tween.tween_property(self, "scale", Vector2(0.12, 0.12), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

func _draw() -> void:
	var edge := Color(color.r, color.g, color.b, 0.92)
	var core := color.lightened(0.28)
	if style in ["aura", "shield", "sanctuary", "time", "summon", "chains", "holy_burst", "execution", "impact", "rain"]:
		_draw_pixel_arc(0.0, TAU, radius, edge, 24, 4.0)
		if style in ["sanctuary", "time", "summon", "holy_burst"]:
			_draw_pixel_arc(0.0, TAU, radius * 0.65, core, 16, 2.0)
			for i in 8:
				var direction := Vector2.from_angle(TAU * float(i) / 8.0)
				var tip := (direction * radius).round()
				draw_rect(Rect2(tip - Vector2(2, 2), Vector2(4, 4)), core, true)
		elif style == "chains":
			for i in 10:
				var direction := Vector2.from_angle(TAU * float(i) / 10.0)
				draw_line((direction * radius).round(), (direction * radius * 0.25).round(), edge, 3.0, false)
		elif style == "rain":
			for x in range(-4, 5):
				var start := Vector2(x * radius / 5.0, -radius).round()
				draw_line(start, start + Vector2(-8, 22), edge, 3.0, false)
		return
	var center_angle := facing.angle()
	var start_angle := center_angle - deg_to_rad(half_angle)
	var end_angle := center_angle + deg_to_rad(half_angle)
	_draw_pixel_arc(start_angle, end_angle, radius, edge, 18, 4.0)
	_draw_pixel_arc(start_angle + 0.08, end_angle - 0.08, radius * 0.72, core, 13, 2.0)
	for angle in [start_angle, end_angle]:
		var angle_value: float = float(angle)
		var tip := (Vector2.from_angle(angle_value) * radius).round()
		draw_rect(Rect2(tip - Vector2(2, 2), Vector2(5, 5)), core, true)

func _draw_pixel_arc(start_angle: float, end_angle: float, arc_radius: float, arc_color: Color, segments: int, width: float) -> void:
	var previous := (Vector2.from_angle(start_angle) * arc_radius).round()
	for index in range(1, segments + 1):
		var ratio := float(index) / float(segments)
		var next := (Vector2.from_angle(lerpf(start_angle, end_angle, ratio)) * arc_radius).round()
		# 1本のSmooth curveにせず、短いPixel segmentと小さなgapでShapeを作る。
		if index % 4 != 0:
			draw_line(previous, next, arc_color, width, false)
		previous = next
