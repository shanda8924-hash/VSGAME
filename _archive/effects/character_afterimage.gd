extends Sprite2D
class_name CharacterAfterimage

func setup(source: AnimatedSprite2D, tint: Color, lifetime: float) -> void:
	if source.sprite_frames == null:
		queue_free()
		return
	texture = source.sprite_frames.get_frame_texture(source.animation, source.frame)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group("transient_vfx")
	global_position = source.global_position
	global_rotation = source.global_rotation
	scale = source.global_scale
	flip_h = source.flip_h
	modulate = tint
	z_index = source.z_index
	var tween := create_tween()
	tween.tween_interval(lifetime * 0.68)
	# Afterimageも寿命途中から全体を薄くせず、最後に縦へ潰して残光だけ消す。
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, lifetime * 0.32).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale:y", scale.y * 0.15, lifetime * 0.32).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_callback(queue_free)
