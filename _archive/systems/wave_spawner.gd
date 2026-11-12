extends Node2D
class_name WaveSpawner
signal sector_wave_cleared()
## 時間経過に応じて敵を生成する簡易版ウェーブシステム。
## enemy_data_list を空にしておけばDataLoaderから自動的に全敵データを読み込む
## (JSON追加だけで新しい敵がスポーン対象になる)。

@export var enemy_scene: PackedScene
@export var enemy_data_list: Array[EnemyData] = []
## data/difficulty/*.json のカーブid。ステージごとに違うカーブを使いたくなったら
## ここを差し替えるだけでよい(WaveSpawner自体のロジックは変更不要)。
@export var difficulty_curve_id: String = "default"
## カーブが読み込めなかった場合のフォールバック値。
@export var fallback_spawn_interval: float = 1.5
@export var spawn_radius: float = 480.0
## プレイヤーからこの距離より近い床マスには湧かせない(至近距離で避ける余地なく
## 出現するのを防ぐため)。
@export var min_spawn_distance: float = 220.0


## 通常敵23種の正式なMAP・基礎階級割り当て。
## Eliteはstrong個体へのAffix付与、midboss/bossはBossSpawnerが担当する。
const ENEMY_HIERARCHY := ["mob", "standard", "strong", "elite", "midboss", "boss"]
const MAP_ENEMY_ROSTERS := {
	1: {
		"mob": ["slime", "bat", "fast_enemy"],
		"standard": ["basic_enemy", "shield_guard", "skeleton_archer"],
		"strong": ["armored_skeleton", "greatsword_skeleton"],
	},
	2: {
		"mob": ["eyeball_monster"],
		"standard": ["blood_monster_a", "ghostfire", "demoness_a", "werewolf"],
		"strong": ["blood_monster_b", "werebear"],
	},
	3: {
		"mob": ["lava_slime", "hellbat"],
		"standard": ["demoness_b", "hellhound", "orc_rider", "warlock"],
		"strong": ["armored_orc", "elite_orc"],
	},
}
## 敵の役割（Phase 1）。波ごとに主役の役割を変え、プレイヤーの対処を変えさせる。
## rush=速い・低HP、wall=遅い・高HP・ノックバック耐性、ranged=弾で立ち止まりを罰する、
## swarm=小さく大量。ここに無い敵は役割なし（通常の追跡）。
const ENEMY_ROLES := {
	"bat": "rush", "fast_enemy": "rush", "werewolf": "rush", "hellhound": "rush", "orc_rider": "rush",
	"shield_guard": "wall", "basic_enemy": "wall", "blood_monster_a": "wall", "demoness_b": "wall",
	"skeleton_archer": "ranged", "demoness_a": "ranged", "ghostfire": "ranged", "warlock": "ranged",
	"slime": "swarm", "eyeball_monster": "swarm", "lava_slime": "swarm", "hellbat": "swarm",
}
const ROLE_DISPLAY_NAMES := {"rush": "突撃", "wall": "壁", "ranged": "弓兵", "swarm": "群れ"}
## 役割つきの波の間、通常湧きのうちこの割合が主役の役割から選ばれる。
const SURGE_ROLE_BIAS := 0.6
const ROOM_RANK_PATTERNS := {
	"first_guard": ["mob"],
	"guard": ["mob", "standard"],
	"junction_guard": ["mob", "standard"],
	"flank": ["mob", "standard"],
	"cache": ["mob"],
	"antechamber": ["standard", "strong"],
	"key_guard": ["strong", "standard"],
	"elite": ["strong"],
}

var _timer: float = 0.0
var _populated_map: DungeonMap = null
var _exploration_enemy_count := 24
var exploration_placed_count := 0
## 現在進行中の精鋭部屋(Elite Room)攻略の数(通常は0か1だが、念のため
## カウンタにしておき、0より大きい間は雑魚湧きを止める)。
var _active_elite_rooms: int = 0
## ボス戦が進行中かどうか(精鋭部屋と同様、この間は通常の雑魚湧きを止める)。
var _boss_fight_active: bool = false
var _spawning_paused: bool = false
var _map_started_elapsed: float = 0.0
var _map_progress_offset: float = 0.0
var _map_move_speed_multiplier := 1.0
var _map_hp_multiplier: float = 1.0
var _map_damage_multiplier: float = 1.0
var _map_enemy_cap: int = 60
var _map_spawn_batch := Vector2i(1, 2)
var _map_surge_active := false
var _map_surge_interval_multiplier := 1.0
var _map_surge_batch_multiplier := 1.0
var _surge_role := ""
var _sector_active := false
var _sector_room_index := 0
var _sector_remaining := 0
var _sector_rank := "mob"
var _sector_timer := 0.0
var _sector_power := 1.0
var _sector_cells: Array[Vector2i] = []

