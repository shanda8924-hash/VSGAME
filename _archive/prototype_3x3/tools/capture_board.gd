extends Node
## 盤面の試作の実画面を撮る。xvfb-run … --rendering-driver opengl3 res://tools/capture_board.tscn → artifacts/board/*.png
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/board")
	var screen := (load("res://scenes/board_prototype.tscn") as PackedScene).instantiate()
	add_child(screen)
	await get_tree().process_frame
	screen.start_run(7)
	for index in [0, 4, 8]:
		screen.board_view.tap_cell(index)
	screen.model.cells.assign([4, 1, 2, 3, 4, 5, 0, 2, 4])
	screen.board_view.bind(screen.model)
	await _shot("1_hold")
	screen.spin_button.pressed.emit()
	for i in 14: await get_tree().process_frame
	await _shot("2_spinning")
	await screen.board_view.spin_finished
	for i in 3: await get_tree().process_frame
	await _shot("3_result")
	get_tree().quit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/board/%s.png" % name)
