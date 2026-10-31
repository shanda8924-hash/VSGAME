extends CanvasLayer
class_name HUD
## プレイ中のHUD。HPバーと所持欠片・獲得アイテム(ミニマル表示)を表示する。
## 【UI方針】親指だけで届く位置に配置する必要はない(HUDは表示専用で操作しないため)。
##
## 【見た目レイヤーについて】2026年8月、「レトロ16bit(SFC・ロマサガ系)×ブライト＆アニメ調」の
## デザイン仕様に合わせて描画層を全面的に差し替えた(ui/common/retro_*.gd)。数値計算・
## シグナル購読・状態遷移(いつ何を表示するか)は以前と完全に同じで、各set_*()/on_*()の
## 「最終的にどのノードへ書き込むか」だけが変わっている。

## 戦利品トレイに個別表示する種類数の上限(仕様書8章)。これを超えた分は
## 個別の行を増やさず、末尾の「+N」バッジへまとめる。
const ITEM_TRAY_DISTINCT_LIMIT := 6
const TRAY_LABEL_WIDTH := 132.0
const TRAY_FONT_SIZE := 18
const TRAY_CHIP_HEIGHT := 38.0

const HP_SEGMENT_COUNT := 10
const BOSS_SEGMENT_COUNT := 20
const IAI_PIP_COUNT := 5 # AbilityStageDots.STAGE_COUNTと同じ5段階(職業スキル熟練度)

@onready var exp_bar: ProgressBar = $MarginContainer/VBoxContainer/ExpBar
@onready var weapon_row: HFlowContainer = $MarginContainer/VBoxContainer/WeaponRow
@onready var item_row: HFlowContainer = $MarginContainer/VBoxContainer/ItemRow
@onready var completed_skill_row: HFlowContainer = $MarginContainer/VBoxContainer/CompletedSkillRow
@onready var gold_label: Label = $MarginContainer/VBoxContainer/GoldLabel
@onready var boss_health_container: VBoxContainer = $BossHealthContainer
@onready var boss_name_label: Label = $BossHealthContainer/BossNameLabel
@onready var boss_hp_bar: ProgressBar = $BossHealthContainer/BossHPBar
@onready var player_panel: RetroPanel = $PlayerPanel
@onready var room_status_label: RichTextLabel = $RoomStatusLabel
@onready var boss_gauge_wrap: Control = $BossGaugeWrap
@onready var room_message_label: Label = $RoomMessageLabel
@onready var room_clear_label: Label = $RoomClearLabel
@onready var combo_panel: PanelContainer = $ComboPanel
@onready var combo_value_label: Label = $ComboPanel/Margin/VBox/Value

var _combo_tween: Tween = null
var _room_announcement_tween: Tween = null
var _loot_toast: Label = null
var _loot_toast_tween: Tween = null
var _loot_toast_count := 0

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
var _tray_container: MarginContainer = null
var _tray_backdrop: Panel = null

# --- PlayerPanel(左下)内の動的ノード ---
var _lv_badge_label: Label
var _hp_gauge: ProgressBar
var _hp_value_label: Label
var _iai_pips_wrap: Control
var _skill_caption_label: Label
var _skill_icon_rect: TextureRect
var _boss_gauge: RetroSegmentGauge

var _skill_display_name := ""
var _skill_cooldown_remaining := 0.0
var _skill_cooldown_total := 0.0
var _loadout_label: Label
var _ability_level := 0

func _ready() -> void:
	EventBus.item_acquired.connect(_on_item_acquired)
	EventBus.equipment_picked_up.connect(_on_equipment_picked_up)
	EventBus.run_gold_changed.connect(_on_run_gold_changed)
	EventBus.run_started.connect(_on_run_started)
	boss_health_container.visible = false
	combo_panel.visible = false
	room_clear_label.visible = false
	_build_player_panel()
	_build_boss_gauge()
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
			_weapon_manager.weapon_added.connect(func(_weapon_data): _refresh_weapon_tray())
			set_ability_stage(_weapon_manager.get_class_ability_level())
	_refresh_weapon_tray()
	_layout_exploration_hud()
	_build_loadout_strip()
	if player:
		player.get_node("EquipmentComponent").equipment_changed.connect(func(_slot: String, _item: EquipmentData): _refresh_loadout_strip())
	if _weapon_manager:
		_weapon_manager.sector_style_changed.connect(_refresh_loadout_strip)
	_refresh_loadout_strip()
	RetroHUDStyle.apply_font(self)
	_on_run_gold_changed(GameManager.run_gold, 0, "hud_ready")