func _ready() -> void:
	if enemy_data_list.is_empty():
		enemy_data_list = DataLoader.get_all_enemies()
	EventBus.elite_room_entered.connect(_on_elite_room_entered)
	EventBus.elite_room_cleared.connect(_on_elite_room_cleared)
	EventBus.boss_fight_started.connect(_on_boss_fight_started)
	EventBus.boss_fight_ended.connect(_on_boss_fight_ended)

func _on_elite_room_entered(_room_index: int) -> void:
	_active_elite_rooms += 1

func _on_elite_room_cleared(_room_index: int) -> void:
	_active_elite_rooms = maxi(0, _active_elite_rooms - 1)

func _on_boss_fight_started(_boss_display_name: String) -> void:
	_boss_fight_active = true

func _on_boss_fight_ended() -> void:
	_boss_fight_active = false

func _process(delta: float) -> void:
	if GameManager.run_state != GameManager.RunState.PLAYING:
		return
	if _sector_active:
		_tick_sector_wave(delta)
		return
	if _spawning_paused:
		return
	if _active_elite_rooms > 0 or (_boss_fight_active and not GameManager.survival_mode_active):
		return # 精鋭部屋の攻略中・ボス戦中は通常の雑魚湧きを止める
	_timer -= delta
	if _timer <= 0.0:
		_recycle_distant_enemies()
		var effective_batch := _effective_map_spawn_batch()
		var amount := randi_range(effective_batch.x, effective_batch.y) if GameManager.map_mode_active else 1
		for _index in amount:
			if _active_enemy_count() >= _map_enemy_cap:
				break
			_spawn_enemy()
		_timer = _current_spawn_interval()

## 経過時間(GameManager.elapsed_seconds)を難易度カーブのbreakpoint間で線形補間し、
## 現在のspawn_intervalを求める(数値が段階的にカクつかないようにするため)。
func _current_spawn_interval() -> float:
	var base_interval := _base_spawn_interval()
	return maxf(base_interval * (_map_surge_interval_multiplier if _map_surge_active else 1.0), 0.08)

func _base_spawn_interval() -> float:
	var breakpoints: Array = DataLoader.difficulty_curves.get(difficulty_curve_id, [])
	if breakpoints.is_empty():
		return fallback_spawn_interval

	var elapsed := GameManager.elapsed_seconds
	if GameManager.map_mode_active:
		elapsed = maxf(GameManager.elapsed_seconds - _map_started_elapsed, 0.0)
	var first: Dictionary = breakpoints[0]
	if elapsed <= float(first.get("time_seconds", 0.0)):
		return float(first.get("spawn_interval", fallback_spawn_interval))

	for i in range(breakpoints.size() - 1):
		var current: Dictionary = breakpoints[i]
		var next: Dictionary = breakpoints[i + 1]
		var t0 := float(current.get("time_seconds", 0.0))
		var t1 := float(next.get("time_seconds", 0.0))
		if elapsed <= t1:
			var v0 := float(current.get("spawn_interval", fallback_spawn_interval))
			var v1 := float(next.get("spawn_interval", fallback_spawn_interval))
			if t1 <= t0:
				return v1
			var ratio := (elapsed - t0) / (t1 - t0)
			return lerpf(v0, v1, ratio)

	# 最後のbreakpointより経過時間が長い場合は、カーブ最終値を維持する。
	var last: Dictionary = breakpoints[breakpoints.size() - 1]
	return float(last.get("spawn_interval", fallback_spawn_interval))

func _map_elapsed() -> float:
	return maxf(GameManager.elapsed_seconds - _map_started_elapsed, 0.0) if GameManager.map_mode_active else GameManager.elapsed_seconds

