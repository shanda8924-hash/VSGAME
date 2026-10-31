extends Node
## 地形構造・到達性・Hazard撤去・透明壁装飾・柱Collisionを実Game Runtimeで確認する。
## `-- --map-terrain-rhythm-check`からのみ起動する。

const MAP_SIZES := [
	Vector4i(78, 78, 10, 1),
	Vector4i(86, 86, 11, 2),
	Vector4i(94, 94, 12, 2),
]
const EXPECTED_COMBAT_TEXTURE := "res://assets/tiles/royal/combat_atlas.png"
const PILLAR_OFFSETS := [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]
const RETIRED_WALL_COLUMNS := [Vector2i(20, 0), Vector2i(20, 1), Vector2i(13, 0), Vector2i(13, 1)]

var failures: Array[String] = []
var player: Player
var stage_environment: StageEnvironment
var wave_spawner: WaveSpawner
var _wall_boundary_cells_checked := 0

func _ready() -> void:
	SaveManager.begin_ephemeral_session()
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = get_parent().get_node("Player") as Player
	stage_environment = get_parent().get_node("StageEnvironment") as StageEnvironment
	wave_spawner = get_parent().get_node("WaveSpawner") as WaveSpawner
	_run.call_deferred()

func _run() -> void:
	await _wait_frames(12)
	_test_seeded_reachability()
	_test_runtime_render_connection()
	await _test_hazard_runtime()
	await _test_pillar_collision_runtime()
	if failures.is_empty():
		_finish(0, "MAP_TERRAIN_RHYTHM_CHECK: PASS")
	else:
		for failure in failures:
			push_error("MAP_TERRAIN_RHYTHM_CHECK: %s" % failure)
		_finish(1, "")

func _test_seeded_reachability() -> void:
	var generated := 0
	var minimum_obstacles := 999999
	var minimum_pillars := 999999
	var visual_probe := preload("res://entities/stage_environment/stage_environment.tscn").instantiate() as StageEnvironment
	add_child(visual_probe)
	visual_probe.hide()
	_test_wall_edge_masks(visual_probe)
	for map_size in MAP_SIZES:
		for seed_value in range(12):
			var rng := RandomNumberGenerator.new()
			rng.seed = 1000 + generated * 97 + seed_value
			var map := DungeonGenerator.generate(map_size.x, map_size.y, map_size.z, map_size.w, rng)
			var reachability := DungeonGenerator.validate_reachability(map)
			var counts := map.get_combat_region_counts()
			_expect(bool(reachability.get("reachable", false)), "seed=%dで到達不能床=%d" % [rng.seed, (reachability.get("unreachable_cells", []) as Array).size()])
			for region_type in DungeonMap.COMBAT_REGION_TYPES:
				_expect(int(counts.get(region_type, 0)) >= 1, "seed=%dに%s領域がありません" % [rng.seed, region_type])
			_expect(map.hazard_regions.is_empty(), "seed=%dに撤去済みHazard矩形があります" % rng.seed)
			var anchors := _pillar_anchors(map)
			_expect(not anchors.is_empty(), "seed=%dに2x2柱がありません" % rng.seed)
			_expect(_pillar_obstacle_count(map) == anchors.size() * 4, "seed=%dの柱が2x2単位ではありません" % rng.seed)
			_expect(_pillar_spacing_is_safe(anchors), "seed=%dの柱間隔が3セル未満です" % rng.seed)
			var floor_before := map.get_floor_cells().duplicate()
			var obstacles_before := map.terrain_obstacle_cells.duplicate()
			visual_probe.build_dungeon(map)
			_test_wall_decorations(map, visual_probe)
			_expect(map.get_floor_cells() == floor_before and map.terrain_obstacle_cells == obstacles_before, "装飾の生成が床/物理障害物を変更しました")
			minimum_obstacles = mini(minimum_obstacles, map.terrain_obstacle_cells.size())
			minimum_pillars = mini(minimum_pillars, anchors.size())
			generated += 1
	visual_probe.free()
	print("MAP_TERRAIN_REACHABILITY generated=%d minimum_obstacles=%d minimum_pillars=%d" % [generated, minimum_obstacles, minimum_pillars])
	print("MAP_WALL_DECORATIONS seeded_maps=%d retired_wall_columns=0 wall_hangings=front_faces_only" % generated)
	print("MAP_WALL_BOUNDARIES seeded_maps=%d checked_cells=%d mask_variants=256 material=original_relief collision=unchanged" % [generated, _wall_boundary_cells_checked])

