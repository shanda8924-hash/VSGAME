extends Node2D
class_name StageEnvironment
## 設計提案書「4. シーン構成」の StageEnvironment(背景・ステージ固有View)に対応。
## GameManager.dungeon_map(DungeonGeneratorが生成した床/壁グリッド)に合わせて
## 床タイル・壁タイル(衝突判定あり)・装飾を配置する。
##
## ダンジョンデータに依存する処理(build_dungeon)は_ready()では行わない。
## StageEnvironmentの_ready()は、ダンジョンを生成するGameManager.start_run()より
## 先に実行されてしまう(子ノードの_ready()は親より先に走るため)。そのため
## build_dungeon()はGame.gd(Controller層)からstart_run()の直後に明示的に
## 呼び出してもらう。_ready()ではTileSet(テクスチャ・タイル登録・衝突形状)の
## 組み立てだけを済ませておく。
##
## Godot 4.3以降で推奨されているTileMapLayerを使用する(旧TileMapは非推奨)。
## TileSet/SpriteFramesは手書きの.tresファイルではなく、ここでスクリプトから
## 組み立てる(エディタでの動作確認ができない環境で作成しているため、手書き
## Resourceのフォーマット崩れで何も表示されないリスクを避け、Godot自身のAPIに任せる)。

const TILESET_TEXTURE_PATH := "res://assets/tilesets/dungeon/Dungeon tileset.png"
const TILE_PIXEL_SIZE := Vector2i(16, 16)
const TILE_RENDER_SCALE := 2 # 16pxタイルを2倍表示にして模様を視認しやすくする(DungeonMap.CELL_WORLD_SIZEと一致させること)
const WALL_PHYSICS_LAYER := 0
## CharacterBody2D(Player/EnemyBasic)は既定でcollision_mask=1のため、
## 壁タイルの物理レイヤーもビット1(値1)に合わせて衝突させる。
const WALL_COLLISION_LAYER_BIT := 1
## 壁タイルの「断面3段構造」をalternative tileで表現する(上端=明るいtint、
## 本体=alternative_tile省略時の既定=0、外側/下端=苔むしたtint)。
const WALL_ALT_TOP := 1
const WALL_ALT_MOSS := 2
## 行き止まりの柱フェンスの出現頻度を間引くためのブロック単位(マス数)。
const PILLAR_FENCE_BLOCK_SIZE := 20

## 床タイル候補(Dungeon tileset.png内の16x16単位の座標)。
## 画像の一番下の帯(グレーの石畳・ひび割れ石畳が並んでいる部分、y=8〜11の行)に
## あるタイルだけに限定している。木箱・樽・松明・旗・鎖・柱・檻(格子)・レンガの壁
## ブロックが描かれているタイルは(見た目が近い色でも)床タイル候補から完全に除外した。
## 以前は壁用ブリック等を色違いの床として転用していたが、それが壁と床の見分けを
## つきにくくしていたため撤回し、1つずつ切り出して「平らな石畳・地面」に見えることを
## 確認したものだけに絞り直した。
@export var floor_atlas_coords: Array[Vector2i] = [
	Vector2i(9, 10),  # 無地の石畳(模様なし、平ら)
	Vector2i(12, 8),  # 無地の石畳(別位置、模様なし)
	Vector2i(0, 9),   # ひび割れ石畳A(十字状の細いひび)
	Vector2i(1, 10),  # ひび割れ石畳B(枝分かれした太めのひび)
	Vector2i(1, 11),  # ひび割れ石畳C(ひび+小さな欠け)
]

## 壁タイル(通常時のベース)候補。旗・檻・アーチ門・松明が並ぶ装飾帯(y=0〜4)の中から、
## それら一点物が描かれていない「繰り返し使える通常のレンガ部分」だけを選んでいる。
## 目地(モルタル)がくっきり見える、明るめの紫がかった石壁の質感。
## (以前使っていた(7,2)/(8,2)は同じ帯でも暗すぎて単調だったため選び直した。
## 隣接タイルの装飾が上下ににじんでいないか1つずつ切り出して確認済み)
## プレイヤー/敵が実際に通れないよう、TileSetの物理レイヤーでタイル全体(16x16)に
## 矩形の衝突形状を設定する(タイルごとにStaticBodyを個別生成するのではなく、
## TileSet標準のコリジョン機能を使うためパフォーマンスに配慮できる)。
@export var wall_atlas_coords: Array[Vector2i] = [
	Vector2i(7, 3), # 明るめの紫レンガ積みA(目地くっきり)
	Vector2i(9, 3), # 明るめの紫レンガ積みB(目地くっきり)
]

## 壁の断面を「上端(明るい縁取り)/本体(レンガ繰り返し)/外側・下端(苔むした緑)」の
## 3段構造にする。タイルセット内にそれ専用の縁取りタイルが見当たらなかったため、
## 参考イメージの意図(断面の3段構造)をwall_atlas_coordsのタイルへのmodulateティントで
## 再現する(ユーザー指示の「無ければmodulateティントで代用」に準拠)。
## - 上端: 床から1マス目(床に直接面する壁)に適用。
## - 本体: 上端でも外側/下端でもない、壁の内部にあたるマス(ティント無し=既定色)。
## - 外側/下端: そのマスから見て、床からさらに離れる方向にもう壁マスが続いていない
##   (=そこが壁のかたまりの末端=マップ外周や、孤立した壁のいちばん奥)マスに適用。
@export var wall_top_tint: Color = Color(1.25, 1.22, 1.35, 1.0)
## 元のレンガが紫がかっているため、緑側へ大きく寄せるteal寄りの弱いtintでは
## ほとんど紫のまま埋もれてしまう。赤味・青味を大きく削り緑を強めることで、
## はっきり「苔むした緑」に見えるようにしている。
@export var wall_moss_tint: Color = Color(0.32, 0.85, 0.4, 1.0)
## 床からこのマス数より離れた壁マスは完全に描画しない(ダンジョン建築の外側は
## 床タイルも壁タイルも置かない真っ黒なvoidにする)。
@export var wall_render_max_distance: int = 4

## 壁沿いに低頻度で混ぜる一点物の装飾(旗/アーチ門)。"top"を持つものは
## アーチ門のように縦2マス分(このマス+真上のマス)を使う。当たり判定はベースの
## 壁タイルと同様に全種類へ設定する。
## 檻(格子)と松明は「意図的な配置」に変えたため、それぞれ専用の配置処理
## (_place_rare_cages / _place_regular_torches)へ分離し、ここからは外してある。
@export var wall_decoration_variants: Array[Dictionary] = [
	{"base": Vector2i(0, 4)},  # 旗(赤)
	{"base": Vector2i(5, 4)},  # 旗(青)
	{"base": Vector2i(13, 1), "top": Vector2i(13, 0)}, # アーチ型の門(縦2マス)
]
## 壁マスに装飾を混ぜる割合。壁マス20〜30個に1個程度を目安にしている。
@export var wall_decoration_chance: float = 0.04

