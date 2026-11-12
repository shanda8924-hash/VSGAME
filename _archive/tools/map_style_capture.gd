extends Node2D

func _ready() -> void:
	SaveManager.begin_ephemeral_session()
	_run.call_deferred()

func _run() -> void:
	var output := "res://artifacts/map_style_review"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--style-output="):
			output = argument.trim_prefix("--style-output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var stage := preload("res://entities/stage_environment/stage_environment.tscn").instantiate() as StageEnvironment
	add_child(stage)
	await get_tree().process_frame
	for map_index in [1, 2, 3]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 91820 + map_index
		var config := {1: Vector4i(78,78,10,1), 2: Vector4i(86,86,11,2), 3: Vector4i(94,94,12,2)}
		var c: Vector4i = config[map_index]
		var map := DungeonGenerator.generate(c.x, c.y, c.z, c.w, rng)
		GameManager.current_map_index = map_index
		seed(72100 + map_index)
		stage.build_dungeon(map)
		var room: Rect2i = map.rooms[mini(2, map.rooms.size()-1)]
		var focus := room.position + room.size / 2
		stage.position = get_viewport_rect().size * 0.5 - map.grid_to_world(focus)
		var actors := Node2D.new()
		stage.add_child(actors)
		var names := ["Soldier", "Swordsman", "Wizard"]
		for index in names.size():
			var character: String = names[index]
			var sprite := Sprite2D.new()
			sprite.texture = load("res://assets/sprites/player/%s/%s_Idle.png" % [character, character])
			sprite.region_enabled = true
			var frame_size := sprite.texture.get_height()
			sprite.region_rect = Rect2(0, 0, frame_size, frame_size)
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.scale = Vector2.ONE * 1.65
			sprite.position = map.grid_to_world(focus) + Vector2((index - 1) * 64, 0)
			sprite.z_index = 50
			actors.add_child(sprite)
		for frame in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png(output + "/map%d.png" % map_index) == OK)
		actors.free()
	print("MAP_STYLE_CAPTURE PASS")
	get_tree().quit()
