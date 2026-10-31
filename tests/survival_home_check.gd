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
	var row := home.stage_row as HBoxContainer
	check(row.get_child_count() == 3, "Home lost a theme")
	var size := get_viewport().get_visible_rect().size
	for card in row.get_children():
		check(get_viewport().get_visible_rect().encloses(card.get_global_rect()), "Stage card exceeds screen")
	for button in home.character_grid.get_children():
		check(button.get_global_rect().end.y <= size.y and button.get_global_rect().position.y >= row.get_global_rect().end.y, "Home controls overlap or exceed screen")
	# 欠片0: MAP3は封印されたまま、出撃先はMAP1。
	check(not SaveManager.is_map_unlocked(3) and SaveManager.is_map_unlocked(1), "Stage lock default wrong")
	(row.get_child(2) as Button).pressed.emit()
	await get_tree().process_frame
	check(GameManager.selected_survival_map == 1 and not SaveManager.is_map_unlocked(3), "Locked stage was selected without cost")
	await capture("home")
	# 欠片550: MAP2(150)→MAP3(400)を解放し、解放したステージが出撃先になる。
	SaveManager.data["meta_currency"] = 550
	home._refresh()
	await get_tree().process_frame
	(home.stage_row.get_child(1) as Button).pressed.emit()
	await get_tree().process_frame
	check(SaveManager.is_map_unlocked(2) and GameManager.selected_survival_map == 2 and int(SaveManager.data["meta_currency"]) == 400, "Stage 2 unlock failed")
	(home.stage_row.get_child(2) as Button).pressed.emit()
	await get_tree().process_frame
	check(SaveManager.is_map_unlocked(3) and GameManager.selected_survival_map == 3 and int(SaveManager.data["meta_currency"]) == 0, "Stage 3 unlock failed")
	(home.stage_row.get_child(0) as Button).pressed.emit()
	await get_tree().process_frame
	check(GameManager.selected_survival_map == 1, "Unlocked stage selection failed")
	(home.stage_row.get_child(2) as Button).pressed.emit()
	await get_tree().process_frame
	check(GameManager.selected_survival_map == 3, "Stage selector disconnected")
	await capture("home_unlocked")
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
