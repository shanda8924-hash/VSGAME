extends CanvasLayer
class_name EquipmentScreen
## 装備・所持品・詳細を一望し、右タブで鍛造へ切り替えるアイテムボックス。

signal closed()
const FrameArt := preload("res://ui/common/relic_frame_art.gd")

const FIXED_STATS := ["attack_power", "defense", "max_hp"]
const STAT_NAMES := {
	"attack_power":"攻撃力", "defense":"防御力", "max_hp":"最大HP", "move_speed":"移動速度",
	"attack_speed":"攻撃速度", "crit_rate":"会心率", "crit_damage":"会心ダメージ"
}
const SLOT_NAMES := {"weapon":"武器", "head":"頭", "body":"胴", "arms":"腕", "legs":"脚", "accessory":"アクセサリー"}
const RARITY_NAMES := {
	"uncommon":"アンコモン", "rare":"レア", "epic":"エピック", "legendary":"レジェンダリー", "mythic":"ミシック"
}
const SORT_NAMES := ["レア度順", "部位順", "入手順"]
const SLOT_FILTERS := ["", "weapon", "head", "body", "arms", "legs", "accessory"]
const SLOT_FILTER_NAMES := ["ALL", "武器", "頭", "胴", "腕", "脚", "装飾"]
const BOOK_COIN_TEXTURE := preload("res://assets/ui/complete_ui_pack/book/icon_coin.png")
const BOOK_STAR_TEXTURE := preload("res://assets/ui/complete_ui_pack/book/icon_star.png")
const SLOT_FILTER_ICONS := {
	"weapon":"res://assets/items/weapons/weapon_sword_uncommon_001.png",
	"head":"res://assets/items/head/head_cap_uncommon_001.png",
	"body":"res://assets/items/body/body_coat_uncommon_001.png",
	"arms":"res://assets/items/arms/arms_gloves_uncommon_001.png",
	"legs":"res://assets/items/legs/legs_boots_rare_001.png",
	"accessory":"res://assets/items/accessories/accessory_ring_epic_001.png",
}

class LockGlyph extends Control:
	var locked := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		var p := (size * 0.5).floor()
		var ink := Color("e5bb68") if locked else Color("a5b0bc")
		draw_rect(Rect2(p + Vector2(-7, -1), Vector2(14, 13)), ink)
		draw_polyline(PackedVector2Array([p + Vector2(-4,-1), p + Vector2(-4,-7), p + Vector2(-2,-9), p + Vector2(2,-9), p + Vector2(4,-7), p + Vector2(4,-1)]), ink, 3, false)
		draw_rect(Rect2(p + Vector2(-1,3), Vector2(3,6)), Color("101a25"))

class CornerSelectionFrame:
	extends Control
	var accent := Color("74f4ec")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		resized.connect(queue_redraw)
		queue_redraw()

	func _draw() -> void:
		var w := floorf(size.x)
		var h := floorf(size.y)
		if w < 24.0 or h < 24.0:
			return
		var reach := 10.0
		var inset := 3.0
		var shadow := Color(0.0, 0.0, 0.0, 0.82)
		for data in [
			[Vector2(inset, inset), 1.0, 1.0], [Vector2(w - inset, inset), -1.0, 1.0],
			[Vector2(inset, h - inset), 1.0, -1.0], [Vector2(w - inset, h - inset), -1.0, -1.0],
		]:
			var corner: Vector2 = data[0]
			var sx: float = data[1]
			var sy: float = data[2]
			draw_line(corner + Vector2(2, 2), corner + Vector2(sx * reach + 2, 2), shadow, 2.0, false)
			draw_line(corner + Vector2(2, 2), corner + Vector2(2, sy * reach + 2), shadow, 2.0, false)
			draw_line(corner, corner + Vector2(sx * reach, 0), accent, 1.0, false)
			draw_line(corner, corner + Vector2(0, sy * reach), accent, 1.0, false)

@onready var character_panel: PanelContainer = $Background/Margin/Main/Columns/CharacterPanel
@onready var inventory_panel: PanelContainer = $Background/Margin/Main/Columns/InventoryPanel
@onready var forge_panel: PanelContainer = $Background/Margin/Main/Columns/ForgePanel
@onready var character_name: Label = $Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/CharacterName
@onready var character_portrait: TextureRect = $Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/CharacterStage/Center/PortraitFrame/CharacterPortrait
@onready var left_slots: VBoxContainer = $Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/CharacterStage/LeftSlots
@onready var top_slot: VBoxContainer = $Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/CharacterStage/Center/TopSlot
@onready var bottom_slot: VBoxContainer = $Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/CharacterStage/Center/BottomSlot
@onready var right_slots: VBoxContainer = $Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/CharacterStage/RightSlots
@onready var stats: RichTextLabel = $Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/StatsPanel/Margin/Stats
@onready var inventory_title: Button = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/CenterTabs/InventoryTab
@onready var inventory_tab: Button = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/CenterTabs/InventoryTab
@onready var equipped_tab: Button = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/CenterTabs/EquippedTab
@onready var detail_shortcut: Button = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/CenterTabs/DetailShortcut
@onready var gold_label: Label = $Background/Margin/Main/Header/GoldPlaque/HBox/Gold
@onready var gold_icon: TextureRect = $Background/Margin/Main/Header/GoldPlaque/HBox/Coin
@onready var capacity_label: Label = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/InventoryTools/Capacity
@onready var category_tabs: VBoxContainer = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/InventoryBody/CategoryTabs
@onready var rarity_counts: Label = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/RarityCounts
@onready var detail_tab: Button = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightHeader/DetailTab
@onready var forge_tab: Button = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightHeader/ForgeTab
@onready var detail_view: VBoxContainer = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/DetailView
@onready var forge_view: VBoxContainer = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/ForgeView
@onready var detail_icon_frame: PanelContainer = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/DetailView/DetailHeader/IconFrame
@onready var detail_icon: TextureRect = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/DetailView/DetailHeader/IconFrame/Icon
@onready var detail_name: Label = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/DetailView/DetailHeader/Labels/Name
@onready var detail_meta: Label = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/DetailView/DetailHeader/Labels/Meta
@onready var detail_rank: Label = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/DetailView/DetailHeader/Labels/Rank
@onready var favorite_button: Button = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/DetailView/DetailHeader/Labels/HeaderActions/FavoriteButton
@onready var material_slots: GridContainer = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/ForgeView/MaterialSlots
@onready var merge_notice: Label = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/ForgeView/MergeNotice
@onready var inventory_list: GridContainer = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/InventoryBody/InventoryWell/Margin/Scroll/InventoryList
@onready var comparison_title: Label = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/DetailView/ComparisonTitle
@onready var comparison: RichTextLabel = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/DetailView/Comparison
@onready var merge_preview_icon: TextureRect = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/ForgeView/MergePreviewRow/MergePreviewIcon
@onready var merge_preview: RichTextLabel = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/ForgeView/MergePreviewRow/MergePreview
@onready var equip_button: Button = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/DetailView/Buttons/EquipButton
@onready var unequip_button: Button = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/DetailView/Buttons/UnequipButton
@onready var lock_button: Button = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/DetailView/DetailHeader/Labels/HeaderActions/LockButton
@onready var current_equipped_icon: TextureRect = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/DetailView/ComparisonCard/Margin/HBox/CurrentIcon
@onready var comparison_summary: RichTextLabel = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/DetailView/ComparisonCard/Margin/HBox/Summary
@onready var add_material_button: Button = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/ForgeView/AddMaterialButton
@onready var merge_button: Button = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/ForgeView/MergeButton
@onready var animation_hint: Label = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/ForgeView/AnimationHint
@onready var merge_animation_layer: Control = $Background/MergeAnimationLayer
@onready var sort_button: Button = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/InventoryTools/SortButton
@onready var rarity_filter: OptionButton = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/InventoryTools/RarityFilter
@onready var autofill_button: Button = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/ForgeView/ForgeTools/AutofillButton
@onready var clear_materials_button: Button = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/ForgeView/ForgeTools/ClearMaterialsButton
@onready var character_stage: Control = $Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/CharacterStage
@onready var connection_lines: Control = $Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/CharacterStage/ConnectionLines
@onready var forge_stage: Control = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/ForgeView/ForgeStage
@onready var forge_caption: Label = $Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/ForgeView/ForgeCaption

const OUTLINE_SHADER = preload("res://ui/equipment/equipment_outline.gdshader")
var _drag_item: EquipmentData = null
var _popup_ready := false
var _forge_scroll: ScrollContainer
var _popup_pinned := false
var _hover_source: Control
var _hover_grace := 0.0
var _bag_forge_button: Button
var _equipment: EquipmentComponent
var _selected: EquipmentData
var _comparison_item: EquipmentData
var _is_open := false
var _covered_hud: CanvasLayer
var _hud_was_visible := false
var interaction_allowed: Callable
var external_open_navigation := false
var _merge_system := EquipmentMergeSystem.new()
var _merge_materials: Array[EquipmentData] = []
var _merge_result: EquipmentData
var _pending_merge_result: EquipmentData
var _merge_in_progress := false
var _has_completed_merge_animation := false
var _merge_animation_tween: Tween
var _material_slot_buttons: Array[Button] = []
var _sort_mode := 0
var _rarity_filter := ""
var _slot_filter := ""
var _inventory_scope := "all"
var _right_mode := "details"
var _category_buttons: Array[Button] = []
var _forge_elapsed := 0.0
var _forge_tweens: Array[Tween] = []
var _forge_result_texture: Texture2D
var _layout_settle_pending := false
var _trimmed_icon_cache: Dictionary = {}

