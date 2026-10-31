extends Node
class_name MapRunController
## 通常製品Run専用の3MAP探索進行。既存ROOM Controllerは呼ばずに保持し、
## DungeonGenerator/StageEnvironment/Wave/Elite/Boss/Reward UIだけを再利用する。

const CONFIG_PATH := "res://data/maps/exploration_run.json"
const TREASURE_CHEST_SCENE := preload("res://entities/pickups/treasure_chest.tscn")
const LANDMARK_SCRIPT := preload("res://entities/stage_environment/map_landmark.gd")

@export var stage_environment_path: NodePath
@export var player_path: NodePath
@export var wave_spawner_path: NodePath
@export var boss_spawner_path: NodePath
@export var elite_room_manager_path: NodePath
@export var hud_path: NodePath
@export var concept_system_path: NodePath
@export var combo_system_path: NodePath
@export var equipment_drop_system_path: NodePath
@export var heart_drop_system_path: NodePath
@export var shop_screen_path: NodePath

@onready var stage_environment: StageEnvironment = get_node(stage_environment_path)
@onready var player: Player = get_node(player_path)
@onready var wave_spawner: WaveSpawner = get_node(wave_spawner_path)
@onready var boss_spawner: BossSpawner = get_node(boss_spawner_path)
@onready var elite_room_manager: EliteRoomManager = get_node(elite_room_manager_path)
@onready var hud: HUD = get_node(hud_path)
@onready var concept_system: ConceptSystem = get_node(concept_system_path)
@onready var combo_system: ComboSystem = get_node(combo_system_path)
@onready var equipment_drop_system: EquipmentDropSystem = get_node(equipment_drop_system_path)
@onready var heart_drop_system: HeartDropSystem = get_node(heart_drop_system_path)
@onready var shop_screen: ShopScreen = get_node(shop_screen_path)

var _config: Dictionary = {}
var _maps: Array = []
var _current_config: Dictionary = {}
var _map_started_at := 0.0
var _map_kills := 0
var _boss_unlocked := false
var _boss_active := false
var _transitioning := false
var _active := false
var _boss_gate: MapLandmark = null
var _floor_index := 1
var _stairs: MapLandmark = null
var _boss_chest: TreasureChest = null
var _boss_loot_position := Vector2.ZERO
var _reward_by_chest_id: Dictionary = {}
var _status_update_timer := 0.0
var _transition_layer: CanvasLayer = null
var _transition_label: Label = null
var _last_transition_profile: Dictionary = {}
var _surge_config: Dictionary = {}
var _surge_active := false
var _surge_remaining := 0.0
var _surge_index := 0
var _surge_trigger_reason := ""
var _surge_reward_count := 0
var _surge_end_message_remaining := 0.0
var _sector_mode := false
var _sector_index := 0
var _sector_total := 4
var _sector_room_index := 0
var _sector_room_order: Array[int] = []
var _sector_chest_rooms: Dictionary = {}
var _sector_chest: TreasureChest = null
var _sector_exit: MapLandmark = null
var _sector_seals: Node2D = null
var _sector_cleared := false

func _ready() -> void:
	EventBus.enemy_died.connect(_on_enemy_died)
	boss_spawner.room_boss_defeated.connect(_on_map_boss_defeated, CONNECT_DEFERRED)
	wave_spawner.sector_wave_cleared.connect(_on_sector_wave_cleared)

func begin_run() -> void:
	if not GameManager.map_mode_active:
		return
	_config = _read_json(CONFIG_PATH)
	_maps = _config.get("maps", [])
	_surge_config = Dictionary(_config.get("surge", {})).duplicate(true)
	if _maps.is_empty():
		push_error("MapRunController: MAP設定がありません")
		return
	_active = true
	_transitioning = false
	# game.tscnでは旧ROOMの手動Wave/Test Lab sandboxを守るため両NodeをDisabledで
	# 配置している。連続MAP探索だけは自然Spawn/Elite Areaを処理する必要がある。
	wave_spawner.process_mode = Node.PROCESS_MODE_INHERIT
	elite_room_manager.process_mode = Node.PROCESS_MODE_INHERIT
	combo_system.configure_timeout(float(_config.get("combo_timeout_seconds", 3.5)))
	combo_system.set_active(true)
	concept_system.set_active(true)
	player.experience_component.set_requirement_multiplier(float(_config.get("experience_requirement_multiplier", 1.25)))
	boss_spawner.prepare_map_run()
	_create_transition_overlay()
	if GameManager.survival_mode_active:
		_start_survival()
	else:
		_start_map(1, 1)

func _process(delta: float) -> void:
	if not _active or _transitioning or not GameManager.map_mode_active or GameManager.run_state != GameManager.RunState.PLAYING:
		return
	if GameManager.survival_mode_active:
		_status_update_timer -= delta
		if _status_update_timer <= 0.0:
			_status_update_timer = 0.25
			_tick_survival()
		return
	if _surge_end_message_remaining > 0.0:
		_surge_end_message_remaining = maxf(_surge_end_message_remaining - delta, 0.0)
	if _surge_active and not wave_spawner.is_map_spawn_suppressed():
		_surge_remaining = maxf(_surge_remaining - delta, 0.0)
		if _surge_remaining <= 0.0:
			_finish_surge()
	_status_update_timer -= delta
	if _status_update_timer <= 0.0:
		_status_update_timer = 0.25
		_update_progress()

var _survival_boss_index := 0
var _survival_supply_index := 0
var _survival_boss_phase := false

func _start_survival() -> void:
	GameManager.elapsed_seconds = 0.0
	_current_config = _get_map_config(GameManager.current_map_index)
	_map_started_at = GameManager.elapsed_seconds
	_map_kills = 0
	_sector_mode = false
	_boss_reward_pending = false
	_survival_boss_index = 0
	_survival_supply_index = 0
	_survival_boss_phase = false
	wave_spawner.configure_map_phase(_current_config)
	elite_room_manager.clear_map_runtime()
	elite_room_manager.process_mode = Node.PROCESS_MODE_DISABLED
	stage_environment.set_boss_seal_visible(false)
	_setup_survival_map_overlay()
	_tick_survival()
	hud.set_room_message("群れを倒し、終盤のボスを撃破！　移動で自動攻撃")
	EventBus.map_started.emit(GameManager.current_map_index, _maps.size(), String(_current_config.get("display_name", "")))

