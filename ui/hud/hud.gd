extends CanvasLayer
class_name HUD
## プレイ中のHUD。HPバーと所持欠片・獲得アイテム(ミニマル表示)を表示する。
## 【UI方針】親指だけで届く位置に配置する必要はない(HUDは表示専用で操作しないため)。

## 戦利品トレイに個別表示する種類数の上限(仕様書8章)。これを超えた分は
## 個別の行を増やさず、末尾の「+N」バッジへまとめる。
const ITEM_TRAY_DISTINCT_LIMIT := 6

## 職業スキルの熟練度(ability_level)を示す「5つの丸印」段階表示
## (ui/common/ability_stage_dots.gd)の見た目パラメータ。EXPバー(水色、
## MarginContainer側)とは配色・配置ともに完全に切り離す(こちらは
## SkillPanel側、金色系)。
const STAGE_DOT_SIZE := 12.0
const STAGE_DOT_FILLED := Color(0.95, 0.8, 0.3, 1.0)
const STAGE_DOT_EMPTY := Color(0.2, 0.2, 0.24, 1.0)
const STAGE_DOT_BORDER := Color(0.6, 0.6, 0.66, 1.0)

@onready var hp_bar: ProgressBar = $MarginContainer/VBoxContainer/HPBar
@onready var level_label: Label = $MarginContainer/VBoxContainer/LevelLabel
@onready var exp_bar: ProgressBar = $MarginContainer/VBoxContainer/ExpBar
@onready var active_element_label: RichTextLabel = $MarginContainer/VBoxContainer/ActiveElementLabel
@onready var weapon_row: HBoxContainer = $MarginContainer/VBoxContainer/WeaponRow
@onready var fragment_row: HBoxContainer = $MarginContainer/VBoxContainer/FragmentRow
@onready var item_row: HBoxContainer = $MarginContainer/VBoxContainer/ItemRow
@onready var completed_skill_row: HBoxContainer = $MarginContainer/VBoxContainer/CompletedSkillRow
@onready var boss_health_container: VBoxContainer = $BossHealthContainer
@onready var boss_name_label: Label = $BossHealthContainer/BossNameLabel
@onready var boss_hp_bar: ProgressBar = $BossHealthContainer/BossHPBar
@onready var skill_panel: PanelContainer = $SkillPanel
@onready var skill_name_label: Label = $SkillPanel/MarginContainer/VBoxContainer/SkillName
@onready var skill_icon_panel: PanelContainer = $SkillPanel/MarginContainer/VBoxContainer/IconPanel
@onready var skill_icon_text: Label = $SkillPanel/MarginContainer/VBoxContainer/IconPanel/IconText
@onready var skill_cooldown_shade: ColorRect = $SkillPanel/MarginContainer/VBoxContainer/IconPanel/CooldownShade
@onready var skill_cooldown_label: Label = $SkillPanel/MarginContainer/VBoxContainer/IconPanel/CooldownLabel
@onready var stage_dots_wrap: CenterContainer = $SkillPanel/MarginContainer/VBoxContainer/StageDotsWrap
@onready var room_status_label: Label = $RoomStatusLabel
@onready var room_message_label: Label = $RoomMessageLabel
@onready var room_clear_label: Label = $RoomClearLabel
@onready var combo_panel: PanelContainer = $ComboPanel
@onready var combo_value_label: Label = $ComboPanel/Margin/VBox/Value

var _combo_tween: Tween = null
var _room_announcement_tween: Tween = null

## item_id -> {"label": Label, "display_name": String, "count": int}。
## 同じアイテムを複数回獲得した際に新しい行を増やさず「×N」で重ね数を示すために
## 種類ごとの行を記録しておく。
var _item_rows: Dictionary = {}
var _item_overflow_count: int = 0
var _item_overflow_label: Label = null
var _completed_skill_labels: Dictionary = {}

