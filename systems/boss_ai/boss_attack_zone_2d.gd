extends Node2D
## 試作ボスのline/cone/ring警告とダメージ判定を、通常2D MAPで共有する地面予兆。

var kind := "circle"
var origin := Vector2.ZERO
var direction := Vector2.RIGHT
var radius := 62.0
var inner_radius := 0.0
var half_angle := deg_to_rad(70.0)
var length := 280.0
var half_width := 55.0
var progress := 0.0
var impact := false
var source: EnemyBasic
var duration := 0.0
var elapsed := 0.0

func _ready() -> void:
	add_to_group("boss_attack_transient")
	global_position = origin
	global_rotation = direction.angle()
	z_index = 2
	queue_redraw()

func contains(point: Vector2) -> bool:
	var local := (point - origin).rotated(-direction.angle())
	if kind == "line":
		return local.x >= 0.0 and local.x <= length and absf(local.y) <= half_width
	var distance := local.length()
	if distance < inner_radius or distance > radius:
		return false
	if distance <= 0.000001 and inner_radius == 0.0:
		return true
	return kind != "cone" or absf(local.angle()) <= half_angle

func contains_sweep(point: Vector2, previous_progress: float, current_progress: float, reverse: bool = false) -> bool:
	if kind != "cone" or not contains(point):
		return false
	var local := (point - origin).rotated(-direction.angle())
	if local.length_squared() <= 0.000001:
		return true
	var fraction := (local.angle() + half_angle) / (2.0 * half_angle)
	if reverse:
		fraction = 1.0 - fraction
	var start := clampf(minf(previous_progress, current_progress), 0.0, 1.0)
	var finish := clampf(maxf(previous_progress, current_progress), 0.0, 1.0)
	return fraction >= start - 0.000001 and fraction <= finish + 0.000001

func redraw() -> void:
	queue_redraw()

func _draw() -> void:
	var edge := Color("ffe0c8") if impact else Color("ff7a4a")
	var fill := Color(edge, 0.42 if impact else 0.14 + 0.12 * progress)
	if kind == "cone" and impact:
		edge = Color("ff7a4a", 0.55)
		fill = Color("ff7a4a", 0.08)
	if kind == "line":
		var polygon := PackedVector2Array([
			Vector2(0.0, -half_width), Vector2(length, -half_width),
			Vector2(length, half_width), Vector2(0.0, half_width),
		])
		draw_colored_polygon(polygon, fill)
		draw_polyline(PackedVector2Array([polygon[0], polygon[1], polygon[2], polygon[3], polygon[0]]), edge, 2.0, false)
		return
	var arc := half_angle if kind == "cone" else PI
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for index in 49:
		var angle := lerpf(-arc, arc, float(index) / 48.0)
		outer.append(Vector2.from_angle(angle) * radius)
		inner.append(Vector2.from_angle(angle) * inner_radius)
	for index in 48:
		if inner_radius <= 0.0:
			draw_colored_polygon(PackedVector2Array([Vector2.ZERO, outer[index], outer[index + 1]]), fill)
		else:
			draw_colored_polygon(PackedVector2Array([inner[index], outer[index], outer[index + 1], inner[index + 1]]), fill)
	draw_polyline(outer, edge, 2.0, false)
	if inner_radius > 0.0:
		draw_polyline(inner, edge, 2.0, false)
	if kind == "cone":
		draw_line(Vector2.ZERO, outer[0], edge, 2.0, false)
		draw_line(Vector2.ZERO, outer[outer.size() - 1], edge, 2.0, false)

func _process(delta: float) -> void:
	if source != null and (not is_instance_valid(source) or source._is_dead):
		queue_free()
		return
	if duration > 0.0:
		elapsed += delta
		progress = clampf(elapsed/duration,0.0,1.0)
		queue_redraw()