func _tick_survival() -> void:
	var elapsed := GameManager.elapsed_seconds
	var boss_at := float(_config.get("survival_boss_seconds", [240])[0])
	if not GameManager.survival_completed:
		if elapsed >= boss_at and _survival_boss_index == 0:
			if not _survival_boss_phase:
				_survival_boss_phase = true
				wave_spawner.set_spawning_paused(true)
				_clear_combat_transients(true)
			var point := wave_spawner._pick_spawn_position(player.global_position)
			if point.is_finite():
				var boss := boss_spawner.start_room_boss(GameManager.current_map_index, {
					"candidates": _current_config.get("boss_candidates", []),
					"hp_multiplier": 1.0,
					"damage_multiplier": 1.0,
					"is_final": true,
				}, point)
				if boss:
					_boss_active = true
					_survival_boss_index = 1
		if not _survival_boss_phase:
			var supply_times: Array = _current_config.get("survival_supply_seconds", _config.get("survival_supply_seconds", [75, 150]))
			if _survival_supply_index < supply_times.size() and elapsed >= float(supply_times[_survival_supply_index]):
				var point := wave_spawner._pick_spawn_position(player.global_position)
				if point.is_finite():
					if _survival_supply_index > 0 or randf() < 0.6:
						_spawn_treasure(point, "normal", "supply_equipment" if _survival_supply_index > 0 else "equipment", false)
					_survival_supply_index += 1
	var phase := "群れを倒して成長" if elapsed < 120 else "密度上昇：包囲を抜けて戦う"
	if _survival_boss_phase: phase = "ボスを倒せ！　5分を過ぎても撃破まで継続"
	if GameManager.survival_completed:
		phase = "ボス撃破！　宝箱と装備を回収" if _boss_reward_pending else "装備を回収し、帰還の階段へ [E]"
	GameManager.dungeon_map.set_meta("objective_text", phase)
	hud.set_survival_status(String(_current_config.get("display_name", "")), elapsed, boss_at, _map_kills, phase, _survival_boss_phase)

func _finish_survival() -> void:
	GameManager.survival_completed = true
	for item: GroundEquipmentItem in get_tree().get_nodes_in_group("ground_equipment"):
		item._cancel_cap_expiration()
	wave_spawner.set_spawning_paused(true)
	elite_room_manager.process_mode = Node.PROCESS_MODE_DISABLED
	boss_spawner.clear_room_boss()
	_clear_combat_transients(true)
	_boss_active = false
	player.weapon_manager.cancel_current_attack()
	player.health_component.invincible = true
	_boss_reward_pending = true
	var point := equipment_drop_system._find_safe_drop_position(player.global_position + Vector2(160, 0))
	_boss_chest = _spawn_treasure(point, "rare", "boss_equipment", true)
	_boss_chest.name_override = "討伐報酬"
	_boss_chest._update_label()
	_boss_loot_position = _boss_exit_position(point, false)
	_stairs = _spawn_landmark("descent_stairs", "帰還の階段", Color("d9b973"), _boss_exit_position(point, true), false)
	EventBus.map_completed.emit(GameManager.current_map_index, GameManager.elapsed_seconds, _map_kills)

func _start_map(map_index: int, floor_index: int = 1) -> void:
	_floor_index = floor_index
	GameManager.current_floor_index = floor_index
	GameManager.current_depth = (map_index - 1) * _floors_per_map() + floor_index
	_current_config = _get_map_config(map_index)
	var progress := float(GameManager.current_depth - 1)
	_current_config["enemy_hp_multiplier"] = float(_current_config.get("enemy_hp_multiplier", 1.0)) * (1.0 + progress * 0.028)
	_current_config["enemy_damage_multiplier"] = float(_current_config.get("enemy_damage_multiplier", 1.0)) * (1.0 + progress * 0.02)
	_current_config["boss_hp_multiplier"] = float(_current_config.get("boss_hp_multiplier", 1.0)) * (1.0 + progress * 0.035)
	_current_config["boss_damage_multiplier"] = float(_current_config.get("boss_damage_multiplier", 1.0)) * (1.0 + progress * 0.02)
	_current_config["enemy_cap"] = mini(int(_current_config.get("enemy_cap", 64)) + floori(progress * 0.7), 128)
	_current_config["boss_kill_requirement"] = int(_current_config.get("boss_kill_requirement", 120)) + (_floor_index - 1) * 3
	if _current_config.is_empty():
		push_error("MapRunController: MAP %d 設定がありません" % map_index)
		return
	GameManager.current_map_index = map_index
	_map_started_at = GameManager.elapsed_seconds
	_map_kills = 0
	_boss_unlocked = false
	_boss_active = false
	_boss_reward_pending = false
	_reward_by_chest_id.clear()
	_stairs = null
	_boss_chest = null
	_boss_loot_position = Vector2.ZERO
	_surge_active = false
	_surge_remaining = 0.0
	_surge_index = 0
	_surge_trigger_reason = ""
	_surge_reward_count = 0
	_surge_end_message_remaining = 0.0
	_sector_mode = bool(_config.get("sector_mode", false))
	_sector_index = 0
	_sector_room_index = 0
	_sector_room_order.clear()
	_sector_chest_rooms.clear()
	_sector_chest = null
	_sector_exit = null
	_sector_seals = null
	_sector_cleared = false
	if _sector_mode:
		_prepare_sector_rooms()
	wave_spawner.configure_map_phase(_current_config)
	if _sector_mode:
		wave_spawner.set_spawning_paused(true)
	stage_environment.set_surge_visual(false, false)
	elite_room_manager.setup(GameManager.dungeon_map)
	# A roaming elite must not invalidate the safe interval after a cleared sector.
	elite_room_manager.process_mode = Node.PROCESS_MODE_DISABLED if _sector_mode else Node.PROCESS_MODE_INHERIT
	_place_map_content()
	if _sector_mode:
		_enter_sector_room()
	_setup_survival_map_overlay()
	var total_maps := int(_config.get("total_maps", _maps.size()))
	var map_name := String(_current_config.get("display_name", "MAP %d" % map_index))
	hud.set_map_status(GameManager.current_depth, int(_config.get("total_floors", 60)), "%s  地下%d層" % [map_name, floor_index], 0.0, float(_current_config.get("boss_fallback_seconds", 900.0)), 0, int(_current_config.get("boss_kill_requirement", 420)), false)
	if _sector_mode:
		hud.set_room_message("敵を全滅させ、宝箱を調べてから出口へ")
	elif GameManager.dungeon_map.get_meta("exploration_layout", false):
		_update_exploration_progress()
		hud.set_room_message("脇道を探索し、封印の鍵を探す　[M] 探索図")
	else:
		hud.set_room_message("通常攻撃は自動。群れを倒してボス領域を解放　[K] 回避　[L] 技")
	if not _sector_mode:
		_clear_hud_message_later(2.6)
	EventBus.map_started.emit(GameManager.current_depth, int(_config.get("total_floors", 60)), "%s  地下%d層" % [map_name, floor_index])

