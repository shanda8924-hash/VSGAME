extends EnemyBehaviorStrategy
class_name ChaseStrategy

const CARDINAL_DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
const PATH_REFRESH_MSEC := 280
## 1物理フレーム内で_build_floor_path()を実行してよいAgent数の上限。
##
## 【これが無いと何が起きるか】経路探索は1回あたりのコストが大きいので、
## 壁越しの敵が多いフレームでは「敵の数だけ探索が走る」→ フレーム時間が
## PATH_REFRESH_MSECを超える → 次のフレームでも全員の再探索期限が切れている、
## という正のフィードバックが成立してしまい、一度重くなると二度と戻らない。
## 予算切れのAgentは前回の経路(または直進)を使い、次フレーム以降に順番が回る。
##
## 【回数だけでは足りない】幅優先探索は探索セル数が距離とともに増えるため、
## 回数を固定しても1回あたりのコストが伸びれば同じことが起きる。実測では
## プレイヤーから300〜610px離れた敵の探索が1回3.1〜3.8ms(347〜484セル)に達し、
## 4回ぶんで12〜15msと60fpsの予算をほぼ食い潰していた。回数はここで、
## 1回あたりのコストはMAX_PATH_SEARCH_CELLSで、それぞれ独立に抑える。
const MAX_PATH_BUILDS_PER_FRAME := 2

## 1回の経路探索が展開してよいセル数の上限。距離が伸びても1回のコストが
## 頭打ちになるようにするためのもの。上限に達した探索は経路を諦めて空を返し、
## その敵はプレイヤーへ直進する(壁にはmove_and_slide()が沿ってくれる)。
##
## 近くの敵ほど探索は小さく済むため、上限にかかるのは遠くの敵だけになる。
## 遠くの敵は画面外(表示範囲は約610px)にいて回り込みの賢さが見えないので、
## そこを直進へ落としても体感は変わらない。900セルは実測0.93us/cellで
## 約0.84ms/回に相当し、MAX_PATH_BUILDS_PER_FRAMEと掛けても2ms未満に収まる。
const MAX_PATH_SEARCH_CELLS := 900

## 予算は全Agentで共有するためstaticで持つ。物理フレームが変わったら使用量を戻す。
static var _budget_physics_frame: int = -1
static var _budget_used: int = 0

var _path: Array[Vector2i] = []
var _next_path_refresh_msec: int = 0
## もっとも基本的な「プレイヤーへ直進する」AI。

func compute_direction(self_position: Vector2, target_position: Vector2) -> Vector2:
	var direct := target_position - self_position
	var map := GameManager.dungeon_map
	if map == null or map.get_meta("floor_only", false) or _has_clear_floor_line(map, self_position, target_position):
		_path.clear()
		return direct.normalized()
	# 再探索の判断は経過時間だけで行う。以前は「_pathが空」「goalセルが変わった」でも
	# 即再探索していたが、どちらも毎フレーム成立しうる条件だった
	# (探索が失敗すると_pathは空のまま / プレイヤーが1マス動くだけでgoalは変わる)ため、
	# PATH_REFRESH_MSECによる間引きが最も高コストな場面でだけ無効になっていた。
	var now := Time.get_ticks_msec()
	if now >= _next_path_refresh_msec and _consume_path_budget():
		# goalの算出は探索を実際に行うときだけでよい。予算切れのフレームで
		# 計算して捨てないよう、この分岐の内側に置く。
		var goal := _nearest_floor_cell(map, map.world_to_grid(target_position))
		var start := _nearest_floor_cell(map, map.world_to_grid(self_position))
		_path = _build_floor_path(map, start, goal)
		_next_path_refresh_msec = now + PATH_REFRESH_MSEC
	while _path.size() > 1 and self_position.distance_to(map.grid_to_world(_path[0])) <= DungeonMap.CELL_WORLD_SIZE * 0.45:
		_path.pop_front()
	if _path.is_empty():
		return direct.normalized()
	return (map.grid_to_world(_path[0]) - self_position).normalized()

## このフレームの探索枠を1つ確保できたらtrue。取れなかった場合は再探索期限を
## 進めないので、次のフレームで改めて順番待ちに並ぶ。
static func _consume_path_budget() -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _budget_physics_frame:
		_budget_physics_frame = frame
		_budget_used = 0
	if _budget_used >= MAX_PATH_BUILDS_PER_FRAME:
		return false
	_budget_used += 1
	return true

## 通行可否はDungeonMapの前計算済みPackedByteArrayを直接引く。これは全敵が
## 毎物理フレーム通る経路なので、1マスごとのメソッド呼び出しを避ける。
func _has_clear_floor_line(map: DungeonMap, from: Vector2, to: Vector2) -> bool:
	var distance := from.distance_to(to)
	var steps := maxi(1, int(ceil(distance / (DungeonMap.CELL_WORLD_SIZE * 0.45))))
	if steps <= 1:
		return true
	var clearance := map.get_navigation_clearance_data()
	var min_coords := map.get_min_coords()
	var map_width := map.width
	var map_height := map.height
	for index in range(1, steps):
		var cell := map.world_to_grid(from.lerp(to, float(index) / float(steps)))
		var local_x := cell.x - min_coords.x
		var local_y := cell.y - min_coords.y
		if local_x < 0 or local_x >= map_width or local_y < 0 or local_y >= map_height:
			return false
		if clearance[local_y * map_width + local_x] != 1:
			return false
	return true

func _nearest_floor_cell(map: DungeonMap, origin: Vector2i) -> Vector2i:
	if map.is_floor(origin):
		return origin
	for radius in range(1, 4):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := origin + Vector2i(x, y)
				if map.is_floor(candidate):
					return candidate
	return origin

## 幅優先探索。展開セル数がMAX_PATH_SEARCH_CELLSに達したら打ち切って空を返す
## (呼び出し側は直進へフォールバックする)。通行可否は_has_clear_floor_line()と
## 同じ理由で、前計算済み配列を直接引く。
func _build_floor_path(map: DungeonMap, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if not map.is_floor(start) or not map.is_floor(goal):
		return []
	var clearance := map.get_navigation_clearance_data()
	var min_coords := map.get_min_coords()
	var map_width := map.width
	var map_height := map.height
	var frontier: Array[Vector2i] = [start]
	var cursor := 0
	var came_from: Dictionary = {start: start}
	var found := false
	while cursor < frontier.size():
		var current := frontier[cursor]
		cursor += 1
		if current == goal:
			found = true
			break
		if frontier.size() >= MAX_PATH_SEARCH_CELLS:
			return []
		for direction in CARDINAL_DIRECTIONS:
			var next := current + direction
			if came_from.has(next):
				continue
			if next != goal:
				var local_x := next.x - min_coords.x
				var local_y := next.y - min_coords.y
				if local_x < 0 or local_x >= map_width or local_y < 0 or local_y >= map_height:
					continue
				if clearance[local_y * map_width + local_x] != 1:
					continue
			came_from[next] = current
			frontier.append(next)
	if not found and not came_from.has(goal):
		return []
	var reversed: Array[Vector2i] = []
	var step := goal
	while step != start:
		reversed.append(step)
		step = came_from[step]
	reversed.append(start)
	reversed.reverse()
	return reversed
