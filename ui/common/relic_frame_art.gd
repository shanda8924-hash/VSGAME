extends RefCounted
## 石板と古金のUIスキン。tools/ui_unified/build.py が生成する assets/ui/stoneworks/ の
## 9-slice テクスチャを全メニューで共有する。マージン値は build.py の PARTS と同じ。
const ART := "res://assets/ui/stoneworks/"
const PANEL_MAJOR := preload("res://assets/ui/stoneworks/panel_major.png")
const PANEL_INSET := preload("res://assets/ui/stoneworks/panel_inset.png")
const BUTTON_NORMAL := preload("res://assets/ui/stoneworks/button_normal.png")
const BUTTON_HOVER := preload("res://assets/ui/stoneworks/button_hover.png")
const BUTTON_PRESSED := preload("res://assets/ui/stoneworks/button_pressed.png")
const BUTTON_DISABLED := preload("res://assets/ui/stoneworks/button_disabled.png")
const PLAQUE := preload("res://assets/ui/stoneworks/plaque.png")
const SLOT := preload("res://assets/ui/stoneworks/slot.png")
const WELL := preload("res://assets/ui/stoneworks/well.png")
const BAR_TRACK := preload("res://assets/ui/stoneworks/bar_track.png")
const BAR_FILL := preload("res://assets/ui/stoneworks/bar_fill.png")
const BACKDROP_TILE := preload("res://assets/ui/stoneworks/backdrop_tile.png")

# 名前 → [テクスチャ, 9-sliceマージン(px), 中央をタイルで繰り返すか, 内容の最小余白(px)]
const KINDS := {
	"major": [PANEL_MAJOR, 32, true, 0],
	"inset": [PANEL_INSET, 16, true, 0],
	"button_normal": [BUTTON_NORMAL, 16, true, 0],
	"button_hover": [BUTTON_HOVER, 16, true, 0],
	"button_pressed": [BUTTON_PRESSED, 16, true, 0],
	"button_disabled": [BUTTON_DISABLED, 16, true, 0],
	"plaque": [PLAQUE, 44, false, 0],
	"slot": [SLOT, 12, true, 0],
	"well": [WELL, 8, true, 0],
	"bar_track": [BAR_TRACK, 6, false, 0],
	"bar_fill": [BAR_FILL, 4, false, 0],
}

