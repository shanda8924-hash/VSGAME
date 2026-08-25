extends CanvasLayer
class_name PauseMenu
## Escキーで開閉する簡易ポーズメニュー。「所持武器」タブと「天賦図」タブを
## 切り替えて表示する(2026年8月、天賦図タブを追加)。
##
## LevelUpSelect/ItemSelect等の選択待ちモーダルと同じGameManager.active_modal_count
## 経由の一時停止に乗る。ただし他モーダルが既に開いている間はEscを押しても
## 割り込んで開かない(選択を強制的に横取りしないため)。
##
## 天賦図(TalentTree)は職業スキルの流派分岐(school、game_specification.md
## 19.9参照)の進行状況を視覚化するパネル。現状はSwordsman(乱撃派/一閃派)
## のみ対応する試験実装で、それ以外の職業を選んでいる場合は「準備中」の
## 案内を表示する(他の職業への展開は後日)。

const NAME_FONT_SIZE := 18
const STATS_FONT_SIZE := 13
const DESC_FONT_SIZE := 13
const STATS_COLOR := Color(0.75, 0.75, 0.8, 1.0)

# --- 天賦図(TalentTree) ---
const TALENT_NODE_SIZE := Vector2(210, 78)
const TALENT_LEVEL_FONT_SIZE := 15
const TALENT_DESC_FONT_SIZE := 12
## 習得済み(現在選択中の流派で、到達済みの段階): はっきり見える金色系。
const TALENT_ACQUIRED_BORDER := Color(0.95, 0.85, 0.3, 1.0)
const TALENT_ACQUIRED_BG := Color(0.32, 0.27, 0.08, 0.95)
const TALENT_ACQUIRED_TEXT := Color(0.98, 0.92, 0.6, 1.0)
## 未到達(まだ選べる/これから来る段階): 薄暗いがロックアイコンで示す。
const TALENT_LOCKED_BORDER := Color(0.4, 0.4, 0.46, 1.0)
const TALENT_LOCKED_BG := Color(0.14, 0.14, 0.18, 0.9)
const TALENT_LOCKED_TEXT := Color(0.65, 0.65, 0.7, 1.0)
## 選択不可(流派確定後、選ばなかった側): 未到達よりさらに沈んだグレーアウト。
const TALENT_UNSELECTABLE_BORDER := Color(0.22, 0.22, 0.24, 1.0)
const TALENT_UNSELECTABLE_BG := Color(0.09, 0.09, 0.10, 0.9)
const TALENT_UNSELECTABLE_TEXT := Color(0.38, 0.38, 0.4, 1.0)
const TALENT_ROOT_BORDER := Color(0.85, 0.85, 0.92, 1.0)
const TALENT_ROOT_BG := Color(0.22, 0.22, 0.26, 0.95)
const TALENT_ROOT_TEXT := Color(0.95, 0.95, 1.0, 1.0)
## 「5つの丸印」段階表示(ui/common/ability_stage_dots.gd)のドットサイズ。
const TALENT_STAGE_DOT_SIZE := 16.0

const RENGEKI_LEVELS := [
	{"level": 2, "desc": "連続斬り数2"},
	{"level": 3, "desc": "連続斬り数3"},
	{"level": 4, "desc": "攻撃間隔-20%"},
	{"level": 5, "desc": "連続斬り数4+最後の一撃は確定クリティカル"},
]
const ISSEN_LEVELS := [
	{"level": 2, "desc": "単発ダメージ+40%"},
	{"level": 3, "desc": "間合い+30%"},
	{"level": 4, "desc": "クリティカル率+25%"},
	{"level": 5, "desc": "HP30%以下の敵に約5倍の大ダメージ"},
]

@onready var weapon_panel: Control = $CenterContainer/Panel/MarginContainer/VBoxContainer/WeaponPanel
@onready var weapon_list: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBoxContainer/WeaponPanel/ScrollContainer/WeaponList
@onready var empty_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/WeaponPanel/EmptyLabel
@onready var talent_panel: Control = $CenterContainer/Panel/MarginContainer/VBoxContainer/TalentPanel
@onready var weapon_tab_button: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/TabBar/WeaponTabButton
@onready var talent_tab_button: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/TabBar/TalentTabButton
@onready var audio_tab_button: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/TabBar/AudioTabButton
@onready var audio_panel: Control = $CenterContainer/Panel/MarginContainer/VBoxContainer/AudioPanel
@onready var music_volume: HSlider = $CenterContainer/Panel/MarginContainer/VBoxContainer/AudioPanel/MusicVolume
@onready var sfx_volume: HSlider = $CenterContainer/Panel/MarginContainer/VBoxContainer/AudioPanel/SFXVolume

## 天賦図はキャラクターの経験値(ExperienceComponent)を一切参照しない
## (2026年8月、スキル熟練度表示をEXPゲージから完全に分離したため)。
var _weapon_manager: WeaponManagerComponent = null
var _is_open: bool = false
var _active_tab: String = "weapon"