## 檻(格子)専用タイル。部屋の壁の一部として「時々」挟み込む程度に留め、
## 通路のど真ん中など目立つ場所には出さない(_is_room_boundary_wallで判定)。
@export var cage_atlas_coords: Vector2i = Vector2i(1, 4)
## 壁装飾より一段レア(壁マス約80個に1個程度)。かつ出入り口の柱付近は避ける。
@export var cage_chance: float = 0.012

## 柱(出入り口の両脇に必ず配置)。縦2マス(このマス+真上のマス)で構成する。
@export var pillar_atlas_base: Vector2i = Vector2i(20, 1)
@export var pillar_atlas_top: Vector2i = Vector2i(20, 0)

## 「収納コーナー」用のタイル状装飾(樽/壺)。部屋の隅にまとめて配置する。
@export var storage_cluster_variants: Array[Vector2i] = [
	Vector2i(7, 5),  # 樽
	Vector2i(12, 5), # 樽(別柄)
	Vector2i(9, 5),  # 壺(小)
	Vector2i(10, 5), # 壺(小・別柄)
]
## 収納コーナーを持たせる部屋の割合(すべての部屋に置く必要はないため約半分)。
@export var storage_cluster_room_ratio: float = 0.5

## 出入り口の柱の脇に添える旗(既存のwall_decoration_variantsの旗と同じ絵柄)。
@export var doorway_banner_atlas_coords: Array[Vector2i] = [Vector2i(0, 4), Vector2i(5, 4)]
## 出入り口(柱と柱の間の開口部)に敷く段差(階段)タイル。
@export var step_atlas_coords: Vector2i = Vector2i(9, 1)

## 通路の行き止まり(部屋の壁ではなく、かつvoidに面している壁のかたまりの末端)にのみ、
## 一定間隔で柱を並べて柵(フェンス)のように見せる。部屋の壁沿いには使わない
## (まっすぐな壁は柱を使わないというルールを守るため、_is_room_boundary_wallで除外する)。
@export var pillar_fence_spacing: int = 3
## 「行き止まり」の条件(部屋の壁ではない・床から最大距離ちょうど離れている)を
## 満たすマスはマップ内に数多く存在するため、そのままだとフェンスが至る所に
## 出来てしまう。20x20マスのブロック単位でこの割合だけ抽選し、当たったブロックの
## 中だけでフェンスを並べることで「時々、行き止まりに柵がある」程度の頻度に絞る。
@export var pillar_fence_block_chance: float = 0.12

## 床の上に低頻度で薄く散らす小さな瓦礫デカール(透過背景の小さな岩片スプライト)。
## floor_atlas_coordsのひび割れ床タイルとは別に、"モノが落ちている"ような追加の
## 装飾として重ねる(タイルセット内にひび割れ/シミ/骨片専用の透過デカールは
## 見当たらなかったため、この瓦礫スプライトで代用している)。
@export var floor_decal_atlas_coords: Vector2i = Vector2i(7, 9)
@export var floor_decal_chance: float = 0.02

const TORCH_A_PATH := "res://assets/tilesets/dungeon/torch_a.png"
const TORCH_B_PATH := "res://assets/tilesets/dungeon/torch_b.png"
const WALL_DECO_PATH := "res://assets/tilesets/dungeon/wall_deco.png"
const TORCH_A_TEXTURE: Texture2D = preload(TORCH_A_PATH)
const TORCH_B_TEXTURE: Texture2D = preload(TORCH_B_PATH)
const WALL_DECO_TEXTURE: Texture2D = preload(WALL_DECO_PATH)

## ゆらめく松明(torch_a/torch_b)は各部屋の壁沿いに、この間隔(マス数)ごとに
## 規則正しく並べる(完全ランダムな散布はやめ、一定間隔の配置に変更した)。
@export var torch_wall_spacing: int = 4
## 明滅する結晶(wall_deco)は装飾的な演出のためこれまで通りランダムに低頻度配置する。
@export var wall_deco_count: int = 15
@export var min_sprite_decoration_spacing: float = 140.0
## torch_a/torch_bは1コマ64x128pxで、無補正だと壁タイル1マス(32px)の4倍もの高さになり
## 明らかに大きすぎるため、壁タイル1〜1.5マス分の見た目高さ(32〜48px)に収まるよう
## 縮小する。128 * 0.3 = 38.4px ≒ タイル1.2マス分。
@export var torch_sprite_scale: float = 0.3

@onready var _tile_map_layer: TileMapLayer = $TileMapLayer
@onready var _decoration_layer: TileMapLayer = $DecorationTileMapLayer
@onready var _sprite_decorations: Node2D = $SpriteDecorations

var _tile_set: TileSet
var _void_background: Sprite2D
var _torch_frames_a: SpriteFrames
var _torch_frames_b: SpriteFrames
var _wall_deco_frames: SpriteFrames
var _sprite_decoration_cursor := 0

func _ready() -> void:
	_tile_set = _build_tile_set()
	if _tile_set == null:
		return

	_tile_map_layer.tile_set = _tile_set
	_decoration_layer.tile_set = _tile_set
	_tile_map_layer.scale = Vector2(TILE_RENDER_SCALE, TILE_RENDER_SCALE)
	_decoration_layer.scale = Vector2(TILE_RENDER_SCALE, TILE_RENDER_SCALE)
	_tile_map_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_decoration_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# SpriteFrames/AtlasTexture生成は全ROOMで同じため、初回だけ構築して保持する。
	_torch_frames_a = _build_sprite_frames(TORCH_A_TEXTURE, 64, 128, 4, 8.0)
	_torch_frames_b = _build_sprite_frames(TORCH_B_TEXTURE, 64, 128, 5, 8.0)
	_wall_deco_frames = _build_sprite_frames(WALL_DECO_TEXTURE, 64, 64, 8, 6.0)

	if _tile_map_layer.tile_set == null or _decoration_layer.tile_set == null:
		push_error("StageEnvironment: tile_setの代入に失敗しました(代入直後の参照がnullです)")