func _layout_exploration_hud() -> void:
	# HP/XPは左上、技は下中央。Sceneの既存データ参照はreparent後も維持する。
	player_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	player_panel.offset_left = 24
	player_panel.offset_right = 374
	player_panel.offset_top = -130
	player_panel.offset_bottom = -32
	_compact_panel(player_panel)
	var status_backdrop := Panel.new()
	status_backdrop.name = "StatusReadabilityPanel"
	status_backdrop.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	status_backdrop.offset_left = -340
	status_backdrop.offset_right = 340
	status_backdrop.offset_top = 6
	status_backdrop.offset_bottom = 92
	status_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_backdrop.add_theme_stylebox_override("panel", PixelUIStyle.FrameArt.box(true, 8))
	add_child(status_backdrop)
	move_child(status_backdrop, 0)
	var root := player_panel.content.get_child(0)
	exp_bar.reparent(self)
	exp_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	exp_bar.offset_left = 24
	exp_bar.offset_right = -24
	exp_bar.offset_top = -18
	exp_bar.offset_bottom = -10
	exp_bar.tooltip_text = "経験値"
	exp_bar.custom_minimum_size = Vector2(0, 8)
	PixelUIStyle.apply_progress_bar(exp_bar, RetroHUDStyle.IAI_TEAL)
	var skill_panel := RetroPanel.new()
	add_child(skill_panel)
	skill_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	skill_panel.offset_left = -374
	skill_panel.offset_right = -24
	skill_panel.offset_top = -130
	skill_panel.offset_bottom = -32
	_compact_panel(skill_panel)
	var skills := VBoxContainer.new()
	var skill_row := HBoxContainer.new()
	skill_row.add_theme_constant_override("separation", 12)
	skill_panel.content.add_child(skill_row)
	_skill_icon_rect = TextureRect.new()
	_skill_icon_rect.custom_minimum_size = Vector2(46, 46)
	_skill_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_skill_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_skill_icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_skill_icon_rect.texture = _load_active_skill_icon()
	skill_row.add_child(_skill_icon_rect)
	skills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills.alignment = BoxContainer.ALIGNMENT_CENTER
	skill_row.add_child(skills)
	_skill_caption_label.reparent(skills)
	_skill_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_iai_pips_wrap.reparent(skills)
	gold_label.reparent(self)
	gold_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	gold_label.offset_left = -220
	gold_label.offset_right = -24
	gold_label.offset_top = 24
	gold_label.offset_bottom = 54
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var coin_frame := PixelUIStyle.FrameArt.box(true, 10)
	coin_frame.content_margin_top = 6
	coin_frame.content_margin_bottom = 6
	gold_label.add_theme_stylebox_override("normal", coin_frame)
	gold_label.text = "金貨　0"
	var tray := $MarginContainer as MarginContainer
	_tray_container = tray
	tray.theme = PixelUIStyle.shared_theme()
	tray.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tray.offset_left = -300
	tray.offset_right = -24
	tray.offset_top = 68
	tray.offset_bottom = 530
	var tray_backdrop := Panel.new()
	_tray_backdrop = tray_backdrop
	tray_backdrop.name = "RelicTrayBackdrop"
	tray_backdrop.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tray_backdrop.offset_left = -310
	tray_backdrop.offset_right = -14
	tray_backdrop.offset_top = 60
	tray_backdrop.offset_bottom = 540
	tray_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tray_backdrop)
	move_child(tray_backdrop, tray.get_index())
	PixelUIStyle.apply_panel(tray_backdrop, PixelUIStyle.BORDER, true)
	var tray_column := tray.get_node("VBoxContainer") as VBoxContainer
	_add_tray_header(tray_column, weapon_row, "武装", PixelUIStyle.BORDER_HOVER)
	_add_tray_header(tray_column, item_row, "戦利品", Color("e8bd58"))
	_add_tray_header(tray_column, completed_skill_row, "完成大技", PixelUIStyle.JEWEL)
	_refresh_tray_height()
	combo_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	combo_panel.offset_left = -65
	combo_panel.offset_right = 65
	combo_panel.offset_top = -115
	combo_panel.offset_bottom = -35
	combo_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	PixelUIStyle.FrameArt.hide_old_ornament(combo_panel)
	combo_value_label.add_theme_font_size_override("font_size", 24)
	room_status_label.add_theme_font_size_override("normal_font_size", 20)
	room_status_label.offset_top = 16
	room_status_label.offset_bottom = 74
	boss_gauge_wrap.offset_top = 76
	boss_gauge_wrap.offset_bottom = 84
	tray.hide()
	tray_backdrop.hide()
	var tray_button := Button.new()
	tray_button.text = "武装・戦利品"
	tray_button.tooltip_text = "取得した武器・戦利品・完成大技を表示"
	add_child(tray_button)
	tray_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tray_button.offset_left = -180
	tray_button.offset_right = -24
	tray_button.offset_top = 58
	tray_button.offset_bottom = 88
	tray_button.add_theme_font_size_override("font_size", 18)
	PixelUIStyle.apply_button(tray_button)
	tray.offset_top = 100
	tray_backdrop.offset_top = 92
	tray_button.pressed.connect(func():
		tray.visible = not tray.visible
		tray_backdrop.visible = tray.visible
		_refresh_tray_height()
	)
	var guide := Label.new()
	guide.name = "ControlsGuide"
	guide.text = "K 回避　L 技　J 反撃　E 調べる\nC 所持品　T 天賦図　M 地図　Esc 停止"
	add_child(guide)
	guide.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	guide.offset_left = 38
	guide.offset_right = 538
	guide.offset_top = -204
	guide.offset_bottom = -136
	guide.add_theme_font_size_override("font_size", 18)
	guide.add_theme_stylebox_override("normal", PixelUIStyle.badge_style(PixelUIStyle.STONE_DARK, Color("0d1622")))
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if DisplayServer.is_touchscreen_available() or "--touch-preview" in OS.get_cmdline_user_args():
		guide.hide()
		player_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		player_panel.offset_left = 24
		player_panel.offset_right = 374
		player_panel.offset_top = 120
		player_panel.offset_bottom = 218
		skill_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		skill_panel.offset_left = -374
		skill_panel.offset_right = -24
		skill_panel.offset_top = 120
		skill_panel.offset_bottom = 218

