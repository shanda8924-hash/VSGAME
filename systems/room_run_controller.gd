extends Node
class_name RoomRunController

enum RoomState { IDLE, ENTERING, COMBAT, CLEAR, REWARD, CHOOSING, RUN_CLEAR }

const CONFIG_PATH := "res://data/rooms/room_mvp.json"
const TREASURE_CHEST_SCENE := preload("res://entities/pickups/treasure_chest.tscn")

@export var stage_environment_path: NodePath
@export var player_path: NodePath
@export var wave_spawner_path: NodePath
@export var boss_spawner_path: NodePath
@export var elite_room_manager_path: NodePath
@export var hud_path: NodePath
@export var room_select_path: NodePath
@export var fragment_select_path: NodePath
@export var item_select_path: NodePath
@export var combo_system_path: NodePath
@export var concept_system_path: NodePath
@export var concept_select_path: NodePath
@export var concept_board_path: NodePath
@export var equipment_drop_system_path: NodePath
@export var equipment_screen_path: NodePath

@onready var stage_environment: StageEnvironment = get_node(stage_environment_path)
@onready var player: Player = get_node(player_path)
@onready var wave_spawner: WaveSpawner = get_node(wave_spawner_path)
@onready var boss_spawner: BossSpawner = get_node(boss_spawner_path)
@onready var elite_room_manager: EliteRoomManager = get_node(elite_room_manager_path)
@onready var hud: HUD = get_node(hud_path)
@onready var room_select: RoomSelect = get_node(room_select_path)
@onready var fragment_select: FragmentSelect = get_node(fragment_select_path)
@onready var item_select: ItemSelect = get_node(item_select_path)
@onready var combo_system: ComboSystem = get_node(combo_system_path)
@onready var concept_system: ConceptSystem = get_node(concept_system_path)
@onready var concept_select: ConceptSelect = get_node(concept_select_path)
@onready var concept_board: ConceptBoard = get_node(concept_board_path)
@onready var equipment_drop_system: EquipmentDropSystem = get_node(equipment_drop_system_path)
@onready var equipment_screen: EquipmentScreen = get_node(equipment_screen_path)

var state: RoomState = RoomState.IDLE
var current_room: int = 0
var total_rooms: int = 10
var current_room_type: String = "combat"
var current_template_id: String = "standard"
var _config: Dictionary = {}
var _transition_epoch: int = 0
var _active_chest: TreasureChest = null
var _boss_reward_pending: bool = false
var _last_defeated_boss_id: String = ""
var _recent_templates: Array[String] = []
var _prepared_room_number := 0
var _prepared_template_id := ""
var _prepared_map: DungeonMap = null
var last_transition_profile: Dictionary = {}

func _ready() -> void:
	wave_spawner.room_wave_cleared.connect(_on_room_wave_cleared)
	boss_spawner.room_boss_defeated.connect(_on_room_boss_defeated)
	room_select.room_chosen.connect(_on_room_chosen)
	room_select.concept_board_requested.connect(_on_concept_board_requested)

func begin_run() -> void:
	if not GameManager.room_mode_active:
		return
	_config = _load_config()
	total_rooms = maxi(int(_config.get("total_rooms", 10)), 1)
	wave_spawner.enable_room_mode(true)
	boss_spawner.prepare_room_run()
	elite_room_manager.process_mode = Node.PROCESS_MODE_DISABLED
	combo_system.configure_timeout(float(_config.get("combo_timeout", 2.5)))
	combo_system.configure_triggered_chain_cap(int(_config.get("combo_triggered_chain_cap", 12)))
	combo_system.set_active(true)
	concept_system.set_active(true)
	room_select.visible = false
	_recent_templates.clear()
	_prepared_room_number = 0
	_prepared_template_id = ""
	_prepared_map = null
	# 64px装備Iconは小さいため、起動を塞がず数枚ずつResource cacheへ保持する。
	equipment_drop_system.warmup_resources()
	wave_spawner.warmup_enemy_visuals(1)
	_begin_room.call_deferred(1, "combat", "standard")

