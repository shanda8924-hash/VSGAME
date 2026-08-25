extends Node2D
class_name WaveSpawner
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

signal room_wave_started(enemy_count: int)
signal room_wave_cleared()

var _timer: float = 0.0
## 現在進行中の精鋭部屋(Elite Room)攻略の数(通常は0か1だが、念のため
## カウンタにしておき、0より大きい間は雑魚湧きを止める)。
var _active_elite_rooms: int = 0
## ボス戦が進行中かどうか(精鋭部屋と同様、この間は通常の雑魚湧きを止める)。
var _boss_fight_active: bool = false
var _room_mode_enabled: bool = false
var _room_wave_active: bool = false
var _room_wave_prepared: bool = false
var _room_alive: Dictionary = {}
var _room_epoch: int = 0
var _visual_warmup_running := false

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
	if _room_mode_enabled:
		return
	if _active_elite_rooms > 0 or _boss_fight_active:
		return # 精鋭部屋の攻略中・ボス戦中は通常の雑魚湧きを止める
	_timer -= delta
	if _timer <= 0.0:
		_spawn_enemy()
		_timer = _current_spawn_interval()

## 経過時間(GameManager.elapsed_seconds)を難易度カーブのbreakpoint間で線形補間し、
## 現在のspawn_intervalを求める(数値が段階的にカクつかないようにするため)。
func _current_spawn_interval() -> float:
	var breakpoints: Array = DataLoader.difficulty_curves.get(difficulty_curve_id, [])
	if breakpoints.is_empty():
		return fallback_spawn_interval

	var elapsed := GameManager.elapsed_seconds
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

var _floor_cells: Array[Vector2i] = []

## GameManager.elapsed_seconds <= min_elapsed_secondsの敵だけを候補にする。
## ランごとに経過時間は増え続けるため、_ready()時ではなく毎回のスポーン試行時に
## 都度フィルタし直す(キャッシュしない)。
func _get_eligible_enemy_data(progress_seconds: float = -1.0) -> Array[EnemyData]:
	var eligible: Array[EnemyData] = []
	var elapsed := GameManager.elapsed_seconds if progress_seconds < 0.0 else progress_seconds
	for data in enemy_data_list:
		if elapsed >= data.min_elapsed_seconds:
			eligible.append(data)
	return eligible

func _spawn_enemy() -> void:
	if enemy_scene == null or enemy_data_list.is_empty():
		return
	var eligible := _get_eligible_enemy_data()
	if eligible.is_empty():
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var enemy := enemy_scene.instantiate()
	enemy.global_position = _pick_spawn_position(player.global_position)
	enemy.enemy_data = eligible[randi() % eligible.size()]
	GameManager.get_runtime_world(self).add_child(enemy)

func enable_room_mode(enabled: bool) -> void:
	_room_mode_enabled = enabled
	_timer = INF if enabled else 0.0
	if not enabled:
		clear_room_wave()

func start_room_wave(room_number: int, enemy_count: int, hp_multiplier: float, damage_multiplier: float, special_chance: float) -> int:
	clear_room_wave()
	_room_mode_enabled = true
	_room_epoch += 1
	var epoch := _room_epoch
	var runtime_world := GameManager.get_runtime_world(self)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if enemy_scene == null or runtime_world == null or player == null:
		room_wave_started.emit(0)
		room_wave_cleared.emit()
		return 0
	var progress_seconds := float(maxi(room_number - 1, 0)) * 45.0
	var eligible := _get_eligible_enemy_data(progress_seconds)
	if eligible.is_empty():
		room_wave_started.emit(0)
		room_wave_cleared.emit()
		return 0
	var advanced: Array[EnemyData] = eligible.filter(func(data: EnemyData): return data.min_elapsed_seconds > 0.0)
	var spawn_positions := _build_room_spawn_positions(player.global_position, enemy_count)
	for index in enemy_count:
		var pool: Array[EnemyData] = advanced if not advanced.is_empty() and randf() < special_chance else eligible
		var enemy := enemy_scene.instantiate() as EnemyBasic
		enemy.enemy_data = pool[randi() % pool.size()]
		enemy.room_hp_multiplier = hp_multiplier
		enemy.room_damage_multiplier = damage_multiplier
		var spawn_position: Vector2 = spawn_positions[index]
		# add_child時点から正しい位置へ置き、全個体のCollisionが原点で一度重なる
		# PhysicsServer更新を発生させない。
		enemy.position = spawn_position
		runtime_world.add_child(enemy)
		_track_room_enemy(enemy, epoch)
	_room_wave_active = not _room_alive.is_empty()
	room_wave_started.emit(_room_alive.size())
	if not _room_wave_active:
		room_wave_cleared.emit()
	return _room_alive.size()

