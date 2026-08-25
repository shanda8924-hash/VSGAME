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

var width: int
var height: int
var spawn_point: Vector2i = Vector2i.ZERO

## 生成された各部屋の矩形(部屋を意識した装飾配置のためStageEnvironmentに公開する)。
var rooms: Array[Rect2i] = []
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

var _cells: PackedByteArray # 1=床, 0=壁
var _floor_cells_cache: Array[Vector2i] = []
var _floor_cells_cache_valid := false

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

## 床マスかつ、上下左右のいずれかが壁マスになっているマス(壁際)かどうか。
## 装飾(松明・結晶等)を通路の真ん中に置かないための判定に使う。
func is_wall_adjacent_floor(grid_pos: Vector2i) -> bool:
	if not is_floor(grid_pos):
		return false
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not is_floor(grid_pos + offset):
			return true
	return false

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

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos) * CELL_WORLD_SIZE

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(round(world_pos.x / CELL_WORLD_SIZE), round(world_pos.y / CELL_WORLD_SIZE))

func _index(grid_pos: Vector2i) -> int:
	var local := grid_pos - get_min_coords()
	return local.y * width + local.x
