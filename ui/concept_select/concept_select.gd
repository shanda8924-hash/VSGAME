extends CanvasLayer
class_name ConceptSelect

signal concept_chosen(concept_id: String)
signal completed_skill_chosen(skill_id: String, level: int)

@export var concept_system_path: NodePath

@onready var concept_system: ConceptSystem = get_node(concept_system_path)
@onready var title_label: Label = $Background/Center/Panel/Margin/VBox/Title
@onready var choices: HBoxContainer = $Background/Center/Panel/Margin/VBox/Choices

const COMPLETED_SKILL_ICON_SIZE := Vector2(72, 72)


func _ready() -> void:
	visible = false
	PixelUIStyle.apply_tree(self)
	PixelUIStyle.add_ornament($Background, "backdrop", PixelUIStyle.JEWEL)
	PixelUIStyle.apply_major_panel($Background/Center/Panel, PixelUIStyle.BORDER_HOVER)
	PixelUIStyle.add_ornament($Background/Center/Panel/Margin/VBox/Seal, "emblem")


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
	var type_label: String = {"trigger":"起点", "skill":"スキル", "modifier":"補助"}.get(concept.concept_type, concept.concept_type)
	var colors := {"trigger": Color("#ffcf66"), "skill": Color("#77cfff"), "modifier": Color("#c393ff")}
	var accent: Color = colors.get(concept.concept_type, Color.WHITE)
	var button := PixelUIStyle.choice_card(type_label, concept.display_name, concept.description, null, "刻印する", accent)
	button.custom_minimum_size = Vector2(320, 240)
	button.set_meta("concept_id", concept.id)
	button.pressed.connect(_choose.bind(concept))
	return button


func _build_completed_skill_button(candidate: Dictionary) -> Button:
	var skill_id := String(candidate.get("id", ""))
	var current_level := concept_system.get_completed_skill_level(skill_id)
	var next_level := current_level + 1
	var maximum := int(candidate.get("max_level", 3))
	var level_text := "新規取得  Lv.1" if current_level <= 0 else "Lv.%d → Lv.%d" % [current_level, mini(next_level, maximum)]
	var accent := Color.from_string(String(candidate.get("color", "#d9dde8")), Color.WHITE)
	var icon := _load_completed_skill_icon(String(candidate.get("icon_path", "")))
	var button := PixelUIStyle.choice_card(
		"完成大技",
		concept_system.get_completed_skill_display_name(skill_id),
		concept_system.get_completed_skill_description(skill_id, next_level),
		icon,
		level_text,
		accent
	)
	button.custom_minimum_size = Vector2(330, 292)
	button.tooltip_text += "\n所持大技 %d / %d" % [concept_system.get_completed_skill_count(), ConceptSystem.MAX_COMPLETED_SKILLS]
	button.set_meta("completed_skill_id", skill_id)
	button.pressed.connect(_choose_completed_skill.bind(skill_id))
	return button


func _load_completed_skill_icon(path: String) -> Texture2D:
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _add_completed_skill_icon(parent: VBoxContainer, path: String, fallback: String) -> void:
	if path != "" and ResourceLoader.exists(path):
		var icon := TextureRect.new()
		icon.custom_minimum_size = COMPLETED_SKILL_ICON_SIZE
		icon.texture = load(path) as Texture2D
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(icon)
		return
	_add_centered_label(parent, fallback, 38, Color.WHITE)


func _add_centered_label(parent: VBoxContainer, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


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
