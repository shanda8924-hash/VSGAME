extends Node
class_name EquipmentDropSystem
## 精鋭死亡通知からドロップ判定し、床マスへGroundEquipmentItemを生成する。

const DROP_TABLE_PATH := "res://data/equipment/drop_table.json"
const TEMPLATES_PATH := "res://data/equipment/templates.json"
const CAPPED_GROUND_RARITIES := ["uncommon", "rare", "epic"]
@export var ground_item_scene: PackedScene
var _drop_table: Dictionary = {}
var _templates: Array = []
var _serial := 0
var _icon_cache: Dictionary = {}
var _warmup_running := false

func _ready() -> void:
	_drop_table = _read_json(DROP_TABLE_PATH)
	var parsed_templates = _read_json_variant(TEMPLATES_PATH)
	_templates = parsed_templates if typeof(parsed_templates) == TYPE_ARRAY else []
	EventBus.enemy_drop_requested.connect(_on_enemy_drop_requested)

func _on_enemy_drop_requested(death_position: Vector2, is_elite: bool, is_boss: bool) -> void:
	if ground_item_scene == null:
		return
	var drop_count := 1
	var rarity_override := ""
	if is_boss:
		drop_count = maxi(int(_drop_table.get("boss_minimum_drop_count", 1)), 1)
		rarity_override = _roll_boss_rarity_id(_current_room_number())
	else:
		var chance_key := "strong_enemy_drop_chance" if is_elite else "normal_enemy_drop_chance"
		# MAP探索ではEliteを見つけて倒す意味を装備へ直結させる。通常敵の率は従来通り。
		var chance := 1.0 if GameManager.map_mode_active and is_elite else clampf(float(_drop_table.get(chance_key, 0.02)), 0.0, 1.0)
		if randf() >= chance:
			return
	for _drop_index in drop_count:
		_spawn_equipment_drop(_generate_equipment(rarity_override), death_position, true)

func _spawn_equipment_drop(equipment: EquipmentData, death_position: Vector2, deferred: bool) -> GroundEquipmentItem:
	if deferred:
		# Boss death also creates the chest/stairs. Resolve placement afterwards so
		# their interaction areas and earlier drops participate in the same check.
		_spawn_equipment_drop.call_deferred(equipment, death_position, false)
		return null
	var runtime_world := GameManager.get_runtime_world(self)
	if equipment == null or ground_item_scene == null or runtime_world == null:
		return null
	var safe_position := _find_safe_drop_position(death_position)
	if not safe_position.is_finite():
		push_error("EquipmentDropSystem: no reachable floor for equipment drop")
		return null
	var ground_item := ground_item_scene.instantiate() as GroundEquipmentItem
	ground_item.setup(equipment)
	runtime_world.add_child(ground_item)
	ground_item.global_position = safe_position
	_enforce_ground_item_cap()
	EventBus.equipment_dropped.emit(equipment, safe_position)
	AudioManager.play_sfx("equipment_drop")
	return ground_item

func _enforce_ground_item_cap() -> void:
	if GameManager.survival_completed: return
	var cap := maxi(int(_drop_table.get("ground_item_low_rarity_cap", 24)), 1)
	var warning_seconds := maxf(float(_drop_table.get("ground_item_expiration_warning_seconds", 1.2)), 0.0)
	var low_rarity_items: Array[GroundEquipmentItem] = []
	var pending_count := 0
	for item_variant in get_tree().get_nodes_in_group("ground_equipment"):
		var item := item_variant as GroundEquipmentItem
		if item == null or not is_instance_valid(item) or item.equipment == null or item.equipment.rarity not in CAPPED_GROUND_RARITIES:
			continue
		low_rarity_items.append(item)
		if item.cap_expiration_pending:
			pending_count += 1
	var new_reservations := maxi(low_rarity_items.size() - cap - pending_count, 0)
	if new_reservations <= 0:
		return
	var candidates := low_rarity_items.filter(func(item: GroundEquipmentItem): return not item.cap_expiration_pending)
	candidates.sort_custom(func(first: GroundEquipmentItem, second: GroundEquipmentItem):
		if first.spawned_at_usec == second.spawned_at_usec:
			return first.get_instance_id() < second.get_instance_id()
		return first.spawned_at_usec < second.spawned_at_usec
	)
	for index in mini(new_reservations, candidates.size()):
		candidates[index].begin_cap_expiration(warning_seconds)

func _current_room_number() -> int:
	if GameManager.map_mode_active:
		return 36 if GameManager.current_depth >= 45 else 24 if GameManager.current_depth >= 25 else 13 if GameManager.current_depth >= 12 else 1
	return 1