func _begin_room(room_number: int, room_type: String, template_id: String) -> void:
	var transition_start := Time.get_ticks_usec()
	_transition_epoch += 1
	var epoch := _transition_epoch
	state = RoomState.ENTERING
	player.set_movement_locked(true)
	current_room = room_number
	current_room_type = _room_type_for(room_number)
	current_template_id = "large" if _is_boss_room(room_number) else template_id
	if current_template_id == "":
		current_template_id = _select_next_template(room_number)
	if not _is_boss_room(room_number) and (_recent_templates.is_empty() or _recent_templates[-1] != current_template_id):
		_recent_templates.append(current_template_id)
	while _recent_templates.size() > 2:
		_recent_templates.pop_front()
	_boss_reward_pending = false
	wave_spawner.clear_room_wave()
	boss_spawner.clear_room_boss()
	combo_system.reset_combo()
	_clear_transient_room_nodes()
	# 前ROOMのqueue_freeを処理してから新ROOMを敷設し、解放と生成を同一Frameへ集中させない。
	await get_tree().process_frame
	if epoch != _transition_epoch:
		return
	var map_start := Time.get_ticks_usec()
	if _prepared_room_number == room_number and _prepared_template_id == current_template_id and _prepared_map != null:
		GameManager.dungeon_map = _prepared_map
	else:
		GameManager.dungeon_map = RoomTemplateFactory.build_map(current_template_id)
	var map_ms := float(Time.get_ticks_usec() - map_start) / 1000.0
	_prepared_room_number = 0
	_prepared_template_id = ""
	_prepared_map = null
	var stage_profile := await stage_environment.build_dungeon_async(GameManager.dungeon_map)
	if epoch != _transition_epoch:
		return
	player.global_position = GameManager.dungeon_map.grid_to_world(GameManager.dungeon_map.spawn_point)
	player.setup_camera_limits(GameManager.dungeon_map)
	hud.hide_room_clear()
	hud.set_room_status(current_room, total_rooms, current_room_type, RoomTemplateFactory.get_display_name(current_template_id))

	var prepared_boss: Node = null
	var prepare_start := Time.get_ticks_usec()
	if _is_boss_room(current_room):
		var encounter := _get_boss_encounter(current_room).duplicate(true)
		encounter["is_final"] = current_room >= total_rooms
		await get_tree().process_frame
		prepared_boss = boss_spawner.start_room_boss(current_room, encounter, Vector2.INF, true)
	else:
		var count := int(_room_value("enemy_counts", current_room, 10.0))
		var hp_multiplier := _room_value("enemy_hp_multipliers", current_room, 1.0)
		var damage_multiplier := _room_value("enemy_damage_multipliers", current_room, 0.5)
		var special_chance := clampf(_room_value("special_enemy_chances", current_room, 0.0), 0.0, 0.4)
		await wave_spawner.prepare_room_wave(current_room, count, hp_multiplier, damage_multiplier, special_chance, int(_config.get("enemy_prepare_batch_size", 2)))
	var prepare_ms := float(Time.get_ticks_usec() - prepare_start) / 1000.0
	var minimum_transition_ms := float(_config.get("room_transition_minimum", 0.34)) * 1000.0
	var spent_ms := float(Time.get_ticks_usec() - transition_start) / 1000.0
	if spent_ms < minimum_transition_ms:
		await get_tree().create_timer((minimum_transition_ms - spent_ms) / 1000.0).timeout
	if epoch != _transition_epoch or GameManager.run_state != GameManager.RunState.PLAYING:
		return
	state = RoomState.COMBAT
	if _is_boss_room(current_room):
		if prepared_boss == null or boss_spawner.activate_prepared_room_boss() == null:
			push_error("RoomRunController: ROOM %d のボス生成に失敗しました" % current_room)
			_finish_current_room.call_deferred()
			return
	else:
		wave_spawner.activate_prepared_room_wave()
	player.set_movement_locked(false)
	last_transition_profile = {
		"room": current_room,
		"template": current_template_id,
		"map_ms": map_ms,
		"stage_total_ms": float(stage_profile.get("total_ms", 0.0)),
		"stage_max_slice_ms": float(stage_profile.get("max_slice_ms", 0.0)),
		"stage_frames": int(stage_profile.get("frames", 0)),
		"prepare_total_ms": prepare_ms,
		"transition_total_ms": float(Time.get_ticks_usec() - transition_start) / 1000.0,
	}