## Game.gdがGameManager.start_run()(ダンジョン生成)の直後に呼び出す。
## 「意図的にデザインされた部屋」という見た目にするため、以下の順で重ね書きする:
## 1. 床・壁のベースタイル(壁は床からの距離で上端/本体/外側・下端の3段にtintし、
##    床から遠すぎる壁マスは何も描画しないvoidにする)
## 2. 各部屋の出入り口の両脇に必ず1本ずつ配置する柱(対称・当たり判定あり)。
##    配置できた出入り口には柱の脇に旗を添え、開口部に段差(階段)タイルを敷く
## 3. 低頻度のランダムな壁装飾(旗/アーチ門)
## 4. さらに低頻度で、部屋の壁のみに(通路のど真ん中を避けて)混ぜる檻
## 5. 部屋の隅にまとめて置く「収納コーナー」(樽/壺、約半数の部屋のみ)
## 6. 床全体に低頻度で薄く散らす瓦礫デカール
## 7. 各部屋の壁沿いに一定間隔で並べる、ゆらめく松明(torch_a/torch_b)
## 8. 装飾的な明滅結晶(wall_deco、従来通りランダム低頻度)
func build_dungeon(map: DungeonMap) -> void:
	if _tile_set == null:
		push_error("StageEnvironment: build_dungeon呼び出し時にtile_setが未構築です")
		return
	if map == null:
		push_error("StageEnvironment: build_dungeon呼び出し時にdungeon_mapがnullです")
		return
	_clear_previous_dungeon()

	_ensure_void_background(map)
	var wall_dist := _fill_floor_and_walls(map)

	# 位置→そこに置いたbase座標のDictionaryを壁装飾パス間で共有し、
	# 柱・旗・アーチ門・檻が互いのマスを奪い合わないようにする。
	var occupied: Dictionary = {}
	var pillar_count := _place_doorway_pillars(map, occupied)
	var fence_count := _place_dead_end_pillar_fence(map, wall_dist, occupied)
	var flourish_count := _place_random_wall_flourishes(map, occupied)
	var cage_count := _place_rare_cages(map, occupied)

	var cluster_count := _place_storage_clusters(map)
	var decal_count := _place_floor_decals(map)

	# 松明と結晶はワールド座標のリストを共有し、互いに近すぎる位置への
	# 追加配置を避ける(min_sprite_decoration_spacing)。柱は通路密集地帯では
	# フォールバックで理論上の位置からずれて配置されることがあるため、松明は
	# map.pillar_positions(理論値)ではなくoccupied(実際に置かれた位置)を見て
	# 柱のすぐそばに重ならないようにする。
	var sprite_positions: Array[Vector2] = []
	var torch_count := _place_regular_torches(map, occupied, sprite_positions)
	var crystal_count := _scatter_crystal_decorations(map, sprite_positions)

	print_verbose(
		"StageEnvironment: ダンジョン敷設完了 floor=%d wall=%d rooms=%d pillars=%d dead_end_fence_pillars=%d flourishes=%d cages=%d storage_clusters=%d floor_decals=%d torches=%d crystals=%d source_count=%d" % [
			map.get_floor_cells().size(),
			map.width * map.height - map.get_floor_cells().size(),
			map.rooms.size(),
			pillar_count,
			fence_count,
			flourish_count,
			cage_count,
			cluster_count,
			decal_count,
			torch_count,
			crystal_count,
			_tile_set.get_source_count(),
		]
	)

## ROOM進行専用。重いTileMap敷設を数Frameへ分散し、Player操作を再開する前に
## 全て完了させる。暗転Tweenで隠すのではなく、各Frameの実処理量そのものを減らす。
func build_dungeon_async(map: DungeonMap, row_batch_size: int = 5) -> Dictionary:
	if _tile_set == null or map == null:
		build_dungeon(map)
		return {"total_ms": 0.0, "max_slice_ms": 0.0, "frames": 0}
	var total_start := Time.get_ticks_usec()
	var max_slice_ms := 0.0
	var max_phase := "clear"
	var frames := 0
	visible = false
	var slice_start := Time.get_ticks_usec()
	_clear_previous_dungeon()
	_ensure_void_background(map)
	var phase_ms := float(Time.get_ticks_usec() - slice_start) / 1000.0
	if phase_ms > max_slice_ms:
		max_slice_ms = phase_ms
		max_phase = "clear"
	await get_tree().process_frame
	frames += 1

	slice_start = Time.get_ticks_usec()
	var wall_dist := _compute_wall_distances(map)
	phase_ms = float(Time.get_ticks_usec() - slice_start) / 1000.0
	if phase_ms > max_slice_ms:
		max_slice_ms = phase_ms
		max_phase = "wall_distance"
	await get_tree().process_frame
	frames += 1
	var fill_profile := await _fill_floor_and_walls_async(map, wall_dist, row_batch_size)
	if float(fill_profile.get("max_slice_ms", 0.0)) > max_slice_ms:
		max_slice_ms = float(fill_profile.get("max_slice_ms", 0.0))
		max_phase = "tile_fill"
	frames += int(fill_profile.get("frames", 0))

	var occupied: Dictionary = {}
	var phase_names := ["pillars", "dead_end_fence", "wall_flourishes", "cages", "storage", "floor_decals"]
	var phases := [
		func(): return _place_doorway_pillars(map, occupied),
		func(): return _place_dead_end_pillar_fence(map, wall_dist, occupied),
		func(): return _place_random_wall_flourishes(map, occupied),
		func(): return _place_rare_cages(map, occupied),
		func(): return _place_storage_clusters(map),
		func(): return _place_floor_decals(map),
	]
	for phase_index in phases.size():
		slice_start = Time.get_ticks_usec()
		phases[phase_index].call()
		phase_ms = float(Time.get_ticks_usec() - slice_start) / 1000.0
		if phase_ms > max_slice_ms:
			max_slice_ms = phase_ms
			max_phase = phase_names[phase_index]
		await get_tree().process_frame
		frames += 1

	var sprite_positions: Array[Vector2] = []
	slice_start = Time.get_ticks_usec()
	_place_regular_torches(map, occupied, sprite_positions)
	phase_ms = float(Time.get_ticks_usec() - slice_start) / 1000.0
	if phase_ms > max_slice_ms:
		max_slice_ms = phase_ms
		max_phase = "torches"
	await get_tree().process_frame
	frames += 1
	slice_start = Time.get_ticks_usec()
	_scatter_crystal_decorations(map, sprite_positions)
	phase_ms = float(Time.get_ticks_usec() - slice_start) / 1000.0
	if phase_ms > max_slice_ms:
		max_slice_ms = phase_ms
		max_phase = "crystals"
	visible = true
	return {
		"total_ms": float(Time.get_ticks_usec() - total_start) / 1000.0,
		"max_slice_ms": max_slice_ms,
		"max_phase": max_phase,
		"frames": frames,
	}

