extends Control
class_name TitleScreen

@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var start_hint: Label = $CenterContainer/VBoxContainer/StartHint
@onready var mode_select: VBoxContainer = $CenterContainer/VBoxContainer/ModeSelect
@onready var menu_frame: Panel = $MenuFrame
var _owned_ui_events: Array[Dictionary] = []


func _ready() -> void:
	_register_controller_ui("ui_accept", JOY_BUTTON_A)
	_register_controller_ui("ui_cancel", JOY_BUTTON_B)
	theme = PixelUIStyle.shared_theme()
	menu_frame.hide()
	$BackgroundShade.hide()
	$CenterContainer/VBoxContainer/Crest.hide()
	$CenterContainer/VBoxContainer/TitleLabel.hide()
	for button in [$CenterContainer/VBoxContainer/StartButton, $CenterContainer/VBoxContainer/ModeSelect/NormalButton, $CenterContainer/VBoxContainer/ModeSelect/TestButton, $CenterContainer/VBoxContainer/ModeSelect/BackButton]:
		_style_title_button(button)
	start_button.pressed.connect(_on_start_pressed)
	$CenterContainer/VBoxContainer/ModeSelect/NormalButton.pressed.connect(_on_normal_pressed)
	$CenterContainer/VBoxContainer/ModeSelect/TestButton.pressed.connect(_on_test_mode_pressed)
	$CenterContainer/VBoxContainer/ModeSelect/BackButton.pressed.connect(_on_back_pressed)
	var test_button := $CenterContainer/VBoxContainer/ModeSelect/TestButton as Button
	if not OS.is_debug_build():
		test_button.disabled = true
		test_button.text = "演出確認室：デバッグ版のみ"
	var mode_buttons: Array[Button] = [
		$CenterContainer/VBoxContainer/ModeSelect/NormalButton,
	]
	if not test_button.disabled:
		mode_buttons.append(test_button)
	mode_buttons.append($CenterContainer/VBoxContainer/ModeSelect/BackButton)
	for index in mode_buttons.size():
		var button := mode_buttons[index]
		var previous := mode_buttons[posmod(index - 1, mode_buttons.size())]
		var following := mode_buttons[(index + 1) % mode_buttons.size()]
		button.focus_neighbor_top = button.get_path_to(previous)
		button.focus_previous = button.focus_neighbor_top
		button.focus_neighbor_bottom = button.get_path_to(following)
		button.focus_next = button.focus_neighbor_bottom
	_set_expanded(false)
	start_button.grab_focus.call_deferred()


func _set_expanded(expanded: bool) -> void:
	$CenterContainer/VBoxContainer/Subtitle.visible = not expanded

func _style_title_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 28 if button == start_button else 23)
	button.add_theme_color_override("font_color", Color("d5d0bd"))
	button.add_theme_color_override("font_focus_color", Color("9ef1e6"))
	button.add_theme_color_override("font_hover_color", Color("fff0c9"))
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("6f7a80"))
	button.add_theme_color_override("font_shadow_color", Color("050b12"))
	button.add_theme_constant_override("shadow_offset_y", 2)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.02, 0.04, 0.06, 0.22) if state in ["hover", "pressed"] else Color.TRANSPARENT
		if state == "focus":
			style.border_width_bottom = 1
			style.border_color = Color(0.45, 0.8, 0.78, 0.65)
		style.content_margin_left = 24
		style.content_margin_right = 24
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		button.add_theme_stylebox_override(state, style)


func _register_controller_ui(action: String, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	if InputMap.action_has_event(action, event):
		return
	InputMap.action_add_event(action, event)
	_owned_ui_events.append({"action": action, "event": event})


func _exit_tree() -> void:
	for binding in _owned_ui_events:
		InputMap.action_erase_event(binding.action, binding.event)


func _unhandled_input(event: InputEvent) -> void:
	if mode_select.visible and event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _on_start_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	start_button.hide()
	start_hint.hide()
	mode_select.show()
	_set_expanded(true)
	$CenterContainer/VBoxContainer/ModeSelect/NormalButton.grab_focus.call_deferred()


func _on_normal_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	get_tree().change_scene_to_file("res://ui/home/home.tscn")


func _on_test_mode_pressed() -> void:
	if not OS.is_debug_build():
		return
	AudioManager.play_sfx("ui_click")
	get_tree().change_scene_to_file("res://scenes/developer_test_lab.tscn")


func _on_back_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	mode_select.hide()
	start_button.show()
	start_hint.show()
	_set_expanded(false)
	start_button.grab_focus.call_deferred()
