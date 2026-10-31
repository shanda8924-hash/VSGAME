extends CanvasLayer
class_name PauseMenu
## Escで探索記録、Tで見開き本の天賦図を開閉する。
## 天賦図はtalent_grimoire.gdへ委譲し、停止状態はこのメニューで一元管理する。
##
## LevelUpSelect/ItemSelect等の選択待ちモーダルと同じGameManager.active_modal_count
## 経由の一時停止に乗る。ただし他モーダルが既に開いている間はEscを押しても
## 割り込んで開かない(選択を強制的に横取りしないため)。
##
## 天賦図(TalentTree)は職業スキルの流派分岐(school、game_specification.md
## 19.9参照)の進行状況を視覚化するパネル。現状はSwordsman(乱撃派/一閃派)
## のみ対応する試験実装で、それ以外の職業を選んでいる場合は「準備中」の
## 案内を表示する(他の職業への展開は後日)。

const NAME_FONT_SIZE := 24
const STATS_FONT_SIZE := 18
const DESC_FONT_SIZE := 20
const STATS_COLOR := Color(0.83, 0.85, 0.9, 1.0)

const TalentBook := preload("res://ui/pause_menu/talent_grimoire.gd")
var talent_book: Control

@onready var weapon_panel: Control = $CenterContainer/Panel/MarginContainer/VBoxContainer/WeaponPanel
@onready var weapon_list: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBoxContainer/WeaponPanel/ScrollContainer/WeaponList
@onready var empty_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/WeaponPanel/EmptyLabel
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
	talent_book = TalentBook.new()
	add_child(talent_book)
	talent_book.hide()
	talent_book.close_requested.connect(_close)
	talent_book.records_requested.connect(_show_tab.bind("weapon"))
	talent_tab_button.text = "天賦図 [T]"
	PixelUIStyle.add_ornament($Background, "backdrop", PixelUIStyle.JEWEL)
	PixelUIStyle.apply_major_panel($CenterContainer/Panel, PixelUIStyle.BORDER_HOVER)
	PixelUIStyle.add_ornament($CenterContainer/Panel/MarginContainer/VBoxContainer/Seal, "emblem")
	var close_button := Button.new()
	close_button.text = "探索へ戻る"
	close_button.custom_minimum_size = Vector2(200, 64)
	$CenterContainer/Panel/MarginContainer/VBoxContainer.add_child(close_button)
	PixelUIStyle.apply_button(close_button)
	close_button.pressed.connect(_close)
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
	if Input.is_action_just_pressed("talent_menu"):
		if _is_open:
			if _active_tab == "talent":
				_close()
			else:
				_show_tab("talent")
		elif GameManager.active_modal_count == 0 and GameManager.run_state == GameManager.RunState.PLAYING:
			_active_tab = "talent"
			_open()
		return
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
	if _active_tab == "talent":
		talent_book.focus_selected()
	else:
		focus_button.grab_focus.call_deferred()

func _close() -> void:
	if not _is_open:
		return
	_is_open = false
	talent_book.cancel_opening()
	visible = false
	var focused := get_viewport().gui_get_focus_owner()
	if focused and is_ancestor_of(focused):
		focused.release_focus()
	GameManager.close_modal()

func _show_tab(tab: String) -> void:
	talent_book.cancel_opening()
	_active_tab = tab
	PixelUIStyle.apply_tab(weapon_tab_button, tab == "weapon")
	PixelUIStyle.apply_tab(talent_tab_button, tab == "talent")
	PixelUIStyle.apply_tab(audio_tab_button, tab == "audio")
	weapon_panel.visible = tab == "weapon"
	$CenterContainer.visible = tab != "talent"
	$Background.visible = tab != "talent"
	talent_book.visible = tab == "talent"
	audio_panel.visible = tab == "audio"
	if tab == "weapon":
		_refresh_weapon_list()
		weapon_tab_button.grab_focus.call_deferred()
	elif tab == "talent":
		_refresh_talent_tree()
		talent_book.play_opening()

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
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = data.display_name
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	row.add_child(name_label)

	var stats_label := Label.new()
	stats_label.text = "攻撃力: %s   攻撃間隔: %s秒   属性: %s" % [
		data.base_damage, data.attack_interval, _resolve_element_display_name(data.vfx_theme_id)
	]
	stats_label.add_theme_font_size_override("font_size", STATS_FONT_SIZE)
	stats_label.add_theme_color_override("font_color", STATS_COLOR)
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(stats_label)

	if data.description != "":
		var desc_label := Label.new()
		desc_label.text = data.description
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size = Vector2(420, 0)
		desc_label.add_theme_font_size_override("font_size", DESC_FONT_SIZE)
		desc_label.add_theme_color_override("font_color", STATS_COLOR)
		row.add_child(desc_label)

	row.add_child(HSeparator.new())
	return row

func _resolve_element_display_name(vfx_theme_id: String) -> String:
	var theme: EffectThemeData = DataLoader.effect_themes.get(vfx_theme_id)
	return theme.display_name if theme else vfx_theme_id

func _refresh_talent_tree() -> void:
	talent_book.refresh(_weapon_manager)
