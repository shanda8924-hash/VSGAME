extends Node
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 450)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var stage := preload("res://entities/stage_environment/stage_environment.tscn").instantiate()
	viewport.add_child(stage)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91822
	var map := DungeonGenerator.generate(86, 86, 11, 2, rng)
	GameManager.current_map_index = 2
	stage.build_dungeon(map)
	var base: Rect2i = map.get_meta("scenic_landmarks")[0].footprint
	stage.scale = Vector2.ONE * 2.0
	stage.position = Vector2(400, 290) - (map.grid_to_world(base.position) + Vector2(96, 30)) * 2.0
	var worker := stage.get_node("ScenicLandmarks/Miner")
	worker.set_process(false)
	for i in 4:
		worker.elapsed = [0.0, 1.0, 1.4, 1.7][i]
		worker._update_pose()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://artifacts/map_themes/miner-frame%d.png" % i)
	print("MINER_CAPTURE 4 poses")
	get_tree().quit()
