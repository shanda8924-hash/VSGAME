extends Node

var failures: Array[String] = []
var game: Node2D
var controller: RoomRunController
var player: Player
var room_durations: Dictionary = {}
var room_started_at: float = -1.0
var last_room: int = 0
var last_state: int = -1
var max_combo: int = 0
var attribute_rewards: int = 0
var treasure_rewards: int = 0
var completed_skill_count: int = 0
var completed_skill_level_total: int = 0
var fusion_room: int = 0
var _tap_action: String = ""
var _tap_release_frames: int = 0
var _next_ui_tick: int = 0
var _started_wall_msec: int = 0
var _game_seen: bool = false
var _result_seen: bool = false
var _title_exit_seen: bool = false
var _last_status_msec: int = 0
var _finishing: bool = false
var boss_ids_by_room: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	seed(81014)
	_started_wall_msec = Time.get_ticks_msec()
	print("NORMAL_RUN_INPUT stage=persistent_runner_ready")

func _process(_delta: float) -> void:
	_release_pending_tap()
	_print_status_if_due()
	# 36 ROOM化後は後半Bossを本編攻撃力で倒すため、旧12 ROOM用の240秒では
	# ROOM 24前後で正常進行中でも打ち切られる。実入力Soakの上限だけ9分へ延長する。
	if Time.get_ticks_msec() - _started_wall_msec > 540000:
		_finish_with_failure("normal input run exceeded 540 wall seconds")
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	if scene is TitleScreen:
		_handle_title(scene as TitleScreen)
		return
	if scene is HomeScreen:
		_handle_home(scene as HomeScreen)
		return
	if scene.is_in_group("game_runtime_world"):
		_handle_game(scene as Node2D)

func _handle_title(title: TitleScreen) -> void:
	_release_movement()
	if _result_seen:
		_title_exit_seen = true
		_finish()
		return
	if not _ui_ready():
		return
	if title.start_button.visible:
		_tap("ui_accept")
	elif title.mode_select.visible:
		_tap("ui_accept")

func _handle_home(_home: HomeScreen) -> void:
	_release_movement()
	if _ui_ready():
		# The first keyboard-focused card is the always-unlocked Soldier.
		_tap("ui_accept")

func _handle_game(scene: Node2D) -> void:
	if not _game_seen:
		_game_seen = true
		game = scene
		controller = game.get_node("RoomRunController") as RoomRunController
		player = game.get_node("Player") as Player
		controller.boss_spawner.room_boss_started.connect(func(room_number, boss_id, _display_name): boss_ids_by_room[room_number] = boss_id)
		# 攻撃DPSと撃破時間を測るSoakでは経路途中の死亡を除外する。攻撃力・
		# 攻撃速度・Build報酬は本編値のままで、耐久だけ計測用に固定する。
		player.health_component.max_hp = 100000.0
		player.health_component.current_hp = 100000.0
		# 8倍では0.08秒のMeleeHit寿命が物理1Frame未満になり、実攻撃判定を
		# 測れない。4倍なら短時間化しつつArea2D判定を最低1Frame以上維持できる。
		Engine.time_scale = 4.0
		print("NORMAL_RUN_INPUT stage=game room_mode=%s character=%s" % [GameManager.room_mode_active, GameManager.selected_character_id])
	_update_metrics()
	if GameManager.run_state == GameManager.RunState.RESULT:
		_handle_result()
		return
	if _handle_visible_modal():
		return
	match controller.state:
		RoomRunController.RoomState.COMBAT:
			_drive_combat()
		RoomRunController.RoomState.REWARD:
			_drive_reward()
		_:
			_release_movement()

func _update_metrics() -> void:
	if controller == null:
		return
	if controller.current_room != last_room:
		last_room = controller.current_room
		last_state = -1
	if controller.state != last_state:
		if controller.state == RoomRunController.RoomState.COMBAT:
			room_started_at = GameManager.elapsed_seconds
		elif last_state == RoomRunController.RoomState.COMBAT and room_started_at >= 0.0:
			room_durations[controller.current_room] = GameManager.elapsed_seconds - room_started_at
		last_state = controller.state
	if game:
		max_combo = maxi(max_combo, (game.get_node("ComboSystem") as ComboSystem).combo)
		var concept := game.get_node("ConceptSystem") as ConceptSystem
		completed_skill_count = concept.get_completed_skill_count()
		completed_skill_level_total = 0
		for level in concept.completed_skill_levels.values():
			completed_skill_level_total += int(level)
	if fusion_room == 0 and GameManager.active_fusion_id != "":
		fusion_room = controller.current_room

