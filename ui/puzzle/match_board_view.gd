extends Control
class_name MatchBoardView
## パズル盤の表示と操作。ルールは MatchBoard が持ち、ここは見せ方と入力だけ。
## マスは粗いドットのアイコン（tools/pixel_icons）。職業のマスはキャラクターの絵ではなく、その職業を象徴する道具（CharacterData.icon_path）。
## 操作：マスを隣へドラッグ（スワイプ）、またはマスをタップしてから隣のマスをタップ。
## 流れ：入れ替え → 揃った並びが光って消える → 上のマスが落ちる → 揃えば連鎖。全部終わると resolved を出す。

signal groups_cleared(groups: Array, chain: int)
signal swap_rejected(a: int, b: int)
signal reshuffled()
signal resolved(chain: int)

const PANEL_COLOR := Color("151a28")
const BORDER := Color("4a5578")
const SELECT_COLOR := Color("fff2b0")

var model: MatchBoard
var busy := false
var _tile := 88.0
var _gap := 4.0
var _swap_seconds := 0.12
var _flash_seconds := 0.2
var _fall_speed := 1500.0
var _display: Array[int] = []
var _offsets: Array[Vector2] = []
var _flash := {}
var _selected := -1
var _press_cell := -1
var _press_position := Vector2.ZERO
var _denied := {}
var _denied_timer := 0.0
## 種類の番号 → アイコン画像（職業のマスは、その職業を象徴する道具）。
var _icons := {}
var _tile_color := Color("bdb6ae")
var _tile_edge_color := Color("8f8880")

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP

func bind(board: MatchBoard) -> void:
	model = board
	_tile = float(board.config.get("tile_size", 88))
	_gap = float(board.config.get("tile_gap", 4))
	_swap_seconds = float(board.config.get("swap_seconds", 0.12))
	_flash_seconds = float(board.config.get("clear_flash_seconds", 0.2))
	_fall_speed = float(board.config.get("fall_speed", 1500))
	_tile_color = Color(String(board.config.get("tile_color", "bdb6ae")))
	_tile_edge_color = Color(String(board.config.get("tile_edge_color", "8f8880")))
	_display = board.grid.duplicate()
	_offsets.resize(board.cell_count())
	_offsets.fill(Vector2.ZERO)
	_flash.clear()
	_selected = -1
	_icons.clear()
	for kind in board.kinds.size():
		var data := board.kind_data(kind)
		var path := String(data.get("icon", ""))
		if String(data.get("type", "")) == "unit":
			var character: CharacterData = DataLoader.characters.get(String(data.get("character", "")))
			path = character.icon_path if character else ""
		if ResourceLoader.exists(path):
			_icons[kind] = load(path) as Texture2D
	custom_minimum_size = board_size()
	queue_redraw()

func pitch() -> float:
	return _tile + _gap

func board_size() -> Vector2:
	if model == null:
		return Vector2.ZERO
	return Vector2(model.width, model.height) * pitch() + Vector2.ONE * _gap

func cell_rect(index: int) -> Rect2:
	return Rect2(Vector2(_gap + (index % model.width) * pitch(), _gap + (index / model.width) * pitch()), Vector2.ONE * _tile)

## 種類 kind のマスに使っているアイコン画像。
func icon_for(kind: int) -> Texture2D:
	return _icons.get(kind)

func cell_at(point: Vector2) -> int:
	if model == null:
		return -1
	var x := int(floor((point.x - _gap * 0.5) / pitch()))
	var y := int(floor((point.y - _gap * 0.5) / pitch()))
	if x < 0 or y < 0 or x >= model.width or y >= model.height:
		return -1
	return model.index_of(x, y)

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_press_cell = cell_at(event.position)
		_press_position = event.position
	elif _press_cell >= 0:
		var delta: Vector2 = event.position - _press_position
		var from := _press_cell
		_press_cell = -1
		if delta.length() > _tile * 0.3:
			# スワイプ：動かした向きの隣と入れ替える
			var step := Vector2i(signi(int(delta.x)), 0) if absf(delta.x) > absf(delta.y) else Vector2i(0, signi(int(delta.y)))
			var x := from % model.width + step.x
			var y := from / model.width + step.y
			_selected = -1
			if x >= 0 and y >= 0 and x < model.width and y < model.height:
				request_swap(from, model.index_of(x, y))
		elif _selected >= 0 and model.are_adjacent(_selected, from):
			var first := _selected
			_selected = -1
			request_swap(first, from)
		else:
			_selected = -1 if _selected == from else from
		queue_redraw()
	accept_event()

