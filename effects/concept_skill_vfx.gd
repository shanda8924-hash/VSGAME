extends Node2D
class_name ConceptSkillVFX

const WIND_BLADE_SHEET := preload("res://assets/vfx/concepts/wind_blade_6f_v2.png")
const PIXEL_FRAME_COUNT := 6

var effect_color: Color = Color.WHITE
var effect_radius: float = 80.0
var skill_kind: String = ""
var effect_level: int = 1
var signature_profile: String = ""
var _pixel_sprite: AnimatedSprite2D


static func spawn(world: Node, position: Vector2, kind: String, radius: float, color: Color, level: int = 1, profile: String = "") -> ConceptSkillVFX:
	var effect := ConceptSkillVFX.new()
	effect.skill_kind = kind
	effect.effect_radius = radius
	effect.effect_color = color
	effect.effect_level = clampi(level, 1, 3)
	effect.signature_profile = profile
	world.add_child(effect)
	effect.global_position = position
	return effect


func _ready() -> void:
	add_to_group("transient_vfx")
	z_index = 46
	process_mode = Node.PROCESS_MODE_ALWAYS
	if skill_kind == "wind_blade":
		_build_wind_blade_sprite()
	if signature_profile != "":
		set_meta("signature_vfx_profile", signature_profile)
		set_meta("signature_vfx_level", effect_level)
	scale = Vector2(0.12, 0.12) if signature_profile != "" else Vector2(0.22, 0.22)
	queue_redraw()
	var tween := create_tween().set_ignore_time_scale(true)
	tween.tween_property(self, "scale", Vector2.ONE, 0.12 if signature_profile != "" else 0.09).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.18 + effect_level * 0.04 if signature_profile != "" else 0.05)
	# 全体Alpha Fadeではなく、短い端方向の圧縮でTriggered現象を崩して消す。
	tween.tween_property(self, "scale", Vector2(1.10, 0.06 if signature_profile != "" else 0.12), 0.12 if signature_profile != "" else 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)


func _draw() -> void:
	var c := effect_color
	if signature_profile != "":
		_draw_signature(c)
		return
	match skill_kind:
		"thunder_strike":
			var points := PackedVector2Array([Vector2(-8, -effect_radius), Vector2(7, -26), Vector2(-5, -8), Vector2(10, effect_radius * 0.35)])
			draw_polyline(points, c, 8.0, false)
			draw_circle(Vector2.ZERO, effect_radius * 0.35, Color(c.r, c.g, c.b, 0.18))
		"wind_blade":
			# 新規6-frame Pixel SpriteがShape形成からFragment化まで担う。
			# Smooth arcを重ねず、Triggered VFXの画面密度を抑える。
			pass
		"light_burst":
			draw_circle(Vector2.ZERO, effect_radius * 0.18, c)
			for angle in 8:
				var direction := Vector2.RIGHT.rotated(float(angle) * TAU / 8.0)
				draw_line(direction * effect_radius * 0.32, direction * effect_radius, c, 5.0)
		"dark_rift":
			draw_arc(Vector2.ZERO, effect_radius, -2.8, 0.25, 20, c, 8.0, false)
			draw_arc(Vector2.ZERO, effect_radius * 0.66, -0.2, 2.9, 16, Color(c.r, c.g, c.b, 0.65), 4.0, false)
		_:
			draw_circle(Vector2.ZERO, effect_radius, Color(c.r, c.g, c.b, 0.14))
			draw_arc(Vector2.ZERO, effect_radius, 0.0, TAU, 24, c, 6.0, false)


func _draw_signature(c: Color) -> void:
	match signature_profile:
		"thunderlord_descent":
			_draw_thunderlord(c)
		"inferno_pillar":
			_draw_inferno_pillar(c)
		"glacial_spear_rain":
			_draw_glacial_spears(c)
		"radiant_blade_array":
			_draw_radiant_blades(c)
		"void_severance":
			_draw_void_severance(c)
		_:
			_draw_pixel_ring(effect_radius, c, 14, 7.0)


