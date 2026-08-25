extends Area2D
class_name GroundEquipmentItem
## 地面に残り、近距離で名前と取得プロンプトを表示する手動取得装備。

@export var pickup_radius: float = 72.0
const ICON_HEIGHT_RATIO := 0.82
const ICON_HEIGHT_MIN := 24.0
const ICON_HEIGHT_MAX := 42.0
var equipment: EquipmentData
var _player: Player
var _icon_visual_size := Vector2(28.0, 28.0)
var _icon_visual_top := -24.0

func setup(item: EquipmentData) -> void:
	equipment = item

func _ready() -> void:
	add_to_group("ground_equipment")
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visual()

func _build_visual() -> void:
	if equipment == null:
		return
	var visual := Node2D.new()
	visual.name = "Visual"
	add_child(visual)
	_build_icon(visual)
	_build_ground_effects(visual)
	_build_labels(visual)

func _build_icon(visual: Node2D) -> void:
	if equipment.icon_path != "" and ResourceLoader.exists(equipment.icon_path):
		var icon := Sprite2D.new()
		icon.name = "EquipmentIcon"
		icon.texture = load(equipment.icon_path)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var image := icon.texture.get_image()
		var used := image.get_used_rect() if image else Rect2i(0, 0, icon.texture.get_width(), icon.texture.get_height())
		var target_height := clampf(_get_player_visual_height() * ICON_HEIGHT_RATIO, ICON_HEIGHT_MIN, ICON_HEIGHT_MAX)
		var visual_scale := target_height / maxf(float(used.size.y), 1.0)
		icon.scale = Vector2.ONE * visual_scale
		var visible_center_x := float(used.position.x) + float(used.size.x) * 0.5 - float(icon.texture.get_width()) * 0.5
		var visible_bottom_y := float(used.position.y + used.size.y) - float(icon.texture.get_height()) * 0.5
		icon.position = Vector2(-visible_center_x * visual_scale, 4.0 - visible_bottom_y * visual_scale)
		icon.z_index = 2
		visual.add_child(icon)
		_icon_visual_size = Vector2(float(used.size.x) * visual_scale, target_height)
		_icon_visual_top = 4.0 - target_height
	else:
		var glyph := Label.new()
		glyph.name = "EquipmentIconFallback"
		glyph.text = {"weapon":"剣", "head":"兜", "body":"鎧", "arms":"腕", "legs":"脚", "accessory":"飾"}.get(equipment.slot, "装")
		glyph.position = Vector2(-14, -24)
		glyph.size = Vector2(28, 28)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", 16)
		glyph.add_theme_color_override("font_color", equipment.get_rarity_color())
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		visual.add_child(glyph)
		_icon_visual_size = Vector2(28.0, 28.0)
		_icon_visual_top = -24.0

func _build_labels(visual: Node2D) -> void:
	var beam_length := _get_beam_length()
	var label := Label.new()
	label.name = "ItemLabel"
	label.text = "%s\n%s" % [equipment.display_name, equipment.get_rarity_display_name()]
	label.position = Vector2(-110, _icon_visual_top - beam_length - 48.0)
	label.size = Vector2(220, 42)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", equipment.get_rarity_color())
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	visual.add_child(label)
	var prompt := Label.new()
	prompt.name = "Prompt"
	prompt.text = "E / X：拾う"
	prompt.position = Vector2(-80, _icon_visual_top - 28.0)
	prompt.size = Vector2(160, 24)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.visible = false
	visual.add_child(prompt)
	if equipment.rarity in ["legendary", "mythic"]:
		var particles := CPUParticles2D.new()
		particles.name = "LootParticles"
		particles.amount = 7 if equipment.rarity == "mythic" else 4
		particles.lifetime = 0.9
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		particles.emission_sphere_radius = maxf(_icon_visual_size.x * 0.42, 8.0)
		particles.direction = Vector2(0, -1)
		particles.spread = 28.0
		particles.initial_velocity_min = 12.0
		particles.initial_velocity_max = 24.0
		particles.gravity = Vector2(0, 2)
		particles.color = Color(equipment.get_rarity_color(), 0.58 if equipment.rarity == "mythic" else 0.4)
		particles.position = Vector2(0, _icon_visual_top + _icon_visual_size.y * 0.5)
		particles.z_index = 1
		visual.add_child(particles)

