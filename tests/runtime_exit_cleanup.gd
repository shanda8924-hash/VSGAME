extends Node
## 実Game Sceneを直接quitせずTitleへ戻してから終了し、動的Scene/Resourceを
## SceneTreeへ正常に解放させるテスト専用後始末。

var _exit_code := 0
var _success_message := ""

func begin(exit_code: int, success_message: String) -> void:
	_exit_code = exit_code
	_success_message = success_message
	_cleanup.call_deferred()

func _cleanup() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/title.tscn")
	for _index in 12:
		await get_tree().process_frame
	if _success_message != "":
		print(_success_message)
	get_tree().quit(_exit_code)
