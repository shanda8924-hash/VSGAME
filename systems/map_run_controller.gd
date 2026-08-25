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
@export var fragment_select_path: NodePath
@export var concept_system_path: NodePath
@export var concept_select_path: NodePath
@export var combo_system_path: NodePath
@export var equipment_drop_system_path: NodePath
@export var heart_drop_system_path: NodePath

@onready var stage_environment: StageEnvironment = get_node(stage_environment_path)
@onready var player: Player = get_node(player_path)
@onready var wave_spawner: WaveSpawner = get_node(wave_spawner_path)
@onready var boss_spawner: BossSpawner = get_node(boss_spawner_path)
@onready var elite_room_manager: EliteRoomManager = get_node(elite_room_manager_path)
@onready var hud: HUD = get_node(hud_path)
@onready var fragment_select: FragmentSelect = get_node(fragment_select_path)
@onready var concept_system: ConceptSystem = get_node(concept_system_path)
@onready var concept_select: ConceptSelect = get_node(concept_select_path)
@onready var combo_system: ComboSystem = get_node(combo_system_path)
@onready var equipment_drop_system: EquipmentDropSystem = get_node(equipment_drop_system_path)
@onready var heart_drop_system: HeartDropSystem = get_node(heart_drop_system_path)

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
var _reward_by_chest_id: Dictionary = {}
var _status_update_timer := 0.0
var _transition_layer: CanvasLayer = null
var _transition_label: Label = null
var _last_transition_profile: Dictionary = {}

func _ready() -> void:
	EventBus.enemy_died.connect(_on_enemy_died)
	boss_spawner.room_boss_defeated.connect(_on_map_boss_defeated)

func begin_run() -> void:
	if not GameManager.map_mode_active:
		return
	_config = _read_json(CONFIG_PATH)
	_maps = _config.get("maps", [])
	if _maps.is_empty():
		push_error("MapRunController: MAP設定がありません")
		return
	_active = true
	_transitioning = false
	combo_system.configure_timeout(float(_config.get("combo_timeout_seconds", 3.5)))
	combo_system.set_active(true)
	concept_system.set_active(true)
	boss_spawner.prepare_room_run()
	_create_transition_overlay()
	_start_map(1)

func _process(delta: float) -> void:
	if not _active or _transitioning or not GameManager.map_mode_active or GameManager.run_state != GameManager.RunState.PLAYING:
		return
	_status_update_timer -= delta
	if _status_update_timer <= 0.0:
		_status_update_timer = 0.25
		_update_progress()

func _start_map(map_index: int) -> void:
	_current_config = _get_map_config(map_index)
	if _current_config.is_empty():
		push_error("MapRunController: MAP %d 設定がありません" % map_index)
		return
	GameManager.current_map_index = map_index
	_map_started_at = GameManager.elapsed_seconds
	_map_kills = 0
	_boss_unlocked = false
	_boss_active = false
	_reward_by_chest_id.clear()
	wave_spawner.configure_map_phase(_current_config)
	elite_room_manager.setup(GameManager.dungeon_map)
	_place_map_content()
	var total_maps := int(_config.get("total_maps", _maps.size()))
	var map_name := String(_current_config.get("display_name", "MAP %d" % map_index))
	hud.set_map_status(map_index, total_maps, map_name, 0.0, float(_current_config.get("boss_unlock_seconds", 600.0)), 0, int(_current_config.get("boss_kill_requirement", 60)), false)
	hud.set_room_message("探索開始：宝箱・祭壇・精鋭を探してください")
	_clear_hud_message_later(2.6)
	EventBus.map_started.emit(map_index, total_maps, map_name)

