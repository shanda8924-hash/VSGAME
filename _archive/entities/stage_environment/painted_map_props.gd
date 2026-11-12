extends RefCounted
const PROPS := "res://assets/tiles/landmarks/painted_props.png"
const ARCHITECTURE := "res://assets/tiles/landmarks/architecture.png"

static func add_sprite(root: Node2D, texture: Texture2D, rect: Rect2, position: Vector2, size: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = rect
	sprite.texture = atlas
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.position = position
	sprite.scale = size / rect.size
	root.add_child(sprite)
	return sprite

static func install(stage: Node2D, map: DungeonMap, theme: int) -> void:
	var root := Node2D.new()
	root.name = "PaintedProps"
	root.z_index = -44
	stage.add_child(root)
	var texture := load(PROPS) as Texture2D
	var q := texture.get_size() * 0.5
	var row := 0 if theme == 2 else 1
	var architecture := load(ARCHITECTURE) as Texture2D
	for original: AnimatedSprite2D in stage._sprite_decorations.get_children():
		if not original.visible:
			continue
		original.self_modulate = Color(1,1,1,0)
		var point: Vector2 = original.position
		if original.sprite_frames == stage._wall_deco_frames:
			var region := Rect2(Vector2(original.frame % 2, row) * q, q)
			add_sprite(root, texture, region, point, Vector2(48, 48))
		else:
			var lamp := add_sprite(root, architecture, Rect2(489, 233, 34, 64), point, Vector2(18, 30))
			# Small breathing of the oil flame; bounded to a few wall lamps.
			var tween := root.create_tween().set_loops()
			tween.tween_property(lamp, "modulate", Color(0.85,0.77,0.65), 0.6)
			tween.tween_property(lamp, "modulate", Color.WHITE, 0.9)
	# Storage keeps the existing physical Tile; its visible silhouette is renewed.
	for cell: Vector2i in stage._decoration_layer.get_used_cells():
		if stage._decoration_layer.get_cell_atlas_coords(cell) in stage.storage_cluster_variants:
			add_sprite(root, texture, Rect2(Vector2(1,row)*q,q), Vector2(cell)*32.0+Vector2(16,10), Vector2(32,32))
	# Pillar Field's 2x2 solid bases must remain visibly occupied.
	for cell: Vector2i in stage._wall_overlay_layer.get_used_cells():
		var coords: Vector2i = stage._wall_overlay_layer.get_cell_atlas_coords(cell)
		if coords in [Vector2i(0,2),Vector2i(2,2)] and map.is_terrain_obstacle(cell):
			add_sprite(root, texture, Rect2(Vector2(0,row)*q,q), Vector2(cell)*32.0+Vector2(32,18), Vector2(70,70))
	stage._decoration_layer.hide()
	stage._wall_overlay_layer.hide()