## 所持武器トレイが参照するプレイヤーのWeaponManagerComponent(所持欠片・獲得
## アイテムとは別の行に、現在持っている完成武器を常時アイコン表示するため)。
var _weapon_manager: WeaponManagerComponent = null
var _active_skill: ActiveSkillComponent = null

func _ready() -> void:
	EventBus.fragment_collected.connect(_on_fragment_collected)
	EventBus.element_loadout_changed.connect(_on_element_loadout_changed)
	EventBus.element_fusion_formed.connect(func(_id, _name, _sources): _on_element_loadout_changed(GameManager.get_active_element_ids(), GameManager.element_stacks))
	EventBus.element_mastery_changed.connect(func(_scope, _id, _rank): _on_element_loadout_changed(GameManager.get_active_element_ids(), GameManager.element_stacks))
	EventBus.item_acquired.connect(_on_item_acquired)
	EventBus.equipment_picked_up.connect(_on_equipment_picked_up)
	boss_health_container.visible = false
	combo_panel.visible = false
	room_clear_label.visible = false
	var player := get_tree().get_first_node_in_group("player")
	if player:
		_weapon_manager = player.get_node_or_null("WeaponManagerComponent")
		_active_skill = player.get_node_or_null("ActiveSkillComponent")
		if _active_skill:
			_active_skill.skill_configured.connect(_on_skill_configured)
			_active_skill.cooldown_changed.connect(_on_skill_cooldown_changed)
			_active_skill.skill_became_ready.connect(_on_skill_became_ready)
			_active_skill.skill_activated.connect(_on_skill_activated)
			var data: CharacterData = DataLoader.characters.get(GameManager.selected_character_id)
			if data:
				var theme: EffectThemeData = DataLoader.effect_themes.get(data.vfx_theme_id)
				_on_skill_configured(data.active_skill_name, data.active_skill_icon, data.active_skill_cooldown, theme.enhanced_color if theme else Color.GOLD)
		if _weapon_manager:
			_weapon_manager.class_ability_level_changed.connect(_on_class_ability_level_changed)
			set_ability_stage(_weapon_manager.get_class_ability_level())
	_refresh_weapon_tray()
	_on_element_loadout_changed(GameManager.get_active_element_ids(), GameManager.element_stacks)
	PixelUIStyle.apply_tree(self)

func _on_active_element_changed(element_id: String) -> void:
	# 旧テスト／外部呼び出し互換。実表示はLoadout全体から構築する。
	_on_element_loadout_changed(GameManager.get_active_element_ids(), GameManager.element_stacks)

func _on_element_loadout_changed(active_ids: Array, stacks: Dictionary) -> void:
	if GameManager.active_fusion_id != "":
		active_element_label.text = "[color=#ffd96a][b]融合属性：%s[/b][/color]\n[color=#d8c7ff]固有熟練 %d[/color]" % [ElementRewardSystem.get_localized_fusion_name(), GameManager.get_fusion_mastery_rank("signature")]
		return
	if active_ids.is_empty():
		active_element_label.text = "[color=#c7ccd6]属性：なし  枠 0 / 2[/color]"
		return
	var parts: Array[String] = []
	for index in active_ids.size():
		var element_id := String(active_ids[index])
		var data: ElementVFXData = DataLoader.element_vfx_effects.get(element_id)
		if data == null:
			continue
		var primary_mark := "主 " if index == active_ids.size() - 1 else ""
		var localized_name := String(ElementRewardSystem.ELEMENT_LABELS.get(element_id, [data.display_name, ""])[0])
		parts.append("[color=#%s][b]%s%s Lv%d[/b][/color]" % [data.attack_tint.to_html(false), primary_mark, localized_name, int(stacks.get(element_id, 0))])
	active_element_label.text = "属性枠 %d / 2%s：%s" % [active_ids.size(), " 固定済み" if active_ids.size() >= 2 else "", "  |  ".join(parts)]

func _on_class_ability_level_changed(new_level: int) -> void:
	set_ability_stage(new_level)