func _update_progress() -> void:
	var elapsed := maxf(GameManager.elapsed_seconds - _map_started_at, 0.0)
	var required_seconds := float(_current_config.get("boss_unlock_seconds", 600.0))
	var required_kills := int(_current_config.get("boss_kill_requirement", 60))
	if not _boss_unlocked and elapsed >= required_seconds and _map_kills >= required_kills:
		_boss_unlocked = true
		if is_instance_valid(_boss_gate):
			_boss_gate.set_available(true)
		hud.set_room_message("ボス領域の封印が解けました。MAP最深部へ向かってください")
		EventBus.map_boss_unlocked.emit(GameManager.current_map_index)
	hud.set_map_status(GameManager.current_map_index, int(_config.get("total_maps", 3)), String(_current_config.get("display_name", "")), elapsed, required_seconds, _map_kills, required_kills, _boss_unlocked)
	EventBus.map_progress_changed.emit(GameManager.current_map_index, elapsed, required_seconds, _map_kills, required_kills)

func _on_enemy_died(_enemy_data: Resource, _death_position: Vector2) -> void:
	if _active and not _transitioning and GameManager.map_mode_active:
		_map_kills += 1

func _place_map_content() -> void:
	var map := GameManager.dungeon_map
	if map == null or map.rooms.size() < 2:
		return
	var room_indices: Array[int] = []
	for index in range(1, map.rooms.size()):
		room_indices.append(index)
	room_indices.sort_custom(func(a: int, b: int):
		return _room_distance_squared(map, a) < _room_distance_squared(map, b)
	)
	var boss_room_index: int = room_indices.back()
	_spawn_landmark("attribute", "属性祭壇", Color("75d8ff"), _room_position(map, room_indices[mini(1, room_indices.size() - 1)], Vector2(-42, 18)), true)
	_spawn_landmark("recovery", "生命の祭壇", Color("ff6684"), _room_position(map, room_indices[mini(2, room_indices.size() - 1)], Vector2(42, 18)), true)
	_boss_gate = _spawn_landmark("boss_gate", "ボス領域", Color("b06cff"), _room_position(map, boss_room_index), false)
	var rewards: Array = _current_config.get("treasure_rewards", ["equipment", "skill", "recovery", "equipment"])
	var rarities: Array = _current_config.get("treasure_rarities", ["normal", "normal", "normal", "rare"])
	var candidates: Array[int] = room_indices.duplicate()
	candidates.erase(boss_room_index)
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
		"attribute":
			fragment_select.show_choices("属性祭壇：属性を1つ選択", 3)
		"recovery":
			player.health_component.heal(player.health_component.max_hp * 0.40)
			EventBus.healing_received.emit(player.health_component.max_hp * 0.40, landmark.global_position)
		"boss_gate":
			_start_map_boss()

func _on_locked_landmark_attempted(kind: String) -> void:
	if kind != "boss_gate":
		return
	var elapsed := maxf(GameManager.elapsed_seconds - _map_started_at, 0.0)
	var seconds_left := maxi(int(ceil(float(_current_config.get("boss_unlock_seconds", 600.0)) - elapsed)), 0)
	var kills_left := maxi(int(_current_config.get("boss_kill_requirement", 60)) - _map_kills, 0)
	hud.set_room_message("封印条件：あと %d秒 / 敵 %d体" % [seconds_left, kills_left])

func _start_map_boss() -> void:
	if not _boss_unlocked or _boss_active or _transitioning or not is_instance_valid(_boss_gate):
		return
	_boss_active = true
	_boss_gate.visible = false
	wave_spawner.enable_room_mode(true)
	_clear_combat_transients(false)
	var encounter := {
		"candidates": _current_config.get("boss_candidates", []),
		"hp_multiplier": float(_current_config.get("boss_hp_multiplier", 2.0)),
		"damage_multiplier": float(_current_config.get("boss_damage_multiplier", 0.7)),
		"attack_interval_multiplier": 1.0,
		"special_interval_multiplier": 1.0,
		"status_duration_multiplier": 1.0,
		"is_final": GameManager.current_map_index >= int(_config.get("total_maps", 3)),
	}
	var spawn_position := _nearest_floor_world(_boss_gate.global_position + Vector2(96, 0))
	var boss := boss_spawner.start_room_boss(GameManager.current_map_index, encounter, spawn_position)
	if boss == null:
		_boss_active = false
		_boss_gate.visible = true
		wave_spawner.configure_map_phase(_current_config)
		hud.set_room_message("ボス生成に失敗しました。もう一度領域を調べてください")
		_boss_gate.used = false
		_boss_gate.set_deferred("monitoring", true)

