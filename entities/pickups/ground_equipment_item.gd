extends Area2D
class_name GroundEquipmentItem
## 地面に残り、近距離で名前と取得プロンプトを表示する手動取得装備。
## 見せ方はDiablo系：レア度色の光の柱、名札（レア以上は常時）、落下して弾む着地、
## 伝説以上は着地の閃光と鐘の音。

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
## 落下アニメーション（生成時に上から落ちて弾む）。テストや静止配置では切れる。
@export var drop_animation: bool = true
const BEAM_HEIGHT := {"uncommon": 56.0, "rare": 84.0, "epic": 112.0, "legendary": 144.0, "mythic": 168.0}
const BEAM_WIDTH := {"uncommon": 7.0, "rare": 9.0, "epic": 12.0, "legendary": 16.0, "mythic": 20.0}
var _beam: LootBeam
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
	_build_beam(visual)
	_build_icon(visual)
	_build_ground_effects(visual)
	_build_labels(visual)
	_set_nearby_visible(false)
	if drop_animation and spawned_at_usec > 0:
		_play_drop_arc(visual)

## レア度色の光の柱。アイコンの後ろから立ち上がり、ゆっくり明滅する。
class LootBeam extends Node2D:
	var color := Color.WHITE
	var height := 60.0
	var width := 8.0
	var reveal := 1.0
	var _phase := 0.0
	func _ready() -> void:
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		self.material = material
	func _process(delta: float) -> void:
		_phase += delta
		queue_redraw()
	func _draw() -> void:
		var h := height * reveal
		if h < 2.0:
			return
		var pulse := 0.8 + 0.2 * sin(_phase * 2.4)
		var w := width
		# 外側の柔らかい光 → 本体 → 白い芯。上へ行くほど薄く、4px 刻みの段にする。
		var steps := int(h / 4.0)
		for step in steps:
			var t := float(step) / float(maxi(steps - 1, 1))
			var fade := (1.0 - t) * (1.0 - t * 0.6)
			var y := -4.0 * (step + 1)
			draw_rect(Rect2(-w * 1.6, y, w * 3.2, 4.0), Color(color, 0.10 * fade * pulse))
			draw_rect(Rect2(-w, y, w * 2.0, 4.0), Color(color, 0.28 * fade * pulse))
			draw_rect(Rect2(-w * 0.45, y, w * 0.9, 4.0), Color(color.lightened(0.35), 0.5 * fade * pulse))
			draw_rect(Rect2(-1.0, y, 2.0, 4.0), Color(color.lightened(0.8), 0.75 * fade * pulse))
		# 根元の光だまり（楕円）
		for ring in 3:
			var rw := w * (3.4 - ring * 0.9)
			draw_rect(Rect2(-rw, -2.0 - ring, rw * 2.0, 2.0 + ring * 2.0), Color(color, (0.10 + ring * 0.08) * pulse))

func _build_beam(visual: Node2D) -> void:
	_beam = LootBeam.new()
	_beam.name = "LootBeam"
	_beam.color = equipment.get_rarity_color()
	_beam.height = float(BEAM_HEIGHT.get(equipment.rarity, 60.0))
	_beam.width = float(BEAM_WIDTH.get(equipment.rarity, 8.0))
	_beam.position = Vector2(0, 6)
	_beam.z_index = 0
	visual.add_child(_beam)

## 落下：少し上から落ちて弾み、着地で柱が立つ。伝説以上は閃光と鐘。
func _play_drop_arc(visual: Node2D) -> void:
	var rank := _rarity_rank()
	visual.position = Vector2(0, -44)
	visual.scale = Vector2(0.55, 0.55)
	if _beam:
		_beam.reveal = 0.0
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(visual, "position", Vector2.ZERO, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_callback(_on_landed.bind(rank))
	if _beam:
		tween.tween_property(_beam, "reveal", 1.0, 0.28 + rank * 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_landed(rank: int) -> void:
	if not is_inside_tree():
		return
	if rank >= 4:
		AudioManager.play_sfx("legendary_drop")
		var flash := PixelSpriteVFX.spawn(self, global_position + Vector2(0, -_icon_visual_size.y * 0.4), "hit_light", Vector2.ONE * (72.0 + rank * 10.0), 0.42, 0.0, equipment.get_rarity_color().lightened(0.5))
		if flash:
			flash.name = "LandingFlash"
			flash.z_index = 4

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
	var color := equipment.get_rarity_color()
	# 名札：暗い板にレア度色の左帯と文字。レア以上は常時表示、アンコモンは近づいた時だけ。
	var label := Label.new()
	label.name = "ItemLabel"
	label.text = "%s　%s" % [equipment.display_name, equipment.get_rarity_display_name().get_slice(" / ", 1)]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color.lightened(0.18))
	label.add_theme_color_override("font_outline_color", Color("0b0c13"))
	label.add_theme_constant_override("outline_size", 3)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.04, 0.045, 0.07, 0.82)
	plate.border_color = Color(color, 0.9)
	plate.border_width_left = 3
	plate.border_width_top = 1
	plate.border_width_bottom = 1
	plate.border_width_right = 1
	plate.content_margin_left = 8
	plate.content_margin_right = 8
	plate.content_margin_top = 1
	plate.content_margin_bottom = 1
	plate.anti_aliasing = false
	label.add_theme_stylebox_override("normal", plate)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	visual.add_child(label)
	label.size = label.get_minimum_size()
	label.position = Vector2(-floorf(label.size.x * 0.5), _icon_visual_top - 24.0 - label.size.y)
	var prompt := Label.new()
	prompt.name = "Prompt"
	prompt.text = "E / X：拾う"
	prompt.add_theme_font_size_override("font_size", 13)
	prompt.add_theme_color_override("font_color", Color("fff0c7"))
	prompt.add_theme_color_override("font_outline_color", Color("10121d"))
	prompt.add_theme_constant_override("outline_size", 4)
	prompt.position = Vector2(-80, 12.0)
	prompt.size = Vector2(160, 20)
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
			# レア以上は常時表示。近づくと明るく、離れると少し沈む。
			var always := _rarity_rank() >= 2
			item_label.visible = value or always
			item_label.modulate = Color.WHITE if value else Color(0.8, 0.8, 0.8, 0.85)
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