func _on_room_wave_cleared() -> void:
	if state != RoomState.COMBAT:
		return
	_finish_current_room.call_deferred()

func _on_room_boss_defeated(room_number: int, boss_id: String, _death_position: Vector2) -> void:
	if state != RoomState.COMBAT or room_number != current_room:
		return
	_last_defeated_boss_id = boss_id
	_boss_reward_pending = current_room < total_rooms
	_finish_current_room.call_deferred()

func _finish_current_room() -> void:
	if state != RoomState.COMBAT:
		return
	state = RoomState.CLEAR
	# 戦闘終了と同時に突進/居合の一時移動ロックが残っても、報酬へ歩けるよう解除する。
	player.set_movement_locked(false)
	_apply_room_clear_recovery()
	hud.show_room_clear(current_room >= total_rooms, _is_boss_room(current_room))
	await get_tree().create_timer(float(_config.get("room_clear_delay", 0.9))).timeout
	hud.hide_room_clear()
	if current_room >= total_rooms:
		state = RoomState.RUN_CLEAR
		combo_system.reset_combo()
		GameManager.complete_room_run(total_rooms)
		return
	_show_attribute_reward()

func _apply_room_clear_recovery() -> void:
	var ratio := clampf(float(_config.get("room_clear_heal_ratio", 0.075)), 0.0, 1.0)
	if ratio <= 0.0 or player == null or player.health_component == null:
		return
	player.health_component.heal(player.health_component.max_hp * ratio)

func _show_attribute_reward() -> void:
	state = RoomState.REWARD
	fragment_select.reward_chosen.connect(_on_attribute_reward_chosen, CONNECT_ONE_SHOT)
	fragment_select.show_choices("属性を1つ選択", 3)

func _on_attribute_reward_chosen(_choice: Dictionary) -> void:
	_spawn_treasure_reward()

func _spawn_treasure_reward() -> void:
	state = RoomState.REWARD
	player.set_movement_locked(false)
	var rarity := _roll_treasure_rarity()
	var rarity_data: Dictionary = _get_rarity_data(rarity)
	_active_chest = TREASURE_CHEST_SCENE.instantiate() as TreasureChest
	_active_chest.configure(rarity, Color.from_string(String(rarity_data.get("color", "#d9dde8")), Color.WHITE), _boss_reward_pending)
	_active_chest.opened.connect(_on_treasure_opened, CONNECT_ONE_SHOT)
	GameManager.get_runtime_world(self).add_child(_active_chest)
	_active_chest.global_position = _find_reward_position()
	hud.set_room_message("ボス宝箱が出現しました" if _boss_reward_pending else "宝箱が出現しました")

func _on_treasure_opened(rarity: String) -> void:
	hud.set_room_message("")
	var candidates := _build_completed_skill_candidates()
	if candidates.is_empty():
		_show_item_fallback(rarity)
		return
	concept_select.completed_skill_chosen.connect(_on_completed_skill_chosen, CONNECT_ONE_SHOT)
	concept_select.show_completed_skill_choices(candidates, "%s：スキルを1つ選択" % _rarity_display_name(rarity))

func _on_completed_skill_chosen(_skill_id: String, _level: int) -> void:
	_complete_reward_phase.call_deferred()

func _show_item_fallback(rarity: String) -> void:
	var candidates := _build_treasure_candidates(rarity)
	if candidates.is_empty():
		_complete_reward_phase.call_deferred()
		return
	item_select.item_chosen.connect(_on_treasure_item_chosen, CONNECT_ONE_SHOT)
	item_select.show_choices(candidates, "%s：能力を1つ選択" % _rarity_display_name(rarity))

func _on_treasure_item_chosen(_item_id: String) -> void:
	_complete_reward_phase.call_deferred()

