extends RefCounted
class_name PixelUIStyle
const FrameArt := preload("res://ui/common/relic_frame_art.gd")
## 朽ちた王宮の石板・古金の金具・封印石の青緑を共通UI文法にする。

const BG := Color("10151c")
const PANEL_BG := Color("1b1924")
const PANEL_RAISED := Color("2d2533")
const PANEL_INSET := Color("11151b")
const STONE := Color("65606e")
const STONE_DARK := Color("3c3d49")
const BORDER := Color("8c7765")
const BORDER_HOVER := Color("c2aa84")
const TEXT := Color("e5e2d5")
const TEXT_MUTED := Color("a9aeb8")
const DISABLED := Color("8b94a0")
const SHADOW := Color(0.0, 0.0, 0.0, 0.86)
const DANGER := Color("ff5c55")
const JEWEL := Color("7abeb6")
const JEWEL_DARK := Color("285f65")

static var _shared_theme: Theme


## 整数座標だけで描く軽量装飾。常時processを使わず、サイズ・選択変更時だけ再描画する。
class RelicOrnament extends Control:
	var kind := "section"
	var accent := Color("c2aa84")
	var host: Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		resized.connect(queue_redraw)

	func _diamond(center: Vector2, radius: int, color: Color) -> void:
		for y in range(-radius, radius + 1, 2):
			var half := radius - absi(y)
			draw_rect(Rect2(center + Vector2(-half, y), Vector2(maxi(2, half * 2), 2)), color)

	func _rivet(position: Vector2, color: Color) -> void:
		draw_rect(Rect2(position - Vector2(2, 2), Vector2(4, 4)), color.darkened(0.55))
		draw_rect(Rect2(position - Vector2(1, 1), Vector2(2, 2)), color.lightened(0.22))

	func _corner_bracket(corner: Vector2, sx: float, sy: float, color: Color, reach: float = 25.0) -> void:
		draw_line(corner, corner + Vector2(sx * reach, 0), color, 2, false)
		draw_line(corner, corner + Vector2(0, sy * reach), color, 2, false)
		draw_line(corner + Vector2(sx * 4, sy * 4), corner + Vector2(sx * 13, sy * 4), color.darkened(0.38), 2, false)
		draw_line(corner + Vector2(sx * 4, sy * 4), corner + Vector2(sx * 4, sy * 13), color.darkened(0.38), 2, false)
		_rivet(corner + Vector2(sx * 2, sy * 2), color)

	func _draw() -> void:
		var w := floorf(size.x)
		var h := floorf(size.y)
		if w < 20 or h < 20:
			return
		if kind == "emblem":
			_draw_emblem(w, h)
			return
		if kind == "backdrop":
			_draw_backdrop(w, h)
			return
		if kind == "card":
			_draw_card(w, h)
			return
		if kind == "portrait_card":
			_draw_portrait_card(w, h)
			return
		if kind == "major_panel":
			_draw_major_panel(w, h)
			return
		_draw_section(w, h)

	func _draw_emblem(w: float, h: float) -> void:
		var center := Vector2(floorf(w * 0.5), floorf(h * 0.5))
		for side in [-1.0, 1.0]:
			for feather in 4:
				var reach := 28.0 + feather * 13.0
				draw_line(center + Vector2(side * reach, 8 - feather * 2), center + Vector2(side * (reach + 17), -12 + feather * 2), accent.darkened(0.12 + feather * 0.1), 3, false)
			draw_line(center + Vector2(side * 31, 13), center + Vector2(side * 106, 13), accent.darkened(0.58), 2, false)
		_diamond(center, 27, accent.darkened(0.58))
		_diamond(center, 23, accent)
		_diamond(center, 17, Color("12212f"))
		_diamond(center, 11, JEWEL)
		_diamond(center + Vector2(-2, -2), 4, Color("e6ffe8"))
		draw_rect(Rect2(center + Vector2(-8, -34), Vector2(16, 5)), accent)
		draw_rect(Rect2(center + Vector2(-3, 28), Vector2(6, 8)), accent.darkened(0.25))

	func _draw_backdrop(w: float, h: float) -> void:
		draw_rect(Rect2(0,0,w,h),Color(.035,.045,.065,.38))

	func _draw_card(w: float, h: float) -> void:
		var button := host as Button
		var selected := button != null and (button.has_focus() or button.is_hovered())
		var header := Color("25394d") if selected else Color("1a2a3a")
		draw_rect(Rect2(7, 7, w - 14, 96), header)
		draw_rect(Rect2(7, h - 46, w - 14, 39), Color("0c1622"))
		draw_rect(Rect2(18, 102, w - 36, 2), accent.darkened(0.42))
		draw_rect(Rect2(18, 106, w - 36, 1), Color("2f4658"))
		# アイコン背面の菱形は置かない。絵そのものの輪郭と重心を見せる。
		draw_rect(Rect2(14, 15, 3, 74), accent.darkened(0.18))
		draw_rect(Rect2(18, 15, 1, 74), accent.darkened(0.56))
		for x in range(28, int(w - 24), 48):
			draw_rect(Rect2(x, h - 14, 10, 1), accent.darkened(0.68))
		if selected:
			draw_rect(Rect2(0, 0, 5, h), accent)
			draw_rect(Rect2(5, 0, w - 5, 2), accent.lightened(0.18))
			_rivet(Vector2(w - 18, 20), Color("fff1c7"))
		_draw_card_corners(w, h)

	func _draw_portrait_card(w: float, h: float) -> void:
		var button := host as Button
		var selected := button != null and (button.has_focus() or button.is_hovered())
		draw_rect(Rect2(7, 7, w - 14, h - 14), Color("182737") if selected else Color("111c29"))
		draw_rect(Rect2(18, 18, w - 36, 226), Color("0a121c"))
		draw_rect(Rect2(20, 20, w - 40, 222), Color("1b2c3c"), false, 2)
		draw_rect(Rect2(7, h - 86, w - 14, 79), Color("0c1622"))
		draw_rect(Rect2(22, h - 90, w - 44, 2), accent.darkened(0.38))
		if selected:
			draw_rect(Rect2(0, 0, 5, h), accent)
			draw_rect(Rect2(5, 0, w - 5, 2), accent.lightened(0.15))
		_draw_card_corners(w, h)

	func _draw_card_corners(w: float, h: float) -> void:
		for data in [
			[Vector2(9, 9), 1.0, 1.0], [Vector2(w - 9, 9), -1.0, 1.0],
			[Vector2(9, h - 9), 1.0, -1.0], [Vector2(w - 9, h - 9), -1.0, -1.0],
		]:
			_corner_bracket(data[0], data[1], data[2], accent.darkened(0.08), 22.0)

	func _draw_major_panel(w: float, h: float) -> void:
		for data in [
			[Vector2(12, 12), 1.0, 1.0], [Vector2(w - 12, 12), -1.0, 1.0],
			[Vector2(12, h - 12), 1.0, -1.0], [Vector2(w - 12, h - 12), -1.0, -1.0],
		]:
			_corner_bracket(data[0], data[1], data[2], accent, 38.0)
		for y in [10.0, h - 10.0]:
			draw_rect(Rect2(w * 0.5 - 90, y - 2, 180, 4), Color("080f18"))
			draw_line(Vector2(w * 0.5 - 84, y), Vector2(w * 0.5 - 18, y), accent.darkened(0.26), 2, false)
			draw_line(Vector2(w * 0.5 + 18, y), Vector2(w * 0.5 + 84, y), accent.darkened(0.26), 2, false)
			_diamond(Vector2(floorf(w * 0.5), y), 10, accent)
			_diamond(Vector2(floorf(w * 0.5), y), 5, JEWEL)
			_diamond(Vector2(floorf(w * 0.5) - 1, y - 1), 2, Color("e4fff0"))

	func _draw_section(w: float, h: float) -> void:
		for data in [
			[Vector2(9, 9), 1.0, 1.0], [Vector2(w - 9, 9), -1.0, 1.0],
			[Vector2(9, h - 9), 1.0, -1.0], [Vector2(w - 9, h - 9), -1.0, -1.0],
		]:
			_corner_bracket(data[0], data[1], data[2], accent.darkened(0.25), 18.0)