func _ready() -> void:
	visible = false
	inventory_list.set_drag_forwarding(Callable(), _can_drop_equipment.bind(""), _drop_equipment.bind(""))
	($Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/InventoryBody/InventoryWell as Control).set_drag_forwarding(Callable(), _can_drop_equipment.bind(""), _drop_equipment.bind(""))
	# 「装備する／外す」は常に見せる（ダブルクリックと E も使える）。
	equip_button.show()
	unequip_button.show()
	var touch_close := Button.new()
	touch_close.text = "閉じる"
	touch_close.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	touch_close.offset_left = 8
	touch_close.offset_right = 112
	touch_close.offset_top = 0
	touch_close.offset_bottom = 62
	$Background/Margin/Main/Header.add_child(touch_close)
	PixelUIStyle.apply_button(touch_close)
	touch_close.pressed.connect(_close)
	merge_animation_layer.visible = false
	PixelUIStyle.apply_tree(self)
	$Background.add_theme_stylebox_override("panel", FrameArt.backdrop_style(Color(0.55, 0.58, 0.66, 0.88)))
	var background_ornament := $Background.get_node_or_null("RelicOrnamentLayer")
	if background_ornament:
		background_ornament.visible = false
	_apply_reference_frame(character_panel, Color("b89658"))
	_apply_reference_frame(inventory_panel, Color("b89658"))
	_apply_reference_frame(forge_panel, Color("b89658"))
	_apply_title_plaque($Background/Margin/Main/Header/TitlePlaque)
	PixelUIStyle.apply_panel($Background/Margin/Main/Header/GoldPlaque, Color("b89658"), true)
	PixelUIStyle.apply_panel($Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/CharacterHeader, Color("b89658"), true)
	PixelUIStyle.apply_panel($Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/StatsPanel, Color("40546b"), true)
	PixelUIStyle.apply_panel($Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/InventoryBody/InventoryWell, Color("40546b"), true)
	PixelUIStyle.apply_panel($Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/DetailView/ComparisonCard, Color("8b6737"), true)
	PixelUIStyle.apply_panel($Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/CharacterStage/Center/PortraitFrame, Color("80633b"))
	PixelUIStyle.apply_panel(detail_icon_frame, Color("b89658"))
	_apply_keycap($Background/Margin/Main/Footer/AcceptKey)
	_apply_keycap($Background/Margin/Main/Footer/BackKey)
	stats.add_theme_font_size_override("normal_font_size", 18)
	comparison.add_theme_font_size_override("normal_font_size", 18)
	comparison_summary.add_theme_font_size_override("normal_font_size", 18)
	detail_name.add_theme_font_size_override("font_size", 22)
	character_name.add_theme_color_override("font_color", Color("efd9a0"))
	($Background/Margin/Main/Header/TitlePlaque/Title as Label).add_theme_color_override("font_color", Color("f3dfba"))
	gold_label.add_theme_color_override("font_color", Color("f1e3c8"))
	gold_icon.texture = BOOK_COIN_TEXTURE
	favorite_button.icon = BOOK_STAR_TEXTURE
	favorite_button.expand_icon = true
	favorite_button.add_theme_constant_override("icon_max_width", 24)
	var lock_glyph := LockGlyph.new()
	lock_glyph.name = "LockGlyph"
	lock_button.add_child(lock_glyph)
	lock_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inventory_tab.pressed.connect(_set_inventory_scope.bind("all"))
	equipped_tab.pressed.connect(_set_inventory_scope.bind("equipped"))
	detail_shortcut.pressed.connect(_focus_detail_shortcut)
	detail_tab.pressed.connect(_set_right_mode.bind("details"))
	forge_tab.pressed.connect(_set_right_mode.bind("forge"))
	favorite_button.pressed.connect(_toggle_selected_favorite)
	lock_button.pressed.connect(_toggle_selected_lock)
	_build_category_tabs()
	_refresh_center_tabs()
	_set_right_mode("details")
	_refresh_gold()
	EventBus.run_gold_changed.connect(func(_current, _delta, _source): _refresh_gold())
	connection_lines.draw.connect(_draw_equipment_connections)
	forge_stage.draw.connect(_draw_forge_stage)
	sort_button.pressed.connect(_cycle_inventory_sort)
	rarity_filter.add_item("すべてのレア度")
	for rarity in EquipmentMergeSystem.RARITY_ORDER:
		rarity_filter.add_item(RARITY_NAMES[rarity])
	rarity_filter.item_selected.connect(_set_rarity_filter)
	autofill_button.pressed.connect(_autofill_materials)
	clear_materials_button.pressed.connect(_clear_merge_materials)
	_material_slot_buttons = [
		material_slots.get_node("Slot1") as Button,
		material_slots.get_node("Slot2") as Button,
		material_slots.get_node("Slot3") as Button,
	]
	for extra in range(3, 10):
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(0, 48)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		material_slots.add_child(slot)
		_material_slot_buttons.append(slot)
	for index in _material_slot_buttons.size():
		_material_slot_buttons[index].pressed.connect(_remove_merge_material.bind(index))
	var player := get_tree().get_first_node_in_group("player")
	if player:
		_equipment = player.get_node_or_null("EquipmentComponent")
		if _equipment:
			_equipment.inventory_changed.connect(_refresh)
			_equipment.equipment_changed.connect(func(_slot, _item): _refresh())
	equip_button.pressed.connect(_equip_selected)
	unequip_button.pressed.connect(_unequip_selected_slot)
	add_material_button.pressed.connect(func(): _toggle_merge_material(_selected))
	merge_button.pressed.connect(_merge_selected)
	_apply_crafted_details()
	_setup_compact_bag()

func _apply_crafted_details() -> void:
	# 詳細：見出しのすぐ下に「装備する／外す」を置き、能力表は内容ぶんだけ伸ばす（ボタンが隠れない）。
	var buttons_row := detail_view.get_node("Buttons") as Control
	detail_view.move_child(buttons_row, detail_view.get_node("DetailHeader").get_index() + 1)
	comparison.custom_minimum_size = Vector2(326.4, 170)
	FrameArt.plaque($Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/CharacterHeader)
	FrameArt.plaque(detail_tab)
	FrameArt.panel($Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/StatsPanel, true)
	FrameArt.panel($Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/InventoryBody/InventoryWell, true)
	FrameArt.panel($Background/Margin/Main/Columns/ForgePanel/Margin/VBox/RightStack/DetailView/ComparisonCard, true)
	FrameArt.panel($Background/Margin/Main/Header/GoldPlaque, true)
	var portrait_frame := character_portrait.get_parent() as Control
	FrameArt.hide_old_ornament(portrait_frame)
	portrait_frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	for key in [$Background/Margin/Main/Footer/AcceptKey, $Background/Margin/Main/Footer/BackKey]:
		FrameArt.hide_old_ornament(key)
	stats.add_theme_font_size_override("normal_font_size", 18)
	comparison.add_theme_font_size_override("normal_font_size", 18)
	comparison_summary.add_theme_font_size_override("normal_font_size", 18)

func _apply_reference_frame(panel: Control, accent: Color) -> void:
	FrameArt.panel(panel)

func _apply_title_plaque(panel: Control) -> void:
	FrameArt.plaque(panel, true)

func _apply_keycap(panel: PanelContainer) -> void:
	var style := PixelUIStyle.badge_style(Color("b89658"), Color("101a26"))
	style.set_content_margin_all(2.0)
	style.shadow_size = 2
	style.shadow_offset = Vector2(2, 2)
	panel.add_theme_stylebox_override("panel", style)

func _build_category_tabs() -> void:
	_category_buttons.clear()
	for index in SLOT_FILTERS.size():
		var slot: String = SLOT_FILTERS[index]
		var button := Button.new()
		button.custom_minimum_size = Vector2(44, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 18)
		button.text = "全" if slot == "" else ""
		button.tooltip_text = SLOT_FILTER_NAMES[index]
		if slot != "":
			FrameArt.part_icon(button, slot)
		button.pressed.connect(_set_slot_filter.bind(slot))
		category_tabs.add_child(button)
		_category_buttons.append(button)
	_refresh_category_tabs()

func _refresh_category_tabs() -> void:
	for index in _category_buttons.size():
		var active: bool = SLOT_FILTERS[index] == _slot_filter
		PixelUIStyle.apply_button(_category_buttons[index], PixelUIStyle.JEWEL if active else Color("52606f"))
		_category_buttons[index].add_theme_color_override("font_color", Color("b9fff6") if active else PixelUIStyle.TEXT_MUTED)

func _set_inventory_scope(scope: String) -> void:
	if _merge_in_progress:
		return
	_inventory_scope = scope
	_refresh_center_tabs()
	_refresh()

func _refresh_center_tabs() -> void:
	_apply_reference_tab(inventory_tab, _inventory_scope == "all")
	_apply_reference_tab(equipped_tab, _inventory_scope == "equipped")
	_apply_reference_tab(detail_shortcut, false)

func _apply_reference_tab(button: Button, selected: bool, forge_accent: bool = false, brown_fill: bool = true) -> void:
	var accent := Color("d48742") if forge_accent else Color("d6a957")
	PixelUIStyle.apply_button(button, accent if selected else Color("3d5064"))
	if selected:
		button.add_theme_stylebox_override("normal", FrameArt.box(true, 12, Color(1.15, 0.9, 0.68) if forge_accent else Color(1.1, 1.05, 0.88)))
	button.add_theme_color_override("font_color", Color("f3dfba") if selected else Color("9fa8b2"))

func _focus_detail_shortcut() -> void:
	_set_right_mode("details")
	detail_tab.grab_focus()

func _set_slot_filter(slot: String) -> void:
	if _merge_in_progress:
		return
	_slot_filter = slot
	_refresh_category_tabs()
	_refresh()

func _set_right_mode(mode: String) -> void:
	if _merge_in_progress:
		return
	_right_mode = mode
	detail_view.visible = mode == "details"
	forge_view.visible = mode == "forge"
	if _forge_scroll:
		_forge_scroll.visible = mode == "forge"
	_apply_reference_tab(detail_tab, detail_view.visible, false, false)
	FrameArt.plaque(detail_tab)
	_apply_reference_tab(forge_tab, forge_view.visible, true)
	(forge_panel.get_node("Margin/VBox/RightStack") as Container).queue_sort()
	($Background/Margin/Main/Columns as Container).queue_sort()
	if _popup_ready:
		forge_panel.visible = mode == "forge"
		_popup_pinned = mode == "forge"
		_position_item_popup.call_deferred()
	_schedule_layout_settle()

func _fit_background_to_viewport() -> void:
	if not is_inside_tree():
		return
	var background := $Background as Control
	var viewport_size := get_viewport().get_visible_rect().size
	var inset := Vector2(maxf((viewport_size.x - 800.0) * 0.5, 0.0), maxf((viewport_size.y - 690.0) * 0.5, 0.0))
	background.offset_left = inset.x
	background.offset_top = inset.y
	background.offset_right = -inset.x
	background.offset_bottom = -inset.y
	background.queue_sort()
	if _popup_ready and forge_panel.visible:
		_position_item_popup()

func _schedule_layout_settle() -> void:
	if _layout_settle_pending or not is_inside_tree():
		return
	_layout_settle_pending = true
	await get_tree().process_frame
	_fit_background_to_viewport()
	await get_tree().process_frame
	_fit_background_to_viewport()
	_layout_settle_pending = false