func _complete_reward_phase() -> void:
	if state == RoomState.RUN_CLEAR or current_room >= total_rooms:
		return
	state = RoomState.CHOOSING
	room_select.visible = false
	var next_room := current_room + 1
	var next_template := _select_next_template(next_room)
	_prepare_next_room(next_room, next_template)
	hud.set_room_message("C / I：装備確認　次のルームを準備中")
	await get_tree().create_timer(float(_config.get("equipment_intermission_seconds", 0.9)), true, false, true).timeout
	while equipment_screen.is_open():
		await equipment_screen.closed
	if state != RoomState.CHOOSING or GameManager.run_state != GameManager.RunState.PLAYING:
		return
	hud.set_room_message("")
	_begin_room.call_deferred(next_room, _room_type_for(next_room), next_template)

func _prepare_next_room(room_number: int, template_id: String) -> void:
	_prepared_room_number = room_number
	_prepared_template_id = template_id
	_prepared_map = RoomTemplateFactory.build_map(template_id)
	equipment_drop_system.warmup_resources()
	if _is_boss_room(room_number):
		_warmup_boss_visuals(room_number)
	else:
		wave_spawner.warmup_enemy_visuals(room_number)

func _warmup_boss_visuals(room_number: int) -> void:
	var encounter := _get_boss_encounter(room_number)
	for candidate in encounter.get("candidates", []):
		var data := DataLoader.bosses.get(String(candidate)) as BossData
		if data == null or data.sprite_folder == "" or SpriteSheetBuilder.is_cached(data.sprite_folder):
			continue
		SpriteSheetBuilder.build_sprite_frames(data.sprite_folder)
		await get_tree().process_frame

func _select_next_template(room_number: int) -> String:
	if _is_boss_room(room_number):
		return "large"
	var configured: Array = _config.get("templates", RoomTemplateFactory.get_template_ids())
	var candidates: Array[String] = []
	for value in configured:
		var candidate := String(value)
		if candidate == "large" or candidate in _recent_templates:
			continue
		candidates.append(candidate)
	if candidates.is_empty():
		for value in configured:
			var candidate := String(value)
			if candidate != "large" and candidate != current_template_id:
				candidates.append(candidate)
	if candidates.is_empty():
		return "standard"
	return candidates[randi() % candidates.size()]

func _show_room_choices() -> void:
	# 将来、意味のある分岐ROOMを再導入する場合の互換入口。現行通常Runからは呼ばない。
	state = RoomState.CHOOSING
	hud.set_room_message("")
	var candidates: Array[Dictionary] = []
	var next_room := current_room + 1
	if _is_boss_room(next_room):
		var final_boss := next_room >= total_rooms
		candidates.append({
			"type": "final_boss" if final_boss else "boss",
			"template": "large",
			"icon": "⚔",
			"title": "最終ボス" if final_boss else "ボス戦",
			"description": "完成したビルドを試す最終決戦" if final_boss else "現在のビルドを試す強敵戦",
			"color": "#ff6f61",
		})
	else:
		var templates := _pick_templates(2)
		for template_id in templates:
			candidates.append({
				"type": "combat",
				"template": template_id,
				"icon": "◆",
				"title": RoomTemplateFactory.get_display_name(template_id),
				"description": "戦闘後に属性と宝箱を獲得",
				"color": "#8edbff",
			})
	var area_transition := "エリア2へ" if current_room == 4 else "エリア3へ" if current_room == 8 else ""
	room_select.show_choices(current_room, total_rooms, candidates, area_transition)

func _on_room_chosen(choice: Dictionary) -> void:
	if state != RoomState.CHOOSING:
		return
	_begin_room(current_room + 1, String(choice.get("type", "combat")), String(choice.get("template", "standard")))

func _on_concept_board_requested() -> void:
	if state != RoomState.CHOOSING:
		return
	concept_board.board_closed.connect(_show_room_choices, CONNECT_ONE_SHOT)
	concept_board.show_board()

func _pick_templates(count: int) -> Array[String]:
	var templates: Array[String] = []
	for template_id in _config.get("templates", RoomTemplateFactory.get_template_ids()):
		if String(template_id) != current_template_id:
			templates.append(String(template_id))
	if templates.size() < count:
		templates = RoomTemplateFactory.get_template_ids()
	templates.shuffle()
	return templates.slice(0, count)

