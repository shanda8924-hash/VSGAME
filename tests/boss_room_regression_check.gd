extends Node

var game: Node2D
var player: Player
var stage: StageEnvironment
var controller: MapRunController
var spawner: BossSpawner
var drops: EquipmentDropSystem
var camera: Camera2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	GameManager.selected_character_id = "swordsman"
	_run.call_deferred()

func _run() -> void:
	game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	player = game.get_node("Player")
	stage = game.get_node("StageEnvironment")
	controller = game.get_node("MapRunController")
	spawner = game.get_node("BossSpawner")
	drops = game.get_node("EquipmentDropSystem")
	player.health_component.invincible = true
	spawner._screen_effects = null
	spawner._hud = null
	GameManager.map_mode_active = true
	GameManager.generate_exploration_map(1)
	await stage.build_dungeon_async(GameManager.dungeon_map,5)
	player.position = GameManager.dungeon_map.grid_to_world(GameManager.dungeon_map.spawn_point)
	controller.begin_run()
	var wave := game.get_node("WaveSpawner") as WaveSpawner
	for frame in 200:
		if wave.encounters_ready: break
		await get_tree().physics_frame
	assert(wave.encounters_ready)
	controller._transition_to_map(1,4)
	for frame in 400:
		await get_tree().process_frame
		if not controller._transitioning: break
	assert(not controller._transitioning and GameManager.current_floor_index == 4)
	for frame in 200:
		if wave.encounters_ready: break
		await get_tree().physics_frame
	assert(wave.encounters_ready)
	var spawn := controller._boss_gate.position + Vector2(96,0)
	var actual_spawns := 0
	# Real BossSpawner entry, all twenty draws per theme, including each rollover.
	for config: Dictionary in controller._maps:
		var pool: Array = config.boss_candidates
		var cycle: Array[String] = []
		var previous := ""
		for floor_index in 20:
			var boss := spawner.start_room_boss(floor_index+1,{"candidates":pool},spawn) as EnemyBasic
			assert(boss != null,"Candidate pool exhausted at floor %d" % (floor_index+1))
			var id := boss.enemy_data.id
			assert(id in pool and id not in cycle and id != previous,"Repeat before completing boss cycle")
			cycle.append(id)
			if cycle.size() == pool.size(): cycle.clear()
			previous = id
			actual_spawns += 1
			spawner.clear_room_boss()
			await get_tree().process_frame
	assert(spawner._pick_unspawned_boss_id([]) == "")
	spawner._spawned_boss_ids.assign(["minotaur"])
	assert(spawner._pick_unspawned_boss_id(["minotaur"]) == "minotaur")
	# Recreate the reported state: three used MAP1 candidates, guardians dead, key acquired.
	spawner._spawned_boss_ids.assign(controller._current_config.boss_candidates)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyBasic and not enemy._is_dead:
			enemy.health_component.clear_shield()
			enemy.health_component.current_hp = 1.0
			enemy.health_component.apply_secondary_damage(1000000)
	await get_tree().physics_frame
	await _close_reward_modals()
	controller._update_progress()
	controller._map_kills = int(controller._current_config.boss_kill_requirement)
	controller._update_progress()
	assert(controller._boss_unlocked and controller._boss_gate.available)
	player.position = controller._boss_gate.position + Vector2(-60,0)
	for frame in 4: await get_tree().physics_frame
	camera = Camera2D.new()
	camera.position = controller._boss_gate.position
	camera.zoom = Vector2.ONE*1.5
	game.add_child(camera)
	camera.make_current()
	assert(stage._boss_floor_seal.visible and stage._boss_floor_seal.modulate.a <= 0.3)
	await _capture("before")
	# Exercise failure recovery without leaving the interaction area.
	var saved_scene := spawner.enemy_scene
	spawner.enemy_scene = null
	assert(player._try_interact_nearest())
	for frame in 3: await get_tree().physics_frame
	assert(not controller._boss_active and controller._boss_gate.can_interact(player),"Failed spawn cannot retry in place")
	spawner.enemy_scene = saved_scene
	assert(player._try_interact_nearest())
	var boss := spawner.debug_get_current_boss() as EnemyBasic
	assert(is_instance_valid(boss) and controller._boss_active,"Floor4 kill/gate route failed")
	assert(not stage._boss_floor_seal.visible,"Seal obscures live boss")
	await _capture("fight")
	# Kill at the east wall, where the previous +160px loot offset landed inside stone.
	var map := GameManager.dungeon_map
	var room: Rect2i = map.rooms[map.boss_room_index]
	boss.position = map.grid_to_world(Vector2i(room.end.x-2,room.position.y+room.size.y/2))
	var death := boss.position
	var old_items := get_tree().get_nodes_in_group("ground_equipment")
	spawner.debug_defeat_current_boss()
	for frame in 6: await get_tree().physics_frame
	await _close_reward_modals()
	assert(not stage._boss_floor_seal.visible,"Seal remains after defeat")
	var items := get_tree().get_nodes_in_group("ground_equipment").filter(func(item): return item not in old_items)
	assert(items.size() >= 1,"Boss guaranteed loot lost")
	for item: GroundEquipmentItem in items: _check_drop(item,room,death)
	await _capture("loot")
	var item := items[0] as GroundEquipmentItem
	player.position = item.position
	for frame in 4: await get_tree().physics_frame
	var item_id := item.equipment.instance_id
	assert(not player._try_interact_nearest(),"Pickup is masked by chest/stairs interaction")
	player._pick_up_nearest_equipment()
	await get_tree().process_frame
	assert(not is_instance_valid(item) or item.is_queued_for_deletion(),"Loot not collected: "+item_id)
	assert(not controller._boss_chest.is_opened and GameManager.current_floor_index == 4,"Pickup opened chest or descended")
	var before_chest := get_tree().get_nodes_in_group("ground_equipment")
	controller._boss_chest._on_body_entered(player)
	assert(controller._boss_chest.interact(player))
	await get_tree().physics_frame
	var rewards := get_tree().get_nodes_in_group("ground_equipment").filter(func(reward): return reward not in before_chest)
	assert(rewards.size()==1,"Chest reward lost")
	_check_drop(rewards[0],room,death)
	assert(controller._stairs.available and GameManager.current_floor_index == 4)
	var cleanup := preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	cleanup.begin(0,"BOSS_ROOM_REGRESSION PASS: %d boss spawns; floor4 kill gate/interaction/retry; seal states; wall-side loot pickup and chest reward" % actual_spawns)