func _handle_visible_modal() -> bool:
	_release_movement()
	var level_up := game.get_node("LevelUpSelect") as CanvasLayer
	if level_up.visible:
		_accept_focused_default(level_up)
		return true
	var fragment := game.get_node("FragmentSelect") as FragmentSelect
	if fragment.visible:
		_choose_attribute_reward(fragment)
		return true
	var concept_select := game.get_node("ConceptSelect") as ConceptSelect
	if concept_select.visible:
		_choose_concept_reward(concept_select)
		return true
	var concept_board := game.get_node("ConceptBoard") as ConceptBoard
	if concept_board.visible:
		_drive_concept_board(concept_board)
		return true
	var item_select := game.get_node("ItemSelect") as CanvasLayer
	if item_select.visible:
		_accept_focused_default(item_select)
		return true
	var room_select := game.get_node("RoomSelect") as RoomSelect
	if room_select.visible:
		_choose_next_room(room_select)
		return true
	return false

func _choose_attribute_reward(fragment: FragmentSelect) -> void:
	if not _ui_ready():
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null:
		_focus_first_button(fragment)
		return
	var choice: Dictionary = focus.get_meta("reward_choice", {})
	var owned := GameManager.get_active_element_ids()
	var wants_second := owned.size() == 1 and GameManager.get_element_stack(owned[0]) >= 3
	if wants_second and (String(choice.get("kind", "")) != "element" or GameManager.get_element_stack(String(choice.get("element_id", ""))) > 0):
		_tap("ui_focus_next")
		return
	attribute_rewards += 1
	_tap("ui_accept")

func _choose_concept_reward(_select: ConceptSelect) -> void:
	if not _ui_ready():
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null:
		_focus_first_button(_select)
		return
	treasure_rewards += 1
	_tap("ui_accept")

func _needed_concept_types() -> Array[String]:
	var concept := game.get_node("ConceptSystem") as ConceptSystem
	var needed: Array[String] = []
	for chain_index in concept.chains.size():
		for slot_type in ["trigger", "skill", "modifier"]:
			if String(concept.get_chain(chain_index).get(slot_type, "")) == "" and slot_type not in needed:
				needed.append(slot_type)
	return needed

func _drive_concept_board(board: ConceptBoard) -> void:
	if not _ui_ready():
		return
	var concept := game.get_node("ConceptSystem") as ConceptSystem
	var desired: ConceptData = null
	var desired_chain := -1
	for chain_index in concept.chains.size():
		for slot_type in ["trigger", "skill", "modifier"]:
			if String(concept.get_chain(chain_index).get(slot_type, "")) != "":
				continue
			var owned := concept.get_owned_concepts(slot_type)
			if not owned.is_empty():
				desired = owned[0]
				desired_chain = chain_index
				break
		if desired:
			break
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null:
		_focus_first_button(board)
		return
	if desired:
		if board._selected_chain != desired_chain or board._selected_slot != desired.concept_type:
			var selected_focus_slot := String(focus.get_meta("slot_type", ""))
			var selected_focus_chain := int(focus.get_meta("chain_index", -1))
			if selected_focus_slot == desired.concept_type and selected_focus_chain == desired_chain:
				_tap("ui_accept")
			else:
				_focus_concept_slot(board, desired_chain, desired.concept_type)
			return
		var focus_slot := String(focus.get_meta("slot_type", ""))
		var focus_chain := int(focus.get_meta("chain_index", -1))
		if focus_slot == desired.concept_type and focus_chain == desired_chain:
			_focus_owned_concept(board, desired.id)
			return
		if String(focus.get_meta("concept_id", "")) == desired.id:
			_tap("ui_accept")
			return
		_focus_owned_concept(board, desired.id)
		return
	if focus == board.done_button:
		_tap("ui_accept")
	else:
		board.done_button.grab_focus()

func _focus_concept_slot(board: ConceptBoard, chain_index: int, slot_type: String) -> void:
	for child in board.chain_rows.find_children("*", "Button", true, false):
		var button := child as Button
		if int(button.get_meta("chain_index", -1)) == chain_index and String(button.get_meta("slot_type", "")) == slot_type:
			button.grab_focus()
			return

func _focus_owned_concept(board: ConceptBoard, concept_id: String) -> void:
	for child in board.owned_grid.find_children("*", "Button", true, false):
		var button := child as Button
		if String(button.get_meta("concept_id", "")) == concept_id:
			button.grab_focus()
			return

func _choose_next_room(_room_select: RoomSelect) -> void:
	if not _ui_ready():
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null:
		_focus_first_button(_room_select)
		return
	var choice: Dictionary = focus.get_meta("room_choice", {})
	var next_room := controller.current_room + 1
	var desired := "final_boss" if next_room >= controller.total_rooms else "boss" if next_room % 4 == 0 else "combat"
	if String(choice.get("type", "")) != desired:
		_tap("ui_focus_next")
		return
	_tap("ui_accept")

