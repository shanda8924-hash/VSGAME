extends Area2D
class_name GroundEquipmentItem
## 地面に残り、近距離で名前と取得プロンプトを表示する手動取得装備。

@export var pickup_radius: float = 72.0
const ICON_HEIGHT_RATIO := 0.82
const ICON_HEIGHT_MIN := 24.0
const ICON_HEIGHT_MAX := 42.0
const ICON_METRICS := preload("res://resources/equipment_icon_metrics.gd")
const LOOT_SEAL_TEXTURE_PATH := "res://assets/vfx/pixel/loot_seal.png"
static var _icon_used_rect_cache: Dictionary = {}
static var _icon_image_read_count: int = 0
var equipment: EquipmentData
var _player: Player
var _icon_visual_size := Vector2(28.0, 28.0)
var _icon_visual_top := -24.0
var spawned_at_usec: int = 0
var cap_expiration_pending := false
var _cap_expiration_tween: Tween

func setup(item: EquipmentData) -> void:
	equipment = item
	spawned_at_usec = Time.get_ticks_usec()

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

func _build_icon(visual: Node2D) -> void:
	if equipment.icon_path != "" and ResourceLoader.exists(equipment.icon_path):
		var icon := Sprite2D.new()
		icon.name = "EquipmentIcon"
		icon.texture = load(equipment.icon_path)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var used := _get_cached_icon_used_rect(equipment.icon_path, icon.texture)
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
	if visual.get_node_or_null("ItemLabel") != null:
		return
	var beam_length := _get_beam_length()
	var label := Label.new()
	label.name = "ItemLabel"
	label.text = "%s\n%s" % [equipment.display_name, equipment.get_rarity_display_name().get_slice(" / ", 1)]
	label.position = Vector2(-110, _icon_visual_top - beam_length - 48.0)
	label.size = Vector2(220, 42)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", equipment.get_rarity_color())
	label.add_theme_color_override("font_outline_color", Color("10121d"))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	visual.add_child(label)
	var prompt := Label.new()
	prompt.name = "Prompt"
	prompt.text = "E / X：拾う"
	prompt.add_theme_color_override("font_color", Color("fff0c7"))
	prompt.add_theme_color_override("font_outline_color", Color("10121d"))
	prompt.add_theme_constant_override("outline_size", 4)
	prompt.position = Vector2(-80, _icon_visual_top - 28.0)
	prompt.size = Vector2(160, 24)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.visible = false
	visual.add_child(prompt)

func _build_ground_effects(visual: Node2D) -> void:
	var color := equipment.get_rarity_color()
	var rank := _rarity_rank()
	# 台座/輪郭/刻印/2Emitterを、生成画像の静止紋章＋0.7秒の6コマへ統合。
	# 常駐VFXはSprite1枚だけ。希少度は既存の色と段階的な大きさで区別する。
	var width := clampf(_icon_visual_size.x + 18.0, 36.0, 52.0) + rank * 2.0
	var seal := Sprite2D.new()
	seal.name = "RoyalLootSeal"
	seal.texture = load(LOOT_SEAL_TEXTURE_PATH) as Texture2D
	seal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	seal.modulate = color
	seal.scale = Vector2(width, width * 0.5) / float(seal.texture.get_width())
	seal.position = Vector2(0, 8)
	seal.z_index = 1
	visual.add_child(seal)
	var awakening := PixelSpriteVFX.spawn(visual, visual.global_position + Vector2(0, -_icon_visual_size.y * 0.35), "loot_awaken", Vector2.ONE * (56.0 + rank * 4.0), 0.7, 0.0, color.lightened(0.75))
	if awakening != null:
		awakening.name = "LootAwakening"
		awakening.z_index = 3

func _rarity_rank() -> int:
	return int({"uncommon":1, "rare":2, "epic":3, "legendary":4, "mythic":5}.get(equipment.rarity, 1))