## Intervalと同じBreakpointから段階的な同時出現数も読む。MAP別spawn_batchは
## 後半の上限として使い、開始直後の少数戦から終盤の大群まで密度を引き上げる。
func _base_map_spawn_batch() -> Vector2i:
	var breakpoints: Array = DataLoader.difficulty_curves.get(difficulty_curve_id, [])
	if breakpoints.is_empty():
		return _map_spawn_batch
	var selected: Dictionary = breakpoints[0]
	var elapsed := _map_elapsed()
	for point_variant in breakpoints:
		var point := point_variant as Dictionary
		if elapsed < float(point.get("time_seconds", 0.0)):
			break
		selected = point
	var batch: Array = selected.get("spawn_batch", [])
	if batch.size() < 2:
		return _map_spawn_batch
	var maximum := maxi(_map_spawn_batch.y, 1)
	var minimum := clampi(int(batch[0]), 1, maximum)
	return Vector2i(minimum, clampi(int(batch[1]), minimum, maximum))

var _floor_cells: Array[Vector2i] = []

## GameManager.elapsed_seconds <= min_elapsed_secondsの敵だけを候補にする。
## ランごとに経過時間は増え続けるため、_ready()時ではなく毎回のスポーン試行時に
## 都度フィルタし直す(キャッシュしない)。
func _get_eligible_enemy_data(progress_seconds: float = -1.0) -> Array[EnemyData]:
	var eligible: Array[EnemyData] = []
	var elapsed := GameManager.elapsed_seconds if progress_seconds < 0.0 else progress_seconds
	if progress_seconds < 0.0 and GameManager.map_mode_active:
		elapsed = maxf(GameManager.elapsed_seconds - _map_started_elapsed, 0.0) + _map_progress_offset
	for data in enemy_data_list:
		if elapsed >= data.min_elapsed_seconds:
			eligible.append(data)
	return eligible

func _spawn_enemy() -> void:
	if enemy_scene == null or enemy_data_list.is_empty():
		return
	var eligible := _survival_enemy_pool() if GameManager.map_mode_active else _get_eligible_enemy_data()
	if eligible.is_empty():
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var spawn_position := _pick_spawn_position(player.global_position)
	if not spawn_position.is_finite():
		return
	_spawn_enemy_at(eligible[randi() % eligible.size()], spawn_position, player)

## 1体を生成して戦場へ置く。サバイバルの速度上限・時間経過倍率・役割の補正をここで一括して掛ける。
func _spawn_enemy_at(data: EnemyData, spawn_position: Vector2, player: Node2D) -> EnemyBasic:
	var enemy := enemy_scene.instantiate() as EnemyBasic
	enemy.global_position = spawn_position
	enemy.enemy_data = data
	enemy.room_hp_multiplier = _map_hp_multiplier
	enemy.room_damage_multiplier = _map_damage_multiplier
	var role := String(ENEMY_ROLES.get(data.id, ""))
	if GameManager.survival_mode_active:
		# Walking pursuers leave room to steer; authored boss moves keep their timings.
		var character: CharacterData = DataLoader.characters.get(GameManager.selected_character_id)
		var walk_speed: float = character.move_speed * Player.MOVE_SPEED_MULTIPLIER if character else (player as Player).movement_component.base_speed
		var speed_cap := 0.75
		if role == "rush": speed_cap = 0.92 # 突撃型だけはほぼ並走できる速さまで許す
		enemy.room_move_speed_multiplier = minf(_map_move_speed_multiplier, walk_speed * speed_cap / maxf(enemy.enemy_data.move_speed, 1.0))
	if GameManager.survival_mode_active:
		var progress := clampf(_map_elapsed() / GameManager.survival_duration_seconds, 0.0, 1.0)
		enemy.room_hp_multiplier *= 1.0 + progress * 0.9
		enemy.room_damage_multiplier *= 1.0 + progress * 0.4
	match role:
		"wall":
			enemy.room_hp_multiplier *= 1.8
			enemy.room_move_speed_multiplier *= 0.7
			enemy.visual_scale_multiplier *= 1.15
			enemy.set_meta("wall", true)
		"rush":
			enemy.room_hp_multiplier *= 0.7
			enemy.attack_windup_multiplier = 0.55
		"swarm":
			enemy.room_hp_multiplier *= 0.6
			enemy.attack_windup_multiplier = 0.7
			enemy.visual_scale_multiplier *= 0.88
	if role != "":
		enemy.set_meta("role", role)
	enemy.set_meta("survival_wave", true)
	GameManager.get_runtime_world(self).add_child(enemy)
	return enemy

