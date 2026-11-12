extends Node2D
class_name ConceptSkillVFX
## 通常6種・完成大技5種の描画専用入口。範囲/状態/ダメージはConceptSystemが持つ。
const MAX_VISUAL_SIDE := 192.0

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
	var effect_id := "concept_" + skill_kind
	var lifetime := 0.22
	if signature_profile != "":
		effect_id = "signature_" + signature_profile
		lifetime = 0.42 + effect_level * 0.04
		set_meta("signature_vfx_profile", signature_profile)
		set_meta("signature_vfx_level", effect_level)
	var visual_side := minf(effect_radius * 2.0, MAX_VISUAL_SIDE)
	var sprite := PixelSpriteVFX.spawn(self, global_position, effect_id, Vector2.ONE * visual_side, lifetime)
	if sprite == null:
		queue_free()
		return
	sprite.ignore_time_scale = true
	sprite.z_index = 0
	if skill_kind == "wind_blade" and signature_profile == "":
		sprite.name = "WindBladePixelVFX"
	sprite.animation_finished.connect(queue_free)
	_pixel_sprite = sprite
	set_meta("pixel_vfx_id", effect_id)
	set_meta("pixel_vfx_texture", PixelSpriteVFX.ASSET_DIRECTORY + effect_id + ".png")
