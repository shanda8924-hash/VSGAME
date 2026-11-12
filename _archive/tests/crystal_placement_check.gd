extends Node2D
## Independent alpha-pixel QA against the rendered TileMap, not the placement helper.
const GAME := preload("res://scenes/game.tscn")
const OUTPUT := "res://artifacts/crystal_placement"
const MAP_SIZES := [Vector4i(78, 78, 10, 1), Vector4i(86, 86, 11, 2), Vector4i(94, 94, 12, 2)]
var game: Node2D
var stage: StageEnvironment
var player: Player
var failures := 0
var crystal_pixels: Array[Vector2i] = []
var texture_images := {}
var tested_maps := 0
var crystal_count := 0
var min_per_map := 100000
var floor_overlaps := 0
var prop_overlaps := 0
var padding_failures := 0
var _phase := "boot"

func _ready() -> void:
	SaveManager.begin_ephemeral_session()
	get_tree().create_timer(150.0, true, false, true).timeout.connect(func():
		push_error("CRYSTAL_PLACEMENT_CHECK timeout: " + _phase)
		get_tree().quit(1)
	)
	_run.call_deferred()

func _exit_tree() -> void:
	SaveManager.end_ephemeral_session()

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	game = GAME.instantiate() as Node2D
	game.tree_entered.connect(func(): get_tree().current_scene = game)
	get_tree().root.add_child(game)
	var controller := game.get_node("MapRunController") as MapRunController
	while not controller._active: await get_tree().process_frame
	stage = game.get_node("StageEnvironment") as StageEnvironment
	player = game.get_node("Player") as Player
	player.health_component.invincible = true
	player.set_movement_locked(true)
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	for name in ["MapRunController", "WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		game.get_node(name).process_mode = Node.PROCESS_MODE_DISABLED
	for enemy in get_tree().get_nodes_in_group("enemies"): enemy.queue_free()
	await _frames(3)
	_check(stage._tile_set != null, "real game Stage has a valid TileSet")
	if stage._tile_set == null:
		get_tree().quit(1)
		return
	var image := Image.load_from_file(ProjectSettings.globalize_path(StageEnvironment.WALL_DECO_PATH))
	_check(image.get_size() == Vector2i(24, 24), "unchanged 24x24 crystal source")
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0: crystal_pixels.append(Vector2i(x, y))
	_check(crystal_pixels.size() == 223, "all 223 nontransparent source pixels are audited")
	for source_id in [0, StageEnvironment.WALL_OVERLAY_SOURCE_ID]:
		var source := stage._tile_set.get_source(source_id) as TileSetAtlasSource
		texture_images[source_id] = source.texture.get_image()
	_phase = "normal game screenshots"
	_audit_layout(GameManager.dungeon_map, false)
	await _capture_field("main_field")
	# Subsequent layouts are generation fixtures, not the initial MAP's content positions.
	for content in get_tree().get_nodes_in_group("map_content"):
		if content is CanvasItem: content.hide()
	for size_index in MAP_SIZES.size():
		var config: Vector4i = MAP_SIZES[size_index]
		for seed_index in range(12):
			_phase = "MAP%d seed%d" % [size_index + 1, seed_index]
			var rng := RandomNumberGenerator.new()
			rng.seed = 91100 + size_index * 100 + seed_index
			var map := DungeonGenerator.generate(config.x, config.y, config.z, config.w, rng)
			var floors := map.get_floor_cells()
			var obstacles := map.terrain_obstacle_cells.duplicate()
			var decoration_seed := 65100 + size_index * 100 + seed_index
			seed(decoration_seed)
			stage.build_dungeon(map)
			var snapshot := _snapshot()
			var children := stage._sprite_decorations.get_child_count()
			_audit_layout(map, true)
			seed(decoration_seed)
			await stage.build_dungeon_async(map, 12)
			_check(_snapshot() == snapshot, "%s sync/async sprite placement matches" % _phase)
			_check(stage._sprite_decorations.get_child_count() == children, "%s rebuild reuses all pooled sprites" % _phase)
			_audit_layout(map, false)
			_check(map.get_floor_cells() == floors and map.terrain_obstacle_cells == obstacles, "%s placement does not modify terrain" % _phase)
			if seed_index == 0:
				GameManager.dungeon_map = map
				player.setup_camera_limits(map)
				await _capture_field("generated_map%d" % (size_index + 1))
	_phase = "small fixture and transformed Stage"
	await _check_small_and_transformed_maps()
	_check(crystal_count > 0 and min_per_map > 0, "safety retains crystals instead of removing the feature")
	_check(SaveManager.is_ephemeral_session_active(), "normal save remains isolated")
	print("CRYSTAL_PLACEMENT_CHECK failures=%d maps=%d sync_async_pairs=%d crystals=%d previous_target=540 min_per_map=%d floor_overlaps=%d prop_overlaps=%d padding_failures=%d alpha_pixels_per_sprite=%d" % [failures, tested_maps, tested_maps, crystal_count, min_per_map, floor_overlaps, prop_overlaps, padding_failures, crystal_pixels.size()])
	get_tree().quit(0 if failures == 0 else 1)

func _audit_layout(map: DungeonMap, count_map: bool) -> void:
	var count := 0
	for child in stage._sprite_decorations.get_children():
		var sprite := child as AnimatedSprite2D
		if not sprite.visible:
			_check(not sprite.is_playing(), "hidden pooled decoration remains stopped")
			continue
		if sprite.sprite_frames != stage._wall_deco_frames: continue
		count += 1
		_check(sprite.scale == Vector2(2, 2) and not sprite.is_playing(), "crystal size/static animation unchanged")
		var on_floor := true
		var props_clear := true
		var padding_clear := true
		for pixel in crystal_pixels:
			var rect := sprite.get_global_transform() * Rect2(Vector2(pixel) - Vector2(12, 12), Vector2.ONE)
			if not _only_rendered_floor(map, rect): on_floor = false
			if not _only_rendered_floor(map, rect.grow(3.0)): padding_clear = false
			var point := rect.get_center()
			if _tile_prop_at_point(stage._decoration_layer, point) or _tile_prop_at_point(stage._wall_overlay_layer, point): props_clear = false
			for other in stage._sprite_decorations.get_children():
				if other == sprite or not other.visible: continue
				if _sprite_at_point(other as AnimatedSprite2D, point): props_clear = false
		if not on_floor: floor_overlaps += 1
		if not props_clear: prop_overlaps += 1
		if not padding_clear: padding_failures += 1
		_check(on_floor, "%s crystal alpha intersects wall/void/pillar at %s" % [_phase, sprite.position])
		_check(props_clear, "%s crystal alpha intersects storage/overlay/other prop at %s" % [_phase, sprite.position])
		_check(padding_clear, "%s crystal has less than 3 world pixels of wall/pillar clearance" % _phase)
	if count_map:
		tested_maps += 1
		crystal_count += count
		min_per_map = mini(min_per_map, count)
		print("CRYSTAL_MAP %s count=%d pool=%d" % [_phase, count, stage._sprite_decorations.get_child_count()])

func _only_rendered_floor(map: DungeonMap, rect: Rect2) -> bool:
	# TileMap transforms and exclusive endpoints are independent of DungeonMap.round().
	var first := stage._tile_map_layer.local_to_map(stage._tile_map_layer.to_local(rect.position))
	var last := stage._tile_map_layer.local_to_map(stage._tile_map_layer.to_local(rect.end - Vector2.ONE * 0.001))
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, y)
			if not map.is_floor(cell) or stage._tile_map_layer.get_cell_source_id(cell) != 0 or stage._tile_map_layer.get_cell_alternative_tile(cell) == StageEnvironment.FLOOR_ALT_BLOCKER:
				return false
	return true