## 波の主役の役割。空文字で解除。通常湧きの6割がこの役割から選ばれる。
func set_surge_role(role: String) -> void:
	_surge_role = role

func get_surge_role() -> String:
	return _surge_role

## 現在のMAPのmob+standardから、指定の役割を持つ敵だけを集める。
func _role_pool(role: String) -> Array[EnemyData]:
	var roster: Dictionary = MAP_ENEMY_ROSTERS.get(GameManager.current_map_index, MAP_ENEMY_ROSTERS[1])
	var pool: Array[EnemyData] = []
	for rank_name in ["mob", "standard"]:
		for id: String in roster.get(rank_name, []):
			if String(ENEMY_ROLES.get(id, "")) != role:
				continue
			var data: EnemyData = DataLoader.enemies.get(id)
			if data: pool.append(data)
	return pool

## 包囲湧き：画面外のリング上へ均等な角度で一斉に出す。波の開始合図に使う。
## 床だけの戦場（floor_only）専用。壁のある層では通常の床マス抽選へ落とす。
func spawn_ring(count: int, role: String = "") -> int:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or enemy_scene == null or count <= 0:
		return 0
	var pool := _role_pool(role) if role != "" else []
	if pool.is_empty():
		pool = _survival_enemy_pool()
	if pool.is_empty():
		return 0
	var spawned := 0
	var start_angle := randf() * TAU
	var map: DungeonMap = GameManager.dungeon_map
	var floor_only: bool = map != null and bool(map.get_meta("floor_only", false))
	var half := get_viewport_rect().size / player.camera.zoom * 0.5 + Vector2(72, 72)
	var shape := CircleShape2D.new()
	shape.radius = 24.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 9
	for index in count:
		if _active_enemy_count() >= _map_enemy_cap:
			break
		var point := Vector2.INF
		if floor_only:
			for attempt in 6:
				var direction := Vector2.from_angle(start_angle + TAU * float(index) / float(count) + randf_range(-0.12, 0.12))
				var radius := minf(half.x / maxf(absf(direction.x), 0.001), half.y / maxf(absf(direction.y), 0.001)) + 24.0 + attempt * 20.0
				var candidate := player.global_position + direction * radius
				query.transform = Transform2D(0, candidate)
				if get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
					point = candidate
					break
		else:
			point = _pick_spawn_position(player.global_position)
		if not point.is_finite():
			continue
		_spawn_enemy_at(pool[(index + randi() % pool.size()) % pool.size()], point, player)
		spawned += 1
	return spawned

## 強敵（strong階級）を1体、画面外へ出す。波の中盤の山場に使う。
func spawn_strong_enemy() -> EnemyBasic:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or enemy_scene == null:
		return null
	var roster: Dictionary = MAP_ENEMY_ROSTERS.get(GameManager.current_map_index, MAP_ENEMY_ROSTERS[1])
	var ids: Array = roster.get("strong", [])
	if ids.is_empty():
		return null
	var data: EnemyData = DataLoader.enemies.get(String(ids.pick_random()))
	if data == null:
		return null
	var point := _pick_spawn_position(player.global_position)
	if not point.is_finite():
		return null
	# 上限いっぱいなら、いちばん遠い通常湧きを1体引き取って枠を空ける（上限は超えない）。
	while _active_enemy_count() >= _map_enemy_cap:
		var farthest: Node2D = null
		var farthest_distance := -1.0
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if not enemy.get_meta("survival_wave", false) or enemy.is_queued_for_deletion():
				continue
			var distance: float = enemy.global_position.distance_squared_to(player.global_position)
			if distance > farthest_distance:
				farthest_distance = distance
				farthest = enemy
		if farthest == null:
			return null
		farthest.queue_free()
	var enemy := _spawn_enemy_at(data, point, player)
	enemy.set_meta("surge_strong", true)
	return enemy

