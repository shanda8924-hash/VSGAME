extends Node
## パズルの試作の実画面を撮る。xvfb-run … --rendering-driver opengl3 res://tools/capture_puzzle.tscn → artifacts/puzzle/*.png
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/puzzle")
	var screen := (load("res://scenes/puzzle_prototype.tscn") as PackedScene).instantiate()
	add_child(screen)
	await get_tree().process_frame
	screen.start(11)
	for i in 4: await get_tree().process_frame
	await _shot("1_start")
	for turn in 14:
		var move: Array[int] = screen.model.find_move()
		screen.board_view.request_swap(move[0], move[1])
		if turn == 6:
			for i in 12: await get_tree().process_frame
			await _shot("2_clearing")
		if screen.board_view.busy:
			await screen.board_view.resolved
	for i in 20: await get_tree().process_frame
	await _shot("3_after_14_moves")
	get_tree().quit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/puzzle/%s.png" % name)
