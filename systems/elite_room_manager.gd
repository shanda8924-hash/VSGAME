extends Node2D
class_name EliteRoomManager
## 精鋭部屋(Elite Room): DungeonGeneratorが指定したmap.elite_room_indicesの部屋に
## プレイヤーが入ると強化された敵を出現させる。出入り口は塞がず逃走可能。
## 全滅させると確定報酬(欠片+メタ通貨)と派手な演出が入る。
##
## 通常のWaveSpawnerによる雑魚湧きは、EventBus.elite_room_entered/clearedを介して
## 精鋭部屋の攻略中だけ止める(疎結合を保つため、WaveSpawnerを直接は参照しない)。
## これとは別に、spawn_curve.jsonの時間帯別間隔で単体の巡回精鋭を通常Waveへ混ぜる。
## 巡回精鋭は部屋イベントを開始しないため、通常敵を止めず、報酬用の壁も生成しない。

@export var enemy_scene: PackedScene
@export var elite_enemy_ids: Array[String] = ["elite_orc", "werebear", "armored_skeleton", "greatsword_skeleton"]
@export var elite_min_count: int = 1
@export var elite_max_count: int = 2
@export var elite_stat_multiplier_min: float = 1.8
@export var elite_stat_multiplier_max: float = 2.2
## 通常個体と一目で区別できるよう、見た目を少し大きくする(EnemyBasic.visual_scale_multiplier
## 経由でAnimatedSprite2D.scaleと当たり判定用CollisionShape2Dの両方に乗算される)。
## 通常敵の既定値(1.40)より一回り大きい値にして、精鋭であることが分かるようにする。
@export var elite_visual_scale: float = 1.78
@export var elite_meta_currency_reward: int = 50

@export var screen_effects_path: NodePath
@export var vfx_pool_path: NodePath

signal roaming_elite_spawned(spawn_time: float, enemy: EnemyBasic)

@onready var _screen_effects: ScreenEffects = get_node_or_null(screen_effects_path)
@onready var _vfx_pool: VFXPoolManager = get_node_or_null(vfx_pool_path)

var _map: DungeonMap
var _rooms_active: Dictionary = {}        # room_index(int) -> bool
var _rooms_cleared: Dictionary = {}       # room_index(int) -> bool
var _elite_enemies_alive: Dictionary = {} # room_index(int) -> Array[Node]
var _affix_settings: Dictionary = {}
var _spawn_settings: Dictionary = {}
var _next_roaming_spawn_at: float = INF
var _last_roaming_spawn_at: float = 0.0
var _retry_not_before: float = 0.0
var _boss_fight_active := false
var _floor_cells: Array[Vector2i] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	EventBus.boss_fight_started.connect(func(_name): _boss_fight_active = true)
	EventBus.boss_fight_ended.connect(func(): _boss_fight_active = false)

## Game.gdがGameManager.start_run()+StageEnvironment.build_dungeon()の直後に呼び出す。
func setup(map: DungeonMap) -> void:
	clear_map_runtime()
	_map = map
	_boss_fight_active = false
	_affix_settings = _load_affix_settings()
	_spawn_settings = _load_json("res://data/elite_affixes/spawn_curve.json")
	_rng.randomize()
	if map.get_meta("exploration_layout", false):
		return
	_last_roaming_spawn_at = GameManager.elapsed_seconds
	_next_roaming_spawn_at = _last_roaming_spawn_at + _roll_delay(_spawn_settings.get("initial_delay_range", [90.0, 120.0]), _rng)
	_retry_not_before = 0.0
	_floor_cells = map.get_spawn_cells()
	for room_index in map.elite_room_indices:
		_create_trigger_area(room_index)

func clear_map_runtime() -> void:
	for child in get_children():
		if child is Area2D:
			child.queue_free()
	_rooms_active.clear()
	_rooms_cleared.clear()
	_elite_enemies_alive.clear()
	_floor_cells.clear()
	_map = null
	_retry_not_before = 0.0

