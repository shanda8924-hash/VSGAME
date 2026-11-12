extends Node2D
## Original raised wall faces, edited corner seams, fixed-camera flames and pooled rebuilds.

const GAME := preload("res://scenes/game.tscn")
const STAGE := preload("res://entities/stage_environment/stage_environment.tscn")
const OUTPUT_DIR := "res://artifacts/wall_material_animation"
const FRAME_SIZE := Vector2i(16, 24)
const BRACKET_RECT := Rect2i(0, 12, 16, 12)
const ORIGINAL_WALL_ATLAS := "res://assets/tiles/royal/dungeon_atlas.png"
const ORIGINAL_WALL_EDGES := "res://assets/tiles/royal/wall_edges.png"
var game: Node2D
var environment: StageEnvironment
var player: Player
var failures := 0
var changed_render_pixels := 0
var _stage := "boot"

func _ready() -> void:
	SaveManager.begin_ephemeral_session()
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(80.0, true, false, true).timeout.connect(func():
		push_error("WALL_MATERIAL_ANIMATION_CHECK timeout: " + _stage)
		get_tree().quit(1)
	)
	_run.call_deferred()

func _exit_tree() -> void:
	SaveManager.end_ephemeral_session()

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	game = GAME.instantiate() as Node2D
	game.tree_entered.connect(func(): get_tree().current_scene = game)
	get_tree().root.add_child(game)
	player = game.get_node("Player") as Player
	environment = game.get_node("StageEnvironment") as StageEnvironment
	var controller := game.get_node("MapRunController") as MapRunController
	var deadline := Time.get_ticks_msec() + 20000
	while not controller._active and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(controller._active and GameManager.map_mode_active, "actual game.tscn starts a normal MAP")
	if not controller._active:
		get_tree().quit(1)
		return
	player.health_component.invincible = true
	player.set_movement_locked(true)
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	for name in ["WaveSpawner", "BossSpawner", "EliteRoomManager", "MapRunController"]:
		game.get_node(name).process_mode = Node.PROCESS_MODE_DISABLED
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await _frames(4)
	_stage = "source material and animation"
	_check_material_contract()
	_check_torch_frames()
	_stage = "same-position main field animation"
	await _check_rendered_torch()
	_stage = "pooled MAP rebuilds"
	await _check_pool_rebuilds()
	_stage = "fixed inner-L fixture"
	await _capture_inner_fixture()
	_check(SaveManager.is_ephemeral_session_active(), "normal save remains protected")
	print("WALL_MATERIAL_ANIMATION_CHECK failures=%d relief_masks=256 original_faces=2 bright_vertical_width=3 mirrored_inner_returns=2 torch_frames=6 fixed_samples=4 render_changed_pixels=%d rebuilds=6 renderer=%s" % [failures, changed_render_pixels, RenderingServer.get_current_rendering_method()])
	get_tree().quit(0 if failures == 0 else 1)