func _refresh_gold() -> void:
	gold_label.text = _format_number(GameManager.run_gold)

func _format_number(value: int) -> String:
	var digits := str(maxi(value, 0))
	var output := ""
	for index in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0:
			output += ","
		output += digits[index]
	return output

func _draw_equipment_connections() -> void:
	var w := connection_lines.size.x
	var h := connection_lines.size.y
	var center := Vector2(w * 0.5, h * 0.54)
	var line_color := Color("3f566a")
	var rune_color := Color("263e51")
	var points := [
		Vector2(w * 0.5, 54), Vector2(60, 140), Vector2(60, h - 92),
		Vector2(w - 60, 140), Vector2(w - 60, h - 92), Vector2(w * 0.5, h - 45),
	]
	for point in points:
		connection_lines.draw_line(center, point, line_color, 2.0, false)
	connection_lines.draw_line(Vector2(w * 0.5, 72), Vector2(w * 0.5, h - 60), rune_color, 3.0, false)
	for offset in [-34.0, 0.0, 34.0]:
		var rune_center := center + Vector2(0, offset)
		var diamond := PackedVector2Array([
			rune_center + Vector2(0, -10), rune_center + Vector2(8, 0),
			rune_center + Vector2(0, 10), rune_center + Vector2(-8, 0), rune_center + Vector2(0, -10),
		])
		connection_lines.draw_polyline(diamond, rune_color, 2.0, false)

func _process(delta: float) -> void:
	if _drag_item != null and not get_viewport().gui_is_dragging():
		_drag_item = null
		_highlight_drop_slots(null)
	if _popup_ready and forge_panel.visible and _right_mode == "details" and not _popup_pinned:
		var mouse := forge_panel.get_global_mouse_position()
		var over_source := is_instance_valid(_hover_source) and _hover_source.get_global_rect().has_point(mouse)
		if over_source or forge_panel.get_global_rect().has_point(mouse):
			_hover_grace = 0.24
		else:
			_hover_grace -= delta
			if _hover_grace <= 0.0:
				forge_panel.hide()
	if _merge_in_progress:
		_forge_elapsed += delta
		forge_stage.queue_redraw()
		return
	if _is_open and rarity_filter.get_popup().visible:
		return
	var toggle_pressed := not external_open_navigation and (Input.is_action_just_pressed("character_screen") or Input.is_action_just_pressed("equipment_menu"))
	if _is_open and (toggle_pressed or Input.is_action_just_pressed("ui_cancel")):
		_close()
	elif not external_open_navigation and toggle_pressed and GameManager.active_modal_count == 0 and GameManager.run_state == GameManager.RunState.PLAYING and _is_safe_timing():
		_open()

func _input(event: InputEvent) -> void:
	# Capture before focused GUI controls consume accept; the initiating press runs
	# before the transaction starts and therefore cannot skip its own animation.
	if not _merge_in_progress or not _has_completed_merge_animation or event.is_echo():
		return
	var skip_pressed := false
	if event is InputEventMouseButton:
		skip_pressed = (event as InputEventMouseButton).pressed
	skip_pressed = skip_pressed or event.is_action_pressed("ui_accept")
	if InputMap.has_action("interact"):
		skip_pressed = skip_pressed or event.is_action_pressed("interact")
	if not skip_pressed:
		return
	get_viewport().set_input_as_handled()
	_complete_merge_animation()

func is_open() -> bool:
	return _is_open

func _is_safe_timing() -> bool:
	if interaction_allowed.is_valid(): return interaction_allowed.call()
	return true

func _open() -> void:
	if _is_open:
		return
	_is_open = true
	_covered_hud = get_parent().get_node_or_null("HUD") as CanvasLayer
	if is_instance_valid(_covered_hud):
		_hud_was_visible = _covered_hud.visible
		_covered_hud.hide()
	GameManager.open_modal()
	# Give wrapping labels their real column width before assigning item text.
	# Refreshing while the full-screen layer is hidden makes Godot measure each glyph
	# as a separate line and can permanently inflate the panel height.
	visible = true
	_refresh_gold()
	# 5分サバイバル中は「新しく拾った装備を装備中と比べる」が目的なので、
	# 入手順（新しい順）で開き、最新の装備を選択して比較を先に見せる（D5、2026-10-31）。
	if GameManager.survival_mode_active and _right_mode != "forge":
		_sort_mode = 2
		sort_button.text = SORT_NAMES[_sort_mode]
		_selected = null
		_right_mode = "details"
	_set_right_mode(_right_mode)
	_refresh()
	call_deferred("_focus_initial_control")

func _close() -> void:
	if not _is_open or _merge_in_progress:
		return
	_is_open = false
	forge_panel.hide()
	_popup_pinned = false
	visible = false
	if is_instance_valid(_covered_hud):
		_covered_hud.visible = _hud_was_visible
	_covered_hud = null
	GameManager.close_modal()
	closed.emit()

func _focus_initial_control() -> void:
	if not _is_open:
		return
	_focus_inventory_item(_selected)

## Developer Test Labの入口と、通常の詳細／鍛造タブを同じ切替へ集約する。
func _set_mode(mode: String) -> void:
	if _merge_in_progress:
		return
	if mode == "merge":
		_set_right_mode("forge")
		autofill_button.grab_focus()
	else:
		_set_right_mode("details")
		_focus_inventory_item(_selected)

func _refresh() -> void:
	# Closed screens rebuild once on open, not for every pickup during combat.
	if _equipment == null or not _is_open:
		return
	var focus := get_viewport().gui_get_focus_owner()
	var focused_item: EquipmentData = focus.get_meta("inventory_item") as EquipmentData if focus and focus.has_meta("inventory_item") else null
	if not _merge_in_progress:
		_sync_merge_materials()
	_refresh_character()
	_refresh_slots()
	_clear(inventory_list)
	var items := _visible_inventory()
	if _selected == null or _selected not in _equipment.inventory or _selected not in items:
		_selected = items[0] if not items.is_empty() else null
	for item in items:
		inventory_list.add_child(_build_inventory_button(item))
	if items.is_empty():
		var empty := Label.new()
		empty.text = "該当なし" if _rarity_filter != "" or _slot_filter != "" else "所持品なし"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(300, 38)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inventory_list.add_child(empty)
	_refresh_comparison()
	_refresh_rarity_counts()
	_refresh_merge_view()
	forge_stage.queue_redraw()
	_fit_background_to_viewport()
	_schedule_layout_settle()
	if focused_item and not _merge_in_progress:
		call_deferred("_focus_inventory_item", focused_item)

## Presentation sorting works on a copy; the inventory transaction order is untouched.
func _visible_inventory() -> Array[EquipmentData]:
	var items := _equipment.get_all_inventory()
	if _merge_in_progress and _pending_merge_result:
		items.erase(_pending_merge_result)
	if _inventory_scope == "equipped":
		items = items.filter(func(item: EquipmentData): return _equipment.is_equipped(item))
	var active_rarity := _rarity_filter
	if active_rarity != "":
		items = items.filter(func(item: EquipmentData): return item.rarity == active_rarity)
	if _slot_filter != "":
		items = items.filter(func(item: EquipmentData): return item.slot == _slot_filter)
	if _sort_mode == 2:
		items.reverse()
	else:
		items.sort_custom(func(a: EquipmentData, b: EquipmentData):
			if a.is_favorite != b.is_favorite:
				return a.is_favorite
			if _sort_mode == 1 and a.slot != b.slot:
				return EquipmentComponent.SLOTS.find(a.slot) < EquipmentComponent.SLOTS.find(b.slot)
			if a.rarity != b.rarity:
				return EquipmentMergeSystem.RARITY_ORDER.find(a.rarity) > EquipmentMergeSystem.RARITY_ORDER.find(b.rarity)
			if a.display_name != b.display_name:
				return a.display_name.naturalnocasecmp_to(b.display_name) < 0
			return a.instance_id.naturalnocasecmp_to(b.instance_id) < 0
		)
	return items

func _cycle_inventory_sort() -> void:
	if _merge_in_progress:
		return
	_sort_mode = (_sort_mode + 1) % SORT_NAMES.size()
	sort_button.text = SORT_NAMES[_sort_mode]
	_refresh()

func _set_rarity_filter(index: int) -> void:
	if _merge_in_progress:
		return
	_rarity_filter = "" if index == 0 else String(EquipmentMergeSystem.RARITY_ORDER[index - 1])
	_refresh()

func _focus_inventory_item(item: EquipmentData = null) -> void:
	if not _is_open or _merge_in_progress:
		return
	var first: Button
	for child in inventory_list.get_children():
		if child is Button and not child.disabled:
			if first == null:
				first = child
			if child.get_meta("inventory_item", null) == item:
				child.grab_focus()
				return
	if first:
		first.grab_focus()
	else:
		sort_button.grab_focus()

func _needed_materials() -> int:
	var rarity := _merge_materials[0].rarity if not _merge_materials.is_empty() else (_selected.rarity if _selected else "uncommon")
	return maxi(3, EquipmentMergeSystem.required_count(rarity))

func _autofill_candidates() -> Array[EquipmentData]:
	var result: Array[EquipmentData] = _merge_materials.duplicate()
	var active_rarity := result[0].rarity if not result.is_empty() else _rarity_filter
	if active_rarity == "":
		# Start with the lowest complete tier so rare treasures are never picked first.
		for rarity in EquipmentMergeSystem.RARITY_ORDER:
			for group in _merge_system.get_mergeable_groups(_equipment):
				if group.rarity == rarity:
					active_rarity = rarity
					break
			if active_rarity != "":
				break
	if active_rarity == "" or _merge_system.get_next_rarity(active_rarity) == "":
		return result
	# 主素材（または選択中）と同じ部位を先に、足りなければ他の部位で埋める。
	var preferred_slot := result[0].slot if not result.is_empty() else (_selected.slot if _selected and _selected.rarity == active_rarity else "")
	var pool := _equipment.get_all_inventory().filter(func(item: EquipmentData): return item.rarity == active_rarity and item not in result and not item.is_locked and not _equipment.is_equipped(item))
	pool.sort_custom(func(a: EquipmentData, b: EquipmentData):
		if (a.slot == preferred_slot) != (b.slot == preferred_slot):
			return a.slot == preferred_slot
		return item_score(a) < item_score(b)
	)
	for item in pool:
		if result.size() >= EquipmentMergeSystem.required_count(active_rarity):
			break
		result.append(item)
	return result

