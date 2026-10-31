extends Node2D
## ComfyUI-authored surfaces rendered over the unchanged collision grid.
##
## floor_only（5分サバイバルの床だけの戦場）では、同じ床素材の繰り返しの上に
## 「床の飾り」（tools/map_unified/build.py が生成する assets/visuals/floor_decals/）を
## 世界座標のハッシュで散らし、紫晶・熔岩など光る飾りには光だまりを重ね、
## 画面の縁の暗がりとテーマ別の浮遊粒（塵・煌めき・火の粉）で空気感を足す。
## 当たり判定・湧き・経路は一切変えない（描画だけ）。
var dungeon: DungeonMap
var cells: Array[Vector2i] = []
var surface_texture: Texture2D
var wall_texture: Texture2D
var theme := 1
var _actor: Player

const DECAL_PX := 64
const DECAL_COLS := 8
## 床素材の繰り返し周期（128px × 2倍）
const FLOOR_PERIOD := 256.0
## 飾りを描く範囲（位置を中心に ±）。周期 256px で位置が飛ぶので、画面 1600×900 ÷ 1.15 倍 ≒ 1392×784 を余裕で覆う。
const DECAL_REACH := 1408
const THEME_TINT := {1: Color(0.80, 0.86, 0.94), 2: Color(0.86, 0.80, 0.96), 3: Color(0.96, 0.86, 0.76)}
const GLOW_COLOR := {1: Color("7ae0d8"), 2: Color("c070ff"), 3: Color("ff8a2a")}
## 縁の暗がりは敵の視認を邪魔しない程度（画面端でも敵の輪郭が読める濃さ）に抑える。
const VIGNETTE_COLOR := {1: Color(0.02, 0.03, 0.07, 0.62), 2: Color(0.06, 0.02, 0.11, 0.62), 3: Color(0.11, 0.03, 0.0, 0.58)}
var _decals: Texture2D
var _glow_texture: Texture2D
var _emissive: Array[int] = []
var _glow_layer: FloorGlow
var _particles: CPUParticles2D
var _atmosphere: CanvasLayer
var _last_snap := Vector2(INF, INF)

func configure(map: DungeonMap, rendered_cells: Array[Vector2i], map_theme: int) -> void:
	dungeon = map
	cells = rendered_cells
	theme = map_theme
	surface_texture = load("res://assets/visuals/ember_v5/map%d_floor.png" % theme)
	wall_texture = load("res://assets/visuals/ember_v5/map%d_wall.png" % theme)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = -90
	set_process(map.get_meta("floor_only", false))
	if map.get_meta("floor_only", false):
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_actor = get_tree().get_first_node_in_group("player") as Player
		_setup_field_dressing()
	queue_redraw()

func _walk_surface(cell: Vector2i) -> bool:
	return dungeon.is_floor(cell) or dungeon.get_meta("scenic_landmark_cells", {}).has(cell)

func _process(_delta: float) -> void:
	if is_instance_valid(_actor):
		# Snap to the texture period so re-centering never shifts the floor artwork.
		var center := _actor.camera.get_screen_center_position()
		position = (center / FLOOR_PERIOD).floor() * FLOOR_PERIOD
		if position != _last_snap:
			_last_snap = position
			queue_redraw()
		if _particles:
			_particles.global_position = center

func _draw() -> void:
	if dungeon.get_meta("floor_only", false) and surface_texture:
		draw_set_transform(Vector2.ZERO, 0, Vector2(2, 2))
		draw_texture_rect(surface_texture, Rect2(-2048, -2048, 4096, 4096), true, THEME_TINT.get(theme, Color(.83, .83, .86)))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		_draw_field_dressing()
		return
	if not surface_texture or not wall_texture: return
	for cell in cells:
		var rect := Rect2(Vector2(cell)*32,Vector2(32,32))
		var floor_cell := _walk_surface(cell)
		var sample := Rect2(Vector2(posmod(cell.x,8),posmod(cell.y,8))*16,Vector2(16,16))
		if floor_cell:
			draw_texture_rect_region(surface_texture,rect,sample,Color(.83,.83,.86))
			if not _walk_surface(cell+Vector2i.UP):
				draw_rect(Rect2(rect.position,Vector2(32,4)),Color(0,0,0,.32))
		else:
			var face := _walk_surface(cell+Vector2i.DOWN) or _walk_surface(cell+Vector2i(0,2))
			var shade := Color(.94,.94,.98) if face else Color(.57,.59,.65)
			draw_texture_rect_region(wall_texture,rect,sample,shade)
			if _walk_surface(cell+Vector2i.UP):
				draw_rect(Rect2(rect.position,Vector2(32,2)),Color(.45,.46,.50,.7))
			if _walk_surface(cell+Vector2i.DOWN):
				draw_rect(Rect2(rect.position+Vector2(0,28),Vector2(32,4)),Color(.025,.03,.04,.9))
			if _walk_surface(cell+Vector2i.LEFT):
				draw_rect(Rect2(rect.position,Vector2(3,32)),Color(.08,.085,.10,.8))
			if _walk_surface(cell+Vector2i.RIGHT):
				draw_rect(Rect2(rect.position+Vector2(29,0),Vector2(3,32)),Color(.025,.03,.04,.85))