func _ready() -> void:
	visible = false
	PixelUIStyle.apply_tree(self)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		_weapon_manager = player.get_node_or_null("WeaponManagerComponent")
	weapon_tab_button.pressed.connect(_show_tab.bind("weapon"))
	talent_tab_button.pressed.connect(_show_tab.bind("talent"))
	audio_tab_button.pressed.connect(_show_tab.bind("audio"))
	music_volume.value = SaveManager.get_audio_volume("Music")
	sfx_volume.value = SaveManager.get_audio_volume("SFX")
	music_volume.value_changed.connect(func(value): SaveManager.set_audio_volume("Music", value))
	sfx_volume.value_changed.connect(func(value): SaveManager.set_audio_volume("SFX", value))

func _process(_delta: float) -> void:
	if not Input.is_action_just_pressed("ui_cancel"):
		return
	if _is_open:
		_close()
	elif GameManager.active_modal_count == 0 and GameManager.run_state == GameManager.RunState.PLAYING:
		_open()

func _open() -> void:
	_is_open = true
	GameManager.open_modal()
	_show_tab(_active_tab)
	visible = true
	var focus_button := weapon_tab_button if _active_tab == "weapon" else (talent_tab_button if _active_tab == "talent" else audio_tab_button)
	focus_button.grab_focus.call_deferred()

func _close() -> void:
	_is_open = false
	visible = false
	var focused := get_viewport().gui_get_focus_owner()
	if focused and is_ancestor_of(focused):
		focused.release_focus()
	GameManager.close_modal()

func _show_tab(tab: String) -> void:
	_active_tab = tab
	weapon_panel.visible = tab == "weapon"
	talent_panel.visible = tab == "talent"
	audio_panel.visible = tab == "audio"
	if tab == "weapon":
		_refresh_weapon_list()
	elif tab == "talent":
		_refresh_talent_tree()

func _refresh_weapon_list() -> void:
	for child in weapon_list.get_children():
		child.queue_free()
	if _weapon_manager == null:
		empty_label.visible = true
		return
	var instances := _weapon_manager.get_weapon_instances()
	empty_label.visible = instances.is_empty()
	for instance in instances:
		weapon_list.add_child(_build_weapon_row(instance.data))

func _build_weapon_row(data: WeaponData) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var name_label := Label.new()
	name_label.text = data.display_name
	name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	row.add_child(name_label)

	var stats_label := Label.new()
	stats_label.text = "攻撃力: %s   攻撃間隔: %s秒   属性: %s" % [
		data.base_damage, data.attack_interval, _resolve_element_display_name(data.vfx_theme_id)
	]
	stats_label.add_theme_font_size_override("font_size", STATS_FONT_SIZE)
	stats_label.add_theme_color_override("font_color", STATS_COLOR)
	row.add_child(stats_label)

	if data.description != "":
		var desc_label := Label.new()
		desc_label.text = data.description
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_label.custom_minimum_size = Vector2(420, 0)
		desc_label.add_theme_font_size_override("font_size", DESC_FONT_SIZE)
		desc_label.add_theme_color_override("font_color", STATS_COLOR)
		row.add_child(desc_label)

	row.add_child(HSeparator.new())
	return row

func _resolve_element_display_name(vfx_theme_id: String) -> String:
	var theme: EffectThemeData = DataLoader.effect_themes.get(vfx_theme_id)
	return theme.display_name if theme else vfx_theme_id

# --- 天賦図(TalentTree) ---

## 起点ノード「居合」を上部中央に、その下に乱撃派(左)/一閃派(右)の
## Lv.2〜Lv.5ノードを2列で並べる。ノードの色/ロック表示は
## WeaponManagerComponent.get_class_school()/get_class_ability_level()の
## 現在値からその場で組み立てる(タブを開くたびに最新状態を反映する)。
func _refresh_talent_tree() -> void:
	for child in talent_panel.get_children():
		child.queue_free()

	var character_id := ""
	var school := "none"
	var ability_level := 1
	if _weapon_manager:
		character_id = _weapon_manager.get_class_character_id()
		school = _weapon_manager.get_class_school()
		ability_level = _weapon_manager.get_class_ability_level()

	if character_id != "swordsman":
		var placeholder := Label.new()
		placeholder.text = "この職業の天賦図は現在準備中です\n(2026年8月時点はSwordsmanの流派分岐のみ試験対応)"
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD
		placeholder.custom_minimum_size = Vector2(440, 0)
		talent_panel.add_child(placeholder)
		return

	var root_wrap := CenterContainer.new()
	root_wrap.add_child(_build_talent_node("居合", "常時発動中の通常攻撃(起点)", TALENT_ROOT_BORDER, TALENT_ROOT_BG, TALENT_ROOT_TEXT, false))
	talent_panel.add_child(root_wrap)

	var arrow_row := HBoxContainer.new()
	arrow_row.alignment = BoxContainer.ALIGNMENT_CENTER
	arrow_row.add_theme_constant_override("separation", 150)
	arrow_row.add_child(_build_arrow_label(TALENT_ROOT_TEXT))
	arrow_row.add_child(_build_arrow_label(TALENT_ROOT_TEXT))
	talent_panel.add_child(arrow_row)

	var columns := HBoxContainer.new()
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_theme_constant_override("separation", 24)
	columns.add_child(_build_school_column("乱撃派", "rengeki", RENGEKI_LEVELS, school, ability_level))
	columns.add_child(_build_school_column("一閃派", "issen", ISSEN_LEVELS, school, ability_level))
	talent_panel.add_child(columns)

	var status_label := Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", STATS_COLOR)
	if school == "none":
		status_label.text = "次のレベルアップで流派を選択します"
	else:
		var school_name := "乱撃派" if school == "rengeki" else "一閃派"
		status_label.text = "現在: %s Lv.%d" % [school_name, ability_level]
	talent_panel.add_child(status_label)

	_add_stage_dots(ability_level)