func _update_progress() -> void:
	if GameManager.survival_mode_active:
		_tick_survival()
		return
	if _sector_mode:
		_update_sector_progress()
		return
	if GameManager.dungeon_map.get_meta("exploration_layout", false):
		_update_exploration_progress()
		return
	var elapsed := maxf(GameManager.elapsed_seconds - _map_started_at, 0.0)
	var fallback_seconds := float(_current_config.get("boss_fallback_seconds", 900.0))
	var required_kills := int(_current_config.get("boss_kill_requirement", 420))
	_try_start_next_surge(elapsed, required_kills)
	# Run時間を固定Timerで作らない。通常は戦闘進行で解放し、長時間撃破できない
	# Buildだけ救済時刻で詰みを回避する。開始には最深部Boss AreaでE/Xが必要。
	if not _boss_unlocked and (_map_kills >= required_kills or elapsed >= fallback_seconds):
		_boss_unlocked = true
		if is_instance_valid(_boss_gate):
			_boss_gate.set_available(true)
		hud.set_room_message("ボス領域の封印が解けました。MAP最深部へ向かってください")
		EventBus.map_boss_unlocked.emit(GameManager.current_map_index)
	var map_name := "%s  地下%d / %d層" % [String(_current_config.get("display_name", "")), _floor_index, _floors_per_map()]
	var objective := "敵を倒してボス領域を解放" if not _boss_unlocked else "封印解除：ボス領域へ [M]"
	if _boss_active: objective = "ボスを倒す"
	elif _boss_reward_pending: objective = "装備を拾い、ボス宝箱を開く"
	elif is_instance_valid(_stairs): objective = "装備を拾い、階段を下りる [E]"
	hud.set_map_status(GameManager.current_map_index, int(_config.get("total_maps", 3)), map_name, elapsed, fallback_seconds, _map_kills, required_kills, _boss_unlocked, objective if _boss_active or _boss_reward_pending or is_instance_valid(_stairs) else "")
	GameManager.dungeon_map.set_meta("objective_text", objective)
	if _boss_active or _boss_unlocked: hud.set_room_message(objective)
	if _surge_active:
		hud.set_room_message("⚠ 侵攻 %d / 2　残り %d秒　敵密度上昇" % [_surge_index + 1, ceili(_surge_remaining)])
	elif _surge_end_message_remaining > 0.0:
		hud.set_room_message("侵攻を退けた！　確定報酬が出現")
	EventBus.map_progress_changed.emit(GameManager.current_map_index, elapsed, fallback_seconds, _map_kills, required_kills)

func _on_enemy_died(_enemy_data: Resource, _death_position: Vector2) -> void:
	if _active and not _transitioning and GameManager.map_mode_active:
		_map_kills += 1

func _start_sector_wave(rank: String) -> void:
	var count := 11 + mini(GameManager.current_depth / 4, 14) + _sector_index * 5
	if rank == "strong": count += 5
	var power := 1.18 if rank == "strong" else 1.05 if rank == "standard" else 1.0
	wave_spawner.start_sector_wave(_sector_room_index, count, rank, power)
	hud.set_room_message("戦闘区画 %d / %d　敵を殲滅" % [_sector_index + 1, _sector_total])

func _prepare_sector_rooms() -> void:
	var map := GameManager.dungeon_map
	if map.get_meta("isolated_room", false):
		_sector_total = 4
		_sector_room_order.assign([0, 0, 0, 0])
		var choices: Array[int] = [0, 1, 2, 3]
		choices.shuffle()
		_sector_chest_rooms[choices[0]] = true
		_sector_chest_rooms[choices[1]] = true
		return
	_sector_room_order.append(0)
	var candidates: Array[int] = []
	for index in range(1, map.rooms.size()):
		if index != map.boss_room_index:
			candidates.append(index)
	candidates.sort_custom(func(a: int, b: int): return _room_distance_squared(map, a) < _room_distance_squared(map, b))
	_sector_total = mini(int(_config.get("sectors_per_floor", 4)), candidates.size() + 1)
	for index in range(_sector_total - 1):
		_sector_room_order.append(candidates[index])
	var chest_candidates: Array[int] = []
	for index in range(_sector_total):
		chest_candidates.append(index)
	chest_candidates.shuffle()
	for index in range(maxi(1, ceili(float(_sector_total) * 0.5))):
		_sector_chest_rooms[chest_candidates[index]] = true

func _enter_sector_room() -> void:
	_sector_room_index = _sector_room_order[_sector_index]
	_sector_cleared = false
	_sector_chest = null
	var map := GameManager.dungeon_map
	_build_sector_seals(map.rooms[_sector_room_index])
	var center := _room_position(map, _sector_room_index)
	_sector_exit = _spawn_landmark("room_exit", "次の部屋への扉", Color("83cbd3"), _sector_exit_position(_sector_room_index), false)
	stage_environment.set_room_exit_wall(_sector_exit.global_position)
	if _sector_chest_rooms.has(_sector_index):
		var rarity := "rare" if randf() < 0.18 + 0.08 * (GameManager.current_map_index - 1) else "normal"
		_sector_chest = _spawn_treasure(_sector_feature_position(_sector_room_index, center + Vector2(-112, 72)), rarity, "equipment", false)
		_sector_chest.set_available(false)
	_start_sector_wave("mob" if _sector_index == 0 else "standard" if _sector_index < _sector_total - 1 else "strong")

func _sector_exit_position(room_index: int) -> Vector2:
	var map := GameManager.dungeon_map
	var room: Rect2i = map.rooms[room_index]
	var x := room.position.x + room.size.x / 2
	# Choose a real north wall rather than a corridor mouth or an interior floor.
	for offset in range(room.size.x / 2 - 2):
		for candidate in [x + offset, x - offset]:
			if not map.is_floor(Vector2i(candidate, room.position.y - 1)) and map.is_floor(Vector2i(candidate, room.position.y + 1)):
				return map.grid_to_world(Vector2i(candidate, room.position.y)) - Vector2(0, 16)
	return map.grid_to_world(Vector2i(x, room.position.y)) - Vector2(0, 16)

func _sector_feature_position(room_index: int, desired: Vector2) -> Vector2:
	var map := GameManager.dungeon_map
	var cells := map.get_spawn_cells(map.rooms[room_index].grow(-3))
	var room_center := _room_position(map, room_index)
	var best := room_center
	var best_score := INF
	var shape := CircleShape2D.new()
	shape.radius = 22.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1
	for cell in cells:
		var point := map.grid_to_world(cell)
		if point.distance_to(room_center) < 80.0:
			continue
		if is_instance_valid(_sector_exit) and point.distance_to(_sector_exit.global_position) < 160.0:
			continue
		var score := point.distance_squared_to(desired)
		if score >= best_score:
			continue
		query.transform = Transform2D(0.0, point)
		if not player.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
			continue
		if score < best_score:
			best_score = score
			best = point
	return best

func _build_sector_seals(room: Rect2i) -> void:
	if is_instance_valid(_sector_seals):
		_sector_seals.queue_free()
	_sector_seals = Node2D.new()
	_sector_seals.name = "RoomSeals"
	_sector_seals.add_to_group("map_content")
	GameManager.get_runtime_world(self).add_child(_sector_seals)
	var map := GameManager.dungeon_map
	var first := map.grid_to_world(room.position)
	var last := map.grid_to_world(room.end - Vector2i.ONE)
	var left := first.x - 16.0
	var right := last.x + 16.0
	var top := first.y - 16.0
	var bottom := last.y + 16.0
	for edge in [
		{"position": Vector2((left + right) * 0.5, top), "size": Vector2(right - left, 12)},
		{"position": Vector2((left + right) * 0.5, bottom), "size": Vector2(right - left, 12)},
		{"position": Vector2(left, (top + bottom) * 0.5), "size": Vector2(12, bottom - top)},
		{"position": Vector2(right, (top + bottom) * 0.5), "size": Vector2(12, bottom - top)},
	]:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = edge.position
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = edge.size
		collision.shape = shape
		body.add_child(collision)
		_sector_seals.add_child(body)
	for x in range(room.position.x, room.end.x):
		for y in [room.position.y, room.end.y - 1]:
			var inside := Vector2i(x, y)
			var outside := inside + (Vector2i.UP if y == room.position.y else Vector2i.DOWN)
			if map.is_floor(inside) and map.is_floor(outside):
				_add_sector_seal_mark((map.grid_to_world(inside) + map.grid_to_world(outside)) * 0.5, true)
	for y in range(room.position.y, room.end.y):
		for x in [room.position.x, room.end.x - 1]:
			var inside := Vector2i(x, y)
			var outside := inside + (Vector2i.LEFT if x == room.position.x else Vector2i.RIGHT)
			if map.is_floor(inside) and map.is_floor(outside):
				_add_sector_seal_mark((map.grid_to_world(inside) + map.grid_to_world(outside)) * 0.5, false)

