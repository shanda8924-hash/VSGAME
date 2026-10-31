extends RefCounted
class_name ImportedBurstVFX

const DODGE_TEXTURE := preload("res://assets/vfx/dodge/holy_impact.png")
const CHEST_TEXTURE := preload("res://assets/vfx/dodge/holy_chest.png")
static var _frames: Dictionary = {}

static func spawn(parent: Node2D, position: Vector2, kind: String) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	if not _frames.has(kind):
		var texture: Texture2D = CHEST_TEXTURE if kind == "chest" else DODGE_TEXTURE
		var frame_size := 48 if kind == "chest" else 32
		var frames := SpriteFrames.new()
		frames.remove_animation("default")
		frames.add_animation("burst")
		frames.set_animation_loop("burst", false)
		frames.set_animation_speed("burst", 24.0)
		for index in int(texture.get_width() / frame_size):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(index * frame_size, 0, frame_size, frame_size)
			frames.add_frame("burst", atlas)
		_frames[kind] = frames
	var effect := AnimatedSprite2D.new()
	effect.name = "ImportedBurst_%s" % kind
	effect.add_to_group("transient_vfx")
	effect.sprite_frames = _frames[kind]
	effect.animation = "burst"
	effect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	effect.z_index = 18
	effect.scale = Vector2.ONE * (1.25 if kind == "chest" else 0.8)
	effect.speed_scale = 1.0 / maxf(Engine.time_scale, 0.1)
	parent.add_child(effect)
	effect.global_position = position
	effect.animation_finished.connect(effect.queue_free, CONNECT_ONE_SHOT)
	effect.play()