func _autofill_materials() -> void:
	if _merge_in_progress:
		return
	var candidates := _autofill_candidates()
	if candidates.is_empty() or candidates.size() != EquipmentMergeSystem.required_count(candidates[0].rarity):
		return
	_merge_result = null
	_merge_materials.assign(candidates)
	_refresh()
	merge_button.grab_focus()

func _clear_merge_materials() -> void:
	if _merge_in_progress:
		return
	_merge_materials.clear()
	_merge_result = null
	_refresh()
	autofill_button.grab_focus()

func _sync_merge_materials() -> void:
	var inventory := _equipment.get_all_inventory()
	for index in range(_merge_materials.size() - 1, -1, -1):
		if _merge_materials[index] not in inventory or _merge_materials[index].is_locked or _equipment.is_equipped(_merge_materials[index]):
			_merge_materials.remove_at(index)

func _refresh_character() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	var data: CharacterData = DataLoader.characters.get(GameManager.selected_character_id)
	character_name.text = data.display_name if data else GameManager.selected_character_id
	var sprite := player.animated_sprite
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(sprite.animation):
		var frame_count := sprite.sprite_frames.get_frame_count(sprite.animation)
		if frame_count > 0:
			var frame_texture := sprite.sprite_frames.get_frame_texture(sprite.animation, mini(sprite.frame, frame_count - 1))
			character_portrait.texture = _crop_transparent_margin(frame_texture)
	var health := player.health_component
	var movement := player.movement_component
	var upgrades := player.upgrades_component
	var modifier := player.get_node_or_null("StatModifierComponent") as StatModifierComponent
	var base_attack := data.base_damage if data else 10.0
	var level_flat := modifier.get_damage_flat_bonus() if modifier else 0.0
	var flat_attack := base_attack + level_flat + _equipment.get_total_stat("attack_power")
	var final_attack := flat_attack * upgrades.damage_multiplier * upgrades.get_equipment_conditional_damage_multiplier()
	var base_crit := data.crit_chance if data else 0.0
	var crit_rate := base_crit + (modifier.get_crit_chance_bonus() if modifier else 0.0) + upgrades.crit_rate_bonus + upgrades.equipment_crit_rate_bonus
	var crit_damage := (data.crit_multiplier if data else 2.0) + upgrades.equipment_crit_damage_bonus
	var attack_speed_bonus := upgrades.attack_interval_multiplier + upgrades.equipment_attack_speed_bonus
	var move_speed := movement.base_speed * movement.bonus_speed_multiplier * movement.equipment_speed_multiplier
	stats.add_theme_font_size_override("normal_font_size", 18)
	stats.add_theme_constant_override("table_h_separation", 4)
	stats.add_theme_constant_override("table_v_separation", 1)
	stats.text = "[table=2]"
	var values := [["max_hp", "HP", "%.0f / %.0f" % [health.current_hp, health.max_hp]], ["attack_power", "攻撃力", "%.0f" % final_attack], ["defense", "防御力", "%.0f" % _equipment.get_total_stat("defense")], ["move_speed", "移動速度", "%.1f" % move_speed], ["crit_rate", "会心率", "%.1f%%" % (crit_rate * 100.0)], ["crit_damage", "会心倍率", "%.1f%%" % (crit_damage * 100.0)]]
	for entry in values:
		stats.text += "[cell]%s[/cell][cell][right]%s[/right][/cell]" % [entry[1], entry[2]]
	stats.text += "[/table]"
	stats.tooltip_text = "最大HP %.0f / 攻撃速度 +%.1f%%" % [health.max_hp, attack_speed_bonus * 100.0]

func _stat_icon(stat_name: String) -> String:
	var paths := {"max_hp":"res://assets/ui/complete_ui_pack/book/icon_heart.png", "attack_power":SLOT_FILTER_ICONS.weapon,
		"defense":"res://assets/ui/icons/shikashi/items/sturdy_shield.png", "move_speed":"res://assets/ui/icons/shikashi/items/swift_boots.png"}
	if paths.has(stat_name):
		return "[img=22x22]%s[/img]" % paths[stat_name]
	return {"crit_rate":"[color=#cfb998]◎[/color]", "crit_damage":"[color=#ff9b57]✹[/color]", "attack_speed":"[color=#a2c4d5]»[/color]"}.get(stat_name, "◇")

func _stat_display(stat_name: String, value: float) -> String:
	return "%.0f" % value if stat_name in FIXED_STATS else "%.1f%%" % (value * 100.0)

## SpriteFramesの各frameは透明余白を多く含む素材がある。元ピクセルを最近傍のまま
## 透明外周だけ切り出し、中央キャラクターをスロット間で十分な大きさに表示する。
func _crop_transparent_margin(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.01:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return texture
	var cropped := image.get_region(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))
	return ImageTexture.create_from_image(cropped)

func _load_trimmed_icon(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if _trimmed_icon_cache.has(path):
		return _trimmed_icon_cache[path] as Texture2D
	var pixel_path := "res://assets/ui/equipment_readable_v4/%s.png" % path.get_file().get_basename()
	var source := pixel_path if path.begins_with("res://assets/items/painted_200/") and ResourceLoader.exists(pixel_path) else path
	var texture := load(source) as Texture2D
	var trimmed := _crop_transparent_margin(texture)
	_trimmed_icon_cache[path] = trimmed
	return trimmed

func _tighten_icon_button(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var source := button.get_theme_stylebox(state)
		if source is StyleBoxFlat or source is StyleBoxTexture:
			var style := source.duplicate() as StyleBox
			style.content_margin_left = 5.0
			style.content_margin_top = 5.0
			style.content_margin_right = 5.0
			style.content_margin_bottom = 5.0
			button.add_theme_stylebox_override(state, style)

func _refresh_slots() -> void:
	for container in [left_slots, top_slot, bottom_slot, right_slots]:
		_clear(container)
	left_slots.add_child(_build_slot_button("weapon"))
	left_slots.add_child(_build_slot_button("arms"))
	top_slot.add_child(_build_slot_button("head"))
	bottom_slot.add_child(_build_slot_button("legs"))
	right_slots.add_child(_build_slot_button("body"))
	right_slots.add_child(_build_slot_button("accessory"))

func _build_slot_button(slot: String) -> Button:
	var item := _equipment.get_equipped(slot)
	var button := Button.new()
	button.custom_minimum_size = Vector2(52, 52)
	button.text = "" if item else ("装飾" if slot == "accessory" else String(SLOT_NAMES.get(slot, slot)))
	button.tooltip_text = "%s：%s" % [SLOT_NAMES.get(slot, slot), item.display_name if item else "未装備"]
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if item:
		button.icon = _load_trimmed_icon(item.icon_path)
		button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 56)
	button.add_theme_font_size_override("font_size", 18)
	button.disabled = _merge_in_progress
	button.set_meta("equipment_slot", slot)
	button.gui_input.connect(_on_equipment_double_click.bind(item, slot))
	button.set_drag_forwarding(_start_equipment_drag.bind(item, slot, button), _can_drop_equipment.bind(slot), _drop_equipment.bind(slot))
	PixelUIStyle.apply_button(button, item.get_rarity_color() if item else Color(0.3, 0.3, 0.37))
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, FrameArt.styled("slot", 5, Color(1.12, 1.1, 1.0) if state == "hover" else Color.WHITE))
	_tighten_icon_button(button)
	# Neutral cells; rarity belongs to the equipment silhouette.
	if item:
		button.add_theme_color_override("font_color", item.get_rarity_color().lightened(0.28))
		_add_corner_badge(button, "E", Color("69f092"))
		if item.is_favorite:
			_add_top_badge(button, "★", Color("ffd36a"))
	button.pressed.connect(func():
		if item:
			# A paperdoll click must reach the item even under an inventory filter.
			if _rarity_filter != "" and _rarity_filter != item.rarity:
				_rarity_filter = ""
				rarity_filter.select(0)
			if _slot_filter != "" and _slot_filter != item.slot:
				_slot_filter = ""
				_refresh_category_tabs()
			_inventory_scope = "all"
			_refresh_center_tabs()
			_selected = item
			_set_right_mode("details")
			_refresh()
	)
	if item:
		_attach_item_hover(button, item)
	return button

## 装備スコア：一目で強さを比べるための単一指標。固定値と割合値を同じ尺度へ寄せる。
static func item_score(item: EquipmentData) -> float:
	if item == null:
		return 0.0
	var score := item.get_stat("attack_power") * 2.0 + item.get_stat("defense") * 1.5 + item.get_stat("max_hp") * 0.25
	score += item.get_stat("move_speed") * 120.0 + item.get_stat("attack_speed") * 120.0 + item.get_stat("crit_rate") * 160.0 + item.get_stat("crit_damage") * 60.0
	score += item.special_effects.size() * 8.0
	score += maxi(EquipmentMergeSystem.RARITY_ORDER.find(item.rarity), 0) * 2.0
	return score

## 同じ部位の装備中と比べたスコア差。未装備なら自身のスコア。
func _score_delta(item: EquipmentData) -> float:
	var current := _equipment.get_equipped(item.slot) if _equipment else null
	if current == item:
		return 0.0
	return item_score(item) - item_score(current)

func _add_top_left_badge(button: Button, text: String, color: Color) -> void:
	var badge := Label.new()
	badge.text = text
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", color)
	badge.add_theme_color_override("font_outline_color", Color("0b0c13"))
	badge.add_theme_constant_override("outline_size", 3)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(badge)
	badge.offset_left = 5.0
	badge.offset_top = 3.0
	badge.offset_right = 22.0
	badge.offset_bottom = 20.0

## 所持品マスのレア度の下地（Diablo 系の色付きマス）。アイコンの後ろに敷く。
func _add_rarity_underlay(button: Button, item: EquipmentData) -> void:
	var underlay := Panel.new()
	underlay.name = "RarityUnderlay"
	underlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	var color := item.get_rarity_color()
	style.bg_color = Color(color, 0.14 + 0.03 * maxi(EquipmentMergeSystem.RARITY_ORDER.find(item.rarity), 0))
	style.border_color = Color(color, 0.85)
	style.border_width_bottom = 3
	style.anti_aliasing = false
	underlay.add_theme_stylebox_override("panel", style)
	button.add_child(underlay)
	button.move_child(underlay, 0)
	underlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	underlay.offset_left = 5
	underlay.offset_top = 5
	underlay.offset_right = -5
	underlay.offset_bottom = -5

