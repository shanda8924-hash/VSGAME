extends Node

const RUNNER_SCRIPT := preload("res://tests/legacy/map_entry_input_check.gd")

func _ready() -> void:
	var runner := Node.new()
	runner.name = "PersistentMapEntryInputRunner"
	runner.set_script(RUNNER_SCRIPT)
	get_tree().root.add_child.call_deferred(runner)
	get_tree().change_scene_to_file.call_deferred("res://scenes/title.tscn")