func _on_map_boss_defeated(map_index: int, _boss_id: String, death_position: Vector2) -> void:
	if not _active or map_index != GameManager.current_map_index:
		return
	_boss_active = false
	wave_spawner.enable_room_mode(true)
	EventBus.map_completed.emit(map_index, GameManager.elapsed_seconds - _map_started_at, _map_kills)
	var final_map := map_index >= int(_config.get("total_maps", 3))
	var rarity := "legendary" if final_map else "rare"
	_spawn_treasure(_nearest_floor_world(death_position), rarity, "boss_skill", true)
	hud.set_room_message("ボス宝箱が出現しました。開封すると%s" % ("ランクリアです" if final_map else "次のMAPへ進みます"))

func _on_treasure_opened(rarity: String, chest: TreasureChest) -> void:
	var reward_type := String(_reward_by_chest_id.get(chest.get_instance_id(), "equipment"))
	_reward_by_chest_id.erase(chest.get_instance_id())
	EventBus.treasure_reward_revealed.emit(reward_type, rarity, chest.global_position)
	match reward_type:
		"equipment":
			var equipment_rarity := "rare" if rarity == "rare" else "legendary" if rarity == "legendary" else ""
			equipment_drop_system.spawn_treasure_drop(_nearest_floor_world(chest.global_position + Vector2(0, 34)), equipment_rarity)
		"recovery":
			heart_drop_system.spawn_recovery_drop(_nearest_floor_world(chest.global_position + Vector2(0, 34)), 0.35, 90.0)
		"attribute":
			fragment_select.show_choices("宝箱報酬：属性を1つ選択", 3)
		"skill":
			_show_skill_reward(rarity, false)
		"boss_skill":
			_show_skill_reward(rarity, true)

func _show_skill_reward(rarity: String, advance_after: bool) -> void:
	var candidates := _build_completed_skill_candidates()
	if candidates.is_empty():
		# 所持3枠すべて最大などの終端でも進行不能にしない。実物装備へ置換する。
		equipment_drop_system.spawn_treasure_drop(player.global_position + Vector2(36, 0), "legendary" if rarity == "legendary" else "rare")
		if advance_after:
			_advance_map.call_deferred()
		return
	concept_select.completed_skill_chosen.connect(_on_completed_skill_selected.bind(advance_after), CONNECT_ONE_SHOT)
	concept_select.show_completed_skill_choices(candidates, "%s：完成スキルを1つ選択" % _rarity_display_name(rarity))

func _on_completed_skill_selected(_skill_id: String, _level: int, advance_after: bool) -> void:
	if advance_after:
		_advance_map.call_deferred()

func _build_completed_skill_candidates() -> Array[Dictionary]:
	var active_elements := GameManager.get_active_element_ids()
	var pool: Array[Dictionary] = []
	for definition in concept_system.get_completed_skill_definitions():
		if not concept_system.is_completed_skill_available_for_build(definition, active_elements):
			continue
		var skill_id := String(definition.get("id", ""))
		var current_level := concept_system.get_completed_skill_level(skill_id)
		var maximum := int(definition.get("max_level", 3))
		if current_level >= maximum or current_level <= 0 and concept_system.get_completed_skill_count() >= ConceptSystem.MAX_COMPLETED_SKILLS:
			continue
		var required: Array = definition.get("required_elements", [])
		var weight := 1.0 + (1.35 if current_level > 0 else 0.0) + (0.7 if required.size() >= 2 else 0.0)
		if not active_elements.is_empty() and String(active_elements[-1]).trim_prefix("element_") in required:
			weight += 0.55
		pool.append({"definition": definition, "weight": weight})
	var result: Array[Dictionary] = []
	while result.size() < 3 and not pool.is_empty():
		var total_weight := 0.0
		for entry in pool:
			total_weight += float(entry.get("weight", 1.0))
		var roll := randf() * maxf(total_weight, 0.001)
		var selected_index := 0
		for index in pool.size():
			roll -= float(pool[index].get("weight", 1.0))
			if roll <= 0.0:
				selected_index = index
				break
		result.append((pool[selected_index].get("definition", {}) as Dictionary).duplicate(true))
		pool.remove_at(selected_index)
	return result

