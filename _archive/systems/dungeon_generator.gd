extends RefCounted
class_name DungeonGenerator
## 手続き的ダンジョン生成: ランダムな矩形の部屋をいくつか配置し、
## 隣接する部屋の中心同士を太い通路で繋ぐだけの単純な方式。
##
## 【重要な設計方針】このゲームの核は「大量の敵に囲まれて一気に薙ぎ払う爽快感」。
## 細い1マス通路の迷路にすると敵が縦一列に並んでしまい爽快感が損なわれるため、
## 部屋・通路とも広めに作る(部屋は最低8x8、通路は最低3〜4マス幅)。

const MIN_ROOM_SIZE := 8
const MAX_ROOM_SIZE := 14
const BOSS_ROOM_SIZE := Vector2i(14, 14)
const CORRIDOR_WIDTH := 4
const BORDER_THICKNESS := 2
const ROOM_PLACEMENT_MARGIN := 2 # 部屋同士が隣接しすぎて壁が消えないための余白
## 精鋭部屋(Elite Room)の対象から、スタート地点に近い部屋を除外するための
## 最低距離(マス数)。スタート直後に強敵と鉢合わせしないようにするための安全マージン。
const ELITE_ROOM_MIN_DISTANCE_FROM_START := 25

## ラン開始時に1回だけ呼ばれる想定。GameManager.start_run()から呼び出す。
static func generate(width: int, height: int, room_count: int, elite_room_count: int = 1, rng: RandomNumberGenerator = null, survival: bool = false) -> DungeonMap:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var map := DungeonMap.new(width, height)
	map.set_meta("survival_layout", survival)
	var room_min := 16 if survival else MIN_ROOM_SIZE
	var room_max := 23 if survival else MAX_ROOM_SIZE
	var boss_size := Vector2i(26, 26) if survival else BOSS_ROOM_SIZE
	var passage_width := 6 if survival else CORRIDOR_WIDTH
	var min_c := map.get_min_coords()
	var max_c := map.get_max_coords()

	var rooms: Array[Rect2i] = []
	var farthest_distance_squared := -1.0
	var interior := Rect2i(min_c + Vector2i.ONE * BORDER_THICKNESS, Vector2i(width, height) - Vector2i.ONE * BORDER_THICKNESS * 2)
	var attempts := 0
	while rooms.size() < room_count and attempts < room_count * 30:
		attempts += 1
		var w := rng.randi_range(room_min, room_max)
		var h := rng.randi_range(room_min, room_max)
		var x_max := max_c.x - w - BORDER_THICKNESS
		var y_max := max_c.y - h - BORDER_THICKNESS
		var x_min := min_c.x + BORDER_THICKNESS
		var y_min := min_c.y + BORDER_THICKNESS
		if x_min >= x_max or y_min >= y_max:
			break # マップが小さすぎて部屋が置けない(異常系)
		var x := rng.randi_range(x_min, x_max)
		var y := rng.randi_range(y_min, y_max)
		var rect := Rect2i(x, y, w, h)
		var candidate_distance_squared := -1.0
		if not rooms.is_empty():
			var center := _room_center(rect)
			candidate_distance_squared = Vector2(center - _room_center(rooms[0])).length_squared()
			# 最遠候補の段階で広さを予約する。配置後に拡幅して隣室/外周へ
			# 食い込ませず、同距離で後から選ばれる候補にも同じ広さを保証する。
			# 40セル未満の小型テストMapは従来の部屋寸法/fallbackを維持する。
			if candidate_distance_squared >= farthest_distance_squared and width >= 40 and height >= 40:
				rect = Rect2i(center - boss_size / 2, boss_size)
				if not interior.encloses(rect):
					continue

		var overlaps := false
		for other in rooms:
			if rect.grow(ROOM_PLACEMENT_MARGIN).intersects(other):
				overlaps = true
				break
		if overlaps:
			continue

		rooms.append(rect)
		farthest_distance_squared = maxf(farthest_distance_squared, candidate_distance_squared)
		_carve_room(map, rect)

	if rooms.is_empty():
		# 万一1部屋も置けなかった場合の保険: マップ中央に最低限の部屋を1つ確保する。
		var fallback := Rect2i(-MIN_ROOM_SIZE / 2, -MIN_ROOM_SIZE / 2, MIN_ROOM_SIZE, MIN_ROOM_SIZE)
		rooms.append(fallback)
		_carve_room(map, fallback)

	# 部屋を配置順にチェーン状に繋ぎ、全部屋が確実に到達可能になるようにする。
	for i in range(1, rooms.size()):
		_carve_corridor(map, i - 1, i, rooms[i - 1], rooms[i], passage_width)

	# 一本道だけだと単調なので、ループになるよう追加でランダムな接続を数本足す。
	var extra_links := mini(3, maxi(0, rooms.size() - 2))
	for i in extra_links:
		var a := rng.randi_range(0, rooms.size() - 1)
		var b := rng.randi_range(0, rooms.size() - 1)
		if a != b:
			_carve_corridor(map, a, b, rooms[a], rooms[b], passage_width)

	_force_border_walls(map)

	map.rooms = rooms
	map.spawn_point = _room_center(rooms[0])
	_assign_boss_room(map)
	if not survival:
		_assign_combat_regions(map)
	else:
		# Keep the wide escape lanes clear of solid decoration, including at junctions.
		var reserved: Dictionary = {}
		for cell in map.get_floor_cells():
			var in_room := false
			for room in rooms:
				if room.grow(-3).has_point(cell):
					in_room = true
					break
			if not in_room: reserved[cell] = true
		for room in rooms:
			var centre := _room_center(room)
			for y in range(room.position.y, room.end.y):
				for x in range(room.position.x, room.end.x):
					if absi(x-centre.x) <= 2 or absi(y-centre.y) <= 2:
						reserved[Vector2i(x,y)] = true
		map.set_meta("exploration_reserved", reserved)
	_assign_elite_rooms(map, elite_room_count, rng)
	return map

