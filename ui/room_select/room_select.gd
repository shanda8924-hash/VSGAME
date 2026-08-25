extends CanvasLayer
class_name RoomSelect

signal room_chosen(choice: Dictionary)
signal concept_board_requested()

@onready var title_label: Label = $Background/CenterContainer/VBoxContainer/Title
@onready var choices: HBoxContainer = $Background/CenterContainer/VBoxContainer/Choices
@onready var concept_board_button: Button = $Background/CenterContainer/VBoxContainer/ConceptBoardButton

func _ready() -> void:
	visible = false
	concept_board_button.visible = false
	concept_board_button.pressed.connect(_request_concept_board)
	PixelUIStyle.apply_tree(self)

func show_choices(current_room: int, total_rooms: int, candidates: Array[Dictionary], area_transition: String = "") -> void:
	if candidates.is_empty():
		return
	GameManager.request_modal(func(): _open(current_room, total_rooms, candidates, area_transition))

func _open(current_room: int, total_rooms: int, candidates: Array[Dictionary], area_transition: String = "") -> void:
	GameManager.open_modal()
	visible = true
	var transition_line := "%s\n" % area_transition if area_transition != "" else ""
	title_label.text = "%sルーム %d クリア\n次のルームを選択  %d / %d" % [transition_line, current_room, current_room + 1, total_rooms]
	for child in choices.get_children():
		child.queue_free()
	for candidate in candidates:
		choices.add_child(_build_card(candidate))
	if choices.get_child_count() > 0:
		(choices.get_child(0) as Button).grab_focus.call_deferred()

func _build_card(candidate: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(320, 190)
	button.text = "%s\n\n%s\n%s" % [candidate.get("icon", "◆"), candidate.get("title", "ルーム"), candidate.get("description", "")]
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 21)
	var accent := Color.from_string(String(candidate.get("color", "#d9dde8")), Color.WHITE)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.05, 0.075, 0.98)
	style.border_color = accent
	style.set_border_width_all(4)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	style.set_content_margin_all(16)
	button.add_theme_stylebox_override("normal", style)
	var highlighted := style.duplicate() as StyleBoxFlat
	highlighted.bg_color = Color(accent.r * 0.18, accent.g * 0.18, accent.b * 0.18, 0.99)
	highlighted.border_color = accent.lightened(0.2)
	highlighted.set_border_width_all(7)
	button.add_theme_stylebox_override("hover", highlighted)
	button.add_theme_stylebox_override("pressed", highlighted)
	button.add_theme_stylebox_override("focus", highlighted)
	button.set_meta("room_choice", candidate.duplicate(true))
	button.pressed.connect(_choose.bind(candidate))
	return button

func _choose(candidate: Dictionary) -> void:
	AudioManager.play_sfx("ui_click")
	visible = false
	GameManager.close_modal()
	room_chosen.emit(candidate.duplicate(true))

func _request_concept_board() -> void:
	AudioManager.play_sfx("ui_click")
	visible = false
	GameManager.close_modal()
	concept_board_requested.emit()
