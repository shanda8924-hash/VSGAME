extends SceneTree

func _initialize() -> void:
	var results := []
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment/templates.json"))
	for item in catalog:
		if item.slot != "weapon": continue
		var path := "res://assets/visuals/ember_v5/equipment/%s.png" % item.id
		var source := Image.new()
		source.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
		var texture := load(path) as Texture2D
		var cached := texture.get_image()
		source.convert(Image.FORMAT_RGBA8)
		cached.convert(Image.FORMAT_RGBA8)
		var different := 0
		var soft := 0
		for y in source.get_height():
			for x in source.get_width():
				var alpha := cached.get_pixel(x,y).a
				if not is_equal_approx(alpha, source.get_pixel(x,y).a): different += 1
				if alpha > 0.0 and alpha < 1.0: soft += 1
		if different > 0: results.append({"id":item.id,"different":different,"soft":soft})
	var output := "res://artifacts/weapon_aura_walls"
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output+"/import_probe.json",FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
	print("TEXTURE_IMPORT_PROBE mismatches=%d: %s" % [results.size(),JSON.stringify(results)])
	assert(results.is_empty(),"Imported cutout differs from source")
	quit()