func _build_inventory_button(item: EquipmentData) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(48, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.set_meta("inventory_item", item)
	button.gui_input.connect(_on_equipment_double_click.bind(item, ""))
	button.set_drag_forwarding(_start_equipment_drag.bind(item, "", button), _can_drop_equipment.bind(""), _drop_equipment.bind(""))
	var state_badges: Array[String] = []
	button.text = ""
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 56)
	button.add_theme_font_size_override("font_size", 18)
	button.icon = _load_trimmed_icon(item.icon_path)
	if button.icon:
		button.expand_icon = true
	PixelUIStyle.apply_button(button, item.get_rarity_color().lightened(0.35) if item == _selected else item.get_rarity_color())
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, FrameArt.styled("slot", 5, Color(1.12, 1.1, 1.0) if state == "hover" else Color.WHITE))
	_tighten_icon_button(button)
	# Neutral cells; rarity belongs to the equipment silhouette.
	button.add_theme_stylebox_override("focus", PixelUIStyle._focus_box(PixelUIStyle.JEWEL))
	if item == _selected:
		button.add_theme_stylebox_override("normal", FrameArt.styled("slot", 5, Color(0.9, 1.25, 1.2)))
	_add_rarity_underlay(button, item)
	if not _equipment.is_equipped(item) and not item.is_locked:
		var delta := _score_delta(item)
		if delta > 0.5:
			_add_top_left_badge(button, "▲", Color("69f092"))
		elif delta < -0.5:
			_add_top_left_badge(button, "▼", Color("a85858"))
	if _right_mode == "forge":
		# 鍛造中は素材にできない品（装備中・保護・別レア度・最高レア）を沈める。
		var eligible := not _equipment.is_equipped(item) and not item.is_locked and _merge_system.get_next_rarity(item.rarity) != ""
		if eligible and not _merge_materials.is_empty() and item.rarity != _merge_materials[0].rarity:
			eligible = false
		if not eligible and item not in _merge_materials:
			button.modulate = Color(0.55, 0.55, 0.6)
	var corner_frame := CornerSelectionFrame.new()
	corner_frame.visible = item == _selected
	button.add_child(corner_frame)
	corner_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.focus_entered.connect(func(): corner_frame.visible = true)
	button.focus_exited.connect(func(): corner_frame.visible = item == _selected)
	if _equipment.is_equipped(item):
		state_badges.append("E")
		_add_corner_badge(button, "E", Color("69f092"))
	if item.is_favorite:
		state_badges.append("★")
		_add_top_right_badge(button, "★", Color("ffd36a"))
	if item.is_locked:
		state_badges.append("◆")
		_add_top_badge(button, "◆", Color("82dff2"))
	if item in _merge_materials:
		state_badges.append("鍛")
		_add_bottom_left_badge(button, "鍛", Color("ffad5b"))
	button.add_theme_color_override("font_color", PixelUIStyle.TEXT)
	button.tooltip_text = "%s / %s\n%s\n%s" % [item.display_name, item.get_slot_display_name(), RARITY_NAMES.get(item.rarity, item.rarity), " / ".join(state_badges)]
	button.disabled = _merge_in_progress
	button.pressed.connect(_on_inventory_item_pressed.bind(item))
	_attach_item_hover(button, item)
	return button

func _add_corner_badge(button: Button, text: String, color: Color) -> void:
	var badge := Label.new()
	badge.text = text
	badge.add_theme_font_size_override("font_size", 18)
	badge.add_theme_color_override("font_color", color)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(badge)
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.offset_left = -27.0
	badge.offset_top = -28.0
	badge.offset_right = -5.0
	badge.offset_bottom = -4.0

func _add_top_badge(button: Button, text: String, color: Color) -> void:
	var badge := Label.new()
	badge.text = text
	badge.add_theme_font_size_override("font_size", 18)
	badge.add_theme_color_override("font_color", color)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(badge)
	badge.offset_left = 6.0
	badge.offset_top = 4.0
	badge.offset_right = 30.0
	badge.offset_bottom = 28.0

func _add_top_right_badge(button: Button, text: String, color: Color) -> void:
	var badge := Label.new()
	badge.text = text
	badge.add_theme_font_size_override("font_size", 18)
	badge.add_theme_color_override("font_color", color)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(badge)
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -24.0
	badge.offset_top = 4.0
	badge.offset_right = -4.0
	badge.offset_bottom = 28.0

func _add_bottom_left_badge(button: Button, text: String, color: Color) -> void:
	var badge := Label.new()
	badge.text = text
	badge.add_theme_font_size_override("font_size", 18)
	badge.add_theme_color_override("font_color", color)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(badge)
	badge.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	badge.offset_left = 5.0
	badge.offset_top = -28.0
	badge.offset_right = 28.0
	badge.offset_bottom = -3.0

func _on_inventory_item_pressed(item: EquipmentData) -> void:
	if _merge_in_progress:
		return
	_selected = item
	if _right_mode == "forge" and not _equipment.is_equipped(item) and not item.is_locked and _merge_system.get_next_rarity(item.rarity) != "":
		# 鍛造中は 1 クリックで素材へ出し入れする（「素材に追加」ボタンはキーボード用に残す）。
		_toggle_merge_material(item)
		return
	_refresh()
	call_deferred("_focus_inventory_item", item)
	if _right_mode == "details":
		_popup_pinned = true
		forge_panel.show()
		_position_item_popup()

func _refresh_comparison() -> void:
	# Keep the reading position on same-item refreshes; a new selection starts at its name.
	var reading_position := comparison.get_v_scroll_bar().value if _comparison_item == _selected else 0.0
	_comparison_item = _selected
	if _selected == null:
		detail_icon.texture = null
		detail_name.text = "装備を選択"
		detail_name.tooltip_text = ""
		detail_meta.text = "レア度 / 部位"
		detail_rank.text = "◇ ◇ ◇"
		current_equipped_icon.texture = null
		comparison_summary.text = "[b]比較[/b]\n現在装備なし"
		PixelUIStyle.apply_panel(detail_icon_frame, Color("52606f"))
		comparison.text = "所持装備はありません"
		comparison.get_v_scroll_bar().value = 0.0
		equip_button.disabled = true
		unequip_button.disabled = true
		add_material_button.disabled = true
		lock_button.disabled = true
		favorite_button.disabled = true
		lock_button.text = ""
		(lock_button.get_node("LockGlyph") as LockGlyph).locked = false
		(lock_button.get_node("LockGlyph") as LockGlyph).queue_redraw()
		return
	detail_icon.texture = _load_trimmed_icon(_selected.icon_path)
	detail_name.text = _selected.display_name
	detail_name.tooltip_text = _selected.display_name
	detail_name.add_theme_color_override("font_color", Color("f1e3c8"))
	detail_name.add_theme_color_override("font_color", _selected.get_rarity_color().lightened(0.3))
	var kind_text := ""
	if _selected.slot == "weapon":
		var kind_profiles: Dictionary = (_equipment.get_parent() as Player).weapon_manager.equipment_attack.PROFILES
		kind_text = " ・ " + String(kind_profiles.get(_selected.attack_kind, kind_profiles.slash).name)
	detail_meta.text = "%s ・ %s%s" % [RARITY_NAMES.get(_selected.rarity, _selected.rarity), _selected.get_slot_display_name(), kind_text]
	detail_meta.tooltip_text = _selected.get_slot_display_name()
	detail_meta.add_theme_color_override("font_color", _selected.get_rarity_color().lightened(0.2))
	# 装備スコアと、同じ部位の装備中との差を一行で。
	var score := item_score(_selected)
	var score_delta := _score_delta(_selected)
	if _equipment.is_equipped(_selected):
		detail_rank.text = "装備スコア %d ・ 装備中" % roundi(score)
		detail_rank.add_theme_color_override("font_color", Color("9fe6c6"))
	elif _equipment.get_equipped(_selected.slot) == null:
		detail_rank.text = "装備スコア %d ・ この部位は未装備" % roundi(score)
		detail_rank.add_theme_color_override("font_color", Color("69f092"))
	else:
		var sign := "+" if score_delta >= 0 else "−"
		detail_rank.text = "装備スコア %d　%s%d %s" % [roundi(score), sign, roundi(absf(score_delta)), "▲ 強くなる" if score_delta > 0.5 else ("▼ 弱くなる" if score_delta < -0.5 else "＝ 同等")]
		detail_rank.add_theme_color_override("font_color", Color("69f092") if score_delta > 0.5 else (Color("ff7a6a") if score_delta < -0.5 else Color("cccccc")))
	PixelUIStyle.apply_panel(detail_icon_frame, _selected.get_rarity_color())
	FrameArt.hide_old_ornament(detail_icon_frame)
	FrameArt.panel(detail_icon_frame, true, true)
	equip_button.disabled = _merge_in_progress or _equipment.is_equipped(_selected)
	equip_button.text = "装備中" if _equipment.is_equipped(_selected) else "装備する"
	var current := _equipment.get_equipped(_selected.slot)
	current_equipped_icon.texture = _load_trimmed_icon(current.icon_path) if current else null
	unequip_button.disabled = _merge_in_progress or not _equipment.is_equipped(_selected)
	favorite_button.disabled = _merge_in_progress
	favorite_button.modulate = Color.WHITE if _selected.is_favorite else Color(0.8, 0.8, 0.8, 1.0)
	PixelUIStyle.apply_button(favorite_button, Color("d6a957") if _selected.is_favorite else Color("52606f"))
	lock_button.disabled = _merge_in_progress
	lock_button.text = ""
	(lock_button.get_node("LockGlyph") as LockGlyph).locked = _selected.is_locked
	(lock_button.get_node("LockGlyph") as LockGlyph).queue_redraw()
	PixelUIStyle.apply_button(lock_button, Color("e0b960") if _selected.is_locked else Color("647384"))
	_refresh_add_material_button()
	# 比較カード：装備中の名前とスコア、入れ替えで「得るもの／失うもの」だけを短く。
	var stat_order := ["max_hp", "attack_power", "defense", "move_speed", "attack_speed", "crit_rate", "crit_damage"]
	if current == null or current == _selected:
		comparison_summary.text = "[color=#64baff]装備中[/color]\n%s" % ("この装備" if current == _selected else "なし ― 装備すると全能力が加わる")
	else:
		var gains: Array[String] = []
		var losses: Array[String] = []
		for stat_name in stat_order:
			var diff := _selected.get_stat(stat_name) - current.get_stat(stat_name)
			if absf(diff) < 0.0005:
				continue
			var text := "%s %s%s" % [STAT_NAMES[stat_name], "+" if diff > 0 else "−", _stat_display(stat_name, absf(diff))]
			if diff > 0:
				gains.append(text)
			else:
				losses.append(text)
		for effect in current.special_effects:
			if effect not in _selected.special_effects:
				losses.append("効果 " + _special_description(current, effect).get_slice("（", 0))
		for effect in _selected.special_effects:
			if effect not in current.special_effects:
				gains.append("効果 " + _special_description(_selected, effect).get_slice("（", 0))
		var summary := "[color=#64baff]装備中[/color] %s（スコア %d）" % [current.display_name, roundi(item_score(current))]
		if not gains.is_empty():
			summary += "\n[color=#65e878]得る  %s[/color]" % " / ".join(gains)
		if not losses.is_empty():
			summary += "\n[color=#ff8a7a]失う  %s[/color]" % " / ".join(losses)
		if gains.is_empty() and losses.is_empty():
			summary += "\n[color=#cccccc]能力は同じ[/color]"
		comparison_summary.text = summary
	var lines: Array[String] = []
	if _selected.slot == "weapon":
		var profiles: Dictionary = (_equipment.get_parent() as Player).weapon_manager.equipment_attack.PROFILES
		var profile: Dictionary = profiles.get(_selected.attack_kind, profiles.slash)
		lines.append("[color=#8dd9dd]◇ %s — %s[/color]" % [profile.name, profile.trait])
		lines.append("[color=#b8c5cd]間隔 %.2f秒 ・ 一撃 ×%.2f ・ 射程 %d[/color]" % [profile.interval, profile.power, int(profile.range)])
	# 能力は「この装備か装備中のどちらかが持つ行」だけ。0 ばかりの表にしない。
	lines.append("[table=6]")
	for stat_name in stat_order:
		var before := current.get_stat(stat_name) if current else 0.0
		var after := _selected.get_stat(stat_name)
		if absf(before) < 0.0005 and absf(after) < 0.0005:
			continue
		var arrow := "↑" if after > before else ("↓" if after < before else "=")
		var color := "#65e878" if after > before else ("#ff6969" if after < before else "#cccccc")
		lines.append("[cell]%s[/cell][cell expand=1]%s[/cell][cell][color=#9aa3ad]%s[/color][/cell][cell] → [/cell][cell][color=%s][b]%s[/b][/color][/cell][cell][color=%s]%s[/color][/cell]" % [_stat_icon(stat_name), STAT_NAMES[stat_name], _stat_display(stat_name, before), color, _stat_display(stat_name, after), color, arrow if arrow != "=" else " "])
	lines.append("[/table]")
	if not _selected.special_effects.is_empty():
		lines.append("[color=#d6a957]◇ パッシブ効果[/color]")
		for effect in _selected.special_effects:
			lines.append("[color=#f0dfbd]・%s[/color]" % _special_description(_selected, effect))
	else:
		lines.append("[color=#7f8b96]◇ パッシブ効果　なし[/color]")
	comparison.text = "\n".join(lines)
	comparison.add_theme_constant_override("table_h_separation", 9)
	comparison.add_theme_constant_override("table_v_separation", 5)
	comparison.get_v_scroll_bar().value = reading_position
	_schedule_layout_settle()