func _add_sector_seal_mark(position: Vector2, horizontal: bool) -> void:
	var line := Line2D.new()
	line.width = 3.0
	line.default_color = Color("69878d", 0.55)
	line.position = position
	line.add_point(Vector2(-16, 0) if horizontal else Vector2(0, -16))
	line.add_point(Vector2(16, 0) if horizontal else Vector2(0, 16))
	_sector_seals.add_child(line)

func _on_sector_wave_cleared() -> void:
	if not _active or not _sector_mode or _boss_active or _transitioning:
		return
	_sector_cleared = true
	if is_instance_valid(_sector_chest) and not _sector_chest.is_opened:
		_sector_chest.set_available(true)
		hud.set_room_message("区画制圧　宝箱を開けてから出口へ")
	else:
		_sector_exit.set_available(true)
		hud.set_room_message("区画制圧　扉を調べて次の部屋へ")

func _enter_room_exit(door: MapLandmark) -> void:
	if _transitioning or not _sector_cleared or (is_instance_valid(_sector_chest) and not _sector_chest.is_opened):
		return
	_transitioning = true
	var was_processing := player.is_processing()
	var was_physics_processing := player.is_physics_processing()
	var old_weapon_mode := player.weapon_manager.process_mode
	var old_color := player.modulate
	player.weapon_manager.cancel_current_attack()
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	player.set_movement_locked(true)
	player.set_process(false)
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	player.animation_component.set_pose_controlled(true)
	var sprite := player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	if sprite.sprite_frames.has_animation("walk"):
		sprite.play("walk")
	door._label.hide()
	var approach := door.global_position + Vector2(0, 32)
	var tween := create_tween()
	tween.tween_property(player, "global_position", approach, clampf(player.global_position.distance_to(approach) / 180.0, 0.12, 0.6))
	tween.tween_property(player, "global_position", door.global_position + Vector2(0, -14), 0.42)
	tween.parallel().tween_property(player, "modulate:a", 0.0, 0.15).set_delay(0.27)
	await tween.finished
	player.animation_component.set_pose_controlled(false)
	player.weapon_manager.process_mode = old_weapon_mode
	player.set_process(was_processing)
	player.set_physics_process(was_physics_processing)
	player.set_movement_locked(false)
	_transitioning = false
	_advance_sector_room()
	player.modulate = old_color

func _advance_sector_room() -> void:
	if _transitioning or not _sector_cleared or (is_instance_valid(_sector_chest) and not _sector_chest.is_opened):
		return
	if GameManager.dungeon_map.get_meta("isolated_room", false):
		_load_isolated_room(_sector_index + 1)
		return
	_clear_combat_transients(false)
	if is_instance_valid(_sector_seals):
		_sector_seals.queue_free()
	_sector_seals = null
	if is_instance_valid(_sector_exit):
		_sector_exit.queue_free()
	_sector_exit = null
	if _sector_index + 1 >= _sector_total:
		_unlock_sector_boss()
		player.global_position = _room_position(GameManager.dungeon_map, GameManager.dungeon_map.boss_room_index, Vector2(-72, 0))
	else:
		_sector_index += 1
		player.global_position = _room_position(GameManager.dungeon_map, _sector_room_order[_sector_index])
		player.velocity = Vector2.ZERO
		_enter_sector_room()

func _load_isolated_room(ordinal: int) -> void:
	if _transitioning:
		return
	_transitioning = true
	player.set_movement_locked(true)
	wave_spawner.stop_sector_wave()
	var room_seed := int(GameManager.dungeon_map.get_meta("room_seed", 0))
	_clear_map_nodes(true)
	_sector_chest = null
	_sector_exit = null
	_sector_seals = null
	_boss_gate = null
	_reward_by_chest_id.clear()
	await get_tree().process_frame
	GameManager.dungeon_map = preload("res://systems/room_layout.gd").generate(GameManager.current_depth, ordinal, room_seed)
	_last_transition_profile = await stage_environment.build_dungeon_async(GameManager.dungeon_map, 5)
	player.global_position = GameManager.dungeon_map.grid_to_world(GameManager.dungeon_map.spawn_point)
	player.velocity = Vector2.ZERO
	player.setup_camera_limits(GameManager.dungeon_map)
	# Explicit room exit never silently discards equipment the player earned.
	var carried_index := 0
	var safe_cells := GameManager.dungeon_map.get_spawn_cells(GameManager.dungeon_map.rooms[0].grow(-2))
	safe_cells.sort_custom(func(a: Vector2i, b: Vector2i): return GameManager.dungeon_map.grid_to_world(a).distance_squared_to(player.global_position) < GameManager.dungeon_map.grid_to_world(b).distance_squared_to(player.global_position))
	var shape := CircleShape2D.new()
	shape.radius = 20.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1
	var safe_points: Array[Vector2] = []
	for cell in safe_cells:
		var point := GameManager.dungeon_map.grid_to_world(cell)
		if point.distance_to(player.global_position) < 56.0:
			continue
		query.transform = Transform2D(0.0, point)
		if player.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
			safe_points.append(point)
	for item in get_tree().get_nodes_in_group("ground_equipment"):
		if is_instance_valid(item) and not item.is_queued_for_deletion():
			item.global_position = safe_points[carried_index % safe_points.size()] if not safe_points.is_empty() else player.global_position
			carried_index += 1
	wave_spawner.configure_map_phase(_current_config)
	wave_spawner.set_spawning_paused(true)
	elite_room_manager.setup(GameManager.dungeon_map)
	_setup_survival_map_overlay()
	if ordinal >= _sector_total:
		_place_map_content()
		_unlock_sector_boss()
	else:
		_sector_index = ordinal
		_enter_sector_room()
	player.set_movement_locked(false)
	_transitioning = false
	_update_sector_progress()

func _unlock_sector_boss() -> void:
	_boss_unlocked = true
	if is_instance_valid(_boss_gate):
		_boss_gate.set_available(true)
	EventBus.map_boss_unlocked.emit(GameManager.current_map_index)
	hud.set_room_message("ボスルームへ到達。領域を調べて決戦")