## 宝箱からも実物の床ドロップを出す共通入口。UIへ直接装備を付与しない。
func spawn_treasure_drop(position: Vector2, rarity_id: String = "") -> GroundEquipmentItem:
	return _spawn_equipment_drop(_generate_equipment(rarity_id), position, false)

func _roll_boss_rarity_id(room_number: int) -> String:
	var tables: Dictionary = _drop_table.get("boss_rarity_by_phase", {})
	var phase := "early"
	if room_number >= 36:
		phase = "final"
	elif room_number >= 24:
		phase = "late"
	elif room_number >= 12:
		phase = "mid"
	var weights: Dictionary = tables.get(phase, {})
	if weights.is_empty():
		return String(_roll_rarity().get("id", "uncommon"))
	var total := 0.0
	for value in weights.values():
		total += float(value)
	var roll := randf() * maxf(total, 1.0)
	for rarity_id in ["uncommon", "rare", "epic", "legendary", "mythic"]:
		roll -= float(weights.get(rarity_id, 0.0))
		if roll <= 0.0:
			return rarity_id
	return "uncommon"

## Equipment Iconを数Frameへ分けてResource cacheへ保持する。Ground Drop/UIの
## 初表示時に同期Texture loadが集中しないようにしつつ、起動Frameは塞がない。
func warmup_resources(batch_size: int = 4) -> void:
	if _warmup_running or _icon_cache.size() >= _templates.size():
		return
	_warmup_running = true
	var loaded_in_batch := 0
	for template in _templates:
		var path := String(template.get("icon_path", ""))
		if path == "" or _icon_cache.has(path):
			continue
		if ResourceLoader.exists(path):
			_icon_cache[path] = ResourceLoader.load(path)
		loaded_in_batch += 1
		if loaded_in_batch >= maxi(batch_size, 1):
			loaded_in_batch = 0
			await get_tree().process_frame
	_warmup_running = false

func is_resource_warmup_complete() -> bool:
	return not _warmup_running and _icon_cache.size() >= _templates.size()

func _generate_equipment(rarity_override: String = "", template_id_override: String = "") -> EquipmentData:
	if _templates.is_empty():
		return null
	var rarity := _rarity_definition(rarity_override) if rarity_override != "" else _roll_rarity()
	if rarity.is_empty():
		return null
	var rarity_id: String = rarity.get("id", "uncommon")
	var rarity_templates: Array = []
	for candidate in _templates:
		if template_id_override != "" and String(candidate.get("id", "")) == template_id_override:
			rarity_templates.append(candidate)
		elif template_id_override == "" and String(candidate.get("rarity", "")) == rarity_id:
			rarity_templates.append(candidate)
	if rarity_templates.is_empty():
		push_warning("EquipmentDropSystem: レアリティ専用テンプレートがありません -> %s" % rarity_id)
		return null
	var template: Dictionary = rarity_templates[randi() % rarity_templates.size()]
	var item := EquipmentData.new()
	_serial += 1
	item.instance_id = "%s_%d_%d" % [template.get("id", "equipment"), Time.get_ticks_msec(), _serial]
	item.template_id = template.get("id", "")
	item.display_name = template.get("display_name", "装備")
	item.slot = template.get("slot", "weapon")
	item.attack_kind = template.get("attack_kind", "slash")
	item.icon_path = template.get("icon_path", "")
	var readable_icon := "res://assets/visuals/ember_v5/equipment/%s.png" % item.template_id
	if ResourceLoader.exists(readable_icon):
		item.icon_path = readable_icon
	elif ResourceLoader.exists("res://assets/ui/equipment_readable_v4/%s.png" % item.template_id):
		item.icon_path = "res://assets/ui/equipment_readable_v4/%s.png" % item.template_id
	item.rarity = rarity_id
	var available_stats: Array = template.get("stats", []).duplicate()
	available_stats.shuffle()
	var stat_count := int(rarity.get("affix_count", 1))
	var stat_ranges: Dictionary = _drop_table.get("stat_ranges", {}).get(rarity_id, {})
	for i in mini(stat_count, available_stats.size()):
		var stat_name: String = available_stats[i]
		var range_values: Array = stat_ranges.get(stat_name, [0.0, 0.0])
		var rolled_value := randf_range(float(range_values[0]), float(range_values[1]))
		item.stats[stat_name] = roundf(rolled_value) if stat_name in ["attack_power", "defense", "max_hp"] else snappedf(rolled_value, 0.001)
	if bool(rarity.get("special_effect", false)):
		var effects: Array = _drop_table.get("special_effects", [])
		if not effects.is_empty():
			var effect: Dictionary = effects[randi() % effects.size()]
			var effect_id := String(effect.get("id", ""))
			if effect_id != "":
				item.special_effects.append(effect_id)
				item.special_effect_values[effect_id] = Dictionary(effect.get(rarity_id, {})).duplicate(true)
	return item

