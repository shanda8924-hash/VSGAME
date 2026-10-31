extends Node
## Phase 1 の波（サージ）の実画面：予告（朱赤の縁・HUDの「N秒前」）と本番（包囲湧き・役割）。
## 通常起動と同じ経路（start_run(true)→MapRunController）を通し、時計だけ進めて撮る。
const GAME_SCENE := preload("res://scenes/game.tscn")

func _ready() -> void:
	var runner := Runner.new()
	runner.name = "SurgeCaptureRunner"
	runner.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child.call_deferred(runner)

class Runner extends Node:
	func _ready() -> void:
		DirAccess.make_dir_recursive_absolute("res://artifacts/surge")
		_run.call_deferred()

	func _run() -> void:
		SaveManager.begin_ephemeral_session()
		GameManager.selected_survival_map = 1
		GameManager.selected_character_id = "swordsman"
		seed(9101)
		get_tree().change_scene_to_packed(GAME_SCENE)
		for frame in 45:
			await get_tree().process_frame
		var game := get_tree().current_scene
		var player := game.get_node("Player") as Player
		player.health_component.invincible = true
		var controller := game.get_node("MapRunController") as MapRunController
		var times: Array = controller._survival_surge_times()
		var first := float(times[0])
		GameManager.elapsed_seconds = first - 6.0
		controller._tick_survival()
		for frame in 30:
			await get_tree().process_frame
		await _capture("warning")
		GameManager.elapsed_seconds = first
		controller._tick_survival()
		for frame in 40:
			await get_tree().process_frame
		await _capture("wave_start")
		GameManager.elapsed_seconds = first + 16.0
		controller._tick_survival()
		for frame in 90:
			await get_tree().process_frame
		await _capture("wave_mid")
		GameManager.elapsed_seconds = first + 31.0
		controller._tick_survival()
		for frame in 30:
			await get_tree().process_frame
		await _capture("wave_end")
		print("SURGE_CAPTURE done state=%s" % JSON.stringify(controller.debug_get_map_state()))
		AudioManager.stop_all(false)
		get_tree().quit()

	func _capture(name: String) -> void:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/surge/%s.png" % name)