## 進行側と描画側はこのindexを使い、独自にBoss部屋を選び直さない。
## 距離二乗が同じ場合は後のindexを採用して生成seedに対して決定的にする。
static func _assign_boss_room(map: DungeonMap) -> void:
	var farthest_distance_squared := -1.0
	for room_index in range(1, map.rooms.size()):
		var distance_squared := Vector2(_room_center(map.rooms[room_index]) - map.spawn_point).length_squared()
		if distance_squared >= farthest_distance_squared:
			farthest_distance_squared = distance_squared
			map.boss_room_index = room_index
	if map.boss_room_index >= 0:
		map.set_combat_region(map.boss_room_index, DungeonMap.REGION_ARENA, map.rooms[map.boss_room_index])

## Boss部屋は開けた専用Arenaとして予約し、他の部屋だけに戦闘地形を割り当てる。
## 通常MAPからHazardを廃止。中央3マスの開口を残す縦の短壁だけ維持する。
static func _assign_combat_regions(map: DungeonMap) -> void:
	if map.rooms.is_empty():
		return
	var candidates: Array[int] = []
	for room_index in range(1, map.rooms.size()):
		if room_index != map.boss_room_index:
			candidates.append(room_index)
	if candidates.size() < DungeonMap.COMBAT_REGION_TYPES.size():
		candidates.append(0)
	candidates.sort_custom(func(first: int, second: int):
		var first_room := map.rooms[first]
		var second_room := map.rooms[second]
		var first_area := first_room.size.x * first_room.size.y
		var second_area := second_room.size.x * second_room.size.y
		if first_area == second_area:
			return first < second
		return first_area > second_area
	)
	var assignments := [
		DungeonMap.REGION_ARENA,
		DungeonMap.REGION_PILLAR_FIELD,
		DungeonMap.REGION_CHOKEPOINT,
	]
	for assignment_index in mini(assignments.size(), candidates.size()):
		var room_index := candidates[assignment_index]
		var room := map.rooms[room_index]
		var region_type := String(assignments[assignment_index])
		map.set_combat_region(room_index, region_type, room)
		match region_type:
			DungeonMap.REGION_PILLAR_FIELD:
				_apply_pillar_field(map, room)
			DungeonMap.REGION_CHOKEPOINT:
				_apply_chokepoint(map, room)