func _tile_prop_at_point(layer: TileMapLayer, global_point: Vector2) -> bool:
	var local := layer.to_local(global_point)
	var cell := layer.local_to_map(local)
	var source_id := layer.get_cell_source_id(cell)
	if source_id == -1: return false
	var tile_data := layer.get_cell_tile_data(cell)
	var pixel := local - layer.map_to_local(cell) + Vector2(8, 8) - Vector2(tile_data.texture_origin)
	var uv := Vector2i(floori(pixel.x), floori(pixel.y))
	if not Rect2i(0, 0, 16, 16).has_point(uv): return false
	var atlas := layer.get_cell_atlas_coords(cell)
	var image: Image = texture_images.get(source_id)
	return image != null and image.get_pixelv(atlas * 16 + uv).a > 0.0

func _sprite_at_point(sprite: AnimatedSprite2D, global_point: Vector2) -> bool:
	# Full frame bounds are a conservative visual reservation, independent of center spacing.
	var size := sprite.sprite_frames.get_frame_texture("default", 0).get_size()
	var origin := sprite.offset - size * 0.5 if sprite.centered else sprite.offset
	return Rect2(origin, size).has_point(sprite.to_local(global_point))

func _snapshot() -> Array:
	var values := []
	for child in stage._sprite_decorations.get_children():
		var sprite := child as AnimatedSprite2D
		if sprite.visible:
			values.append([sprite.sprite_frames == stage._wall_deco_frames, sprite.position, sprite.scale, sprite.speed_scale])
	return values