func _check_material_contract() -> void:
	var atlas := environment._tile_set.get_source(StageEnvironment.WALL_JUNCTION_SOURCE_ID) as TileSetAtlasSource
	_check(atlas != null and atlas.get_tiles_count() == 256, "all walls use the 256-mask raised-wall atlas")
	if atlas == null:
		return
	_check(atlas.texture.resource_path == "res://assets/tiles/royal/wall_relief.png", "actual game uses the restored raised-wall asset")
	_check(atlas.texture.get_size() == Vector2(256, 256), "raised-wall atlas is 256x256")
	var image := atlas.texture.get_image()
	var original := Image.load_from_file(ProjectSettings.globalize_path(ORIGINAL_WALL_ATLAS))
	var edges := Image.load_from_file(ProjectSettings.globalize_path(ORIGINAL_WALL_EDGES))
	var body := original.get_region(Rect2i(112, 48, 16, 16))
	var front := original.get_region(Rect2i(144, 48, 16, 16))
	_check(_changed_pixels(_wall_tile(image, 0), body) == 0, "unexposed body keeps the entire original dark upper surface")
	_check(_changed_pixels(_wall_tile(image, 4), front) == 0, "straight front keeps the entire original bright facade and coping")
	for mask in range(256):
		var data := atlas.get_tile_data(Vector2i(mask & 15, mask >> 4), 0)
		_check(data.modulate == Color.WHITE, "mask %d has no direction/distance tint" % mask)
		_check(data.get_collision_polygons_count(0) == 1, "mask %d keeps wall collision" % mask)
		var tile := _wall_tile(image, mask)
		var reference := front if mask & 4 else body
		_check(_changed_pixels(tile.get_region(Rect2i(4, 4, 8, 8)), reference.get_region(Rect2i(4, 4, 8, 8))) == 0, "mask %d preserves its original facade or upper-surface center" % mask)
		if mask & 4:
			_check(_changed_pixels(tile.get_region(Rect2i(4, 0, 8, 16)), front.get_region(Rect2i(4, 0, 8, 16))) == 0, "mask %d preserves full facade height and gold coping" % mask)
	var body_luma := _mean_luma(body)
	var front_luma := _mean_luma(front)
	_check(front_luma > body_luma * 1.5, "original bright facade remains visually distinct from dark upper surface")
	_check_relief_seams(image, body, front, edges)
	print("WALL_RELIEF_PIXELS original_body_exact=true original_front_exact=true centers_preserved=256 body_luma=%.2f front_luma=%.2f" % [body_luma, front_luma])

func _wall_tile(image: Image, mask: int) -> Image:
	return image.get_region(Rect2i((mask & 15) * 16, (mask >> 4) * 16, 16, 16))

func _mean_luma(image: Image) -> float:
	var total := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			total += color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
	return total * 255.0 / float(image.get_width() * image.get_height())

func _is_gold(color: Color) -> bool:
	return color.r > color.b * 1.6 and color.g > color.b * 1.3 and color.r > 90.0 / 255.0

func _check_relief_seams(image: Image, body: Image, front: Image, edges: Image) -> void:
	var bright_left := edges.get_region(Rect2i(32, 0, 3, 16))
	var bright_right := bright_left.duplicate() as Image
	bright_right.flip_x()
	_check(_changed_pixels(_wall_tile(image, 8).get_region(Rect2i(0, 0, 3, 16)), bright_left) == 0, "west wall uses the existing bright three-pixel side unchanged")
	_check(_changed_pixels(_wall_tile(image, 2).get_region(Rect2i(13, 0, 3, 16)), bright_right) == 0, "east wall is the exact horizontal mirror of the same bright side")
	var side_checks := 0
	for mask in range(256):
		var tile := _wall_tile(image, mask)
		for left in [true, false]:
			var side_bit := 8 if left else 2
			var corner_bit := 128 if left else 64
			if not (mask & side_bit) and not (not (mask & 4) and (mask & corner_bit)):
				continue
			var start := 0 if left else 13
			var canonical := bright_left if left else bright_right
			_check(_changed_pixels(tile.get_region(Rect2i(start, 4, 3, 12)), canonical.get_region(Rect2i(0, 4, 3, 12))) == 0, "mask %d %s vertical/inner/outer face keeps the bright side color and three-pixel width" % [mask, "left" if left else "right"])
			side_checks += 1
	var coping_row := -1
	var greatest_gold_count := 0
	for y in range(16):
		var gold_count := 0
		for x in range(16):
			if _is_gold(front.get_pixel(x, y)): gold_count += 1
		if gold_count > greatest_gold_count:
			greatest_gold_count = gold_count
			coping_row = y
	_check(coping_row >= 0, "original facade has an authored gold coping row")
	if coping_row < 0: return
	for mask in [64, 128]:
		var left: bool = mask == 128
		var start := 0 if left else 13
		var tile := _wall_tile(image, mask)
		var coping := front.get_region(Rect2i(13 if left else 0, 0, 3, 4))
		coping.flip_x()
		_check(_changed_pixels(tile.get_region(Rect2i(start, 0, 3, 4)), coping) == 0, "inner %d connects only its top four rows to the neighboring facade coping" % mask)
		var untouched := Rect2i(3 if left else 0, 0, 13, 16)
		_check(_changed_pixels(tile.get_region(untouched), body.get_region(untouched)) == 0, "inner %d leaves the old body outside its three-pixel return and never widens to four pixels" % mask)
		var gold_count := 0
		for x in range(start, start + 3):
			if _is_gold(tile.get_pixel(x, coping_row)): gold_count += 1
		_check(gold_count > 0, "inner %d coping matches original facade height %d" % [mask, coping_row])
	for mask in [6, 12, 14]:
		_check(_changed_pixels(_wall_tile(image, mask).get_region(Rect2i(0, 0, 16, 4)), front.get_region(Rect2i(0, 0, 16, 4))) == 0, "outer %d preserves original gold coping and front height" % mask)
	_check(_changed_pixels(_wall_tile(image, 1).get_region(Rect2i(0, 0, 16, 3)), edges.get_region(Rect2i(16, 0, 16, 3))) == 0, "rear wall keeps the original horizontal coping")
	_check(_changed_pixels(_wall_tile(image, 16).get_region(Rect2i(0, 0, 3, 3)), bright_left.get_region(Rect2i(0, 0, 3, 3))) == 0, "rear-left corner uses the same bright vertical face")
	_check(_changed_pixels(_wall_tile(image, 32).get_region(Rect2i(13, 0, 3, 3)), bright_right.get_region(Rect2i(0, 0, 3, 3))) == 0, "rear-right corner mirrors the same bright vertical face")
	print("WALL_RELIEF_SEAMS gold_coping_row=%d canonical_side_width=3 mirrored_vertical_checks=%d inner_returns=2 outer_caps=3 rear_corners=2" % [coping_row, side_checks])

