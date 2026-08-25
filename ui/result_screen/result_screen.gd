extends CanvasLayer
class_name ResultScreen
## リザルト画面。

@onready var time_label: Label = $CenterContainer/VBoxContainer/TimeLabel
@onready var kill_label: Label = $CenterContainer/VBoxContainer/KillLabel
@onready var retry_button: Button = $CenterContainer/VBoxContainer/RetryButton
@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var title_button: Button = $CenterContainer/VBoxContainer/TitleButton

func _ready() -> void:
	visible = false
	PixelUIStyle.apply_tree(self)
	EventBus.run_ended.connect(_on_run_ended)
	EventBus.run_cleared.connect(_on_run_cleared)
	retry_button.pressed.connect(_on_retry_pressed)
	title_button.pressed.connect(_on_title_pressed)

func _on_run_ended(survived_seconds: float, kill_count: int) -> void:
	SaveManager.update_best_survival(survived_seconds)
	SaveManager.add_meta_currency(kill_count)
	get_tree().paused = true
	visible = true
	title_label.text = "ゲームオーバー"
	time_label.text = "生存時間: %d秒" % int(survived_seconds)
	kill_label.text = "撃破数: %d体" % kill_count
	retry_button.grab_focus.call_deferred()

func _on_run_cleared(room_count: int, elapsed_seconds: float, kill_count: int) -> void:
	SaveManager.update_best_survival(elapsed_seconds)
	SaveManager.add_meta_currency(kill_count)
	get_tree().paused = true
	visible = true
	title_label.text = "クリア！"
	time_label.text = "全%dルーム踏破  /  %d秒" % [room_count, int(elapsed_seconds)]
	kill_label.text = "撃破数: %d体" % kill_count
	retry_button.grab_focus.call_deferred()

func _on_retry_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_title_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/title.tscn")