func _drive_reward() -> void:
	if not is_instance_valid(controller._active_chest):
		return
	var offset := controller._active_chest.global_position - player.global_position
	if offset.length() > 68.0:
		_set_movement(_navigation_direction(player.global_position, controller._active_chest.global_position))
		return
	_release_movement()
	if _ui_ready():
		_tap("interact")

func _drive_combat() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies").filter(func(enemy):
		return is_instance_valid(enemy) and enemy.get_node_or_null("HealthComponent") != null and (enemy.get_node("HealthComponent") as HealthComponent).current_hp > 0.0
	)
	if enemies.is_empty():
		_release_movement()
		return
	var nearest := enemies[0] as Node2D
	var nearest_distance := player.global_position.distance_to(nearest.global_position)
	for enemy_variant in enemies:
		var enemy := enemy_variant as Node2D
		var distance := player.global_position.distance_to(enemy.global_position)
		if distance < nearest_distance:
			nearest = enemy
			nearest_distance = distance
	var approach_direction := _navigation_direction(player.global_position, nearest.global_position)
	var direction := Vector2.ZERO
	# Soldierの近接通常攻撃が確実に届く距離まで入り、範囲内では静止する。
	# 横周回を続けると攻撃Windup中に向きが変わり、計測Botだけが空振りを重ねる。
	if nearest_distance > 42.0:
		direction = approach_direction
	_set_movement(direction)
	if _ui_ready() and player.active_skill_component.cooldown_remaining <= 0.0:
		_tap("active_skill")

func _navigation_direction(from: Vector2, to: Vector2) -> Vector2:
	var map := GameManager.dungeon_map
	var direct := to - from
	if map == null or _clear_floor_line(map, from, to):
		return direct.normalized()
	var start := map.world_to_grid(from)
	var goal := map.world_to_grid(to)
	if not map.is_floor(start) or not map.is_floor(goal):
		return direct.normalized()
	var frontier: Array[Vector2i] = [start]
	var cursor := 0
	var came_from: Dictionary = {start: start}
	var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	while cursor < frontier.size():
		var current := frontier[cursor]
		cursor += 1
		if current == goal:
			break
		for grid_direction in directions:
			var next := current + grid_direction
			if (next == goal or _test_navigation_clearance(map, next)) and not came_from.has(next):
				came_from[next] = current
				frontier.append(next)
	if not came_from.has(goal):
		return direct.normalized()
	var step := goal
	while came_from.get(step, start) != start:
		step = came_from[step]
	return (map.grid_to_world(step) - from).normalized()

func _clear_floor_line(map: DungeonMap, from: Vector2, to: Vector2) -> bool:
	var distance := from.distance_to(to)
	var steps := maxi(1, int(ceil(distance / (DungeonMap.CELL_WORLD_SIZE * 0.45))))
	for index in range(steps + 1):
		var cell := map.world_to_grid(from.lerp(to, float(index) / float(steps)))
		if index > 0 and index < steps and not _test_navigation_clearance(map, cell):
			return false
	return true

func _test_navigation_clearance(map: DungeonMap, cell: Vector2i) -> bool:
	if not map.is_floor(cell):
		return false
	for y in range(-1, 2):
		for x in range(-1, 2):
			if not map.is_floor(cell + Vector2i(x, y)):
				return false
	return true

func _handle_result() -> void:
	_release_movement()
	var result := game.get_node("ResultScreen") as ResultScreen
	if not result.visible:
		return
	if result.title_label.text != "クリア！":
		_finish_with_failure("normal run ended before the clear result")
		return
	_result_seen = true
	if _ui_ready():
		# Default focus is Retry; one keyboard focus step selects Title.
		var focus := get_viewport().gui_get_focus_owner()
		if focus == null:
			_focus_first_button(result)
			return
		if focus == result.title_button:
			_tap("ui_accept")
		else:
			_tap("ui_focus_next")

func _accept_focused_default(root: Node) -> void:
	if not _ui_ready():
		return
	if get_viewport().gui_get_focus_owner() == null:
		_focus_first_button(root)
	else:
		_tap("ui_accept")

func _focus_first_button(root: Node) -> void:
	for child in root.find_children("*", "Button", true, false):
		var button := child as Button
		if button.visible and not button.disabled:
			button.grab_focus()
			return

func _set_movement(direction: Vector2) -> void:
	if direction.x < -0.18: Input.action_press("ui_left", -direction.x)
	else: Input.action_release("ui_left")
	if direction.x > 0.18: Input.action_press("ui_right", direction.x)
	else: Input.action_release("ui_right")
	if direction.y < -0.18: Input.action_press("ui_up", -direction.y)
	else: Input.action_release("ui_up")
	if direction.y > 0.18: Input.action_press("ui_down", direction.y)
	else: Input.action_release("ui_down")

func _release_movement() -> void:
	for action in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		Input.action_release(action)