func _draw_thunderlord(c: Color) -> void:
	var r := effect_radius
	var blade := PackedVector2Array([
		Vector2(-9, -r * 1.10), Vector2(11, -r * 1.10), Vector2(8, -r * 0.16),
		Vector2(r * 0.16, -r * 0.04), Vector2(7, r * 0.09), Vector2(5, r * 0.58),
		Vector2(-5, r * 0.58), Vector2(-7, r * 0.09), Vector2(-r * 0.16, -r * 0.04), Vector2(-8, -r * 0.16)
	])
	draw_colored_polygon(blade, Color(c.r, c.g, c.b, 0.86))
	draw_polyline(PackedVector2Array([Vector2(-r * 0.72, -r * 0.72), Vector2(-r * 0.25, -r * 0.22), Vector2(-r * 0.48, 0), Vector2(-r * 0.05, r * 0.48)]), c, 7.0, false)
	draw_polyline(PackedVector2Array([Vector2(r * 0.75, -r * 0.62), Vector2(r * 0.28, -r * 0.14), Vector2(r * 0.50, r * 0.02), Vector2(r * 0.10, r * 0.52)]), c, 7.0, false)
	_draw_pixel_ring(r * 0.62, Color(c.r, c.g, c.b, 0.82), 12, 8.0)
	_draw_fragments(c, r, 7 + effect_level * 2, 0.82)


func _draw_inferno_pillar(c: Color) -> void:
	var r := effect_radius
	var deep := Color("b82d20")
	draw_rect(Rect2(Vector2(-r * 0.20, -r), Vector2(r * 0.40, r * 1.48)), deep, true)
	var flame := PackedVector2Array([
		Vector2(-r * 0.30, r * 0.36), Vector2(-r * 0.38, -r * 0.08), Vector2(-r * 0.16, -r * 0.30),
		Vector2(-r * 0.08, -r), Vector2(r * 0.05, -r * 0.48), Vector2(r * 0.22, -r * 0.82),
		Vector2(r * 0.18, -r * 0.22), Vector2(r * 0.38, r * 0.04), Vector2(r * 0.28, r * 0.38)
	])
	draw_colored_polygon(flame, Color(c.r, c.g, c.b, 0.90))
	draw_rect(Rect2(Vector2(-r * 0.07, -r * 0.54), Vector2(r * 0.14, r * 0.88)), Color("ffd55c"), true)
	_draw_pixel_ring(r * 0.74, c, 14, 9.0)
	_draw_pixel_ring(r * 0.48, Color("ffb03d"), 12, 6.0)
	_draw_fragments(c, r, 9 + effect_level * 3, 1.02)


func _draw_glacial_spears(c: Color) -> void:
	var r := effect_radius
	var spear_count := 7 + effect_level * 2
	for index in spear_count:
		var angle := TAU * float(index) / float(spear_count) + 0.18
		var direction := Vector2.RIGHT.rotated(angle)
		var side := direction.orthogonal()
		var tip := direction * r
		var base := direction * r * 0.22
		var spear := PackedVector2Array([tip, base + side * 7.0, direction * r * 0.04, base - side * 7.0])
		draw_colored_polygon(spear, c if index % 2 == 0 else Color(c.r, c.g, c.b, 0.72))
	_draw_pixel_ring(r * 0.38, Color("d8f8ff"), 12, 7.0)
	draw_rect(Rect2(Vector2(-r * 0.15, -r * 0.15), Vector2(r * 0.30, r * 0.30)), Color(c.r, c.g, c.b, 0.72), true)
	_draw_fragments(c, r, 8 + effect_level * 3, 0.90)


func _draw_radiant_blades(c: Color) -> void:
	var r := effect_radius
	var count := 8 + effect_level * 2
	for index in count:
		var angle := TAU * float(index) / float(count)
		var direction := Vector2.RIGHT.rotated(angle)
		var side := direction.orthogonal()
		var blade := PackedVector2Array([
			direction * r, direction * r * 0.30 + side * 5.0,
			direction * r * 0.12, direction * r * 0.30 - side * 5.0
		])
		draw_colored_polygon(blade, c if index % 2 == 0 else Color("ffd96a"))
	_draw_pixel_ring(r * 0.68, Color(c.r, c.g, c.b, 0.78), 16, 5.0)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -r * 0.23), Vector2(r * 0.23, 0), Vector2(0, r * 0.23), Vector2(-r * 0.23, 0)]), Color("fff8cf"))
	_draw_fragments(Color("ffe88f"), r, 7 + effect_level * 3, 0.84)


