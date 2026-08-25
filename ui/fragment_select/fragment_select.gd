extends CanvasLayer
class_name FragmentSelect
## Boss撃破後のElement Build 4択。属性取得・Mastery・Fusion Masteryを同じ画面で扱う。

signal fragment_chosen(fragment_id: String)
signal reward_chosen(choice: Dictionary)

const SLOT_COUNT := 4
const FALLBACK_COLOR := Color(0.75, 0.75, 0.8, 1.0)

@onready var title_label: Label = $CenterContainer/VBoxContainer/StepTitle
@onready var build_label: Label = $CenterContainer/VBoxContainer/BuildSummary
@onready var grid_container: GridContainer = $CenterContainer/VBoxContainer/GridContainer

func _ready() -> void:
	visible = false
	PixelUIStyle.apply_tree(self)

func show_choices(title: String = "ボス撃破報酬：属性ビルドを選択", choice_count: int = SLOT_COUNT) -> void:
	GameManager.request_modal(func(): _open(title, choice_count))

func _open(title: String, choice_count: int = SLOT_COUNT) -> void:
	var choices := ElementRewardSystem.build_choices()
	if choices.is_empty():
		return
	# 通常ROOMは3択表示。Fusionの4系統を固定順の先頭3件だけsliceすると、
	# power/echo/hasteがMAXになった時に未取得signatureが4件目へ隠れ、全カード
	# disabledで進行不能になる。取得可能カードを先頭へ寄せてから表示数を絞る。
	var available: Array[Dictionary] = []
	var capped: Array[Dictionary] = []
	for choice in choices:
		if bool(choice.get("maxed", false)):
			capped.append(choice)
		else:
			available.append(choice)
	choices = available + capped
	GameManager.open_modal()
	visible = true
	title_label.text = title
	build_label.text = ElementRewardSystem.build_summary()
	for child in grid_container.get_children():
		child.queue_free()
	for choice in choices.slice(0, clampi(choice_count, 1, SLOT_COUNT)):
		grid_container.add_child(_build_button(choice))
	if grid_container.get_child_count() > 0:
		(grid_container.get_child(0) as Button).grab_focus.call_deferred()

func _build_button(choice: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(300, 128)
	button.text = "%s\n%s" % [choice.get("title", ""), choice.get("description", "")]
	button.tooltip_text = "%s\n段階 %d / %d" % [choice.get("description", ""), int(choice.get("rank", 1)), int(choice.get("max_rank", 3))]
	button.add_theme_font_size_override("font_size", 19)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var accent := Color.from_string(String(choice.get("color", "#c0c0cc")), FALLBACK_COLOR)
	PixelUIStyle.apply_button(button, accent)
	button.disabled = bool(choice.get("maxed", false))
	button.set_meta("reward_choice", choice.duplicate(true))
	button.pressed.connect(_on_reward_pressed.bind(choice))
	return button

func _on_reward_pressed(choice: Dictionary) -> void:
	if not ElementRewardSystem.apply_choice(choice):
		return
	AudioManager.play_sfx("ui_click")
	if choice.get("kind", "") == "element":
		fragment_chosen.emit(String(choice.get("element_id", "")).trim_prefix("element_"))
	reward_chosen.emit(choice.duplicate(true))
	visible = false
	GameManager.close_modal()