func _update_sector_progress() -> void:
	var map_name := "%s  地下%d / %d層" % [String(_current_config.get("display_name", "")), _floor_index, _floors_per_map()]
	var objective := "区画 %d / %d　敵を殲滅" % [_sector_index + 1, _sector_total]
	if GameManager.dungeon_map.get_meta("isolated_room", false):
		objective = "部屋%d / 5　%s　残敵 %d" % [_sector_index + 1, String(GameManager.dungeon_map.get_meta("room_role", "")), wave_spawner._sector_remaining + wave_spawner._active_sector_enemy_count()]
	if _sector_cleared:
		objective = "宝箱を開けて出口へ" if is_instance_valid(_sector_chest) and not _sector_chest.is_opened else "出口の扉を調べる"
	if _boss_unlocked: objective = "封印解除：ボス領域へ"
	if _boss_active: objective = "ボスを倒す"
	elif _boss_reward_pending: objective = "装備を拾い、ボス宝箱を開く"
	elif is_instance_valid(_stairs): objective = "装備を拾い、階段を下りる"
	hud.set_map_status(GameManager.current_map_index, int(_config.get("total_maps", 3)), map_name, 0.0, 0.0, _sector_index, _sector_total, _boss_unlocked, objective)
	GameManager.dungeon_map.set_meta("objective_text", objective)

func _try_start_next_surge(elapsed: float, required_kills: int) -> void:
	if _boss_active or _boss_unlocked or wave_spawner.is_map_spawn_suppressed():
		return
	if not bool(_surge_config.get("enabled", true)):
		return
	if _surge_active:
		return
	var fractions: Array = _surge_config.get("kill_fractions", [0.25, 0.5, 0.75])
	var fallback_times: Array = _current_config.get("surge_fallback_seconds", [])
	if _surge_index >= fractions.size() or _surge_index >= fallback_times.size():
		return
	var kill_threshold := ceili(float(required_kills) * float(fractions[_surge_index]))
	var time_threshold := float(fallback_times[_surge_index])
	if _map_kills >= kill_threshold:
		_start_surge("kills")
	elif elapsed >= time_threshold:
		_start_surge("time")

func _start_surge(trigger_reason: String) -> void:
	if _surge_active:
		return
	var duration := clampf(float(_surge_config.get("duration_seconds", 45.0)), 40.0, 60.0)
	var interval_multiplier := clampf(float(_surge_config.get("spawn_interval_multiplier", 0.5)), 0.1, 1.0)
	var batch_multiplier := clampf(float(_surge_config.get("spawn_batch_multiplier", 1.5)), 1.0, 2.0)
	_surge_active = true
	_surge_remaining = duration
	_surge_trigger_reason = trigger_reason
	_surge_end_message_remaining = 0.0
	wave_spawner.set_map_surge(true, interval_multiplier, batch_multiplier)
	stage_environment.set_surge_visual(true)
	hud.set_room_message("⚠ 侵攻 %d / 2　敵群接近！" % [_surge_index + 1])
	AudioManager.play_sfx("boss_appear")
	EventBus.map_surge_started.emit(GameManager.current_map_index, _surge_index + 1, trigger_reason, duration)

func _finish_surge() -> void:
	if not _surge_active:
		return
	var completed_index := _surge_index
	_surge_active = false
	_surge_remaining = 0.0
	wave_spawner.set_map_surge(false)
	stage_environment.set_surge_visual(false)
	var reward := _spawn_surge_reward(completed_index)
	_surge_index += 1
	_surge_reward_count += 1
	_surge_end_message_remaining = 3.0
	hud.set_room_message("侵攻を退けた！　確定報酬が出現")
	AudioManager.play_sfx("level_up")
	EventBus.map_surge_ended.emit(GameManager.current_map_index, completed_index + 1, String(reward.get("type", "")), Vector2(reward.get("position", player.global_position)))

func _spawn_surge_reward(completed_index: int) -> Dictionary:
	var reward_sequence: Array = _surge_config.get("reward_sequence", ["recovery", "equipment", "recovery"])
	var reward_type := String(reward_sequence[completed_index % reward_sequence.size()]) if not reward_sequence.is_empty() else "recovery"
	var reward_position := _nearest_floor_world(player.global_position + Vector2(48.0, 0.0))
	if reward_type == "equipment":
		equipment_drop_system.spawn_treasure_drop(reward_position, String(_current_config.get("surge_equipment_rarity", "uncommon")))
	else:
		reward_type = "recovery"
		heart_drop_system.spawn_recovery_drop(reward_position, 0.20, 90.0)
	return {"type": reward_type, "position": reward_position}

func _place_map_content() -> void:
	var map := GameManager.dungeon_map
	if map == null or map.boss_room_index < 0 or map.boss_room_index >= map.rooms.size():
		return
	_boss_gate = _spawn_landmark("boss_gate", "ボス領域", Color("b06cff"), _room_position(map, map.boss_room_index), false)
	if _sector_mode:
		return
	if map.get_meta("exploration_layout", false):
		_place_exploration_content(map)
		return
	var room_indices: Array[int] = []
	for index in range(1, map.rooms.size()):
		if index != map.boss_room_index:
			room_indices.append(index)
	room_indices.sort_custom(func(a: int, b: int):
		return _room_distance_squared(map, a) < _room_distance_squared(map, b)
	)
	# TODO: 属性祭壇は属性システム廃止に伴い生成を停止した(触れても何も起きない
	# オブジェクトをMAP上に残さないため)。ゴールド/ショップ実装時に、
	# ショップまたは別報酬のLandmarkとして復活させる。
	# 生命の祭壇は撤去。宝箱との重複配置も発生させない。
	var rewards: Array = _current_config.get("treasure_rewards", ["equipment", "equipment", "recovery", "equipment"])
	var rarities: Array = _current_config.get("treasure_rarities", ["normal", "normal", "normal", "rare"])
	var candidates: Array[int] = room_indices.duplicate()
	# Start直後ではなく探索距離のある部屋から均等に4個配置する。
	for index in mini(rewards.size(), candidates.size()):
		var sample_index := clampi(int(round(float(index + 1) * float(candidates.size()) / float(rewards.size() + 1))), 0, candidates.size() - 1)
		var rarity := String(rarities[index]) if index < rarities.size() else "normal"
		var offset := Vector2(36 if index % 2 == 0 else -36, -24 if index % 3 == 0 else 28)
		_spawn_treasure(_room_position(map, int(candidates[sample_index]), offset), rarity, String(rewards[index]), false)

func _spawn_landmark(kind: String, display_name: String, color: Color, position: Vector2, available: bool) -> MapLandmark:
	var landmark := LANDMARK_SCRIPT.new() as MapLandmark
	landmark.configure(kind, display_name, color, available)
	landmark.activated.connect(_on_landmark_activated)
	landmark.attempted_while_locked.connect(_on_locked_landmark_attempted)
	GameManager.get_runtime_world(self).add_child(landmark)
	landmark.global_position = position
	return landmark

func _spawn_treasure(position: Vector2, rarity: String, reward_type: String, boss_chest: bool) -> TreasureChest:
	var chest := TREASURE_CHEST_SCENE.instantiate() as TreasureChest
	var color: Color = {"normal": Color("d9dde8"), "rare": Color("7fd8ff"), "legendary": Color("ffd75f")}.get(rarity, Color.WHITE)
	chest.configure(rarity, color, boss_chest)
	chest.opened.connect(_on_treasure_opened.bind(chest), CONNECT_ONE_SHOT)
	GameManager.get_runtime_world(self).add_child(chest)
	chest.global_position = position
	_reward_by_chest_id[chest.get_instance_id()] = reward_type
	return chest