func _draw_void_severance(c: Color) -> void:
	var r := effect_radius
	var rift := PackedVector2Array([
		Vector2(-r, -r * 0.14), Vector2(-r * 0.58, -r * 0.28), Vector2(-r * 0.26, -r * 0.09),
		Vector2(0, -r * 0.24), Vector2(r * 0.27, -r * 0.07), Vector2(r * 0.62, -r * 0.26),
		Vector2(r, -r * 0.10), Vector2(r * 0.58, r * 0.18), Vector2(r * 0.22, r * 0.07),
		Vector2(-r * 0.08, r * 0.25), Vector2(-r * 0.42, r * 0.08), Vector2(-r * 0.76, r * 0.22)
	])
	draw_colored_polygon(rift, Color("160d25"))
	var outline := rift.duplicate()
	outline.append(rift[0])
	draw_polyline(outline, c, 8.0, false)
	draw_line(Vector2(-r * 0.72, 0), Vector2(r * 0.72, 0), Color("d89cff"), 4.0, false)
	for index in 3 + effect_level:
		var y := -r * 0.55 + index * r * 0.28
		draw_line(Vector2(-r * 0.42, y), Vector2(-r * 0.18, y + r * 0.12), Color(c.r, c.g, c.b, 0.62), 5.0, false)
		draw_line(Vector2(r * 0.42, -y), Vector2(r * 0.18, -y - r * 0.12), Color(c.r, c.g, c.b, 0.62), 5.0, false)
	_draw_fragments(c, r, 9 + effect_level * 3, 0.96)


func _draw_pixel_ring(radius: float, color: Color, segments: int, width: float) -> void:
	var points := PackedVector2Array()
	for index in segments + 1:
		points.append(Vector2.RIGHT.rotated(TAU * float(index) / float(segments)) * radius)
	draw_polyline(points, color, width, false)


func _draw_fragments(color: Color, radius: float, count: int, spread: float) -> void:
	for index in count:
		var angle := TAU * float(index) / float(count) + float(index % 3) * 0.17
		var start := Vector2.RIGHT.rotated(angle) * radius * (0.62 + 0.06 * float(index % 4))
		var direction := Vector2.RIGHT.rotated(angle) * radius * (0.12 + 0.025 * float(index % 3)) * spread
		draw_line(start, start + direction, color, 3.0 + float(index % 2) * 2.0, false)


func _build_wind_blade_sprite() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("wind_blade")
	frames.set_animation_loop("wind_blade", false)
	frames.set_animation_speed("wind_blade", 24.0)
	var frame_size := Vector2(WIND_BLADE_SHEET.get_width() / PIXEL_FRAME_COUNT, WIND_BLADE_SHEET.get_height())
	for frame_index in PIXEL_FRAME_COUNT:
		var atlas := AtlasTexture.new()
		atlas.atlas = WIND_BLADE_SHEET
		atlas.region = Rect2(Vector2(frame_index * frame_size.x, 0.0), frame_size)
		frames.add_frame("wind_blade", atlas)
	_pixel_sprite = AnimatedSprite2D.new()
	_pixel_sprite.name = "WindBladePixelVFX"
	_pixel_sprite.sprite_frames = frames
	_pixel_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pixel_sprite.scale = Vector2.ONE * clampf(effect_radius * 1.62 / frame_size.y, 0.9, 2.3)
	_pixel_sprite.z_index = 2
	add_child(_pixel_sprite)
	_pixel_sprite.play("wind_blade")
	set_meta("pixel_vfx_id", "concept_wind_blade_v2")
	set_meta("pixel_vfx_texture", WIND_BLADE_SHEET.resource_path)