func configure_map_phase(config: Dictionary) -> void:
	_sector_active = false
	if GameManager.dungeon_map != _populated_map:
		encounters_ready = false
		encounter_enemies.clear()
	_spawning_paused = false
	_active_elite_rooms = 0
	_boss_fight_active = false
	_floor_cells.clear()
	_map_started_elapsed = GameManager.elapsed_seconds
	_map_progress_offset = float(config.get("enemy_progress_offset", 0.0))
	_map_move_speed_multiplier = float(config.get("enemy_move_speed_multiplier", 1.0))
	_map_hp_multiplier = maxf(float(config.get("enemy_hp_multiplier", 1.0)), 0.1)
	_map_damage_multiplier = maxf(float(config.get("enemy_damage_multiplier", 1.0)), 0.1)
	_map_enemy_cap = maxi(int(config.get("enemy_cap", 60)), 1)
	if GameManager.survival_mode_active and (DisplayServer.is_touchscreen_available() or "--touch-preview" in OS.get_cmdline_user_args()):
		_map_enemy_cap = mini(_map_enemy_cap, 96)
	var batch: Array = config.get("spawn_batch", [1, 2])
	_map_spawn_batch = Vector2i(maxi(int(batch[0]), 1), maxi(int(batch[1]), 1)) if batch.size() >= 2 else Vector2i(1, 2)
	set_map_surge(false)
	_surge_role = ""
	difficulty_curve_id = String(config.get("difficulty_curve_id", "map_exploration"))
	_timer = 1.0
	_exploration_enemy_count = int(config.get("exploration_enemy_count", 24))
	# No authored room guards or key: start the timed horde instead.
	_populated_map = GameManager.dungeon_map
	exploration_placed_count = 0
	encounter_enemies.clear()
	encounter_defeated.clear()
	encounters_ready = true

func start_sector_wave(room_index: int, total: int, rank: String, power: float = 1.0) -> void:
	_sector_room_index = room_index
	_sector_cells.clear()
	var map := GameManager.dungeon_map
	if map and room_index >= 0 and room_index < map.rooms.size():
		_sector_cells = map.get_spawn_cells(map.rooms[room_index].grow(-2))
		if _sector_cells.is_empty():
			_sector_cells = map.get_spawn_cells(map.rooms[room_index].grow(-1))
	_sector_remaining = maxi(total, 1)
	_sector_rank = rank
	_sector_power = power
	_sector_timer = 0.25
	_sector_active = true
	_spawning_paused = true

func stop_sector_wave() -> void:
	_sector_active = false
	_sector_remaining = 0
	_sector_cells.clear()

func _tick_sector_wave(delta: float) -> void:
	if _active_elite_rooms > 0 or _boss_fight_active:
		return
	_sector_timer -= delta
	if _sector_remaining > 0 and _sector_timer <= 0.0:
		var alive := _active_sector_enemy_count()
		var cap := 28 if DisplayServer.is_touchscreen_available() else 42
		if GameManager.dungeon_map.get_meta("isolated_room", false):
			cap = 16
		for index in mini(mini(3, _sector_remaining), maxi(cap - alive, 0)):
			if _spawn_sector_enemy():
				_sector_remaining -= 1
		_sector_timer = 0.58
	if _sector_remaining <= 0 and _active_sector_enemy_count() == 0:
		_sector_active = false
		sector_wave_cleared.emit()

func _active_sector_enemy_count() -> int:
	var count := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.get_meta("sector_wave", false):
			count += 1
	return count

func _spawn_sector_enemy() -> bool:
	var map := GameManager.dungeon_map
	if map == null or _sector_room_index < 0 or _sector_room_index >= map.rooms.size():
		return false
	var roster: Dictionary = MAP_ENEMY_ROSTERS.get(GameManager.current_map_index, MAP_ENEMY_ROSTERS[1])
	var ids: Array = roster.get(_sector_rank, roster.get("mob", []))
	if ids.is_empty():
		return false
	if _sector_cells.is_empty():
		return false
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	var shape := CircleShape2D.new()
	shape.radius = 24.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 9
	for attempt in 24:
		var point := map.grid_to_world(_sector_cells.pick_random())
		if actor and point.distance_to(actor.global_position) < 115.0:
			continue
		query.transform = Transform2D(0.0, point)
		if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
			continue
		var data: EnemyData = DataLoader.enemies.get(ids.pick_random())
		if data == null:
			return false
		var enemy := enemy_scene.instantiate() as EnemyBasic
		enemy.global_position = point
		enemy.enemy_data = data
		enemy.room_hp_multiplier = _map_hp_multiplier * _sector_power
		enemy.room_damage_multiplier = _map_damage_multiplier * _sector_power
		enemy.set_meta("sector_wave", true)
		GameManager.get_runtime_world(self).add_child(enemy)
		return true
	return false

