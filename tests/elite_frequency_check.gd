extends Node
## 10分を実時間待機せず、実運用と同じJSONカーブ・独立RNGで遭遇時刻を検証する。

var failures: Array[String] = []

func _ready() -> void:
	var manager := EliteRoomManager.new()
	manager._spawn_settings = _read_json("res://data/elite_affixes/spawn_curve.json")
	var boss_windows: Array = []
	for start in range(60, 600, 60):
		boss_windows.append([float(start), float(start + 25)])
	var run_counts: Array[int] = []
	var run_times: Array = []
	for run_index in 5:
		var times := manager.simulate_roaming_spawn_times(600.0, 20260809 + run_index, boss_windows)
		run_counts.append(times.size())
		run_times.append(times)
		_check(times.size() >= 3 and times.size() <= 5, "measured run %d produced %d elites" % [run_index + 1, times.size()])
	var average := 0.0
	for count in run_counts:
		average += float(count)
	average /= float(run_counts.size())
	_check(average >= 3.0 and average <= 5.0, "five-run average is %.2f" % average)
	for seed_value in range(1, 101):
		var count := manager.simulate_roaming_spawn_times(600.0, seed_value).size()
		_check(count >= 3 and count <= 5, "seed %d produced %d elites" % [seed_value, count])
		var blocked_count := manager.simulate_roaming_spawn_times(600.0, seed_value, boss_windows).size()
		_check(blocked_count >= 3 and blocked_count <= 5, "boss-blocked seed %d produced %d elites" % [seed_value, blocked_count])
	var source := FileAccess.get_file_as_string("res://systems/elite_room_manager.gd")
	_check("StaticBody2D.new" not in source and "_seal_room" not in source, "roaming elite adds no invisible wall")
	_check(manager._get_delay_range(60.0)[0] > manager._get_delay_range(500.0)[0], "late game interval is shorter")
	_check(float(manager._spawn_settings.get("soft_pity_seconds", 0.0)) > 0.0, "soft pity is configured")
	for failure in failures:
		push_error(failure)
	print("ELITE_FREQUENCY_CHECK failures=%d run_counts=%s average=%.2f run_times=%s" % [failures.size(), run_counts, average, run_times])
	manager.free()
	get_tree().quit(0 if failures.is_empty() else 1)

func _read_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