func _compact_panel(host: RetroPanel) -> void:
	for child in host.get_children():
		if child is Panel:
			PixelUIStyle.FrameArt.hide_old_ornament(child)
			child.add_theme_stylebox_override("panel", PixelUIStyle.FrameArt.box(true, 8, Color.WHITE))
	for side in ["left", "right", "top", "bottom"]:
		host.content.add_theme_constant_override("margin_" + side, 12)

func _build_loadout_strip() -> void:
	_loadout_label = Label.new()
	_loadout_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_loadout_label.offset_left = 24
	_loadout_label.offset_right = 350
	_loadout_label.offset_top = 14
	_loadout_label.offset_bottom = 106
	_loadout_label.add_theme_font_size_override("font_size", 18)
	_loadout_label.clip_text = true
	_loadout_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_loadout_label.add_theme_stylebox_override("normal", PixelUIStyle.FrameArt.box(true, 8))
	_loadout_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_loadout_label)

func _refresh_loadout_strip() -> void:
	if _loadout_label == null or _weapon_manager == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	var equipped := player.equipment_component.get_equipped("weapon") if player else null
	var main_name := equipped.display_name if equipped else _weapon_manager._character_data.display_name if _weapon_manager._character_data else "素手"
	var secondary := "なし"
	var instances := _weapon_manager.get_weapon_instances()
	if not instances.is_empty(): secondary = instances[0].data.display_name
	var skill := "準備完了" if _skill_cooldown_remaining <= 0.0 else "残り %.1f秒" % _skill_cooldown_remaining
	_loadout_label.text = "主: %s  /  副: %s\n技: %s  %s\n%s" % [main_name, secondary, _skill_display_name, skill, _weapon_manager.get_sector_style_summary()]
	_loadout_label.tooltip_text = _loadout_label.text

