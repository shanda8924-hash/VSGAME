extends RefCounted
class_name DungeonMap
## DungeonGeneratorが生成するグリッドデータ本体。
## 「床マス」「壁マス」だけを持つ単純な2値グリッドで、部屋レイアウトの
## アルゴリズム自体は持たない(それはDungeonGenerator側の責務)。
##
## グリッド座標は原点(0,0)がマップ中心に来るよう中心寄せしてある
## (StageEnvironment/TileMapLayerのセル座標や、これまでのプレイヤー
## 開始位置(ワールド原点)との整合を取るため)。

## TileMapLayer側の1セルぶんのワールドサイズ。
## StageEnvironment.TILE_PIXEL_SIZE * StageEnvironment.TILE_RENDER_SCALE と
## 常に一致させること(ズレるとタイル絵と当たり判定・スポーン位置がずれる)。
const CELL_WORLD_SIZE := 32.0

const REGION_ARENA := "arena"
const REGION_PILLAR_FIELD := "pillar_field"
const REGION_CHOKEPOINT := "chokepoint"
const REGION_HAZARD := "hazard"
const COMBAT_REGION_TYPES := [REGION_ARENA, REGION_PILLAR_FIELD, REGION_CHOKEPOINT]

var width: int
var height: int
var spawn_point: Vector2i = Vector2i.ZERO

## 生成された各部屋の矩形(部屋を意識した装飾配置のためStageEnvironmentに公開する)。
var rooms: Array[Rect2i] = []
## Spawnから部屋中心が最も遠い部屋。Generator/描画/進行で同じ予約領域を使う。
## 単一部屋の小さな互換MapにはBoss領域を割り当てない。
var boss_room_index: int = -1
## 各部屋の出入り口(通路との接続部分)の両脇に置くべき柱のマス座標。
## 1つの出入り口につき必ず2箇所(両側対称)がペアで入る(添字0,1が1組・2,3が1組…)。
var pillar_positions: Array[Vector2i] = []
## pillar_positions[i]に対応する「さらに外側(通路の開口部から離れる向き)」への単位ベクトル。
## 通路が密集して重なり本来の位置が床になってしまった場合、StageEnvironment側で
## この方向へ少しずつずらして再試行するためのフォールバック情報。
var pillar_step_directions: Array[Vector2i] = []
## 出入り口ペア(pillar_positionsの2個1組、添字i*2,i*2+1)が、roomsのどの添字の
## 部屋に属するかを記録する(pillar_pair_room_index[i]が対応するペアの部屋番号)。
## 精鋭部屋(Elite Room)の入室演出で「その部屋の出入り口だけ」を特定して塞ぐために使う。
var pillar_pair_room_index: Array[int] = []
## roomsのうち、精鋭部屋(Elite Room)として指定された部屋の添字一覧。
var elite_room_indices: Array[int] = []

## 戦闘上の役割を持つ部屋。room index→region typeを保持し、描画側は
## cell単位Cacheを参照する。障害物セルは床から除外されてもregion表示を残せる。
var combat_region_by_room: Dictionary = {}
var terrain_obstacle_cells: Dictionary = {}
## 旧地形の互換用。通常MAPでは生成もRuntime Area配置も行わない。
var hazard_regions: Array[Rect2i] = []
var _combat_region_by_cell: Dictionary = {}

var _cells: PackedByteArray # 1=床, 0=壁
var _floor_cells_cache: Array[Vector2i] = []
var _floor_cells_cache_valid := false
## 3x3すべてが床のマス(=敵が引っかからずに通れるマス)を前計算したもの。1=通行可。
## 敵AIの経路探索が毎フレーム大量に問い合わせる判定なので、その都度9回のis_floor()を
## 呼ぶのではなく、生成完了後に1度だけ作って以降は配列1回参照で答える。
## 床の書き換え(set_floor)はDungeonGenerator/ExplorationLayoutの生成時だけなので、
## 実行中に作り直しが走ることはない。
var _clearance_cells: PackedByteArray
var _clearance_cache_valid := false
var _spawn_cells_cache: Array[Vector2i] = []

func _init(map_width: int, map_height: int) -> void:
	width = map_width
	height = map_height
	_cells = PackedByteArray()
	_cells.resize(width * height)
	_cells.fill(0)

func get_min_coords() -> Vector2i:
	return Vector2i(-width / 2, -height / 2)

func get_max_coords() -> Vector2i:
	return get_min_coords() + Vector2i(width - 1, height - 1)

func is_in_bounds(grid_pos: Vector2i) -> bool:
	var local := grid_pos - get_min_coords()
	return local.x >= 0 and local.x < width and local.y >= 0 and local.y < height

func is_floor(grid_pos: Vector2i) -> bool:
	if get_meta("floor_only", false): return true
	if not is_in_bounds(grid_pos):
		return false
	return _cells[_index(grid_pos)] == 1

func set_floor(grid_pos: Vector2i, value: bool) -> void:
	if not is_in_bounds(grid_pos):
		return
	var next_value := 1 if value else 0
	var index := _index(grid_pos)
	if _cells[index] == next_value:
		return
	_cells[index] = next_value
	_floor_cells_cache_valid = false
	_clearance_cache_valid = false

func set_combat_region(room_index: int, region_type: String, rect: Rect2i) -> void:
	if region_type not in COMBAT_REGION_TYPES:
		return
	combat_region_by_room[room_index] = region_type
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			if is_in_bounds(cell):
				_combat_region_by_cell[cell] = region_type

func get_combat_region_type(grid_pos: Vector2i) -> String:
	return String(_combat_region_by_cell.get(grid_pos, ""))