## ROOM遷移中にEnemyのScene/AI/Animation/Collision初期化を数Frameへ分散する。
## 準備中は非表示・停止状態で保持し、全個体の準備完了後に同時有効化するため、
## Playerから1体ずつポップして見えることはない。
func prepare_room_wave(room_number: int, enemy_count: int, hp_multiplier: float, damage_multiplier: float, special_chance: float, batch_size: int = 2) -> int:
	clear_room_wave()
	_room_mode_enabled = true
	_room_epoch += 1
	var epoch := _room_epoch
	var runtime_world := GameManager.get_runtime_world(self)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if enemy_scene == null or runtime_world == null or player == null:
		return 0
	var progress_seconds := float(maxi(room_number - 1, 0)) * 45.0
	var eligible := _get_eligible_enemy_data(progress_seconds)
	if eligible.is_empty():
		return 0
	var advanced: Array[EnemyData] = eligible.filter(func(data: EnemyData): return data.min_elapsed_seconds > 0.0)
	var spawn_positions := _build_room_spawn_positions(player.global_position, enemy_count)
	var safe_batch := maxi(batch_size, 1)
	for index in enemy_count:
		if epoch != _room_epoch:
			return 0
		var pool: Array[EnemyData] = advanced if not advanced.is_empty() and randf() < special_chance else eligible
		var enemy := enemy_scene.instantiate() as EnemyBasic
		enemy.enemy_data = pool[randi() % pool.size()]
		enemy.room_hp_multiplier = hp_multiplier
		enemy.room_damage_multiplier = damage_multiplier
		# 完全に非表示だと全Textureの初回Canvas uploadがCOMBAT開始Frameへ集中する。
		# ほぼ透明のまま1体ずつ描画準備し、開始時は全員を同時に不透明化する。
		enemy.visible = true
		enemy.modulate.a = 0.001
		enemy.set_room_activation_locked(true)
		var spawn_position: Vector2 = spawn_positions[index]
		# 親へ追加する前に配置し、準備中のEnemy全員が原点でCollision登録される
		# 一時的なoverlap/broadphase負荷を避ける(Runtime worldはidentity transform)。
		enemy.position = spawn_position
		runtime_world.add_child(enemy)
		_track_room_enemy(enemy, epoch)
		if (index + 1) % safe_batch == 0 and index + 1 < enemy_count:
			await get_tree().process_frame
	if epoch != _room_epoch:
		return 0
	_room_wave_prepared = not _room_alive.is_empty()
	return _room_alive.size()

func activate_prepared_room_wave(batch_size: int = 2) -> int:
	if not _room_wave_prepared:
		room_wave_started.emit(0)
		room_wave_cleared.emit()
		return 0
	_room_wave_prepared = false
	var prepared_enemies: Array[EnemyBasic] = []
	for enemy_variant in _room_alive.values():
		var enemy := enemy_variant as EnemyBasic
		if enemy == null or not is_instance_valid(enemy):
			continue
		# 全Spriteは同時に見せるが、AI/Physicsの初回処理は数Frameへ分散する。
		# これによりArea切替直後の12〜15体が同じPhysics frameで初期追跡を
		# 開始して発生していた50ms級のCOMBAT first-frame spikeを避ける。
		enemy.visible = true
		enemy.modulate.a = 1.0
		prepared_enemies.append(enemy)
	_room_wave_active = not _room_alive.is_empty()
	room_wave_started.emit(_room_alive.size())
	if not _room_wave_active:
		room_wave_cleared.emit()
	else:
		_activate_prepared_enemy_batches(_room_epoch, prepared_enemies, maxi(batch_size, 1))
	return _room_alive.size()

func _activate_prepared_enemy_batches(epoch: int, enemies: Array[EnemyBasic], batch_size: int) -> void:
	for index in enemies.size():
		if epoch != _room_epoch:
			return
		var enemy := enemies[index]
		if is_instance_valid(enemy) and _room_alive.has(enemy.get_instance_id()):
			enemy.set_room_activation_locked(false)
		if (index + 1) % batch_size == 0 and index + 1 < enemies.size():
			await get_tree().process_frame

func warmup_enemy_visuals(room_number: int, batch_size: int = 1) -> void:
	if _visual_warmup_running:
		return
	_visual_warmup_running = true
	var progress_seconds := float(maxi(room_number - 1, 0)) * 45.0
	var eligible := _get_eligible_enemy_data(progress_seconds)
	var loaded_in_batch := 0
	for data in eligible:
		if data.sprite_folder == "" or SpriteSheetBuilder.is_cached(data.sprite_folder):
			continue
		SpriteSheetBuilder.build_sprite_frames(data.sprite_folder)
		loaded_in_batch += 1
		if loaded_in_batch >= maxi(batch_size, 1):
			loaded_in_batch = 0
			await get_tree().process_frame
	_visual_warmup_running = false

func clear_room_wave() -> void:
	_room_epoch += 1
	_room_wave_active = false
	_room_wave_prepared = false
	var enemies := _room_alive.values().duplicate()
	_room_alive.clear()
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()

func get_room_alive_count() -> int:
	return _room_alive.size()