func _add_tray_header(container: VBoxContainer, before: Control, text: String, accent: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", accent)
	container.add_child(label)
	container.move_child(label, before.get_index())

func _refresh_tray_height() -> void:
	if _tray_container == null or _tray_backdrop == null:
		return
	var row_count := ceili(weapon_row.get_child_count() / 2.0)
	row_count += ceili(item_row.get_child_count() / 2.0)
	row_count += ceili(completed_skill_row.get_child_count() / 2.0)
	var height := clampf(132.0 + row_count * (TRAY_CHIP_HEIGHT + 2.0), 132.0, 500.0)
	_tray_container.offset_bottom = _tray_container.offset_top + height
	_tray_backdrop.offset_bottom = _tray_container.offset_bottom + 10.0

func _load_active_skill_icon() -> Texture2D:
	var character_id := GameManager.selected_character_id
	var path := "res://assets/ui/icons/battle_skills/talents/swordsman_root.png" if character_id == "swordsman" else "res://assets/ui/icons/battle_skills/upgrades/class_%s_lv2.png" % character_id
	return load(path) as Texture2D if ResourceLoader.exists(path) else preload("res://assets/ui/shop/weapon_icon.png")

func _on_run_started() -> void:
	gold_label.visible = GameManager.map_mode_active
	_on_run_gold_changed(GameManager.run_gold, 0, "run_started")

func _on_run_gold_changed(current_gold: int, _delta: int, _source: String) -> void:
	if gold_label:
		gold_label.text = "金貨　%d G" % maxi(current_gold, 0)

# ============================================================
# PlayerPanel(左下): LVバッジ・HPゲージ(連続比率)・居合ピップ(5段階)・SPACEキャプション
# ============================================================

func _build_player_panel() -> void:
	var content := player_panel.content
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	content.add_child(root)

	var lv_row := HBoxContainer.new()
	root.add_child(lv_row)
	var lv_box := PanelContainer.new()
	var lv_style := StyleBoxFlat.new()
	lv_style.bg_color = RetroHUDStyle.VOID_DEEP
	lv_style.border_color = RetroHUDStyle.BRONZE_LIGHT
	lv_style.set_border_width_all(1)
	lv_style.set_corner_radius_all(0)
	lv_style.content_margin_left = 8.0
	lv_style.content_margin_right = 8.0
	lv_style.content_margin_top = 2.0
	lv_style.content_margin_bottom = 2.0
	lv_box.add_theme_stylebox_override("panel", lv_style)
	lv_row.add_child(lv_box)
	_lv_badge_label = Label.new()
	_lv_badge_label.text = "LV 1"
	_lv_badge_label.add_theme_font_size_override("font_size", 20)
	_lv_badge_label.add_theme_color_override("font_color", RetroHUDStyle.BRONZE_LIGHT)
	lv_box.add_child(_lv_badge_label)
	var profession := Label.new()
	var character: CharacterData = DataLoader.characters.get(GameManager.selected_character_id)
	profession.text = character.display_name if character else "冒険者"
	profession.add_theme_font_size_override("font_size", 20)
	lv_row.add_child(profession)

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	root.add_child(hp_row)
	var hp_label := Label.new()
	hp_label.text = "HP"
	hp_label.custom_minimum_size = Vector2(30, 0)
	hp_label.add_theme_font_size_override("font_size", 20)
	hp_label.add_theme_color_override("font_color", RetroHUDStyle.PARCHMENT_DIM)
	hp_row.add_child(hp_label)

	_hp_gauge = ProgressBar.new()
	_hp_gauge.custom_minimum_size = Vector2(150, 14)
	_hp_gauge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_gauge.show_percentage = false
	_hp_gauge.add_theme_stylebox_override("background", RetroHUDStyle.track_style())
	_hp_gauge.add_theme_stylebox_override("fill", RetroHUDStyle.segment_style(RetroHUDStyle.HP_RED_LIGHT))
	hp_row.add_child(_hp_gauge)

	_hp_value_label = Label.new()
	_hp_value_label.custom_minimum_size = Vector2(92, 0)
	_hp_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hp_value_label.add_theme_font_size_override("font_size", 20)
	_hp_value_label.add_theme_color_override("font_color", RetroHUDStyle.PARCHMENT_DIM)
	hp_row.add_child(_hp_value_label)

	_iai_pips_wrap = Control.new()
	_iai_pips_wrap.custom_minimum_size = Vector2(0, 18)
	root.add_child(_iai_pips_wrap)
	_refresh_iai_pips()

	_skill_caption_label = Label.new()
	_skill_caption_label.add_theme_font_size_override("font_size", 20)
	_skill_caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skill_caption_label.add_theme_color_override("font_color", RetroHUDStyle.PARCHMENT_DIM)
	root.add_child(_skill_caption_label)
	_refresh_skill_caption()

	RetroHUDStyle.apply_font(root)

func _refresh_iai_pips() -> void:
	if _iai_pips_wrap == null:
		return
	for child in _iai_pips_wrap.get_children():
		child.queue_free()
	_iai_pips_wrap.add_child(RetroPipRow.build(IAI_PIP_COUNT, _ability_level, RetroHUDStyle.IAI_TEAL_LIGHT))

func _refresh_skill_caption() -> void:
	if _skill_caption_label == null:
		return
	var cooling := _skill_cooldown_remaining > 0.01
	var state_text := "あと %.1f秒" % _skill_cooldown_remaining if cooling else "使用可能"
	var name_text := _skill_display_name if _skill_display_name != "" else "アクティブスキル"
	_skill_caption_label.text = "[L]  %s  ・  %s" % [name_text, state_text]
	_skill_caption_label.add_theme_color_override("font_color", RetroHUDStyle.PARCHMENT_DIM if cooling else RetroHUDStyle.IAI_TEAL_LIGHT)

# ============================================================
# TopBanner: 撃破カウント用ボスゲージ(MAPモードのみ表示)
# ============================================================

func _build_boss_gauge() -> void:
	_boss_gauge = RetroSegmentGauge.new()
	_boss_gauge.set_anchors_preset(Control.PRESET_FULL_RECT)
	boss_gauge_wrap.add_child(_boss_gauge)
	_boss_gauge.configure(BOSS_SEGMENT_COUNT, RetroHUDStyle.BOSS_PURPLE_LIGHT, RetroHUDStyle.VOID, true)

func _on_class_ability_level_changed(new_level: int) -> void:
	set_ability_stage(new_level)

## 職業スキルの熟練度(ability_level)をPlayerPanelの居合ピップで表示する
## (キャラクターの経験値ゲージ(set_experience())とは完全に別の概念・別のデータ・
## 別の見た目。同じバーに重ねたり色を似せたりしない)。
func set_ability_stage(ability_level: int) -> void:
	_ability_level = ability_level
	_refresh_iai_pips()

func _on_skill_configured(display_name: String, _icon_text: String, cooldown: float, _color: Color) -> void:
	_skill_display_name = display_name
	if "/" in _skill_display_name:
		_skill_display_name = _skill_display_name.get_slice("/", 1)
	_skill_cooldown_total = cooldown
	_on_skill_cooldown_changed(0.0, cooldown)

func _on_skill_cooldown_changed(remaining: float, total: float) -> void:
	_skill_cooldown_remaining = remaining
	_skill_cooldown_total = total
	_refresh_skill_caption()
	_refresh_loadout_strip()

func _on_skill_activated() -> void:
	if player_panel == null:
		return
	player_panel.scale = Vector2(0.97, 0.97)
	var tween := create_tween()
	tween.tween_property(player_panel, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK)

func _on_skill_became_ready() -> void:
	if _skill_caption_label == null:
		return
	var tween := create_tween()
	tween.tween_property(_skill_caption_label, "modulate", Color(1.8, 1.8, 1.8, 1.0), 0.12)
	tween.tween_property(_skill_caption_label, "modulate", Color.WHITE, 0.35)

func set_health(current: float, max_hp: float) -> void:
	if _hp_gauge:
		_hp_gauge.max_value = maxf(max_hp, 1.0)
		_hp_gauge.value = current
	if _hp_value_label:
		_hp_value_label.text = "%d/%d" % [int(round(current)), int(round(max_hp))]

## 経験値ゲージ(2026年8月追加)。scenes/game.gdがExperienceComponent.exp_changed/
## leveled_upを購読して呼ぶ(HPバーと同じ「game.gdが仲介する」方式に合わせる)。
func set_experience(current_exp: int, exp_to_next_level: int, level: int) -> void:
	if _lv_badge_label:
		_lv_badge_label.text = "LV %d" % level
	exp_bar.max_value = maxf(exp_to_next_level, 1)
	exp_bar.value = current_exp

## BossSpawnerがボスを出現させたときに呼ぶ。画面上部中央にボス専用のHPバーを表示する。
func show_boss_health(display_name: String, current: float, max_hp: float) -> void:
	boss_health_container.visible = true
	if GameManager.map_mode_active and not GameManager.survival_mode_active:
		room_status_label.visible = false
		boss_gauge_wrap.visible = false
	boss_name_label.text = display_name
	boss_hp_bar.max_value = max_hp
	boss_hp_bar.value = current

func update_boss_health(current: float, max_hp: float) -> void:
	boss_hp_bar.max_value = max_hp
	boss_hp_bar.value = current

func hide_boss_health() -> void:
	boss_health_container.visible = false
	if GameManager.map_mode_active:
		room_status_label.visible = true
		boss_gauge_wrap.visible = true

func set_survival_status(map_name: String, elapsed: float, duration: float, kills: int, phase: String, boss_phase: bool = false) -> void:
	var left := maxi(ceili(duration - elapsed), 0)
	room_status_label.visible = true
	var clock := "ボスまで %d:%02d" % [left / 60, left % 60]
	if boss_phase:
		var fight_time := maxi(int(elapsed - duration), 0)
		clock = "ボス戦 %d:%02d" % [fight_time / 60, fight_time % 60]
	if GameManager.survival_completed: clock = "撃破成功"
	room_status_label.text = "[center]%s　[color=#d6c29d][b]%s[/b][/color]　撃破 %d\n%s[/center]" % [map_name, clock, kills, phase]
	boss_gauge_wrap.visible = not boss_phase
	if _boss_gauge: _boss_gauge.set_value(minf(elapsed, duration), duration)
	boss_health_container.offset_top = 98.0
	boss_health_container.offset_bottom = 154.0
	room_message_label.offset_top = 162.0
	room_message_label.offset_bottom = 194.0
	room_message_label.text = ""

func set_map_status(map_index: int, total_maps: int, map_name: String, elapsed: float, fallback_seconds: float, kills: int, required_kills: int, boss_ready: bool, objective: String = "") -> void:
	var fallback_left := maxi(int(ceil(fallback_seconds - elapsed)), 0)
	var map_line := "MAP [color=#%s][b]%d / %d[/b][/color] ・ %s" % [RetroHUDStyle.BRONZE_LIGHT.to_html(false), map_index, total_maps, map_name]
	if total_maps > 3:
		map_line = "深度 [color=#%s][b]%d / %d層[/b][/color] ・ %s" % [RetroHUDStyle.BRONZE_LIGHT.to_html(false), map_index, total_maps, map_name]
	var boss_line: String
	if boss_ready:
		boss_line = "[color=#%s]封印解除！ ボス門へ[/color]" % RetroHUDStyle.BRONZE_LIGHT.to_html(false)
	else:
		boss_line = "封印解除 [color=#%s]%d / %d[/color] ・ 時間解放まで [color=#%s]%d:%02d[/color]" % [
			RetroHUDStyle.BOSS_PURPLE_LIGHT.to_html(false), mini(kills, required_kills), required_kills,
			RetroHUDStyle.HP_RED_LIGHT.to_html(false), fallback_left / 60, fallback_left % 60,
		]
	if not objective.is_empty(): boss_line = objective
	room_status_label.text = "[center]%s\n%s[/center]" % [map_line, boss_line]
	room_message_label.offset_top = 110.0
	room_message_label.offset_bottom = 142.0
	room_message_label.text = ""
	if boss_health_container.visible:
		return
	boss_gauge_wrap.visible = true
	if _boss_gauge:
		_boss_gauge.set_value(mini(kills, required_kills), required_kills)

func set_room_message(message: String) -> void:
	room_message_label.text = message

func _on_equipment_picked_up(equipment: EquipmentData) -> void:
	if equipment == null:
		return
	if not is_instance_valid(_loot_toast):
		_loot_toast = Label.new()
		_loot_toast.name = "EquipmentLootToast"
		_loot_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_loot_toast.add_theme_font_size_override("font_size", 18)
		_loot_toast.add_theme_stylebox_override("normal", PixelUIStyle.FrameArt.box(true, 6))
		_loot_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_loot_toast.offset_left = -210.0
		_loot_toast.offset_right = 210.0
		_loot_toast.offset_top = -116.0
		_loot_toast.offset_bottom = -82.0
		_loot_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_loot_toast)
		RetroHUDStyle.apply_font(_loot_toast)
	if _loot_toast_tween != null and _loot_toast_tween.is_valid():
		_loot_toast_tween.kill()
	_loot_toast_count += 1
	_loot_toast.text = "%sを入手" % equipment.display_name if _loot_toast_count == 1 else "装備を%d個入手" % _loot_toast_count
	_loot_toast.add_theme_color_override("font_color", equipment.get_rarity_color())
	_loot_toast.show()
	_loot_toast.modulate.a = 1.0
	_loot_toast_tween = create_tween().set_ignore_time_scale(true)
	_loot_toast_tween.tween_interval(1.1)
	_loot_toast_tween.tween_property(_loot_toast, "modulate:a", 0.0, 0.22)
	_loot_toast_tween.finished.connect(func():
		_loot_toast.hide()
		_loot_toast_count = 0
	)

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
	_refresh_tray_height.call_deferred()
	_refresh_loadout_strip()