func _build_ground_effects(visual: Node2D) -> void:
	var color := equipment.get_rarity_color()
	var half_width := maxf(_icon_visual_size.x * 0.5 + 4.0, 12.0)
	# Smooth ellipse/長い縦Beamは画面占有率が高いため撤去。Icon直下に硬い
	# 8点Pixel台座と短いCorner markだけを置き、Rarityは色とFragment数で読む。
	var plate := Polygon2D.new()
	plate.name = "PixelLootPlate"
	plate.polygon = PackedVector2Array([
		Vector2(-half_width + 3, 6), Vector2(half_width - 3, 6),
		Vector2(half_width, 9), Vector2(half_width - 3, 12),
		Vector2(-half_width + 3, 12), Vector2(-half_width, 9),
	])
	plate.color = Color(color.r, color.g, color.b, 0.24)
	plate.z_index = 0
	visual.add_child(plate)
	var outline := Line2D.new()
	outline.name = "PixelLootOutline"
	outline.points = PackedVector2Array([
		Vector2(-half_width + 3, 6), Vector2(half_width - 3, 6),
		Vector2(half_width, 9), Vector2(half_width - 3, 12),
		Vector2(-half_width + 3, 12), Vector2(-half_width, 9), Vector2(-half_width + 3, 6),
	])
	outline.width = 1.5
	outline.default_color = color
	outline.antialiased = false
	outline.z_index = 1
	visual.add_child(outline)
	_build_loot_particles(visual, color)
	_build_spawn_burst(visual, color)

func _build_loot_particles(visual: Node2D, color: Color) -> void:
	var particles := CPUParticles2D.new()
	particles.name = "LootAmbientParticles"
	particles.amount = int({"uncommon":2, "rare":3, "epic":4, "legendary":6, "mythic":9}.get(equipment.rarity, 2))
	particles.lifetime = 1.15
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = maxf(_icon_visual_size.x * 0.42, 7.0)
	particles.direction = Vector2(0, -1)
	particles.spread = 32.0
	particles.initial_velocity_min = 7.0
	particles.initial_velocity_max = 16.0
	particles.gravity = Vector2(0, 1.5)
	particles.color = Color(color.r, color.g, color.b, float({"uncommon":0.28, "rare":0.34, "epic":0.42, "legendary":0.52, "mythic":0.64}.get(equipment.rarity, 0.28)))
	particles.position = Vector2(0, _icon_visual_top + _icon_visual_size.y * 0.55)
	particles.z_index = 1
	visual.add_child(particles)

func _build_spawn_burst(visual: Node2D, color: Color) -> void:
	var burst := CPUParticles2D.new()
	burst.name = "LootSpawnBurst"
	burst.amount = int({"uncommon":3, "rare":4, "epic":5, "legendary":7, "mythic":9}.get(equipment.rarity, 3))
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.lifetime = 0.5
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = maxf(_icon_visual_size.x * 0.3, 6.0)
	burst.direction = Vector2(0, -1)
	burst.spread = 72.0
	burst.initial_velocity_min = 18.0
	burst.initial_velocity_max = 30.0
	burst.gravity = Vector2(0, 12)
	burst.color = Color(color.r, color.g, color.b, 0.88)
	burst.position = Vector2(0, _icon_visual_top + _icon_visual_size.y * 0.55)
	burst.z_index = 3
	visual.add_child(burst)
	burst.emitting = true

func _ellipse_points(half_width: float, half_height: float, center_y: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in 24:
		var angle := TAU * float(index) / 24.0
		points.append(Vector2(cos(angle) * half_width, sin(angle) * half_height + center_y))
	return points

func _get_beam_length() -> float:
	return 0.0

func _get_player_visual_height() -> float:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or player.animated_sprite == null:
		return 32.0
	var sprite := player.animated_sprite
	var frames := sprite.sprite_frames
	if frames == null or not frames.has_animation(sprite.animation):
		return 32.0
	var texture := frames.get_frame_texture(sprite.animation, sprite.frame)
	if texture == null:
		return 32.0
	var image := texture.get_image()
	if image == null:
		return 32.0
	var used := image.get_used_rect()
	if used.size.y <= 0:
		return 32.0
	return clampf(float(used.size.y) * absf(sprite.global_scale.y), 24.0, 56.0)

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_player = body
		_player.register_ground_equipment(self)
		_set_nearby_visible(true)

func _on_body_exited(body: Node2D) -> void:
	if body == _player:
		_player.unregister_ground_equipment(self)
		_player = null
		_set_nearby_visible(false)

func _set_nearby_visible(value: bool) -> void:
	var visual := get_node_or_null("Visual")
	if visual:
		visual.get_node("ItemLabel").visible = value
		visual.get_node("Prompt").visible = value

func collect(player: Player) -> bool:
	if equipment == null or player == null:
		return false
	var component := player.get_node_or_null("EquipmentComponent") as EquipmentComponent
	if component == null:
		return false
	component.add_item(equipment)
	player.unregister_ground_equipment(self)
	queue_free()
	return true