func _toggle_selected_lock() -> void:
	if _merge_in_progress or _selected == null:
		return
	_selected.is_locked = not _selected.is_locked
	if _selected.is_locked:
		_merge_materials.erase(_selected)
	_refresh()

func _toggle_selected_favorite() -> void:
	if _merge_in_progress or _selected == null:
		return
	_selected.is_favorite = not _selected.is_favorite
	_refresh()

func _refresh_add_material_button() -> void:
	add_material_button.text = "素材から戻す" if _selected in _merge_materials else "素材に追加"
	var reason := ""
	if _selected == null:
		reason = "装備を選択してください"
	elif _equipment.is_equipped(_selected):
		reason = "装備を外すと、素材へ追加できます"
	elif _selected.is_locked:
		reason = "ロック中の装備は素材にできません"
	elif _merge_system.get_next_rarity(_selected.rarity) == "":
		reason = "最高レア度は素材にできません"
	elif _selected not in _merge_materials:
		if _merge_materials.size() >= _needed_materials():
			reason = "素材枠がいっぱいです。右の素材を選択して取り外せます"
		elif not _merge_materials.is_empty() and _selected.rarity != _merge_materials[0].rarity:
			reason = "素材のレア度を揃えてください"
	add_material_button.disabled = _merge_in_progress or reason != ""
	add_material_button.tooltip_text = reason if reason != "" else "素材枠に置くだけでは消費されません"

func _refresh_rarity_counts() -> void:
	var counts := {"uncommon":0, "rare":0, "epic":0, "legendary":0, "mythic":0}
	for item in _equipment.get_all_inventory():
		if not item.is_locked and not _equipment.is_equipped(item):
			counts[item.rarity] = int(counts.get(item.rarity, 0)) + 1
	var ready_sets := 0
	for rarity in EquipmentMergeSystem.RARITY_ORDER:
		if _merge_system.get_next_rarity(rarity) != "":
			ready_sets += floori(float(counts[rarity]) / EquipmentMergeSystem.required_count(rarity))
	capacity_label.text = "%d / %d" % [_equipment.inventory.size(), EquipmentComponent.MAX_INVENTORY_SIZE]
	rarity_counts.text = " "
	rarity_counts.tooltip_text = "鍛造可能 %d組。装備中・保護中の品は素材対象外です。" % ready_sets

func _refresh_merge_view() -> void:
	forge_stage.custom_minimum_size.y = 64 if _needed_materials() > 3 else 138
	forge_caption.custom_minimum_size.y = 28
	material_slots.columns = 5 if _needed_materials() > 3 else 3
	_refresh_merge_slots()
	merge_preview_icon.texture = null
	if _merge_result != null:
		_show_merge_result(_merge_result)
	else:
		_show_merge_preview()
	var validation := _merge_system.get_merge_validation(_equipment, _merge_materials)
	var valid := bool(validation.get("valid", false)) and not _merge_in_progress
	merge_button.disabled = not valid
	merge_button.text = "合成中…" if _merge_in_progress else ("合成する" if valid else "素材 %d / %d" % [_merge_materials.size(), _needed_materials()])
	if _merge_in_progress:
		merge_notice.text = "装備を合成しています…"
		merge_notice.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35))
	elif _has_mixed_material_rarity():
		merge_notice.text = "素材のレアリティを統一してください"
		merge_notice.add_theme_color_override("font_color", Color(1.0, 0.42, 0.34))
	else:
		merge_notice.text = String(validation.get("reason", "必要数の素材を選択してください"))
		if valid:
			var rate := _merge_system.success_rate(_merge_materials[0].rarity)
			merge_notice.text = "下のとおり完成 ・ 必ず成功" if rate >= 0.999 else "成功率 %d%% ／ 失敗時 %d個消費・残り返却" % [roundi(rate*100), _merge_system.failure_loss(_merge_materials[0].rarity)]
		elif _merge_materials.is_empty():
			merge_notice.text = "同じレア度を3つ。枠1の部位が完成品の部位"
		merge_notice.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35) if valid else Color(0.68, 0.68, 0.74))
	var accent := _merge_materials[0].get_rarity_color() if valid and not _merge_materials.is_empty() else Color(0.32, 0.36, 0.42)
	PixelUIStyle.apply_button(merge_button, accent)
	var auto_candidates := _autofill_candidates()
	autofill_button.disabled = _merge_in_progress or auto_candidates.is_empty() or auto_candidates.size() != EquipmentMergeSystem.required_count(auto_candidates[0].rarity) or _merge_materials.size() == _needed_materials()
	autofill_button.text = "同部位でセット"
	clear_materials_button.disabled = _merge_in_progress or _merge_materials.is_empty()
	sort_button.disabled = _merge_in_progress
	rarity_filter.disabled = _merge_in_progress
	rarity_filter.tooltip_text = "所持品の表示だけを絞ります。セットした素材はそのまま残ります。"
	forge_caption.text = "同レア3つ → 1段上のレア度1つ（部位は主素材）"
	if _merge_result:
		forge_caption.text = "鍛造完了 — 装備詳細タブで確認・装備"
	elif valid:
		forge_caption.text = "刻印が共鳴しています。鍛造の準備完了。"

func _refresh_merge_slots() -> void:
	for index in _material_slot_buttons.size():
		var button := _material_slot_buttons[index]
		button.visible = index < _needed_materials()
		button.custom_minimum_size = Vector2(0, 48)
		button.icon = null
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", 28)
		button.add_theme_font_size_override("font_size", 18)
		if index >= _merge_materials.size():
			button.text = "主" if index == 0 else "%d" % (index + 1)
			button.tooltip_text = "所持品をクリックでセット（枠1＝主素材。完成品はその部位になる）"
			button.disabled = true
			PixelUIStyle.apply_button(button, Color(0.30, 0.34, 0.40))
			continue
		var item := _merge_materials[index]
		button.text = "主" if index == 0 else "外す"
		button.tooltip_text = "%s / %s\n%s決定で素材から取り外す" % [item.display_name, RARITY_NAMES.get(item.rarity, item.rarity), "主素材：完成品はこの部位になる\n" if index == 0 else ""]
		button.set_meta("material_item", item)
		button.disabled = _merge_in_progress
		button.icon = _load_trimmed_icon(item.icon_path)
		if button.icon:
			button.expand_icon = true
		PixelUIStyle.apply_button(button, item.get_rarity_color())

