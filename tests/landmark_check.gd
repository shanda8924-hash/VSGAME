extends Node
const Landmarks := preload("res://entities/stage_environment/scenic_landmarks.gd")
const Stage := preload("res://entities/stage_environment/stage_environment.tscn")
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var count := 0
	var sparse := 0
	for theme in [1, 2, 3]:
		for sample in 20:
			var rng := RandomNumberGenerator.new()
			rng.seed = 91820 + theme + sample * 100
			var map := DungeonGenerator.generate(78 + (theme - 1) * 8, 78 + (theme - 1) * 8, 9 + theme, 2, rng)
			var original := map.get_floor_cells().size()
			var entries := Landmarks.prepare(map, theme)
			assert(DungeonGenerator.validate_reachability(map).reachable)
			assert(Landmarks.prepare(map, theme) == entries)
			assert(original - map.get_floor_cells().size() == entries.size() * 12)
			if theme == 1:
				assert(entries.is_empty())
			elif entries.size() < 2:
				sparse += 1
			for entry: Dictionary in entries:
				assert(entry.room != map.boss_room_index)
				var rect: Rect2i = entry.footprint
				for dx in range(6):
					assert(not map.is_floor(rect.position + Vector2i(dx, -1)))
				for cell in map.get_spawn_cells():
					assert(not rect.has_point(cell))
			count += entries.size()
	var stage := Stage.instantiate()
	add_child(stage)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91822
	var map := DungeonGenerator.generate(86, 86, 11, 2, rng)
	GameManager.current_map_index = 2
	await stage.build_dungeon_async(map)
	assert(stage.get_node("ScenicLandmarks").get_child_count() == map.get_meta("scenic_landmarks").size() + 1)
	for cell: Vector2i in map.get_meta("scenic_landmark_cells"):
		assert(stage._tile_map_layer.get_cell_alternative_tile(cell) == StageEnvironment.FLOOR_ALT_BLOCKER)
	stage.build_dungeon(map)
	assert(stage.get_node("ScenicLandmarks").get_child_count() == map.get_meta("scenic_landmarks").size() + 1)
	print("LANDMARK_CHECK PASS seeds=60 landmarks=%d sparse_layouts=%d async_and_rebuild=ok" % [count, sparse])
	get_tree().quit()