func _test_runtime_render_connection() -> void:
	var map := GameManager.dungeon_map
	var reachability := DungeonGenerator.validate_reachability(map)
	var terrain := stage_environment.debug_get_combat_terrain_snapshot()
	_expect(bool(reachability.get("reachable", false)), "実Runtime MAPが全床到達可能ではありません")
	_expect(int(terrain.get("rendered_cells", 0)) > 0, "戦闘地形TileがRuntimeへ描画接続されていません")
	_expect(int(terrain.get("physics_layer", 0)) == 1, "柱/壁Collisionがlayer=1ではありません")
	_expect(ResourceLoader.exists(String(terrain.get("texture_path", ""))), "Retro TileSetがimportされていません")
	_expect(ResourceLoader.exists(String(terrain.get("terrain_texture_path", ""))), "戦闘地形TileSetがimportされていません")
	_expect(String(terrain.get("terrain_texture_path", "")) == EXPECTED_COMBAT_TEXTURE, "CombatTerrainが新8x6 Atlasを参照していません")
	var combat_texture := load(EXPECTED_COMBAT_TEXTURE) as Texture2D
	_expect(combat_texture != null and combat_texture.get_size() == Vector2(128, 96), "CombatTerrain Atlasが128x96ではありません")
	var wall_texture := load(StageEnvironment.WALL_JUNCTION_TEXTURE_PATH) as Texture2D
	_expect(wall_texture != null and wall_texture.get_size() == Vector2(256, 256), "立体壁Atlasが256x256ではありません")
	var wall_source := stage_environment._tile_set.get_source(StageEnvironment.WALL_JUNCTION_SOURCE_ID) as TileSetAtlasSource
	_expect(wall_source != null and wall_source.texture == wall_texture, "生成された壁境界画像が実Runtime TileSetへ接続されていません")
	_test_runtime_floor_variants(map)
	_test_runtime_pillar_tiles_and_collision(map)
	_test_wall_decorations(map, stage_environment)
	print("MAP_TERRAIN_RUNTIME rendered_cells=%d floor_cells=%d obstacles=%d regions=%s" % [
		int(terrain.get("rendered_cells", 0)), map.get_floor_cells().size(), map.terrain_obstacle_cells.size(), map.get_combat_region_counts(),
	])

func _test_wall_decorations(map: DungeonMap, environment: StageEnvironment) -> void:
	_test_wall_boundaries(map, environment)
	for cell in environment._tile_map_layer.get_used_cells():
		var coords := environment._tile_map_layer.get_cell_atlas_coords(cell)
		_expect(coords not in RETIRED_WALL_COLUMNS, "壁内部/voidへ装飾柱が再配置されました: %s" % cell)
		_expect(environment._tile_map_layer.get_cell_source_id(cell) != StageEnvironment.WALL_OVERLAY_SOURCE_ID, "装飾が壁本体を上書きしました")
	var overlays := environment.get_node("WallOverlayTileMapLayer") as TileMapLayer
	for cell in overlays.get_used_cells():
		var coords := overlays.get_cell_atlas_coords(cell)
		var tile := overlays.get_cell_tile_data(cell)
		_expect(tile != null and tile.get_collision_polygons_count(0) == 0, "透過装飾が追加Collisionを持っています")
		if coords.y >= 2: # 物理柱の4分割は別途検証。
			continue
		var base_cell := cell + Vector2i.DOWN if coords.y == 0 and coords.x <= 3 else cell
		_expect(not map.is_floor(base_cell) and not map.is_terrain_obstacle(base_cell) and map.is_floor(base_cell + Vector2i.DOWN), "旗/格子の基部が正面壁以外です: %s" % cell)
		var base := environment._tile_map_layer.get_cell_tile_data(cell)
		_expect(base != null and base.get_collision_polygons_count(0) == 1, "装飾の下地壁に穴が開きました: %s" % cell)
	for sprite_variant in environment._sprite_decorations.get_children():
		var sprite := sprite_variant as AnimatedSprite2D
		if sprite == null or not sprite.visible or sprite.sprite_frames != environment._torch_frames_a:
			continue
		var cell := map.world_to_grid(sprite.position)
		_expect(not map.is_floor(cell) and not map.is_terrain_obstacle(cell) and map.is_floor(cell + Vector2i.DOWN), "松明が正面壁以外にあります: %s" % cell)
	for cell in environment._decoration_layer.get_used_cells():
		if environment._decoration_layer.get_cell_atlas_coords(cell) == environment.step_atlas_coords:
			_expect(map.is_floor(cell), "入口の敷居が通行不能壁にあります: %s" % cell)

