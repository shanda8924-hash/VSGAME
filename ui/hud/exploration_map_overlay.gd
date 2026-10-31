extends CanvasLayer
class_name ExplorationMapOverlay
## Discovered floor only. M is deliberately separate from inventory/talents.
var panel: Control
var map: DungeonMap
var actor: Player
var opened := false
var _font := preload("res://assets/fonts/MPLUS1p-Medium.ttf")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 35
	panel = Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.draw.connect(_draw_map)
	add_child(panel)
	panel.hide()
	add_to_group("map_overlay")
	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close_button.offset_left = -160
	close_button.offset_right = -32
	close_button.offset_top = 26
	close_button.offset_bottom = 90
	close_button.add_theme_font_size_override("font_size", 22)
	panel.add_child(close_button)
	PixelUIStyle.apply_button(close_button)
	close_button.pressed.connect(toggle_map)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode == KEY_M or (opened and event.physical_keycode == KEY_ESCAPE):
		toggle_map()
		get_viewport().set_input_as_handled()

func toggle_map() -> void:
	if not opened and (GameManager.active_modal_count > 0 or GameManager.run_state != GameManager.RunState.PLAYING):
		return
	opened = not opened
	panel.visible = opened
	if opened:
		GameManager.open_modal()
		panel.queue_redraw()
	else:
		GameManager.close_modal()

func _draw_map() -> void:
	if map==null or not is_instance_valid(actor): return
	var screen := panel.get_viewport_rect().size
	var fit := minf(1.0,minf(screen.x/740.0,screen.y/600.0))
	panel.draw_set_transform((screen-Vector2(720,580)*fit)/2,0,Vector2.ONE*fit)
	var box := Rect2(Vector2.ZERO,Vector2(720,580))
	panel.draw_rect(Rect2(-screen/fit,screen*3/fit),Color(0,0,0,0.65))
	panel.draw_rect(box,Color("091721"))
	panel.draw_rect(box,Color("b68b49"),false,2)
	panel.draw_string(_font,box.position+Vector2(28,38),"探索図",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color("f2e6cc"))
	panel.draw_string(_font,box.position+Vector2(490,38),"[M / Esc] 閉じる",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("adbac5"))
	if map.get_meta("floor_only", false):
		var area := Rect2(30, 68, 660, 420)
		panel.draw_rect(area, Color("38454d"))
		var center := area.get_center()
		var scale := 0.12
		for content in get_tree().get_nodes_in_group("map_content"):
			var point: Vector2 = center + (content.global_position - actor.global_position) * scale
			if not area.has_point(point): continue
			panel.draw_circle(point, 4, Color("d3a45b"))
			panel.draw_string(_font, point+Vector2(8, 5), "帰還" if content is MapLandmark else "宝箱", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("d9c8a5"))
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if not enemy.enemy_data is BossData: continue
			var point: Vector2 = center + (enemy.global_position - actor.global_position) * scale
			if area.has_point(point): panel.draw_circle(point, 6, Color("e87661"))
		panel.draw_circle(center, 5, Color("5be1d5"))
		panel.draw_string(_font, Vector2(30, 524), _objective_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("e6c887"))
		panel.draw_string(_font, Vector2(30, 554), "現在地の周辺を表示　／　壁・地形障害物なし", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("a8b5c0"))
		return
	var scale := minf(660.0/map.width,420.0/map.height)
	var origin := box.position+Vector2(30,68)+(Vector2(660,420)-Vector2(map.width,map.height)*scale)/2
	var explored: Dictionary = map.get_meta("explored_cells",{})
	for cell: Vector2i in explored:
		if not map.is_floor(cell): continue
		panel.draw_rect(Rect2(origin+Vector2(cell-map.get_min_coords())*scale,Vector2.ONE*(scale+0.3)),Color("506677"))
	if map.get_meta("survival_layout", false) or map.get_meta("isolated_room", false):
		for cell in map.get_floor_cells():
			panel.draw_rect(Rect2(origin+Vector2(cell-map.get_min_coords())*scale,Vector2.ONE*(scale+0.3)),Color("506677"))
		for room_id in ([0] if map.boss_room_index == 0 else [0, map.boss_room_index]):
			if room_id < 0: continue
			var c: Vector2i = map.rooms[room_id].get_center()
			var point := origin+Vector2(c-map.get_min_coords())*scale
			panel.draw_circle(point,4,Color("d3a45b"))
			panel.draw_string(_font,point+Vector2(7,5),"ボス" if room_id == map.boss_room_index else "入口",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("f2ddb5"))

	var visited: Dictionary = map.get_meta("visited_rooms",{})
	var roles: Array = map.get_meta("room_roles",[])
	for room_id: int in visited:
		var c: Vector2i = map.rooms[room_id].position+map.rooms[room_id].size/2
		var point := origin+Vector2(c-map.get_min_coords())*scale
		var role: String = roles[room_id]
		var label: String = {"entry":"入口","key_guard":"鍵","boss":"ボス","rest":"休息","cache":"宝箱","elite":"精鋭","landmark":"遺構"}.get(role,"")
		if label.is_empty(): continue
		panel.draw_circle(point,4,Color("d3a45b"))
		panel.draw_string(_font,point+Vector2(7,5),label,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("f2ddb5"))
	for content in get_tree().get_nodes_in_group("map_content"):
		if content is MapLandmark and content.kind in ["room_exit", "descent_stairs"]:
			var point := origin + Vector2(map.world_to_grid(content.global_position) - map.get_min_coords()) * scale
			panel.draw_rect(Rect2(point - Vector2(4, 4), Vector2(8, 8)), Color("d3a45b") if content.available else Color("8b94a0"))
			panel.draw_string(_font, point + Vector2(8, 5), "階段" if content.kind == "descent_stairs" else "出口", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("f2ddb5"))
	var here := origin+Vector2(map.world_to_grid(actor.global_position)-map.get_min_coords())*scale
	panel.draw_circle(here,5,Color("5be1d5"))
	var objective := _objective_text()
	panel.draw_string(_font,box.position+Vector2(30,524),objective,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("e6c887"))
	panel.draw_string(_font,box.position+Vector2(30,554),"青緑：現在地　／　金：出口・階段" if map.get_meta("survival_layout", false) or map.get_meta("isolated_room", false) else "青緑：現在地　／　探索した道だけを記録",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("a8b5c0"))

## Use the same objective as the live HUD; room floors do not have a key-search objective.
func _objective_text() -> String:
	var current := String(map.get_meta("objective_text", ""))
	if not current.is_empty():
		return current
	if map.get_meta("isolated_room", false):
		return "部屋 %d / 5　%s　敵を倒し、宝箱を開けて出口へ" % [int(map.get_meta("room_ordinal", 0)) + 1, String(map.get_meta("room_role", ""))]
	if map.get_meta("survival_layout", false):
		return "敵を倒してボス領域を解放"
	return "鍵を入手済み：ボス領域へ" if bool(map.get_meta("key_acquired", false)) else "封印の鍵を探す"
