extends Node
## パズルの試作の検査（実際の画面を生成し、ドラッグとタップで操作する）。
## ルール：最初から揃っていない、手がある、揃わない入れ替えと離れたマスは拒否、消えたら落ちて埋まる（列の順番は保つ）、報酬の数。
## 画面：スワイプとタップで入れ替え、弓兵を3つ揃えると弓兵が部屋に1体現れて待機する、強化を揃えると段階が上がる、
## 連鎖が終わると盤に揃いが残らない、処理中は入力を受け付けない、やり直しで初期化。
## Godot --headless --path . res://tests/puzzle_prototype_check.tscn
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func mouse(view: MatchBoardView, cell: int, pressed: bool) -> void:
	var point := get_viewport().get_stretch_transform() * (view.get_global_transform_with_canvas() * view.cell_rect(cell).get_center())
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame

## 揃いの無い下地（種類 = (x + 2y) mod 種類数）を作る。
func base_grid(board: MatchBoard) -> void:
	for index in board.cell_count():
		board.grid[index] = (index % board.width + 2 * (index / board.width)) % board.kinds.size()

func kind_index(board: MatchBoard, id: String) -> int:
	for kind in board.kinds.size():
		if String(board.kind_data(kind).get("id", "")) == id:
			return kind
	return -1