func _get_beam_length() -> float:
	return 0.0

func _get_player_visual_height() -> float:
	# AttackVFXManagerがPlayer接続時に一度だけ計算した値を共有し、Drop生成側からも
	# Sprite AtlasのGPU→CPU読み戻しを発生させない。
	var attack_vfx := get_tree().get_first_node_in_group("attack_vfx_manager") as AttackVFXManager
	if attack_vfx != null:
		return attack_vfx._get_player_visual_height()
	return 32.0

static func _get_cached_icon_used_rect(icon_path: String, texture: Texture2D) -> Rect2i:
	if _icon_used_rect_cache.has(icon_path):
		return _icon_used_rect_cache[icon_path] as Rect2i
	var fallback := Rect2i(0, 0, texture.get_width(), texture.get_height())
	# Boundsは新しいPNGを正規化するときにCPU上で保存する。
	# 初めて出た装備もGPU readbackせず、未知の画像は全体寸法で安全に表示する。
	var used: Rect2i = ICON_METRICS.BOUNDS.get(icon_path, fallback)
	if used.size.x <= 0 or used.size.y <= 0:
		used = fallback
	_icon_used_rect_cache[icon_path] = used
	return used

static func debug_reset_icon_read_cache() -> void:
	_icon_used_rect_cache.clear()
	_icon_image_read_count = 0

static func debug_get_icon_read_snapshot() -> Dictionary:
	return {"cached_paths": _icon_used_rect_cache.size(), "image_reads": _icon_image_read_count}

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_player = body
		_player.register_ground_equipment(self)
		var visual := get_node_or_null("Visual") as Node2D
		if visual != null:
			_build_labels(visual)
		_set_nearby_visible(true)

func _on_body_exited(body: Node2D) -> void:
	if body == _player:
		_player.unregister_ground_equipment(self)
		_player = null
		_set_nearby_visible(false)

func _set_nearby_visible(value: bool) -> void:
	var visual := get_node_or_null("Visual")
	if visual:
		var item_label := visual.get_node_or_null("ItemLabel") as Label
		var prompt := visual.get_node_or_null("Prompt") as Label
		if item_label != null:
			item_label.visible = value
		if prompt != null:
			prompt.visible = value

func begin_cap_expiration(warning_seconds: float) -> bool:
	if cap_expiration_pending or equipment == null or equipment.rarity not in ["uncommon", "rare", "epic"]:
		return false
	cap_expiration_pending = true
	var visual := get_node_or_null("Visual") as CanvasItem
	if visual == null or warning_seconds <= 0.0:
		_expire_from_cap()
		return true
	var blink_count := 5
	var half_blink := maxf(warning_seconds / float(blink_count * 2), 0.04)
	_cap_expiration_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for _blink in blink_count:
		_cap_expiration_tween.tween_property(visual, "modulate:a", 0.22, half_blink)
		_cap_expiration_tween.tween_property(visual, "modulate:a", 1.0, half_blink)
	_cap_expiration_tween.tween_callback(_expire_from_cap)
	return true

func _expire_from_cap() -> void:
	if is_inside_tree() and not is_queued_for_deletion():
		queue_free()

func _cancel_cap_expiration() -> void:
	if _cap_expiration_tween != null and _cap_expiration_tween.is_valid():
		_cap_expiration_tween.kill()
	_cap_expiration_tween = null
	cap_expiration_pending = false
	var visual := get_node_or_null("Visual") as CanvasItem
	if visual: visual.modulate.a = 1.0

func _exit_tree() -> void:
	_cancel_cap_expiration()

func collect(player: Player) -> bool:
	if equipment == null or player == null:
		return false
	var component := player.get_node_or_null("EquipmentComponent") as EquipmentComponent
	if component == null:
		return false
	if not component.add_item(equipment):
		return false
	player.unregister_ground_equipment(self)
	_cancel_cap_expiration()
	queue_free()
	return true