func _check_torch_frames() -> void:
	var frames := environment._torch_frames_a
	var count := frames.get_frame_count("default")
	_check(count == 6 and count >= 4, "real torch SpriteFrames has six animation frames")
	_check(frames.get_animation_loop("default"), "torch animation loops")
	_check(is_equal_approx(frames.get_animation_speed("default"), 8.0), "torch base animation rate is 8fps")
	var flame_hashes := {}
	var bracket: Image
	var visible_bracket_changes := 0
	var connected_columns: Array[int] = []
	var source_png := Image.load_from_file(ProjectSettings.globalize_path(StageEnvironment.TORCH_A_PATH))
	var source_bracket := source_png.get_region(BRACKET_RECT).get_data()
	for index in count:
		var image := _frame_image(frames.get_frame_texture("default", index))
		_check(image.get_size() == FRAME_SIZE, "torch frame %d is 16x24" % index)
		if image.get_size() != FRAME_SIZE:
			continue
		_check(source_png.get_region(Rect2i(index * 16, 12, 16, 12)).get_data() == source_bracket, "source PNG bracket bytes are identical at frame %d" % index)
		var connected := 0
		for x in range(FRAME_SIZE.x):
			if source_png.get_pixel(index * 16 + x, 11).a > 0.0 and source_png.get_pixel(index * 16 + x, 12).a == 1.0:
				connected += 1
		connected_columns.append(connected)
		_check(connected > 0, "source PNG flame at row 11 touches opaque bracket at row 12 in frame %d" % index)
		var current_bracket := image.get_region(BRACKET_RECT)
		if index == 0:
			bracket = current_bracket
		else:
			var changed := _changed_pixels(current_bracket, bracket)
			visible_bracket_changes += changed
			_check(changed == 0, "imported torch frame %d keeps visible bracket pixels fixed" % index)
		flame_hashes[hash(image.get_region(Rect2i(0, 0, 16, 12)).get_data())] = true
	_check(flame_hashes.size() >= 4, "at least four visibly different flame frames exist")
	print("TORCH_SOURCE frames=%d unique_flames=%d bracket_rows=12..23 visible_bracket_changes=%d flame_bracket_connected_columns=%s" % [count, flame_hashes.size(), visible_bracket_changes, connected_columns])

