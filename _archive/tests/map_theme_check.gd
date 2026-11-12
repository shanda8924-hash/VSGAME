extends Node

const STAGE_SCENE := preload("res://entities/stage_environment/stage_environment.tscn")
const MAP_SIZES := {
	1: Vector4i(78, 78, 10, 1),
	2: Vector4i(86, 86, 11, 2),
	3: Vector4i(94, 94, 12, 2),
}
const EXPECTED_ROOTS := {
	1: "res://assets/tiles/royal",
	2: "res://assets/tiles/amethyst_depths",
	3: "res://assets/tiles/ruin_forge",
}

var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var stage := STAGE_SCENE.instantiate() as StageEnvironment
	add_child(stage)
	await get_tree().process_frame
	for map_index in [1, 2, 3]:
		var config: Vector4i = MAP_SIZES[map_index]
		var rng := RandomNumberGenerator.new()
		rng.seed = 91820 + map_index
		var map := DungeonGenerator.generate(config.x, config.y, config.z, config.w, rng)
		GameManager.current_map_index = map_index
		stage.build_dungeon(map)
		var painted := stage.get_node_or_null("PaintedSurfaces")
		_expect(painted != null, "3MAPの新しい描画素材を実経路へ接続")
		if painted != null:
			_expect(painted.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "背景のドットを補間しない")
			_expect(painted.surface_texture.get_size() == Vector2(128,128), "床の16pxサンプル契約")
			_expect(painted.surface_texture.resource_path.ends_with("map%d_floor.png" % map_index), "再生成した素材を実描画へ接続")
			_expect(painted.wall_texture.get_size() == Vector2(128,128), "壁の16pxサンプル契約")
			_expect(painted.cells.size() == stage._tile_map_layer.get_used_cells().size(), "全床壁に新作画を適用")
		var reachability := DungeonGenerator.validate_reachability(map)
		_expect(bool(reachability.get("reachable", false)), "MAP%dの床がすべて到達可能" % map_index)
		var snapshot := stage.debug_get_combat_terrain_snapshot()
		_expect(int(snapshot.get("map_theme", 0)) == map_index, "MAP%d専用テーマが選択される" % map_index)
		_expect(String(snapshot.get("texture_path", "")).begins_with(EXPECTED_ROOTS[map_index]), "MAP%d専用床Atlasを使用" % map_index)
		_expect(String(snapshot.get("terrain_texture_path", "")).begins_with(EXPECTED_ROOTS[map_index]), "MAP%d専用戦闘床Atlasを使用" % map_index)
		var detail_cells := int(snapshot.get("theme_detail_cells", 0))
		_expect(detail_cells > 0 if map_index in [2, 3] else detail_cells == 0, "MAP%dの専用床意匠数が不正" % map_index)
		_expect(int(snapshot.get("macro_floor_source", -1)) == (StageEnvironment.THEME_FLOOR_SOURCE_ID if map_index in [2, 3] else -1), "MAP%dの連続床Sourceが不正" % map_index)
		var expected_wall_variants := 4 if map_index in [2, 3] else 1
		_expect(int(snapshot.get("wall_variant_count", 0)) == expected_wall_variants, "MAP%dの壁Variation契約が不正" % map_index)
		_expect(_count_used_wall_variants(stage, map) >= (3 if map_index in [2, 3] else 1), "MAP%dの壁Variationが実配置されていない" % map_index)
		_expect(stage.get_node_or_null("PaintedProps") == null, "native obstacle sprites remain the actual visible art")
		if map_index in [2, 3]:
			var frames := stage._wall_deco_frames
			var union: Rect2 = stage._crystal_bounds(frames, 1.0)
			var seen := {}
			for index in 4:
				var atlas := frames.get_frame_texture("default", index) as AtlasTexture
				_expect(atlas.atlas.resource_path.ends_with("map%d_props.png" % map_index), "新作画の小物を実描画へ接続")
				var image := atlas.atlas.get_image().get_region(atlas.region)
				seen[hash(image.get_data())] = true
				var expected := Rect2(image.get_used_rect())
				expected.position -= Vector2(image.get_size()) * 0.5
				_expect(stage._crystal_bounds(frames, 1.0, index) == expected, "collision bounds match visible frame")
				_expect(union.encloses(expected), "placement reserves every variant")
			_expect(seen.size() == 4, "all four prop variants are distinct")
		var expected_prop_variants := 4 if map_index in [2, 3] else 1
		_expect(stage._wall_deco_frames.get_frame_count("default") == expected_prop_variants, "MAP%dの固体小物Variation数が不正" % map_index)
		_expect(_has_solid_rendered_wall(stage, map), "MAP%dに表示と衝突を備えた壁がある" % map_index)
		_expect(_all_visible_obstacles_are_solid(stage), "MAP%dの水晶・炉心柱がすべて通り抜け不可" % map_index)
		print("MAP_THEME_CHECK map=%d theme=%s wall_cells=%d obstacle_props=%d" % [
			map_index,
			snapshot.get("texture_path", ""),
			_count_wall_cells(stage, map),
			_count_visible_obstacles(stage),
		])
	stage.queue_free()
	if failures.is_empty():
		print("MAP_THEME_CHECK PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("MAP_THEME_CHECK: " + failure)
		get_tree().quit(1)

func _has_solid_rendered_wall(stage: StageEnvironment, map: DungeonMap) -> bool:
	for cell in stage._tile_map_layer.get_used_cells():
		if map.is_floor(cell):
			continue
		var tile_data := stage._tile_map_layer.get_cell_tile_data(cell)
		if stage._tile_map_layer.get_cell_source_id(cell) == StageEnvironment.WALL_JUNCTION_SOURCE_ID and tile_data != null and tile_data.get_collision_polygons_count(StageEnvironment.WALL_PHYSICS_LAYER) == 1:
			return true
	return false

func _all_visible_obstacles_are_solid(stage: StageEnvironment) -> bool:
	var found := false
	for child in stage._sprite_decorations.get_children():
		var sprite := child as AnimatedSprite2D
		if sprite == null or not sprite.visible or sprite.sprite_frames != stage._wall_deco_frames:
			continue
		found = true
		var body := sprite.get_node_or_null("PropBody") as StaticBody2D
		var shape := body.get_node_or_null("Footprint") as CollisionShape2D if body != null else null
		if body == null or body.collision_layer != StageEnvironment.WALL_COLLISION_LAYER_BIT or shape == null or shape.shape == null:
			return false
	return found

func _count_wall_cells(stage: StageEnvironment, map: DungeonMap) -> int:
	var count := 0
	for cell in stage._tile_map_layer.get_used_cells():
		if not map.is_floor(cell):
			count += 1
	return count

func _count_used_wall_variants(stage: StageEnvironment, map: DungeonMap) -> int:
	var variants: Dictionary = {}
	for cell in stage._tile_map_layer.get_used_cells():
		if map.is_floor(cell) or stage._tile_map_layer.get_cell_source_id(cell) != StageEnvironment.WALL_JUNCTION_SOURCE_ID:
			continue
		var coords := stage._tile_map_layer.get_cell_atlas_coords(cell)
		variants[coords.x % 4 if int(GameManager.current_map_index) in [2, 3] else 0] = true
	return variants.size()

func _count_visible_obstacles(stage: StageEnvironment) -> int:
	var count := 0
	for child in stage._sprite_decorations.get_children():
		var sprite := child as AnimatedSprite2D
		if sprite != null and sprite.visible and sprite.sprite_frames == stage._wall_deco_frames:
			count += 1
	return count

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