func _check_small_and_transformed_maps() -> void:
	var map := DungeonMap.new(28, 28)
	for y in range(-8, 9):
		for x in range(-8, 9): map.set_floor(Vector2i(x, y), true)
	var original_position := stage.position
	stage.position = Vector2(113, -77)
	seed(4811)
	stage.build_dungeon(map)
	_audit_layout(map, false)
	_check(stage._sprite_decoration_cursor > 0, "translated Stage retains correctly aligned crystals")
	var children := stage._sprite_decorations.get_child_count()
	var thin := DungeonMap.new(16, 16)
	for x in range(-6, 6): thin.set_floor(Vector2i(x, 0), true)
	stage.build_dungeon(thin)
	_check(stage._sprite_decoration_cursor == 0, "one-cell strip safely skips oversized crystals without fallback")
	_check(stage._sprite_decorations.get_child_count() == children, "tiny rebuild never grows sprite pool")
	for child in stage._sprite_decorations.get_children():
		_check(not child.visible and not child.is_playing(), "tiny map retires old pooled sprites")
	stage.position = original_position
	await _frames(2)
	print("CRYSTAL_POOL translated_map=pass thin_map=skip hidden_pool_stopped=true")

func _capture_field(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var target: AnimatedSprite2D
	for child in stage._sprite_decorations.get_children():
		if child.visible and child.sprite_frames == stage._wall_deco_frames:
			target = child
			break
	_check(target != null, name + " has a crystal to inspect")
	if target == null: return
	var safe_position := GameManager.dungeon_map.find_spawn_position_near(target.global_position + Vector2(0, 80))
	_check(safe_position.is_finite(), name + " has a safe player viewing position")
	if not safe_position.is_finite(): return
	player.global_position = safe_position
	player.camera.position_smoothing_enabled = false
	player.camera.reset_smoothing()
	player.camera.force_update_scroll()
	await _frames(3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT + "/" + name + ".png")
	print("CRYSTAL_CAPTURE %s position=%s" % [name, target.global_position])

func _frames(count: int) -> void:
	for _index in count: await get_tree().process_frame

func _check(ok: bool, message: String) -> void:
	if ok: return
	failures += 1
	if failures <= 24: push_error("CRYSTAL_PLACEMENT_CHECK: " + message)