func _check_drop(item: GroundEquipmentItem, room: Rect2i, death: Vector2) -> void:
	var map := GameManager.dungeon_map
	var cell := map.world_to_grid(item.position)
	assert(room.has_point(cell) and map.has_navigation_clearance(cell),"Drop outside clear floor in death room")
	assert(item.position.distance_to(death)<320,"Drop teleported far from death")
	assert(item.position.distance_to(controller._boss_chest.position)>=112,"Loot overlaps chest interaction")
	assert(item.position.distance_to(controller._stairs.position)>=112,"Loot overlaps stairs interaction")
	var shape := CircleShape2D.new()
	shape.radius = 20
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	query.transform = Transform2D(0,item.position)
	assert(game.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(),"Physical obstacle at pickup")

func _capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	if label == "loot": await get_tree().create_timer(1.2).timeout
	controller._update_progress()
	get_tree().paused = true
	for frame in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/boss_room_fixed_%s.png" % label)
	get_tree().paused = false

func _close_reward_modals() -> void:
	for attempt in 15:
		var handled := false
		for ui_name in ["LevelUpSelect","ConceptSelect","ItemSelect"]:
			var ui := game.get_node_or_null(ui_name) as CanvasLayer
			if ui == null or not ui.visible: continue
			for button in ui.find_children("*","Button",true,false):
				if button.visible and not button.disabled:
					button.pressed.emit()
					handled = true
					break
			if handled: break
		if not handled: return
		for frame in 3: await get_tree().process_frame
