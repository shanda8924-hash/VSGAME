extends RefCounted
## ComfyUI-authored thin metal/leather skin, shared by all game menus.
const PANEL_INSET := preload("res://assets/visuals/ember_v5/ui_inset.png")
const PANEL_OUTER := preload("res://assets/visuals/ember_v5/ui_panel.png")

static func box(inset: bool = false, margin: float = 16.0, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = PANEL_INSET if inset else PANEL_OUTER
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 3)
	style.modulate_color = tint
	style.set_content_margin_all(margin)
	return style

static func hide_old_ornament(host: Control) -> void:
	for name in ["RelicOrnamentLayer", "FrameArt", "PlaqueArt"]:
		var old := host.get_node_or_null(name) as CanvasItem
		if old: old.hide()

static func panel(host: Control, inset: bool = false, slot: bool = false) -> void:
	hide_old_ornament(host)
	# These framed hosts already provide their own MarginContainer/absolute layout.
	host.add_theme_stylebox_override("panel", box(inset or slot, 0))
	host.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

static func plaque(host: Control, _crest: bool = false) -> void:
	hide_old_ornament(host)
	if host is Button:
		for state in ["normal", "hover", "pressed", "disabled"]:
			var tint := Color(1.1,1.15,1.14) if state == "hover" else Color(.55,.55,.6) if state == "disabled" else Color.WHITE
			host.add_theme_stylebox_override(state,box(true,8,tint))
	elif host is Label:
		host.add_theme_stylebox_override("normal",box(true,8))
	else:
		host.add_theme_stylebox_override("panel",box(true,8))

class Seal extends Control:
	func _draw() -> void:
		var c := size * .5
		draw_line(Vector2(12,c.y),Vector2(c.x-16,c.y),Color("625869"),1,false)
		draw_line(Vector2(c.x+16,c.y),Vector2(size.x-12,c.y),Color("625869"),1,false)
		draw_colored_polygon(PackedVector2Array([c+Vector2(0,-8),c+Vector2(6,0),c+Vector2(0,8),c+Vector2(-6,0)]),Color("8cbaa9"))
		draw_line(c+Vector2(0,-5),c+Vector2(-3,0),Color("d3dfd2"),1,false)

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
	var names := {"weapon":"wanderer_iron_sword","head":"leather_scout_cap","body":"traveler_leather_coat","arms":"scout_gloves","legs":"windrunner_boots","accessory":"amethyst_ring"}
	var path := "res://assets/visuals/ember_v5/equipment/%s.png" % names.get(slot,"")
	if not ResourceLoader.exists(path): return
	var art := TextureRect.new()
	art.texture = load(path)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.modulate = Color(.7,.72,.77)
	host.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_left = 9
	art.offset_top = 6
	art.offset_right = -9
	art.offset_bottom = -6