func _on_landmark_activated(kind: String, landmark: MapLandmark) -> void:
	match kind:
		"room_exit":
			_enter_room_exit(landmark)
		"attribute":
			# TODO: 属性祭壇の報酬(FragmentSelect)は属性システム廃止に伴い撤去した。
			# ゴールドとショップに差し替える予定。現在この祭壇は何も付与しない。
			pass
		"recovery":
			player.health_component.heal(player.health_component.max_hp * 0.40)
			EventBus.healing_received.emit(player.health_component.max_hp * 0.40, landmark.global_position)
		"boss_gate":
			_start_map_boss()
		"descent_stairs":
			_continue_after_boss_reward.call_deferred()

func _on_locked_landmark_attempted(kind: String) -> void:
	if kind == "room_exit":
		hud.set_room_message("先に敵を全滅させてください" if not _sector_cleared else "先に宝箱を開けてください")
		return
	if kind == "descent_stairs":
		hud.set_room_message("先にボス宝箱を開けてください")
		return
	if GameManager.dungeon_map.get_meta("exploration_layout", false):
		hud.set_room_message("封印の鍵が必要。脇道の番人を探してください")
		return
	if kind != "boss_gate":
		return
	var elapsed := maxf(GameManager.elapsed_seconds - _map_started_at, 0.0)
	var seconds_left := maxi(int(ceil(float(_current_config.get("boss_fallback_seconds", 900.0)) - elapsed)), 0)
	var kills_left := maxi(int(_current_config.get("boss_kill_requirement", 420)) - _map_kills, 0)
	hud.set_room_message("封印条件：あと敵 %d体（長期探索の救済まで %d:%02d）" % [kills_left, seconds_left / 60, seconds_left % 60])

func _start_map_boss() -> void:
	if not _boss_unlocked or _boss_active or _transitioning or not is_instance_valid(_boss_gate):
		return
	if _surge_active:
		_finish_surge()
	_boss_active = true
	_boss_gate.visible = false
	stage_environment.set_boss_seal_visible(false)
	wave_spawner.stop_sector_wave()
	wave_spawner.set_spawning_paused(true)
	_clear_combat_transients(false)
	var encounter := {
		"candidates": _current_config.get("boss_candidates", []),
		"hp_multiplier": float(_current_config.get("boss_hp_multiplier", 2.0)),
		"damage_multiplier": float(_current_config.get("boss_damage_multiplier", 0.7)),
		"attack_interval_multiplier": 1.0,
		"special_interval_multiplier": 1.0,
		"status_duration_multiplier": 1.0,
		"is_final": GameManager.current_depth >= int(_config.get("total_floors", 60)),
	}
	var spawn_position := _nearest_floor_world(_boss_gate.global_position + Vector2(96, 0))
	var boss := boss_spawner.start_room_boss(GameManager.current_map_index, encounter, spawn_position)
	if boss == null:
		_boss_active = false
		_boss_gate.visible = true
		stage_environment.set_boss_seal_visible(true)
		wave_spawner._boss_fight_active = false
		wave_spawner.set_spawning_paused(false)
		if _sector_mode: wave_spawner.set_spawning_paused(true)
		hud.set_room_message("ボス生成に失敗しました。もう一度領域を調べてください")
		_boss_gate.reset_interaction.call_deferred()

func _on_map_boss_defeated(map_index: int, _boss_id: String, death_position: Vector2) -> void:
	if not _active or map_index != GameManager.current_map_index:
		return
	_boss_active = false
	if GameManager.survival_mode_active:
		if GameManager.survival_completed: return
		_finish_survival()
		return
	SaveManager.record_cleared_floor(GameManager.current_depth)
	if GameManager.current_depth % 5 == 0:
		GameManager.add_run_gold(15 + GameManager.current_depth, "five_floor_milestone")
		player.health_component.heal(player.health_component.max_hp * 0.20)
		hud.set_room_message("地下%d層突破！　金貨と回復を獲得" % GameManager.current_depth)
	_boss_reward_pending = true
	stage_environment.set_boss_seal_visible(false)
	wave_spawner.set_spawning_paused(true)
	EventBus.map_completed.emit(map_index, GameManager.elapsed_seconds - _map_started_at, _map_kills)
	var final_floor := GameManager.current_depth >= int(_config.get("total_floors", 60))
	var rarity := "legendary" if final_floor else "rare"
	var chest_position := GameManager.dungeon_map.find_spawn_position_near(death_position)
	_boss_chest = _spawn_treasure(chest_position, rarity, "boss_equipment", true)
	_boss_loot_position = _boss_exit_position(chest_position, false)
	_stairs = _spawn_landmark("descent_stairs", "地下への階段", Color("d9b973"), _boss_exit_position(chest_position, true), false)
	var milestone := "　%d層区切り突破：金貨＋回復" % GameManager.current_depth if GameManager.current_depth % 5 == 0 else ""
	hud.set_room_message("ボス撃破。装備と宝箱を回収して階段へ" + milestone)

func _on_treasure_opened(rarity: String, chest: TreasureChest) -> void:
	var reward_type := String(_reward_by_chest_id.get(chest.get_instance_id(), "equipment"))
	_reward_by_chest_id.erase(chest.get_instance_id())
	EventBus.treasure_reward_revealed.emit(reward_type, rarity, chest.global_position)
	match reward_type:
		"key":
			_key_acquired = true
			GameManager.dungeon_map.set_meta("key_acquired", true)
			_update_exploration_progress()
			hud.set_room_message("封印の鍵を入手。ボス領域へ向かう")
		"equipment", "supply_equipment":
			_spawn_equipment_reward(chest.global_position, rarity)
			if GameManager.survival_mode_active:
				player.weapon_manager.grant_sector_style()
				if reward_type == "supply_equipment" and not GameManager.survival_completed:
					shop_screen.show_shop(1)
			if _sector_mode and chest == _sector_chest:
				player.weapon_manager.grant_sector_style()
				if _sector_cleared and is_instance_valid(_sector_exit):
					_sector_exit.set_available(true)
					hud.set_room_message("宝箱を開封　装備を拾ってから扉へ")
		"recovery":
			heart_drop_system.spawn_recovery_drop(_nearest_floor_world(chest.global_position + Vector2(0, 34)), 0.35, 90.0)
		"attribute", "skill":
			# 旧属性/完成大技報酬を含む既存データも、属性システム停止中は装備へ置換する。
			_spawn_equipment_reward(chest.global_position, rarity)
		"boss_skill", "boss_equipment":
			_spawn_equipment_reward(_boss_loot_position, rarity)
			_boss_reward_pending = false
			if is_instance_valid(_stairs): _stairs.set_available(true)
			hud.set_room_message("装備を回収し、帰還の階段へ [E]" if GameManager.survival_mode_active else "装備を回収し、階段を調べる [E]")

func _spawn_equipment_reward(chest_position: Vector2, rarity: String) -> void:
	var equipment_rarity := "rare" if rarity == "rare" else "legendary" if rarity == "legendary" else ""
	equipment_drop_system.spawn_treasure_drop(_nearest_floor_world(chest_position + Vector2(0, 34)), equipment_rarity)