func _process(_delta: float) -> void:
	if _map == null or GameManager.run_state != GameManager.RunState.PLAYING:
		return
	if _map.get_meta("exploration_layout", false):
		return
	var wave := get_parent().get_node_or_null("WaveSpawner") as WaveSpawner
	if wave and (wave.is_map_spawn_suppressed() or wave._active_enemy_count() >= wave._map_enemy_cap): return
	if _boss_fight_active or _has_active_elite_room():
		return
	var elapsed := GameManager.elapsed_seconds
	if elapsed < _retry_not_before:
		return
	var soft_pity := float(_spawn_settings.get("soft_pity_seconds", 180.0))
	var pity_deadline := _last_roaming_spawn_at + soft_pity
	if elapsed < minf(_next_roaming_spawn_at, pity_deadline):
		return
	if _spawn_roaming_elite():
		_last_roaming_spawn_at = elapsed
		_next_roaming_spawn_at = elapsed + _roll_delay(_get_delay_range(elapsed), _rng)
		_retry_not_before = 0.0
	else:
		_retry_not_before = elapsed + float(_spawn_settings.get("retry_delay_seconds", 5.0))

func _has_active_elite_room() -> bool:
	for active in _rooms_active.values():
		if bool(active):
			return true
	return false

## 10分相当の頻度テスト用。実ゲームと同じ設定を独立RNGで進めるため、
## テストが本番の乱数状態やスポーン順を消費しない。
func simulate_roaming_spawn_times(duration_seconds: float, seed_value: int = 1, blocked_windows: Array = []) -> Array[float]:
	var simulation_rng := RandomNumberGenerator.new()
	simulation_rng.seed = seed_value
	var result: Array[float] = []
	var last_spawn := 0.0
	var next_spawn := _roll_delay(_spawn_settings.get("initial_delay_range", [90.0, 120.0]), simulation_rng)
	var soft_pity := float(_spawn_settings.get("soft_pity_seconds", 180.0))
	while true:
		var elapsed := minf(next_spawn, last_spawn + soft_pity)
		elapsed = _shift_past_blocked_windows(elapsed, blocked_windows)
		if elapsed > duration_seconds:
			break
		result.append(elapsed)
		last_spawn = elapsed
		next_spawn = elapsed + _roll_delay(_get_delay_range(elapsed), simulation_rng)
	return result

func _shift_past_blocked_windows(value: float, blocked_windows: Array) -> float:
	var shifted := value
	var changed := true
	while changed:
		changed = false
		for window in blocked_windows:
			if not (window is Array) or window.size() < 2:
				continue
			var start := float(window[0])
			var finish := float(window[1])
			if shifted >= start and shifted < finish:
				shifted = finish
				changed = true
	return shifted

func _get_delay_range(elapsed: float) -> Array:
	var selected: Array = [150.0, 180.0]
	for phase in _spawn_settings.get("phases", []):
		if elapsed >= float(phase.get("start_seconds", 0.0)):
			selected = phase.get("delay_range", selected)
		else:
			break
	return selected

func _roll_delay(values: Array, source_rng: RandomNumberGenerator) -> float:
	if values.size() < 2:
		return 150.0
	return source_rng.randf_range(float(values[0]), float(values[1]))

func _spawn_roaming_elite() -> bool:
	if enemy_scene == null or elite_enemy_ids.is_empty():
		return false
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return false
	var ids: Array = WaveSpawner.MAP_ENEMY_ROSTERS.get(GameManager.current_map_index, {}).get("strong", elite_enemy_ids)
	var enemy_id: String = ids[_rng.randi() % ids.size()]
	var base_data: EnemyData = DataLoader.enemies.get(enemy_id)
	if base_data == null:
		return false
	var wave := get_parent().get_node_or_null("WaveSpawner") as WaveSpawner
	var spawn_position := wave._pick_spawn_position(player.global_position) if wave else _pick_roaming_position(player.global_position)
	if not spawn_position.is_finite():
		return false # 既存のretry_delayで再試行。地形内部へのfallbackはしない。
	var enemy := enemy_scene.instantiate() as EnemyBasic
	enemy.enemy_data = base_data
	if wave:
		enemy.room_hp_multiplier = wave._map_hp_multiplier
		enemy.room_damage_multiplier = wave._map_damage_multiplier
	enemy.elite_stat_multiplier = _rng.randf_range(elite_stat_multiplier_min, elite_stat_multiplier_max)
	enemy.visual_scale_multiplier = elite_visual_scale
	GameManager.get_runtime_world(self).add_child(enemy)
	enemy.global_position = spawn_position
	attach_exploration_affix(enemy, GameManager.current_map_index)
	roaming_elite_spawned.emit(GameManager.elapsed_seconds, enemy)
	return true