static func add_ornament(host: Control, kind: String = "section", accent: Color = BORDER_HOVER) -> Control:
	if kind == "emblem":
		return FrameArt.emblem(host)
	if kind in ["major_panel", "section", "card", "portrait_card"]:
		FrameArt.hide_old_ornament(host)
		return host
	var existing := host.get_node_or_null("RelicOrnamentLayer/RelicOrnament") as RelicOrnament
	if existing:
		existing.kind = kind
		existing.accent = accent
		existing.host = host
		existing.queue_redraw()
		return existing
	var layer := Node2D.new()
	layer.name = "RelicOrnamentLayer"
	host.add_child(layer)
	var ornament := RelicOrnament.new()
	ornament.name = "RelicOrnament"
	ornament.kind = kind
	ornament.accent = accent
	ornament.host = host
	ornament.size = host.size
	layer.add_child(ornament)
	host.resized.connect(func(): ornament.size = host.size)
	if host is Button:
		(host as Button).focus_entered.connect(ornament.queue_redraw)
		(host as Button).focus_exited.connect(ornament.queue_redraw)
		host.mouse_entered.connect(ornament.queue_redraw)
		host.mouse_exited.connect(ornament.queue_redraw)
	return ornament


static func apply_tree(root: Node) -> void:
	if root == null:
		return
	var controls: Array[Control] = []
	if root is Control:
		controls.append(root as Control)
	for node in root.find_children("*", "Control", true, false):
		controls.append(node as Control)
	for control in controls:
		if not (control.get_parent() is Control):
			control.theme = shared_theme()
		if control is Label or control is Button:
			control.add_theme_font_size_override("font_size", maxi(control.get_theme_font_size("font_size"), 18))
			control.add_theme_constant_override("outline_size", 0)
		elif control is RichTextLabel:
			control.add_theme_font_size_override("normal_font_size", maxi(control.get_theme_font_size("normal_font_size"), 20))
		if control is Button:
			var button := control as Button
			apply_button(button, _existing_border(button, "normal", BORDER))
		elif control is PanelContainer:
			var panel := control as PanelContainer
			apply_panel(panel, _existing_border(panel, "panel", BORDER))
		elif control is Panel:
			var panel := control as Panel
			apply_panel(panel, _existing_border(panel, "panel", BORDER))
		elif control is ProgressBar:
			apply_progress_bar(control as ProgressBar)


