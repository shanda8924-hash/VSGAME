extends Control
## One rigid hinged cover followed by three curved sheets. No sprite squash.
const COVER := preload("res://assets/visuals/book_motion_v2/cover.png")
const PAPER := preload("res://assets/visuals/book_motion_v2/paper.png")
const DURATION := 1.48
const COVER_END := .62
const PAGE_STARTS := [.64, .79, .94]
const PAGE_DURATIONS := [.28, .28, .44]
const WIDTH := 154.0
const HEIGHT := 180.0
const SEGMENTS := 36

# The live UI renders to one transparent viewport only while pages turn.
var ink_texture: Texture2D
var left_ink_uv := Rect2()
var right_ink_uv := Rect2()
var ink_on_pages := false

var phase := 0.0:
	set(value):
		phase = clampf(value, 0.0, DURATION)
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _ease(value: float) -> float:
	return .5 - .5 * cos(PI * clampf(value, 0.0, 1.0))

func cover_angle(time: float) -> float:
	return PI * _ease(time / COVER_END)

func page_angle(time: float, index: int) -> float:
	return PI * _ease((time - PAGE_STARTS[index]) / PAGE_DURATIONS[index])

func _project(u: float, v: float, angle: float, paper: bool) -> Vector2:
	var lift := sin(angle)
	var curl := sin(PI * u) * lift if paper else 0.0
	var x := cos(angle) * u * WIDTH + curl * WIDTH * .17
	var z := lift * u * WIDTH + curl * WIDTH * .12
	var perspective := 1.0 / (1.0 + z / 900.0)
	return Vector2(x, (v - .5) * HEIGHT - z * .18) * perspective

func _surface(angle: float, paper: bool, shadow: bool = false, printed_back: bool = false) -> void:
	var texture := PAPER if paper or angle > PI / 2 else COVER
	var base_light := 1.0 if paper or angle > PI / 2 else .91
	for i in SEGMENTS:
		var u0 := float(i) / SEGMENTS
		var u1 := float(i + 1) / SEGMENTS
		var points := PackedVector2Array([
			_project(u0, 0, angle, paper), _project(u1, 0, angle, paper),
			_project(u1, 1, angle, paper), _project(u0, 1, angle, paper)])
		if shadow:
			for p in points.size(): points[p] += Vector2(3, 5) * sin(angle)
			draw_colored_polygon(points, Color(0.045, .03, .045, .13 * sin(angle)))
			continue
		var light := base_light - .15 * sin(angle) - .08 * sin(PI * (u0 + u1) / 2.0) * sin(angle)
		light = snappedf(light, .025)
		var tint := Color(light, light, light, 1)
		var uv := PackedVector2Array([Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1)])
		draw_polygon(points, PackedColorArray([tint, tint, tint, tint]), uv, texture)
		if printed_back and ink_on_pages and ink_texture:
			# u=0 is the spine, i.e. the right edge of a settled left page.
			# Reverse UVs, not the text, so the final sheet reads left to right.
			var ink_uv := PackedVector2Array([left_page_uv(u0, 0), left_page_uv(u1, 0), left_page_uv(u1, 1), left_page_uv(u0, 1)])
			draw_polygon(points, PackedColorArray([tint, tint, tint, tint]), ink_uv, ink_texture)
	# Top and fore-edge track the hinge and bend; they never slide across the spine.
	var edge := PackedVector2Array()
	for i in SEGMENTS + 1: edge.append(_project(float(i) / SEGMENTS, 0, angle, paper))
	edge.append(_project(1, 1, angle, paper))
	for i in range(SEGMENTS - 1, -1, -1): edge.append(_project(float(i) / SEGMENTS, 1, angle, paper))
	draw_polyline(edge, Color("b8ab8b") if paper else Color("6c4656"), .7 if paper else 1.5, false)

func _draw() -> void:
	var factor := page_scale()
	# The screen-space spine stays at the same point for the whole opening.
	draw_set_transform(size / 2, 0, Vector2.ONE * factor)
	var block := Rect2(Vector2(0, -HEIGHT / 2), Vector2(WIDTH, HEIGHT))
	draw_rect(Rect2(block.position + Vector2(-2, 0), block.size + Vector2(5, 6)), Color("302431"))
	for i in 3:
		draw_rect(Rect2(block.position + Vector2(1, i + 2), block.size + Vector2(2, 0)), Color("b6a686").lightened(.06 * i))
	draw_texture_rect(PAPER, block, false)
	for i in 5:
		draw_rect(Rect2(Vector2(i, -HEIGHT / 2), Vector2(1, HEIGHT)), Color(0.13, .08, .09, .2 - .03 * i))
	if ink_on_pages and phase >= PAGE_STARTS[2]:
		_draw_ink(block, false)
	var angle := cover_angle(phase)
	_surface(angle, false, true)
	_surface(angle, false)
	if phase >= COVER_END:
		# The inside of the cover becomes the left leaf of this same persistent book.
		var left := Rect2(Vector2(-WIDTH, -HEIGHT / 2), Vector2(WIDTH, HEIGHT))
		draw_rect(Rect2(left.position + Vector2(-3, -2), left.size + Vector2(5, 7)), Color("302431"))
		for i in 3:
			draw_rect(Rect2(left.position + Vector2(-1, i + 2), left.size), Color("b6a686").lightened(.06 * i))
		draw_texture_rect(PAPER, left, false)
		for i in 5:
			draw_rect(Rect2(Vector2(-1 - i, -HEIGHT / 2), Vector2(1, HEIGHT)), Color(0.13, .08, .09, .22 - .04 * i))
		if ink_on_pages and phase >= PAGE_STARTS[2] + PAGE_DURATIONS[2]:
			_draw_ink(left, true)
	for index in PAGE_STARTS.size():
		if phase > PAGE_STARTS[index] and phase < PAGE_STARTS[index] + PAGE_DURATIONS[index]:
			var sheet_angle := page_angle(phase, index)
			_surface(sheet_angle, true, true)
			_surface(sheet_angle, true, false, index == 2 and sheet_angle > PI / 2)
	draw_set_transform(Vector2.ZERO)

func page_scale() -> float:
	return minf(size.x / (2.0 * WIDTH + 12.0), size.y / (HEIGHT + 12.0))

func page_rect(left: bool) -> Rect2:
	var factor := page_scale()
	return Rect2(size / 2 + Vector2(-WIDTH if left else 0.0, -HEIGHT / 2) * factor, Vector2(WIDTH, HEIGHT) * factor)

func left_page_uv(u: float, v: float) -> Vector2:
	return left_ink_uv.position + Vector2(1.0 - u, v) * left_ink_uv.size

func _draw_ink(rect: Rect2, left: bool) -> void:
	if not ink_texture: return
	var uv := left_ink_uv if left else right_ink_uv
	draw_texture_rect_region(ink_texture, rect, Rect2(uv.position * ink_texture.get_size(), uv.size * ink_texture.get_size()))