# ============================================================
# floor_only の床の飾り・光だまり・空気感
# ============================================================

## 世界座標から決まる 0..1 の値。同じ場所は毎回同じ飾りになる。
static func _hash01(x: int, y: int, salt: int) -> float:
	var h := (x * 374761393 + y * 668265263 + salt * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0

func _setup_field_dressing() -> void:
	var decal_path := "res://assets/visuals/floor_decals/map%d.png" % theme
	_decals = load(decal_path) if ResourceLoader.exists(decal_path) else null
	_glow_texture = load("res://assets/visuals/floor_decals/glow.png") if ResourceLoader.exists("res://assets/visuals/floor_decals/glow.png") else null
	_emissive.assign({1: [12, 13], 2: [10, 11, 12, 13, 14, 15], 3: [10, 11, 12, 13]}.get(theme, []))
	if _glow_layer == null:
		_glow_layer = FloorGlow.new()
		_glow_layer.name = "FloorGlow"
		_glow_layer.texture = _glow_texture
		_glow_layer.color = GLOW_COLOR.get(theme, Color.WHITE)
		add_child(_glow_layer)
	_setup_particles()
	_setup_vignette()

func _draw_field_dressing() -> void:
	if _decals == null:
		return
	var glows: Array[Vector2] = []
	var origin := Vector2i(position) / DECAL_PX
	var reach := DECAL_REACH / DECAL_PX
	# 大きな染み（床の調子の変化）。192px 間隔のおよそ 1/3 に、飾り 9 番（染み）を 3 倍で薄く敷く。
	var stain_step := 192
	var stain_reach := DECAL_REACH / stain_step
	var stain_region := Rect2(9 * DECAL_PX, DECAL_PX, DECAL_PX, DECAL_PX)
	for gy in range(-stain_reach, stain_reach + 1):
		for gx in range(-stain_reach, stain_reach + 1):
			var wx := int(position.x) / stain_step + gx
			var wy := int(position.y) / stain_step + gy
			if _hash01(wx, wy, 7) > 0.34:
				continue
			var size := DECAL_PX * (2.5 + _hash01(wx, wy, 8) * 1.5)
			var local := Vector2(wx * stain_step, wy * stain_step) - position + Vector2(_hash01(wx, wy, 9) * 64.0, _hash01(wx, wy, 10) * 64.0)
			draw_texture_rect_region(_decals, Rect2(local - Vector2(size, size) * 0.5, Vector2(size, size)), stain_region, Color(1, 1, 1, 0.55))
	# 飾り：64px 格子のおよそ 1 割。向きは左右反転だけ（上下反転は影の向きが崩れる）。
	for gy in range(-reach, reach + 1):
		for gx in range(-reach, reach + 1):
			var wx := origin.x + gx
			var wy := origin.y + gy
			var roll := _hash01(wx, wy, 1)
			if roll > 0.10:
				continue
			var index := int(_hash01(wx, wy, 2) * (DECAL_COLS * 2)) % (DECAL_COLS * 2)
			# 光る飾りは少なめに（出過ぎると床が騒がしい）
			if index in _emissive and _hash01(wx, wy, 3) > 0.45:
				index = int(_hash01(wx, wy, 4) * 10) % 10
			var flip := _hash01(wx, wy, 5) > 0.5
			var local := Vector2(wx * DECAL_PX, wy * DECAL_PX) - position + Vector2(_hash01(wx, wy, 6) * 16.0 - 8.0, _hash01(wx, wy, 11) * 16.0 - 8.0)
			var region := Rect2((index % DECAL_COLS) * DECAL_PX, (index / DECAL_COLS) * DECAL_PX, DECAL_PX, DECAL_PX)
			var rect := Rect2(local, Vector2(DECAL_PX, DECAL_PX))
			if flip:
				rect = Rect2(local + Vector2(DECAL_PX, 0), Vector2(-DECAL_PX, DECAL_PX))
			draw_texture_rect_region(_decals, rect, region, Color(1, 1, 1, 0.92))
			if index in _emissive:
				glows.append(local + Vector2(DECAL_PX, DECAL_PX) * 0.5)
	if _glow_layer:
		_glow_layer.points = glows
		_glow_layer.queue_redraw()

## 光だまり：加算合成でゆっくり明滅する。飾りの座標は親の _draw が渡す。
class FloorGlow extends Node2D:
	var texture: Texture2D
	var color := Color.WHITE
	var points: Array[Vector2] = []
	var _phase := 0.0
	func _ready() -> void:
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		self.material = material
		z_index = 1
	func _process(delta: float) -> void:
		_phase += delta
		if not points.is_empty():
			queue_redraw()
	func _draw() -> void:
		if texture == null:
			return
		for index in points.size():
			var pulse := 0.75 + 0.25 * sin(_phase * 1.7 + float(index) * 1.3)
			var size := 112.0 + 16.0 * sin(_phase * 1.1 + float(index))
			draw_texture_rect(texture, Rect2(points[index] - Vector2(size, size) * 0.5, Vector2(size, size)), false, Color(color, 0.30 * pulse))
			draw_texture_rect(texture, Rect2(points[index] - Vector2(size, size) * 0.25, Vector2(size, size) * 0.5), false, Color(color.lightened(0.4), 0.22 * pulse))

## テーマ別の浮遊粒。世界座標で湧かせ、発生位置だけカメラへ追従させる（位置の飛びで粒が跳ねない）。
func _setup_particles() -> void:
	if _particles != null:
		return
	_particles = CPUParticles2D.new()
	_particles.name = "FieldMotes"
	_particles.local_coords = false
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.emission_rect_extents = Vector2(900, 540)
	_particles.z_index = 60
	var image := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_particles.texture = ImageTexture.create_from_image(image)
	match theme:
		2:
			_particles.amount = 26
			_particles.lifetime = 4.0
			_particles.direction = Vector2(0, -1)
			_particles.spread = 180.0
			_particles.gravity = Vector2.ZERO
			_particles.initial_velocity_min = 2.0
			_particles.initial_velocity_max = 8.0
			_particles.scale_amount_min = 0.6
			_particles.scale_amount_max = 1.4
			_particles.color = Color(0.85, 0.7, 1.0, 0.55)
		3:
			_particles.amount = 34
			_particles.lifetime = 3.2
			_particles.direction = Vector2(0, -1)
			_particles.spread = 25.0
			_particles.gravity = Vector2(0, -22)
			_particles.initial_velocity_min = 10.0
			_particles.initial_velocity_max = 26.0
			_particles.scale_amount_min = 0.7
			_particles.scale_amount_max = 1.5
			_particles.color = Color(1.0, 0.55, 0.2, 0.7)
		_:
			_particles.amount = 22
			_particles.lifetime = 6.0
			_particles.direction = Vector2(1, 0)
			_particles.spread = 180.0
			_particles.gravity = Vector2.ZERO
			_particles.initial_velocity_min = 3.0
			_particles.initial_velocity_max = 9.0
			_particles.scale_amount_min = 0.5
			_particles.scale_amount_max = 1.1
			_particles.color = Color(0.7, 0.82, 0.95, 0.32)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.2, Color(1, 1, 1, 1))
	ramp.add_point(0.8, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	_particles.color_ramp = ramp
	add_child(_particles)

## 画面の縁の暗がり（テーマ色）。HUD より下、世界より上。
func _setup_vignette() -> void:
	if _atmosphere != null:
		return
	var vignette_path := "res://assets/visuals/floor_decals/vignette.png"
	if not ResourceLoader.exists(vignette_path):
		return
	_atmosphere = CanvasLayer.new()
	_atmosphere.name = "FieldAtmosphere"
	_atmosphere.layer = 0
	add_child(_atmosphere)
	var vignette := TextureRect.new()
	vignette.name = "Vignette"
	vignette.texture = load(vignette_path)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate = VIGNETTE_COLOR.get(theme, Color(0, 0, 0, 0.7))
	_atmosphere.add_child(vignette)
	_vignette = vignette

var _vignette: TextureRect
var _alarm_tween: Tween
var _alarm_active := false

## 波の予告・本番の間、縁の暗がりを朱赤に脈打たせる。解除で元のテーマ色へ戻す。
func set_alarm(active: bool) -> void:
	if _vignette == null or _alarm_active == active:
		return
	_alarm_active = active
	if _alarm_tween and _alarm_tween.is_valid():
		_alarm_tween.kill()
	var base: Color = VIGNETTE_COLOR.get(theme, Color(0, 0, 0, 0.7))
	if not active:
		_alarm_tween = create_tween()
		_alarm_tween.tween_property(_vignette, "modulate", base, 0.4)
		return
	var dim := Color(0.55, 0.06, 0.03, 0.62)
	var bright := Color(0.95, 0.18, 0.08, 0.78)
	_alarm_tween = create_tween().set_loops()
	_alarm_tween.tween_property(_vignette, "modulate", bright, 0.45).set_trans(Tween.TRANS_SINE)
	_alarm_tween.tween_property(_vignette, "modulate", dim, 0.55).set_trans(Tween.TRANS_SINE)

func is_alarm_active() -> bool:
	return _alarm_active
