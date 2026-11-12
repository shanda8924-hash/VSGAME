extends Node
## 盤面の試作の検査（実際の画面を生成し、クリックとボタンで操作する）。
## ルール：ライン判定8本、ホールドの上限、回すとホールド以外だけ引き直す、重みに沿った抽選。
## 画面：マスのクリックでホールド、回転中は操作を受け付けない、8回で1プレイが終わり「もう一度」で始め直す。
## Godot --headless --path . res://tests/board_prototype_check.tscn
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func click(view: BoardView, index: int) -> void:
	var point := view.get_global_transform_with_canvas() * view.cell_rect(index).get_center()
	point = get_viewport().get_stretch_transform() * point
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		Input.parse_input_event(event)
		await get_tree().process_frame
	await get_tree().process_frame

func _run() -> void:
	# --- ルール（BoardModel）
	var model := BoardModel.new(12345)
	check(model.symbols.size() >= 5 and model.cells.size() == 9, "config did not load symbols / cells")
	model.cells.assign([0, 0, 0, 1, 2, 3, 4, 5, 1])
	var lines := model.matched_lines()
	check(lines.size() == 1 and int(lines[0].line) == 0 and int(lines[0].symbol) == 0, "top row not detected as the only line")
	model.cells.assign([1, 0, 2, 0, 1, 0, 2, 0, 1])
	check(model.matched_lines().size() == 1 and int(model.matched_lines()[0].line) == 6, "diagonal not detected")
	model.cells.assign([2, 0, 1, 2, 1, 0, 2, 1, 1])
	check(model.matched_lines().size() == 1 and int(model.matched_lines()[0].line) == 3, "left column not detected")
	model.cells.assign([3, 3, 3, 3, 3, 3, 3, 3, 3])
	check(model.matched_lines().size() == 8, "full board is not 8 lines")
	model.cells.assign([0, 1, 2, 3, 4, 5, 0, 1, 2])
	check(model.matched_lines().is_empty(), "false line on a mixed board")
	for index in model.max_holds:
		check(model.toggle_hold(index), "hold %d rejected below the cap" % index)
	check(not model.toggle_hold(8) and model.held_count() == model.max_holds, "hold cap is not enforced")
	check(model.toggle_hold(0) and model.held_count() == model.max_holds - 1, "releasing a hold failed")
	model.toggle_hold(0)
	var before := model.cells.duplicate()
	var rerolled := {}
	for i in 40:
		var changed := model.spin()
		check(changed.size() == 9 - model.max_holds, "spin rerolled the wrong number of cells")
		for index in 9:
			if model.held[index]:
				check(model.cells[index] == before[index], "held cell %d changed on spin" % index)
			elif model.cells[index] != before[index]:
				rerolled[index] = true
	check(rerolled.size() == 9 - model.max_holds, "some unheld cells never change")
	check(model.held_count() == model.max_holds, "holds did not persist across spins")
	var counts := {}
	for i in 6000:
		var symbol := model.roll_symbol()
		counts[symbol] = int(counts.get(symbol, 0)) + 1
	for symbol in model.symbols.size():
		var share := float(counts.get(symbol, 0)) / 6000.0
		check(absf(share - 1.0 / model.symbols.size()) < 0.03, "symbol %d share %.3f is off its weight" % [symbol, share])
	# --- 画面（起動シーン）
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/board_prototype.tscn", "run scene is not the board prototype")
	var screen := (load("res://scenes/board_prototype.tscn") as PackedScene).instantiate()
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	var view := screen.board_view as BoardView
	var button := screen.spin_button as Button
	check(get_viewport().get_visible_rect().encloses(view.get_global_rect()) and get_viewport().get_visible_rect().encloses(button.get_global_rect()), "board or spin button is off screen")
	await click(view, 4)
	check(screen.model.held[4], "clicking a cell does not hold it")
	await click(view, 4)
	check(not screen.model.held[4], "clicking a held cell does not release it")
	for index in [0, 1, 2, 3]:
		await click(view, index)
	await click(view, 8)
	check(screen.model.held_count() == screen.model.max_holds and not screen.model.held[8], "clicks can exceed the hold cap")
	check(screen.hold_label.text.contains("%d / %d" % [screen.model.max_holds, screen.model.max_holds]), "hold counter not shown: " + screen.hold_label.text)
	var kept: Array = [screen.model.cells[0], screen.model.cells[1], screen.model.cells[2], screen.model.cells[3]]
	var finished: Array = []
	view.spin_finished.connect(func(result: Array): finished.append(result.size()))
	button.pressed.emit()
	await get_tree().process_frame
	check(view.spinning and screen.spins_done == 1 and button.disabled, "spin did not start from the button")
	button.pressed.emit()
	await click(view, 8)
	check(screen.spins_done == 1 and not screen.model.held[8], "input is accepted while the board is spinning")
	await view.spin_finished
	await get_tree().process_frame
	check(not view.spinning and not button.disabled and finished.size() == 1, "spin never finished")
	check([screen.model.cells[0], screen.model.cells[1], screen.model.cells[2], screen.model.cells[3]] == kept, "held cells changed in the real spin")
	check(finished[0] == screen.model.matched_lines().size() and screen.total_lines == finished[0], "reported lines disagree with the board")
	# 強制的に全マスを揃えて「揃った」表示を確かめる
	for index in 9:
		if screen.model.held[index]: screen.model.toggle_hold(index)
	for index in [0, 1, 2, 4]:
		screen.model.toggle_hold(index)
	screen.model.cells.assign([5, 5, 5, 0, 5, 1, 2, 3, 4])
	button.pressed.emit()
	await view.spin_finished
	await get_tree().process_frame
	check(finished[1] >= 1 and screen.result_label.text.contains("揃った"), "a guaranteed line is not announced: " + screen.result_label.text)
	var guard := 0
	while not screen.run_finished and guard < 20:
		guard += 1
		button.pressed.emit()
		await view.spin_finished
		await get_tree().process_frame
	check(screen.run_finished and screen.spins_done == screen.spins_per_run and screen.spins_per_run == 8, "run does not end after 8 spins (%d)" % screen.spins_done)
	check(button.text == "もう一度" and screen.result_label.text.contains("合計"), "end of run is not shown")
	button.pressed.emit()
	await get_tree().process_frame
	check(not screen.run_finished and screen.spins_done == 0 and screen.total_lines == 0 and screen.model.held_count() == 0, "restart does not reset the run")
	print("BOARD_PROTOTYPE_CHECK failures=%d" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