func _check_rendered_torch() -> void:
	var target: AnimatedSprite2D
	for child in environment._sprite_decorations.get_children():
		var sprite := child as AnimatedSprite2D
		if sprite.visible and sprite.sprite_frames == environment._torch_frames_a:
			target = sprite
			break
	_check(target != null, "an animated torch exists in the actual MAP field")
	if target == null:
		return
	_check(target.is_playing(), "actual field torch is playing")
	player.global_position = target.global_position + Vector2(0, 96)
	# Camera limits near the MAP edge can place a real torch behind the HUD.
	# This test-only fixed camera keeps the same live field and exposes the flame;
	# production camera settings, wall coordinates and sprite positions stay intact.
	var capture_camera := Camera2D.new()
	capture_camera.zoom = player.camera.zoom
	add_child(capture_camera)
	capture_camera.global_position = target.global_position + Vector2(0, 80)
	capture_camera.make_current()
	capture_camera.force_update_scroll()
	await _frames(5)
	var fixed_transform := target.get_global_transform_with_canvas()
	var observed_frames := {}
	var first_bracket: Image
	var first_flame: Image
	var flame_rect := _sprite_screen_rect(target, Rect2i(0, 0, 16, 12))
	var bracket_rect := _sprite_screen_rect(target, BRACKET_RECT)
	for sample in range(4):
		if sample > 0:
			await get_tree().create_timer(0.19).timeout
		_check(target.get_global_transform_with_canvas().is_equal_approx(fixed_transform), "torch and camera remain fixed for sample %d" % sample)
		observed_frames[target.frame] = true
		var image := await _capture("main_field_t%d" % sample)
		if image == null:
			continue
		_check(image.get_used_rect().encloses(flame_rect) and Rect2i(Vector2i.ZERO, image.get_size()).encloses(bracket_rect), "fixed torch crop stays inside the viewport")
		var flame := image.get_region(flame_rect)
		var bracket := image.get_region(bracket_rect)
		if first_bracket == null:
			first_bracket = bracket
			first_flame = flame
		else:
			_check(_changed_pixels(first_bracket, bracket) == 0, "rendered bracket does not wobble at t%d" % sample)
			changed_render_pixels += _changed_pixels(first_flame, flame)
	_check(observed_frames.size() >= 3, "actual elapsed time advances at least three visible torch frames")
	if DisplayServer.get_name() != "headless":
		_check(changed_render_pixels > 0, "same-position Vulkan flame pixels visibly change")
	print("TORCH_RUNTIME observed_frames=%s bracket_crop=%s flame_crop=%s changed_pixels=%d" % [observed_frames.keys(), bracket_rect, flame_rect, changed_render_pixels])
	player.camera.make_current()
	capture_camera.queue_free()

func _check_pool_rebuilds() -> void:
	var map := GameManager.dungeon_map
	var floors := map.get_floor_cells()
	var obstacles := map.terrain_obstacle_cells.duplicate()
	seed(50811)
	environment.build_dungeon(map)
	var initial_count := environment._sprite_decorations.get_child_count()
	for index in range(6):
		seed(50811)
		if index % 2 == 0:
			environment.build_dungeon(map)
		else:
			await environment.build_dungeon_async(map, 5)
		_check(environment._sprite_decorations.get_child_count() == initial_count, "rebuild %d reuses sprite pool without growth" % index)
		for child in environment._sprite_decorations.get_children():
			var sprite := child as AnimatedSprite2D
			if not sprite.visible:
				_check(not sprite.is_playing(), "hidden pooled sprite is stopped")
		_check(map.get_floor_cells() == floors and map.terrain_obstacle_cells == obstacles, "material/animation rebuild leaves topology unchanged")
	var small := DungeonMap.new(24, 24)
	_carve(small, Rect2i(-4, -3, 8, 6))
	small.spawn_point = Vector2i.ZERO
	environment.build_dungeon(small)
	var hidden_count := 0
	for child in environment._sprite_decorations.get_children():
		var sprite := child as AnimatedSprite2D
		if not sprite.visible:
			hidden_count += 1
			_check(not sprite.is_playing(), "small rebuild retires surplus animated torches")
	_check(hidden_count > 0, "small map exercises unused pool retirement")
	_check(environment._sprite_decorations.get_child_count() == initial_count, "small map does not allocate more sprites")
	print("TORCH_POOL high_water=%d rebuilds=6 retired_hidden=%d" % [initial_count, hidden_count])