## ホバー時にツールチップ(武器名・攻撃力・攻撃間隔・属性)を出すため、
## Label既定のmouse_filter(IGNORE)をSTOPへ変更しtooltip_textを設定する。
func _build_weapon_icon(instance: WeaponInstance) -> Label:
	var data := instance.data
	var icon := data.icon
	if icon == null:
		icon = preload("res://assets/ui/shop/weapon_icon.png")
	var accent := PixelUIStyle.BORDER_HOVER
	var effect_theme: EffectThemeData = DataLoader.effect_themes.get(data.vfx_theme_id)
	if effect_theme:
		accent = effect_theme.enhanced_color
	var label := _new_tray_label(data.display_name, "", icon, accent)
	label.tooltip_text = _build_weapon_tooltip(data)
	return label

## 2列の固定幅。名前だけを詰め、Lv/所持数は最後まで表示する。
## 動的に生成されたLabelにも書体/サイズを明示し、全文はTooltipへ残す。
func _new_tray_label(display_name: String, suffix: String = "", icon: Texture2D = null, accent: Color = PixelUIStyle.BORDER_HOVER) -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(TRAY_LABEL_WIDTH, TRAY_CHIP_HEIGHT)
	label.add_theme_font_size_override("font_size", TRAY_FONT_SIZE)
	RetroHUDStyle.apply_font(label)
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.clip_text = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var chip_style := PixelUIStyle.badge_style(accent, Color("111c29"))
	chip_style.content_margin_left = 38.0 if icon else 8.0
	chip_style.content_margin_right = 6.0
	chip_style.content_margin_top = 3.0
	chip_style.content_margin_bottom = 3.0
	label.add_theme_stylebox_override("normal", chip_style)
	label.set_meta("tray_text_width", TRAY_LABEL_WIDTH - (46.0 if icon else 16.0))
	if icon:
		var picture := TextureRect.new()
		picture.name = "TrayIcon"
		picture.texture = icon
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.anchor_top = 0.5
		picture.anchor_bottom = 0.5
		picture.offset_left = 5
		picture.offset_right = 33
		picture.offset_top = -14
		picture.offset_bottom = 14
		label.add_child(picture)
	_set_tray_text(label, display_name, suffix)
	return label

