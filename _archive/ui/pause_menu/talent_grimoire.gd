extends Control
## Read-only talent atlas. Progression continues through the existing level-up choices.
signal close_requested
signal records_requested

const INK := Color("342b29")
const MUTED := Color("776656")
const GOLD := Color("ab763b")
const TEAL := Color("236963")
const ROOT_ICON := "res://assets/ui/icons/battle_skills/talents/swordsman_root.png"
const BRANCHES := [
	{"id": "rengeki", "name": "乱撃派", "summary": "手数を重ね、連撃を極める", "titles": ["双連斬", "三連斬", "疾風", "終ノ連撃"], "ids": ["class_swordsman_school_rengeki", "class_swordsman_rengeki_lv3", "class_swordsman_rengeki_lv4", "class_swordsman_rengeki_lv5"]},
	{"id": "issen", "name": "一閃派", "summary": "間合いを制し、一撃を極める", "titles": ["剛剣", "間合い", "急所看破", "断命の一閃"], "ids": ["class_swordsman_school_issen", "class_swordsman_issen_lv3", "class_swordsman_issen_lv4", "class_swordsman_issen_lv5"]},
]

var opening := false
var _intro_tween: Tween
var _intro: Control
var _ink_viewport: SubViewport
const BookArt := preload("res://ui/pause_menu/book_opening_art.gd")
var canvas: Control
var detail: Control
var diagram: Control
var nodes: Array[Button] = []
var entries: Array[Dictionary] = []
var manager: WeaponManagerComponent
var school := "none"
var stage := 1
var character_id := "swordsman"
var selected_index := 0

class TalentSeal extends Button:
	var acquired := false
	var excluded := false
	var selected := false
	var tier := 1
	var art: Texture2D
	func _ready() -> void:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
	func _draw() -> void:
		var c := size / 2
		var r := size.x / 2 - 5
		var metal := Color("236963") if acquired else Color("8a745c")
		draw_circle(c + Vector2(1, 2), r + 1, Color(0.22, .16, .12, .18))
		draw_circle(c, r, Color("c8ceba") if acquired else Color("d9c8a8"))
		draw_arc(c, r, 0, TAU, 32, metal, 1, false)
		if selected or is_hovered():
			draw_arc(c, r + 4, 0, TAU, 32, Color("236963"), 1, false)
		if art:
			var tint := Color.WHITE if acquired else Color(0.65, 0.64, 0.58, 1)
			if excluded:
				tint = Color(0.34, 0.34, 0.32, 1)
			draw_texture_rect(art, Rect2(c - Vector2(23, 23), Vector2(46, 46)), false, tint)
		if not acquired:
			var p := c + Vector2(18, 18)
			draw_rect(Rect2(p - Vector2(5, 3), Vector2(10, 8)), Color("7a6a55"))
			draw_arc(p - Vector2(0, 3), 3, PI, TAU, 8, Color("7a6a55"), 1, false)
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 3)), Color("d9c8a8"))

