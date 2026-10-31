extends Node
## Generator-only regression: the farthest room is a clear, reserved boss arena.

const MAP_SIZES := [Vector4i(78, 78, 10, 1), Vector4i(86, 86, 11, 2), Vector4i(94, 94, 12, 2)]
var failures: Array[String] = []
var vertical_wall_cells := 0

func _ready() -> void:
	SaveManager.begin_ephemeral_session()
	_run.call_deferred()

func _run() -> void:
	var generated := 0
	var minimum_room_count := 999
	var minimum_elite_count := 999
	for config in MAP_SIZES:
		for seed_index in range(128):
			var rng := RandomNumberGenerator.new()
			rng.seed = 1000 + generated * 97 + seed_index
			var map := DungeonGenerator.generate(config.x, config.y, config.z, config.w, rng)
			_test_generated_map(map, rng.seed)
			minimum_room_count = mini(minimum_room_count, map.rooms.size())
			minimum_elite_count = mini(minimum_elite_count, map.elite_room_indices.size())
			_check(map.elite_room_indices.size() == config.w, "production elite count seed=%d" % rng.seed)
			generated += 1
			if generated % 12 == 0:
				await get_tree().process_frame
	_check(vertical_wall_cells > 0, "existing vertical short walls remain in generated maps")
	_test_small_maps()
	_test_tied_distance()
	_test_short_wall_orientation()
	print("DUNGEON_RESERVATION generated=%d min_rooms=%d min_elites=%d vertical_wall_cells=%d" % [generated, minimum_room_count, minimum_elite_count, vertical_wall_cells])
	if failures.is_empty():
		print("DUNGEON_RESERVATION_CHECK: PASS")
	else:
		for failure in failures:
			push_error("DUNGEON_RESERVATION_CHECK: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _test_generated_map(map: DungeonMap, seed_value: int) -> void:
	var prefix := "seed=%d " % seed_value
	var index := map.boss_room_index
	_check(index > 0 and index < map.rooms.size(), prefix + "valid non-start boss room")
	if index <= 0 or index >= map.rooms.size():
		return
	var boss_room := map.rooms[index]
	_check(boss_room.size == DungeonGenerator.BOSS_ROOM_SIZE, prefix + "14x14 boss arena")
	_check(_farthest_room_index(map) == index, prefix + "distance-squared selection contract")
	_check(index not in map.elite_room_indices, prefix + "boss is not an elite room")
	_check(map.combat_region_by_room.get(index) == DungeonMap.REGION_ARENA, prefix + "boss is arena region")
	_check(map.hazard_regions.is_empty() and DungeonMap.REGION_HAZARD not in map.combat_region_by_room.values(), prefix + "no generated hazards")
	var interior := Rect2i(map.get_min_coords() + Vector2i(2, 2), Vector2i(map.width - 4, map.height - 4))
	_check(interior.encloses(boss_room), prefix + "boss respects outer border")
	var clear := true
	for y in range(boss_room.position.y, boss_room.end.y):
		for x in range(boss_room.position.x, boss_room.end.x):
			var cell := Vector2i(x, y)
			clear = clear and map.is_floor(cell) and not map.is_terrain_obstacle(cell)
	_check(clear, prefix + "all 196 boss cells are clear floor")
	for other_index in map.rooms.size():
		if other_index != index:
			_check(not boss_room.grow(DungeonGenerator.ROOM_PLACEMENT_MARGIN).intersects(map.rooms[other_index]), prefix + "boss does not overlap neighboring room")
	for cell_variant in map.terrain_obstacle_cells.keys():
		var cell: Vector2i = cell_variant
		if map.get_combat_region_type(cell) == DungeonMap.REGION_CHOKEPOINT:
			for room_index in map.combat_region_by_room.keys():
				if map.combat_region_by_room[room_index] != DungeonMap.REGION_CHOKEPOINT:
					continue
				var room: Rect2i = map.rooms[room_index]
				var center := room.position + room.size / 2
				_check(cell.x == center.x and absi(cell.y - center.y) > 1, prefix + "vertical walls only, central opening retained")
				vertical_wall_cells += 1
	var reachable := DungeonGenerator.validate_reachability(map)
	_check(bool(reachable.get("reachable", false)), prefix + "all floors reachable")

func _farthest_room_index(map: DungeonMap) -> int:
	var chosen := -1
	var farthest := -1.0
	for index in range(1, map.rooms.size()):
		var room := map.rooms[index]
		var distance := Vector2(room.position + room.size / 2 - map.spawn_point).length_squared()
		if distance >= farthest:
			farthest = distance
			chosen = index
	return chosen

func _test_small_maps() -> void:
	for config in [Vector4i(8, 8, 1, 0), Vector4i(16, 16, 2, 0), Vector4i(24, 24, 3, 1), Vector4i(32, 32, 4, 1)]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 719
		var map := DungeonGenerator.generate(config.x, config.y, config.z, config.w, rng)
		_check(not map.rooms.is_empty() and map.is_floor(map.spawn_point), "small %s fallback spawn remains valid" % config)
		_check(bool(DungeonGenerator.validate_reachability(map).get("reachable", false)), "small %s all floors reachable" % config)
		_check(map.boss_room_index == _farthest_room_index(map), "small %s valid boss or -1" % config)
		_check(map.hazard_regions.is_empty(), "small %s no hazard" % config)
	print("DUNGEON_RESERVATION small_maps=4 fallback=preserved")

func _test_tied_distance() -> void:
	var map := DungeonMap.new(64, 64)
	map.rooms.assign([Rect2i(-4, -4, 8, 8), Rect2i(-24, -4, 8, 8), Rect2i(16, -4, 8, 8)])
	map.spawn_point = Vector2i.ZERO
	DungeonGenerator._assign_boss_room(map)
	_check(map.boss_room_index == 2, "equal distances select later room index deterministically")

func _test_short_wall_orientation() -> void:
	var wide := DungeonMap.new(32, 32)
	DungeonGenerator._apply_chokepoint(wide, Rect2i(-7, -4, 14, 8))
	_check(not wide.terrain_obstacle_cells.is_empty(), "wide room keeps vertical short walls")
	var tall := DungeonMap.new(32, 32)
	DungeonGenerator._apply_chokepoint(tall, Rect2i(-4, -7, 8, 14))
	_check(tall.terrain_obstacle_cells.is_empty(), "tall room no longer generates horizontal short walls")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
