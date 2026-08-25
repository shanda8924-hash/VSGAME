extends CanvasLayer
class_name ConceptSelect

signal concept_chosen(concept_id: String)
signal completed_skill_chosen(skill_id: String, level: int)

@export var concept_system_path: NodePath

@onready var concept_system: ConceptSystem = get_node(concept_system_path)
@onready var title_label: Label = $Background/Center/Panel/Margin/VBox/Title
@onready var choices: HBoxContainer = $Background/Center/Panel/Margin/VBox/Choices


func _ready() -> void:
	visible = false
	PixelUIStyle.apply_tree(self)


func show_choices(candidates: Array[ConceptData], title: String = "コンセプトを1つ取得") -> void:
	if candidates.is_empty():
		return
	GameManager.request_modal(func(): _open(candidates, title))


func show_completed_skill_choices(candidates: Array[Dictionary], title: String = "宝箱スキルを1つ選択") -> void:
	if candidates.is_empty():
		return
	GameManager.request_modal(func(): _open_completed_skills(candidates, title))


func _open(candidates: Array[ConceptData], title: String) -> void:
	GameManager.open_modal()
	visible = true
	title_label.text = title
	for child in choices.get_children():
		child.queue_free()
	for concept in candidates:
		choices.add_child(_build_button(concept))
	if choices.get_child_count() > 0:
		(choices.get_child(0) as Button).grab_focus.call_deferred()


func _open_completed_skills(candidates: Array[Dictionary], title: String) -> void:
	GameManager.open_modal()
	visible = true
	title_label.text = title
	for child in choices.get_children():
		child.queue_free()
	for candidate in candidates:
		choices.add_child(_build_completed_skill_button(candidate))
	if choices.get_child_count() > 0:
		(choices.get_child(0) as Button).grab_focus.call_deferred()


func _build_button(concept: ConceptData) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(300, 170)
	var type_label: String = {"trigger":"起点", "skill":"スキル", "modifier":"補助"}.get(concept.concept_type, concept.concept_type)
	button.text = "%s\n%s\n\n%s" % [type_label, concept.display_name, concept.description]
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 18)
	button.set_meta("concept_id", concept.id)
	var colors := {"trigger": Color("#ffcf66"), "skill": Color("#77cfff"), "modifier": Color("#c393ff")}
	PixelUIStyle.apply_button(button, colors.get(concept.concept_type, Color.WHITE))
	button.pressed.connect(_choose.bind(concept))
	return button


func _build_completed_skill_button(candidate: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(300, 190)
	var skill_id := String(candidate.get("id", ""))
	var current_level := concept_system.get_completed_skill_level(skill_id)
	var next_level := current_level + 1
	var maximum := int(candidate.get("max_level", 3))
	var level_text := "新規取得  Lv.1" if current_level <= 0 else "Lv.%d → Lv.%d" % [current_level, mini(next_level, maximum)]
	button.text = "%s  【%s】\n%s\n\n%s" % [candidate.get("icon", "◆"), concept_system.get_completed_skill_display_name(skill_id), level_text, concept_system.get_completed_skill_description(skill_id, next_level)]
	button.tooltip_text = "所持スキル %d / %d" % [concept_system.get_completed_skill_count(), ConceptSystem.MAX_COMPLETED_SKILLS]
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 18)
	button.set_meta("completed_skill_id", skill_id)
	var accent := Color.from_string(String(candidate.get("color", "#d9dde8")), Color.WHITE)
	PixelUIStyle.apply_button(button, accent)
	button.pressed.connect(_choose_completed_skill.bind(skill_id))
	return button


func _choose(concept: ConceptData) -> void:
	concept_system.acquire_concept(concept.id)
	AudioManager.play_sfx("ui_click")
	visible = false
	GameManager.close_modal()
	concept_chosen.emit(concept.id)


func _choose_completed_skill(skill_id: String) -> void:
	var level := concept_system.acquire_completed_skill(skill_id)
	if level <= 0:
		return
	AudioManager.play_sfx("ui_click")
	visible = false
	GameManager.close_modal()
	completed_skill_chosen.emit(skill_id, level)
