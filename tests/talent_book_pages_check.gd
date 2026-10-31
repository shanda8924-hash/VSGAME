extends Node
var OUT := "res://artifacts/talent_book_pages_v3"
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
		for paper in [false, true]:
			for step in 11:
				for edge in [0.0, 1.0]:
					var local: Vector2 = book.size / 2 + book._project(step / 10.0, edge, angle, paper) * book.page_scale()
					_check(get_viewport().get_visible_rect().has_point(book.get_global_transform_with_canvas() * local), "Turning cover or page leaves the viewport")

		var pages := []
		for index in 3: pages.append(book.page_angle(t, index))
		timeline.append({"frame":i,"phase":t,"cover":angle,"pages":pages,"diagramVisible":menu.talent_book.canvas.visible})
		if i % 2 == 0 and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OUT+"/frame_%03d.png" % i)
		await _frames(1)
	_check(not menu.talent_book.opening and menu.talent_book.canvas.visible and book.visible and is_equal_approx(book.modulate.a,1.0),"Open book must remain under the talent writing")

	_check(book.get_index() < menu.talent_book.canvas.get_index(), "Page artwork must stay behind interactive content")
	var left := _page_bounds(book, true)
	var right := _page_bounds(book, false)
	_check(is_equal_approx(left.end.x, right.position.x), "Pages must share one spine")
	_check(left.size.x + right.size.x > menu.talent_book.size.x * .7, "The open book must be large enough to read")
	_check(get_viewport().get_visible_rect().encloses(left) and get_viewport().get_visible_rect().encloses(right), "Pages leave the viewport")
	for index in menu.talent_book.nodes.size():
		var button: Button = menu.talent_book.nodes[index]
		_check(left.encloses(button.get_global_rect()), "Talent seal leaves the left page")
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.pressed = true
		get_viewport().push_input(event, true)
		event = event.duplicate()
		event.pressed = false
		get_viewport().push_input(event, true)
		await _frames(2)
		_check(menu.talent_book.selected_index == index, "Book artwork blocks talent input")
		for child in menu.talent_book.detail.get_children():
			if child is Control: _check(right.encloses(child.get_global_rect()), "Detail leaves the right page: " + str(index) + "/" + child.name)
	menu.talent_book._select(0)
	await _capture("open_book")
	menu.talent_book._select(1)
	await _capture("selected_talent")
	menu.talent_book._select(4)
	await _capture("last_talent")
	menu.talent_book.nodes[1].grab_focus()
	await _frames(1)
	_check(menu.talent_book.selected_index == 1, "Keyboard focus does not update the right page")
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
	var report := {"failures":failures,"muted":AudioServer.is_bus_mute(0),"driver":AudioServer.get_driver_name(),"timeline":timeline,"pages":3,"persistentBook":book.phase >= book.DURATION,"largeSpread":true,"allNineTalentsClickable":true,"hinge":"fixed-left-spine","direction":"right-to-left"}
	FileAccess.open(OUT+"/check.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	var cleanup := preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	cleanup.begin(0 if failures.is_empty() else 1,"TALENT_BOOK_PAGES_V3 failures=%d persistent_book=true two_pages=true muted=true" % failures.size())

func _page_bounds(book: Control, left: bool) -> Rect2:
	var local: Rect2 = book.page_rect(left)
	var transform := book.get_global_transform_with_canvas()
	var start: Vector2 = transform * local.position
	return Rect2(start, transform * local.end - start)

func _capture(name: String) -> void:
	await _frames(3)
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "/" + name + ".png")