func _fill_floor_and_walls_async(map: DungeonMap, wall_dist: Dictionary, row_batch_size: int) -> Dictionary:
	var min_c := map.get_min_coords()
	var max_c := map.get_max_coords()
	var batch := maxi(row_batch_size, 1)
	var rows_in_batch := 0
	var frames := 0
	var max_slice_ms := 0.0
	var slice_start := Time.get_ticks_usec()
	for y in range(min_c.y, max_c.y + 1):
		for x in range(min_c.x, max_c.x + 1):
			var pos := Vector2i(x, y)
			if map.is_floor(pos):
				var floor_coords := floor_atlas_coords[_hash_index(x, y, 92837111, 689287499, floor_atlas_coords.size())]
				_tile_map_layer.set_cell(pos, 0, floor_coords)
			elif wall_dist.has(pos):
				var wall_coords := wall_atlas_coords[_hash_index(x, y, 15485863, 452930477, wall_atlas_coords.size())]
				_tile_map_layer.set_cell(pos, 0, wall_coords, _wall_tier_alt(pos, wall_dist))
		rows_in_batch += 1
		if rows_in_batch >= batch:
			max_slice_ms = maxf(max_slice_ms, float(Time.get_ticks_usec() - slice_start) / 1000.0)
			await get_tree().process_frame
			frames += 1
			rows_in_batch = 0
			slice_start = Time.get_ticks_usec()
	max_slice_ms = maxf(max_slice_ms, float(Time.get_ticks_usec() - slice_start) / 1000.0)
	return {"max_slice_ms": max_slice_ms, "frames": frames}

func _clear_previous_dungeon() -> void:
	_tile_map_layer.clear()
	_decoration_layer.clear()
	for child in _sprite_decorations.get_children():
		child.visible = false
	_sprite_decoration_cursor = 0

func _build_tile_set() -> TileSet:
	var texture: Texture2D = load(TILESET_TEXTURE_PATH)
	if texture == null:
		push_error("StageEnvironment: タイルセット画像の読み込みに失敗しました -> %s" % TILESET_TEXTURE_PATH)
		return null

	var tile_set := TileSet.new()
	# 実行時生成のリソースはパスを持たずリモートインスペクタ等で無名表示になりがちなので、
	# 見分けやすいよう名前を付けておく。
	tile_set.resource_name = "DungeonFloorTileSet"
	tile_set.tile_size = TILE_PIXEL_SIZE

	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(WALL_PHYSICS_LAYER, WALL_COLLISION_LAYER_BIT)
	tile_set.set_physics_layer_collision_mask(WALL_PHYSICS_LAYER, 0)

	var atlas := TileSetAtlasSource.new()
	atlas.texture = texture
	atlas.texture_region_size = TILE_PIXEL_SIZE

	for coords in _all_used_atlas_coords():
		if not atlas.has_tile(coords):
			atlas.create_tile(coords)
		if not atlas.has_tile(coords):
			push_error("StageEnvironment: タイル座標の登録に失敗しました -> %s" % coords)

	tile_set.add_source(atlas, 0)

	# 壁タイル(ベース+一点物の装飾すべて)に、タイル全体を覆う矩形の衝突形状を設定する。
	# 装飾版(旗・檻・アーチ門・松明)も通常版と同じく通行不可にする。
	var half := Vector2(TILE_PIXEL_SIZE) / 2.0
	var rect_points := PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	for coords in _all_wall_related_coords():
		var tile_data := atlas.get_tile_data(coords, 0)
		if tile_data == null:
			push_error("StageEnvironment: 壁タイルのTileDataが取得できません -> %s" % coords)
			continue
		tile_data.add_collision_polygon(WALL_PHYSICS_LAYER)
		tile_data.set_collision_polygon_points(WALL_PHYSICS_LAYER, 0, rect_points)

	# 壁本体(wall_atlas_coords)に、上端/外側・下端用のalternative tileを追加する。
	# それぞれmodulateで色調を変え、衝突形状も通常版と同じく設定する
	# (断面のどの段でも通行不可であることに変わりはないため)。
	for coords in wall_atlas_coords:
		for alt_id in [WALL_ALT_TOP, WALL_ALT_MOSS]:
			var created_id := atlas.create_alternative_tile(coords, alt_id)
			if created_id != alt_id:
				push_error("StageEnvironment: 壁のalternative tile作成に失敗しました -> %s alt=%d" % [coords, alt_id])
				continue
			var alt_data := atlas.get_tile_data(coords, alt_id)
			alt_data.modulate = wall_top_tint if alt_id == WALL_ALT_TOP else wall_moss_tint
			alt_data.add_collision_polygon(WALL_PHYSICS_LAYER)
			alt_data.set_collision_polygon_points(WALL_PHYSICS_LAYER, 0, rect_points)

	return tile_set

## 壁関連(ベース+一点物装飾のbase/top+柱+檻)で実際に使う座標を重複なく集める。
## これらすべてに衝突形状を設定する対象になる。
func _all_wall_related_coords() -> Array[Vector2i]:
	var seen: Dictionary = {}
	var result: Array[Vector2i] = []
	for coords in wall_atlas_coords:
		if not seen.has(coords):
			seen[coords] = true
			result.append(coords)
	for variant in wall_decoration_variants:
		var base: Vector2i = variant["base"]
		if not seen.has(base):
			seen[base] = true
			result.append(base)
		if variant.has("top"):
			var top: Vector2i = variant["top"]
			if not seen.has(top):
				seen[top] = true
				result.append(top)
	for coords in [cage_atlas_coords, pillar_atlas_base, pillar_atlas_top]:
		if not seen.has(coords):
			seen[coords] = true
			result.append(coords)
	return result

## 床タイル・壁タイル・収納コーナー用タイルで実際に使う座標を重複なく集める。
func _all_used_atlas_coords() -> Array[Vector2i]:
	var seen: Dictionary = {}
	var result: Array[Vector2i] = []
	for coords in floor_atlas_coords:
		if not seen.has(coords):
			seen[coords] = true
			result.append(coords)
	for coords in _all_wall_related_coords():
		if not seen.has(coords):
			seen[coords] = true
			result.append(coords)
	for coords in storage_cluster_variants:
		if not seen.has(coords):
			seen[coords] = true
			result.append(coords)
	for coords in doorway_banner_atlas_coords:
		if not seen.has(coords):
			seen[coords] = true
			result.append(coords)
	for coords in [step_atlas_coords, floor_decal_atlas_coords]:
		if not seen.has(coords):
			seen[coords] = true
			result.append(coords)
	return result