func _show_merge_preview() -> void:
	if _merge_materials.is_empty():
		merge_preview.text = "[b]同レア素材 → 上位装備1点[/b]\n未装備・未ロック品が対象。\n「合成する」で初めて消費します。"
		return
	var source_rarity := _merge_materials[0].rarity
	var next_rarity := _merge_system.get_next_rarity(source_rarity)
	if next_rarity == "":
		merge_preview.text = "[b]%s[/b]\n最高レアリティのため合成できません" % RARITY_NAMES.get(source_rarity, source_rarity)
		return
	var color := _rarity_color(next_rarity).lightened(0.28).to_html(false)
	var preview_item := _merge_system.preview_result(_equipment, _merge_materials)
	if preview_item == null:
		merge_preview.text = "[b]%s ×%d[/b] → [color=#%s][b]%s ×1[/b][/color]\n完成品は主素材（枠1）の部位を受け継ぐ。\n素材が揃うと完成品の名前と能力をここに表示。" % [
			RARITY_NAMES.get(source_rarity, source_rarity), _needed_materials(), color, RARITY_NAMES.get(next_rarity, next_rarity)]
		return
	if preview_item.icon_path != "" and ResourceLoader.exists(preview_item.icon_path):
		merge_preview_icon.texture = _load_trimmed_icon(preview_item.icon_path)
	var current := _equipment.get_equipped(preview_item.slot)
	var score := item_score(preview_item)
	var delta_text := ""
	if current != null:
		var delta := score - item_score(current)
		delta_text = "　[color=%s]%s%d vs 装備中[/color]" % ["#65e878" if delta > 0.5 else ("#ff8a7a" if delta < -0.5 else "#cccccc"), "+" if delta >= 0 else "−", roundi(absf(delta))]
	var stat_bits: Array[String] = []
	for stat_name in preview_item.stats:
		stat_bits.append("%s %s" % [STAT_NAMES.get(stat_name, stat_name), _stat_display(String(stat_name), preview_item.get_stat(String(stat_name)))])
	merge_preview.text = "[b]%s ×%d[/b] → [color=#%s][b]%s ×1[/b][/color]\n[color=#%s][b]%s[/b][/color]（%s）\n装備スコア %d%s\n%s" % [
		RARITY_NAMES.get(source_rarity, source_rarity), _needed_materials(), color, RARITY_NAMES.get(next_rarity, next_rarity),
		color, preview_item.display_name, preview_item.get_slot_display_name(), roundi(score), delta_text, " / ".join(stat_bits)]

func _show_merge_result(result: EquipmentData) -> void:
	if result.icon_path != "" and ResourceLoader.exists(result.icon_path):
		merge_preview_icon.texture = _load_trimmed_icon(result.icon_path)
		_forge_result_texture = merge_preview_icon.texture
	merge_preview.text = "[color=#%s][b]完成　%s[/b][/color]\n%s / %s\n能力比較は装備詳細タブに表示" % [result.get_rarity_color().lightened(0.28).to_html(false), result.display_name, RARITY_NAMES.get(result.rarity, result.rarity), result.get_slot_display_name()]

func _toggle_merge_material(item: EquipmentData) -> void:
	if _merge_in_progress or item == null or item.is_locked or _equipment.is_equipped(item):
		return
	if _merge_system.get_next_rarity(item.rarity) == "" or item not in _equipment.inventory:
		return
	if not _merge_materials.is_empty() and item.rarity != _merge_materials[0].rarity:
		return
	_merge_result = null
	if item in _merge_materials:
		_merge_materials.erase(item)
	elif _merge_materials.size() < _needed_materials():
		_merge_materials.append(item)
	_refresh()
	call_deferred("_focus_inventory_item", item)

func _remove_merge_material(index: int) -> void:
	if _merge_in_progress or index < 0 or index >= _merge_materials.size():
		return
	_merge_result = null
	var removed := _merge_materials[index]
	_merge_materials.remove_at(index)
	_refresh()
	call_deferred("_focus_inventory_item", removed)

func _has_mixed_material_rarity() -> bool:
	if _merge_materials.size() < 2:
		return false
	var rarity := _merge_materials[0].rarity
	for item in _merge_materials:
		if item.rarity != rarity:
			return true
	return false

func _special_description(item: EquipmentData, effect_id: String) -> String:
	match effect_id:
		"kill_heal": return "命喰らい（敵撃破時HPを%.0f回復）" % item.get_special_value(effect_id, "heal_flat")
		"negate_hit": return "守護の残響（%.0f%%で被弾無効）" % (item.get_special_value(effect_id, "chance") * 100.0)
		"low_hp_power": return "窮地の力（HP%.0f%%以下で攻撃力+%.0f%%）" % [item.get_special_value(effect_id, "hp_threshold") * 100.0, item.get_special_value(effect_id, "damage_bonus") * 100.0]
		_: return effect_id

func _on_equipment_double_click(event: InputEvent, item: EquipmentData, slot: String) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed or not mouse.double_click:
		return
	if not _is_open or _merge_in_progress or item == null:
		return
	call_deferred("_toggle_equipment_double_click", item, slot)

func _toggle_equipment_double_click(item: EquipmentData, slot: String) -> void:
	if not is_instance_valid(self) or not _is_open or _merge_in_progress or _equipment == null or item not in _equipment.inventory:
		return
	if slot != "" or _equipment.is_equipped(item):
		_equipment.unequip(item.slot)
	else:
		_equipment.equip(item)

func _equip_selected() -> void:
	if _equipment and _selected and not _merge_in_progress:
		_equipment.equip(_selected)

func _unequip_selected_slot() -> void:
	if _equipment and _selected and _equipment.is_equipped(_selected) and not _merge_in_progress:
		_equipment.unequip(_selected.slot)

func _merge_selected() -> void:
	if _equipment == null or _merge_in_progress:
		return
	var validation := _merge_system.get_merge_validation(_equipment, _merge_materials)
	if not bool(validation.get("valid", false)):
		_refresh_merge_view()
		return
	var animation_sources := _capture_animation_sources()
	_merge_in_progress = true
	_pending_merge_result = null
	_refresh_merge_view()
	var result := _merge_system.merge_materials(_equipment, _merge_materials)
	if result == null:
		_merge_in_progress = false
		_merge_result = null
		var loss := _merge_system.last_failure_loss
		_refresh()
		if loss > 0:
			merge_notice.text = "鍛造失敗：%d個消費。残りの素材は保持しました。" % loss
			forge_caption.text = "素材を補充して再挑戦できます"
		return
	_pending_merge_result = result
	_refresh()
	_play_merge_animation(result, animation_sources)

func _capture_animation_sources() -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	for index in _merge_materials.size():
		var button := _material_slot_buttons[index]
		var texture: Texture2D
		if _merge_materials[index].icon_path != "" and ResourceLoader.exists(_merge_materials[index].icon_path):
			texture = _load_trimmed_icon(_merge_materials[index].icon_path)
		sources.append({"center": button.global_position + button.size * 0.5, "texture": texture})
	return sources

func _play_merge_animation(result: EquipmentData, sources: Array[Dictionary]) -> void:
	_clear(merge_animation_layer)
	merge_animation_layer.visible = true
	_forge_elapsed = 0.0
	_forge_result_texture = _load_trimmed_icon(result.icon_path)
	var target := forge_stage.global_position + _forge_center()
	var rarity_index := maxi(0, EquipmentMergeSystem.RARITY_ORDER.find(result.rarity))
	var accent := result.get_rarity_color()
	for index in sources.size():
		var ghost := TextureRect.new()
		ghost.custom_minimum_size = Vector2(58, 58)
		ghost.size = Vector2(58, 58)
		ghost.texture = sources[index].get("texture") as Texture2D
		ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ghost.pivot_offset = ghost.size * 0.5
		merge_animation_layer.add_child(ghost)
		ghost.global_position = Vector2(sources[index].get("center")) - ghost.size * 0.5
		var ghost_tween := _track_forge_tween(ghost)
		ghost_tween.tween_interval(index * 0.08)
		ghost_tween.tween_property(ghost, "global_position", target - ghost.size * 0.5, 0.48).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		ghost_tween.parallel().tween_property(ghost, "scale", Vector2(0.30, 0.30), 0.48).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		ghost_tween.tween_callback(ghost.hide)
	_merge_animation_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_merge_animation_tween.tween_interval(0.66)
	_merge_animation_tween.tween_callback(_spawn_merge_impact.bind(target, accent, rarity_index))
	_merge_animation_tween.tween_interval(0.98)
	_merge_animation_tween.tween_callback(_complete_merge_animation)
	forge_caption.text = "炉に火が入り、素材の刻印が共鳴する…"

func _track_forge_tween(node: Node) -> Tween:
	var tween := node.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_forge_tweens.append(tween)
	return tween

func _spawn_merge_impact(target: Vector2, accent: Color, rarity_index: int) -> void:
	if not _merge_in_progress or merge_animation_layer.get_node_or_null("ForgeAwakening") != null:
		return
	AudioManager.play_sfx("level_up")
	forge_caption.text = "遺物覚醒\n新たな力が、目を覚ます。"
	# 炉心の発生→拡大→破片の崩壊は生成済み6フレーム内で描き、Nodeを飛ばさない。
	# 戦闘VFXは装備画面のPauseで寿命が止まるため、その予算とは別に炉専用1個を確保する。
	var awakening := PixelSpriteVFX.new()
	if not awakening.configure("forge_awaken", Vector2.ONE * (128.0 + rarity_index * 12.0), 0.78):
		awakening.free()
		return
	awakening.name = "ForgeAwakening"
	# 原画の金/白い炉心を強い青・紫の乗算で濁らせない。Rarityは弱い色味と外枠で示す。
	awakening.modulate = accent.lightened(0.75)
	merge_animation_layer.add_child(awakening)
	awakening.play_once(target)

func _complete_merge_animation() -> void:
	if not _merge_in_progress:
		return
	if _merge_animation_tween and _merge_animation_tween.is_valid():
		_merge_animation_tween.kill()
	for tween in _forge_tweens:
		if tween.is_valid():
			tween.kill()
	_forge_tweens.clear()
	_merge_in_progress = false
	_has_completed_merge_animation = true
	_merge_result = _pending_merge_result
	_pending_merge_result = null
	_merge_materials.clear()
	if _merge_result:
		_selected = _merge_result
		# The new treasure must be visible even when its ingredients were filtered.
		_rarity_filter = ""
		rarity_filter.select(0)
	_clear(merge_animation_layer)
	merge_animation_layer.visible = false
	_set_right_mode("forge")
	_refresh()
	if _merge_result:
		if not autofill_button.disabled:
			autofill_button.grab_focus()
		else:
			_focus_inventory_item(_selected)

func _forge_center() -> Vector2:
	return (forge_stage.size * 0.5).round()