func _test_wall_edge_masks(environment: StageEnvironment) -> void:
	# 8近傍の全256組合せ。正面・背面・側面・内外角を同じ材質で描く。
	var offsets := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i(-1, -1), Vector2i(1, -1), Vector2i.ONE, Vector2i(-1, 1)]
	for mask in range(256):
		var map := DungeonMap.new(9, 9)
		for index in offsets.size():
			if mask & (1 << index):
				map.set_floor(offsets[index], true)
		_expect(environment._wall_neighbor_mask(map, Vector2i.ZERO) == mask, "壁の8近傍Maskが不正です: %d" % mask)
		environment._set_wall_cell(map, Vector2i.ZERO, {Vector2i.ZERO: 1})
		_expect(environment._tile_map_layer.get_cell_source_id(Vector2i.ZERO) == StageEnvironment.WALL_JUNCTION_SOURCE_ID, "壁の材質Sourceが不正です")
		_expect(environment._tile_map_layer.get_cell_atlas_coords(Vector2i.ZERO) == Vector2i(mask & 15, mask >> 4), "壁の8近傍画像が不正です")

func _test_wall_boundaries(map: DungeonMap, environment: StageEnvironment) -> void:
	for cell in environment._tile_map_layer.get_used_cells():
		if map.is_floor(cell) or (map.is_terrain_obstacle(cell) and map.get_combat_region_type(cell) == DungeonMap.REGION_PILLAR_FIELD):
			continue
		var mask := environment._wall_neighbor_mask(map, cell)
		var actual_source := environment._tile_map_layer.get_cell_source_id(cell)
		_expect(actual_source == StageEnvironment.WALL_JUNCTION_SOURCE_ID, "普通壁に異なる素材が混入しています: %s" % cell)
		_expect(environment._tile_map_layer.get_cell_atlas_coords(cell) == Vector2i(mask & 15, mask >> 4), "壁の向きと画像が不一致: %s" % cell)
		_wall_boundary_cells_checked += 1
		var tile_data := environment._tile_map_layer.get_cell_tile_data(cell)
		_expect(tile_data != null and tile_data.modulate == Color.WHITE, "距離による暗色帯が残っています: %s" % cell)
		_expect(tile_data != null and tile_data.get_collision_polygons_count(StageEnvironment.WALL_PHYSICS_LAYER) == 1, "壁境界のCollisionがありません: %s" % cell)
		if tile_data != null and tile_data.get_collision_polygons_count(StageEnvironment.WALL_PHYSICS_LAYER) == 1:
			_expect(tile_data.get_collision_polygon_points(StageEnvironment.WALL_PHYSICS_LAYER, 0) == PackedVector2Array([Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)]), "壁境界が元の16px矩形Collisionから変わりました: %s" % cell)

func _test_hazard_runtime() -> void:
	_expect(GameManager.dungeon_map.hazard_regions.is_empty(), "通常MAPに撤去済みHazard矩形が残っています")
	_expect(get_tree().get_nodes_in_group("map_hazard").is_empty(), "通常MAPに継続Damage Areaが残っています")
	await _wait_frames(4)
	_expect(get_tree().get_nodes_in_group("map_hazard").is_empty(), "遅延生成で撤去済みHazardが復活しました")

func _test_pillar_collision_runtime() -> void:
	var map := GameManager.dungeon_map
	var probe := _find_pillar_chase_probe(map)
	_expect(not probe.is_empty(), "追跡Collision確認に使える柱がありません")
	if probe.is_empty():
		return
	var pillar_anchor: Vector2i = probe["anchor"]
	var enemy_cell: Vector2i = probe["enemy_cell"]
	var target_cell: Vector2i = probe["target_cell"]
	for enemy_variant in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy_variant):
			(enemy_variant as Node).queue_free()
	await _wait_frames(3)
	var enemy := wave_spawner.enemy_scene.instantiate() as EnemyBasic
	enemy.enemy_data = wave_spawner.enemy_data_list[0]
	enemy.position = map.grid_to_world(enemy_cell)
	player.global_position = map.grid_to_world(target_cell)
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	GameManager.get_runtime_world(self).add_child(enemy)
	var start_distance := enemy.global_position.distance_to(player.global_position)
	# 描画FPSに依存するprocess_frameではなく、追跡/Collisionと同じ物理tickを固定数進める。
	await _wait_physics_frames(120)
	var end_distance := enemy.global_position.distance_to(player.global_position) if is_instance_valid(enemy) else INF
	_expect(is_instance_valid(enemy), "柱回避確認中にEnemyが消えました")
	if is_instance_valid(enemy):
		_expect(map.world_to_grid(enemy.global_position) not in _pillar_footprint(pillar_anchor), "Enemyが2x2柱Collisionを通過しました")
		_expect(end_distance < start_distance - 24.0, "Enemyが柱に停止して追跡を継続できません: %.1f→%.1f" % [start_distance, end_distance])
		enemy.queue_free()
	player.weapon_manager.process_mode = Node.PROCESS_MODE_INHERIT
	player.global_position = map.grid_to_world(map.spawn_point)
	print("MAP_PILLAR_CHASE start_distance=%.1f end_distance=%.1f anchor=%s" % [start_distance, end_distance, pillar_anchor])