func set_map_surge(active: bool, interval_multiplier: float = 0.5, batch_multiplier: float = 1.5) -> void:
	_map_surge_active = active
	_map_surge_interval_multiplier = clampf(interval_multiplier, 0.1, 1.0) if active else 1.0
	_map_surge_batch_multiplier = clampf(batch_multiplier, 1.0, 2.0) if active else 1.0
	# 通常intervalの残り時間を引き継いで開始合図後だけ敵が来ない状態を避ける。
	if active:
		_timer = minf(_timer, _current_spawn_interval())

func _effective_map_spawn_batch() -> Vector2i:
	var base_batch := _base_map_spawn_batch() if GameManager.map_mode_active else _map_spawn_batch
	if not _map_surge_active:
		return base_batch
	return Vector2i(
		maxi(ceili(float(base_batch.x) * _map_surge_batch_multiplier), 1),
		maxi(ceili(float(base_batch.y) * _map_surge_batch_multiplier), 1),
	)

func is_map_spawn_suppressed() -> bool:
	return _active_elite_rooms > 0 or (_boss_fight_active and not GameManager.survival_mode_active) or _spawning_paused

func debug_get_map_spawn_snapshot() -> Dictionary:
	var effective_batch := _effective_map_spawn_batch()
	var base_batch := _base_map_spawn_batch() if GameManager.map_mode_active else _map_spawn_batch
	return {
		"surge_active": _map_surge_active,
		"spawn_interval": _current_spawn_interval(),
		"base_spawn_interval": _base_spawn_interval(),
		"batch_min": effective_batch.x,
		"batch_max": effective_batch.y,
		"base_batch_min": base_batch.x,
		"base_batch_max": base_batch.y,
		"enemy_cap": _map_enemy_cap,
		"damage_multiplier": _map_damage_multiplier,
	}

func _active_enemy_count() -> int:
	var count := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			count += 1
	return count

func set_spawning_paused(enabled: bool) -> void:
	_spawning_paused = enabled
	_timer = INF if enabled else 0.0

## GameManager.dungeon_mapの「床マス」の中から、プレイヤーの近く(ただしmin_spawn_distance
## より近い至近距離は除く)のものをランダムに選ぶ(壁マスやマップ範囲外には湧かせない)。
## 条件を満たすマスが近くに無ければ、最低距離の条件だけ保ってマップ全体から選ぶ。
## dungeon_mapが無い場合(異常系)は従来通りプレイヤー周囲のリング上にフォールバックする。
func _pick_spawn_position(near_world_pos: Vector2) -> Vector2:
	var map: DungeonMap = GameManager.dungeon_map
	if map == null:
		return _fallback_ring_position(near_world_pos)

	if map.get_meta("floor_only", false):
		var actor := get_tree().get_first_node_in_group("player") as Player
		var half := get_viewport_rect().size / actor.camera.zoom * 0.5 + Vector2(80, 80)
		var shape := CircleShape2D.new()
		shape.radius = 26.0
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.collision_mask = 9
		for attempt in 24:
			var direction := Vector2.from_angle(randf() * TAU)
			var radius := minf(half.x / maxf(absf(direction.x), 0.001), half.y / maxf(absf(direction.y), 0.001)) + randf_range(32, 96)
			var point := near_world_pos + direction * maxf(radius, min_spawn_distance)
			query.transform = Transform2D(0, point)
			if get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(): return point
		return Vector2.INF
	if _floor_cells.is_empty():
		_floor_cells = map.get_spawn_cells()
	if _floor_cells.is_empty():
		return Vector2.INF


	var candidates: Array[Vector2i] = []
	for cell in _floor_cells:
		var dist := map.grid_to_world(cell).distance_to(near_world_pos)
		if dist >= min_spawn_distance and dist <= spawn_radius:
			candidates.append(cell)
	if candidates.is_empty():
		return Vector2.INF
	candidates.shuffle()
	var shape := CircleShape2D.new()
	shape.radius = 26.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 9 # Walls, solid props and existing enemy bodies.
	for index in mini(candidates.size(), 48):
		var point := map.grid_to_world(candidates[index])
		query.transform = Transform2D(0, point)
		if get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
			return point
	return Vector2.INF