static func _apply_pillar_field(map: DungeonMap, room: Rect2i) -> void:
	var center := _room_center(room)
	# 柱本体2セル + 通行間隔3セル = 5セルpitch。外周に1セル、中央に3セルの
	# 十字レーンを残し、最小8セル部屋でも柱が最低1本は成立するようにする。
	for y in range(room.position.y + 1, room.end.y - 2, 5):
		for x in range(room.position.x + 1, room.end.x - 2, 5):
			var anchor := Vector2i(x, y)
			if _pillar_footprint_overlaps_center_lane(anchor, center):
				continue
			for offset in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
				map.mark_terrain_obstacle(anchor + offset)

static func _pillar_footprint_overlaps_center_lane(anchor: Vector2i, center: Vector2i) -> bool:
	for offset in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
		var cell: Vector2i = anchor + offset
		if absi(cell.x - center.x) <= 1 or absi(cell.y - center.y) <= 1:
			return true
	return false

static func _apply_chokepoint(map: DungeonMap, room: Rect2i) -> void:
	var center := _room_center(room)
	if room.size.x >= room.size.y:
		for y in range(room.position.y + 1, room.end.y - 1):
			if absi(y - center.y) <= 1:
				continue
			map.mark_terrain_obstacle(Vector2i(center.x, y))

## Spawn地点から全床セルへ到達できるかを4近傍BFSで検証する。
## 自動Testから同じ実装を呼び、地形追加後の袋小路・孤立床を検出する。
static func validate_reachability(map: DungeonMap) -> Dictionary:
	if map == null or not map.is_floor(map.spawn_point):
		return {"reachable": false, "reachable_cells": 0, "floor_cells": 0, "unreachable_cells": []}
	var visited := {map.spawn_point: true}
	var queue: Array[Vector2i] = [map.spawn_point]
	var head := 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var neighbor: Vector2i = current + offset
			if map.is_in_bounds(neighbor) and map.is_floor(neighbor) and not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	var floors := map.get_floor_cells()
	var unreachable: Array[Vector2i] = []
	for cell in floors:
		if not visited.has(cell):
			unreachable.append(cell)
	return {
		"reachable": unreachable.is_empty() and visited.size() == floors.size(),
		"reachable_cells": visited.size(),
		"floor_cells": floors.size(),
		"unreachable_cells": unreachable,
	}