func _pick_roaming_position(near_world_pos: Vector2) -> Vector2:
	if _map == null:
		var fallback_radius := float(_spawn_settings.get("spawn_radius", 520.0))
		return near_world_pos + Vector2.from_angle(_rng.randf() * TAU) * fallback_radius
	if _floor_cells.is_empty():
		return Vector2.INF
	var near_grid := _map.world_to_grid(near_world_pos)
	var max_cells := float(_spawn_settings.get("spawn_radius", 520.0)) / DungeonMap.CELL_WORLD_SIZE
	var min_cells := float(_spawn_settings.get("min_spawn_distance", 280.0)) / DungeonMap.CELL_WORLD_SIZE
	var candidates: Array[Vector2i] = []
	for cell in _floor_cells:
		var distance := Vector2(cell - near_grid).length()
		if distance >= min_cells and distance <= max_cells:
			candidates.append(cell)
	if candidates.is_empty():
		for cell in _floor_cells:
			if Vector2(cell - near_grid).length() >= min_cells:
				candidates.append(cell)
	if candidates.is_empty():
		return Vector2.INF
	return _map.grid_to_world(candidates[_rng.randi() % candidates.size()])

func _create_trigger_area(room_index: int) -> void:
	var room: Rect2i = _map.rooms[room_index]
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 1 # Player(CharacterBody2D既定のレイヤー1)を検出する
	area.monitoring = true
	area.monitorable = false
	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = Vector2(room.size) * DungeonMap.CELL_WORLD_SIZE
	shape.shape = rect_shape
	area.add_child(shape)
	area.position = _map.grid_to_world(room.position) + Vector2(room.size) * DungeonMap.CELL_WORLD_SIZE / 2.0
	area.body_entered.connect(_on_body_entered.bind(room_index))
	add_child(area)

func _on_body_entered(body: Node2D, room_index: int) -> void:
	if not body.is_in_group("player"):
		return
	if _rooms_cleared.get(room_index, false) or _rooms_active.get(room_index, false):
		return
	# body_enteredはPhysicsServerが接触クエリをflushしている最中に発火する。
	# ここでEnemyBasicをadd_childすると、その_ready()内のCollisionShape拡大が
	# "Can't change this state while flushing queries"で拒否されるため、イベント開始と
	# scene生成は安全なdeferredタイミングへ送る。activeだけ先に立てて多重予約を防ぐ。
	_rooms_active[room_index] = true
	call_deferred("_begin_elite_event", room_index)

func _begin_elite_event(room_index: int) -> void:
	if _map == null or room_index < 0 or room_index >= _map.rooms.size():
		_rooms_active[room_index] = false
		return
	EventBus.elite_room_entered.emit(room_index)
	_spawn_elite_enemies(room_index)

func _spawn_elite_enemies(room_index: int) -> void:
	if enemy_scene == null or elite_enemy_ids.is_empty():
		_clear_room(room_index) # 生成できない異常系では即座に解放する(部屋に閉じ込めない)
		return
	var room: Rect2i = _map.rooms[room_index]
	var count := randi_range(elite_min_count, elite_max_count)
	var alive: Array[Node] = []
	for i in count:
		var enemy_id: String = elite_enemy_ids[randi() % elite_enemy_ids.size()]
		var base_data: EnemyData = DataLoader.enemies.get(enemy_id)
		if base_data == null:
			continue
		var spawn_position := _pick_position_in_room(room)
		if not spawn_position.is_finite():
			continue
		var enemy := enemy_scene.instantiate()
		enemy.enemy_data = base_data
		enemy.elite_stat_multiplier = randf_range(elite_stat_multiplier_min, elite_stat_multiplier_max)
		enemy.visual_scale_multiplier = elite_visual_scale
		GameManager.get_runtime_world(self).add_child(enemy)
		enemy.global_position = spawn_position
		enemy.health_component.died.connect(_on_elite_enemy_died.bind(enemy, room_index))
		_attach_affixes(enemy)
		alive.append(enemy)
	if alive.is_empty():
		_clear_room(room_index)
		return
	_elite_enemies_alive[room_index] = alive