static func shared_theme() -> Theme:
	if _shared_theme:
		return _shared_theme
	var theme := Theme.new()
	theme.default_font_size = 20
	var font := RetroHUDStyle.retro_font()
	if font:
		theme.default_font = font
		for role in ["normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"]:
			theme.set_font(role, "RichTextLabel", font)
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_shadow_color", "Label", SHADOW)
	theme.set_constant("shadow_offset_x", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", 0)
	theme.set_constant("outline_size", "Label", 0)
	theme.set_color("default_color", "RichTextLabel", TEXT)
	theme.set_font_size("normal_font_size", "RichTextLabel", 20)
	theme.set_font_size("font_size", "TooltipLabel", 18)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color("bcecf2"))
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", DISABLED)
	theme.set_stylebox("normal", "Button", _button_box(BORDER, PANEL_BG, false))
	theme.set_stylebox("hover", "Button", _button_box(BORDER_HOVER, PANEL_RAISED, false))
	theme.set_stylebox("pressed", "Button", _button_box(BORDER_HOVER, PANEL_INSET, true))
	theme.set_stylebox("focus", "Button", _focus_box(BORDER_HOVER))
	theme.set_stylebox("disabled", "Button", _button_box(Color("303944"), Color("0b1119"), false))
	theme.set_stylebox("panel", "Panel", _section_box(BORDER, PANEL_BG))
	theme.set_stylebox("panel", "PanelContainer", _section_box(BORDER, PANEL_BG))
	theme.set_stylebox("background", "ProgressBar", _bar_box(Color("283441"), Color("080b0f")))
	theme.set_stylebox("fill", "ProgressBar", _bar_box(Color("7fd8e8"), Color("173c47")))
	theme.set_color("font_color", "ProgressBar", TEXT)
	theme.set_color("font_outline_color", "ProgressBar", Color.BLACK)
	theme.set_constant("outline_size", "ProgressBar", 2)
	_shared_theme = theme
	return _shared_theme


