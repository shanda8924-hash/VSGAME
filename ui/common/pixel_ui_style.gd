extends RefCounted
class_name PixelUIStyle
## VSGAMEのControlを同じPixel UI文法へ揃える軽量Style Factory。
## Gameplay/UI構造は変えず、角丸・Gradient・曖昧な状態差だけを排除する。

const BG := Color("090d13")
const PANEL_BG := Color("111821")
const PANEL_INSET := Color("0b1017")
const BORDER := Color("40546b")
const BORDER_HOVER := Color("79d7e8")
const TEXT := Color("e7edf2")
const TEXT_MUTED := Color("91a0ad")
const DISABLED := Color("59636c")
const SHADOW := Color(0.0, 0.0, 0.0, 0.82)
const DANGER := Color("ff5c55")

static var _shared_theme: Theme


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
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_shadow_color", "Label", SHADOW)
	theme.set_constant("shadow_offset_x", "Label", 2)
	theme.set_constant("shadow_offset_y", "Label", 2)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color("bcecf2"))
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", DISABLED)
	theme.set_stylebox("normal", "Button", _button_box(BORDER, PANEL_BG, false))
	theme.set_stylebox("hover", "Button", _button_box(BORDER_HOVER, Color("182530"), false))
	theme.set_stylebox("pressed", "Button", _button_box(BORDER_HOVER, PANEL_INSET, true))
	theme.set_stylebox("focus", "Button", _button_box(Color("f2c14e"), Color("16202a"), false, 4))
	theme.set_stylebox("disabled", "Button", _button_box(Color("303944"), Color("0d1218"), false))
	theme.set_stylebox("panel", "Panel", _panel_box(BORDER))
	theme.set_stylebox("panel", "PanelContainer", _panel_box(BORDER))
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
	button.add_theme_stylebox_override("normal", _button_box(resolved, PANEL_BG, false))
	button.add_theme_stylebox_override("hover", _button_box(resolved.lightened(0.24), Color("182530"), false))
	button.add_theme_stylebox_override("pressed", _button_box(resolved.lightened(0.12), PANEL_INSET, true))
	button.add_theme_stylebox_override("focus", _button_box(Color("f2c14e"), Color("16202a"), false, 4))
	button.add_theme_stylebox_override("disabled", _button_box(Color("303944"), Color("0d1218"), false))
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color("bcecf2"))
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", DISABLED)
	button.add_theme_constant_override("outline_size", 2)
	button.add_theme_color_override("font_outline_color", Color("020304"))
	button.set_meta("pixel_ui", true)


static func apply_panel(panel: Control, accent: Color = BORDER, inset: bool = false) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", _panel_box(accent, inset))
	panel.set_meta("pixel_ui", true)


static func apply_progress_bar(bar: ProgressBar, fill_color: Color = Color("72d7e8")) -> void:
	if bar == null:
		return
	bar.add_theme_stylebox_override("background", _bar_box(Color("283441"), Color("080b0f")))
	bar.add_theme_stylebox_override("fill", _bar_box(fill_color.darkened(0.32), fill_color))
	bar.set_meta("pixel_ui", true)


static func _button_box(accent: Color, fill: Color, pressed: bool, border_width: int = 3) -> StyleBoxFlat:
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


static func _panel_box(accent: Color, inset: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_INSET if inset else PANEL_BG
	style.border_color = accent if accent.a > 0.0 else BORDER
	style.set_border_width_all(3)
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
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	return style


static func _existing_border(control: Control, style_name: String, fallback: Color) -> Color:
	if control.has_theme_stylebox_override(style_name):
		var style := control.get_theme_stylebox(style_name)
		if style is StyleBoxFlat and (style as StyleBoxFlat).border_color.a > 0.0:
			return (style as StyleBoxFlat).border_color
	return fallback
