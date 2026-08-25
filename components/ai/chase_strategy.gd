extends EnemyBehaviorStrategy
class_name ChaseStrategy

const CARDINAL_DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
const PATH_REFRESH_MSEC := 280

var _path: Array[Vector2i] = []
var _path_target := Vector2i(999999, 999999)
var _next_path_refresh_msec: int = 0
## もっとも基本的な「プレイヤーへ直進する」AI。

func compute_direction(self_position: Vector2, target_position: Vector2) -> Vector2:
	var direct := target_position - self_position
	var map := GameManager.dungeon_map
	if map == null or _has_clear_floor_line(map, self_position, target_position):
		_path.clear()
		return direct.normalized()
	var start := _nearest_floor_cell(map, map.world_to_grid(self_position))
	var goal := _nearest_floor_cell(map, map.world_to_grid(target_position))
	var now := Time.get_ticks_msec()
	if _path.is_empty() or goal != _path_target or now >= _next_path_refresh_msec:
		_path = _build_floor_path(map, start, goal)
		_path_target = goal
		_next_path_refresh_msec = now + PATH_REFRESH_MSEC
	while _path.size() > 1 and self_position.distance_to(map.grid_to_world(_path[0])) <= DungeonMap.CELL_WORLD_SIZE * 0.45:
		_path.pop_front()
	if _path.is_empty():
		return direct.normalized()
	return (map.grid_to_world(_path[0]) - self_position).normalized()

func _has_clear_floor_line(map: DungeonMap, from: Vector2, to: Vector2) -> bool:
	var distance := from.distance_to(to)
	var steps := maxi(1, int(ceil(distance / (DungeonMap.CELL_WORLD_SIZE * 0.45))))
	for index in range(steps + 1):
		var cell := map.world_to_grid(from.lerp(to, float(index) / float(steps)))
		if index > 0 and index < steps and not _has_navigation_clearance(map, cell):
			return false
	return true

func _nearest_floor_cell(map: DungeonMap, origin: Vector2i) -> Vector2i:
	if map.is_floor(origin):
		return origin
	for radius in range(1, 4):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := origin + Vector2i(x, y)
				if map.is_floor(candidate):
					return candidate
	return origin

func _build_floor_path(map: DungeonMap, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if not map.is_floor(start) or not map.is_floor(goal):
		return []
	var frontier: Array[Vector2i] = [start]
	var cursor := 0
	var came_from: Dictionary = {start: start}
	while cursor < frontier.size():
		var current := frontier[cursor]
		cursor += 1
		if current == goal:
			break
		for direction in CARDINAL_DIRECTIONS:
			var next := current + direction
			if (next == goal or _has_navigation_clearance(map, next)) and not came_from.has(next):
				came_from[next] = current
				frontier.append(next)
	if not came_from.has(goal):
		return []
	var reversed: Array[Vector2i] = []
	var step := goal
	while step != start:
		reversed.append(step)
		step = came_from[step]
	reversed.append(start)
	reversed.reverse()
	return reversed

func _has_navigation_clearance(map: DungeonMap, cell: Vector2i) -> bool:
	if not map.is_floor(cell):
		return false
	for y in range(-1, 2):
		for x in range(-1, 2):
			if not map.is_floor(cell + Vector2i(x, y)):
				return false
	return true