func _capture_inner_fixture() -> void:
	game.hide()
	for layer in game.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).hide()
	var stage := STAGE.instantiate() as StageEnvironment
	add_child(stage)
	var map := DungeonMap.new(32, 24)
	_carve(map, Rect2i(-7, -3, 14, 8))
	_carve(map, Rect2i(-1, -8, 3, 5))
	map.spawn_point = Vector2i(0, 2)
	stage.wall_deco_count = 0
	stage.floor_decal_chance = 0.0
	stage.wall_decoration_chance = 0.0
	stage.build_dungeon(map)
	if is_instance_valid(stage._royal_crest): stage._royal_crest.hide()
	var camera := Camera2D.new()
	add_child(camera)
	camera.zoom = Vector2(1.5, 1.5)
	camera.global_position = stage._tile_map_layer.to_global(stage._tile_map_layer.map_to_local(Vector2i(0, -2)))
	camera.make_current()
	camera.force_update_scroll()
	await _frames(4)
	await _capture("coherent_room_overview")
	camera.zoom = Vector2(3.0, 3.0)
	camera.global_position = stage._tile_map_layer.to_global(stage._tile_map_layer.map_to_local(Vector2i(-7, -3)))
	camera.force_update_scroll()
	await _frames(3)
	await _capture("inner_L_same_material")
	stage.queue_free()

func _frame_image(texture: Texture2D) -> Image:
	if texture is AtlasTexture:
		return (texture as AtlasTexture).atlas.get_image().get_region(Rect2i((texture as AtlasTexture).region))
	return texture.get_image()

func _sprite_screen_rect(sprite: AnimatedSprite2D, region: Rect2i) -> Rect2i:
	var top_left := Vector2(region.position) - Vector2(FRAME_SIZE) * 0.5 + sprite.offset
	var transform := sprite.get_global_transform_with_canvas()
	var start := transform * top_left
	var end := transform * (top_left + Vector2(region.size))
	return Rect2i(Vector2i(start.round()), Vector2i((end - start).round()))

func _changed_pixels(first: Image, second: Image) -> int:
	if first.get_size() != second.get_size(): return -1
	var count := 0
	for y in range(first.get_height()):
		for x in range(first.get_width()):
			var first_color := first.get_pixel(x, y)
			var second_color := second.get_pixel(x, y)
			# Texture import may fill invisible RGB at alpha=0 (fix_alpha_border).
			# Alpha changes or ANY visible color changes still fail the bracket check.
			if first_color.a == 0.0 and second_color.a == 0.0:
				continue
			count += 1 if first_color != second_color else 0
	return count

func _capture(filename: String) -> Image:
	if DisplayServer.get_name() == "headless": return null
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image != null and not image.is_empty(), filename + ": real viewport exists")
	if image != null:
		_check(image.save_png(OUTPUT_DIR + "/" + filename + ".png") == OK, filename + ": screenshot saved")
	print("WALL_MATERIAL_CAPTURE ", filename)
	await get_tree().process_frame
	return image

func _carve(map: DungeonMap, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x): map.set_floor(Vector2i(x, y), true)

func _frames(count: int) -> void:
	for _index in count: await get_tree().process_frame

func _check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	if failures <= 24: push_error("WALL_MATERIAL_ANIMATION_CHECK: " + message)