func debug_defeat_room_wave() -> void:
	if not OS.is_debug_build():
		return
	for enemy_variant in _room_alive.values().duplicate():
		var enemy := enemy_variant as EnemyBasic
		if enemy == null or not is_instance_valid(enemy):
			continue
		enemy.health_component.current_hp = minf(enemy.health_component.current_hp, 1.0)
		enemy.health_component.apply_secondary_damage(999999.0, CombatEventMeta.create_secondary("debug_room_clear", [], false))

func _track_room_enemy(enemy: EnemyBasic, epoch: int) -> void:
	var id := enemy.get_instance_id()
	_room_alive[id] = enemy
	enemy.health_component.died.connect(_on_room_enemy_removed.bind(id, epoch), CONNECT_ONE_SHOT)
	enemy.tree_exited.connect(_on_room_enemy_removed.bind(id, epoch), CONNECT_ONE_SHOT)

func _on_room_enemy_removed(id: int, epoch: int) -> void:
	if epoch != _room_epoch or not _room_alive.has(id):
		return
	_room_alive.erase(id)
	if _room_wave_active and _room_alive.is_empty():
		_room_wave_active = false
		room_wave_cleared.emit()

func _pick_room_spawn_position(player_position: Vector2, occupied: Array[Vector2]) -> Vector2:
	var map: DungeonMap = GameManager.dungeon_map
	if map == null:
		return _fallback_ring_position(player_position)
	var cells := map.get_floor_cells()
	cells.shuffle()
	for cell in cells:
		var world_position := map.grid_to_world(cell)
		if world_position.distance_to(player_position) < 180.0:
			continue
		var separated := true
		for other in occupied:
			if world_position.distance_to(other) < 42.0:
				separated = false
				break
		if separated:
			return world_position
	return map.grid_to_world(cells[0]) if not cells.is_empty() else _fallback_ring_position(player_position)

## ROOM開始時の全Spawn位置を1回のfloor cache複製・shuffleで決める。
## 以前はEnemy 1体ごとに全床セルを複製してshuffleしており、後半の15体生成時に
## 同じO(floor_cells)処理を15回繰り返していた。
func _build_room_spawn_positions(player_position: Vector2, count: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var map: DungeonMap = GameManager.dungeon_map
	if map == null:
		for index in count:
			result.append(_fallback_ring_position(player_position) + Vector2.from_angle(TAU * float(index) / maxf(float(count), 1.0)) * 36.0)
		return result
	var cells := map.get_floor_cells()
	cells.shuffle()
	for cell in cells:
		var world_position := map.grid_to_world(cell)
		if world_position.distance_to(player_position) < 180.0:
			continue
		var separated := true
		for other in result:
			if world_position.distance_to(other) < 42.0:
				separated = false
				break
		if separated:
			result.append(world_position)
			if result.size() >= count:
				return result
	# 小さいTemplateでも必要数を必ず返す。通常は上の分離条件だけで充足する。
	for cell in cells:
		if result.size() >= count:
			break
		var world_position := map.grid_to_world(cell)
		if world_position.distance_to(player_position) >= 180.0 and world_position not in result:
			result.append(world_position)
	while result.size() < count:
		result.append(_fallback_ring_position(player_position))
	return result

## GameManager.dungeon_mapの「床マス」の中から、プレイヤーの近く(ただしmin_spawn_distance
## より近い至近距離は除く)のものをランダムに選ぶ(壁マスやマップ範囲外には湧かせない)。
## 条件を満たすマスが近くに無ければ、最低距離の条件だけ保ってマップ全体から選ぶ。
## dungeon_mapが無い場合(異常系)は従来通りプレイヤー周囲のリング上にフォールバックする。
func _pick_spawn_position(near_world_pos: Vector2) -> Vector2:
	var map: DungeonMap = GameManager.dungeon_map
	if map == null:
		return _fallback_ring_position(near_world_pos)

	if _floor_cells.is_empty():
		_floor_cells = map.get_floor_cells()
	if _floor_cells.is_empty():
		return _fallback_ring_position(near_world_pos)

	var near_grid := map.world_to_grid(near_world_pos)
	var max_radius_cells := spawn_radius / DungeonMap.CELL_WORLD_SIZE
	var min_radius_cells := min_spawn_distance / DungeonMap.CELL_WORLD_SIZE

	var candidates: Array[Vector2i] = []
	for cell in _floor_cells:
		var dist := Vector2(cell - near_grid).length()
		if dist >= min_radius_cells and dist <= max_radius_cells:
			candidates.append(cell)
	if candidates.is_empty():
		# 半径内に条件を満たすマスが無い場合、最低距離だけは守ってマップ全体から探す。
		for cell in _floor_cells:
			if Vector2(cell - near_grid).length() >= min_radius_cells:
				candidates.append(cell)
	if candidates.is_empty():
		return _fallback_ring_position(near_world_pos)

	var chosen: Vector2i = candidates[randi() % candidates.size()]
	return map.grid_to_world(chosen)

func _fallback_ring_position(near_world_pos: Vector2) -> Vector2:
	var radius := maxf(spawn_radius, min_spawn_distance)
	var angle := randf() * TAU
	return near_world_pos + Vector2(cos(angle), sin(angle)) * radius