func _roll_treasure_rarity() -> String:
	var rarity_config: Dictionary = _config.get("treasure_rarity", {})
	if _boss_reward_pending:
		rarity_config = _get_boss_encounter(current_room).get("treasure_rarity", rarity_config)
	var total_weight := 0.0
	for data in rarity_config.values():
		total_weight += float(data.get("weight", 0.0))
	var roll := randf() * maxf(total_weight, 1.0)
	for rarity in ["normal", "rare", "legendary"]:
		var data: Dictionary = rarity_config.get(rarity, {})
		roll -= float(data.get("weight", 0.0))
		if roll <= 0.0:
			return rarity
	return "normal"

func _get_rarity_data(rarity: String) -> Dictionary:
	var rarity_config: Dictionary = _config.get("treasure_rarity", {})
	return rarity_config.get(rarity, {"weight": 1.0, "value_multiplier": 1.0, "color": "#d9dde8"})

func _build_treasure_candidates(rarity: String) -> Array[ItemData]:
	var source := DataLoader.get_all_items()
	source.shuffle()
	var result: Array[ItemData] = []
	var multiplier := float(_get_rarity_data(rarity).get("value_multiplier", 1.0))
	for index in mini(3, source.size()):
		var item := source[index].duplicate(true) as ItemData
		item.value *= multiplier
		item.display_name = "[%s] %s" % [rarity.to_upper(), item.display_name]
		item.description = _describe_scaled_item(item)
		result.append(item)
	return result

func _build_concept_candidates() -> Array[ConceptData]:
	var unowned := concept_system.get_unowned_concepts()
	var result: Array[ConceptData] = []
	# Categoryを確定配布せず、所持数が少ない種類と空Slotに必要な種類へ緩い重みを付ける。
	# 完成Chainを保証はしないが、Triggerだけが偏り続ける確率を抑えるSmart Weight。
	while result.size() < mini(3, unowned.size()):
		var total_weight := 0.0
		var weighted: Array[Dictionary] = []
		for data in unowned:
			if data in result:
				continue
			var owned_count := concept_system.get_owned_concepts(data.concept_type).size()
			var maximum_owned := 0
			for concept_type in ["trigger", "skill", "modifier"]:
				maximum_owned = maxi(maximum_owned, concept_system.get_owned_concepts(concept_type).size())
			var weight := 1.0 + float(maximum_owned - owned_count) * 0.55
			if _has_empty_concept_slot(data.concept_type):
				weight += 0.65
			weighted.append({"data": data, "weight": weight})
			total_weight += weight
		var roll := randf() * maxf(total_weight, 0.001)
		for entry in weighted:
			roll -= float(entry.get("weight", 1.0))
			if roll <= 0.0:
				result.append(entry.get("data") as ConceptData)
				break
	return result

func _build_completed_skill_candidates() -> Array[Dictionary]:
	var active_elements := GameManager.get_active_element_ids()
	var pool: Array[Dictionary] = []
	for definition in concept_system.get_completed_skill_definitions():
		if not concept_system.is_completed_skill_available_for_build(definition, active_elements):
			continue
		var skill_id := String(definition.get("id", ""))
		var current_level := concept_system.get_completed_skill_level(skill_id)
		var maximum := int(definition.get("max_level", 3))
		if current_level >= maximum:
			continue
		if current_level <= 0 and concept_system.get_completed_skill_count() >= ConceptSystem.MAX_COMPLETED_SKILLS:
			continue
		var required: Array = definition.get("required_elements", [])
		var weight := 1.0
		if current_level > 0:
			weight += 1.35
		if required.size() >= 2:
			weight += 0.7
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

func _rarity_display_name(rarity: String) -> String:
	return {
		"normal": "宝箱",
		"rare": "希少な宝箱",
		"legendary": "伝説の宝箱",
	}.get(rarity, "宝箱")

func _has_empty_concept_slot(slot_type: String) -> bool:
	for chain_index in concept_system.chains.size():
		if String(concept_system.get_chain(chain_index).get(slot_type, "")) == "":
			return true
	return false