func _continue_after_boss_reward() -> void:
	if GameManager.survival_mode_active:
		if not GameManager.survival_completed or _boss_reward_pending:
			return
		_advance_map()
		return
	var total_floors := int(_config.get("total_floors", 60))
	if GameManager.current_depth >= total_floors:
		_advance_map()
		return
	if not shop_screen.shop_closed.is_connected(_on_shop_closed):
		shop_screen.shop_closed.connect(_on_shop_closed, CONNECT_ONE_SHOT)
	shop_screen.show_shop(GameManager.current_depth)

func _on_shop_closed() -> void:
	_advance_map.call_deferred()

func _advance_map() -> void:
	if GameManager.survival_mode_active:
		_active = false
		combo_system.reset_combo()
		GameManager.complete_map_run(1)
		return
	var total_floors := int(_config.get("total_floors", 60))
	if GameManager.current_depth >= total_floors:
		_active = false
		combo_system.reset_combo()
		GameManager.complete_map_run(total_floors)
		return
	var next_floor := _floor_index + 1
	var next_map := GameManager.current_map_index
	if next_floor > _floors_per_map():
		next_floor = 1
		next_map += 1
	_transition_to_map(next_map, next_floor)

func _transition_to_map(next_map_index: int, next_floor_index: int = 1) -> void:
	if _transitioning:
		return
	_transitioning = true
	player.set_movement_locked(true)
	wave_spawner.set_spawning_paused(true)
	combo_system.reset_combo()
	_show_transition_overlay(next_map_index, next_floor_index)
	_clear_map_nodes()
	await get_tree().process_frame
	var next_config := _get_map_config(next_map_index)
	GameManager.current_floor_index = next_floor_index
	GameManager.current_depth = (next_map_index - 1) * _floors_per_map() + next_floor_index
	GameManager.generate_exploration_map(next_map_index, int(next_config.get("width", 86)), int(next_config.get("height", 86)), int(next_config.get("room_count", 11)), int(next_config.get("elite_rooms", 2)))
	_last_transition_profile = await stage_environment.build_dungeon_async(GameManager.dungeon_map, 5)
	print_verbose("MAP_TRANSITION_PROFILE map=%d total_ms=%.3f max_slice_ms=%.3f frames=%d" % [next_map_index, float(_last_transition_profile.get("total_ms", 0.0)), float(_last_transition_profile.get("max_slice_ms", 0.0)), int(_last_transition_profile.get("frames", 0))])
	player.global_position = GameManager.dungeon_map.grid_to_world(GameManager.dungeon_map.spawn_point)
	player.setup_camera_limits(GameManager.dungeon_map)
	# With 60 descents, the old 25% between three maps would erase attrition.
	player.health_component.heal(player.health_component.max_hp * 0.08)
	_start_map(next_map_index, next_floor_index)
	_hide_transition_overlay()
	player.set_movement_locked(false)
	_transitioning = false

func _clear_map_nodes(preserve_equipment: bool = false) -> void:
	_exploration_chests.clear()
	boss_spawner.clear_room_boss()
	elite_room_manager.clear_map_runtime()
	for group_name in ["map_content", "enemies", "projectiles", "boss_projectiles", "boss_attack_transient", "boss_summons", "allies", "ground_equipment", "room_transient", "transient_vfx"]:
		if preserve_equipment and group_name == "ground_equipment":
			continue
		for node in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(node) and node != player:
				node.queue_free()

func _clear_combat_transients(include_boss: bool) -> void:
	for group_name in ["enemies", "projectiles", "boss_projectiles", "boss_attack_transient", "boss_summons"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node):
				continue
			if not include_boss and node is EnemyBasic and node.exploration_guard and GameManager.dungeon_map.get_meta("exploration_layout",false):
				continue
			if not include_boss and node is EnemyBasic and node.enemy_data is BossData:
				continue
			node.queue_free()

func _floors_per_map() -> int:
	return maxi(1, int(_config.get("floors_per_map", 20)))

func _boss_exit_position(chest_position: Vector2, staircase: bool) -> Vector2:
	var map := GameManager.dungeon_map
	if map.get_meta("floor_only", false):
		var offset := Vector2(0, 192) if staircase else Vector2(-160, 0)
		return equipment_drop_system._find_safe_drop_position(chest_position + offset)
	var room: Rect2i = map.rooms[map.boss_room_index]
	var candidates := map.get_spawn_cells(room.grow(-2))
	var target := map.grid_to_world(Vector2i(room.position.x + room.size.x / 2, room.end.y - 3))
	var best := _nearest_floor_world(target)
	var best_score := -INF
	for cell in candidates:
		var point := map.grid_to_world(cell)
		if point.distance_to(chest_position) < 120.0:
			continue
		if staircase and _boss_loot_position != Vector2.ZERO and point.distance_to(_boss_loot_position) < 96.0:
			continue
		var score := -point.distance_to(target) if staircase else -point.distance_to(chest_position)
		if score > best_score:
			best_score = score
			best = point
	return best

func _get_map_config(map_index: int) -> Dictionary:
	for entry in _maps:
		if int(entry.get("index", 0)) == map_index:
			return Dictionary(entry).duplicate(true)
	return {}

func _room_distance_squared(map: DungeonMap, room_index: int) -> float:
	var center := map.rooms[room_index].position + map.rooms[room_index].size / 2
	return Vector2(center - map.spawn_point).length_squared()

func _room_position(map: DungeonMap, room_index: int, offset: Vector2 = Vector2.ZERO) -> Vector2:
	var room := map.rooms[room_index]
	return _nearest_floor_world(map.grid_to_world(room.position + room.size / 2) + offset)

func _nearest_floor_world(position: Vector2) -> Vector2:
	var map := GameManager.dungeon_map
	if map == null:
		return position
	var origin := map.world_to_grid(position)
	if map.is_floor(origin):
		return map.grid_to_world(origin)
	for radius in range(1, 8):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := origin + Vector2i(x, y)
				if map.is_floor(candidate):
					return map.grid_to_world(candidate)
	return map.grid_to_world(map.spawn_point)

func _create_transition_overlay() -> void:
	if is_instance_valid(_transition_layer):
		return
	_transition_layer = CanvasLayer.new()
	_transition_layer.layer = 80
	_transition_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("172238")
	_transition_layer.add_child(background)
	_transition_label = Label.new()
	_transition_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_transition_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_transition_label.add_theme_font_size_override("font_size", 34)
	_transition_label.add_theme_color_override("font_color", Color("d9efff"))
	_transition_label.add_theme_color_override("font_outline_color", Color("050912"))
	_transition_label.add_theme_constant_override("outline_size", 8)
	_transition_layer.add_child(_transition_label)
	add_child(_transition_layer)
	_transition_layer.visible = false

func _show_transition_overlay(next_map_index: int, next_floor_index: int = 1) -> void:
	if not is_instance_valid(_transition_layer):
		return
	var next_config := _get_map_config(next_map_index)
	_transition_label.text = "MAP %d / 3  地下%d / %d層\n%s\n\n次の階層を構築中…" % [next_map_index, next_floor_index, _floors_per_map(), next_config.get("display_name", "")]
	_transition_layer.visible = true

func _hide_transition_overlay() -> void:
	if is_instance_valid(_transition_layer):
		_transition_layer.visible = false

