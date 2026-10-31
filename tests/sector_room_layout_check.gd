extends SceneTree

func _initialize() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/exploration_run.json"))
	for theme in config.maps:
		var fewest := 100
		var failed := 0
		for sample in 60:
			var rng := RandomNumberGenerator.new()
			rng.seed = 920000 + int(theme.index) * 1000 + sample
			var map := DungeonGenerator.generate(int(theme.width), int(theme.height), int(theme.room_count), 0, rng, true)
			fewest = mini(fewest, map.rooms.size())
			if map.rooms.size() < 4 or not DungeonGenerator.validate_reachability(map).get("reachable", false):
				failed += 1
		print("ROOM_LAYOUT map=%d min_rooms=%d failed=%d" % [int(theme.index), fewest, failed])
		assert(failed == 0, "A generated floor cannot support several combat rooms and a boss")
	quit()
