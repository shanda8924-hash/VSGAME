extends Node

func _ready() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 640)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var atlas := load(preload("res://entities/stage_environment/scenic_landmarks.gd").SHEET) as Texture2D
	var regions := preload("res://entities/stage_environment/scenic_landmarks.gd").REGIONS
	for kind in [2, 3]:
		var sprite := Sprite2D.new()
		var cropped := AtlasTexture.new()
		cropped.atlas = atlas
		cropped.region = regions[kind]
		sprite.texture = cropped
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = Vector2(320, 320)
		sprite.scale = Vector2.ONE * 2.0
		var material := ShaderMaterial.new()
		material.shader = load("res://entities/stage_environment/landmark_flow.gdshader")
		material.set_shader_parameter("kind", kind)
		material.set_shader_parameter("region_origin", cropped.region.position)
		material.set_shader_parameter("region_size", cropped.region.size)
		sprite.material = material
		viewport.add_child(sprite)
		for frame in 4: await get_tree().process_frame
		var first := viewport.get_texture().get_image()
		var source := atlas.get_image().get_region(cropped.region)
		var checked_color := false
		for y in 20:
			for x in source.get_width():
				var original := source.get_pixel(x, y)
				if original.a > 0.99 and not checked_color:
					var pixel := Vector2i(Vector2(320, 320) - cropped.region.size + Vector2(x, y) * 2)
					var shown := first.get_pixelv(pixel)
					assert(Vector3(original.r, original.g, original.b).distance_to(Vector3(shown.r, shown.g, shown.b)) < 0.03, "shader must not multiply source color twice")
					checked_color = true
		assert(checked_color)
		assert(first.save_png("res://artifacts/landmark_flow_%d_a.png" % kind) == OK)
		await get_tree().create_timer(0.35, true, false, true).timeout
		for frame in 3: await get_tree().process_frame
		var second := viewport.get_texture().get_image()
		assert(first.get_data() != second.get_data(), "furnace/water animation must change pixels")
		assert(second.save_png("res://artifacts/landmark_flow_%d_b.png" % kind) == OK)
		viewport.remove_child(sprite)
		sprite.queue_free()
		await get_tree().process_frame
	print("LANDMARK_FLOW_CAPTURE saved real shader frames for furnace and water")
	get_tree().quit()