## 職業スキルの熟練度(ability_level)を「5つの丸印」で表示する
## (キャラクターの経験値ゲージ(set_experience())とは完全に別の概念・別の
## データ・別の見た目。同じバーに重ねたり色を似せたりしない)。
func set_ability_stage(ability_level: int) -> void:
	for child in stage_dots_wrap.get_children():
		child.queue_free()
	stage_dots_wrap.add_child(AbilityStageDots.build(ability_level, STAGE_DOT_SIZE, STAGE_DOT_FILLED, STAGE_DOT_EMPTY, STAGE_DOT_BORDER))

func _on_skill_configured(display_name: String, icon_text: String, _cooldown: float, color: Color) -> void:
	skill_name_label.text = display_name
	skill_icon_text.text = icon_text
	PixelUIStyle.apply_panel(skill_icon_panel, color)
	_on_skill_cooldown_changed(0.0, _cooldown)

func _on_skill_cooldown_changed(remaining: float, _total: float) -> void:
	var cooling := remaining > 0.01
	skill_cooldown_shade.color = Color(0.0, 0.0, 0.0, 0.68 if cooling else 0.0)
	skill_cooldown_label.text = "%.1f" % remaining if cooling else ""
	skill_icon_text.modulate = Color(0.55, 0.55, 0.55, 1.0) if cooling else Color.WHITE

func _on_skill_activated() -> void:
	skill_panel.scale = Vector2(0.94, 0.94)
	var tween := create_tween()
	tween.tween_property(skill_panel, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK)

func _on_skill_became_ready() -> void:
	var tween := create_tween()
	tween.tween_property(skill_icon_panel, "modulate", Color(1.8, 1.8, 1.8, 1.0), 0.12)
	tween.tween_property(skill_icon_panel, "modulate", Color.WHITE, 0.35)

func set_health(current: float, max_hp: float) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = current

## 経験値ゲージ(2026年8月追加)。scenes/game.gdがExperienceComponent.exp_changed/
## leveled_upを購読して呼ぶ(HPバーと同じ「game.gdが仲介する」方式に合わせる)。
func set_experience(current_exp: int, exp_to_next_level: int, level: int) -> void:
	level_label.text = "Lv.%d" % level
	exp_bar.max_value = maxf(exp_to_next_level, 1)
	exp_bar.value = current_exp

## BossSpawnerがボスを出現させたときに呼ぶ。画面上部中央にボス専用のHPバーを表示する。
func show_boss_health(display_name: String, current: float, max_hp: float) -> void:
	boss_health_container.visible = true
	boss_name_label.text = display_name
	boss_hp_bar.max_value = max_hp
	boss_hp_bar.value = current

func update_boss_health(current: float, max_hp: float) -> void:
	boss_hp_bar.max_value = max_hp
	boss_hp_bar.value = current

func hide_boss_health() -> void:
	boss_health_container.visible = false

func set_room_status(room_number: int, total_rooms: int, room_type: String, template_name: String) -> void:
	var label := "最終ボス" if room_type == "final_boss" else "ボス戦" if room_type == "boss" else "ルーム %d / %d" % [room_number, total_rooms]
	room_status_label.text = "%s  ·  %s" % [label, template_name]
	room_message_label.text = ""

func set_room_message(message: String) -> void:
	room_message_label.text = message

func _on_equipment_picked_up(equipment: EquipmentData) -> void:
	if equipment == null:
		return
	var popup := Label.new()
	popup.text = "%sを入手" % equipment.display_name
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.add_theme_font_size_override("font_size", 18)
	popup.add_theme_color_override("font_color", equipment.get_rarity_color())
	popup.anchor_left = 0.5
	popup.anchor_right = 0.5
	popup.offset_left = -180.0
	popup.offset_right = 180.0
	popup.offset_top = 112.0
	popup.offset_bottom = 144.0
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.modulate.a = 0.0
	add_child(popup)
	var tween := create_tween().set_ignore_time_scale(true)
	tween.tween_property(popup, "modulate:a", 1.0, 0.12)
	tween.tween_interval(0.65)
	tween.tween_property(popup, "modulate:a", 0.0, 0.22)
	tween.finished.connect(popup.queue_free)

