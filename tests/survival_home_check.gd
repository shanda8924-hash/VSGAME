extends Node
var OUT := "res://artifacts/open_field_survival"
var failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	SaveManager.data["meta_currency"] = 0
	if "--touch-preview" in OS.get_cmdline_user_args(): OUT += "/mobile"
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "/" + name + ".png")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var home := preload("res://ui/home/home.tscn").instantiate()
	home.tree_entered.connect(func(): get_tree().current_scene = home)
	get_tree().root.add_child(home)
	for i in 4: await get_tree().process_frame
	var choice := home.get_node("MarginContainer/VBoxContainer/MapChoice") as OptionButton
	check(choice.item_count == 3, "Home lost a theme")
	var size := get_viewport().get_visible_rect().size
	for button in home.character_grid.get_children():
		check(button.get_global_rect().end.y <= size.y and button.get_global_rect().position.y >= choice.get_global_rect().end.y, "Home controls overlap or exceed screen")
	await capture("home")
	choice.select(2)
	choice.item_selected.emit(2)
	check(GameManager.selected_survival_map == 3, "Stage selector disconnected")
	for button in home.character_grid.get_children():
		if not button.disabled:
			button.pressed.emit()
			break
	for theme in [3, 1, 2]:
		if theme != 3:
			GameManager.selected_survival_map = theme
			get_tree().reload_current_scene()
		await get_tree().process_frame
		await get_tree().process_frame
		var game := get_tree().current_scene
		var controller := game.get_node("MapRunController") as MapRunController
		while not controller._active: await get_tree().process_frame
		check(GameManager.survival_mode_active and GameManager.current_map_index == theme, "Real selected stage entry failed")
		check(GameManager.dungeon_map.get_meta("survival_arena", false), "Theme uses old dungeon")
		game.get_node("WaveSpawner").set_process(false)
		controller.set_process(false)
		check(game.get_node("StageEnvironment")._active_map_theme == theme, "Arena rendered wrong art theme")
		await capture("arena%d" % theme)
	var f := FileAccess.open(OUT + "/home_check.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"failures": failures, "three_real_stage_entries": true, "home_fits": true, "silent": true}, "\t"))
	f.close()
	var exit := preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(exit)
	exit.begin(0 if failures.is_empty() else 1, "SURVIVAL_HOME " + ("PASS" if failures.is_empty() else "FAIL"))
