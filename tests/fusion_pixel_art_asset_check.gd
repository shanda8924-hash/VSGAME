extends Node

const FUSIONS := ["frostfire", "plasma", "solar", "inferno", "superconductor", "aurora", "void_frost", "judgment", "voidstorm", "eclipse"]
const MODES := ["attack", "trail", "hit", "burst", "intro"]
const RUNTIME_MODES := ["attack", "trail", "hit", "burst", "formation"]

var failures: Array[String] = []
var texture_paths: Dictionary = {}

func _ready() -> void:
	for fusion_id in FUSIONS:
		var data := DataLoader.fusion_vfx_effects.get(fusion_id) as FusionVFXData
		_check(data != null, "%s generated Pixel Art Resource loads" % fusion_id)
		if data == null:
			continue
		var textures := {
			"attack": data.attack_sprite_sheet,
			"trail": data.trail_sprite_sheet,
			"hit": data.hit_sprite_sheet,
			"burst": data.burst_sprite_sheet,
			"intro": data.intro_sprite_sheet,
		}
		for mode in MODES:
			var texture := textures[mode] as Texture2D
			_check(texture != null, "%s %s image is assigned" % [fusion_id, mode])
			if texture == null:
				continue
			var expected_fragment := "/assets/vfx/fusions/%s/fx_fusion_%s_%s_6f.png" % [fusion_id, fusion_id, mode]
			_check(texture.resource_path.ends_with(expected_fragment), "%s %s uses its generated Fusion-only PNG" % [fusion_id, mode])
			_check(not texture_paths.has(texture.resource_path), "%s %s does not reuse another Fusion image" % [fusion_id, mode])
			texture_paths[texture.resource_path] = true
			_check(texture.get_size() == Vector2(384, 64), "%s %s is a six-frame 64px sheet" % [fusion_id, mode])
			var image := texture.get_image()
			_check(image != null and image.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_RGBAF, Image.FORMAT_RGBAH], "%s %s keeps alpha" % [fusion_id, mode])
			if image:
				_check(image.get_pixel(0, 0).a <= 0.01, "%s %s has a transparent corner" % [fusion_id, mode])
				_check(_opaque_pixel_count(image) > 32, "%s %s contains visible generated pixels" % [fusion_id, mode])
				_check_phenomenon_lifecycle(image, fusion_id, mode)

		for runtime_mode in RUNTIME_MODES:
			var effect := FusionVFXEffect.new()
			add_child(effect)
			effect.configure(fusion_id, Vector2.ZERO, Vector2(80, 0), runtime_mode, 1.0)
			var sprite := effect.get_node_or_null("GeneratedFusionPixelArt") as AnimatedSprite2D
			_check(bool(effect.get_meta("generated_pixel_art", false)), "%s %s Runtime marks generated Pixel Art active" % [fusion_id, runtime_mode])
			_check(sprite != null and sprite.sprite_frames.get_frame_count("play") == 6, "%s %s Runtime plays six generated frames" % [fusion_id, runtime_mode])
			_check(String(effect.get_meta("pixel_art_texture", "")).contains("/assets/vfx/fusions/%s/" % fusion_id), "%s %s Runtime resolves its own PNG" % [fusion_id, runtime_mode])
			_check(_count_collisions(effect) == 0, "%s %s generated VFX remains visual-only" % [fusion_id, runtime_mode])
			if runtime_mode in ["attack", "trail"] and sprite:
				var fixed_position := sprite.position
				effect._update_pixel_art_transform(0.92)
				_check(sprite.position.is_equal_approx(fixed_position), "%s %s keeps the image fixed while its shape animates" % [fusion_id, runtime_mode])
				_check(is_zero_approx(float(effect.get_meta("sprite_translation_ratio", -1.0))), "%s %s declares zero sprite translation" % [fusion_id, runtime_mode])
			effect.queue_free()
			await get_tree().process_frame

	_check(texture_paths.size() == 50, "all 10 Fusion x 5 mode images are unique and connected")
	for failure in failures:
		push_error(failure)
	print("FUSION_PIXEL_ART_ASSET_CHECK failures=%d textures=%d" % [failures.size(), texture_paths.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _opaque_pixel_count(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.01:
				count += 1
	return count

func _check_phenomenon_lifecycle(image: Image, fusion_id: String, mode: String) -> void:
	var visible_counts: Array[int] = []
	for frame_index in 6:
		var visible := 0
		var alpha_sum := 0.0
		for y in 64:
			for x in 64:
				var alpha := image.get_pixel(frame_index * 64 + x, y).a
				if alpha > 0.01:
					visible += 1
					alpha_sum += alpha
		visible_counts.append(visible)
		var average_alpha := alpha_sum / float(maxi(visible, 1))
		_check(average_alpha >= 0.78, "%s %s frame %d stays strongly coloured instead of whole-frame fading" % [fusion_id, mode, frame_index])
	_check(visible_counts[0] < visible_counts[3], "%s %s grows toward its peak frame" % [fusion_id, mode])
	_check(visible_counts[5] < visible_counts[3], "%s %s loses outer geometry after its peak" % [fusion_id, mode])

func _count_collisions(root: Node) -> int:
	var count := 1 if root is CollisionObject2D or root is CollisionShape2D else 0
	for child in root.get_children():
		count += _count_collisions(child)
	return count

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
