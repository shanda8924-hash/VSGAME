extends Node2D
class_name EliteAffixVisual
## 精鋭の能力を本体の周囲に常時表示する軽量な描画ノード。

const COLORS := {
	"fire": Color("ff6538"),
	"lightning": Color("ffe34d"),
	"freeze": Color("62c8ff"),
	"poison": Color("79db45"),
	"vampiric": Color("d7476f"),
	"fortified": Color("d8d8e8"),
}

var affix_ids: Array[String] = []
var _elapsed := 0.0
var _pulse_id := ""
var _pulse_left := 0.0
var _pulse_duration := 0.0
var _shield_active := false

func configure(ids: Array[String]) -> void:
	affix_ids = ids.duplicate()
	queue_redraw()

func _ready() -> void:
	z_index = 7

func _process(delta: float) -> void:
	_elapsed += delta
	_pulse_left = maxf(_pulse_left - delta, 0.0)
	if _pulse_left <= 0.0:
		_pulse_id = ""
	queue_redraw()

func pulse_affix(id: String, duration: float) -> void:
	_pulse_id = id
	_pulse_duration = maxf(duration, 0.01)
	_pulse_left = _pulse_duration

func set_shield_active(active: bool) -> void:
	_shield_active = active
	queue_redraw()

func _draw() -> void:
	if affix_ids.is_empty():
		return
	var center := Vector2(0, 11)
	var count := affix_ids.size()
	var base_radius := 23.0 + sin(_elapsed * 3.0)
	for index in count:
		var id := affix_ids[index]
		var color: Color = COLORS.get(id, Color.WHITE)
		var angle := _elapsed * 0.75 + TAU * float(index) / float(count)
		var marker := center + Vector2(cos(angle) * base_radius, sin(angle) * 7.5)
		_draw_sigil(id, marker.round(), color)
		_draw_ellipse_arc(center, base_radius, 7.5, angle - 0.28, angle + 0.28, Color(color, 0.7), 2.0)
	if _pulse_id != "":
		var progress := 1.0 - _pulse_left / _pulse_duration
		var pulse_color: Color = COLORS.get(_pulse_id, Color.WHITE)
		_draw_ellipse_arc(center, 25.0 + progress * 9.0, 9.0 + progress * 3.0, 0.0, TAU, Color(pulse_color, 0.9 * (1.0 - progress)), 3.0)
	if _shield_active:
		var shield_color := Color("8bd9ff")
		var shield_points := PackedVector2Array([
			Vector2(-19, -25), Vector2(0, -34), Vector2(19, -25),
			Vector2(22, 4), Vector2(0, 20), Vector2(-22, 4), Vector2(-19, -25)
		])
		draw_colored_polygon(shield_points, Color(shield_color, 0.10))
		draw_polyline(shield_points, Color(shield_color, 0.9), 2.0, false)

func _draw_sigil(id: String, position: Vector2, color: Color) -> void:
	draw_circle(position, 6.0, Color(0.02, 0.04, 0.07, 0.82))
	match id:
		"fire":
			draw_colored_polygon(PackedVector2Array([position + Vector2(0, -5), position + Vector2(4, 4), position, position + Vector2(-4, 4)]), color)
		"lightning":
			draw_polyline(PackedVector2Array([position + Vector2(2, -5), position + Vector2(-2, 0), position + Vector2(2, 0), position + Vector2(-2, 5)]), color, 2.0, false)
		"freeze":
			for ray in 4:
				var direction := Vector2.RIGHT.rotated(float(ray) * PI / 4.0)
				draw_line(position - direction * 5.0, position + direction * 5.0, color, 1.5, false)
		"poison":
			draw_circle(position + Vector2(-2, 2), 2.5, color)
			draw_circle(position + Vector2(2, -2), 1.5, color)
		"vampiric":
			draw_colored_polygon(PackedVector2Array([position + Vector2(0, -5), position + Vector2(4, 1), position + Vector2(0, 5), position + Vector2(-4, 1)]), color)
		"fortified":
			var points := PackedVector2Array()
			for side in 7:
				points.append(position + Vector2.RIGHT.rotated(TAU * float(side) / 6.0) * 4.5)
			draw_polyline(points, color, 2.0, false)

func _draw_ellipse_arc(center: Vector2, radius_x: float, radius_y: float, from: float, to: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	var segments := maxi(4, int(absf(to - from) * 8.0))
	for index in segments + 1:
		var angle := lerpf(from, to, float(index) / float(segments))
		points.append((center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y)).round())
	draw_polyline(points, color, width, false)