func _advance_map() -> void:
	var total_maps := int(_config.get("total_maps", 3))
	if GameManager.current_map_index >= total_maps:
		_active = false
		combo_system.reset_combo()
		GameManager.complete_map_run(total_maps)
		return
	_transition_to_map(GameManager.current_map_index + 1)

func _transition_to_map(next_map_index: int) -> void:
	if _transitioning:
		return
	_transitioning = true
	player.set_movement_locked(true)
	wave_spawner.enable_room_mode(true)
	combo_system.reset_combo()
	_show_transition_overlay(next_map_index)
	_clear_map_nodes()
	await get_tree().process_frame
	var next_config := _get_map_config(next_map_index)
	GameManager.generate_exploration_map(next_map_index, int(next_config.get("width", 86)), int(next_config.get("height", 86)), int(next_config.get("room_count", 11)), int(next_config.get("elite_rooms", 2)))
	_last_transition_profile = await stage_environment.build_dungeon_async(GameManager.dungeon_map, 5)
	print_verbose("MAP_TRANSITION_PROFILE map=%d total_ms=%.3f max_slice_ms=%.3f frames=%d" % [next_map_index, float(_last_transition_profile.get("total_ms", 0.0)), float(_last_transition_profile.get("max_slice_ms", 0.0)), int(_last_transition_profile.get("frames", 0))])
	player.global_position = GameManager.dungeon_map.grid_to_world(GameManager.dungeon_map.spawn_point)
	player.setup_camera_limits(GameManager.dungeon_map)
	player.health_component.heal(player.health_component.max_hp * 0.25)
	_start_map(next_map_index)
	_hide_transition_overlay()
	player.set_movement_locked(false)
	_transitioning = false

func _clear_map_nodes() -> void:
	boss_spawner.clear_room_boss()
	elite_room_manager.clear_map_runtime()
	for group_name in ["map_content", "enemies", "projectiles", "boss_projectiles", "boss_attack_transient", "boss_summons", "allies", "ground_equipment", "room_transient", "transient_vfx"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(node) and node != player:
				node.queue_free()

func _clear_combat_transients(include_boss: bool) -> void:
	for group_name in ["enemies", "projectiles", "boss_projectiles", "boss_attack_transient", "boss_summons"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node):
				continue
			if not include_boss and node is EnemyBasic and node.enemy_data is BossData:
				continue
			node.queue_free()

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

func _show_transition_overlay(next_map_index: int) -> void:
	if not is_instance_valid(_transition_layer):
		return
	var next_config := _get_map_config(next_map_index)
	_transition_label.text = "MAP %d\n%s\n\n探索地点を構築中…" % [next_map_index, next_config.get("display_name", "")]
	_transition_layer.visible = true

func _hide_transition_overlay() -> void:
	if is_instance_valid(_transition_layer):
		_transition_layer.visible = false

func _clear_hud_message_later(delay: float) -> void:
	var map_index := GameManager.current_map_index
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func():
		if _active and not _transitioning and GameManager.current_map_index == map_index:
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
	_map_started_at = GameManager.elapsed_seconds - float(_current_config.get("boss_unlock_seconds", 600.0))
	_map_kills = int(_current_config.get("boss_kill_requirement", 60))
	_update_progress()

func debug_start_boss() -> void:
	if OS.is_debug_build():
		_start_map_boss()

func debug_get_map_state() -> Dictionary:
	if not OS.is_debug_build():
		return {}
	return {"map_index": GameManager.current_map_index, "kills": _map_kills, "boss_unlocked": _boss_unlocked, "boss_active": _boss_active, "transitioning": _transitioning, "chest_count": _reward_by_chest_id.size(), "transition_profile": _last_transition_profile.duplicate(true)}
