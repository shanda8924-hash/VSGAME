extends Node

func _ready() -> void:
	var rosters := WaveSpawner.get_enemy_rosters()
	assert(WaveSpawner.ENEMY_HIERARCHY == ["mob", "standard", "strong", "elite", "midboss", "boss"])
	assert(rosters.size() == 3)
	var assigned := {}
	var reached := {}
	var original_depth := GameManager.current_depth
	var spawner := WaveSpawner.new()
	for map_index in range(1, 4):
		var roster: Dictionary = rosters[map_index]
		for rank_name in ["mob", "standard", "strong"]:
			assert(not (roster[rank_name] as Array).is_empty(), "Every MAP needs all three base ranks")
			for enemy_id in roster[rank_name]:
				assert(DataLoader.enemies.has(enemy_id), "Assigned enemy data must exist: " + enemy_id)
				assert(not assigned.has(enemy_id), "Each base species belongs to one MAP: " + enemy_id)
				assigned[enemy_id] = {"map": map_index, "rank": rank_name}
		for local_floor in range(1, 21):
			GameManager.current_depth = (map_index - 1) * 20 + local_floor
			for room_id in range(8):
				for role in WaveSpawner.ROOM_RANK_PATTERNS:
					for enemy_id in spawner._encounter_enemy_ids(map_index, role, room_id):
						reached[enemy_id] = true
	GameManager.current_depth = original_depth
	spawner.free()
	assert(assigned.size() == 23, "All 23 normal enemies must be assigned")
	assert(reached.size() == 23, "All 23 normal enemies must be reachable in authored encounters")
	print("ENEMY ASSIGNMENT PASS: 23 species / 3 maps / 6 ranks / all reachable")
	get_tree().quit()