func _set_tray_text(label: Label, display_name: String, suffix: String = "") -> void:
	var localized := PixelUIStyle.localized_name(display_name)
	label.tooltip_text = localized + suffix
	var shortened := localized
	var font := label.get_theme_font("font")
	var available_width := float(label.get_meta("tray_text_width", TRAY_LABEL_WIDTH))
	if font.get_string_size(shortened + suffix, HORIZONTAL_ALIGNMENT_LEFT, -1, TRAY_FONT_SIZE).x <= available_width:
		label.text = shortened + suffix
		return
	while not shortened.is_empty() and font.get_string_size(shortened + "…" + suffix, HORIZONTAL_ALIGNMENT_LEFT, -1, TRAY_FONT_SIZE).x > available_width:
		shortened = shortened.left(shortened.length() - 1)
	label.text = shortened + "…" + suffix

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

## ボス撃破アイテムを獲得した際に呼ばれる。item_row(戦利品トレイ)へ
## 常時ステータス上昇アイテムの一覧を積み上げていくとともに、画面上部に
## 数秒でフェードアウトするポップアップ演出を出す。同じアイテムを複数回獲得した
## 場合は新しい行を増やさず「×N」で重ね数を表示し、種類数が上限
## (ITEM_TRAY_DISTINCT_LIMIT)を超えたら以降は末尾の「+N」バッジへまとめる
## (仕様書8章)。
func _on_item_acquired(item_id: String, display_name: String) -> void:
	if _item_rows.has(item_id):
		var row: Dictionary = _item_rows[item_id]
		row["count"] += 1
		_set_tray_text(row["label"], row["display_name"], " ×%d" % row["count"])
	elif _item_rows.size() < ITEM_TRAY_DISTINCT_LIMIT:
		var item_data: ItemData = DataLoader.items.get(item_id)
		var icon: Texture2D = null
		if item_data and item_data.icon_path != "" and ResourceLoader.exists(item_data.icon_path):
			icon = load(item_data.icon_path) as Texture2D
		if icon == null:
			icon = preload("res://assets/ui/shop/weapon_icon.png")
		var label := _new_tray_label(display_name, " ×1", icon, Color("e8bd58"))
		item_row.add_child(label)
		_item_rows[item_id] = {"label": label, "display_name": display_name, "count": 1}
	else:
		_item_overflow_count += 1
		_update_overflow_badge()
	_refresh_tray_height.call_deferred()
	_show_item_popup(display_name)

