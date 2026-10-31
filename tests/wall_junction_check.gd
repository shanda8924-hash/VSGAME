extends Node2D
## Real StageEnvironment regression for original raised walls and matching bright side returns.

const STAGE_SCENE := preload("res://entities/stage_environment/stage_environment.tscn")
const OUTPUT_DIR := "res://artifacts/wall_junction"
const COLLISION_RECT := [Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)]
var environment: StageEnvironment
var camera: Camera2D
var failures: Array[String] = []
var failure_count := 0
var generated_junctions := 0

func _ready() -> void:
	SaveManager.begin_ephemeral_session()
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(75.0, true, false, true).timeout.connect(func():
		push_error("WALL_JUNCTION_CHECK: timeout")
		get_tree().quit(1)
	)
	_run.call_deferred()

func _exit_tree() -> void:
	SaveManager.end_ephemeral_session()

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	environment = STAGE_SCENE.instantiate() as StageEnvironment
	add_child(environment)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = false
	add_child(camera)
	camera.make_current()
	_check_atlas_contract()
	_check_neighbor_masks()
	var room := _room_fixture()
	environment.build_dungeon(room)
	_hide_fixture_decorations()
	_check_tile(Vector2i(-8, -4), _coords(64), "left inner front junction")
	_check_tile(Vector2i(7, -4), _coords(128), "right inner front junction")
	_check_tile(Vector2i(-2, -4), _coords(230), "doorway left wall right endcap")
	_check_tile(Vector2i(2, -4), _coords(220), "doorway right wall left endcap")
	_check_tile(Vector2i(-5, -4), _coords(196), "straight front uses restored original facade")
	_check_tile(Vector2i(-8, 0), _coords(98), "straight side uses the original bright mirrored rim")
	await _check_physics()
	await _capture(Vector2i(0, -2), 1.5, "room_front_junctions")
	await _capture(Vector2i(-7, -3), 4.0, "inner_left")
	await _capture(Vector2i(6, -3), 4.0, "inner_right")
	await _capture(Vector2i(0, -4), 3.0, "doorway_endcaps")
	var courtyard := _courtyard_fixture()
	environment.build_dungeon(courtyard)
	_hide_fixture_decorations()
	_check_tile(Vector2i(-3, 1), _coords(220), "convex block front left cap")
	_check_tile(Vector2i(2, 1), _coords(230), "convex block front right cap")
	await _capture(Vector2i(0, 0), 2.0, "convex_front_caps")
	await _check_generated_builds()
	_check(SaveManager.is_ephemeral_session_active(), "normal save remains protected")
	print("WALL_JUNCTION_CHECK failures=%d mask_cases=256 atlas_tiles=256 physical_probes=6 generated_maps=3 sync_async_pairs=3 generated_wall_cells=%d renderer=%s" % [failure_count, generated_junctions, RenderingServer.get_current_rendering_method()])
	get_tree().quit(0 if failure_count == 0 else 1)

func _check_atlas_contract() -> void:
	var source := environment._tile_set.get_source(StageEnvironment.WALL_JUNCTION_SOURCE_ID) as TileSetAtlasSource
	_check(source != null, "raised-wall atlas is attached to the real TileSet")
	if source == null:
		return
	_check(source.texture.resource_path == StageEnvironment.WALL_JUNCTION_TEXTURE_PATH, "TileSet uses original wall materials with matching bright side returns")
	_check(source.texture.get_size() == Vector2(256, 256), "raised-wall atlas is 256x256")
	_check(source.get_tiles_count() == 256, "all 256 wall neighborhoods are registered")
	_check(environment._tile_set.get_physics_layer_collision_layer(0) == 1, "wall collision remains layer 1")
	for index in source.get_tiles_count():
		var coords := source.get_tile_id(index)
		_check_collision(source.get_tile_data(coords, 0), "atlas %s" % coords)

func _check_neighbor_masks() -> void:
	# Public material contract: N/E/S/W/NW/NE/SE/SW, clockwise cardinal first.
	var offsets := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]
	for bits in range(256):
		var map := DungeonMap.new(9, 9)
		for index in offsets.size():
			if bits & (1 << index):
				map.set_floor(offsets[index], true)
		_check(environment._wall_neighbor_mask(map, Vector2i.ZERO) == bits, "neighbor mask %d" % bits)
	print("WALL_JUNCTION_MASKS: 256 cardinal/diagonal combinations checked")

func _coords(mask: int) -> Vector2i:
	return Vector2i(mask % 16, mask / 16)

func _room_fixture() -> DungeonMap:
	var map := DungeonMap.new(30, 24)
	var room := Rect2i(-7, -3, 14, 8)
	_carve(map, room)
	_carve(map, Rect2i(-1, -8, 3, 5))
	map.rooms.append(room)
	map.spawn_point = Vector2i(0, 2)
	return map

func _courtyard_fixture() -> DungeonMap:
	var map := DungeonMap.new(30, 24)
	_carve(map, Rect2i(-9, -6, 18, 12))
	for y in range(-2, 2):
		for x in range(-3, 3):
			map.set_floor(Vector2i(x, y), false)
	map.spawn_point = Vector2i(0, 4)
	return map

