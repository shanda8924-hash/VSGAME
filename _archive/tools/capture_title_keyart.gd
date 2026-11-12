extends Node
func _ready() -> void:
	var title := (load("res://scenes/title.tscn") as PackedScene).instantiate()
	add_child(title)
	DirAccess.make_dir_recursive_absolute("res://artifacts/title_keyart")
	await capture("title")
	title._on_start_pressed()
	await capture("modes")
	AudioManager.stop_all(false)
	get_tree().quit()

func capture(filename: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/title_keyart/%s.png" % filename)
