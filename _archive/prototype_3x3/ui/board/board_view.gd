extends Control
class_name BoardView
## 3×3盤面の表示と操作。マスをタップでホールド、spin() で回す。
## 回転は列ごとに左から順に止まり、止まったあと揃ったラインを1本ずつ光らせる。
## ルールは BoardModel が持ち、ここは見せ方だけ。

signal hold_toggled(index: int, accepted: bool)
signal spin_finished(lines: Array)

const CELL := 168.0
const GAP := 14.0
const PANEL_COLOR := Color("1b2030")
const CELL_COLOR := Color("2a3148")
const CELL_HELD_COLOR := Color("3b4a2e")
const HELD_BORDER := Color("b8e06a")
const BORDER := Color("4a5578")
const LINE_COLOR := Color("fff2b0")

var model: BoardModel
var spinning := false
var _elapsed := 0.0
var _roll_timer := 0.0
var _rolling: Array[bool] = []
var _shown: Array[int] = []
var _stop_times: Array = [0.35, 0.55, 0.75]
var _roll_interval := 0.05
var _flash_seconds := 0.22
var _lines: Array[Dictionary] = []
var _flash_index := -1
var _flash_timer := 0.0
var _pop: Array[float] = []
var _denied := -1
var _denied_timer := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2.ONE * board_side()
	mouse_filter = Control.MOUSE_FILTER_STOP

func board_side() -> float:
	return CELL * 3.0 + GAP * 4.0

func bind(board: BoardModel) -> void:
	model = board
	_stop_times = board.config.get("reel_stop_seconds", _stop_times)
	_roll_interval = float(board.config.get("roll_interval_seconds", _roll_interval))
	_flash_seconds = float(board.config.get("line_flash_seconds", _flash_seconds))
	_shown = board.cells.duplicate()
	_rolling.resize(BoardModel.CELL_COUNT)
	_rolling.fill(false)
	_pop.resize(BoardModel.CELL_COUNT)
	_pop.fill(0.0)
	_lines = board.matched_lines()
	queue_redraw()

func cell_rect(index: int) -> Rect2:
	var column := index % 3
	var row := index / 3
	return Rect2(Vector2(GAP + column * (CELL + GAP), GAP + row * (CELL + GAP)), Vector2(CELL, CELL))

func cell_at(point: Vector2) -> int:
	for index in BoardModel.CELL_COUNT:
		if cell_rect(index).has_point(point):
			return index
	return -1

func _gui_input(event: InputEvent) -> void:
	var pressed := false
	var point := Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed = true
		point = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pressed = true
		point = event.position
	if pressed:
		tap_cell(cell_at(point))
		accept_event()

## マスをタップしたときの処理（回転中は受け付けない）。
func tap_cell(index: int) -> void:
	if model == null or spinning or index < 0:
		return
	var accepted := model.toggle_hold(index)
	if not accepted:
		_denied = index
		_denied_timer = 0.3
	hold_toggled.emit(index, accepted)
	queue_redraw()

## 回す。結果は先に BoardModel で決まり、表示は列ごとに順に止まる。
func spin() -> bool:
	if model == null or spinning:
		return false
	var changed := model.spin()
	spinning = true
	_elapsed = 0.0
	_roll_timer = 0.0
	_flash_index = -1
	_lines = []
	_rolling.fill(false)
	for index in changed:
		_rolling[index] = true
	set_process(true)
	queue_redraw()
	return true

func _process(delta: float) -> void:
	for index in _pop.size():
		_pop[index] = maxf(_pop[index] - delta * 4.0, 0.0)
	if _denied_timer > 0.0:
		_denied_timer = maxf(_denied_timer - delta, 0.0)
	if not spinning:
		queue_redraw()
		return
	_elapsed += delta
	var still_rolling := false
	for index in BoardModel.CELL_COUNT:
		if not _rolling[index]:
			continue
		if _elapsed >= float(_stop_times[index % 3]):
			_rolling[index] = false
			_shown[index] = model.cells[index]
			_pop[index] = 1.0
		else:
			still_rolling = true
	if still_rolling:
		_roll_timer -= delta
		if _roll_timer <= 0.0:
			_roll_timer = _roll_interval
			for index in BoardModel.CELL_COUNT:
				if _rolling[index]:
					_shown[index] = randi() % maxi(model.symbols.size(), 1)
	elif _flash_index < 0 and _lines.is_empty():
		_lines = model.matched_lines()
		_flash_index = 0
		_flash_timer = _flash_seconds
		_pulse_line()
		if _lines.is_empty():
			_finish()
	else:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash_index += 1
			_flash_timer = _flash_seconds
			if _flash_index >= _lines.size():
				_finish()
			else:
				_pulse_line()
	queue_redraw()

