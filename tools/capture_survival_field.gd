extends Node
## 5分サバイバルの実画面（3テーマの床だけの戦場）を撮る。
## game.tscn を change_scene で current_scene にし、通常起動と同じ経路（start_run(true)）を通す。
## 撮影役は root 直下に置き、シーン切替で消えないようにする。
const GAME_SCENE := preload("res://scenes/game.tscn")

func _ready() -> void:
	var runner := Runner.new()
	runner.name = "SurvivalFieldCaptureRunner"
	runner.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child.call_deferred(runner)

class Runner extends Node:
	func _ready() -> void:
		DirAccess.make_dir_recursive_absolute("res://artifacts/survival_field")
		_run.call_deferred()

	func _run() -> void:
		for map_index in [1, 2, 3]:
			SaveManager.begin_ephemeral_session()
			SaveManager.unlock_map(map_index, 0)
			GameManager.selected_survival_map = map_index
			GameManager.selected_character_id = "swordsman"
			seed(5100 + map_index)
			get_tree().change_scene_to_packed(GAME_SCENE)
			for frame in 45:
				await get_tree().process_frame
			var game := get_tree().current_scene
			for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
				var background := game.get_node_or_null(node_name)
				if background:
					background.process_mode = Node.PROCESS_MODE_DISABLED
			for enemy in get_tree().get_nodes_in_group("enemies"):
				enemy.queue_free()
			var player := game.get_node("Player") as Player
			player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
			for frame in 8:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://artifacts/survival_field/map%d.png" % map_index)
			print("SURVIVAL_FIELD_CAPTURE map=%d survival=%s theme=%d" % [map_index, GameManager.survival_mode_active, GameManager.current_map_index])
		AudioManager.stop_all(false)
		get_tree().quit()