func _survival_enemy_pool() -> Array[EnemyData]:
	var elapsed := _map_elapsed()
	if _surge_role != "" and randf() < SURGE_ROLE_BIAS:
		var role_pool := _role_pool(_surge_role)
		if not role_pool.is_empty():
			return role_pool
	var roll := randf()
	var rank_name := "mob"
	if elapsed >= 45.0 and roll < (0.45 if elapsed >= 150.0 else 0.25):
		rank_name = "standard"
	var roster: Dictionary = MAP_ENEMY_ROSTERS.get(GameManager.current_map_index, MAP_ENEMY_ROSTERS[1])
	var pool: Array[EnemyData] = []
	for id: String in roster.get(rank_name, []):
		var data: EnemyData = DataLoader.enemies.get(id)
		if data: pool.append(data)
	return pool

func _recycle_distant_enemies() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null: return
	for enemy in get_tree().get_nodes_in_group("enemies"):
		# Despawn only ordinary waves left far behind; no death/EXP/loot signals.
		if enemy.get_meta("survival_wave", false) and enemy.global_position.distance_squared_to(player.global_position) > 1200.0 * 1200.0:
			enemy.queue_free()

func _fallback_ring_position(near_world_pos: Vector2) -> Vector2:
	var radius := maxf(spawn_radius, min_spawn_distance)
	var angle := randf() * TAU
	return near_world_pos + Vector2(cos(angle), sin(angle)) * radius

func _populate_exploration_map() -> void:
	var map: DungeonMap = GameManager.dungeon_map
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if not GameManager.map_mode_active or map == null or map == _populated_map or player == null or enemy_scene == null:
		return
	_populated_map = map
	exploration_placed_count = 0
	if map.get_meta("exploration_layout", false):
		_populate_authored_encounters(map)
		return
	var cells := map.get_spawn_cells()
	cells.shuffle()
	var positions: Array[Vector2] = []
	for cell in cells:
		var reserved := false
		for room_index in map.elite_room_indices:
			if map.rooms[room_index].grow(2).has_point(cell):
				reserved = true
		if map.boss_room_index >= 0 and map.rooms[map.boss_room_index].grow(2).has_point(cell):
			reserved = true
		if reserved:
			continue
		var point := map.grid_to_world(cell)
		if point.distance_to(player.global_position) < 300.0:
			continue
		var crowded := false
		for placed in positions:
			if point.distance_to(placed) < 180.0:
				crowded = true
				break
		if crowded:
			continue
		positions.append(point)
		if positions.size() >= _exploration_enemy_count:
			break
	positions.sort_custom(func(a: Vector2, b: Vector2): return a.distance_squared_to(player.global_position) < b.distance_squared_to(player.global_position))
	for index in positions.size():
		# Deeper locations introduce stronger species; waiting in place never upgrades the roster.
		var progress := _map_progress_offset + float(index) / maxf(positions.size() - 1, 1) * 180.0
		var eligible := _get_eligible_enemy_data(progress)
		if eligible.is_empty():
			continue
		var enemy := enemy_scene.instantiate() as EnemyBasic
		enemy.position = positions[index]
		enemy.enemy_data = eligible.pick_random()
		enemy.room_hp_multiplier = _map_hp_multiplier
		enemy.room_damage_multiplier = _map_damage_multiplier
		enemy.exploration_guard = true
		GameManager.get_runtime_world(self).add_child(enemy)
		exploration_placed_count += 1


var encounter_enemies: Dictionary = {}
var encounters_ready := false
var encounter_defeated: Dictionary = {}

