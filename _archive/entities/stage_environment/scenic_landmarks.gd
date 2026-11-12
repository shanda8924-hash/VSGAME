extends RefCounted
## Architectural landmarks. Placement is stored on the map so rebuilding its view
## never consumes more floor or changes the selected rooms.
const SHEET := "res://assets/visuals/ember_v5/architecture.png"
const REGIONS := [Rect2(0, 0, 96, 91), Rect2(96, 0, 96, 85), Rect2(192, 0, 96, 97), Rect2(288, 0, 96, 85)]
const NAMES := ["紫晶採掘場", "結晶神殿", "古代溶鉱炉", "冷却水車"]

static func prepare(map: DungeonMap, theme: int) -> Array:
	if theme not in [2, 3]:
		return []
	if map.has_meta("scenic_landmarks"):
		return map.get_meta("scenic_landmarks")
	var entries: Array = []
	var blocked: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = str(map.rooms).hash()
	var candidates: Array = []
	for room_index in range(1, map.rooms.size()):
		if room_index == map.boss_room_index or room_index in map.elite_room_indices:
			continue
		var room: Rect2i = map.rooms[room_index]
		for x in range(room.position.x + 1, room.end.x - 6):
			var base := Rect2i(Vector2i(x, room.position.y), Vector2i(6, 2))
			var safe := true
			for dy in range(-4, 5):
				for dx in range(-1, 7):
					var cell := base.position + Vector2i(dx, dy)
					if not map.is_in_bounds(cell) or map.get_meta("exploration_reserved", {}).has(cell):
						safe = false
					elif dy < 0:
						if dx >= 0 and dx < 6 and map.is_floor(cell):
							safe = false
					elif not map.is_floor(cell) or Vector2(cell - map.spawn_point).length() < 6.0:
						safe = false
			if safe:
				candidates.append({"room": room_index, "footprint": base})
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Dictionary = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = swap
	var target := 2 if rng.randf() < 0.35 else 1
	for candidate: Dictionary in candidates:
		var base: Rect2i = candidate.footprint
		if not entries.is_empty():
			var previous: Rect2i = entries[0].footprint
			if candidate.room == entries[0].room or Vector2(base.position - previous.position).length() < 22.0:
				continue
		for y in range(base.position.y, base.end.y):
			for x in range(base.position.x, base.end.x):
				map.set_floor(Vector2i(x, y), false)
		if not DungeonGenerator.validate_reachability(map).get("reachable", false):
			for y in range(base.position.y, base.end.y):
				for x in range(base.position.x, base.end.x):
					map.set_floor(Vector2i(x, y), true)
			continue
		for y in range(base.position.y, base.end.y):
			for x in range(base.position.x, base.end.x):
				var cell := Vector2i(x, y)
				map.mark_terrain_obstacle(cell)
				blocked[cell] = true
		var kind := (theme - 2) * 2 + entries.size()
		entries.append({"kind": kind, "name": NAMES[kind], "room": candidate.room, "footprint": base})
		if entries.size() >= target:
			break
	map.set_meta("scenic_landmarks", entries)
	map.set_meta("scenic_landmark_cells", blocked)
	return entries

static func render(stage: Node2D, map: DungeonMap, entries: Array) -> void:
	var root := Node2D.new()
	root.name = "ScenicLandmarks"
	root.z_index = -40
	stage.add_child(root)
	if entries.is_empty():
		return
	var sheet := load(SHEET) as Texture2D
	for entry: Dictionary in entries:
		var base: Rect2i = entry.footprint
		var sprite := Sprite2D.new()
		sprite.name = "Landmark%d" % int(entry.kind)
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = REGIONS[int(entry.kind)]
		sprite.texture = atlas
		if int(entry.kind) in [2, 3]:
			var flow := ShaderMaterial.new()
			flow.shader = preload("res://entities/stage_environment/landmark_flow.gdshader")
			flow.set_shader_parameter("kind", int(entry.kind))
			flow.set_shader_parameter("region_origin", atlas.region.position)
			flow.set_shader_parameter("region_size", atlas.region.size)
			sprite.material = flow
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var factor := 192.0 / atlas.region.size.x
		sprite.scale = Vector2.ONE * factor
		sprite.position = map.grid_to_world(base.position) + Vector2(96, 64) - Vector2(0, atlas.region.size.y * factor * 0.5)
		root.add_child(sprite)
		# Static tile collision is installed by StageEnvironment using the exact
		# same six-by-two footprint consumed by navigation and safe-spawn caches.
		sprite.set_meta("footprint", base)
		if int(entry.kind) == 0:
			var worker := Node2D.new()
			worker.name = "Miner"
			worker.set_script(preload("res://entities/stage_environment/miner_worker.gd"))
			worker.position = map.grid_to_world(base.position) + Vector2(90, 18)
			root.add_child(worker)

static func reserve_decorations(map: DungeonMap, occupied: Dictionary, positions: Array[Vector2]) -> void:
	for entry: Dictionary in map.get_meta("scenic_landmarks", []):
		var base: Rect2i = entry.footprint
		positions.append(map.grid_to_world(base.position) + Vector2(96, 0))
		for y in range(base.position.y - 4, base.end.y):
			for x in range(base.position.x, base.end.x):
				occupied[Vector2i(x, y)] = Vector2i(-999, -999)
