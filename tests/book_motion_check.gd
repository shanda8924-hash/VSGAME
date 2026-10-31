extends Node
var OUT := "res://artifacts/book_motion_v2"
var failures: Array[String] = []
var timeline: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if "--touch-preview" in OS.get_cmdline_user_args(): OUT += "/mobile"
	SaveManager.begin_ephemeral_session()
	get_tree().create_timer(45, true).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_check(AudioServer.is_bus_mute(0) and AudioServer.get_driver_name() == "Dummy", "Audio must be silent")
	GameManager.selected_character_id = "swordsman"
	var game := preload("res://scenes/game.tscn").instantiate()
	game.tree_entered.connect(func(): get_tree().current_scene = game)
	get_tree().root.add_child(game)
	var controller := game.get_node("MapRunController") as MapRunController
	while not controller._active: await _frames(1)
	var menu := game.get_node("PauseMenu") as PauseMenu
	menu._active_tab = "talent"
	menu._open()
	var book = menu.talent_book._intro
	var prior := 0.0
	for index in 3:
		_check(book.page_angle(-1, index) == 0.0 and is_equal_approx(book.page_angle(3, index), PI), "Pages must turn right to left")
	for i in 121:
		var t: float = book.phase
		var angle: float = book.cover_angle(t)
		_check(angle + .00001 >= prior, "Cover turned backwards")
		prior = angle
		_check(book._project(0, 0, angle, false).is_equal_approx(Vector2(0, -90)), "Spine moved during opening")
		_check(menu.talent_book.canvas.get_parent() == menu.talent_book._ink_viewport or t >= book.DURATION, "Interactive controls returned before pages settled")
		var pages := []
		for index in 3: pages.append(book.page_angle(t, index))
		timeline.append({"frame":i,"phase":t,"cover":angle,"pages":pages,"diagramVisible":menu.talent_book.canvas.visible})
		if i % 2 == 0 and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OUT+"/frame_%03d.png" % i)
		await _frames(1)
	_check(not menu.talent_book.opening and menu.talent_book.canvas.visible and book.visible,"Open book must stay beneath the talent writing")
	_check(GameManager.active_modal_count == 1 and get_tree().paused, "Talents did not retain the pause modal")
	menu._close()
	_check(GameManager.active_modal_count == 0 and not get_tree().paused,"Closing did not resume combat")
	for count in [10, 40, 75]:
		menu._open()
		await _frames(count)
		menu._close()
		await _frames(115)
		_check(not menu.talent_book.opening and not book.visible and GameManager.active_modal_count == 0,"Interrupted cover/page animation leaked a modal")
	menu._open()
	await _frames(115)
	_check(menu.talent_book.canvas.visible and not menu.talent_book.opening,"Reopening after interruption failed")
	menu._close()
	var report := {"failures":failures,"muted":AudioServer.is_bus_mute(0),"driver":AudioServer.get_driver_name(),"timeline":timeline,"pages":3,"hinge":"fixed-left-spine","direction":"right-to-left"}
	FileAccess.open(OUT+"/check.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	var cleanup := preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	cleanup.begin(0 if failures.is_empty() else 1,"BOOK_MOTION_V2 failures=%d fixed_spine=true curved_pages=3 muted=true" % failures.size())
