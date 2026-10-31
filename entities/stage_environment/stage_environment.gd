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

const ScenicLandmarks := preload("res://entities/stage_environment/scenic_landmarks.gd")

const TILESET_TEXTURE_PATH := "res://assets/tiles/royal/dungeon_atlas.png"
const COMBAT_TERRAIN_TEXTURE_PATH := "res://assets/tiles/royal/combat_atlas.png"
const WALL_JUNCTION_TEXTURE_PATH := "res://assets/tiles/royal/wall_relief.png"
const WALL_OVERLAY_TEXTURE_PATH := "res://assets/tiles/royal/wall_overlays.png"
const BOSS_FLOOR_BORDER_TEXTURE_PATH := "res://assets/tiles/royal/boss_floor_border.png"
const BOSS_FLOOR_SEAL_TEXTURE_PATH := "res://assets/tiles/royal/boss_floor_seal.png"
const MAP_THEME_ROOTS := {
	1: "res://assets/tiles/royal",
	2: "res://assets/tiles/amethyst_depths",
	3: "res://assets/tiles/ruin_forge",
}
const TILE_PIXEL_SIZE := Vector2i(16, 16)
const TILE_RENDER_SCALE := 2 # 16pxタイルを2倍表示にして模様を視認しやすくする(DungeonMap.CELL_WORLD_SIZEと一致させること)
const WALL_PHYSICS_LAYER := 0
## CharacterBody2D(Player/EnemyBasic)は既定でcollision_mask=1のため、
## 壁タイルの物理レイヤーもビット1(値1)に合わせて衝突させる。
const WALL_COLLISION_LAYER_BIT := 1
const COMBAT_TERRAIN_SOURCE_ID := 1
const WALL_OVERLAY_SOURCE_ID := 3
const BOSS_FLOOR_BORDER_SOURCE_ID := 4
const WALL_JUNCTION_SOURCE_ID := 5
const THEME_DETAIL_SOURCE_ID := 6
const THEME_FLOOR_SOURCE_ID := 7
const FLOOR_ALT_BLOCKER := 3
const ARENA_TILES := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
const HAZARD_TILES := [Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0)]
const PILLAR_FLOOR_TILES := [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]
const CHOKEPOINT_FLOOR_TILES := [Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1), Vector2i(7, 1)]
const CHOKEPOINT_BLOCK_TILES := [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)]
const BOSS_BANNER_BASE := Vector2i(2, 1)
const WALL_PILASTER_BASE := Vector2i(3, 1)

## 新規Royal Atlas。既存の16px座標契約は維持し、絵を全面交換する。
## tools/build_royal_dungeon.pyが同じ石材Paletteで床/戦闘地形/完全な小物をpackする。
@export var floor_atlas_coords: Array[Vector2i] = [
	Vector2i(9, 10),  # 無地の石畳(模様なし、平ら)
	Vector2i(12, 8),  # 無地の石畳(別位置、模様なし)
	Vector2i(0, 9),   # ひび割れ石畳A(十字状の細いひび)
	Vector2i(1, 10),  # ひび割れ石畳B(枝分かれした太めのひび)
	Vector2i(1, 11),  # ひび割れ石畳C(ひび+小さな欠け)
]

## 床からこのマス数より離れた壁マスは完全に描画しない(ダンジョン建築の外側は
## 床タイルも壁タイルも置かない真っ黒なvoidにする)。
@export var wall_render_max_distance: int = 4

## 透過PNGの旗は別レイヤーに重ねる。下地の石材/笠木/Collisionを交換しない。
## 檻(格子)と松明は「意図的な配置」に変えたため、それぞれ専用の配置処理
## (_place_rare_cages / _place_regular_torches)へ分離し、ここからは外してある。
@export var wall_decoration_variants: Array[Dictionary] = [
	{"base": Vector2i(0, 1), "top": Vector2i(0, 0)},
	{"base": Vector2i(1, 1), "top": Vector2i(1, 0)},
]
## 壁マスに装飾を混ぜる割合。壁マス20〜30個に1個程度を目安にしている。
@export var wall_decoration_chance: float = 0.04

## 檻(格子)専用タイル。部屋の壁の一部として「時々」挟み込む程度に留め、
## 通路のど真ん中など目立つ場所には出さない(部屋外周の正面壁だけを候補化)。
@export var cage_atlas_coords: Vector2i = Vector2i(5, 0)
## 壁装飾より一段レア(壁マス約80個に1個程度)。かつ出入り口の柱付近は避ける。
@export var cage_chance: float = 0.012

## 「収納コーナー」用のタイル状装飾(樽/壺)。部屋の隅にまとめて配置する。
@export var storage_cluster_variants: Array[Vector2i] = [
	Vector2i(7, 5),  # 樽
	Vector2i(12, 5), # 樽(別柄)
	Vector2i(9, 5),  # 壺(小)
	Vector2i(10, 5), # 壺(小・別柄)
]
## 収納コーナーを持たせる部屋の割合(すべての部屋に置く必要はないため約半分)。
@export var storage_cluster_room_ratio: float = 0.5

## 出入り口の正面壁に添える旗。
@export var doorway_banner_atlas_coords: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 1)]
## 出入り口の開口部に敷く段差(階段)タイル。
@export var step_atlas_coords: Vector2i = Vector2i(9, 1)

## 床の上に低頻度で薄く散らす小さな瓦礫デカール(透過背景の小さな岩片スプライト)。
## floor_atlas_coordsのひび割れ床タイルとは別に、"モノが落ちている"ような追加の
## 装飾として重ねる(タイルセット内にひび割れ/シミ/骨片専用の透過デカールは
## 見当たらなかったため、この瓦礫スプライトで代用している)。
@export var floor_decal_atlas_coords: Vector2i = Vector2i(7, 9)
@export var floor_decal_chance: float = 0.02

const TORCH_A_PATH := "res://assets/tiles/royal/torch_6f.png"
const TORCH_B_PATH := "res://assets/tiles/royal/torch_6f.png"
const WALL_DECO_PATH := "res://assets/tiles/royal/crystal.png"

## ゆらめく松明(torch_a/torch_b)は各部屋の壁沿いに、この間隔(マス数)ごとに
## 規則正しく並べる(完全ランダムな散布はやめ、一定間隔の配置に変更した)。
@export var torch_wall_spacing: int = 4
## 明滅する結晶(wall_deco)は装飾的な演出のためこれまで通りランダムに低頻度配置する。
@export var wall_deco_count: int = 15
@export var min_sprite_decoration_spacing: float = 140.0
## 16x24px×6コマの炎を整数2倍表示。下半分の燭台は全コマ固定、追加Particleなし。
@export var torch_sprite_scale: float = 2.0

@onready var _tile_map_layer: TileMapLayer = $TileMapLayer
@onready var _combat_terrain_layer: TileMapLayer = $CombatTerrainTileMapLayer
@onready var _decoration_layer: TileMapLayer = $DecorationTileMapLayer
@onready var _wall_overlay_layer: TileMapLayer = $WallOverlayTileMapLayer
@onready var _sprite_decorations: Node2D = $SpriteDecorations

var _tile_set: TileSet
var _void_background: Sprite2D
var _torch_frames_a: SpriteFrames
var _torch_frames_b: SpriteFrames
var _wall_deco_frames: SpriteFrames
var _sprite_decoration_cursor := 0
var _royal_crest: Sprite2D
var _boss_floor_seal: Sprite2D
var _surge_visual_tween: Tween = null
var _active_map_theme := -1