## 部屋のうちelite_room_count個を「精鋭部屋(Elite Room)」としてランダムに指定する。
## スタート地点(rooms[0]の中心)からELITE_ROOM_MIN_DISTANCE_FROM_STARTマス未満しか
## 離れていない部屋は、開始直後に強敵と鉢合わせしないよう対象から除外する。
## rng.randi_range経由の手動Fisher-Yatesシャッフルを使うことで、Array.shuffle()の
## ようにグローバルRNGへ依存せず、呼び出し元が渡したrngだけで再現可能にしている。
static func _assign_elite_rooms(map: DungeonMap, elite_room_count: int, rng: RandomNumberGenerator) -> void:
	if elite_room_count <= 0 or map.rooms.size() <= 1:
		return
	var eligible: Array[int] = []
	for i in range(1, map.rooms.size()):
		if i == map.boss_room_index:
			continue
		var dist := Vector2(_room_center(map.rooms[i]) - map.spawn_point).length()
		if dist >= ELITE_ROOM_MIN_DISTANCE_FROM_START:
			eligible.append(i)

	for i in range(eligible.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := eligible[i]
		eligible[i] = eligible[j]
		eligible[j] = tmp

	var count := mini(elite_room_count, eligible.size())
	for i in count:
		map.elite_room_indices.append(eligible[i])

static func _room_center(rect: Rect2i) -> Vector2i:
	return rect.position + rect.size / 2

static func _carve_room(map: DungeonMap, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			map.set_floor(Vector2i(x, y), true)

## room_a→room_bをL字(横→縦)に、指定した幅で太く繋ぐ。
## 併せて、通路が各部屋の境界を横切る「出入り口」の両脇(対称な2箇所)に
## 柱を置くための座標をmap.pillar_positionsへ記録する(room_a_index/room_b_indexは
## それぞれの出入り口ペアがどちらの部屋に属するかをmap.pillar_pair_room_indexへ
## 記録するために使う。精鋭部屋の入室時に「その部屋の出入り口だけ」を塞ぐ際に必要)。
static func _carve_corridor(map: DungeonMap, room_a_index: int, room_b_index: int, room_a: Rect2i, room_b: Rect2i, width: int) -> void:
	var a := _room_center(room_a)
	var b := _room_center(room_b)
	var half := width / 2
	for x in range(min(a.x, b.x), max(a.x, b.x) + 1):
		for dy in range(-half, half + 1):
			map.set_floor(Vector2i(x, a.y + dy), true)
	for y in range(min(a.y, b.y), max(a.y, b.y) + 1):
		for dx in range(-half, half + 1):
			map.set_floor(Vector2i(b.x + dx, y), true)

	var dx_sign := 0
	if b.x > a.x:
		dx_sign = 1
	elif b.x < a.x:
		dx_sign = -1
	var dy_sign := 0
	if b.y > a.y:
		dy_sign = 1
	elif b.y < a.y:
		dy_sign = -1

	_record_doorway_pillars_horizontal(map, room_a_index, room_a, a, dx_sign, half)
	_record_doorway_pillars_vertical(map, room_b_index, room_b, b, dy_sign, half)

## room_aの左右どちらかの辺を通路(横方向の区間)が横切る位置の、真上と真下に
## 柱座標を1つずつ記録する(通路の開口部を対称に挟む)。
static func _record_doorway_pillars_horizontal(map: DungeonMap, room_index: int, room: Rect2i, center: Vector2i, travel_dx_sign: int, half: int) -> void:
	if travel_dx_sign == 0:
		return # 部屋の中心x座標が一致している(横方向の移動が無い)特殊ケースは対象外
	var edge_x: int = (room.position.x + room.size.x) if travel_dx_sign > 0 else (room.position.x - 1)
	map.pillar_positions.append(Vector2i(edge_x, center.y - half - 1))
	map.pillar_step_directions.append(Vector2i(0, -1)) # 開口部からさらに上へ離れる向き
	map.pillar_positions.append(Vector2i(edge_x, center.y + half + 1))
	map.pillar_step_directions.append(Vector2i(0, 1)) # 開口部からさらに下へ離れる向き
	map.pillar_pair_room_index.append(room_index)

## room_bの上下どちらかの辺を通路(縦方向の区間)が横切る位置の、真左と真右に
## 柱座標を1つずつ記録する。
static func _record_doorway_pillars_vertical(map: DungeonMap, room_index: int, room: Rect2i, center: Vector2i, travel_dy_sign: int, half: int) -> void:
	if travel_dy_sign == 0:
		return
	var edge_y: int = (room.position.y - 1) if travel_dy_sign > 0 else (room.position.y + room.size.y)
	map.pillar_positions.append(Vector2i(center.x - half - 1, edge_y))
	map.pillar_step_directions.append(Vector2i(-1, 0)) # 開口部からさらに左へ離れる向き
	map.pillar_positions.append(Vector2i(center.x + half + 1, edge_y))
	map.pillar_step_directions.append(Vector2i(1, 0)) # 開口部からさらに右へ離れる向き
	map.pillar_pair_room_index.append(room_index)

## 部屋や通路の生成結果に関わらず、外周は必ず壁で囲む(最終安全策)。
static func _force_border_walls(map: DungeonMap) -> void:
	var min_c := map.get_min_coords()
	var max_c := map.get_max_coords()
	for x in range(min_c.x, max_c.x + 1):
		for t in range(BORDER_THICKNESS):
			map.set_floor(Vector2i(x, min_c.y + t), false)
			map.set_floor(Vector2i(x, max_c.y - t), false)
	for y in range(min_c.y, max_c.y + 1):
		for t in range(BORDER_THICKNESS):
			map.set_floor(Vector2i(min_c.x + t, y), false)
			map.set_floor(Vector2i(max_c.x - t, y), false)