func _clear_hud_message_later(delay: float) -> void:
	var map_index := GameManager.current_map_index
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func():
		if _active and not _transitioning and not _surge_active and _surge_end_message_remaining <= 0.0 and GameManager.current_map_index == map_index:
			hud.set_room_message("")
	)

func _rarity_display_name(rarity: String) -> String:
	return {"normal": "宝箱", "rare": "希少な宝箱", "legendary": "伝説の宝箱"}.get(rarity, "宝箱")

func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

## Headless/Developer Test Labから、実時間を待たず同じBoss経路を検証する入口。
func debug_force_boss_ready() -> void:
	if not OS.is_debug_build() or not _active:
		return
	if _sector_mode:
		wave_spawner.stop_sector_wave()
		_clear_combat_transients(true)
		_sector_index = _sector_total
		_sector_cleared = true
		if is_instance_valid(_sector_seals):
			_sector_seals.queue_free()
		_sector_seals = null
		if is_instance_valid(_sector_exit):
			_sector_exit.queue_free()
		_sector_exit = null
		_unlock_sector_boss()
		return
	_map_kills = int(_current_config.get("boss_kill_requirement", 420))
	_update_progress()

func debug_start_boss() -> void:
	if OS.is_debug_build():
		_start_map_boss()

func debug_trigger_next_surge(trigger_reason: String) -> void:
	if not OS.is_debug_build() or _surge_active:
		return
	var fractions: Array = _surge_config.get("kill_fractions", [0.25, 0.5, 0.75])
	var fallback_times: Array = _current_config.get("surge_fallback_seconds", [])
	if _surge_index >= fractions.size() or _surge_index >= fallback_times.size():
		return
	if trigger_reason == "time":
		_map_started_at = GameManager.elapsed_seconds - float(fallback_times[_surge_index]) - 0.1
	else:
		_map_kills = maxi(_map_kills, ceili(float(_current_config.get("boss_kill_requirement", 420)) * float(fractions[_surge_index])))
	_update_progress()

func debug_finish_surge() -> void:
	if OS.is_debug_build():
		_finish_surge()

func debug_get_map_state() -> Dictionary:
	if not OS.is_debug_build():
		return {}
	return {
		"map_index": GameManager.current_map_index,
		"floor_index": _floor_index,
		"depth": GameManager.current_depth,
		"stairs_present": is_instance_valid(_stairs),
		"kills": _map_kills,
		"boss_unlocked": _boss_unlocked,
		"boss_active": _boss_active,
		"transitioning": _transitioning,
		"chest_count": _reward_by_chest_id.size(),
		"transition_profile": _last_transition_profile.duplicate(true),
		"surge_active": _surge_active,
		"surge_index": _surge_index,
		"surge_remaining": _surge_remaining,
		"surge_trigger_reason": _surge_trigger_reason,
		"surge_reward_count": _surge_reward_count,
	}


var _exploration_chests: Dictionary = {}
var _visited_rooms: Dictionary = {}
var _explored_cells: Dictionary = {}
var _key_acquired := false
var _boss_reward_pending := false
var _exploration_map_ui: ExplorationMapOverlay

func _place_exploration_content(map: DungeonMap) -> void:
	_exploration_chests.clear()
	_visited_rooms.clear()
	_explored_cells.clear()
	_key_acquired = false
	_boss_reward_pending = false
	map.set_meta("key_acquired",false)
	if is_instance_valid(_exploration_map_ui): _exploration_map_ui.queue_free()
	_exploration_map_ui = preload("res://ui/hud/exploration_map_overlay.gd").new()
	_exploration_map_ui.map = map
	_exploration_map_ui.actor = player
	add_child(_exploration_map_ui)
	var roles: Array = map.get_meta("room_roles",[])
	var cells: Dictionary = map.get_meta("objective_cells",{})
	for room_id: int in cells:
		var role: String = roles[room_id]
		var reward := "key" if role=="key_guard" else ("recovery" if role=="rest" else "equipment")
		var rarity := "rare" if role=="elite" else "normal"
		var chest := _spawn_treasure(map.grid_to_world(cells[room_id])+Vector2.ONE*16,rarity,reward,false)
		chest.name_override = "封印の鍵" if reward=="key" else ("補給箱" if reward=="recovery" else "宝箱")
		chest.locked_reason = "番人を倒す" if reward=="key" else "周囲の敵を倒す"
		chest.set_available(role=="rest")
		_exploration_chests[room_id] = chest

func _update_exploration_progress() -> void:
	var map := GameManager.dungeon_map
	var cell := map.world_to_grid(player.global_position)
	for y in range(-6,7):
		for x in range(-6,7):
			if x*x+y*y<=36:
				var next := cell+Vector2i(x,y)
				if map.is_floor(next): _explored_cells[next]=true
	var room_id := ExplorationLayout.room_at(map,cell)
	if room_id>=0:
		_visited_rooms[room_id]=true
		var room: Rect2i = map.rooms[room_id]
		for y in range(room.position.y,room.end.y):
			for x in range(room.position.x,room.end.x):
				var next := Vector2i(x,y)
				if map.is_floor(next): _explored_cells[next]=true
	map.set_meta("visited_rooms",_visited_rooms)
	map.set_meta("explored_cells",_explored_cells)
	for id: int in _exploration_chests:
		if not is_instance_valid(_exploration_chests[id]): continue
		var chest: TreasureChest = _exploration_chests[id]
		if not chest.available and wave_spawner.is_encounter_cleared(id):
			chest.set_available(true)
	if _key_acquired and not _boss_unlocked:
		_boss_unlocked = true
		_boss_gate.set_available(true)
		EventBus.map_boss_unlocked.emit(GameManager.current_map_index)
	var current_role: String = map.get_meta("room_roles",[])[room_id] if room_id>=0 else "passage"
	var region: String = {"entry":"入口","first_guard":"見張りの広間","junction":"分かれ道","guard":"広間","key_guard":"鍵の番人","junction_guard":"合流点","antechamber":"最深部の前室","boss":"ボス領域","cache":"脇道の宝箱","flank":"迂回路","rest":"補給の間","elite":"精鋭の間","landmark":"遺構","passage":"通路"}.get(current_role,"探索中")
	var objective := "鍵の番人を探す" if not _key_acquired else "封印解除・ボス領域へ"
	if room_id==int(map.get_meta("key_room",4)) and not _key_acquired:
		objective = "番人を倒して鍵箱を開く" if not wave_spawner.is_encounter_cleared(room_id) else "[E] 鍵箱を開く"
	if _boss_active: objective = "ボスを倒す"
	elif _boss_reward_pending: objective = "ボス宝箱を開く"
	elif is_instance_valid(_stairs): objective = "装備を拾い、階段を下りる"
	hud.set_exploration_status(GameManager.current_map_index,String(_current_config.get("display_name","")),region,objective,_visited_rooms.size(),map.rooms.size(),_floor_index,_floors_per_map())

func _setup_survival_map_overlay() -> void:
	if is_instance_valid(_exploration_map_ui): _exploration_map_ui.queue_free()
	_exploration_map_ui = ExplorationMapOverlay.new()
	_exploration_map_ui.map = GameManager.dungeon_map
	_exploration_map_ui.actor = player
	add_child(_exploration_map_ui)