func set_completed_skill(skill_id: String, display_name: String, level: int) -> void:
	var label: Label = _completed_skill_labels.get(skill_id)
	if label == null:
		var definition: Dictionary = {}
		var concept_system := get_parent().get_node_or_null("ConceptSystem") as ConceptSystem
		if concept_system:
			definition = concept_system.get_completed_skill_definition(skill_id)
		var icon_path := String(definition.get("icon_path", ""))
		var icon: Texture2D = load(icon_path) as Texture2D if icon_path != "" and ResourceLoader.exists(icon_path) else null
		if icon == null:
			icon = preload("res://assets/ui/icons/battle_skills/completed/inferno_pillar.png")
		var accent := Color.from_string(String(definition.get("color", "#72d7e8")), PixelUIStyle.JEWEL)
		label = _new_tray_label(display_name, "", icon, accent)
		completed_skill_row.add_child(label)
		_completed_skill_labels[skill_id] = label
	_set_tray_text(label, display_name, " Lv.%d" % level)
	label.tooltip_text += "\n宝箱スキル  %d / %d" % [_completed_skill_labels.size(), ConceptSystem.MAX_COMPLETED_SKILLS]
	_refresh_tray_height.call_deferred()

## 上限を超えた分をまとめる「+N」バッジ。初めて上限を超えた瞬間にitem_rowの
## 末尾へ追加し、以降はテキストを更新するだけにする。
func _update_overflow_badge() -> void:
	if _item_overflow_label == null:
		_item_overflow_label = _new_tray_label("ほか")
		item_row.add_child(_item_overflow_label)
	_set_tray_text(_item_overflow_label, "ほか", " +%d" % _item_overflow_count)

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
	RetroHUDStyle.apply_font(popup)
	var tween := create_tween()
	tween.tween_property(popup, "modulate:a", 1.0, 0.25)
	tween.tween_interval(1.8)
	tween.tween_property(popup, "modulate:a", 0.0, 0.6)
	tween.finished.connect(popup.queue_free)

func set_exploration_status(map_index: int, map_name: String, region: String, objective: String, visited: int, total: int, floor_index: int = 1, floors_per_map: int = 20) -> void:
	room_status_label.text = "[center]MAP %d / 3 ・ 地下%d / %d層 ・ %s\n%s ・ %s  [M][/center]" % [map_index, floor_index, floors_per_map, map_name, region, objective]
	if not boss_health_container.visible:
		boss_gauge_wrap.visible = false