## ダンジョン建築(床・壁レンダリング範囲)の外側を確実に真っ黒にするための保険。
## project.godotのrendering/environment/defaults/default_clear_colorを黒に設定
## 済みだが、それだけに頼らず、マップ全体を覆う巨大な単色の黒いSprite2Dを
## TileMapLayerの背面(z_index=-200)に敷いておく。これにより、床タイルはもちろん
## 余分な壁タイルも一切配置されないマップ外周は、常に完全な黒として見える。
func _ensure_void_background(map: DungeonMap) -> void:
	if _void_background != null:
		return
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	var texture := ImageTexture.create_from_image(img)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.z_index = -200
	sprite.z_as_relative = false
	var margin := 8 # マス数。カメラが多少行き過ぎても黒背景が途切れないように余裕を持たせる。
	var world_w := float(map.width + margin * 2) * DungeonMap.CELL_WORLD_SIZE
	var world_h := float(map.height + margin * 2) * DungeonMap.CELL_WORLD_SIZE
	sprite.scale = Vector2(world_w / img.get_width(), world_h / img.get_height())
	sprite.position = Vector2.ZERO
	add_child(sprite)
	_void_background = sprite

## 床マスには床タイル、壁マスにはベースの壁タイルを「上端/本体/外側・下端」の
## 3段構造(alternative tileのtint違い)で敷き詰める。床からwall_render_max_distance
## より離れた壁マスは完全に描画しない(黒い何もないvoidになる)。
## (柱・旗・アーチ門・檻・松明は後続の専用パスで一部のマスに重ね書きする)。
## 戻り値: 各壁マスの床からの距離(_compute_wall_distances)。行き止まりの柱フェンス
## など、後続パスがどのマスがvoidに面した末端かを再判定するために使う。
func _fill_floor_and_walls(map: DungeonMap) -> Dictionary:
	var min_c := map.get_min_coords()
	var max_c := map.get_max_coords()
	var wall_dist := _compute_wall_distances(map)
	for y in range(min_c.y, max_c.y + 1):
		for x in range(min_c.x, max_c.x + 1):
			var pos := Vector2i(x, y)
			if map.is_floor(pos):
				var coords := floor_atlas_coords[_hash_index(x, y, 92837111, 689287499, floor_atlas_coords.size())]
				_tile_map_layer.set_cell(pos, 0, coords)
				continue
			if not wall_dist.has(pos):
				continue # ダンジョン建築から離れすぎた壁マス: 何も描画しない(黒背景のvoid)
			var coords := wall_atlas_coords[_hash_index(x, y, 15485863, 452930477, wall_atlas_coords.size())]
			var alt := _wall_tier_alt(pos, wall_dist)
			_tile_map_layer.set_cell(pos, 0, coords, alt)
	return wall_dist

## 床マス(距離0)から4近傍でBFSし、各壁マスの「床からの最短距離」を
## wall_render_max_distanceまで求める。この距離を超えるマスは辞書に含まれず、
## それが「描画しないマス(void)」の判定に使われる。
func _compute_wall_distances(map: DungeonMap) -> Dictionary:
	var dist: Dictionary = {}
	var queue: Array[Vector2i] = []
	for cell in map.get_floor_cells():
		dist[cell] = 0
		queue.append(cell)
	var head := 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		var d: int = dist[current]
		if d >= wall_render_max_distance:
			continue
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor: Vector2i = current + offset
			if not map.is_in_bounds(neighbor):
				continue
			if dist.has(neighbor):
				continue
			dist[neighbor] = d + 1
			queue.append(neighbor)
	return dist

## 壁マスposの断面上の段(alternative tile ID)を決める:
## - 床からの距離が1(床に直接面する) -> 上端(明るいtint)
## - どの4近傍にも「自分より1つ遠い距離」の壁マスが続いていない(=壁のかたまりの
##   末端、マップ外周や孤立した壁の最奥) -> 外側・下端(苔むしたtint)
## - それ以外 -> 本体(tint無し、既定のalternative=0)
func _wall_tier_alt(pos: Vector2i, wall_dist: Dictionary) -> int:
	var d: int = wall_dist[pos]
	if d == 1:
		return WALL_ALT_TOP
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if wall_dist.get(pos + offset, -1) == d + 1:
			return 0
	return WALL_ALT_MOSS

func _is_floor_adjacent_wall(map: DungeonMap, pos: Vector2i) -> bool:
	if map.is_floor(pos):
		return false
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if map.is_floor(pos + offset):
			return true
	return false

## 出入り口ごと(map.pillar_positionsは2個1組)に、両脇の柱を「両方置けたときだけ」
## 配置する(左右非対称にならないようにするため)。通路が密集して他の通路と重なり
## 本来の位置が床になってしまっている場合は、pillar_step_directionsの向きへ最大3マス分
## ずらして再試行し、それでも無理ならその出入り口だけ諦める(通行可能なマスを塞がない
## ことを優先する)。柱が配置できた出入り口には、柱の脇に旗を添え、柱と柱の間の
## 開口部(床マス)には段差(階段)タイルを敷いて「意図的に設計された入り口」に見せる。
##
## 1つの部屋に複数の出入り口が近接していると、柱が壁沿いに連続して並び「柱の列」の
## ように見えてしまう。柱は本来の目的(出入り口の目印)に限定するため、既に柱を
## 置いた出入り口からDOORWAY_MIN_SEPARATIONマス以内にある別の出入り口には
## 柱を置かない(通路・段差・松明などそれ以外の要素は影響を受けない)。
const DOORWAY_MIN_SEPARATION := 6

func _place_doorway_pillars(map: DungeonMap, occupied: Dictionary) -> int:
	var count := 0
	var placed_pillar_positions: Array[Vector2i] = []
	var i := 0
	while i + 1 < map.pillar_positions.size():
		var pos_a: Vector2i = map.pillar_positions[i]
		var step_a: Vector2i = map.pillar_step_directions[i]
		var pos_b: Vector2i = map.pillar_positions[i + 1]
		var step_b: Vector2i = map.pillar_step_directions[i + 1]
		i += 2

		if _is_near_any_cell(pos_a, placed_pillar_positions, DOORWAY_MIN_SEPARATION) or _is_near_any_cell(pos_b, placed_pillar_positions, DOORWAY_MIN_SEPARATION):
			continue # 近くの出入り口に既に柱があるため、柱の列にならないよう見送る

		for attempt in range(4):
			var try_a := pos_a + step_a * attempt
			var try_b := pos_b + step_b * attempt
			if _is_pillar_base_available(try_a, map, occupied) and _is_pillar_base_available(try_b, map, occupied):
				_place_single_pillar(try_a, map, occupied)
				_place_single_pillar(try_b, map, occupied)
				_place_doorway_flanking_banner(try_a, step_a, map, occupied)
				_place_doorway_flanking_banner(try_b, step_b, map, occupied)
				_place_doorway_step(pos_a, pos_b, map)
				placed_pillar_positions.append(try_a)
				placed_pillar_positions.append(try_b)
				count += 1
				break
	return count

