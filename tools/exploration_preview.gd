extends Node
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	GameManager.selected_character_id = "swordsman"
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	var controller := game.get_node("MapRunController") as MapRunController
	var player := game.get_node("Player") as Player
	var stage := game.get_node("StageEnvironment") as StageEnvironment
	var wave := game.get_node("WaveSpawner") as WaveSpawner
	var camera := Camera2D.new()
	camera.zoom=Vector2.ONE*0.95
	game.add_child(camera)
	camera.make_current()
	GameManager.map_mode_active=true
	for index in [1,2,3]:
		if index>1:
			controller._clear_map_nodes()
			await get_tree().process_frame
		var rng := RandomNumberGenerator.new()
		rng.seed=913000
		var map := ExplorationLayout.generate(index,rng)
		GameManager.dungeon_map=map
		GameManager.current_map_index=index
		await stage.build_dungeon_async(map,5)
		player.position=map.grid_to_world(map.spawn_point)
		if index==1: controller.begin_run()
		else: controller._start_map(index)
		while not wave.encounters_ready: await get_tree().physics_frame
		# Actual geometry, props, enemies and HUD; pause only to capture a readable view.
		var room: Rect2i=map.rooms[2]
		player.position=map.grid_to_world(room.position+room.size/2)+Vector2(0,35)
		camera.position=player.position
		controller._update_progress()
		game.get_node("HUD").set_room_message("")
		get_tree().paused=true
		await capture("res://artifacts/exploration_map%d.png"%index)
		get_tree().paused=false
		# A second real camera view, focused on one encounter and an irregular exit.
		room=map.rooms[4]
		player.position=map.grid_to_world(room.position+room.size/2)+Vector2(-100,100)
		camera.position=map.grid_to_world(room.position+room.size/2)
		camera.zoom=Vector2.ONE*1.3
		controller._update_progress()
		get_tree().paused=true
		await capture("res://artifacts/exploration_guardian%d.png"%index)
		get_tree().paused=false
		camera.zoom=Vector2.ONE*0.95
		if index==2:
			# Record a continuous navigable route rather than disconnected camera jumps.
			var queue: Array[Vector2i] = [map.spawn_point]
			var previous := {map.spawn_point:map.spawn_point}
			var target: Vector2i = map.rooms[4].position+map.rooms[4].size/2
			var cursor := 0
			while cursor<queue.size() and not previous.has(target):
				var cell := queue[cursor]
				cursor+=1
				for direction in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
					var next: Vector2i = cell+direction
					if previous.has(next) or not map.has_navigation_clearance(next): continue
					previous[next]=cell
					queue.append(next)
			var path: Array[Vector2i] = [target]
			while target!=map.spawn_point:
				target=previous[target]
				path.append(target)
			path.reverse()
			for cell in path:
				player.position=map.grid_to_world(cell)
				controller._update_progress()
			var input := InputEventKey.new()
			input.physical_keycode=KEY_M
			input.pressed=true
			controller._exploration_map_ui._unhandled_key_input(input)
			await capture("res://artifacts/exploration_discovery.png")
			controller._exploration_map_ui._unhandled_key_input(input)
	print("MAP PREVIEWS CAPTURED")
	get_tree().quit()

func capture(path: String) -> void:
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