func _pulse_line() -> void:
	if _flash_index >= 0 and _flash_index < _lines.size():
		for index in _lines[_flash_index].cells:
			_pop[index] = 1.0

func _finish() -> void:
	spinning = false
	_flash_index = -1
	_shown = model.cells.duplicate()
	spin_finished.emit(_lines)

func _draw() -> void:
	if model == null:
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2.ONE * board_side()), PANEL_COLOR)
	draw_rect(Rect2(Vector2.ZERO, Vector2.ONE * board_side()), BORDER, false, 4.0)
	for index in BoardModel.CELL_COUNT:
		var rect := cell_rect(index).grow(_pop[index] * 8.0)
		var is_held: bool = model.held[index]
		draw_rect(rect, CELL_HELD_COLOR if is_held else CELL_COLOR)
		if _rolling[index]:
			draw_rect(rect, Color(1, 1, 1, 0.05))
		var data := model.symbol_data(_shown[index])
		_draw_symbol(rect.get_center(), CELL * 0.3 * (1.0 + _pop[index] * 0.15), String(data.get("shape", "circle")), Color(String(data.get("color", "ffffff"))), 0.55 if _rolling[index] else 1.0)
		if is_held:
			draw_rect(rect, HELD_BORDER, false, 5.0)
			draw_string(get_theme_default_font(), rect.position + Vector2(10, 26), "HOLD", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, HELD_BORDER)
		else:
			draw_rect(rect, BORDER, false, 2.0)
		if index == _denied and _denied_timer > 0.0:
			draw_rect(rect, Color(1.0, 0.35, 0.3, _denied_timer / 0.3), false, 6.0)
	# 揃ったライン：回転中は光らせている1本まで、止まったあとは全部。
	var visible_lines := _lines.size() if not spinning else _flash_index + 1
	for line_number in mini(visible_lines, _lines.size()):
		var line_cells: Array = _lines[line_number].cells
		var from := cell_rect(line_cells[0]).get_center()
		var to := cell_rect(line_cells[2]).get_center()
		var strong := spinning and line_number == _flash_index
		draw_line(from, to, Color(LINE_COLOR, 0.95 if strong else 0.55), 14.0 if strong else 8.0)

func _draw_symbol(center: Vector2, radius: float, shape: String, color: Color, alpha: float) -> void:
	var tint := Color(color, alpha)
	match shape:
		"circle":
			draw_circle(center, radius, tint)
		"square":
			draw_rect(Rect2(center - Vector2.ONE * radius * 0.85, Vector2.ONE * radius * 1.7), tint)
		"triangle":
			draw_colored_polygon(PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius, radius * 0.85), center + Vector2(-radius, radius * 0.85)]), tint)
		"diamond":
			draw_colored_polygon(PackedVector2Array([center + Vector2(0, -radius * 1.1), center + Vector2(radius * 0.8, 0), center + Vector2(0, radius * 1.1), center + Vector2(-radius * 0.8, 0)]), tint)
		"star":
			var points := PackedVector2Array()
			for step in 10:
				var length := radius * (1.1 if step % 2 == 0 else 0.48)
				points.append(center + Vector2.from_angle(-PI * 0.5 + step * PI / 5.0) * length)
			draw_colored_polygon(points, tint)
		_:
			var arm := radius * 0.36
			draw_rect(Rect2(center - Vector2(arm, radius), Vector2(arm * 2.0, radius * 2.0)), tint)
			draw_rect(Rect2(center - Vector2(radius, arm), Vector2(radius * 2.0, arm * 2.0)), tint)