func _ready() -> void:
	_activate_map_theme(1)
	if _tile_set == null:
		return

	_tile_map_layer.tile_set = _tile_set
	_combat_terrain_layer.tile_set = _tile_set
	_decoration_layer.tile_set = _tile_set
	_wall_overlay_layer.tile_set = _tile_set
	_tile_map_layer.scale = Vector2(TILE_RENDER_SCALE, TILE_RENDER_SCALE)
	_combat_terrain_layer.scale = Vector2(TILE_RENDER_SCALE, TILE_RENDER_SCALE)
	_decoration_layer.scale = Vector2(TILE_RENDER_SCALE, TILE_RENDER_SCALE)
	_wall_overlay_layer.scale = Vector2(TILE_RENDER_SCALE, TILE_RENDER_SCALE)
	_tile_map_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_combat_terrain_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_decoration_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_wall_overlay_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _tile_map_layer.tile_set == null or _decoration_layer.tile_set == null:
		push_error("StageEnvironment: tile_setの代入に失敗しました(代入直後の参照がnullです)")

func _current_map_theme_index() -> int:
	return GameManager.current_map_index if MAP_THEME_ROOTS.has(GameManager.current_map_index) else 1

func _theme_asset(file_name: String) -> String:
	return String(MAP_THEME_ROOTS.get(_active_map_theme, MAP_THEME_ROOTS[1])) + "/" + file_name

func _activate_map_theme(map_index: int) -> void:
	var next_theme := map_index if MAP_THEME_ROOTS.has(map_index) else 1
	if _active_map_theme == next_theme and _tile_set != null:
		return
	_active_map_theme = next_theme
	_tile_set = _build_tile_set()
	if _tile_set == null:
		return
	for layer: TileMapLayer in [_tile_map_layer, _combat_terrain_layer, _decoration_layer, _wall_overlay_layer]:
		layer.tile_set = _tile_set
	var torch_texture := load(_theme_asset("torch_6f.png")) as Texture2D
	var obstacle_texture := load(_theme_asset("crystal_pixel_v3.png" if _active_map_theme in [2, 3] else "crystal.png")) as Texture2D
	if _active_map_theme in [2, 3]:
		obstacle_texture = load("res://assets/visuals/ember_v5/map%d_props.png" % _active_map_theme) as Texture2D
	if torch_texture == null or obstacle_texture == null:
		push_error("StageEnvironment: MAP%d専用の装飾画像を読み込めません" % _active_map_theme)
		return
	_torch_frames_a = _build_sprite_frames(torch_texture, 16, 24, 6, 8.0)
	_torch_frames_b = _torch_frames_a
	var prop_frame_size := obstacle_texture.get_height()
	var prop_frame_count := maxi(1, obstacle_texture.get_width() / prop_frame_size)
	_wall_deco_frames = _build_sprite_frames(obstacle_texture, prop_frame_size, prop_frame_size, prop_frame_count, 1.0)
	if is_instance_valid(_royal_crest):
		_royal_crest.texture = load(_theme_asset("royal_inlay.png"))
	if is_instance_valid(_boss_floor_seal):
		_boss_floor_seal.texture = load(_theme_asset("boss_floor_seal.png"))

func _theme_storage_ratio() -> float:
	match _active_map_theme:
		2: return 0.28
		3: return 0.62
		_: return storage_cluster_room_ratio

func _theme_floor_decal_chance() -> float:
	match _active_map_theme:
		2: return 0.035
		3: return 0.07
		_: return floor_decal_chance

func _theme_torch_spacing() -> int:
	match _active_map_theme:
		2: return 4
		3: return 4
		_: return torch_wall_spacing

func _theme_obstacle_count() -> int:
	match _active_map_theme:
		2: return 12
		3: return 10
		_: return maxi(6, wall_deco_count - 6)

func _theme_obstacle_scale() -> float:
	return 2.0

func _theme_wall_render_distance() -> int:
	match _active_map_theme:
		2: return 2
		3: return 3
		_: return wall_render_max_distance

func _theme_void_color() -> Color:
	match _active_map_theme:
		2: return Color("08091a")
		3: return Color("130905")
		_: return Color.BLACK

## Game.gdがGameManager.start_run()(ダンジョン生成)の直後に呼び出す。
## 下地の石材を連続させたまま、以下の順で透過装飾を重ねる:
## 1. 床・壁のベースタイル(元の暗い上面・明るい正面と、それらを結ぶ加工済み角を使い、
##    床から遠すぎる壁マスだけ何も描画しないvoidにする)
## 2. Boss広間の象嵌/壁付柱/王旗、出入り口の床に敷居、実在する正面壁に旗
## 3. 正面壁だけに低頻度の旗
## 4. さらに低頻度で、部屋の壁のみに(通路のど真ん中を避けて)混ぜる檻
## 5. 部屋の隅にまとめて置く「収納コーナー」(樽/壺、約半数の部屋のみ)
## 6. 床全体に低頻度で薄く散らす瓦礫デカール
## 7. 各部屋の壁沿いに一定間隔で並べる、ゆらめく松明(torch_a/torch_b)
## 8. 装飾的な明滅結晶(wall_deco、従来通りランダム低頻度)
func build_dungeon(map: DungeonMap) -> void:
	if map.get_meta("isolated_room", false):
		_activate_map_theme(_current_map_theme_index())
		_build_isolated_room(map)
		return
	_activate_map_theme(_current_map_theme_index())
	if _tile_set == null:
		push_error("StageEnvironment: build_dungeon呼び出し時にtile_setが未構築です")
		return
	if map == null:
		push_error("StageEnvironment: build_dungeon呼び出し時にdungeon_mapがnullです")
		return
	_clear_previous_dungeon()
	var landmarks := ScenicLandmarks.prepare(map, _active_map_theme)
	ScenicLandmarks.render(self, map, landmarks)

	_ensure_void_background(map)
	_fill_floor_and_walls(map)
	var combat_terrain_count := _place_combat_regions(map)
	var theme_detail_count := _place_theme_floor_details(map)
	_place_royal_crest(map)

	# 位置→そこに置いたbase座標のDictionaryを壁装飾パス間で共有し、
	# 旗・檻が互いのマスを奪い合わないようにする。
	var occupied: Dictionary = {}
	var sprite_positions: Array[Vector2] = []
	ScenicLandmarks.reserve_decorations(map, occupied, sprite_positions)
	_place_boss_chamber(map, occupied, sprite_positions)
	var doorway_count := _place_doorway_accents(map, occupied)
	var flourish_count := _place_random_wall_flourishes(map, occupied)
	var cage_count := _place_rare_cages(map, occupied)

	var cluster_count := _place_storage_clusters(map)
	var decal_count := _place_floor_decals(map)

	# 松明と結晶はワールド座標のリストを共有し、互いに近すぎる位置への
	# 追加配置を避ける(min_sprite_decoration_spacing)。松明は壁装飾と重ねない。
	var torch_count := _place_regular_torches(map, occupied, sprite_positions)
	var crystal_count := _scatter_crystal_decorations(map, sprite_positions)
	_refresh_painted_surfaces(map)
	var ruin_count := preload("res://entities/stage_environment/imported_ruin_props.gd").install(self, map, _active_map_theme)

	print_verbose(
		"StageEnvironment: ダンジョン敷設完了 floor=%d wall=%d rooms=%d combat_terrain=%d theme_details=%d doorways=%d flourishes=%d cages=%d storage_clusters=%d floor_decals=%d torches=%d crystals=%d ruins=%d source_count=%d" % [
			map.get_floor_cells().size(),
			map.width * map.height - map.get_floor_cells().size(),
			map.rooms.size(),
			combat_terrain_count,
			theme_detail_count,
			doorway_count,
			flourish_count,
			cage_count,
			cluster_count,
			decal_count,
			torch_count,
			crystal_count,
			ruin_count,
			_tile_set.get_source_count(),
		]
	)

