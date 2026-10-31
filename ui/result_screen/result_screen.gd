extends CanvasLayer
class_name ResultScreen
## 一回の探索を、古王国の踏破記録として見せるリザルト画面。

@onready var time_label: Label = $CenterContainer/VBoxContainer/TimeLabel
@onready var kill_label: Label = $CenterContainer/VBoxContainer/KillLabel
@onready var reward_label: Label = $CenterContainer/VBoxContainer/RewardLabel
@onready var retry_button: Button = $CenterContainer/VBoxContainer/RetryButton
@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var eyebrow_label: Label = $CenterContainer/VBoxContainer/Eyebrow
@onready var title_button: Button = $CenterContainer/VBoxContainer/TitleButton


func _ready() -> void:
	visible = false
	PixelUIStyle.apply_tree(self)
	PixelUIStyle.add_ornament($Background, "backdrop", PixelUIStyle.JEWEL)
	PixelUIStyle.apply_major_panel($ResultFrame, PixelUIStyle.BORDER_HOVER)
	PixelUIStyle.add_ornament($CenterContainer/VBoxContainer/Seal, "emblem")
	for stat_label in [time_label, kill_label]:
		stat_label.add_theme_stylebox_override("normal", PixelUIStyle.badge_style(PixelUIStyle.STONE, PixelUIStyle.PANEL_INSET))
	PixelUIStyle.apply_button(retry_button, PixelUIStyle.BORDER_HOVER)
	PixelUIStyle.apply_button(title_button, PixelUIStyle.STONE)
	EventBus.run_ended.connect(_on_run_ended)
	EventBus.run_cleared.connect(_on_run_cleared)
	retry_button.pressed.connect(_on_retry_pressed)
	title_button.pressed.connect(_on_title_pressed)


func _on_run_ended(survived_seconds: float, kill_count: int) -> void:
	SaveManager.update_best_survival(survived_seconds)
	# 負けても到達時間ぶんの欠片は残る（10秒=1）。
	var reward := _run_reward(kill_count, survived_seconds)
	SaveManager.add_meta_currency(reward)
	get_tree().paused = true
	visible = true
	eyebrow_label.text = "探索記録"
	title_label.text = "探索失敗"
	title_label.add_theme_color_override("font_color", PixelUIStyle.DANGER.lightened(0.16))
	time_label.text = "探索時間　%s" % _format_time(survived_seconds)
	if GameManager.survival_mode_active:
		eyebrow_label.text = "5分サバイバル"
		title_label.text = "ステージ失敗"
	elif GameManager.map_mode_active:
		time_label.text += "　最高到達 地下%d層" % int(SaveManager.data.get("deepest_cleared_floor", 0))
	kill_label.text = "撃破数　%d体" % kill_count
	reward_label.text = "継承の欠片　+%d" % reward
	if GameManager.survival_mode_active:
		reward_label.text += "（撃破＋残金＋回収装備%d点＋到達時間）" % GameManager.run_equipment_count
		var carried := SaveManager.get_persistent_equipment()
		var carried_count: int = Dictionary(carried.get("equipped", {})).size() + Array(carried.get("inventory", [])).size()
		reward_label.text += "\n持ち帰った装備 %d点（ロック品は必ず残る）　深度 %d のまま" % [carried_count, SaveManager.get_survival_depth()]
	retry_button.grab_focus.call_deferred()


func _on_run_cleared(room_count: int, elapsed_seconds: float, kill_count: int) -> void:
	SaveManager.update_best_survival(elapsed_seconds)
	var reward := _run_reward(kill_count)
	SaveManager.add_meta_currency(reward)
	get_tree().paused = true
	visible = true
	eyebrow_label.text = "封印解放"
	title_label.text = "古王国踏破"
	title_label.add_theme_color_override("font_color", PixelUIStyle.BORDER_HOVER.lightened(0.18))
	var route_name := "全%d層踏破" % room_count if GameManager.map_mode_active else "全%d区画踏破" % room_count
	if GameManager.survival_mode_active:
		eyebrow_label.text = "5分サバイバル"
		title_label.text = "ステージクリア"
		route_name = "ボス討伐"
	time_label.text = "%s　%s" % [route_name, _format_time(elapsed_seconds)]
	kill_label.text = "撃破数　%d体" % kill_count
	reward_label.text = "継承の欠片　+%d" % reward
	if GameManager.survival_mode_active:
		reward_label.text += "（撃破＋残金＋回収装備%d点）" % GameManager.run_equipment_count
		var depth := SaveManager.get_survival_depth()
		reward_label.text += "\n装備をすべて持ち越し　深度 %d → %d　次の出撃先 MAP%d" % [maxi(depth - 1, 1), depth, GameManager.selected_survival_map]
	retry_button.grab_focus.call_deferred()


func _run_reward(kills: int, survived_seconds: float = 0.0) -> int:
	if not GameManager.survival_mode_active:
		return kills
	return kills + GameManager.run_gold + GameManager.run_equipment_count * 5 + int(survived_seconds / 10.0)

func _format_time(seconds: float) -> String:
	var total := maxi(int(seconds), 0)
	return "%02d:%02d" % [floori(total / 60.0), total % 60]


func _on_retry_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_title_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/title.tscn")