static func styled(kind: String, margin: float = 16.0, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var spec: Array = KINDS[kind]
	var style := StyleBoxTexture.new()
	style.texture = spec[0]
	var texture_margin := int(spec[1])
	if kind == "plaque":
		style.texture_margin_left = texture_margin
		style.texture_margin_right = texture_margin
		style.texture_margin_top = 10
		style.texture_margin_bottom = 10
	else:
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			style.set_texture_margin(side, texture_margin)
	if spec[2]:
		style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.modulate_color = tint
	style.set_content_margin_all(margin)
	if kind == "plaque":
		style.content_margin_left = maxf(margin, 48.0)
		style.content_margin_right = maxf(margin, 48.0)
		style.content_margin_top = minf(margin, 8.0)
		style.content_margin_bottom = minf(margin, 8.0)
	return style

## 旧API互換。inset=false は大パネル（石のレール＋金の角金具）、true は内側パネル。
static func box(inset: bool = false, margin: float = 16.0, tint: Color = Color.WHITE) -> StyleBoxTexture:
	return styled("inset" if inset else "major", margin, tint)

## 区画の窪み（金具なし）。カードの中の小区画など、枠を重ねたくない所に使う。
static func well_box(margin: float = 8.0, tint: Color = Color.WHITE) -> StyleBoxTexture:
	return styled("well", margin, tint)

static func button_box(state: String, margin: float = 12.0, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var style := styled("button_" + state, margin, tint)
	# 押し込み時は中身を 1px 右下へ
	if state == "pressed":
		style.content_margin_left = margin + 1.0
		style.content_margin_top = margin + 1.0
		style.content_margin_right = margin - 1.0
		style.content_margin_bottom = margin - 1.0
	return style

static func bar_box(fill: bool, color: Color = Color.WHITE) -> StyleBoxTexture:
	var style := styled("bar_fill" if fill else "bar_track", 0.0, color)
	style.set_content_margin_all(2.0 if fill else 3.0)
	return style

static func backdrop_style(tint: Color = Color(1, 1, 1, 0.92)) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = BACKDROP_TILE
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.modulate_color = tint
	style.set_content_margin_all(0.0)
	return style

static func hide_old_ornament(host: Control) -> void:
	for name in ["RelicOrnamentLayer", "FrameArt", "PlaqueArt"]:
		var old := host.get_node_or_null(name) as CanvasItem
		if old: old.hide()

## 枠だけを付ける（中身の余白は呼び出し側の MarginContainer に任せる）。
## inset=内側パネル、slot=所持品のマス。
static func panel(host: Control, inset: bool = false, slot: bool = false) -> void:
	hide_old_ornament(host)
	host.add_theme_stylebox_override("panel", styled("slot", 4) if slot else box(inset, 0))
	host.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## 見出しの板（槍頭の金具付き）。Button なら状態ごとのボタン板にする。
static func plaque(host: Control, _crest: bool = false) -> void:
	hide_old_ornament(host)
	if host is Button:
		host.add_theme_stylebox_override("normal", button_box("normal", 8))
		host.add_theme_stylebox_override("hover", button_box("hover", 8))
		host.add_theme_stylebox_override("pressed", button_box("pressed", 8))
		host.add_theme_stylebox_override("disabled", button_box("disabled", 8))
	elif host is Label:
		host.add_theme_stylebox_override("normal", styled("plaque", 8))
	else:
		host.add_theme_stylebox_override("panel", styled("plaque", 8))
	host.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

class Seal extends Control:
	func _draw() -> void:
		var c := size * .5
		var gold := Color("cf9a34")
		var gold_light := Color("f0cc62")
		var gold_dark := Color("5a3c10")
		var teal := Color("4fb3b8")
		# 左右の飾り線（二重）
		for side: float in [-1.0, 1.0]:
			var x0: float = c.x + side * 22.0
			var x1: float = c.x + side * (c.x - 12.0)
			draw_line(Vector2(x0, c.y), Vector2(x1, c.y), gold_dark, 3, false)
			draw_line(Vector2(x0, c.y - 1), Vector2(x1, c.y - 1), gold, 1, false)
			# 線の先の小さな菱形
			draw_colored_polygon(PackedVector2Array([Vector2(x1, c.y - 4), Vector2(x1 + side * 4, c.y), Vector2(x1, c.y + 4), Vector2(x1 - side * 4, c.y)]), gold)
		# 中央の紋章：金の菱形に封印石
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -13), c + Vector2(13, 0), c + Vector2(0, 13), c + Vector2(-13, 0)]), gold_dark)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -11), c + Vector2(11, 0), c + Vector2(0, 11), c + Vector2(-11, 0)]), gold)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, 0), c + Vector2(0, 7), c + Vector2(-7, 0)]), Color("12212f"))
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)]), teal)
		draw_rect(Rect2(c + Vector2(-2, -4), Vector2(2, 2)), Color("e4fff0"))
		draw_line(c + Vector2(-10, -1), c + Vector2(0, -11), gold_light, 1, false)

static func emblem(host: Control, _skull: bool = false) -> Control:
	hide_old_ornament(host)
	if host.has_node("CraftedEmblem"): return host.get_node("CraftedEmblem")
	var art := Seal.new()
	art.name = "CraftedEmblem"
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.resized.connect(art.queue_redraw)
	return art

static func part_icon(host: Button, slot: String) -> void:
	var paths := {"weapon":"res://assets/items/weapons/weapon_sword_uncommon_001.png","head":"res://assets/items/head/head_cap_uncommon_001.png","body":"res://assets/items/body/body_coat_uncommon_001.png","arms":"res://assets/items/arms/arms_gloves_uncommon_001.png","legs":"res://assets/items/legs/legs_boots_rare_001.png","accessory":"res://assets/items/accessories/accessory_ring_epic_001.png"}
	var path: String = paths.get(slot, "")
	if path == "" or not ResourceLoader.exists(path): return
	var art := TextureRect.new()
	art.texture = load(path)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.modulate = Color(.78, .8, .86)
	host.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_left = 7
	art.offset_top = 5
	art.offset_right = -7
	art.offset_bottom = -5