func _is_near_any_cell(pos: Vector2i, cells: Array[Vector2i], radius: int) -> bool:
	for cell in cells:
		if absi(cell.x - pos.x) <= radius and absi(cell.y - pos.y) <= radius:
			return true
	return false

## 通路の行き止まり(部屋の境界壁ではなく、かつ床からwall_render_max_distance分
## 離れた、壁のかたまりの最も奥=voidの直前のマス)にのみ、pillar_fence_spacingおきに
## 柱を並べて柵のように見せる。
## 部屋の壁沿い(_is_room_boundary_wall)は対象外にすることで、「まっすぐな部屋の壁は
## 柱を使わない」という既存のルールと両立させている。
## 単に「壁のかたまりの末端(MOSS)」だけを条件にすると、近接した部屋同士を隔てる
## 薄い(2マス程度の)間仕切り壁まですべて対象になってしまい柵だらけになるため、
## 「床からの距離がwall_render_max_distanceちょうど(=描画範囲の最奥、voidの直前)」
## という条件を追加し、本当に何もない方向へ深く伸びている壁だけに絞っている。
## (x+y)%spacing==0という単純な判定を使うことで、水平・垂直どちらの向きの並びでも
## 実際に歩いてみると隣接マスとの間隔がspacingマスおきになる(x+yは1マス移動するごとに
## 必ず1ずつ変化するため)。
func _place_dead_end_pillar_fence(map: DungeonMap, wall_dist: Dictionary, occupied: Dictionary) -> int:
	var count := 0
	for pos in wall_dist:
		if map.is_floor(pos) or occupied.has(pos):
			continue
		if _is_room_boundary_wall(pos, map):
			continue
		var d: int = wall_dist[pos]
		if d != wall_render_max_distance:
			continue
		if _wall_tier_alt(pos, wall_dist) != WALL_ALT_MOSS:
			continue
		if (pos.x + pos.y) % pillar_fence_spacing != 0:
			continue
		var block := Vector2i(floori(float(pos.x) / PILLAR_FENCE_BLOCK_SIZE), floori(float(pos.y) / PILLAR_FENCE_BLOCK_SIZE))
		if _hash_chance(block.x, block.y, 88001, 91009) >= pillar_fence_block_chance:
			continue
		if not _is_pillar_base_available(pos, map, occupied):
			continue
		_place_single_pillar(pos, map, occupied)
		count += 1
	return count

## 柱の「さらに外側」(step方向へ2マス分、柱自身の縦2マス分の footprint と
## 重ならない位置)に、旗を1枚添える。壁マスとして空いていない場合は
## (通路密集地帯で他の要素と重なった場合など)無理に上書きせず諦める。
func _place_doorway_flanking_banner(pillar_pos: Vector2i, step: Vector2i, map: DungeonMap, occupied: Dictionary) -> void:
	var banner_pos := pillar_pos + step * 2
	if map.is_floor(banner_pos) or occupied.has(banner_pos):
		return
	var banner_coords: Vector2i = doorway_banner_atlas_coords[_hash_index(banner_pos.x, banner_pos.y, 733, 977, doorway_banner_atlas_coords.size())]
	_tile_map_layer.set_cell(banner_pos, 0, banner_coords)
	occupied[banner_pos] = banner_coords

## 柱pos_a・pos_bは出入り口の両脇にあり、互いに同じx(横並びの通路の場合)か
## 同じy(縦並びの通路の場合)を共有している。その間にある床マス(=通路の開口部)に
## 段差(階段)タイルを敷く。
func _place_doorway_step(pos_a: Vector2i, pos_b: Vector2i, map: DungeonMap) -> void:
	if pos_a.x == pos_b.x:
		var y_min := mini(pos_a.y, pos_b.y) + 1
		var y_max := maxi(pos_a.y, pos_b.y)
		for y in range(y_min, y_max):
			var cell := Vector2i(pos_a.x, y)
			if map.is_floor(cell):
				_decoration_layer.set_cell(cell, 0, step_atlas_coords)
	elif pos_a.y == pos_b.y:
		var x_min := mini(pos_a.x, pos_b.x) + 1
		var x_max := maxi(pos_a.x, pos_b.x)
		for x in range(x_min, x_max):
			var cell := Vector2i(x, pos_a.y)
			if map.is_floor(cell):
				_decoration_layer.set_cell(cell, 0, step_atlas_coords)

## 柱の土台(baseタイル)だけを必須条件にする。真上のマス(topタイル)は
## 見た目を伸ばす付加要素に過ぎないため、そこが塞がっていても土台だけで
## 1本の柱として成立させ、通路密集地帯での柱の欠落を減らす。
func _is_pillar_base_available(pos: Vector2i, map: DungeonMap, occupied: Dictionary) -> bool:
	return not map.is_floor(pos) and not occupied.has(pos)

func _place_single_pillar(pos: Vector2i, map: DungeonMap, occupied: Dictionary) -> void:
	_tile_map_layer.set_cell(pos, 0, pillar_atlas_base)
	occupied[pos] = pillar_atlas_base
	var top_pos := pos + Vector2i(0, -1)
	if not map.is_floor(top_pos) and not occupied.has(top_pos):
		_tile_map_layer.set_cell(top_pos, 0, pillar_atlas_top)
		occupied[top_pos] = pillar_atlas_base

## 装飾(2マス使うものは真上のマスも)を置ける状態か判定する:
## - 対象マスがすでに装飾済みでないこと
## - "top"を使う場合、真上のマスも壁であり、かつ未装飾であること
## - 隣接マス(上下左右、2マス分なら合わせて4マス)に同じ装飾が既に無いこと
func _can_place_wall_decoration(pos: Vector2i, variant: Dictionary, map: DungeonMap, occupied: Dictionary) -> bool:
	if occupied.has(pos):
		return false
	var cells := [pos]
	if variant.has("top"):
		var top_pos := pos + Vector2i(0, -1)
		if map.is_floor(top_pos) or occupied.has(top_pos):
			return false
		cells.append(top_pos)

	var base: Vector2i = variant["base"]
	for cell in cells:
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor: Vector2i = cell + offset
			if occupied.get(neighbor) == base:
				return false
	return true