## 職業スキルの熟練度(ability_level)を、HUDのスキルアイコン付近と同じ
## 「5つの丸印」段階表示(ui/common/ability_stage_dots.gd)で示す。
## 【重要】これはキャラクターの経験値ゲージ(ExperienceComponent)とは
## 完全に別の概念・別のデータ(WeaponManagerComponent.get_class_ability_level())
## であり、見た目も経験値バーとは別の場所(このパネル内)に配置する
## (色もEXPバーの水色とは別の金色系にして紛れないようにしている)。
func _add_stage_dots(ability_level: int) -> void:
	var wrap := CenterContainer.new()
	wrap.add_child(AbilityStageDots.build(ability_level, TALENT_STAGE_DOT_SIZE, TALENT_ACQUIRED_BORDER, TALENT_LOCKED_BG, TALENT_LOCKED_BORDER))
	talent_panel.add_child(wrap)

func _build_arrow_label(color: Color) -> Label:
	var arrow := Label.new()
	arrow.text = "↓"
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.add_theme_font_size_override("font_size", 22)
	arrow.add_theme_color_override("font_color", color)
	return arrow

## 1列(乱撃派 or 一閃派)ぶんのヘッダー+Lv.2〜Lv.5ノードを組み立てる。
## 各ノードの状態は3通り: 習得済み(選んだ流派・到達済み段階)/
## 未到達(まだ選べる、選んだ流派でこれから来る段階、または流派未確定)/
## 選択不可(流派確定後、選ばなかった側は永続的にグレーアウト)。
func _build_school_column(title: String, school_id: String, levels: Array, current_school: String, ability_level: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	var is_unselectable_school := current_school != "none" and current_school != school_id
	var is_chosen_school := current_school == school_id

	var header := Label.new()
	header.text = title
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 17)
	if is_unselectable_school:
		header.add_theme_color_override("font_color", TALENT_UNSELECTABLE_TEXT)
	elif is_chosen_school:
		header.add_theme_color_override("font_color", TALENT_ACQUIRED_TEXT)
	column.add_child(header)

	for i in levels.size():
		var entry: Dictionary = levels[i]
		var level: int = entry["level"]
		var desc: String = entry["desc"]
		var is_acquired := is_chosen_school and ability_level >= level
		var label_text := "Lv.%d" % level
		var border: Color
		var bg: Color
		var text_color: Color
		var show_lock := false
		if is_unselectable_school:
			border = TALENT_UNSELECTABLE_BORDER
			bg = TALENT_UNSELECTABLE_BG
			text_color = TALENT_UNSELECTABLE_TEXT
		elif is_acquired:
			border = TALENT_ACQUIRED_BORDER
			bg = TALENT_ACQUIRED_BG
			text_color = TALENT_ACQUIRED_TEXT
		else:
			border = TALENT_LOCKED_BORDER
			bg = TALENT_LOCKED_BG
			text_color = TALENT_LOCKED_TEXT
			show_lock = true
		column.add_child(_build_talent_node(label_text, desc, border, bg, text_color, show_lock))
		if i < levels.size() - 1:
			column.add_child(_build_arrow_label(TALENT_UNSELECTABLE_TEXT if is_unselectable_school else TALENT_LOCKED_TEXT))
	return column

func _build_talent_node(title: String, desc: String, border_color: Color, bg_color: Color, text_color: Color, show_lock: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = TALENT_NODE_SIZE
	PixelUIStyle.apply_panel(panel, border_color)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", TALENT_LEVEL_FONT_SIZE)
	title_label.add_theme_color_override("font_color", text_color)
	title_row.add_child(title_label)
	if show_lock:
		var lock_label := Label.new()
		lock_label.text = " 🔒"
		lock_label.add_theme_font_size_override("font_size", TALENT_LEVEL_FONT_SIZE)
		title_row.add_child(lock_label)
	vbox.add_child(title_row)

	var desc_label := Label.new()
	desc_label.text = desc
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.add_theme_font_size_override("font_size", TALENT_DESC_FONT_SIZE)
	desc_label.add_theme_color_override("font_color", text_color)
	vbox.add_child(desc_label)

	return panel