func show_room_clear(final_room: bool = false, boss_room: bool = false) -> void:
	_cancel_room_announcement()
	room_clear_label.text = "最終ボス撃破！" if final_room else "ボス撃破！" if boss_room else "ルームクリア"
	room_clear_label.visible = true
	room_clear_label.modulate = Color.WHITE
	room_clear_label.scale = Vector2(0.86, 0.86)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(room_clear_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	tween.tween_property(room_clear_label, "modulate", Color(1.15, 1.05, 0.72, 1.0), 0.18)

func hide_room_clear() -> void:
	_cancel_room_announcement()
	room_clear_label.visible = false

## 操作を止めない短い中央表示。画像や全画面暗転を生成せず、既存HUDだけで
## Boss ROOMに入ったことを伝える。
func show_boss_intro(display_name: String, final_boss: bool = false) -> void:
	_cancel_room_announcement()
	room_clear_label.text = "%s\n%s" % ["最終ボス出現" if final_boss else "ボス出現", display_name]
	room_clear_label.visible = true
	room_clear_label.modulate = Color(1.25, 0.72, 0.62, 1.0)
	room_clear_label.scale = Vector2(0.82, 0.82)
	_room_announcement_tween = create_tween().set_ignore_time_scale(true)
	_room_announcement_tween.tween_property(room_clear_label, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK)
	_room_announcement_tween.tween_interval(0.85)
	_room_announcement_tween.tween_property(room_clear_label, "modulate:a", 0.0, 0.2)
	_room_announcement_tween.tween_callback(func(): room_clear_label.visible = false)

func _cancel_room_announcement() -> void:
	if _room_announcement_tween and _room_announcement_tween.is_valid():
		_room_announcement_tween.kill()
	_room_announcement_tween = null

func set_combo(value: int, milestone: bool = false) -> void:
	if _combo_tween and _combo_tween.is_valid():
		_combo_tween.kill()
	combo_panel.visible = true
	combo_panel.modulate = Color.WHITE
	combo_value_label.text = str(value)
	combo_panel.scale = Vector2(1.12, 1.12) if milestone else Vector2(1.04, 1.04)
	_combo_tween = create_tween()
	_combo_tween.tween_property(combo_panel, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK)

func reset_combo_display() -> void:
	if _combo_tween and _combo_tween.is_valid():
		_combo_tween.kill()
	_combo_tween = create_tween()
	_combo_tween.tween_property(combo_panel, "modulate", Color(1, 1, 1, 0), 0.22)
	_combo_tween.tween_callback(func(): combo_panel.visible = false)

func _on_fragment_collected(_fragment_id: String) -> void:
	# Fragmentは即座に2-slot Buildへ反映されるため、旧Fusion用の生ID列は表示しない。
	for child in fragment_row.get_children():
		child.queue_free()

## 所持武器トレイ(HUD左上、欠片・戦利品の行とは別行)。VS/Brotato的な常時アイコン表示に倣い、
## WeaponManagerComponentが保持する完成武器を一覧表示する。アイコン画像は未用意のため、
## 他のトレイ(戦利品・欠片)と同じくテキスト略称で暫定表示する。
func _refresh_weapon_tray() -> void:
	for child in weapon_row.get_children():
		child.queue_free()
	if _weapon_manager == null:
		return
	for instance in _weapon_manager.get_weapon_instances():
		weapon_row.add_child(_build_weapon_icon(instance))

## ホバー時にツールチップ(武器名・攻撃力・攻撃間隔・属性)を出すため、
## Label既定のmouse_filter(IGNORE)をSTOPへ変更しtooltip_textを設定する。
func _build_weapon_icon(instance: WeaponInstance) -> Label:
	var data := instance.data
	var label := Label.new()
	label.text = "[%s]" % _abbreviate(data.display_name)
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.tooltip_text = _build_weapon_tooltip(data)
	return label

func _abbreviate(display_name: String) -> String:
	return display_name.substr(0, 2) if display_name.length() > 2 else display_name

func _build_weapon_tooltip(data: WeaponData) -> String:
	var lines: Array[String] = [
		data.display_name,
		"攻撃力: %s" % data.base_damage,
		"攻撃間隔: %s秒" % data.attack_interval,
		"属性: %s" % _resolve_element_display_name(data.vfx_theme_id),
	]
	if data.description != "":
		lines.append(data.description)
	return "\n".join(lines)

func _resolve_element_display_name(vfx_theme_id: String) -> String:
	var theme: EffectThemeData = DataLoader.effect_themes.get(vfx_theme_id)
	return theme.display_name if theme else vfx_theme_id

## ボス撃破アイテムを獲得した際に呼ばれる。fragment_rowとは別の行(item_row)へ
## 常時ステータス上昇アイテムの一覧を積み上げていくとともに、画面上部に
## 数秒でフェードアウトするポップアップ演出を出す。同じアイテムを複数回獲得した
## 場合は新しい行を増やさず「×N」で重ね数を表示し、種類数が上限
## (ITEM_TRAY_DISTINCT_LIMIT)を超えたら以降は末尾の「+N」バッジへまとめる
## (仕様書8章)。
func _on_item_acquired(item_id: String, display_name: String) -> void:
	if _item_rows.has(item_id):
		var row: Dictionary = _item_rows[item_id]
		row["count"] += 1
		row["label"].text = _format_item_label(row["display_name"], row["count"])
	elif _item_rows.size() < ITEM_TRAY_DISTINCT_LIMIT:
		# TODO: プロトタイプではテキストラベルで代用。本実装ではアイコン(Texture2D)に差し替える。
		var label := Label.new()
		label.text = _format_item_label(display_name, 1)
		item_row.add_child(label)
		_item_rows[item_id] = {"label": label, "display_name": display_name, "count": 1}
	else:
		_item_overflow_count += 1
		_update_overflow_badge()
	_show_item_popup(display_name)

func _format_item_label(display_name: String, count: int) -> String:
	if count <= 1:
		return "<%s>" % display_name
	return "<%s> ×%d" % [display_name, count]

func set_completed_skill(skill_id: String, display_name: String, level: int) -> void:
	var label: Label = _completed_skill_labels.get(skill_id)
	if label == null:
		label = Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		completed_skill_row.add_child(label)
		_completed_skill_labels[skill_id] = label
	label.text = "【%s Lv.%d】" % [display_name, level]
	label.tooltip_text = "宝箱スキル  %d / %d" % [_completed_skill_labels.size(), ConceptSystem.MAX_COMPLETED_SKILLS]

## 上限を超えた分をまとめる「+N」バッジ。初めて上限を超えた瞬間にitem_rowの
## 末尾へ追加し、以降はテキストを更新するだけにする。
func _update_overflow_badge() -> void:
	if _item_overflow_label == null:
		_item_overflow_label = Label.new()
		item_row.add_child(_item_overflow_label)
	_item_overflow_label.text = "+%d" % _item_overflow_count

func _show_item_popup(display_name: String) -> void:
	var popup := Label.new()
	popup.text = "アイテム獲得: %s" % display_name
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.add_theme_font_size_override("font_size", 24)
	popup.anchor_left = 0.5
	popup.anchor_right = 0.5
	popup.offset_left = -220.0
	popup.offset_right = 220.0
	popup.offset_top = 140.0
	popup.offset_bottom = 180.0
	popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	popup.modulate = Color(1.0, 0.9, 0.4, 0.0)
	add_child(popup)
	var tween := create_tween()
	tween.tween_property(popup, "modulate:a", 1.0, 0.25)
	tween.tween_interval(1.8)
	tween.tween_property(popup, "modulate:a", 0.0, 0.6)
	tween.finished.connect(popup.queue_free)
