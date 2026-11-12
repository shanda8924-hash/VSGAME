extends RefCounted

## NEWの分割済み小物を、戦闘導線から外れた室内の端へ少数だけ配置する。
const PROPS := [
	{"path": "res://assets/tiles/imported_ruins/pixel_v3/Rock_shadow1_1.png", "kind": "rock", "scale": 2.0, "solid": true},
	{"path": "res://assets/tiles/imported_ruins/pixel_v3/Bones_shadow1_1.png", "kind": "bones", "scale": 2.0, "solid": false},
	{"path": "res://assets/tiles/imported_ruins/pixel_v3/Ruin_shadow1_3.png", "kind": "ruin", "scale": 2.0, "solid": true},
	{"path": "res://assets/tiles/imported_ruins/pixel_v3/Rock_shadow1_4.png", "kind": "rock", "scale": 2.0, "solid": true},
	{"path": "res://assets/tiles/imported_ruins/pixel_v3/Bones_shadow1_3.png", "kind": "bones", "scale": 2.0, "solid": false},
	{"path": "res://assets/tiles/imported_ruins/pixel_v3/Ruin_shadow1_5.png", "kind": "ruin", "scale": 2.0, "solid": true},
]

static func install(stage: StageEnvironment, map: DungeonMap, theme: int) -> int:
	var root := Node2D.new()
	root.name = "ImportedRuinProps"
	root.z_index = -43
	stage.add_child(root)
	var assets: Array[Dictionary] = []
	for data: Dictionary in PROPS:
		var texture := load(String(data.path)) as Texture2D
		if texture == null:
			continue
		var scale: float = data.scale
		var used := texture.get_image().get_used_rect()
		assets.append({"data": data, "texture": texture, "bounds": Rect2((Vector2(used.position) - texture.get_size() * 0.5) * scale, Vector2(used.size) * scale)})
	if assets.is_empty():
		return 0
	var reserved: Dictionary = map.get_meta("exploration_reserved", {})
	var candidates: Array[Dictionary] = []
	for room_index in range(map.rooms.size()):
		if room_index == map.boss_room_index:
			continue
		var room: Rect2i = map.rooms[room_index]
		for cell: Vector2i in map.get_spawn_cells(room.grow(-3)):
			if reserved.has(cell):
				continue
			var edge := mini(mini(cell.x - room.position.x, room.end.x - cell.x - 1), mini(cell.y - room.position.y, room.end.y - cell.y - 1))
			if edge <= 5:
				candidates.append({"cell": cell, "room": room_index})
	candidates.shuffle()
	var occupied: Array[Rect2] = []
	for child in stage._sprite_decorations.get_children():
		var sprite := child as AnimatedSprite2D
		if sprite == null or not sprite.visible or sprite.sprite_frames == null:
			continue
		var size := sprite.sprite_frames.get_frame_texture("default", 0).get_size()
		var origin := sprite.offset - size * 0.5 if sprite.centered else sprite.offset
		occupied.append(sprite.get_global_transform() * Rect2(origin, size))
	var room_counts := {}
	var positions: Array[Vector2] = []
	var placed := 0
	var isolated: bool = map.get_meta("isolated_room", false)
	var target := 3 if isolated and map.boss_room_index < 0 else mini(10, maxi(0, map.rooms.size() - 1) * 2)
	for candidate: Dictionary in candidates:
		if placed >= target:
			break
		var room_index: int = candidate.room
		if int(room_counts.get(room_index, 0)) >= (3 if isolated else 2):
			continue
		var asset: Dictionary = assets[placed % assets.size()]
		var data: Dictionary = asset.data
		var texture: Texture2D = asset.texture
		var scale: float = data.scale
		var bounds: Rect2 = asset.bounds
		var position := map.grid_to_world(candidate.cell) + Vector2(16, 16)
		var too_near := false
		for prior in positions:
			if prior.distance_to(position) < 88.0:
				too_near = true
				break
		if too_near or not stage._crystal_footprint_fits(map, position, bounds, occupied):
			continue
		var kind := String(data.kind)
		var sprite := Sprite2D.new()
		sprite.name = "%s%d" % [kind.capitalize(), placed]
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = position
		sprite.scale = Vector2.ONE * scale
		sprite.modulate = _tint(theme, kind)
		root.add_child(sprite)
		if bool(data.solid):
			_add_collision(root, position, bounds, placed)
		occupied.append(stage._sprite_decorations.get_global_transform() * Rect2(position + bounds.position, bounds.size))
		positions.append(position)
		room_counts[room_index] = int(room_counts.get(room_index, 0)) + 1
		placed += 1
	root.set_meta("placed_count", placed)
	return placed

static func _tint(theme: int, kind: String) -> Color:
	if kind == "ruin":
		return Color(1.35, 1.48, 1.62) if theme == 1 else Color(1.48, 1.34, 1.63) if theme == 2 else Color(1.54, 1.34, 1.2)
	if kind == "bones":
		return Color("aebbc5") if theme == 1 else Color("b3a4bb") if theme == 2 else Color("b4a99e")
	return Color("667788") if theme == 1 else Color("746b84") if theme == 2 else Color("777171")

static func _add_collision(root: Node2D, position: Vector2, bounds: Rect2, index: int) -> void:
	var body := StaticBody2D.new()
	body.name = "Solid%d" % index
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = position + Vector2(0, bounds.end.y - bounds.size.y * 0.28)
	var footprint := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(maxf(12.0, bounds.size.x * 0.72), maxf(10.0, bounds.size.y * 0.5))
	footprint.shape = shape
	body.add_child(footprint)
	root.add_child(body)