## A pixel-built forge tableau. Static while browsing; only the 1.64s ritual redraws.
func _draw_forge_stage() -> void:
	var center := _forge_center()
	var extent := minf(112.0, minf(forge_stage.size.y - 12.0, forge_stage.size.x - 24.0))
	var art := preload("res://assets/visuals/ember_v5/prop_3.png")
	forge_stage.draw_texture_rect(art, Rect2(center - Vector2.ONE * extent * .5, Vector2.ONE * extent), false)
	var ready := _merge_materials.size() == _needed_materials() or _merge_result != null
	if ready or _merge_in_progress:
		var accent := _merge_result.get_rarity_color() if _merge_result else _rarity_color(_merge_system.get_next_rarity(_merge_materials[0].rarity)) if not _merge_materials.is_empty() else Color("7abeb6")
		var pulse := .7 + .3 * sin(_forge_elapsed * 9.0) if _merge_in_progress else 1.0
		for side in [-1,1]:
			var p := center + Vector2(side * (extent * .5 + 12), -8)
			forge_stage.draw_line(p-Vector2(0,5),p+Vector2(0,5),Color(accent,pulse),1,false)
			forge_stage.draw_line(p-Vector2(3,0),p+Vector2(3,0),Color(accent,pulse),1,false)

func _rarity_color(rarity: String) -> Color:
	var probe := EquipmentData.new()
	probe.rarity = rarity
	return probe.get_rarity_color()

func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _setup_compact_bag() -> void:
	# A bounded scroll surface prevents wrapped detail text or forge controls from
	# carrying an old minimum height into the floating crafting panel.
	_forge_scroll = ScrollContainer.new()
	_forge_scroll.name = "ForgeScroll"
	_forge_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_forge_scroll.follow_focus = true
	_forge_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_forge_scroll.hide()
	forge_view.get_parent().add_child(_forge_scroll)
	forge_view.reparent(_forge_scroll)
	forge_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forge_view.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	forge_panel.reparent(self)
	forge_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	forge_panel.custom_minimum_size = Vector2(390, 0)
	forge_panel.size = Vector2(390, 620)
	forge_panel.hide()
	_popup_ready = true
	_bag_forge_button = Button.new()
	_bag_forge_button.text = "鍛造"
	_bag_forge_button.custom_minimum_size = Vector2(66, 32)
	inventory_tab.get_parent().add_child(_bag_forge_button)
	_bag_forge_button.add_theme_stylebox_override("normal", FrameArt.box(true, 6))
	_bag_forge_button.pressed.connect(func(): _set_right_mode("details" if _right_mode == "forge" else "forge"))
	var close_popup := Button.new()
	close_popup.text = "×"
	close_popup.custom_minimum_size = Vector2(60, 48) if DisplayServer.is_touchscreen_available() or "--touch-preview" in OS.get_cmdline_user_args() else Vector2(32, 32)
	detail_tab.get_parent().add_child(close_popup)
	close_popup.pressed.connect(func():
		if not _merge_in_progress:
			_set_right_mode("details")
			forge_panel.hide()
	)
	connection_lines.hide()
	for button in _category_buttons:
		button.custom_minimum_size = Vector2(32, 32)
		button.add_theme_constant_override("icon_max_width", 20)
		for child in button.get_children():
			if child is TextureRect:
				child.offset_left = 5
				child.offset_right = -5
				child.offset_top = 4
				child.offset_bottom = -4

func _attach_item_hover(button: Button, item: EquipmentData) -> void:
	var art := TextureRect.new()
	art.texture = _load_trimmed_icon(item.icon_path)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ink := ShaderMaterial.new()
	ink.shader = OUTLINE_SHADER
	ink.set_shader_parameter("rarity_color", item.get_rarity_color())
	art.material = ink
	button.icon = null
	button.tooltip_text = ""
	button.add_child(art)
	button.move_child(art, 0)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_left = 3
	art.offset_top = 3
	art.offset_right = -3
	art.offset_bottom = -3
	button.mouse_entered.connect(_show_item_hover.bind(item, button, false))
	button.focus_entered.connect(func():
		# Keyboard selection gets the same comparison without needing a pointer.
		if Input.is_action_pressed("ui_left") or Input.is_action_pressed("ui_right") or Input.is_action_pressed("ui_up") or Input.is_action_pressed("ui_down"):
			_show_item_hover(item, button, true)
	)

func _show_item_hover(item: EquipmentData, source: Control, pinned: bool = false) -> void:
	if not _is_open or _merge_in_progress or _right_mode == "forge" or _drag_item != null:
		return
	_selected = item
	_hover_source = source
	_popup_pinned = pinned
	_hover_grace = 0.24
	forge_panel.show()
	_refresh_comparison()
	_position_item_popup()

func _position_item_popup() -> void:
	if _popup_ready:
		_style_inspection_popup()
	if not _popup_ready:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var touch_layout := DisplayServer.is_touchscreen_available() or "--touch-preview" in OS.get_cmdline_user_args()
	if touch_layout:
		forge_panel.custom_minimum_size.x = minf(560.0, viewport_size.x - 32.0)
		forge_panel.size = Vector2(forge_panel.custom_minimum_size.x, minf(700.0, viewport_size.y - 32.0))
		forge_panel.position = (viewport_size - forge_panel.size) * 0.5
		return
	forge_panel.size = Vector2(390, 700)
	if _right_mode == "details":
		forge_panel.size = Vector2(390, clampf(forge_panel.get_combined_minimum_size().y + 12.0, 420.0, viewport_size.y - 16.0))
	var bag := ($Background as Control).get_global_rect()
	var x := bag.end.x + 8.0
	if x + forge_panel.size.x > viewport_size.x - 8.0:
		x = maxf(8.0, bag.position.x - forge_panel.size.x - 8.0)
	var y := bag.position.y
	if _right_mode == "details" and is_instance_valid(_hover_source):
		var origin := _hover_source.get_global_rect()
		x = origin.end.x + 10.0
		if x + forge_panel.size.x > viewport_size.x - 8.0:
			x = origin.position.x - forge_panel.size.x - 10.0
		y = origin.position.y - 60.0
	forge_panel.position = Vector2(clampf(x, 8.0, maxf(8.0, viewport_size.x - forge_panel.size.x - 8.0)), clampf(y, 8.0, maxf(8.0, viewport_size.y - forge_panel.size.y - 8.0)))

func _style_inspection_popup() -> void:
	var inspecting := _right_mode == "details"
	for node in forge_panel.find_children("*", "", true, false):
		if node is CanvasItem and node.name in ["FrameArt", "PlaqueArt", "RelicOrnamentLayer"]:
			node.visible = not inspecting and node.name != "RelicOrnamentLayer"
	if not inspecting:
		forge_panel.add_theme_stylebox_override("panel", FrameArt.box(false, 0))
		return
	var accent := _selected.get_rarity_color() if _selected else Color("8cbab9")
	var shell := StyleBoxFlat.new()
	shell.bg_color = Color(0.025, 0.032, 0.042, 0.97 if DisplayServer.is_touchscreen_available() or "--touch-preview" in OS.get_cmdline_user_args() else 0.91)
	shell.border_color = Color(accent, 0.75)
	shell.border_width_top = 2
	shell.border_width_left = 1
	shell.border_width_right = 1
	shell.border_width_bottom = 1
	shell.shadow_color = Color(0, 0, 0, 0.45)
	shell.shadow_size = 12
	forge_panel.add_theme_stylebox_override("panel", shell)
	detail_icon_frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var card := detail_view.get_node("ComparisonCard") as PanelContainer
	var inset := StyleBoxFlat.new()
	inset.bg_color = Color(0.12, 0.14, 0.16, 0.38)
	card.add_theme_stylebox_override("panel", inset)
	for button in [detail_tab, forge_tab, equip_button, unequip_button, favorite_button, lock_button]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.16, 0.19, 0.22, 0.8) if state == "hover" else Color(0.07, 0.085, 0.10, 0.6)
			style.set_content_margin_all(5)
			button.add_theme_stylebox_override(state, style)
func _start_equipment_drag(_position: Vector2, item: EquipmentData, source_slot: String, source: Control) -> Variant:
	if not _is_open or _merge_in_progress or _right_mode == "forge" or item == null or item not in _equipment.inventory:
		return null
	_drag_item = item
	_popup_pinned = false
	forge_panel.hide()
	_highlight_drop_slots(item)
	var preview := Control.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := TextureRect.new()
	art.texture = _load_trimmed_icon(item.icon_path)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.position = Vector2(-24, -24)
	art.size = Vector2(48, 48)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ink := ShaderMaterial.new()
	ink.shader = OUTLINE_SHADER
	ink.set_shader_parameter("rarity_color", item.get_rarity_color())
	art.material = ink
	preview.add_child(art)
	source.set_drag_preview(preview)
	return {"equipment_owner": _equipment, "item": item, "source_slot": source_slot}

func _can_drop_equipment(_position: Vector2, data: Variant, target_slot: String) -> bool:
	if not _is_open or _merge_in_progress or _right_mode == "forge" or not data is Dictionary:
		return false
	if data.get("equipment_owner") != _equipment:
		return false
	var item := data.get("item") as EquipmentData
	if item == null or item not in _equipment.inventory:
		return false
	if target_slot == "":
		return data.get("source_slot", "") == item.slot and _equipment.get_equipped(item.slot) == item
	return item.slot == target_slot

func _drop_equipment(position: Vector2, data: Variant, target_slot: String) -> void:
	if not _can_drop_equipment(position, data, target_slot):
		return
	var item := data.get("item") as EquipmentData
	_selected = item
	_drag_item = null
	# Commit after the GUI finishes dispatching drop; equipment signals rebuild the controls.
	_commit_equipment_drop.call_deferred(item, target_slot)

func _commit_equipment_drop(item: EquipmentData, target_slot: String) -> void:
	if not _is_open or _merge_in_progress or item not in _equipment.inventory:
		return
	if target_slot == "":
		if _equipment.get_equipped(item.slot) == item:
			_equipment.unequip(item.slot)
	elif item.slot == target_slot:
		_merge_materials.erase(item)
		_equipment.equip(item)
	forge_panel.hide()
	_highlight_drop_slots(null)

func _highlight_drop_slots(item: EquipmentData) -> void:
	for container in [left_slots, right_slots, top_slot, bottom_slot]:
		for child in container.get_children():
			if child is Button and child.has_meta("equipment_slot"):
				for state in ["normal", "hover"]:
					var style := child.get_theme_stylebox(state).duplicate() as StyleBoxFlat
					if style:
						style.border_color = Color("71e2d2") if item and item.slot == child.get_meta("equipment_slot") else Color("3d3b49")
						child.add_theme_stylebox_override(state, style)
