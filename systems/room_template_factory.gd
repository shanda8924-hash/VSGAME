extends RefCounted
class_name RoomTemplateFactory

const TEMPLATE_IDS: Array[String] = ["standard", "wide", "tall", "center_block", "pillars", "large"]

static func build_map(template_id: String) -> DungeonMap:
	var room_size := _room_size(template_id)
	var map := DungeonMap.new(room_size.x + 12, room_size.y + 12)
	var room := Rect2i(Vector2i(-room_size.x / 2, -room_size.y / 2), room_size)
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			map.set_floor(Vector2i(x, y), true)
	_apply_obstacles(map, room, template_id)
	map.rooms = [room]
	map.spawn_point = Vector2i(0, maxi(4, room_size.y / 4))
	map.elite_room_indices.clear()
	return map

static func get_template_ids() -> Array[String]:
	return TEMPLATE_IDS.duplicate()

static func get_display_name(template_id: String) -> String:
	return {
		"standard": "戦士の間",
		"wide": "大広間",
		"tall": "長廊",
		"center_block": "中央遺跡",
		"pillars": "柱の間",
		"large": "大殿堂",
	}.get(template_id, template_id.to_upper())

static func _room_size(template_id: String) -> Vector2i:
	return {
		"standard": Vector2i(34, 22),
		"wide": Vector2i(44, 18),
		"tall": Vector2i(26, 30),
		"center_block": Vector2i(36, 24),
		"pillars": Vector2i(38, 24),
		"large": Vector2i(44, 28),
	}.get(template_id, Vector2i(34, 22))

static func _apply_obstacles(map: DungeonMap, room: Rect2i, template_id: String) -> void:
	match template_id:
		"center_block":
			_fill_obstacle(map, Rect2i(Vector2i(-3, -3), Vector2i(6, 6)))
		"pillars":
			for center in [Vector2i(-9, -5), Vector2i(9, -5), Vector2i(-9, 5), Vector2i(9, 5)]:
				_fill_obstacle(map, Rect2i(center - Vector2i.ONE, Vector2i(3, 3)))
		"large":
			_fill_obstacle(map, Rect2i(Vector2i(-13, -1), Vector2i(5, 3)))
			_fill_obstacle(map, Rect2i(Vector2i(8, -1), Vector2i(5, 3)))
		_:
			pass

static func _fill_obstacle(map: DungeonMap, obstacle: Rect2i) -> void:
	for y in range(obstacle.position.y, obstacle.end.y):
		for x in range(obstacle.position.x, obstacle.end.x):
			map.set_floor(Vector2i(x, y), false)