## 床に面した壁マスに、旗/アーチ門を低頻度でランダムに混ぜる(柱が置かれた
## マスは既にoccupiedにあるため自動的に避けられる)。
func _place_random_wall_flourishes(map: DungeonMap, occupied: Dictionary) -> int:
	var count := 0
	# 全MAP矩形を走査せず、床の4近傍に実在する壁だけを候補化する。
	var candidates: Dictionary = {}
	for floor_cell in map.get_floor_cells():
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var wall_cell: Vector2i = floor_cell + offset
			if map.is_in_bounds(wall_cell) and not map.is_floor(wall_cell):
				candidates[wall_cell] = true
	for candidate in candidates.keys():
		var pos: Vector2i = candidate
		if occupied.has(pos) or randf() >= wall_decoration_chance:
			continue
		var variant: Dictionary = wall_decoration_variants[randi() % wall_decoration_variants.size()]
		if not _can_place_wall_decoration(pos, variant, map, occupied):
			continue
		_tile_map_layer.set_cell(pos, 0, variant["base"])
		occupied[pos] = variant["base"]
		if variant.has("top"):
			var top_pos := pos + Vector2i(0, -1)
			_tile_map_layer.set_cell(top_pos, 0, variant["top"])
			occupied[top_pos] = variant["base"]
		count += 1
	return count

## 檻(格子)は「壁の一部として時々挟み込む」程度に留めるため、
## - 部屋の壁面のみを対象にする(通路のど真ん中には出さない)
## - 出入り口の柱付近(2マス以内)は避ける(目立ちすぎるのを防ぐ)
## - 頻度は旗/アーチ門よりさらに低くする(cage_chance)
func _place_rare_cages(map: DungeonMap, occupied: Dictionary) -> int:
	var count := 0
	# Room外周だけを直接列挙する。旧実装のMAP全セル×全Room判定を避ける。
	var candidates: Dictionary = {}
	for room in map.rooms:
		var left := room.position.x - 1
		var right := room.position.x + room.size.x
		var top := room.position.y - 1
		var bottom := room.position.y + room.size.y
		for y in range(top, bottom + 1):
			candidates[Vector2i(left, y)] = true
			candidates[Vector2i(right, y)] = true
		for x in range(left, right + 1):
			candidates[Vector2i(x, top)] = true
			candidates[Vector2i(x, bottom)] = true
	for candidate in candidates.keys():
		var pos: Vector2i = candidate
		if map.is_floor(pos) or occupied.has(pos) or not _is_floor_adjacent_wall(map, pos):
			continue
		if _is_near_any_pillar(pos, map, 2) or randf() >= cage_chance:
			continue
		_tile_map_layer.set_cell(pos, 0, cage_atlas_coords)
		occupied[pos] = cage_atlas_coords
		count += 1
	return count

## posがいずれかの部屋の直近の外周(壁の厚み1マス分)に該当するか。
## 部屋と部屋の間をただ繋ぐだけの通路の壁は対象外になる。
func _is_room_boundary_wall(pos: Vector2i, map: DungeonMap) -> bool:
	for room in map.rooms:
		var left := room.position.x - 1
		var right := room.position.x + room.size.x
		var top := room.position.y - 1
		var bottom := room.position.y + room.size.y
		if (pos.x == left or pos.x == right) and pos.y >= top and pos.y <= bottom:
			return true
		if (pos.y == top or pos.y == bottom) and pos.x >= left and pos.x <= right:
			return true
	return false

## map.pillar_positions(理論上の柱位置)を対象にした近接判定。檻の配置回避のように
## 「実際に柱が置かれたか」に関わらず出入り口周辺を一律避けたい場合に使う。
func _is_near_any_pillar(pos: Vector2i, map: DungeonMap, radius: int) -> bool:
	for pillar_pos in map.pillar_positions:
		if absi(pillar_pos.x - pos.x) <= radius and absi(pillar_pos.y - pos.y) <= radius:
			return true
	return false

