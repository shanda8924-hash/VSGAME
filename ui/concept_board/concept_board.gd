extends CanvasLayer
class_name ConceptBoard

signal board_closed()

@export var concept_system_path: NodePath

@onready var concept_system: ConceptSystem = get_node(concept_system_path)
@onready var title_label: Label = $Background/Center/Panel/Margin/VBox/Title
@onready var chain_rows: VBoxContainer = $Background/Center/Panel/Margin/VBox/ChainRows
@onready var owned_title: Label = $Background/Center/Panel/Margin/VBox/OwnedTitle
@onready var owned_grid: GridContainer = $Background/Center/Panel/Margin/VBox/OwnedGrid
@onready var clear_button: Button = $Background/Center/Panel/Margin/VBox/Controls/Clear
@onready var done_button: Button = $Background/Center/Panel/Margin/VBox/Controls/Done

var _selected_chain: int = 0
var _selected_slot: String = "trigger"


func _ready() -> void:
	visible = false
	PixelUIStyle.apply_tree(self)
	clear_button.pressed.connect(_clear_selected)
	done_button.pressed.connect(_close)
	concept_system.board_changed.connect(_refresh)


func show_board(title: String = "コンセプトボード — スロットを選び、取得Conceptを装備") -> void:
	GameManager.request_modal(func(): _open(title))


func _open(title: String) -> void:
	GameManager.open_modal()
	visible = true
	title_label.text = title
	_refresh()
	_focus_selected_slot.call_deferred()


func _refresh() -> void:
	if not is_node_ready():
		return
	for child in chain_rows.get_children():
		chain_rows.remove_child(child)
		child.queue_free()
	for chain_index in 2:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var label := Label.new()
		label.custom_minimum_size = Vector2(100, 70)
		label.text = "チェーン %s" % String.chr(65 + chain_index)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 20)
		row.add_child(label)
		for slot_type in ["trigger", "skill", "modifier"]:
			row.add_child(_build_slot_button(chain_index, slot_type))
		chain_rows.add_child(row)
	_refresh_owned()
	_focus_selected_slot.call_deferred()


func _focus_selected_slot() -> void:
	if not visible:
		return
	for row in chain_rows.get_children():
		for child in row.get_children():
			if child is Button and int(child.get_meta("chain_index", -1)) == _selected_chain and String(child.get_meta("slot_type", "")) == _selected_slot:
				child.grab_focus()
				return
	done_button.grab_focus()


func _build_slot_button(chain_index: int, slot_type: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(240, 72)
	var concept_id := String(concept_system.get_chain(chain_index).get(slot_type, ""))
	var data := DataLoader.get_concept(concept_id) if concept_id != "" else null
	var slot_label: String = {"trigger":"起点", "skill":"スキル", "modifier":"補助"}.get(slot_type, slot_type)
	button.text = "%s\n%s" % [slot_label, data.display_name if data else "— 空き —"]
	button.set_meta("chain_index", chain_index)
	button.set_meta("slot_type", slot_type)
	var selected := chain_index == _selected_chain and slot_type == _selected_slot
	PixelUIStyle.apply_button(button, Color("#ffffff") if selected else Color("#586174"))
	button.pressed.connect(_select_slot.bind(chain_index, slot_type))
	return button


func _select_slot(chain_index: int, slot_type: String) -> void:
	_selected_chain = chain_index
	_selected_slot = slot_type
	AudioManager.play_sfx("ui_click")
	_refresh()


func _refresh_owned() -> void:
	for child in owned_grid.get_children():
		owned_grid.remove_child(child)
		child.queue_free()
	var type_label: String = {"trigger":"起点", "skill":"スキル", "modifier":"補助"}.get(_selected_slot, _selected_slot)
	owned_title.text = "所持%s — 選択してチェーン %sへ装備" % [type_label, String.chr(65 + _selected_chain)]
	var owned := concept_system.get_owned_concepts(_selected_slot)
	if owned.is_empty():
		var empty := Label.new()
		empty.text = "この種類のコンセプトはまだ取得していません"
		owned_grid.add_child(empty)
		return
	for data in owned:
		var button := Button.new()
		button.custom_minimum_size = Vector2(245, 70)
		button.text = "%s\n%s" % [data.display_name, data.description]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.set_meta("concept_id", data.id)
		PixelUIStyle.apply_button(button, Color("#6f8ba7"))
		button.pressed.connect(_equip.bind(data.id))
		owned_grid.add_child(button)


func _equip(concept_id: String) -> void:
	concept_system.equip_concept(_selected_chain, _selected_slot, concept_id)
	AudioManager.play_sfx("ui_click")


func _clear_selected() -> void:
	concept_system.unequip_concept(_selected_chain, _selected_slot)
	AudioManager.play_sfx("ui_click")


func _close() -> void:
	visible = false
	AudioManager.play_sfx("ui_click")
	GameManager.close_modal()
	board_closed.emit()