func _carve(map: DungeonMap, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			map.set_floor(Vector2i(x, y), true)

func _check_tile(cell: Vector2i, expected: Vector2i, label: String) -> void:
	var layer := environment._tile_map_layer
	_check(layer.get_cell_source_id(cell) == StageEnvironment.WALL_JUNCTION_SOURCE_ID, label + ": uses junction source")
	_check(layer.get_cell_atlas_coords(cell) == expected, label + ": correct orientation")
	_check_collision(layer.get_cell_tile_data(cell), label)

func _check_collision(data: TileData, label: String) -> void:
	_check(data != null and data.get_collision_polygons_count(0) == 1, label + ": one wall collision polygon")
	if data != null and data.get_collision_polygons_count(0) == 1:
		_check(data.get_collision_polygon_points(0, 0) == PackedVector2Array(COLLISION_RECT), label + ": unchanged 16px collision bounds")

func _check_physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var body := CharacterBody2D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 6.0
	shape.shape = circle
	body.add_child(shape)
	add_child(body)
	for probe in [
		[Vector2i(-7, -3), Vector2(-40, -40), true, "left concave corner"],
		[Vector2i(6, -3), Vector2(40, -40), true, "right concave corner"],
		[Vector2i(-2, -3), Vector2(0, -64), true, "front endcap from below"],
		[Vector2i(-1, -4), Vector2(-64, 0), true, "front endcap from side"],
		[Vector2i(0, -2), Vector2(0, -128), false, "three-cell doorway stays open"],
		[Vector2i(-5, -3), Vector2(0, -64), true, "unchanged straight front wall"],
	]:
		body.global_position = _cell_center(probe[0])
		await get_tree().physics_frame
		var collision := body.move_and_collide(probe[1])
		_check((collision != null) == bool(probe[2]), "physics " + String(probe[3]))
	body.queue_free()
	await get_tree().physics_frame

func _check_generated_builds() -> void:
	environment._wall_overlay_layer.show()
	environment._sprite_decorations.show()
	environment._decoration_layer.show()
	var configs := [Vector4i(78, 78, 10, 1), Vector4i(86, 86, 11, 2), Vector4i(94, 94, 12, 2)]
	for index in configs.size():
		var config: Vector4i = configs[index]
		var rng := RandomNumberGenerator.new()
		rng.seed = 90205 + index * 93
		var map := DungeonGenerator.generate(config.x, config.y, config.z, config.w, rng)
		var floors := map.get_floor_cells()
		var obstacles := map.terrain_obstacle_cells.duplicate()
		environment.build_dungeon(map)
		var sync_cells := _tile_snapshot()
		await environment.build_dungeon_async(map, 5)
		_check(_tile_snapshot() == sync_cells, "MAP%d sync/async chooses identical base tiles" % (index + 1))
		_check(map.get_floor_cells() == floors and map.terrain_obstacle_cells == obstacles, "renderer never edits floor/collision topology")
		var count := 0
		var representative := Vector2i.ZERO
		for cell: Vector2i in environment._tile_map_layer.get_used_cells():
			if environment._tile_map_layer.get_cell_source_id(cell) != StageEnvironment.WALL_JUNCTION_SOURCE_ID:
				continue
			_check(not map.is_floor(cell), "junction artwork never replaces a floor cell")
			_check_collision(environment._tile_map_layer.get_cell_tile_data(cell), "generated junction %s" % cell)
			if count == 0:
				representative = cell
			count += 1
		_check(count > 0, "MAP%d uses actual junction tiles" % (index + 1))
		generated_junctions += count
		print("WALL_JUNCTION_GENERATED map=%d seed=%d junctions=%d" % [index + 1, rng.seed, count])
		await _capture(representative, 2.0, "generated_map%d" % (index + 1))

func _tile_snapshot() -> Dictionary:
	var result := {}
	var layer := environment._tile_map_layer
	for cell in layer.get_used_cells():
		result[cell] = [layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell)]
	return result

func _hide_fixture_decorations() -> void:
	environment._wall_overlay_layer.hide()
	environment._sprite_decorations.hide()
	environment._decoration_layer.hide()
	if is_instance_valid(environment._royal_crest):
		environment._royal_crest.hide()

func _cell_center(cell: Vector2i) -> Vector2:
	return environment._tile_map_layer.to_global(environment._tile_map_layer.map_to_local(cell))

func _capture(cell: Vector2i, zoom_value: float, filename: String) -> void:
	camera.global_position = _cell_center(cell)
	camera.zoom = Vector2.ONE * zoom_value
	camera.force_update_scroll()
	for _frame in 3:
		await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image != null and not image.is_empty(), filename + ": rendered viewport image exists")
	if image != null and not image.is_empty():
		_check(image.save_png(OUTPUT_DIR + "/" + filename + ".png") == OK, filename + ": capture saved")
	print("WALL_JUNCTION_CAPTURE ", filename)
	await get_tree().process_frame

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	if failures.size() < 20:
		failures.append(message)
		push_error("WALL_JUNCTION_CHECK: " + message)
