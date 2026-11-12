extends SceneTree
const Layout := preload("res://systems/room_layout.gd")

func _initialize() -> void:
	var fingerprints := {}
	for sample in 60:
		for ordinal in 5:
			var map: DungeonMap = Layout.generate(1 + sample % 20, ordinal, sample * 139)
			assert(map.rooms.size() == 1 and map.width <= 32 and map.height <= 26)
			assert(map.has_navigation_clearance(map.spawn_point))
			assert(map.has_navigation_clearance(Vector2i.ZERO), "Central combat space is obstructed")
			var exit_cell := Vector2i(0, map.rooms[0].position.y + 2)
			assert(map.has_navigation_clearance(exit_cell), "Door approach is obstructed")
			var queue: Array[Vector2i] = [map.spawn_point]
			var visited := {map.spawn_point: true}
			var cursor := 0
			while cursor < queue.size():
				var cell := queue[cursor]
				cursor += 1
				for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var next: Vector2i = cell + direction
					if map.has_navigation_clearance(next) and not visited.has(next):
						visited[next] = true
						queue.append(next)
			for cell in map.get_spawn_cells():
				assert(visited.has(cell), "Actors can spawn in an unreachable pocket")
			assert((map.boss_room_index == 0) == (ordinal == 4))
			fingerprints[hash(map.get_floor_cells())] = true
	assert(fingerprints.size() >= 8, "Room seeds do not produce varied geometry")
	print("ROOM_LAYOUT_CHECK PASS: 300 rooms; actor clearance, connected combat space, exit approach, boss and seeded variation")
	quit()
