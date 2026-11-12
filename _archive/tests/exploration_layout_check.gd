extends Node
const SCENIC = preload("res://entities/stage_environment/scenic_landmarks.gd")
var metrics: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	for map_index in [1,2,3]:
		for seed_value in 40:
			var rng := RandomNumberGenerator.new()
			rng.seed = 913000+seed_value
			var map := ExplorationLayout.generate(map_index,rng)
			SCENIC.prepare(map,map_index)
			assert(DungeonGenerator.validate_reachability(map).get("reachable",false), "Disconnected floor")
			var distances := reachable(map)
			for room in map.rooms:
				assert(distances.has(room.position+room.size/2), "Room unreachable with 3x3 clearance")
			for cell: Vector2i in map.get_meta("objective_cells").values():
				assert(distances.has(cell), "Key/reward unreachable")
			assert(map.rooms.size()==[13,15,17][map_index-1])
			assert(map.boss_room_index==7 and map.get_meta("room_roles")[4]=="key_guard")
			if seed_value==0:
				var floors: Array = []
				for cell in map.get_floor_cells(): floors.append([cell.x,cell.y])
				var rooms: Array = []
				for room in map.rooms: rooms.append([room.position.x,room.position.y,room.size.x,room.size.y])
				var edges: Array = []
				for edge: Vector2i in map.get_meta("route_edges"): edges.append([edge.x,edge.y])
				var boss_cell: Vector2i = map.rooms[7].position+map.rooms[7].size/2
				metrics.append({"map":map_index,"width":map.width,"height":map.height,"rooms":rooms,"roles":map.get_meta("room_roles"),"edges":edges,"floors":floors,"start":[map.spawn_point.x,map.spawn_point.y],"start_boss_tiles":distances[boss_cell],"start_key_tiles":distances[map.get_meta("objective_cells")[4]],"floor_tiles":floors.size(),"landmarks":map.get_meta("scenic_landmarks",[]).size()})
	print("LAYOUT PASS: 120 seeds, all rooms/objectives reachable with 3x3 clearance after scenic footprints")
	var file := FileAccess.open("res://artifacts/exploration_layout_metrics.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics,"\t"))
	file.close()
	if "--geometry-only" in OS.get_cmdline_user_args():
		get_tree().quit()
		return
	GameManager.selected_character_id = "swordsman"
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	var controller := game.get_node("MapRunController") as MapRunController
	var stage := game.get_node("StageEnvironment") as StageEnvironment
	var wave := game.get_node("WaveSpawner") as WaveSpawner
	var player := game.get_node("Player") as Player
	GameManager.map_mode_active = true
	GameManager.generate_exploration_map(1)
	await stage.build_dungeon_async(GameManager.dungeon_map,5)
	player.position = GameManager.dungeon_map.grid_to_world(GameManager.dungeon_map.spawn_point)
	player.setup_camera_limits(GameManager.dungeon_map)
	controller.begin_run()
	for map_index in [1,2,3]:
		if map_index>1:
			controller._transition_to_map(map_index)
			while controller._transitioning: await get_tree().process_frame
		while not wave.encounters_ready: await get_tree().physics_frame
		await get_tree().physics_frame
		print("Placed encounter enemies: ",wave.exploration_placed_count)
		assert(wave.exploration_placed_count==[15,16,19][map_index-1], "Missing encounter enemies")
		assert(not controller._key_acquired and not controller._boss_unlocked)
		var elite := (wave.encounter_enemies[12][0] as WeakRef).get_ref() as EnemyBasic
		assert(elite.is_in_group("elite_enemies"))
		for child in elite.get_children():
			if child is EliteAffixComponent:
				assert(child.affix_ids.size()==(2 if map_index==3 else 1))
				var timers: Dictionary=child._timers.duplicate()
				child._process(30.0)
				assert(child._timers==timers,"Undiscovered elite must not attack at a distance")
		var count := get_tree().get_nodes_in_group("enemies").size()
		GameManager.elapsed_seconds += 2000
		controller._map_kills = 999
		controller._update_progress()
		for i in 5: await get_tree().physics_frame
		assert(not controller._boss_unlocked,"Time/kills must not bypass the key")
		assert(get_tree().get_nodes_in_group("enemies").size()==count,"No time-based reinforcement")
		var map := GameManager.dungeon_map
		var physical := physical_reachable(map,game as Node2D)
		print("Physical reachable cells=",physical.size()," floor clearance=",map.get_spawn_cells().size())
		for room in map.rooms:
			if not physical.has(room.position+room.size/2): print("Blocked room ",map.rooms.find(room)," centre ",room.position+room.size/2)
			assert(physical.has(room.position+room.size/2),"Rendered walls/props block a room")
		for cell: Vector2i in map.get_meta("objective_cells").values():
			var accessible := false
			for direction in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
				if physical.has(cell+direction): accessible=true
			assert(accessible,"Cannot approach an objective through actual collision")
		var guard := (wave.encounter_enemies[1][0] as WeakRef).get_ref() as EnemyBasic
		var saved_player := player.position
		player.position=guard.exploration_home+Vector2(500,0)
		guard.position=guard.exploration_home+Vector2(32,0)
		guard.exploration_alert=true
		guard._physics_process(1.0/60)
		assert(guard._returning_home and not guard.exploration_alert,"Guard must break an overlong chase")
		guard.position=guard.exploration_home
		guard._physics_process(1.0/60)
		assert(not guard._returning_home and guard.movement_component.direction.is_zero_approx())
		player.position=saved_player
		var key_chest: TreasureChest = controller._exploration_chests[4]
		key_chest._on_body_entered(player)
		assert(key_chest.interact(player) and not key_chest.is_opened,"Cannot steal key while guardians alive")
		for ref: WeakRef in wave.encounter_enemies[4]:
			var enemy := ref.get_ref() as EnemyBasic
			assert(enemy.exploration_room==4 and enemy.exploration_home==enemy.position)
			while not enemy._is_dead:
				enemy.health_component.apply_secondary_damage(10000)
				await get_tree().physics_frame
		controller._update_progress()
		assert(key_chest.available,"Guardian deaths unlock local chest")
		assert(key_chest.interact(player) and key_chest.is_opened)
		assert(controller._key_acquired and controller._boss_unlocked and controller._boss_gate.available)
		assert(not key_chest.interact(player),"Key reward once")
		var map_ui := controller._exploration_map_ui
		while GameManager.active_modal_count>0: GameManager.close_modal()
		var input := InputEventKey.new()
		input.physical_keycode=KEY_M
		input.pressed=true
		map_ui._unhandled_key_input(input)
		assert(map_ui.opened and get_tree().paused)
		map_ui._unhandled_key_input(input)
		assert(not map_ui.opened and not get_tree().paused)
		assert(map.get_meta("visited_rooms").size()<map.rooms.size(),"Unvisited rooms remain hidden")
		player.health_component.invincible=true
		player.position=controller._boss_gate.position+Vector2(0,80)
		controller._start_map_boss()
		await get_tree().physics_frame
		assert(controller._boss_active,"Key permits actual boss encounter")
		assert(is_instance_valid(guard) and not guard.is_queued_for_deletion(),"Boss must not erase uncleared optional encounters")
		print("MAP_FLOW PASS map=",map_index," enemies=",wave.exploration_placed_count," key locks/progression + M pause")
	print("EXPLORATION PASS")
	get_tree().quit()

func reachable(map: DungeonMap) -> Dictionary:
	var queue: Array[Vector2i] = [map.spawn_point]
	var seen := {map.spawn_point:0}
	var index := 0
	while index<queue.size():
		var cell := queue[index]
		index+=1
		for dir in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i = cell+dir
			if seen.has(next) or not map.has_navigation_clearance(next): continue
			seen[next]=seen[cell]+1
			queue.append(next)
	return seen

func physical_reachable(map: DungeonMap, world: Node2D) -> Dictionary:
	var allowed := {}
	var shape := CircleShape2D.new()
	shape.radius=20.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape=shape
	query.collision_mask=1
	query.exclude=[(get_tree().get_first_node_in_group("player") as CollisionObject2D).get_rid()]
	for cell in map.get_spawn_cells():
		query.transform=Transform2D(0,map.grid_to_world(cell)+Vector2.ONE*16)
		if world.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): allowed[cell]=true
	var queue: Array[Vector2i] = [map.spawn_point]
	var seen := {map.spawn_point:true}
	var index := 0
	while index<queue.size():
		var cell := queue[index]
		index+=1
		for direction in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var next: Vector2i=cell+direction
			if seen.has(next) or not allowed.has(next): continue
			seen[next]=true
			queue.append(next)
	return seen
