extends Control
class_name TitleScreen

@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var mode_select: VBoxContainer = $CenterContainer/VBoxContainer/ModeSelect

func _ready() -> void:
	PixelUIStyle.apply_tree(self)
	start_button.pressed.connect(_on_start_pressed)
	$CenterContainer/VBoxContainer/ModeSelect/NormalButton.pressed.connect(_on_normal_pressed)
	$CenterContainer/VBoxContainer/ModeSelect/TestButton.pressed.connect(_on_test_mode_pressed)
	$CenterContainer/VBoxContainer/ModeSelect/BackButton.pressed.connect(_on_back_pressed)
	var test_button := $CenterContainer/VBoxContainer/ModeSelect/TestButton as Button
	if not OS.is_debug_build():
		test_button.disabled = true
		test_button.text = "テストモード / デバッグ版のみ"
	start_button.grab_focus.call_deferred()

func _on_start_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	start_button.hide()
	mode_select.show()
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
	start_button.grab_focus.call_deferred()