static func apply_button(button: Button, accent: Color = BORDER) -> void:
	if button == null:
		return
	var resolved := accent if accent.a > 0.0 else BORDER
	button.add_theme_stylebox_override("normal", _button_box(resolved.darkened(0.24), PANEL_BG, false))
	button.add_theme_stylebox_override("hover", _button_box(resolved.lightened(0.15), PANEL_RAISED, false))
	button.add_theme_stylebox_override("pressed", _button_box(resolved, PANEL_INSET, true))
	button.add_theme_stylebox_override("focus", _focus_box(resolved.lightened(0.2)))
	button.add_theme_stylebox_override("disabled", _button_box(Color("303944"), Color("0b1119"), false))
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color("d8f5f3"))
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", DISABLED)
	button.add_theme_constant_override("outline_size", 0)
	button.add_theme_font_size_override("font_size", maxi(button.get_theme_font_size("font_size"), 18))
	button.add_theme_stylebox_override("normal", FrameArt.box(true, 12, Color(0.85, 0.9, 1.0)))
	button.add_theme_stylebox_override("hover", FrameArt.box(true, 12, Color(1.15, 1.12, 1.0)))
	button.add_theme_stylebox_override("pressed", FrameArt.box(true, 12, Color(0.65, 0.95, 0.95)))
	button.add_theme_stylebox_override("disabled", FrameArt.box(true, 12, Color(0.42, 0.46, 0.5)))
	button.set_meta("pixel_ui", true)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


static func apply_tab(button: Button, selected: bool) -> void:
	var accent := BORDER_HOVER if selected else STONE
	apply_button(button, accent)
	button.add_theme_color_override("font_color", TEXT if selected else TEXT_MUTED)
	if selected:
		button.add_theme_stylebox_override("normal", FrameArt.box(true, 12, Color(1.15, 1.1, 0.9)))


static func apply_panel(panel: Control, accent: Color = BORDER, inset: bool = false) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", FrameArt.box(inset, 12))
	panel.set_meta("pixel_ui", true)
	if not inset:
		add_ornament(panel, "section", accent)


static func apply_major_panel(panel: Control, accent: Color = BORDER_HOVER) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", frame_style())
	panel.set_meta("pixel_ui", true)
	add_ornament(panel, "major_panel", accent)


static func apply_progress_bar(bar: ProgressBar, fill_color: Color = Color("72d7e8")) -> void:
	if bar == null:
		return
	bar.add_theme_stylebox_override("background", _bar_box(STONE_DARK, Color("070b10")))
	bar.add_theme_stylebox_override("fill", _bar_box(fill_color.darkened(0.38), fill_color))
	bar.set_meta("pixel_ui", true)