func _attach_affixes(enemy: EnemyBasic) -> void:
	var definitions: Dictionary = _affix_settings.get("affixes", {})
	var available: Array = definitions.keys()
	if available.is_empty():
		return
	available.shuffle()
	var count_range := _get_affix_count_range()
	var count := mini(randi_range(count_range.x, count_range.y), available.size())
	var ids: Array[String] = []
	for i in count:
		ids.append(String(available[i]))
	var component := EliteAffixComponent.new()
	component.configure(enemy, ids, definitions)
	enemy.add_child(component)

func _get_affix_count_range() -> Vector2i:
	var key := "early_affix_count"
	if GameManager.elapsed_seconds >= float(_affix_settings.get("mid_end_seconds", 300.0)):
		key = "late_affix_count"
	elif GameManager.elapsed_seconds >= float(_affix_settings.get("early_end_seconds", 120.0)):
		key = "mid_affix_count"
	var values: Array = _affix_settings.get(key, [1, 1])
	return Vector2i(int(values[0]), int(values[1]))

func _load_affix_settings() -> Dictionary:
	return _load_json("res://data/elite_affixes/default.json")

func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("EliteRoomManager: 設定を読み込めません -> %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _pick_position_in_room(room: Rect2i) -> Vector2:
	# 精鋭部屋はPillar Fieldと共存する。矩形内の乱数座標だけでは、床から
	# 除外済みの2x2噴水・柱まで選んでしまうため、同じ室内の安全床だけを使う。
	var interior := room.grow(-1)
	if not interior.has_area():
		return Vector2.INF
	var cells := _map.get_spawn_cells(interior)
	if cells.is_empty():
		return Vector2.INF
	return _map.grid_to_world(cells[randi() % cells.size()])

func _on_elite_enemy_died(enemy: Node, room_index: int) -> void:
	var alive: Array = _elite_enemies_alive.get(room_index, [])
	alive.erase(enemy)
	_elite_enemies_alive[room_index] = alive
	if alive.is_empty():
		_clear_room(room_index)

func _clear_room(room_index: int) -> void:
	_rooms_active[room_index] = false
	_rooms_cleared[room_index] = true
	EventBus.elite_room_cleared.emit(room_index)
	_grant_rewards(room_index)

func _grant_rewards(room_index: int) -> void:
	# MAP探索はElite本体からの確定装備+経験値が報酬。ROOM用の欠片Modalは混ぜない。
	if not GameManager.map_mode_active:
		SaveManager.add_meta_currency(elite_meta_currency_reward)
	# TODO: 属性の欠片報酬(FragmentSelect)は属性システム廃止に伴い撤去した。
	# ゴールドとショップに差し替える予定。
	_play_reward_effect(room_index)

## 通常の雑魚撃破よりも派手な演出にするため、既存のMassKillTracker用パーティクル
## プールを再利用しつつ、報酬らしい金色のフラッシュ+強めの画面シェイクを重ねる。
func _play_reward_effect(room_index: int) -> void:
	var room: Rect2i = _map.rooms[room_index]
	var world_center := _map.grid_to_world(room.position + room.size / 2)
	if _vfx_pool:
		_vfx_pool.play_mass_kill_burst(world_center)
	if _screen_effects:
		_screen_effects.shake(10.0, 0.4)
		_screen_effects.flash(Color(1.0, 0.85, 0.3), 0.35)

func attach_exploration_affix(enemy: EnemyBasic, map_index: int) -> void:
	var definitions: Dictionary = _affix_settings.get("affixes", {})
	var available: Array = definitions.keys()
	if available.is_empty(): return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_map.get_meta("layout_seed", 1))
	var ids: Array[String] = []
	for i in mini(2 if map_index == 3 else 1, available.size()):
		var index := rng.randi_range(0, available.size()-1)
		ids.append(String(available.pop_at(index)))
	var component := EliteAffixComponent.new()
	component.configure(enemy, ids, definitions)
	enemy.add_child(component)