func _run() -> void:
	# --- ルール（MatchBoard）
	for seed_value in 30:
		var fresh := MatchBoard.new(seed_value)
		check(fresh.find_matches().is_empty() and fresh.has_moves(), "seed %d: initial board has matches or no moves" % seed_value)
	var board := MatchBoard.new(1)
	check(board.width == 8 and board.height == 8 and board.kinds.size() == 8, "config not loaded")
	base_grid(board)
	check(board.find_matches().is_empty(), "base pattern is not match-free")
	var archer := kind_index(board, "archer")
	var bottom := board.height - 1
	# 最下段に 弓兵・弓兵・(別)、その上に弓兵 → (2,6)と(2,7)を入れ替えると横に3つ
	var other := (archer + 3) % board.kinds.size()
	board.grid[board.index_of(0, bottom)] = archer
	board.grid[board.index_of(1, bottom)] = archer
	board.grid[board.index_of(2, bottom)] = other
	board.grid[board.index_of(2, bottom - 1)] = archer
	board.grid[board.index_of(3, bottom)] = (archer + 1) % board.kinds.size()
	board.grid[board.index_of(0, bottom - 1)] = (archer + 2) % board.kinds.size()
	board.grid[board.index_of(1, bottom - 1)] = (archer + 4) % board.kinds.size()
	check(board.find_matches().is_empty(), "test setup already has a match")
	var a := board.index_of(2, bottom - 1)
	var b := board.index_of(2, bottom)
	var snapshot := board.grid.duplicate()
	check(not board.swap(board.index_of(5, 0), board.index_of(6, 0)) and board.grid == snapshot, "a swap that matches nothing was accepted")
	check(not board.swap(a, board.index_of(4, bottom)) and board.grid == snapshot, "a non-adjacent swap was accepted")
	check(board.can_swap(a, b) and board.grid == snapshot, "can_swap changed the board or rejected a valid swap")
	check(board.swap(a, b), "valid swap rejected")
	var column_above: Array[int] = []
	for y in range(bottom - 1, -1, -1):
		column_above.append(board.grid[board.index_of(0, y)])
	var step := board.resolve_step()
	check(not step.is_empty() and step.groups.size() == 1 and int(step.groups[0].kind) == archer and step.groups[0].cells.size() == 3, "the three archers were not cleared as one group")
	check(board.reward_for(step.groups[0]) == 1 and board.reward_for({"cells": [0, 1, 2, 3]}) == 2 and board.reward_for({"cells": [0, 1, 2, 3, 4]}) == 3, "reward counts are wrong")
	check(not board.grid.has(MatchBoard.EMPTY), "board has holes after refill")
	for offset in column_above.size():
		check(board.grid[board.index_of(0, bottom - offset)] == column_above[offset], "column 0 did not fall in order (row offset %d)" % offset)
	check(int(step.drop[board.index_of(0, bottom)]) == 1 and int(step.drop[board.index_of(0, 0)]) == 1 and int(step.drop[board.index_of(5, 3)]) == 0, "drop distances are wrong")
	var guard := 0
	while not board.resolve_step().is_empty() and guard < 50:
		guard += 1
	check(board.find_matches().is_empty(), "cascade does not terminate")
	# --- 画面（起動シーン）
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/puzzle_prototype.tscn", "run scene is not the puzzle prototype")
	var screen := (load("res://scenes/puzzle_prototype.tscn") as PackedScene).instantiate()
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	var view := screen.board_view as MatchBoardView
	var visible_area := get_viewport().get_visible_rect()
	check(visible_area.encloses(view.get_global_rect()) and visible_area.encloses(screen.room_panel.get_global_rect()) and visible_area.encloses(screen.restart_button.get_global_rect()), "board, room or button is off screen")
	check(view.size.x >= view.board_size().x - 1.0 and view.size.y >= view.board_size().y - 1.0, "board view is smaller than the board")
	# 職業のマスは象徴の道具のアイコン（キャラクターの絵ではない）
	for kind in screen.model.kinds.size():
		var kind_data: Dictionary = screen.model.kind_data(kind)
		if String(kind_data.get("type", "")) == "unit":
			var character: CharacterData = DataLoader.characters[String(kind_data.character)]
			var icon := view.icon_for(kind)
			check(icon != null and icon.resource_path == character.icon_path and icon.resource_path.begins_with("res://assets/icons/class/"), "%s tile does not use its class icon" % character.id)
		else:
			var upgrade_icon := view.icon_for(kind)
			check(upgrade_icon != null and upgrade_icon.resource_path == String(kind_data.icon) and upgrade_icon.resource_path.begins_with("res://assets/icons/upgrade/"), "%s tile has no upgrade icon" % String(kind_data.id))
		check(view.icon_for(kind) != null and view.icon_for(kind).get_size() == Vector2(16, 16), "tile icon %d is not a 16px pixel icon" % kind)
	# 弓兵3つをスワイプで揃える
	var model := screen.model as MatchBoard
	base_grid(model)
	model.grid[model.index_of(0, bottom)] = archer
	model.grid[model.index_of(1, bottom)] = archer
	model.grid[model.index_of(2, bottom)] = other
	model.grid[model.index_of(2, bottom - 1)] = archer
	model.grid[model.index_of(3, bottom)] = (archer + 1) % model.kinds.size()
	model.grid[model.index_of(0, bottom - 1)] = (archer + 2) % model.kinds.size()
	model.grid[model.index_of(1, bottom - 1)] = (archer + 4) % model.kinds.size()
	view.bind(model)
	await get_tree().process_frame
	var cleared_groups: Array = []
	view.groups_cleared.connect(func(groups: Array, _chain: int): cleared_groups.append_array(groups))
	await mouse(view, model.index_of(2, bottom - 1), true)
	await mouse(view, model.index_of(2, bottom), false)
	check(view.busy, "swipe did not start a swap")
	var probe := model.find_move()
	await mouse(view, model.index_of(6, 2), true)
	await mouse(view, model.index_of(6, 3), false)
	check(screen.moves == 0, "input accepted while the board is resolving")
	if view.busy:
		await view.resolved
	await get_tree().process_frame
	check(not view.busy and screen.moves == 1 and model.find_matches().is_empty(), "board did not settle after the swap")
	var archer_rewards := 0
	for group in cleared_groups:
		if int(group.kind) == archer:
			archer_rewards += model.reward_for(group)
	check(archer_rewards >= 1 and int(screen.summoned.get("archer", 0)) == archer_rewards, "matching three archers did not summon an archer (%s)" % str(screen.summoned))
	var archers_in_room := 0
	for unit in screen.units:
		if unit.character_data and unit.character_data.id == "archer":
			archers_in_room += 1
			check(unit.animated_sprite.animation == &"idle" and unit.animated_sprite.is_playing(), "summoned archer is not idling")
			check(screen.room_panel.get_global_rect().has_point(unit.global_position), "summoned archer stands outside the room")
	check(archers_in_room == archer_rewards and screen.summon_label.text.contains("弓兵 ×%d" % archer_rewards), "room or label disagrees with the summon count: " + screen.summon_label.text)
	# 強化（攻撃）を縦に3つ、タップ2回で揃える
	var attack := kind_index(model, "attack")
	base_grid(model)
	var other2 := (attack + 3) % model.kinds.size()
	model.grid[model.index_of(4, 2)] = attack
	model.grid[model.index_of(4, 3)] = attack
	model.grid[model.index_of(4, 4)] = other2
	model.grid[model.index_of(5, 4)] = attack
	model.grid[model.index_of(4, 1)] = (attack + 1) % model.kinds.size()
	model.grid[model.index_of(4, 5)] = (attack + 2) % model.kinds.size()
	model.grid[model.index_of(3, 2)] = (attack + 4) % model.kinds.size()
	model.grid[model.index_of(5, 2)] = (attack + 5) % model.kinds.size()
	model.grid[model.index_of(3, 3)] = (attack + 5) % model.kinds.size()
	model.grid[model.index_of(5, 3)] = (attack + 4) % model.kinds.size()
	model.grid[model.index_of(6, 4)] = (attack + 1) % model.kinds.size()
	model.grid[model.index_of(5, 5)] = (attack + 5) % model.kinds.size()
	check(model.find_matches().is_empty() and model.can_swap(model.index_of(5, 4), model.index_of(4, 4)), "upgrade setup is not a clean one-move match")
	view.bind(model)
	cleared_groups.clear()
	for cell in [model.index_of(5, 4), model.index_of(4, 4)]:
		await mouse(view, cell, true)
		await mouse(view, cell, false)
	if view.busy:
		await view.resolved
	await get_tree().process_frame
	var attack_rewards := 0
	for group in cleared_groups:
		if int(group.kind) == attack:
			attack_rewards += model.reward_for(group)
	check(attack_rewards >= 1 and int(screen.upgrades.get("attack", 0)) == attack_rewards and screen.upgrade_label.text.contains("攻撃 Lv.%d" % attack_rewards), "matching three attack tiles did not raise the upgrade: " + screen.upgrade_label.text)
	check(screen.moves == 2, "tap-tap swap not counted as a move")
	# 揃わない入れ替えは弾く
	base_grid(model)
	view.bind(model)
	var rejected: Array = []
	view.swap_rejected.connect(func(x: int, y: int): rejected.append([x, y]))
	var moves_before: int = screen.moves
	var bad_a := -1
	for index in model.cell_count() - 1:
		if index % model.width < model.width - 1 and not model.can_swap(index, index + 1):
			bad_a = index
			break
	await mouse(view, bad_a, true)
	await mouse(view, bad_a + 1, false)
	await get_tree().process_frame
	check(rejected.size() == 1 and screen.moves == moves_before and not view.busy, "an invalid swipe was not rejected")
	# 自動で20手：毎回、盤に揃いが残らず、穴も無い
	screen.start(99)
	model = screen.model
	for turn in 20:
		var move := model.find_move()
		check(move.size() == 2, "no move available on turn %d" % turn)
		if move.size() != 2:
			break
		view.request_swap(move[0], move[1])
		if view.busy:
			await view.resolved
		check(model.find_matches().is_empty() and not model.grid.has(MatchBoard.EMPTY) and model.has_moves(), "board is not clean after turn %d" % turn)
	check(screen.moves == 20, "20 automatic moves were not all counted (%d)" % screen.moves)
	var total_units := 0
	for id in screen.summoned.keys():
		total_units += int(screen.summoned[id])
	check(screen.units.size() == mini(total_units, int(model.config.get("max_army", 20))) and screen.army.units.size() == screen.units.size(), "units in the room disagree with the summon total")
	screen.restart_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check(screen.moves == 0 and screen.summoned.is_empty() and screen.upgrades.is_empty() and screen.units.is_empty() and screen.units_root.get_child_count() == 0, "restart does not reset the prototype")
	print("PUZZLE_PROTOTYPE_CHECK failures=%d" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