func _populate_authored_encounters(map: DungeonMap) -> void:
	encounter_enemies.clear()
	encounter_defeated.clear()
	encounters_ready = false
	await get_tree().physics_frame
	if map != GameManager.dungeon_map: return
	var roles: Array = map.get_meta("room_roles",[])
	var world := GameManager.get_runtime_world(self) as Node2D
	var elite_manager := world.get_node_or_null("EliteRoomManager") as EliteRoomManager
	var reinforcement_rooms: Array[int] = []
	for index in roles.size():
		if String(roles[index]) in ["guard", "junction_guard", "flank", "antechamber"]:
			reinforcement_rooms.append(index)
	var extra_budget := floori(float(GameManager.current_depth - 1) * 0.5)
	for room_id in roles.size():
		var role: String = roles[room_id]
		var enemy_ids := _encounter_enemy_ids(GameManager.current_map_index, role, room_id)
		var rank := reinforcement_rooms.find(room_id)
		if rank >= 0 and not reinforcement_rooms.is_empty():
			var quota := floori(float(extra_budget) / float(reinforcement_rooms.size())) + (1 if rank < extra_budget % reinforcement_rooms.size() else 0)
			for extra in mini(quota, 2):
				var reinforcement_rank := "mob" if extra % 2 == 0 else "standard"
				var reinforcement_id := _enemy_for_rank(GameManager.current_map_index, reinforcement_rank, room_id + extra + 7)
				if not reinforcement_id.is_empty():
					enemy_ids.append(reinforcement_id)
		if enemy_ids.is_empty(): continue
		var room: Rect2i = map.rooms[room_id]
		var centre := room.position+room.size/2
		var cells := map.get_spawn_cells(room.grow(-2))
		var placed: Array[Vector2] = []
		encounter_enemies[room_id] = []
		encounter_defeated[room_id] = 0
		for index in enemy_ids.size():
			var preferred := centre+([Vector2i(1,1),Vector2i(-2,2),Vector2i(2,-2)][index%3] as Vector2i)
			cells.sort_custom(func(a: Vector2i,b: Vector2i): return a.distance_squared_to(preferred)<b.distance_squared_to(preferred))
			var position := Vector2.INF
			for cell in cells:
				var objective: Vector2i = map.get_meta("objective_cells",{}).get(room_id,Vector2i(9999,9999))
				if absi(cell.x-objective.x)<=2 and absi(cell.y-objective.y)<=2: continue
				var point := map.grid_to_world(cell)+Vector2.ONE*16.0
				var crowded := false
				for other in placed:
					if point.distance_to(other)<94.0: crowded=true
				if crowded: continue
				var query := PhysicsShapeQueryParameters2D.new()
				var circle := CircleShape2D.new()
				circle.radius = 28.0
				query.shape = circle
				query.transform = Transform2D(0,point)
				query.collision_mask = 1
				if not world.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): continue
				position=point
				break
			if not position.is_finite():
				push_error("Encounter has no safe placement: room %d" % room_id)
				continue
			var base: EnemyData = DataLoader.enemies.get(String(enemy_ids[index]))
			if base == null: continue
			var enemy := enemy_scene.instantiate() as EnemyBasic
			enemy.position = position
			enemy.enemy_data = base
			enemy.room_hp_multiplier = _map_hp_multiplier
			enemy.room_damage_multiplier = _map_damage_multiplier
			enemy.exploration_guard = true
			enemy.exploration_home = position
			enemy.exploration_room = room_id
			if role == "elite":
				enemy.elite_stat_multiplier = 1.35
				enemy.visual_scale_multiplier = 1.65
			world.add_child(enemy)
			if role == "elite" and elite_manager: elite_manager.attach_exploration_affix(enemy,GameManager.current_map_index)
			enemy.health_component.died.connect(_on_encounter_enemy_defeated.bind(map,room_id),CONNECT_ONE_SHOT)
			encounter_enemies[room_id].append(weakref(enemy))
			placed.append(position)
			exploration_placed_count += 1
	encounters_ready = true

func _encounter_enemy_ids(map_index: int, room_role: String, room_id: int) -> Array[String]:
	var enemy_ids: Array[String] = []
	var pattern: Array = ROOM_RANK_PATTERNS.get(room_role, [])
	for index in pattern.size():
		var enemy_id := _enemy_for_rank(map_index, String(pattern[index]), room_id + index * 3)
		if not enemy_id.is_empty():
			enemy_ids.append(enemy_id)
	return enemy_ids

func _enemy_for_rank(map_index: int, rank_name: String, seed_offset: int) -> String:
	var roster: Dictionary = MAP_ENEMY_ROSTERS.get(map_index, MAP_ENEMY_ROSTERS[1])
	var pool: Array = roster.get(rank_name, [])
	if pool.is_empty():
		return ""
	var floor_offset := maxi(GameManager.current_depth - 1, 0) % 20
	return String(pool[posmod(seed_offset + floor_offset, pool.size())])

static func get_enemy_rosters() -> Dictionary:
	return MAP_ENEMY_ROSTERS.duplicate(true)

func is_encounter_cleared(room_id: int) -> bool:
	if not encounters_ready or not encounter_enemies.has(room_id): return false
	if encounter_enemies[room_id].is_empty(): return false
	return int(encounter_defeated.get(room_id,0)) >= encounter_enemies[room_id].size()

func _on_encounter_enemy_defeated(map: DungeonMap, room_id: int) -> void:
	if map != _populated_map: return
	encounter_defeated[room_id] = int(encounter_defeated.get(room_id,0))+1
