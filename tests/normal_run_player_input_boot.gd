extends Node

const RUNNER_SCRIPT := preload("res://tests/normal_run_player_input_check.gd")

func _ready() -> void:
	_install_runner.call_deferred()

func _install_runner() -> void:
	var runner := Node.new()
	runner.name = "PersistentNormalRunInputRunner"
	runner.set_script(RUNNER_SCRIPT)
	get_tree().root.add_child(runner)
	get_tree().change_scene_to_file.call_deferred("res://scenes/title.tscn")