func get_combat_region_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell_variant in _combat_region_by_cell.keys():
		result.append(cell_variant as Vector2i)
	return result

func mark_terrain_obstacle(grid_pos: Vector2i) -> void:
	if not is_in_bounds(grid_pos):
		return
	terrain_obstacle_cells[grid_pos] = true
	set_floor(grid_pos, false)

func is_terrain_obstacle(grid_pos: Vector2i) -> bool:
	return terrain_obstacle_cells.has(grid_pos)

func add_hazard_region(rect: Rect2i) -> void:
	hazard_regions.append(rect)

func get_combat_region_counts() -> Dictionary:
	var counts := {}
	for region_type in COMBAT_REGION_TYPES:
		counts[region_type] = 0
	for region_type_variant in combat_region_by_room.values():
		var region_type := String(region_type_variant)
		counts[region_type] = int(counts.get(region_type, 0)) + 1
	return counts

## 床マスかつ、上下左右のいずれかが壁マスになっているマス(壁際)かどうか。
## 装飾(松明・結晶等)を通路の真ん中に置かないための判定に使う。
func is_wall_adjacent_floor(grid_pos: Vector2i) -> bool:
	if not is_floor(grid_pos):
		return false
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not is_floor(grid_pos + offset):
			return true
	return false

## 自分と周囲8マスがすべて床かどうか。敵AIの経路探索(ChaseStrategy)が
## 「体格ぶんの余裕があって引っかからないマス」を判定するのに使う。
func has_navigation_clearance(grid_pos: Vector2i) -> bool:
	if get_meta("floor_only", false): return true
	if not is_in_bounds(grid_pos):
		return false
	if not _clearance_cache_valid:
		_rebuild_clearance_cache()
	return _clearance_cells[_index(grid_pos)] == 1

## 経路探索の内側ループが、1マスごとのメソッド呼び出しを介さずに直接読むための生データ。
## GDScriptはメソッド呼び出し1回だけで約1.4usかかり、幅優先探索では1セルにつき
## 4回呼ぶためここが支配項になる(実測: 1セルあたり8.8us、347セルの探索で3.1ms)。
## 添字は_index()と同じ (grid_pos - get_min_coords()) の行優先。範囲判定は呼び出し側で行うこと。
func get_navigation_clearance_data() -> PackedByteArray:
	if not _clearance_cache_valid:
		_rebuild_clearance_cache()
	return _clearance_cells

## 外周1マスは3x3が取れないので常に0のまま残す(元の実装でもis_floor()が
## 範囲外にfalseを返すため通行不可扱いで、挙動は変わらない)。
func _rebuild_clearance_cache() -> void:
	_clearance_cells.resize(width * height)
	_clearance_cells.fill(0)
	_spawn_cells_cache.clear()
	var min_coords := get_min_coords()
	for y in range(1, height - 1):
		for x in range(1, width - 1):
			var index := y * width + x
			if _cells[index] != 1:
				continue
			var open := true
			for dy in range(-1, 2):
				var row := index + dy * width
				if _cells[row - 1] != 1 or _cells[row] != 1 or _cells[row + 1] != 1:
					open = false
					break
			if open:
				_clearance_cells[index] = 1
				_spawn_cells_cache.append(min_coords + Vector2i(x, y))
	_clearance_cache_valid = true

func get_floor_cells() -> Array[Vector2i]:
	if not _floor_cells_cache_valid:
		_floor_cells_cache.clear()
		var min_c := get_min_coords()
		for y in height:
			for x in width:
				if _cells[y * width + x] == 1:
					_floor_cells_cache.append(min_c + Vector2i(x, y))
		_floor_cells_cache_valid = true
	# Spawn callers shuffle their local result, so never expose the cache itself.
	return _floor_cells_cache.duplicate()

## Spawnは床の点だけでなく本体が収まる必要がある。既存の3x3通行余裕を
## 共用し、噴水/柱/壁の内部と境界を候補から除外する（地形自体は変更しない）。
func get_spawn_cells(bounds: Rect2i = Rect2i()) -> Array[Vector2i]:
	if get_meta("floor_only", false) and bounds.has_area():
		var points: Array[Vector2i] = []
		for y in range(bounds.position.y, bounds.end.y):
			for x in range(bounds.position.x, bounds.end.x): points.append(Vector2i(x, y))
		return points
	if not _clearance_cache_valid:
		_rebuild_clearance_cache()
	if not bounds.has_area():
		return _spawn_cells_cache.duplicate()
	var result: Array[Vector2i] = []
	for cell in _spawn_cells_cache:
		if bounds.has_point(cell):
			result.append(cell)
	return result

## 召喚などの任意座標は最寄りの安全セルへ寄せる。候補なしはINFを返し、
## 呼出し元が生成を中止する。壁の中へのリングfallbackや無限再抽選はしない。
func find_spawn_position_near(world_position: Vector2) -> Vector2:
	var cell := world_to_grid(world_position)
	if has_navigation_clearance(cell):
		return grid_to_world(cell)
	var nearest := Vector2.INF
	var nearest_distance := INF
	for candidate in get_spawn_cells():
		var position := grid_to_world(candidate)
		var distance := position.distance_squared_to(world_position)
		if distance < nearest_distance:
			nearest = position
			nearest_distance = distance
	return nearest

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos) * CELL_WORLD_SIZE

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(round(world_pos.x / CELL_WORLD_SIZE), round(world_pos.y / CELL_WORLD_SIZE))

func _index(grid_pos: Vector2i) -> int:
	var local := grid_pos - get_min_coords()
	return local.y * width + local.x