func _test_runtime_floor_variants(map: DungeonMap) -> void:
	var expected := {
		DungeonMap.REGION_ARENA: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
		DungeonMap.REGION_PILLAR_FIELD: [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)],
		DungeonMap.REGION_CHOKEPOINT: [Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1), Vector2i(7, 1)],
	}
	for region_type_variant in expected.keys():
		var region_type := String(region_type_variant)
		var used := {}
		for cell in map.get_combat_region_cells():
			if map.get_combat_region_type(cell) == region_type and map.is_floor(cell):
				var actual := stage_environment._combat_terrain_layer.get_cell_atlas_coords(cell)
				used[actual] = true
		for coords in expected[region_type]:
			_expect(used.has(coords), "%s床で4変種の%sが使われていません" % [region_type, coords])

func _test_runtime_pillar_tiles_and_collision(map: DungeonMap) -> void:
	var overlays := stage_environment.get_node("WallOverlayTileMapLayer") as TileMapLayer
	for anchor in _pillar_anchors(map):
		var top_left := overlays.get_cell_atlas_coords(anchor)
		_expect(top_left == Vector2i(0, 2) or top_left == Vector2i(2, 2), "透過柱左上がA/Bの2x2起点ではありません: %s" % top_left)
		for offset in PILLAR_OFFSETS:
			var expected_coords: Vector2i = top_left + offset
			var actual_coords: Vector2i = overlays.get_cell_atlas_coords(anchor + offset)
			_expect(actual_coords == expected_coords and overlays.get_cell_source_id(anchor + offset) == StageEnvironment.WALL_OVERLAY_SOURCE_ID, "透過柱2x2の分割座標が不正です: %s expected=%s actual=%s" % [anchor + offset, expected_coords, actual_coords])
			var base_tile := stage_environment._tile_map_layer.get_cell_tile_data(anchor + offset)
			_expect(stage_environment._tile_map_layer.get_cell_alternative_tile(anchor + offset) == StageEnvironment.FLOOR_ALT_BLOCKER, "柱下地が床模様付きBlockerではありません")
			_expect(base_tile != null and base_tile.get_collision_polygons_count(StageEnvironment.WALL_PHYSICS_LAYER) == 1, "柱の4セル全てに元のCollisionがありません: %s" % [anchor + offset])

func _pillar_anchors(map: DungeonMap) -> Array[Vector2i]:
	var anchors: Array[Vector2i] = []
	for cell_variant in map.terrain_obstacle_cells.keys():
		var cell: Vector2i = cell_variant
		if map.get_combat_region_type(cell) != DungeonMap.REGION_PILLAR_FIELD:
			continue
		if map.is_terrain_obstacle(cell + Vector2i.LEFT) or map.is_terrain_obstacle(cell + Vector2i.UP):
			continue
		if map.is_terrain_obstacle(cell + Vector2i.RIGHT) and map.is_terrain_obstacle(cell + Vector2i.DOWN) and map.is_terrain_obstacle(cell + Vector2i.ONE):
			anchors.append(cell)
	return anchors

func _pillar_footprint(anchor: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset in PILLAR_OFFSETS:
		cells.append(anchor + offset)
	return cells

func _find_pillar_chase_probe(map: DungeonMap) -> Dictionary:
	# 2x2柱の斜め両側を結ぶ。外周1セルに寄った柱でも、部屋内側の2方向を使える。
	var offset_pairs := [
		[Vector2i(0, 3), Vector2i(3, 0)],
		[Vector2i(1, 3), Vector2i(-2, 1)],
		[Vector2i(1, -2), Vector2i(3, 1)],
		[Vector2i(-2, 0), Vector2i(0, 3)],
	]
	for anchor in _pillar_anchors(map):
		for pair in offset_pairs:
			var enemy_cell: Vector2i = anchor + pair[0]
			var target_cell: Vector2i = anchor + pair[1]
			if map.is_floor(enemy_cell) and map.is_floor(target_cell):
				return {"anchor": anchor, "enemy_cell": enemy_cell, "target_cell": target_cell}
	return {}

func _pillar_obstacle_count(map: DungeonMap) -> int:
	var count := 0
	for cell_variant in map.terrain_obstacle_cells.keys():
		if map.get_combat_region_type(cell_variant as Vector2i) == DungeonMap.REGION_PILLAR_FIELD:
			count += 1
	return count

func _pillar_spacing_is_safe(anchors: Array[Vector2i]) -> bool:
	for first_index in anchors.size():
		for second_index in range(first_index + 1, anchors.size()):
			var delta := anchors[first_index] - anchors[second_index]
			if absi(delta.x) < 5 and absi(delta.y) < 5:
				return false
	return true

func _wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame

func _wait_physics_frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish(exit_code: int, message: String) -> void:
	var cleanup := preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	cleanup.begin(exit_code, message)
