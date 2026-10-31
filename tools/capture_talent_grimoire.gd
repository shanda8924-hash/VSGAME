extends Node
## Actual game UI screenshot, ephemeral save only. No gameplay test suite.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	GameManager.selected_character_id = "swordsman"
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	var menu := game.get_node("PauseMenu") as PauseMenu
	Input.action_press("talent_menu")
	await get_tree().process_frame
	Input.action_release("talent_menu")
	for i in 4:
		await get_tree().process_frame
	menu.talent_book.nodes[1].grab_focus()
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts/talent_grimoire")
	get_viewport().get_texture().get_image().save_png("res://artifacts/talent_grimoire/implemented.png")
	AudioManager.stop_all(false)
	get_tree().quit()