## ROOM進行専用。重いTileMap敷設を数Frameへ分散し、Player操作を再開する前に
## 全て完了させる。暗転Tweenで隠すのではなく、各Frameの実処理量そのものを減らす。
func build_dungeon_async(map: DungeonMap, row_batch_size: int = 5) -> Dictionary:
	_activate_map_theme(_current_map_theme_index())
	if map != null and map.get_meta("isolated_room", false):
		var started := Time.get_ticks_usec()
		visible = false
		_build_isolated_room(map)
		var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
		await get_tree().physics_frame
		visible = true
		return {"total_ms": elapsed, "max_slice_ms": elapsed, "frames": 1}
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
	var landmarks := ScenicLandmarks.prepare(map, _active_map_theme)
	ScenicLandmarks.render(self, map, landmarks)
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

	slice_start = Time.get_ticks_usec()
	_place_combat_regions(map)
	_place_theme_floor_details(map)
	phase_ms = float(Time.get_ticks_usec() - slice_start) / 1000.0
	if phase_ms > max_slice_ms:
		max_slice_ms = phase_ms
		max_phase = "combat_regions"
	await get_tree().process_frame
	frames += 1

	var occupied: Dictionary = {}
	var sprite_positions: Array[Vector2] = []
	ScenicLandmarks.reserve_decorations(map, occupied, sprite_positions)
	var phase_names := ["boss_chamber", "doorways", "wall_flourishes", "cages", "storage", "floor_decals"]
	var phases := [
		func(): return _place_boss_chamber(map, occupied, sprite_positions),
		func(): return _place_doorway_accents(map, occupied),
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
	_refresh_painted_surfaces(map)
	preload("res://entities/stage_environment/imported_ruin_props.gd").install(self, map, _active_map_theme)
	visible = true
	_place_royal_crest(map)
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
				_set_floor_cell(pos)
			elif wall_dist.has(pos):
				_set_wall_cell(map, pos, wall_dist)
		rows_in_batch += 1
		if rows_in_batch >= batch:
			max_slice_ms = maxf(max_slice_ms, float(Time.get_ticks_usec() - slice_start) / 1000.0)
			await get_tree().process_frame
			frames += 1
			rows_in_batch = 0
			slice_start = Time.get_ticks_usec()
	max_slice_ms = maxf(max_slice_ms, float(Time.get_ticks_usec() - slice_start) / 1000.0)
	return {"max_slice_ms": max_slice_ms, "frames": frames}

var _room_exit_saved_cells: Array[Dictionary] = []

## A real opening in the wall's visual and physical layers. Restore the old
## opening when the next room in the same dungeon becomes active.
func set_room_exit_wall(position: Vector2) -> void:
	for old in _room_exit_saved_cells:
		old.layer.set_cell(old.cell, old.source, old.atlas, old.alternative)
	_room_exit_saved_cells.clear()
	var map := GameManager.dungeon_map
	var first_floor := map.world_to_grid(position + Vector2(0, 16))
	var cut: Array[Vector2i] = []
	for depth in range(1, 4):
		var cell := first_floor + Vector2i(0, -depth)
		if map.is_floor(cell):
			continue
		cut.append(cell)
		for layer in [_tile_map_layer, _combat_terrain_layer, _decoration_layer, _wall_overlay_layer]:
			_room_exit_saved_cells.append({"layer":layer,"cell":cell,"source":layer.get_cell_source_id(cell),"atlas":layer.get_cell_atlas_coords(cell),"alternative":layer.get_cell_alternative_tile(cell)})
			if layer == _tile_map_layer and layer.get_cell_source_id(cell) >= 0:
				# Preserve its wall art but remove collision only at this doorway.
				var source := layer.tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
				var coords: Vector2i = layer.get_cell_atlas_coords(cell)
				if not source.has_alternative_tile(coords, 4):
					source.create_alternative_tile(coords, 4)
				layer.set_cell(cell, layer.get_cell_source_id(cell), coords, 4)
			elif layer != _tile_map_layer:
				layer.erase_cell(cell)
	map.set_meta("room_exit_wall_cells", cut)
	var painted := get_node_or_null("PaintedSurfaces")
	if painted: painted.queue_redraw()

func _clear_previous_dungeon() -> void:
	_room_exit_saved_cells.clear()
	for node_name in ["PaintedSurfaces", "PaintedProps", "ImportedRuinProps"]:
		var old := get_node_or_null(node_name)
		if old != null:
			remove_child(old)
			old.queue_free()
	_decoration_layer.visible = true
	_wall_overlay_layer.visible = true
	_combat_terrain_layer.visible = true
	for old_sprite in _sprite_decorations.get_children():
		old_sprite.self_modulate = Color.WHITE
	var old_landmarks := get_node_or_null("ScenicLandmarks")
	if old_landmarks != null:
		remove_child(old_landmarks)
		old_landmarks.queue_free()
	if is_instance_valid(_royal_crest): _royal_crest.hide()
	if is_instance_valid(_boss_floor_seal): _boss_floor_seal.hide()
	_tile_map_layer.clear()
	_combat_terrain_layer.clear()
	_decoration_layer.clear()
	_wall_overlay_layer.clear()
	for child in _sprite_decorations.get_children():
		child.visible = false
		if child is AnimatedSprite2D:
			child.stop()
			var body := child.get_node_or_null("PropBody") as StaticBody2D
			if body:
				body.collision_layer = 0
	_sprite_decoration_cursor = 0
	set_surge_visual(false, false)

func _build_isolated_room(map: DungeonMap) -> void:
	_clear_previous_dungeon()
	_ensure_void_background(map)
	if map.get_meta("floor_only", false):
		_refresh_painted_surfaces(map)
		return
	_fill_floor_and_walls(map)
	_refresh_painted_surfaces(map)
	var occupied := {}
	var positions: Array[Vector2] = []
	if map.boss_room_index >= 0:
		_place_boss_chamber(map, occupied, positions)
	_place_regular_torches(map, occupied, positions)
	preload("res://entities/stage_environment/imported_ruin_props.gd").install(self, map, 1)

func _build_tile_set() -> TileSet:
	var texture_path := _theme_asset("dungeon_atlas.png")
	var texture: Texture2D = load(texture_path)
	if texture == null:
		push_error("StageEnvironment: タイルセット画像の読み込みに失敗しました -> %s" % texture_path)
		return null

	var tile_set := TileSet.new()
	# 実行時生成のリソースはパスを持たずリモートインスペクタ等で無名表示になりがちなので、
	# 見分けやすいよう名前を付けておく。
	tile_set.resource_name = "DungeonFloorTileSet_MAP%d" % _active_map_theme
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
	# Storage is solid at its base; decals and torches remain non-blocking.
	for coords in storage_cluster_variants:
		var data := atlas.get_tile_data(coords, 0)
		data.add_collision_polygon(WALL_PHYSICS_LAYER)
		data.set_collision_polygon_points(WALL_PHYSICS_LAYER, 0, PackedVector2Array([
			Vector2(-6, -2), Vector2(6, -2), Vector2(6, 7), Vector2(-6, 7)]))

	var combat_texture_path := _theme_asset("combat_atlas.png")
	var combat_texture: Texture2D = load(combat_texture_path)
	if combat_texture == null:
		push_error("StageEnvironment: 戦闘地形タイル画像の読み込みに失敗しました -> %s" % combat_texture_path)
		return null
	var combat_atlas := TileSetAtlasSource.new()
	combat_atlas.texture = combat_texture
	combat_atlas.texture_region_size = TILE_PIXEL_SIZE
	for coords in _all_combat_terrain_coords():
		combat_atlas.create_tile(coords)
	tile_set.add_source(combat_atlas, COMBAT_TERRAIN_SOURCE_ID)

	# 衝突は下地の壁だけが担当し、透過装飾には付けない。
	var half := Vector2(TILE_PIXEL_SIZE) / 2.0
	var rect_points := PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	# 床の実体柱も背後の石畳を継続。透明柱の4セル下だけ元のCollisionを残す。
	for coords in floor_atlas_coords:
		atlas.create_alternative_tile(coords, FLOOR_ALT_BLOCKER)
		var blocker := atlas.get_tile_data(coords, FLOOR_ALT_BLOCKER)
		blocker.add_collision_polygon(WALL_PHYSICS_LAYER)
		blocker.set_collision_polygon_points(WALL_PHYSICS_LAYER, 0, rect_points)

	# 元の上面/正面を保持し、角の明暗接続だけ加工した256近傍Atlas。
	# 後付けの距離Tintは使わず、画像の立体陰影と元の矩形Collisionを保持する。
	var junction_texture_path := _theme_asset("wall_relief.png")
	var junction_texture := load(junction_texture_path) as Texture2D
	var themed_wall_atlas := _active_map_theme in [2, 3]
	var expected_wall_size := Vector2(1024, 256) if themed_wall_atlas else Vector2(256, 256)
	if junction_texture == null or junction_texture.get_size() != expected_wall_size:
		push_error("StageEnvironment: 立体壁Atlasの寸法が不正です expected=%s -> %s" % [expected_wall_size, junction_texture_path])
		return null
	var junction_atlas := TileSetAtlasSource.new()
	junction_atlas.texture = junction_texture
	junction_atlas.texture_region_size = TILE_PIXEL_SIZE
	tile_set.add_source(junction_atlas, WALL_JUNCTION_SOURCE_ID)
	var wall_atlas_columns := 64 if themed_wall_atlas else 16
	for row in range(16):
		for column in range(wall_atlas_columns):
			var coords := Vector2i(column, row)
			junction_atlas.create_tile(coords)
			var junction_data := junction_atlas.get_tile_data(coords, 0)
			junction_data.modulate = Color.WHITE
			junction_data.add_collision_polygon(WALL_PHYSICS_LAYER)
			junction_data.set_collision_polygon_points(WALL_PHYSICS_LAYER, 0, rect_points)

	var overlay_texture := load(_theme_asset("wall_overlays.png")) as Texture2D
	var border_texture := load(_theme_asset("boss_floor_border.png")) as Texture2D
	if overlay_texture == null or overlay_texture.get_size() != Vector2(128, 64) or border_texture == null or border_texture.get_size() != Vector2(48, 48):
		push_error("StageEnvironment: 透過壁装飾Atlas(128x64)/Boss縁取りAtlas(48x48)の寸法が不正です")
		return null
	var overlay_atlas := TileSetAtlasSource.new()
	overlay_atlas.texture = overlay_texture
	overlay_atlas.texture_region_size = TILE_PIXEL_SIZE
	for y in range(4):
		for x in range(8):
			overlay_atlas.create_tile(Vector2i(x, y))
	tile_set.add_source(overlay_atlas, WALL_OVERLAY_SOURCE_ID)
	var border_atlas := TileSetAtlasSource.new()
	border_atlas.texture = border_texture
	border_atlas.texture_region_size = TILE_PIXEL_SIZE
	for y in range(3):
		for x in range(3):
			if Vector2i(x, y) != Vector2i.ONE:
				border_atlas.create_tile(Vector2i(x, y))
	tile_set.add_source(border_atlas, BOSS_FLOOR_BORDER_SOURCE_ID)

	# MAP2/3は32px単位でつながる専用床意匠を重ねる。小さな16px模様を
	# 全面反復させず、部屋ごとに鉱脈・水溜まり・炉床亀裂・鉄格子を置く。
	if _active_map_theme in [2, 3]:
		var detail_texture_path := _theme_asset("ground_details.png")
		var detail_texture := load(detail_texture_path) as Texture2D
		if detail_texture == null or detail_texture.get_size() != Vector2(128, 64):
			push_error("StageEnvironment: 専用床意匠Atlasは128x64である必要があります -> " + detail_texture_path)
			return null
		var detail_atlas := TileSetAtlasSource.new()
		detail_atlas.texture = detail_texture
		detail_atlas.texture_region_size = TILE_PIXEL_SIZE
		for y in range(4):
			for x in range(8):
				detail_atlas.create_tile(Vector2i(x, y))
		tile_set.add_source(detail_atlas, THEME_DETAIL_SOURCE_ID)

		var macro_floor_path := _theme_asset("floor_macro.png")
		var macro_floor_texture := load(macro_floor_path) as Texture2D
		if macro_floor_texture == null or macro_floor_texture.get_size() != Vector2(256, 256):
			push_error("StageEnvironment: 連続床Atlasは256x256である必要があります -> " + macro_floor_path)
			return null
		var macro_floor_atlas := TileSetAtlasSource.new()
		macro_floor_atlas.texture = macro_floor_texture
		macro_floor_atlas.texture_region_size = TILE_PIXEL_SIZE
		tile_set.add_source(macro_floor_atlas, THEME_FLOOR_SOURCE_ID)
		for y in range(16):
			for x in range(16):
				var coords := Vector2i(x, y)
				macro_floor_atlas.create_tile(coords)
				macro_floor_atlas.create_alternative_tile(coords, FLOOR_ALT_BLOCKER)
				var macro_blocker := macro_floor_atlas.get_tile_data(coords, FLOOR_ALT_BLOCKER)
				macro_blocker.add_collision_polygon(WALL_PHYSICS_LAYER)
				macro_blocker.set_collision_polygon_points(WALL_PHYSICS_LAYER, 0, rect_points)

	return tile_set

func _all_combat_terrain_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for row in range(6):
		for column in range(8):
			coords.append(Vector2i(column, row))
	return coords

func _place_royal_crest(map: DungeonMap) -> void:
	# 始点の紋章床は通行可能な3x3床だけへ。Actorや衝突は増やさない。
	var center := map.spawn_point
	for y in range(-1, 2):
		for x in range(-1, 2):
			if not map.is_floor(center + Vector2i(x, y)): return
	if not is_instance_valid(_royal_crest):
		_royal_crest = Sprite2D.new()
		_royal_crest.name = "RoyalCrest"
		_royal_crest.texture = load(_theme_asset("royal_inlay.png"))
		_royal_crest.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_royal_crest.scale = Vector2.ONE * TILE_RENDER_SCALE
		_royal_crest.z_index = -8
		add_child(_royal_crest)
	_royal_crest.global_position = map.grid_to_world(center)
	_royal_crest.show()

func _is_boss_chamber_cell(map: DungeonMap, cell: Vector2i, include_walls: bool = false) -> bool:
	if map.boss_room_index < 0 or map.boss_room_index >= map.rooms.size():
		return false
	var room := map.rooms[map.boss_room_index]
	return (room.grow(2) if include_walls else room).has_point(cell)

## Boss室は同じ石床を残した儀礼広間。中央は画像だけで、Collision/発光処理なし。
## 左右一対を置ける壁だけ装飾し、入口や狭い壁へ片側だけ無理に押し込まない。
func _place_boss_chamber(map: DungeonMap, occupied: Dictionary, placed: Array[Vector2]) -> int:
	if map.boss_room_index < 0 or map.boss_room_index >= map.rooms.size():
		return 0
	var room := map.rooms[map.boss_room_index]
	var frame := room.grow(-1)
	var count := 0
	for y in range(frame.position.y, frame.end.y):
		for x in range(frame.position.x, frame.end.x):
			if x != frame.position.x and x != frame.end.x - 1 and y != frame.position.y and y != frame.end.y - 1:
				continue
			var cell := Vector2i(x, y)
			if not map.is_floor(cell):
				continue
			var atlas_x := 0 if x == frame.position.x else (2 if x == frame.end.x - 1 else 1)
			var atlas_y := 0 if y == frame.position.y else (2 if y == frame.end.y - 1 else 1)
			_decoration_layer.set_cell(cell, BOSS_FLOOR_BORDER_SOURCE_ID, Vector2i(atlas_x, atlas_y))
			count += 1
	if not is_instance_valid(_boss_floor_seal):
		_boss_floor_seal = Sprite2D.new()
		_boss_floor_seal.name = "BossFloorSeal"
		_boss_floor_seal.texture = load(_theme_asset("boss_floor_seal.png"))
		_boss_floor_seal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_boss_floor_seal.scale = Vector2.ONE * 2.0
		_boss_floor_seal.z_index = -70
		add_child(_boss_floor_seal)
	_boss_floor_seal.position = map.grid_to_world(room.position + room.size / 2)
	_boss_floor_seal.modulate = Color(0.55, 0.62, 0.72, 0.28)
	_boss_floor_seal.set_meta("boss_room_index", map.boss_room_index)
	_boss_floor_seal.show()
	for decoration in [
		{"offset": 1, "base": WALL_PILASTER_BASE, "top": WALL_PILASTER_BASE + Vector2i.UP},
		{"offset": 3, "base": BOSS_BANNER_BASE, "top": BOSS_BANNER_BASE + Vector2i.UP},
	]:
		var left := Vector2i(room.position.x + int(decoration["offset"]), room.position.y - 1)
		var right := Vector2i(room.end.x - 1 - int(decoration["offset"]), room.position.y - 1)
		if left.x >= right.x or not _can_place_wall_decoration(left, decoration, map, occupied) or not _can_place_wall_decoration(right, decoration, map, occupied):
			continue
		_place_wall_overlay(left, decoration, map, occupied)
		_place_wall_overlay(right, decoration, map, occupied)
		count += 2
	var torch_left := Vector2i(room.position.x + 5, room.position.y - 1)
	var torch_right := Vector2i(room.end.x - 6, room.position.y - 1)
	if torch_left.x < torch_right.x and _is_front_wall(map, torch_left) and _is_front_wall(map, torch_right) and not occupied.has(torch_left) and not occupied.has(torch_right):
		for cell in [torch_left, torch_right]:
			var world_pos := map.grid_to_world(cell)
			_spawn_single_sprite(_torch_frames_a, world_pos, torch_sprite_scale)
			placed.append(world_pos)
			occupied[cell] = "boss_torch"
			count += 1
	return count

func set_boss_seal_visible(value: bool) -> void:
	if is_instance_valid(_boss_floor_seal):
		_boss_floor_seal.visible = value

func _place_combat_regions(map: DungeonMap) -> int:
	var placed := 0
	for cell in map.get_combat_region_cells():
		var region_type := map.get_combat_region_type(cell)
		var coords := Vector2i(-1, -1)
		match region_type:
			DungeonMap.REGION_ARENA:
				if map.is_floor(cell):
					coords = ARENA_TILES[_hash_index(cell.x, cell.y, 449, 953, ARENA_TILES.size())]
			DungeonMap.REGION_PILLAR_FIELD:
				if map.is_terrain_obstacle(cell):
					continue # 床の青い球体/細い台座をやめ、下地と同じ石壁の障害物を見せる。
				elif map.is_floor(cell):
					coords = PILLAR_FLOOR_TILES[_hash_index(cell.x, cell.y, 761, 1237, PILLAR_FLOOR_TILES.size())]
			DungeonMap.REGION_CHOKEPOINT:
				if map.is_terrain_obstacle(cell):
					continue # 縦の短壁も下地の正面/天面/側面を維持。別の壁画像を焼き込まない。
				elif map.is_floor(cell):
					coords = CHOKEPOINT_FLOOR_TILES[_hash_index(cell.x, cell.y, 1291, 2203, CHOKEPOINT_FLOOR_TILES.size())]
			DungeonMap.REGION_HAZARD:
				if map.is_floor(cell):
					coords = ARENA_TILES[_hash_index(cell.x, cell.y, 449, 953, ARENA_TILES.size())]
					# 部屋タイプとダメージ矩形は別。安全な外周まで噴出口にしない。
					for hazard in map.hazard_regions:
						if hazard.has_point(cell):
							coords = HAZARD_TILES[_hash_index(cell.x, cell.y, 1597, 2879, HAZARD_TILES.size())]
							break
		if coords.x < 0:
			continue
		_combat_terrain_layer.set_cell(cell, COMBAT_TERRAIN_SOURCE_ID, coords)
		placed += 1
	return placed

## 専用テーマの大きな床モチーフを2x2セル単位で置く。
## 床全面を同じ縁取りで埋めず、部屋ごとに静かな面と視線を集める面を作る。
func _place_theme_floor_details(map: DungeonMap) -> int:
	if _active_map_theme not in [2, 3]:
		return 0
	var placed := 0
	for room_index in map.rooms.size():
		if room_index == map.boss_room_index:
			continue
		var room: Rect2i = map.rooms[room_index]
		if room.size.x < 7 or room.size.y < 7:
			continue
		var anchors: Array[Vector2i] = [
			room.position + Vector2i(2, 2),
			Vector2i(room.end.x - 4, room.position.y + 2),
			Vector2i(room.position.x + 2, room.end.y - 4),
			room.position + room.size / 2 - Vector2i.ONE,
		]
		var motif_count := 2 if room.size.x * room.size.y >= 130 else 1
		for motif_offset in motif_count:
			var anchor: Vector2i = anchors[(room_index + motif_offset * 2) % anchors.size()]
			var motif := _hash_index(room_index, motif_offset, 1877, 3253, 8)
			var atlas_origin := Vector2i((motif % 4) * 2, (motif >> 2) * 2)
			for dy in range(2):
				for dx in range(2):
					var cell := anchor + Vector2i(dx, dy)
					if not map.is_floor(cell) or map.is_terrain_obstacle(cell):
						continue
					if _decoration_layer.get_cell_source_id(cell) != -1:
						continue
					_decoration_layer.set_cell(cell, THEME_DETAIL_SOURCE_ID, atlas_origin + Vector2i(dx, dy))
					placed += 1
	return placed

func set_surge_visual(active: bool, animated: bool = true) -> void:
	if _surge_visual_tween != null and _surge_visual_tween.is_valid():
		_surge_visual_tween.kill()
	_surge_visual_tween = null
	var target := Color(1.04, 0.94, 0.98, 1.0) if active else Color.WHITE
	var layers: Array[CanvasItem] = [_tile_map_layer, _combat_terrain_layer, _decoration_layer, _wall_overlay_layer, _sprite_decorations]
	if not animated:
		for layer in layers:
			layer.self_modulate = target
		return
	_surge_visual_tween = create_tween().set_parallel(true)
	for layer in layers:
		_surge_visual_tween.tween_property(layer, "self_modulate", target, 0.28)

func debug_get_combat_terrain_snapshot() -> Dictionary:
	return {
		"rendered_cells": _combat_terrain_layer.get_used_cells().size(),
		"theme_detail_cells": _decoration_layer.get_used_cells_by_id(THEME_DETAIL_SOURCE_ID).size(),
		"physics_layer": _tile_set.get_physics_layer_collision_layer(WALL_PHYSICS_LAYER) if _tile_set != null else 0,
		"map_theme": _active_map_theme,
		"texture_path": _theme_asset("dungeon_atlas.png"),
		"terrain_texture_path": _theme_asset("combat_atlas.png"),
		"macro_floor_source": THEME_FLOOR_SOURCE_ID if _active_map_theme in [2, 3] else -1,
		"wall_variant_count": 4 if _active_map_theme in [2, 3] else 1,
	}

## 主Atlasの床・収納・段差・デカールだけを登録。壁は専用Source 5に集約する。
func _all_used_atlas_coords() -> Array[Vector2i]:
	var seen: Dictionary = {}
	var result: Array[Vector2i] = []
	for coords in floor_atlas_coords:
		if not seen.has(coords):
			seen[coords] = true
			result.append(coords)
	for coords in storage_cluster_variants:
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
		_void_background.modulate = _theme_void_color()
		return
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
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
	sprite.modulate = _theme_void_color()
	add_child(sprite)
	_void_background = sprite

## 床マスには床タイル、壁マスには8近傍に対応する同一石材を敷く。
## 床からwall_render_max_distance
## より離れた壁マスは完全に描画しない(黒い何もないvoidになる)。
## 柱・旗・格子・松明は後続の別レイヤーで描き、この下地は上書きしない。
## 戻り値: 各壁マスの床からの距離(_compute_wall_distances)。
func _fill_floor_and_walls(map: DungeonMap) -> Dictionary:
	var min_c := map.get_min_coords()
	var max_c := map.get_max_coords()
	var wall_dist := _compute_wall_distances(map)
	for y in range(min_c.y, max_c.y + 1):
		for x in range(min_c.x, max_c.x + 1):
			var pos := Vector2i(x, y)
			if map.is_floor(pos):
				_set_floor_cell(pos)
				continue
			if not wall_dist.has(pos):
				continue # ダンジョン建築から離れすぎた壁マス: 何も描画しない(黒背景のvoid)
			_set_wall_cell(map, pos, wall_dist)
	return wall_dist

func _set_floor_cell(pos: Vector2i, solid: bool = false) -> void:
	var alternative := FLOOR_ALT_BLOCKER if solid else 0
	if _active_map_theme in [2, 3]:
		var macro_coords := Vector2i(posmod(pos.x, 16), posmod(pos.y, 16))
		_tile_map_layer.set_cell(pos, THEME_FLOOR_SOURCE_ID, macro_coords, alternative)
		return
	var coords := floor_atlas_coords[_hash_index(pos.x, pos.y, 92837111, 689287499, floor_atlas_coords.size())]
	_tile_map_layer.set_cell(pos, 0, coords, alternative)

func _set_wall_cell(map: DungeonMap, pos: Vector2i, _wall_dist: Dictionary) -> void:
	if map.get_meta("scenic_landmark_cells", {}).has(pos):
		_set_floor_cell(pos, true)
		return
	var mask := _wall_neighbor_mask(map, pos)
	if _active_map_theme in [2, 3]:
		var variant := _theme_wall_variant(pos)
		_tile_map_layer.set_cell(pos, WALL_JUNCTION_SOURCE_ID, Vector2i((mask & 15) * 4 + variant, mask >> 4))
	else:
		_tile_map_layer.set_cell(pos, WALL_JUNCTION_SOURCE_ID, Vector2i(mask & 15, mask >> 4))

func _theme_wall_variant(pos: Vector2i) -> int:
	var roll := _hash_index(pos.x, pos.y, 1877, 3253, 128)
	if roll < 94:
		return 0
	if roll < 125:
		return 1
	if roll < 127:
		return 2
	return 3

## 床の8近傍をAtlas座標へ: N1/E2/S4/W8/NW16/NE32/SE64/SW128。
## 斜め床も省略せず、四方向の内角と上下/左右が同時に露出する細い壁を保持する。
func _wall_neighbor_mask(map: DungeonMap, pos: Vector2i) -> int:
	var mask := 0
	if map.is_floor(pos + Vector2i.UP):
		mask |= 1
	if map.is_floor(pos + Vector2i.RIGHT):
		mask |= 2
	if map.is_floor(pos + Vector2i.DOWN):
		mask |= 4
	if map.is_floor(pos + Vector2i.LEFT):
		mask |= 8
	if map.is_floor(pos + Vector2i(-1, -1)):
		mask |= 16
	if map.is_floor(pos + Vector2i(1, -1)):
		mask |= 32
	if map.is_floor(pos + Vector2i(1, 1)):
		mask |= 64
	if map.is_floor(pos + Vector2i(-1, 1)):
		mask |= 128
	return mask

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
		if d >= _theme_wall_render_distance():
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

## 壁掛けは床の上辺にある正面壁だけに置く。壁天面/void/物理柱には貼らない。
func _is_front_wall(map: DungeonMap, pos: Vector2i) -> bool:
	return map.is_in_bounds(pos) and not map.is_floor(pos) and not map.is_terrain_obstacle(pos) and map.is_floor(pos + Vector2i.DOWN)

## map.pillar_positionsはGeneratorの入口アンカーとしてのみ使う。
## 柱を壁内部へ逃がす旧fallbackとvoid端の柱フェンスは廃止。敷居は本来の床へ、
## 旗は元のアンカーが正面壁である場合のみ置く。DungeonMapの床/壁を変更しない。
const DOORWAY_MIN_SEPARATION := 6

func _place_doorway_accents(map: DungeonMap, occupied: Dictionary) -> int:
	var count := 0
	var placed_positions: Array[Vector2i] = []
	var i := 0
	while i + 1 < map.pillar_positions.size():
		var pos_a: Vector2i = map.pillar_positions[i]
		var pos_b: Vector2i = map.pillar_positions[i + 1]
		i += 2

		if _is_near_any_cell(pos_a, placed_positions, DOORWAY_MIN_SEPARATION) or _is_near_any_cell(pos_b, placed_positions, DOORWAY_MIN_SEPARATION):
			continue
		_place_doorway_banner(pos_a, map, occupied)
		_place_doorway_banner(pos_b, map, occupied)
		_place_doorway_step(pos_a, pos_b, map)
		placed_positions.append(pos_a)
		placed_positions.append(pos_b)
		count += 1
	return count

func _is_near_any_cell(pos: Vector2i, cells: Array[Vector2i], radius: int) -> bool:
	for cell in cells:
		if absi(cell.x - pos.x) <= radius and absi(cell.y - pos.y) <= radius:
			return true
	return false

func _place_doorway_banner(banner_pos: Vector2i, map: DungeonMap, occupied: Dictionary) -> void:
	if _is_boss_chamber_cell(map, banner_pos, true):
		return
	var banner_coords: Vector2i = doorway_banner_atlas_coords[_hash_index(banner_pos.x, banner_pos.y, 733, 977, doorway_banner_atlas_coords.size())]
	_place_wall_overlay(banner_pos, {"base": banner_coords, "top": banner_coords + Vector2i.UP}, map, occupied)

## pos_a・pos_bは出入り口の両脇にあり、互いに同じx(横並びの通路の場合)か
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

## 装飾(2マス使うものは真上のマスも)を置ける状態か判定する:
## - 対象マスがすでに装飾済みでないこと
## - "top"を使う場合、真上のマスも壁であり、かつ未装飾であること
## - 隣接マス(上下左右、2マス分なら合わせて4マス)に同じ装飾が既に無いこと
func _can_place_wall_decoration(pos: Vector2i, variant: Dictionary, map: DungeonMap, occupied: Dictionary) -> bool:
	if not _is_front_wall(map, pos) or occupied.has(pos):
		return false
	var cells := [pos]
	if variant.has("top"):
		var top_pos := pos + Vector2i(0, -1)
		if not map.is_in_bounds(top_pos) or map.is_floor(top_pos) or occupied.has(top_pos) or _tile_map_layer.get_cell_source_id(top_pos) == -1:
			return false
		cells.append(top_pos)

	var base: Vector2i = variant["base"]
	for cell in cells:
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor: Vector2i = cell + offset
			if occupied.get(neighbor) == base:
				return false
	return true

func _place_wall_overlay(pos: Vector2i, variant: Dictionary, map: DungeonMap, occupied: Dictionary) -> bool:
	if not _can_place_wall_decoration(pos, variant, map, occupied):
		return false
	_wall_overlay_layer.set_cell(pos, WALL_OVERLAY_SOURCE_ID, variant["base"])
	occupied[pos] = variant["base"]
	if variant.has("top"):
		_wall_overlay_layer.set_cell(pos + Vector2i.UP, WALL_OVERLAY_SOURCE_ID, variant["top"])
		occupied[pos + Vector2i.UP] = variant["base"]
	return true

## 正面壁だけに旗を低頻度で混ぜる。壁天面へ壁掛けを散布しない。
func _place_random_wall_flourishes(map: DungeonMap, occupied: Dictionary) -> int:
	var count := 0
	# 全MAP矩形を走査せず、床の真上に実在する正面壁だけを候補化する。
	var candidates: Dictionary = {}
	for floor_cell in map.get_floor_cells():
		var wall_cell: Vector2i = floor_cell + Vector2i.UP
		if _is_front_wall(map, wall_cell):
			candidates[wall_cell] = true
	for candidate in candidates.keys():
		var pos: Vector2i = candidate
		if _is_boss_chamber_cell(map, pos, true) or occupied.has(pos) or randf() >= _theme_wall_decoration_chance():
			continue
		var variant: Dictionary = wall_decoration_variants[randi() % wall_decoration_variants.size()]
		if _place_wall_overlay(pos, variant, map, occupied):
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
		if _is_boss_chamber_cell(map, pos, true) or not _is_front_wall(map, pos) or occupied.has(pos):
			continue
		if _is_near_any_pillar(pos, map, 2) or randf() >= _theme_cage_chance():
			continue
		if _place_wall_overlay(pos, {"base": cage_atlas_coords}, map, occupied):
			count += 1
	return count

func _theme_wall_decoration_chance() -> float:
	match _active_map_theme:
		2: return 0.07
		3: return 0.06
		_: return wall_decoration_chance

func _theme_cage_chance() -> float:
	match _active_map_theme:
		2: return 0.018
		3: return 0.022
		_: return cage_chance

## map.pillar_positions(理論上の柱位置)を対象にした近接判定。檻の配置回避のように
## 「実際に柱が置かれたか」に関わらず出入り口周辺を一律避けたい場合に使う。
func _is_near_any_pillar(pos: Vector2i, map: DungeonMap, radius: int) -> bool:
	for pillar_pos in map.pillar_positions:
		if absi(pillar_pos.x - pos.x) <= radius and absi(pillar_pos.y - pos.y) <= radius:
			return true
	return false

## 部屋のうち約storage_cluster_room_ratioの割合で、1つの隅に樽/壺を2〜4個
## まとめて配置する(1個ずつ孤立させて散らすのではなく「収納コーナー」として
## まとめることで、雑然とした印象を避ける)。
func _place_storage_clusters(map: DungeonMap) -> int:
	var count := 0
	for room_index in map.rooms.size():
		if room_index == map.boss_room_index or not _room_gets_storage_cluster(room_index):
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
			if not map.is_floor(cell) or map.get_meta("exploration_reserved", {}).has(cell) or _decoration_layer.get_cell_source_id(cell) != -1:
				continue
			var variant: Vector2i = storage_cluster_variants[(room_index + i) % storage_cluster_variants.size()]
			_decoration_layer.set_cell(cell, 0, variant)
			count += 1
	return count

func _room_gets_storage_cluster(room_index: int) -> bool:
	var h: int = absi((room_index * 2654435761) % 100)
	return h < int(_theme_storage_ratio() * 100)

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
			if not map.is_floor(pos) or _is_boss_chamber_cell(map, pos):
				continue
			if _decoration_layer.get_cell_source_id(pos) != -1:
				continue
			if _hash_chance(x, y, 950213, 1299827) >= _theme_floor_decal_chance():
				continue
			_decoration_layer.set_cell(pos, 0, floor_decal_atlas_coords)
			count += 1
	return count

## 各部屋の正面壁(床の上辺)だけに等間隔で松明を並べる。
## 左右/下側の壁天面に正面向きの燭台を貼らない。
func _place_regular_torches(map: DungeonMap, occupied: Dictionary, placed: Array[Vector2]) -> int:
	if _torch_frames_a == null or _torch_frames_b == null:
		push_error("StageEnvironment: 松明の画像読み込みに失敗しました")
		return 0

	var count := 0
	for room_index in map.rooms.size():
		if room_index == map.boss_room_index:
			continue
		var room: Rect2i = map.rooms[room_index]
		var frames := _torch_frames_a if room_index % 2 == 0 else _torch_frames_b
		count += _place_torches_along_edge(map, room, true, room.position.y - 1, frames, occupied, placed)
	return count

## horizontal=trueなら部屋の上辺/下辺(fixed_coord=y)、falseなら左辺/右辺(fixed_coord=x)を
## torch_wall_spacingおきに歩き、出入り口の開口部(床マス)や別の壁装飾は
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
		coord += _theme_torch_spacing()
		if not _is_front_wall(map, cell):
			continue
		if occupied.has(cell):
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

## 結晶は壁際の安全な床へ低頻度配置する。Sprite中心だけでなく不透明画像の
## 全外接矩形を検査し、壁/柱/別の装飾へ食い込ませない。
func _scatter_crystal_decorations(map: DungeonMap, placed: Array[Vector2]) -> int:
	if _wall_deco_frames == null:
		push_error("StageEnvironment: 壁飾り(結晶)の画像読み込みに失敗しました")
		return 0

	var candidate_cells: Array[Vector2i] = []
	for pos in map.get_floor_cells():
		if map.is_wall_adjacent_floor(pos) and not _is_boss_chamber_cell(map, pos):
			candidate_cells.append(pos)

	return _spawn_flickering_sprites(_wall_deco_frames, _theme_obstacle_count(), candidate_cells, map, placed, _theme_obstacle_scale())

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
	var opaque_bounds := _crystal_bounds(frames, sprite_scale)
	if not opaque_bounds.has_area():
		return 0
	var occupied_rects: Array[Rect2] = []
	for child in _sprite_decorations.get_children():
		var sprite := child as AnimatedSprite2D
		if not sprite.visible or sprite.sprite_frames == null:
			continue
		var size := sprite.sprite_frames.get_frame_texture("default", 0).get_size()
		var origin := sprite.offset - size * 0.5 if sprite.centered else sprite.offset
		occupied_rects.append(sprite.get_global_transform() * Rect2(origin, size))
	# 同じ不適切セルを繰り返し抽選せず、候補を有限回だけ調べる。
	candidate_cells.shuffle()
	var spawned := 0
	for cell in candidate_cells:
		if spawned >= count:
			break
		# grid_to_worldは描画セルの左上。実TileMapの中心をSprite親の座標へ変換する。
		var center := _sprite_decorations.to_local(_tile_map_layer.to_global(_tile_map_layer.map_to_local(cell)))
		# 36x40pxの可視画像は32pxセルより大きい。壁側に3px以上の隙間が残る
		# 小さな内寄せだけを試し、通路の中央まで遠くへ移したり画像を縮めたりしない。
		for offset: Vector2 in [Vector2.ZERO, Vector2(0, 8), Vector2(0, -8), Vector2(8, 0), Vector2(-8, 0), Vector2(8, 8), Vector2(-8, 8), Vector2(8, -8), Vector2(-8, -8)]:
			var pos := center + offset
			if _too_close(pos, placed) or not _crystal_footprint_fits(map, pos, opaque_bounds, occupied_rects):
				continue
			placed.append(pos)
			occupied_rects.append(_sprite_decorations.get_global_transform() * Rect2(pos + opaque_bounds.position, opaque_bounds.size))
			_spawn_single_sprite(frames, pos, sprite_scale)
			spawned += 1
			break
	return spawned

var _crystal_bounds_frames: SpriteFrames
var _crystal_frame_bounds: Array[Rect2] = []
var _crystal_opaque_bounds := Rect2()

## Placement reserves the union of every variant; collision uses the selected visible frame.
## Read each imported image once when the theme changes, never per placement candidate.
func _crystal_bounds(frames: SpriteFrames, sprite_scale: float, frame_index: int = -1) -> Rect2:
	if frames != _crystal_bounds_frames:
		_crystal_bounds_frames = frames
		_crystal_frame_bounds.clear()
		_crystal_opaque_bounds = Rect2()
		for index in frames.get_frame_count("default"):
			var texture := frames.get_frame_texture("default", index)
			var image: Image
			if texture is AtlasTexture:
				image = (texture as AtlasTexture).atlas.get_image().get_region(Rect2i((texture as AtlasTexture).region))
			else:
				image = texture.get_image()
			var used := Rect2(image.get_used_rect())
			var bounds := Rect2(used.position - texture.get_size() * 0.5, used.size)
			_crystal_frame_bounds.append(bounds)
			_crystal_opaque_bounds = bounds if index == 0 else _crystal_opaque_bounds.merge(bounds)
	var bounds := _crystal_frame_bounds[frame_index] if frame_index >= 0 else _crystal_opaque_bounds
	return Rect2(bounds.position * sprite_scale, bounds.size * sprite_scale)

func _crystal_footprint_fits(map: DungeonMap, position: Vector2, bounds: Rect2, occupied_rects: Array[Rect2]) -> bool:
	var footprint := _sprite_decorations.get_global_transform() * Rect2(position + bounds.position, bounds.size)
	var padded := footprint.grow(3.0)
	var first := _tile_map_layer.local_to_map(_tile_map_layer.to_local(padded.position))
	var last := _tile_map_layer.local_to_map(_tile_map_layer.to_local(padded.end - Vector2.ONE * 0.01))
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, y)
			if not map.is_floor(cell) or map.get_meta("exploration_reserved", {}).has(cell) or _is_boss_chamber_cell(map, cell):
				return false
			# Storage/敷居/瓦礫、旗/床柱のTile領域を保守的に予約する。
			if _decoration_layer.get_cell_source_id(cell) != -1 or _wall_overlay_layer.get_cell_source_id(cell) != -1:
				return false
	for occupied in occupied_rects:
		if padded.intersects(occupied):
			return false
	return true

