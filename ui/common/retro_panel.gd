class_name RetroPanel
extends Control
## HUDの情報石板。厚い王宮枠はこの小数の重要パネルだけに使う。

@export var glow_enabled: bool = false # 既存Scene互換。Glowは描画しない。
var content: MarginContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", PixelUIStyle.frame_style())
	add_child(panel)
	PixelUIStyle.add_ornament(panel, "major_panel")
	content = MarginContainer.new()
	content.name = "Content"
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		content.add_theme_constant_override("margin_" + side, 12)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.theme = PixelUIStyle.shared_theme()
	add_child(content)