func debug_generate_equipment(template_id: String, rarity_id: String) -> EquipmentData:
	if not OS.is_debug_build():
		return null
	return _generate_equipment(rarity_id, template_id)

func debug_get_templates() -> Array:
	return _templates.duplicate(true) if OS.is_debug_build() else []

func debug_drop_equipment(item: EquipmentData, position: Vector2) -> GroundEquipmentItem:
	var runtime_world := GameManager.get_runtime_world(self)
	if not OS.is_debug_build() or item == null or ground_item_scene == null or runtime_world == null:
		return null
	return _spawn_equipment_drop(item, position, false)

func debug_force_enemy_drop(position: Vector2, is_elite: bool, is_boss: bool, room_number: int = 1) -> GroundEquipmentItem:
	if not OS.is_debug_build():
		return null
	var rarity_id := _roll_boss_rarity_id(room_number) if is_boss else ""
	return _spawn_equipment_drop(_generate_equipment(rarity_id), position, false)

func _roll_rarity() -> Dictionary:
	var rarities: Array = _drop_table.get("rarities", [])
	var total := 0.0
	for rarity in rarities:
		total += float(rarity.get("weight", 0.0))
	var roll := randf() * total
	for rarity in rarities:
		roll -= float(rarity.get("weight", 0.0))
		if roll <= 0.0:
			return rarity
	return rarities[0] if not rarities.is_empty() else {"id":"uncommon", "affix_count":1}

func _rarity_definition(rarity_id: String) -> Dictionary:
	for rarity in _drop_table.get("rarities", []):
		if String(rarity.get("id", "")) == rarity_id:
			return Dictionary(rarity)
	return {}

func _find_safe_drop_position(origin: Vector2) -> Vector2:
	var map: DungeonMap = GameManager.dungeon_map
	if map == null:
		return origin
	var origin_cell := map.world_to_grid(origin)
	var candidates := map.get_spawn_cells(Rect2i(origin_cell - Vector2i(8, 8), Vector2i(17, 17))) if map.get_meta("floor_only", false) else map.get_spawn_cells()
	# Stay on the death/chest side of a wall, instead of scattering into a
	# neighbouring corridor. Navigation-clear cells leave room for the player.
	for room in map.rooms:
		if not map.get_meta("floor_only", false) and room.has_point(origin_cell):
			candidates = map.get_spawn_cells(room)
			break
	candidates.sort_custom(func(a: Vector2i, b: Vector2i): return map.grid_to_world(a).distance_squared_to(origin) < map.grid_to_world(b).distance_squared_to(origin))
	var shape := CircleShape2D.new()
	shape.radius = 20.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1 # Walls and solid decorations; not enemy bodies.
	var player := get_tree().get_first_node_in_group("player") as CollisionObject2D
	if player: query.exclude = [player.get_rid()]
	var space := get_viewport().find_world_2d().direct_space_state
	var content := get_tree().get_nodes_in_group("map_content")
	var existing := get_tree().get_nodes_in_group("ground_equipment")
	var crowded_fallback := Vector2.INF
	for cell in candidates:
		var point := map.grid_to_world(cell)
		query.transform = Transform2D(0.0, point)
		if not space.intersect_shape(query, 1).is_empty(): continue
		var blocked := false
		for node in content:
			if node.is_queued_for_deletion(): continue
			if node is TreasureChest or (node is MapLandmark and node.kind == "descent_stairs"):
				var separation := 112.0
				if node is TreasureChest and not node.is_boss_chest:
					separation = 48.0 if node.is_opened else 96.0
				if point.distance_to(node.global_position) < separation:
					blocked = true
					break
		if blocked: continue
		if not crowded_fallback.is_finite(): crowded_fallback = point
		for item in existing:
			if not item.is_queued_for_deletion() and point.distance_to(item.global_position) < 56.0:
				blocked = true
				break
		if not blocked: return point
	# A crowded bag of drops may share a safe floor, never a wall or a chest.
	return crowded_fallback

func _read_json(path: String) -> Dictionary:
	var parsed = _read_json_variant(path)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _read_json_variant(path: String):
	if not FileAccess.file_exists(path):
		push_warning("EquipmentDropSystem: 設定がありません -> %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(file.get_as_text()) if file else null
