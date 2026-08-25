extends CanvasLayer
class_name LevelUpSelect
## 通常レベルアップは通常強化3択だけを提示する。欠片は特別報酬UIが担当する。

signal option_selected(choice_id: String)

const SLOT_COUNT := 3
const BORDER_COLOR := Color(0.35, 0.55, 1.0, 1.0)
const MELEE_PATTERN_IDS := ["melee_arc", "wide_cleave", "self_pulse", "piercing_thrust"]

@onready var step_title: Label = $CenterContainer/VBoxContainer/StepTitle
@onready var grid_container: GridContainer = $CenterContainer/VBoxContainer/GridContainer

func _ready() -> void:
	visible = false
	PixelUIStyle.apply_tree(self)
	EventBus.player_leveled_up.connect(_on_leveled_up)

func _on_leveled_up(_new_level: int) -> void:
	GameManager.request_modal(_open)

func _open() -> void:
	GameManager.open_modal()
	visible = true
	step_title.text = "レベルアップ! 強化を1つ選んでください"
	for child in grid_container.get_children():
		child.queue_free()
	var upgrades := _get_compatible_upgrades()

	# 流派選択(class_school_select、2026年8月試験実装)は、他の候補と同じ
	# 抽選プールに「混ぜる」が、選択が埋もれて出現しない回のないよう出現を
	# 保証する(school分岐の起点は一度きりの重要な選択のため)。
	var forced: Array[UpgradeData] = []
	var rest: Array[UpgradeData] = []
	for upgrade in upgrades:
		if upgrade.effect_type == "class_school_select":
			forced.append(upgrade)
		else:
			rest.append(upgrade)
	rest.shuffle()
	var chosen: Array[UpgradeData] = []
	chosen.append_array(forced)
	for upgrade in rest:
		if chosen.size() >= SLOT_COUNT:
			break
		chosen.append(upgrade)

	for i in mini(SLOT_COUNT, chosen.size()):
		grid_container.add_child(_build_choice_button(chosen[i]))
	if grid_container.get_child_count() > 0:
		(grid_container.get_child(0) as Button).grab_focus.call_deferred()

## 通常の汎用強化オプション(common/melee/ranged)に加え、現在の職業専用強化
## (class_character_id/class_ability_level、2026年8月追加)を同じ候補プールへ
## 混ぜる。新しい選択UIは作らず、既存の3択抽選にそのまま乗せる方針
## (モーダルの二重表示問題を再発させないため、game_specification.md 19.9参照)。
## 職業専用強化は、現在のキャラクターのidと一致し、かつ「現在のability_level+1」
## に対応するものだけを候補にすることで、Lv2→Lv3→Lv4→Lv5の順序を保証する。
## 流派分岐(class_school、2026年8月試験実装、Swordsmanのみ)を持つ強化は、
## さらに「school未確定ならclass_school_selectのみ・確定後は選んだ流派と
## 一致するものだけ」でも絞り込む(選ばなかった流派は二度と出現しない)。
func _get_compatible_upgrades() -> Array[UpgradeData]:
	var result: Array[UpgradeData] = []
	var character: CharacterData = DataLoader.characters.get(GameManager.selected_character_id)
	var combat_category := "melee" if character and character.attack_pattern_id in MELEE_PATTERN_IDS else "ranged"
	var character_id := character.id if character else ""
	var current_ability_level := _get_current_ability_level()
	var current_school := _get_current_school()
	for upgrade in DataLoader.get_all_upgrades():
		if upgrade.class_character_id != "":
			if upgrade.class_character_id != character_id:
				continue
			if upgrade.class_ability_level != current_ability_level + 1:
				continue
			if upgrade.effect_type == "class_school_select":
				if current_school != "none":
					continue
			elif upgrade.class_school != "" and upgrade.class_school != current_school:
				continue
			result.append(upgrade)
			continue
		if upgrade.category == "common" or upgrade.category == combat_category:
			result.append(upgrade)
	return result

func _get_current_ability_level() -> int:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return 0
	var weapon_manager: WeaponManagerComponent = player.get_node_or_null("WeaponManagerComponent")
	return weapon_manager.get_class_ability_level() if weapon_manager else 0

func _get_current_school() -> String:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return "none"
	var weapon_manager: WeaponManagerComponent = player.get_node_or_null("WeaponManagerComponent")
	return weapon_manager.get_class_school() if weapon_manager else "none"

func _build_choice_button(upgrade: UpgradeData) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(220, 96)
	button.text = "%s\n%s" % [upgrade.display_name, upgrade.description]
	button.autowrap_mode = TextServer.AUTOWRAP_WORD
	PixelUIStyle.apply_button(button, BORDER_COLOR)
	button.pressed.connect(_on_choice_pressed.bind(upgrade))
	return button

func _on_choice_pressed(upgrade: UpgradeData) -> void:
	AudioManager.play_sfx("ui_click")
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var component: PlayerUpgradesComponent = player.get_node_or_null("PlayerUpgradesComponent")
		if component:
			component.apply_upgrade(upgrade)
	option_selected.emit(upgrade.id)
	visible = false
	GameManager.close_modal()