## a と b を入れ替えて、揃いと連鎖を最後まで進める。揃わない入れ替えは弾いて false。
func request_swap(a: int, b: int) -> bool:
	if model == null or busy:
		return false
	if not model.swap(a, b):
		_denied = {a: true, b: true}
		_denied_timer = 0.25
		swap_rejected.emit(a, b)
		queue_redraw()
		return false
	busy = true
	_display = model.grid.duplicate()
	var shift := cell_rect(b).position - cell_rect(a).position
	_offsets[a] = shift
	_offsets[b] = -shift
	await _settle(shift.length() / maxf(_swap_seconds, 0.01))
	var chain := 0
	while true:
		var before: Array[int] = model.grid.duplicate()
		var step := model.resolve_step()
		if step.is_empty():
			break
		chain += 1
		_display = before
		_flash.clear()
		for cell in step.cleared:
			_flash[cell] = true
		queue_redraw()
		await get_tree().create_timer(_flash_seconds).timeout
		_flash.clear()
		groups_cleared.emit(step.groups, chain)
		_display = model.grid.duplicate()
		var drop: Array = step.drop
		for index in model.cell_count():
			_offsets[index] = Vector2(0, -float(drop[index]) * pitch())
		await _settle(_fall_speed)
	if not model.has_moves():
		model.reshuffle()
		_display = model.grid.duplicate()
		reshuffled.emit()
	busy = false
	queue_redraw()
	resolved.emit(chain)
	return true

var _settle_speed := 1500.0

func _settle(speed: float) -> void:
	_settle_speed = speed
	while true:
		var moving := false
		for offset in _offsets:
			if offset != Vector2.ZERO:
				moving = true
				break
		if not moving:
			return
		await get_tree().process_frame

func _process(delta: float) -> void:
	var changed := false
	for index in _offsets.size():
		if _offsets[index] != Vector2.ZERO:
			_offsets[index] = _offsets[index].move_toward(Vector2.ZERO, _settle_speed * delta)
			changed = true
	if _denied_timer > 0.0:
		_denied_timer = maxf(_denied_timer - delta, 0.0)
		changed = true
	if changed or not _flash.is_empty():
		queue_redraw()

func _draw() -> void:
	if model == null:
		return
	var area := Rect2(Vector2.ZERO, board_size())
	draw_rect(area, PANEL_COLOR)
	for index in model.cell_count():
		var kind := _display[index]
		if kind < 0:
			continue
		var rect := cell_rect(index)
		rect.position += _offsets[index]
		if rect.end.y <= 0.0:
			continue
		var data := model.kind_data(kind)
		var flashing := _flash.has(index)
		if flashing:
			rect = rect.grow(5.0)
		draw_rect(rect, _tile_color)
		draw_rect(rect, _tile_edge_color, false, 3.0)
		if _icons.has(kind) and _icons[kind] != null:
			# 16pxの絵を整数倍で拡大する（ドットをにじませない）。
			var texture: Texture2D = _icons[kind]
			var factor := maxf(floorf(rect.size.x * 0.95 / maxf(texture.get_width(), 1.0)), 1.0)
			var size := texture.get_size() * factor
			draw_texture_rect(texture, Rect2((rect.get_center() - size * 0.5).round(), size), false)
		if flashing:
			draw_rect(rect, Color(1, 1, 1, 0.55))
		if index == _selected:
			draw_rect(rect, SELECT_COLOR, false, 5.0)
		if _denied_timer > 0.0 and _denied.has(index):
			draw_rect(rect, Color(1.0, 0.35, 0.3, _denied_timer / 0.25), false, 6.0)
	draw_rect(area, BORDER, false, 4.0)
