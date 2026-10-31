extends RefCounted
## MAP1 loads one readable battle room at a time, not a whole distant maze.
const ROLES := ["入口の広間", "崩れた回廊", "石柱の広間", "強敵の前室", "ボスの祭室"]

static func generate(depth: int, ordinal: int, seed_value: int, survival: bool = false) -> DungeonMap:
	if survival:
		var field := DungeonMap.new(96, 96)
		field.rooms.append(Rect2i(Vector2i(-48, -48), Vector2i(96, 96)))
		for y in range(-48, 48):
			for x in range(-48, 48): field.set_floor(Vector2i(x, y), true)
		field.spawn_point = Vector2i.ZERO
		field.boss_room_index = 0
		field.set_meta("floor_only", true)
		field.set_meta("isolated_room", true)
		field.set_meta("survival_arena", true)
		field.set_meta("survival_layout", true)
		field.set_meta("global_depth", depth)
		return field
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + depth * 701 + ordinal * 131
	var boss := ordinal >= 4
	var size := Vector2i(36, 28) if survival else (Vector2i(24, 18) if boss else Vector2i(22 + rng.randi_range(0, 1) * 2, 16))
	var map := DungeonMap.new(size.x + 8, size.y + 8)
	var room := Rect2i(-size / 2, size)
	map.rooms.append(room)
	map.boss_room_index = 0 if boss or survival else -1
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			map.set_floor(Vector2i(x, y), true)
	# Keep a five-cell central lane; cover changes flanking without trapping actors.
	var mirror := -1 if rng.randf() < 0.5 else 1
	var blocks: Array[Rect2i] = []
	if ordinal == 1:
		blocks = [Rect2i(Vector2i(-size.x / 2, -2), Vector2i(4, 4)), Rect2i(Vector2i(size.x / 2 - 4, -6), Vector2i(4, 3))]
	elif ordinal == 2:
		blocks = [Rect2i(Vector2i(-6, -2 * mirror), Vector2i(2, 2)), Rect2i(Vector2i(4, mirror), Vector2i(2, 2))]
	elif ordinal == 3:
		blocks = [Rect2i(Vector2i(-size.x / 2, -5), Vector2i(4, 3)), Rect2i(Vector2i(size.x / 2 - 4, 2), Vector2i(4, 3))]
	for block in blocks:
		if mirror < 0:
			block.position.x = -block.end.x
		for y in range(block.position.y, block.end.y):
			for x in range(block.position.x, block.end.x):
				map.mark_terrain_obstacle(Vector2i(x, y))
	map.spawn_point = Vector2i(0, 3) if survival else Vector2i(0, room.end.y - 3)
	var reserved := {}
	for cell in map.get_floor_cells():
		if abs(cell.x) <= 2 or cell.distance_to(map.spawn_point) < 4 or cell.distance_to(Vector2i(-4, 3)) < 3:
			reserved[cell] = true
	map.set_meta("exploration_reserved", reserved)
	map.set_meta("isolated_room", true)
	map.set_meta("survival_arena", survival)
	map.set_meta("survival_layout", survival)
	map.set_meta("room_ordinal", ordinal)
	map.set_meta("room_role", ROLES[mini(ordinal, 4)])
	map.set_meta("room_seed", seed_value)
	map.set_meta("global_depth", depth)
	return map