## occupied(実際に柱タイルが置かれた位置のDictionary)を対象にした近接判定。
## 松明のように「実際に描画された柱と視覚的に重ならないこと」が重要な場合に使う
## (柱はフォールバック探索で理論上の位置からずれることがあるため)。
func _is_near_placed_pillar(pos: Vector2i, occupied: Dictionary, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if occupied.get(pos + Vector2i(dx, dy)) == pillar_atlas_base:
				return true
	return false

## 部屋のうち約storage_cluster_room_ratioの割合で、1つの隅に樽/壺を2〜4個
## まとめて配置する(1個ずつ孤立させて散らすのではなく「収納コーナー」として
## まとめることで、雑然とした印象を避ける)。
func _place_storage_clusters(map: DungeonMap) -> int:
	var count := 0
	for room_index in map.rooms.size():
		if not _room_gets_storage_cluster(room_index):
			continue
		var room: Rect2i = map.rooms[room_index]
		var corners := [
			room.position + Vector2i(1, 1),
			Vector2i(room.position.x + room.size.x - 2, room.position.y + 1),
			Vector2i(room.position.x + 1, room.position.y + room.size.y - 2),
			room.position + room.size - Vector2i(2, 2),
		]
		var corner: Vector2i = corners[room_index % corners.size()]
		var item_count := 2 + (room_index % 3) # 2〜4個
		var item_offsets := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
		for i in item_count:
			var cell: Vector2i = corner + item_offsets[i]
			if not map.is_floor(cell) or _decoration_layer.get_cell_source_id(cell) != -1:
				continue
			var variant: Vector2i = storage_cluster_variants[(room_index + i) % storage_cluster_variants.size()]
			_decoration_layer.set_cell(cell, 0, variant)
			count += 1
	return count

func _room_gets_storage_cluster(room_index: int) -> bool:
	var h: int = absi((room_index * 2654435761) % 100)
	return h < int(storage_cluster_room_ratio * 100)

func _hash_index(x: int, y: int, salt_a: int, salt_b: int, count: int) -> int:
	if count <= 1:
		return 0
	var h := (x * salt_a) ^ (y * salt_b)
	return abs(h) % count

## (x, y)に対して0.0〜1.0未満の疑似乱数値を座標固定のハッシュで返す(呼び出しごとに
## 独立した系列にするためsaltを分ける)。
func _hash_chance(x: int, y: int, salt_a: int, salt_b: int) -> float:
	var h := (x * salt_a) ^ (y * salt_b)
	return float(abs(h) % 100000) / 100000.0

## 床全体(部屋・通路問わず)に低頻度で薄く瓦礫デカールを散らす。収納コーナーや
## 出入り口の段差タイルなど、装飾レイヤーに既に何か置かれているマスは避ける。
func _place_floor_decals(map: DungeonMap) -> int:
	var count := 0
	var min_c := map.get_min_coords()
	var max_c := map.get_max_coords()
	for y in range(min_c.y, max_c.y + 1):
		for x in range(min_c.x, max_c.x + 1):
			var pos := Vector2i(x, y)
			if not map.is_floor(pos):
				continue
			if _decoration_layer.get_cell_source_id(pos) != -1:
				continue
			if _hash_chance(x, y, 950213, 1299827) >= floor_decal_chance:
				continue
			_decoration_layer.set_cell(pos, 0, floor_decal_atlas_coords)
			count += 1
	return count

## 各部屋の四辺(壁沿い)に、torch_wall_spacingマスごとに規則正しく松明を並べる
## (完全ランダムな散布から、等間隔の意図的な配置に変更した)。部屋ごとに
## torch_a/torch_bを交互に使い、単調にならないようにする。
func _place_regular_torches(map: DungeonMap, occupied: Dictionary, placed: Array[Vector2]) -> int:
	if _torch_frames_a == null or _torch_frames_b == null:
		push_error("StageEnvironment: 松明の画像読み込みに失敗しました")
		return 0

	var count := 0
	for room_index in map.rooms.size():
		var room: Rect2i = map.rooms[room_index]
		var frames := _torch_frames_a if room_index % 2 == 0 else _torch_frames_b
		count += _place_torches_along_edge(map, room, true, room.position.y - 1, frames, occupied, placed)
		count += _place_torches_along_edge(map, room, true, room.position.y + room.size.y, frames, occupied, placed)
		count += _place_torches_along_edge(map, room, false, room.position.x - 1, frames, occupied, placed)
		count += _place_torches_along_edge(map, room, false, room.position.x + room.size.x, frames, occupied, placed)
	return count

## horizontal=trueなら部屋の上辺/下辺(fixed_coord=y)、falseなら左辺/右辺(fixed_coord=x)を
## torch_wall_spacingおきに歩き、出入り口の開口部(床マス)や実際に置かれた柱のすぐそばは
## スキップする。
func _place_torches_along_edge(map: DungeonMap, room: Rect2i, horizontal: bool, fixed_coord: int, frames: SpriteFrames, occupied: Dictionary, placed: Array[Vector2]) -> int:
	var start: int
	var end: int
	if horizontal:
		start = room.position.x + 1
		end = room.position.x + room.size.x - 1
	else:
		start = room.position.y + 1
		end = room.position.y + room.size.y - 1

	var count := 0
	var coord := start
	while coord < end:
		var cell := Vector2i(coord, fixed_coord) if horizontal else Vector2i(fixed_coord, coord)
		coord += torch_wall_spacing
		if map.is_floor(cell):
			continue
		if _is_near_placed_pillar(cell, occupied, 1):
			continue
		# 松明同士の間隔はtorch_wall_spacingで既に規則的に制御されているため、
		# min_sprite_decoration_spacing(結晶用の汎用チェック)はここでは適用しない
		# (torch_wall_spacing*32pxがmin_sprite_decoration_spacingより狭いと、規則的な
		# 配置の半分が誤って弾かれてしまうため)。後続の結晶配置がこの位置を避けられるよう
		# placedへは登録する。
		var world_pos := map.grid_to_world(cell)
		placed.append(world_pos)
		_spawn_single_sprite(frames, world_pos, torch_sprite_scale)
		count += 1
	return count

## 明滅する結晶(wall_deco)は演出目的の装飾のため、従来通り壁際の床マスに
## ランダム・低頻度で配置する(松明の位置とは間隔を空ける)。
func _scatter_crystal_decorations(map: DungeonMap, placed: Array[Vector2]) -> int:
	if _wall_deco_frames == null:
		push_error("StageEnvironment: 壁飾り(結晶)の画像読み込みに失敗しました")
		return 0

	var candidate_cells: Array[Vector2i] = []
	for pos in map.get_floor_cells():
		if map.is_wall_adjacent_floor(pos):
			candidate_cells.append(pos)

	return _spawn_flickering_sprites(_wall_deco_frames, wall_deco_count, candidate_cells, map, placed, 1.0)

## atlas_texture方式で1本のループアニメーション(アニメ名"default")を持つ
## SpriteFramesを組み立てる。frame_widthはコマ幅、frame_countはコマ数
## (横一列に並んでいる前提)。
func _build_sprite_frames(texture: Texture2D, frame_width: int, frame_height: int, frame_count: int, fps: float) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.set_animation_loop("default", true)
	frames.set_animation_speed("default", fps)
	for i in frame_count:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(i * frame_width, 0, frame_width, frame_height)
		frames.add_frame("default", atlas)
	return frames

func _spawn_flickering_sprites(frames: SpriteFrames, count: int, candidate_cells: Array[Vector2i], map: DungeonMap, placed: Array[Vector2], sprite_scale: float = 1.0) -> int:
	if candidate_cells.is_empty():
		return 0
	var attempts := 0
	var spawned := 0
	while spawned < count and attempts < count * 20:
		attempts += 1
		var cell: Vector2i = candidate_cells[randi() % candidate_cells.size()]
		var pos := map.grid_to_world(cell)
		if _too_close(pos, placed):
			continue
		placed.append(pos)
		spawned += 1
		_spawn_single_sprite(frames, pos, sprite_scale)
	return spawned

func _spawn_single_sprite(frames: SpriteFrames, world_pos: Vector2, sprite_scale: float) -> void:
	var sprite: AnimatedSprite2D
	if _sprite_decoration_cursor < _sprite_decorations.get_child_count():
		sprite = _sprite_decorations.get_child(_sprite_decoration_cursor) as AnimatedSprite2D
	else:
		sprite = AnimatedSprite2D.new()
		_sprite_decorations.add_child(sprite)
	_sprite_decoration_cursor += 1
	sprite.sprite_frames = frames
	sprite.position = world_pos
	sprite.scale = Vector2(sprite_scale, sprite_scale)
	sprite.visible = true
	sprite.play("default")
	sprite.frame = randi() % frames.get_frame_count("default")
	sprite.speed_scale = randf_range(0.85, 1.15) # 複数の松明が完全同期して揺れないように

func _too_close(pos: Vector2, placed: Array[Vector2]) -> bool:
	for p in placed:
		if p.distance_to(pos) < min_sprite_decoration_spacing:
			return true
	return false