func _describe_scaled_item(item: ItemData) -> String:
	var percent := int(round(item.value * 100.0))
	match item.effect_type:
		"damage_up": return "攻撃力が%d%%上昇する" % percent
		"crit_rate_up": return "会心率が%d%%上昇する" % percent
		"max_hp_bonus": return "最大HPが%d上昇し、その場で回復する" % int(round(item.value))
		"move_speed_multiplier": return "移動速度が%d%%上昇する" % percent
		"attack_interval_multiplier": return "攻撃間隔が%d%%短縮する" % percent
		"damage_taken_multiplier": return "被ダメージが%d%%軽減される" % percent
		"attack_range_multiplier": return "攻撃範囲が%d%%上昇する" % percent
		"lifesteal": return "与えたダメージの%d%%を回復する（1Hit最大3HP）" % percent
	return item.description

func _find_reward_position() -> Vector2:
	var player_position := player.global_position
	var target := player_position + Vector2(190.0, 0.0)
	var best := player_position + Vector2(160.0, 0.0)
	var best_distance := INF
	for cell in GameManager.dungeon_map.get_floor_cells():
		var position := GameManager.dungeon_map.grid_to_world(cell)
		if position.distance_to(player_position) < 130.0:
			continue
		var distance := position.distance_squared_to(target)
		if distance < best_distance:
			best_distance = distance
			best = position
	return best

func _clear_transient_room_nodes() -> void:
	if is_instance_valid(_active_chest):
		_active_chest.queue_free()
	_active_chest = null
	for group_name in ["projectiles", "transient_vfx", "ground_equipment", "room_transient", "boss_projectiles", "boss_attack_transient", "boss_summons"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(node):
				node.queue_free()

func _is_boss_room(room_number: int) -> bool:
	return room_number > 0 and (room_number % 4 == 0 or room_number >= total_rooms)

func _room_type_for(room_number: int) -> String:
	if room_number >= total_rooms:
		return "final_boss"
	return "boss" if room_number % 4 == 0 else "combat"

func _get_boss_encounter(room_number: int) -> Dictionary:
	var encounters: Dictionary = _config.get("boss_encounters", {})
	return encounters.get(str(room_number), {})

func _room_value(key: String, room_number: int, fallback: float) -> float:
	var values: Array = _config.get(key, [])
	var index := room_number - 1
	if index >= 0 and index < values.size():
		return float(values[index])
	return fallback

func _load_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_warning("RoomRunController: ROOM設定が見つかりません -> %s" % CONFIG_PATH)
		return {}
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text()) if file else null
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("RoomRunController: ROOM設定のJSON解析に失敗しました")
		return {}
	return parsed

func debug_jump_to_room(room_number: int) -> void:
	if not OS.is_debug_build():
		return
	if _config.is_empty():
		_config = _load_config()
	total_rooms = maxi(int(_config.get("total_rooms", 36)), 1)
	var target := clampi(room_number, 1, total_rooms)
	GameManager.room_mode_active = true
	wave_spawner.enable_room_mode(true)
	boss_spawner.prepare_room_run()
	combo_system.set_active(true)
	concept_system.set_active(true)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_begin_room.call_deferred(target, _room_type_for(target), _select_next_template(target))

func debug_transition_stress(iterations: int = 12) -> Dictionary:
	if not OS.is_debug_build():
		return {}
	if _config.is_empty():
		_config = _load_config()
	total_rooms = maxi(int(_config.get("total_rooms", 36)), 1)
	GameManager.room_mode_active = true
	wave_spawner.enable_room_mode(true)
	boss_spawner.prepare_room_run()
	var max_slice_ms := 0.0
	var nodes_start := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for index in maxi(iterations, 1):
		var room_number := (index % total_rooms) + 1
		var template_id := _select_next_template(room_number)
		await _begin_room(room_number, _room_type_for(room_number), template_id)
		max_slice_ms = maxf(max_slice_ms, float(last_transition_profile.get("stage_max_slice_ms", 0.0)))
	var nodes_end := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	return {"iterations": maxi(iterations, 1), "max_stage_slice_ms": max_slice_ms, "nodes_start": nodes_start, "nodes_end": nodes_end}
