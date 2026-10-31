extends Node2D
## ComfyUI-authored surfaces rendered over the unchanged collision grid.
var dungeon: DungeonMap
var cells: Array[Vector2i] = []
var surface_texture: Texture2D
var wall_texture: Texture2D
var theme := 1
var _actor: Player

func configure(map: DungeonMap, rendered_cells: Array[Vector2i], map_theme: int) -> void:
	dungeon = map
	cells = rendered_cells
	theme = map_theme
	surface_texture = load("res://assets/visuals/ember_v5/map%d_floor.png" % theme)
	wall_texture = load("res://assets/visuals/ember_v5/map%d_wall.png" % theme)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = -90
	set_process(map.get_meta("floor_only", false))
	if map.get_meta("floor_only", false):
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_actor = get_tree().get_first_node_in_group("player") as Player
	queue_redraw()

func _walk_surface(cell: Vector2i) -> bool:
	return dungeon.is_floor(cell) or dungeon.get_meta("scenic_landmark_cells", {}).has(cell)

func _process(_delta: float) -> void:
	if is_instance_valid(_actor):
		# Snap to the texture period so re-centering never shifts the floor artwork.
		position = (_actor.camera.get_screen_center_position() / 256.0).floor() * 256.0

func _draw() -> void:
	if dungeon.get_meta("floor_only", false) and surface_texture:
		draw_set_transform(Vector2.ZERO, 0, Vector2(2, 2))
		draw_texture_rect(surface_texture, Rect2(-2048, -2048, 4096, 4096), true, Color(.83,.83,.86))
		return
	if not surface_texture or not wall_texture: return
	for cell in cells:
		var rect := Rect2(Vector2(cell)*32,Vector2(32,32))
		var floor_cell := _walk_surface(cell)
		var sample := Rect2(Vector2(posmod(cell.x,8),posmod(cell.y,8))*16,Vector2(16,16))
		if floor_cell:
			draw_texture_rect_region(surface_texture,rect,sample,Color(.83,.83,.86))
			if not _walk_surface(cell+Vector2i.UP):
				draw_rect(Rect2(rect.position,Vector2(32,4)),Color(0,0,0,.32))
		else:
			var face := _walk_surface(cell+Vector2i.DOWN) or _walk_surface(cell+Vector2i(0,2))
			var shade := Color(.94,.94,.98) if face else Color(.57,.59,.65)
			draw_texture_rect_region(wall_texture,rect,sample,shade)
			if _walk_surface(cell+Vector2i.UP):
				draw_rect(Rect2(rect.position,Vector2(32,2)),Color(.45,.46,.50,.7))
			if _walk_surface(cell+Vector2i.DOWN):
				draw_rect(Rect2(rect.position+Vector2(0,28),Vector2(32,4)),Color(.025,.03,.04,.9))
			if _walk_surface(cell+Vector2i.LEFT):
				draw_rect(Rect2(rect.position,Vector2(3,32)),Color(.08,.085,.10,.8))
			if _walk_surface(cell+Vector2i.RIGHT):
				draw_rect(Rect2(rect.position+Vector2(29,0),Vector2(3,32)),Color(.025,.03,.04,.85))