func _spawn_single_sprite(frames: SpriteFrames, world_pos: Vector2, sprite_scale: float) -> void:
	var sprite: AnimatedSprite2D
	if _sprite_decoration_cursor < _sprite_decorations.get_child_count():
		sprite = _sprite_decorations.get_child(_sprite_decoration_cursor) as AnimatedSprite2D
	else:
		sprite = AnimatedSprite2D.new()
		_sprite_decorations.add_child(sprite)
	_sprite_decoration_cursor += 1
	sprite.stop()
	sprite.sprite_frames = frames
	sprite.position = world_pos
	sprite.scale = Vector2(sprite_scale, sprite_scale)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.visible = true
	var frame_count := frames.get_frame_count("default")
	var start_frame := randi() % frame_count
	sprite.frame = start_frame
	var body := sprite.get_node_or_null("PropBody") as StaticBody2D
	if frames == _wall_deco_frames:
		if body == null:
			body = StaticBody2D.new()
			body.name = "PropBody"
			body.collision_mask = 0
			var shape := CollisionShape2D.new()
			shape.name = "Footprint"
			shape.shape = RectangleShape2D.new()
			body.add_child(shape)
			sprite.add_child(body)
		var bounds := _crystal_bounds(frames, 1.0, start_frame)
		var footprint := body.get_node("Footprint") as CollisionShape2D
		(footprint.shape as RectangleShape2D).size = Vector2(bounds.size.x * 0.8, bounds.size.y * 0.55)
		footprint.position = bounds.position + Vector2(bounds.size.x * 0.5, bounds.size.y * 0.725)
		body.collision_layer = WALL_COLLISION_LAYER_BIT
	elif body:
		body.collision_layer = 0
	sprite.speed_scale = randf_range(0.85, 1.15) # 複数の松明が完全同期して揺れないように
	# MAP2/3の4種類の大型小物はアニメのコマではなく形状Variation。
	# 配置時に1枚を選び、松明だけを連続再生する。
	if frame_count > 1 and frames != _wall_deco_frames:
		sprite.play("default")
		sprite.frame = start_frame

func _too_close(pos: Vector2, placed: Array[Vector2]) -> bool:
	for p in placed:
		if p.distance_to(pos) < min_sprite_decoration_spacing:
			return true
	return false

func _refresh_painted_surfaces(map: DungeonMap) -> void:
	var surface := Node2D.new()
	surface.name = "PaintedSurfaces"
	surface.set_script(preload("res://entities/stage_environment/detailed_map_surfaces.gd"))
	add_child(surface)
	surface.configure(map, _tile_map_layer.get_used_cells(), _active_map_theme)
	# Retain TileMap data and collision; replace only its low-density artwork.
	_combat_terrain_layer.hide()
	# Native storage, animated lamps and overlays remain visible at the same 2x pixel scale.
