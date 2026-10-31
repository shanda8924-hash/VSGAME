extends Node2D
class_name ActiveSkillVFX
## Spaceスキルの生成Pixel Animation。発生地点を固定し、6枚の絵で展開・崩壊する。
const MAX_VISUAL_SIDE := 192.0

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
	var visual_size := Vector2.ONE * radius * 2.0
	var angle := 0.0
	if style == "charge":
		visual_size.y = maxf(radius * 0.45, 36.0)
		angle = facing.angle()
	elif style == "burst" and half_angle < 180.0:
		visual_size.y = radius * clampf(sin(deg_to_rad(half_angle)) * 2.0, 0.65, 2.0)
		angle = facing.angle()
	# 64px原画を広い攻撃半径へ際限なく拡大すると人物と床を覆う。
	# 上限は描画だけ。実際の攻撃半径はActiveSkillComponent側の値を維持する。
	visual_size *= minf(1.0, MAX_VISUAL_SIDE / maxf(visual_size.x, visual_size.y))
	# Art carries its authored palette. The old yellow override stays in the
	# public setup API, but must not recolor every new design into the same yellow.
	var sprite := PixelSpriteVFX.spawn(self, global_position, "active_" + style, visual_size, 0.30, angle)
	if sprite == null:
		queue_free()
		return
	sprite.z_index = 0
	sprite.animation_finished.connect(queue_free)
	set_meta("pixel_vfx_id", "active_" + style)