class BranchInk extends Control:
	var paths: Array[PackedVector2Array] = []
	func _draw() -> void:
		for path in paths:
			draw_polyline(path, Color("8a745c"), 1, false)
			for p in [path[0], path[-1]]:
				draw_circle(p, 2, Color("8a745c"))

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = PixelUIStyle.shared_theme()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var black := ColorRect.new()
	black.color = Color(.025,.035,.05,.92)
	add_child(black)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ink_viewport = SubViewport.new()
	_ink_viewport.name = "PrintedPageViewport"
	_ink_viewport.size = Vector2i(1600, 900)
	_ink_viewport.transparent_bg = true
	_ink_viewport.gui_disable_input = true
	_ink_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_ink_viewport)
	canvas = Control.new()
	canvas.theme = theme
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.size = Vector2(1600, 900)
	add_child(canvas)
	diagram = Control.new()
	canvas.add_child(diagram)
	detail = Control.new()
	canvas.add_child(detail)
	_label(canvas, "天 賦 図", Rect2(392, 188, 340, 40), 30, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_label(canvas, "刻印の記録", Rect2(872, 188, 326, 40), 28, INK)
	var records := _button("探索記録", Rect2(234, 816, 170, 42))
	records.pressed.connect(func(): records_requested.emit())
	var close := _button("閉じる  [T / Esc]", Rect2(1110, 816, 265, 42))
	close.pressed.connect(func(): close_requested.emit())
	_label(canvas, "クリック・矢印キーで天賦を選択", Rect2(420, 823, 660, 30), 18, Color("d4c3a3"), HORIZONTAL_ALIGNMENT_CENTER)
	_intro = BookArt.new()
	_intro.name = "OpeningBook"
	add_child(_intro)
	# Keep the same open pages beneath their interactive ink.
	move_child(_intro, canvas.get_index())
	_intro.hide()
	resized.connect(_fit)
	_fit()

func _fit() -> void:
	if canvas == null: return
	var factor := minf(size.x / 1600.0, size.y / 900.0)
	var origin := (size - Vector2(1600, 900) * factor) / 2
	if canvas.get_parent() == _ink_viewport:
		canvas.scale = Vector2.ONE
		canvas.position = Vector2.ZERO
	else:
		canvas.scale = Vector2.ONE * factor
		canvas.position = origin
	_intro.size = Vector2(1200,720) * factor
	_intro.position = origin + Vector2(200,85) * factor
	# Crop the very same live controls to each paper rectangle in reference space.
	var reference := Vector2(1600, 900)
	var left: Rect2 = _intro.page_rect(true)
	var right: Rect2 = _intro.page_rect(false)
	_intro.left_ink_uv = Rect2((_intro.position - origin + left.position) / factor / reference, left.size / factor / reference)
	_intro.right_ink_uv = Rect2((_intro.position - origin + right.position) / factor / reference, right.size / factor / reference)

func refresh(weapon_manager: WeaponManagerComponent) -> void:
	manager = weapon_manager
	school = manager.get_class_school() if manager else "none"
	stage = manager.get_class_ability_level() if manager else 1
	character_id = manager.get_class_character_id() if manager else GameManager.selected_character_id
	for child in diagram.get_children():
		diagram.remove_child(child)
		child.queue_free()
	nodes.clear()
	entries.clear()
	var is_swordsman := character_id == "swordsman"
	var root_icon := ROOT_ICON if is_swordsman else "res://assets/ui/icons/battle_skills/upgrades/class_%s_lv2.png" % character_id
	_add_node({"title": "居合" if is_swordsman else "職業の起点", "icon": root_icon, "level": 1, "school": "", "desc": "通常攻撃の起点。流派を選び、職業強化を重ねることで技が成長します。" if is_swordsman else "現在の職業の記録です。分岐図は準備中です。"}, Vector2(550, 270))
	if is_swordsman:
		var ink := BranchInk.new()
		ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
		diagram.add_child(ink)
		diagram.move_child(ink, 0)
		for branch_index in 2:
			var branch: Dictionary = BRANCHES[branch_index]
			var x := 428.0 if branch_index == 0 else 672.0
			ink.paths.append(PackedVector2Array([Vector2(550, 310), Vector2(550, 326), Vector2(x, 326)]))
			_label(diagram, branch.name, Rect2(x - 64, 338, 128, 30), 21, INK, HORIZONTAL_ALIGNMENT_CENTER)
			for i in 4:
				var upgrade: UpgradeData = DataLoader.upgrades.get(String(branch.ids[i]))
				var center := Vector2(x, 410 + i * 76)
				if i > 0:
					ink.paths.append(PackedVector2Array([center - Vector2(0, 43), center - Vector2(0, 33)]))
				_add_node({"title": branch.titles[i], "icon": upgrade.icon_path if upgrade else "", "level": i + 2, "school": branch.id, "desc": upgrade.description if upgrade else "効果情報を読み込めません。", "branch_name": branch.name, "summary": branch.summary}, center)
	else:
		_label(diagram, "この職業の分岐は準備中", Rect2(335, 424, 420, 42), 25, INK, HORIZONTAL_ALIGNMENT_CENTER)
		_label(diagram, "現在の職業と熟練段階は\n右ページで確認できます。", Rect2(340, 483, 400, 90), 20, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	for i in nodes.size():
		var above := 0 if i == 1 or i == 5 else maxi(0, i - 1)
		var below := i if i == 4 or i == 8 else mini(nodes.size() - 1, i + 1)
		nodes[i].focus_neighbor_top = nodes[above].get_path()
		nodes[i].focus_neighbor_bottom = nodes[below].get_path()
		if nodes.size() == 9 and i > 0:
			var other := i + 4 if i <= 4 else i - 4
			nodes[i].focus_neighbor_left = nodes[other].get_path()
			nodes[i].focus_neighbor_right = nodes[other].get_path()
	selected_index = clampi(selected_index, 0, nodes.size() - 1)
	_select(selected_index)

func focus_selected() -> void:
	if not opening and not nodes.is_empty():
		nodes[selected_index].grab_focus.call_deferred()

func _add_node(entry: Dictionary, center: Vector2) -> void:
	var node := TalentSeal.new()
	node.size = Vector2(78, 78) if entry.level == 1 else Vector2(68, 68)
	node.position = center - node.size / 2
	node.acquired = entry.level == 1 or (school == entry.school and stage >= int(entry.level))
	node.excluded = entry.level > 1 and school != "none" and school != entry.school
	node.tier = int(entry.level)
	if entry.icon != "" and ResourceLoader.exists(entry.icon):
		node.art = load(entry.icon)
	node.tooltip_text = "%s · 段階 %d\n%s" % [entry.title, entry.level, entry.desc]
	diagram.add_child(node)
	var index := nodes.size()
	nodes.append(node)
	entries.append(entry)
	node.pressed.connect(_select.bind(index))
	node.focus_entered.connect(_select.bind(index))
	_label(diagram, "起点" if entry.level == 1 else "%02d" % int(entry.level), Rect2(center.x + 42, center.y - 12, 45, 28), 17, MUTED)

func _select(index: int) -> void:
	selected_index = index
	for i in nodes.size():
		nodes[i].selected = i == index
		nodes[i].queue_redraw()
	for child in detail.get_children():
		detail.remove_child(child)
		child.queue_free()
	var entry: Dictionary = entries[index]
	var selected: TalentSeal = nodes[index]
	var data: CharacterData = DataLoader.characters.get(character_id)
	var class_name_text := data.display_name if data else character_id
	var portrait := PanelContainer.new()
	portrait.position = Vector2(863, 248)
	portrait.size = Vector2(160, 194)
	detail.add_child(portrait)
	var portrait_paper := StyleBoxFlat.new()
	portrait_paper.bg_color = Color("d6c4a2")
	portrait_paper.border_color = Color("aa8f68")
	portrait_paper.set_border_width_all(1)
	portrait.add_theme_stylebox_override("panel", portrait_paper)
	var image := TextureRect.new()
	image.position = Vector2(12, 12)
	image.size = Vector2(136, 150)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A plain child wrapper keeps the portrait's local layout independent of PanelContainer.
	var holder := Control.new()
	portrait.add_child(holder)
	holder.add_child(image)
	var player := get_tree().get_first_node_in_group("player") as Player
	if player and player.animated_sprite and player.animated_sprite.sprite_frames:
		var sprite := player.animated_sprite
		var source := sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
		if source:
			var bitmap := source.get_image()
			var crop := AtlasTexture.new()
			crop.atlas = source
			crop.region = Rect2(bitmap.get_used_rect())
			image.texture = crop
	_label(holder, class_name_text, Rect2(8, 158, 144, 30), 21, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_label(detail, "現在の流派", Rect2(1048, 250, 220, 28), 17, MUTED)
	var school_name := "未選択" if school == "none" else ("乱撃派" if school == "rengeki" else "一閃派")
	_label(detail, school_name, Rect2(1048, 280, 224, 38), 28, INK)
	_label(detail, "職業熟練  %d / 5" % stage, Rect2(1048, 331, 240, 28), 20, INK)
	for i in 5:
		_label(detail, "◆" if i < stage else "◇", Rect2(1047 + i * 42, 368, 36, 30), 26, TEAL if i < stage else MUTED)
	_label(detail, "職業強化を選ぶと成長", Rect2(1048, 409, 245, 28), 16, MUTED)
	_rule(Vector2(867, 455), 403)
	if selected.art:
		var icon := TextureRect.new()
		icon.texture = selected.art
		icon.position = Vector2(866, 470)
		icon.size = Vector2(62, 62)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		detail.add_child(icon)
	_label(detail, entry.title, Rect2(943, 467, 330, 36), 27, INK)
	var state := "習得済み" if selected.acquired else ("別流派のため選択不可" if selected.excluded else "未習得")
	_label(detail, "%s  ·  段階 %d" % [state, entry.level], Rect2(944, 508, 334, 28), 17, TEAL if selected.acquired else MUTED)
	var effect := String(entry.desc)
	if effect.contains("Lv2:"):
		effect = String(entry.get("summary", "")) + "。\n" + effect.get_slice("Lv2:", 1).strip_edges()
	_label(detail, effect, Rect2(868, 543, 405, 84), 20, INK)
	_rule(Vector2(867, 637), 403)
	var condition := "習得済みの起点です。"
	if int(entry.level) > 1:
		if selected.acquired:
			condition = "この天賦は現在の通常攻撃に反映されています。"
		elif selected.excluded:
			condition = "流派は選択済みです。この探索中は変更できません。"
		elif int(entry.level) == 2:
			condition = "レベルアップ時に選択。流派の変更不可。"
		else:
			condition = "%sの段階%dを習得後、レベルアップの候補から取得。" % [entry.branch_name, int(entry.level) - 1]
	_label(detail, "習得条件", Rect2(868, 650, 405, 24), 17, MUTED)
	_label(detail, condition, Rect2(868, 678, 405, 60), 18, INK)

func _rule(start: Vector2, length: float) -> void:
	var line := ColorRect.new()
	line.position = start
	line.size = Vector2(length, 1)
	line.color = Color("98713e")
	detail.add_child(line)
	_label(detail, "◆", Rect2(start.x + length / 2 - 10, start.y - 12, 20, 24), 15, MUTED, HORIZONTAL_ALIGNMENT_CENTER)

func _label(parent: Node, text: String, rect: Rect2, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", maxi(18, font_size))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	label.add_theme_constant_override("outline_size", 0)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	# Reapply after wrap setup: Label's initial unwrapped minimum can otherwise widen the page.
	label.size = rect.size
	return label

func _button(text: String, rect: Rect2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 18)
	canvas.add_child(button)
	PixelUIStyle.apply_button(button)
	return button

func play_opening() -> void:
	cancel_opening()
	opening = true
	# Render the real controls, not a duplicate/stale picture, as ink on the paper.
	# Reparent them back once the sheet lands: same selection, layout and pixels.
	canvas.reparent(_ink_viewport, false)
	canvas.show()
	canvas.modulate.a = 1.0
	_fit()
	_ink_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_intro.ink_texture = _ink_viewport.get_texture()
	_intro.ink_on_pages = true
	_intro.show()
	_intro.modulate.a = 0.0
	_intro.scale = Vector2.ONE
	_intro.phase = 0.0
	_intro_tween = create_tween()
	_intro_tween.tween_property(_intro,"modulate:a",1.0,.16)
	_intro_tween.tween_property(_intro,"phase",BookArt.DURATION,BookArt.DURATION)
	_intro_tween.tween_callback(func():
		_return_printed_controls()
		opening = false
		focus_selected()
	)

func _return_printed_controls() -> void:
	if canvas and canvas.get_parent() == _ink_viewport:
		canvas.reparent(self, false)
		_fit()
	if _intro:
		_intro.ink_on_pages = false
		_intro.queue_redraw()
	if _ink_viewport:
		_ink_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func cancel_opening() -> void:
	if _intro_tween and _intro_tween.is_valid(): _intro_tween.kill()
	opening = false
	_return_printed_controls()
	if _intro: _intro.hide()
	if canvas:
		canvas.show()
		canvas.modulate.a = 1.0