func _ui_ready() -> bool:
	return _tap_action == "" and Time.get_ticks_msec() >= _next_ui_tick

func _tap(action: String) -> void:
	if not _ui_ready():
		return
	var action_event := InputEventAction.new()
	action_event.action = action
	action_event.pressed = true
	Input.parse_input_event(action_event)
	_tap_action = action
	_tap_release_frames = 2
	_next_ui_tick = Time.get_ticks_msec() + 90

func _release_pending_tap() -> void:
	if _tap_action == "":
		return
	_tap_release_frames -= 1
	if _tap_release_frames <= 0:
		_release_tap_event()
		_tap_action = ""

func _finish_with_failure(message: String) -> void:
	if message not in failures:
		failures.append(message)
	_finish()

func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	if not _game_seen:
		failures.append("normal Title/Home/Game entry was not reached")
	if not _result_seen:
		failures.append("RUN CLEAR result was not reached")
	if not _title_exit_seen and _result_seen:
		failures.append("Result could not return to Title by keyboard")
	if last_room < 36:
		failures.append("normal run stopped before ROOM 36")
	if GameManager.active_fusion_id == "" and fusion_room == 0:
		failures.append("focused Attribute route did not complete a Fusion")
	if completed_skill_count < 1:
		failures.append("normal treasure rewards did not grant a completed skill")
	if completed_skill_count > ConceptSystem.MAX_COMPLETED_SKILLS:
		failures.append("completed skill ownership exceeded the six-skill cap")
	if completed_skill_level_total <= completed_skill_count:
		failures.append("duplicate completed skill reward did not produce a level-up")
	Engine.time_scale = 1.0
	get_tree().paused = false
	_release_movement()
	if _tap_action != "":
		_release_tap_event()
	var durations: Array[float] = []
	for value in room_durations.values():
		durations.append(float(value))
	var average: float = float(durations.reduce(func(sum, value): return float(sum) + float(value), 0.0)) / maxf(float(durations.size()), 1.0)
	print("NORMAL_RUN_PLAYER_INPUT_CHECK failures=%d rooms=%d avg_room=%.2f durations=%s bosses=%s attributes=%d treasures=%d fusion_room=%d fusion=%s completed_skills=%d skill_levels=%d max_combo=%d kills=%d wall_seconds=%.2f" % [failures.size(), last_room, average, room_durations, boss_ids_by_room, attribute_rewards, treasure_rewards, fusion_room, GameManager.active_fusion_id, completed_skill_count, completed_skill_level_total, max_combo, GameManager.kill_count, float(Time.get_ticks_msec() - _started_wall_msec) / 1000.0])
	for failure in failures:
		push_error("NORMAL_RUN_PLAYER_INPUT_CHECK: %s" % failure)
	_shutdown_after_cleanup.call_deferred(0 if failures.is_empty() else 1)

func _shutdown_after_cleanup(exit_code: int) -> void:
	AudioManager.stop_all(false)
	game = null
	controller = null
	player = null
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.25, true, false, true).timeout
	get_tree().quit(exit_code)

func _release_tap_event() -> void:
	var action_event := InputEventAction.new()
	action_event.action = _tap_action
	action_event.pressed = false
	Input.parse_input_event(action_event)

func _print_status_if_due() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_status_msec < 10000:
		return
	_last_status_msec = now
	var scene := get_tree().current_scene
	if game and is_instance_valid(game) and controller and player:
		var visible_ui: Array[String] = []
		for node_name in ["LevelUpSelect", "FragmentSelect", "ConceptSelect", "ConceptBoard", "ItemSelect", "RoomSelect", "ResultScreen"]:
			var ui := game.get_node_or_null(node_name) as CanvasLayer
			if ui and ui.visible:
				visible_ui.append(node_name)
		var enemies := get_tree().get_nodes_in_group("enemies")
		var enemy_note := ""
		if enemies.size() == 1 and is_instance_valid(enemies[0]):
			var last_enemy := enemies[0] as Node2D
			var last_health := last_enemy.get_node_or_null("HealthComponent") as HealthComponent
			enemy_note = " last_hp=%.1f dist=%.1f enemy_pos=%s player_pos=%s" % [last_health.current_hp if last_health else -1.0, player.global_position.distance_to(last_enemy.global_position), last_enemy.global_position, player.global_position]
		print("NORMAL_RUN_INPUT status room=%d state=%d hp=%.1f enemies=%d modal=%s focus=%s elapsed=%.1f%s" % [controller.current_room, controller.state, player.health_component.current_hp, enemies.size(), visible_ui, get_viewport().gui_get_focus_owner(), GameManager.elapsed_seconds, enemy_note])
	else:
		print("NORMAL_RUN_INPUT status scene=%s paused=%s" % [scene.name if scene else "null", get_tree().paused])