static func badge_style(accent: Color = BORDER_HOVER, fill: Color = PANEL_INSET) -> StyleBoxFlat:
	var style := _section_box(accent, fill, 1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.shadow_size = 2
	style.shadow_offset = Vector2(2, 2)
	return style


static func _button_box(accent: Color, fill: Color, pressed: bool, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = accent
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	style.shadow_color = SHADOW
	style.shadow_size = 3 if not pressed else 1
	style.shadow_offset = Vector2(3, 3) if not pressed else Vector2(1, 1)
	style.content_margin_left = 14.0 + (2.0 if pressed else 0.0)
	style.content_margin_right = 14.0 - (2.0 if pressed else 0.0)
	style.content_margin_top = 9.0 + (2.0 if pressed else 0.0)
	style.content_margin_bottom = 9.0 - (2.0 if pressed else 0.0)
	return style


static func _focus_box(accent: Color) -> StyleBoxFlat:
	var focus := _button_box(accent, Color(0, 0, 0, 0), false, 1)
	focus.draw_center = false
	focus.shadow_size = 0
	return focus


static func _section_box(accent: Color, fill: Color, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = accent if accent.a > 0.0 else BORDER
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	style.shadow_color = SHADOW
	style.shadow_size = 4
	style.shadow_offset = Vector2(4, 4)
	style.set_content_margin_all(12.0)
	return style


static func _bar_box(border: Color, fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	return style


static func _existing_border(control: Control, style_name: String, fallback: Color) -> Color:
	if control.has_theme_stylebox_override(style_name):
		var style := control.get_theme_stylebox(style_name)
		if style is StyleBoxFlat and (style as StyleBoxFlat).border_color.a > 0.0:
			return (style as StyleBoxFlat).border_color
	return fallback


static func frame_style() -> StyleBoxTexture:
	return FrameArt.box(false, 20)


static func localized_name(value: String) -> String:
	var pieces := value.split("/", false)
	return pieces[-1].strip_edges() if pieces.size() > 1 else value.strip_edges()


## Shop / LevelUp / 報酬共通カード。抽選や購入は呼び出し元の責務。
static func choice_card(category: String, title: String, description: String, icon: Texture2D, footer: String, accent: Color = BORDER_HOVER) -> Button:
	var display_title := localized_name(title)
	var button := Button.new()
	button.custom_minimum_size = Vector2(420, 250)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = "%s\n%s\n%s" % [display_title, description, footer]
	apply_button(button, accent.darkened(0.16))
	add_ornament(button, "card", accent)
	button.add_theme_stylebox_override("normal", FrameArt.box(false, 20))
	button.add_theme_stylebox_override("hover", FrameArt.box(false, 20, Color(1.1, 1.12, 1.0)))
	button.add_theme_stylebox_override("pressed", FrameArt.box(false, 20, Color(0.75, 1.0, 1.0)))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	button.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 88
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	if icon:
		var picture := TextureRect.new()
		picture.name = "CardIcon"
		picture.texture = icon
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.custom_minimum_size = Vector2(76, 76)
		picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(picture)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(heading)
	var kind_label := Label.new()
	kind_label.text = category
	kind_label.add_theme_font_size_override("font_size", 18)
	kind_label.add_theme_color_override("font_color", accent.lightened(0.08))
	heading.add_child(kind_label)
	var name_label := Label.new()
	name_label.name = "CardTitle"
	name_label.text = display_title
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_child(name_label)
	var cursor := Label.new()
	cursor.name = "CardCursor"
	cursor.text = "▶"
	cursor.add_theme_font_size_override("font_size", 18)
	cursor.add_theme_color_override("font_color", accent.lightened(0.12))
	cursor.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cursor.modulate.a = 0.0
	row.add_child(cursor)
	button.focus_entered.connect(func(): cursor.modulate.a = 1.0)
	button.focus_exited.connect(func(): cursor.modulate.a = 0.0)
	var body := Label.new()
	body.name = "CardDescription"
	body.text = description
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("font_size", 20)
	body.custom_minimum_size.y = 48
	body.max_lines_visible = 3
	body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(body)
	var bottom := Label.new()
	bottom.name = "CardFooter"
	bottom.text = footer
	bottom.add_theme_font_size_override("font_size", 20)
	bottom.add_theme_color_override("font_color", accent.lightened(0.08))
	bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(bottom)
	for child in button.find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.theme = shared_theme()
	return button
