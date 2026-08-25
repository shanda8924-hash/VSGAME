extends Node2D
class_name ConceptSkillVFX

const WIND_BLADE_SHEET := preload("res://assets/vfx/concepts/wind_blade_6f_v2.png")
const PIXEL_FRAME_COUNT := 6

var effect_color: Color = Color.WHITE
var effect_radius: float = 80.0
var skill_kind: String = ""
var _pixel_sprite: AnimatedSprite2D


static func spawn(world: Node, position: Vector2, kind: String, radius: float, color: Color) -> ConceptSkillVFX:
	var effect := ConceptSkillVFX.new()
	effect.skill_kind = kind
	effect.effect_radius = radius
	effect.effect_color = color
	world.add_child(effect)
	effect.global_position = position
	return effect


func _ready() -> void:
	add_to_group("transient_vfx")
	z_index = 46
	process_mode = Node.PROCESS_MODE_ALWAYS
	if skill_kind == "wind_blade":
		_build_wind_blade_sprite()
	scale = Vector2(0.22, 0.22)
	queue_redraw()
	var tween := create_tween().set_ignore_time_scale(true)
	tween.tween_property(self, "scale", Vector2.ONE, 0.09).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.05)
	# 全体Alpha Fadeではなく、短い端方向の圧縮でTriggered現象を崩して消す。
	tween.tween_property(self, "scale", Vector2(1.08, 0.12), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)


func _draw() -> void:
	var c := effect_color
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
