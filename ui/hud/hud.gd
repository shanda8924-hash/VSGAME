extends CanvasLayer
class_name HUD
## プレイ中のHUD（表示専用。数値計算・抽選・入力はここに持たない）。
##
## 2026-10-31 Phase 4：5分サバイバルの情報優先度に合わせて描画層を組み直した。
## 上中央に時計と終盤ボスの予告ゲージ、左上に職業/LV/HP/XP、その下に取得済み強化の段階、
## 右上に金貨と（中身がある時だけ）武装・戦利品、右下に職業技。各set_*()/on_*()の
## 呼び出し元と引数、Signal購読、状態遷移は変えず、最終的な描き先だけが変わっている。

## 戦利品トレイに個別表示する種類数の上限(仕様書8章)。これを超えた分は
## 個別の行を増やさず、末尾の「+N」バッジへまとめる。
const ITEM_TRAY_DISTINCT_LIMIT := 6
const TRAY_LABEL_WIDTH := 132.0
const TRAY_FONT_SIZE := 18
const TRAY_CHIP_HEIGHT := 38.0

const HP_SEGMENT_COUNT := 10
const BOSS_SEGMENT_COUNT := 20
const IAI_PIP_COUNT := 5 # AbilityStageDots.STAGE_COUNTと同じ5段階(職業スキル熟練度)

## 取得済み強化の表示順（data/upgrades/survival_*.json）。
const SURVIVAL_UPGRADE_IDS: Array[String] = ["survival_area", "survival_haste", "survival_power", "survival_echo", "survival_chain", "survival_guard", "survival_multishot", "survival_pierce"]
## 操作案内を畳むまでの戦闘時間。
const GUIDE_COLLAPSE_SECONDS := 20.0
const COIN_ICON := preload("res://assets/ui/complete_ui_pack/book/icon_coin.png")
const GOLD_TEXT := Color("ffd87a")

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
var _tray_header: Button = null
var _tray_expanded := true
var _is_touch := false

# --- PlayerPanel(左上) ---
var _lv_badge_label: Label
var _hp_gauge: ProgressBar
var _hp_value_label: Label
var _weapon_name_label: Label

# --- 取得済み強化（左上の下） ---
var _upgrade_strip: HFlowContainer

# --- 職業技パネル(右下) ---
var _skill_panel: RetroPanel
var _skill_icon_rect: TextureRect
var _skill_shade: ColorRect
var _skill_key_label: Label
var _skill_name_label: Label
var _skill_state_label: Label
var _iai_pips_wrap: Control
var _skill_display_name := ""
var _skill_cooldown_remaining := 0.0
var _skill_cooldown_total := 0.0
var _ability_level := 0

# --- 上中央のステージ石板 ---
var _stage_panel: RetroPanel
var _clock_row: HBoxContainer
var _clock_prefix_label: Label
var _clock_label: Label
var _boss_gauge: RetroSegmentGauge ## 終盤ボスまでの時間（旧: 撃破カウント）
var _boss_hp_wrap: Control
var _boss_hp_gauge: RetroSegmentGauge
var _boss_display_name := ""

# --- 操作案内(左下、PCのみ) ---
var _guide_full: Label
var _guide_chip: Button
var _guide_collapsed := false
var _guide_pinned := false

func _ready() -> void:
	EventBus.item_acquired.connect(_on_item_acquired)
	EventBus.equipment_picked_up.connect(_on_equipment_picked_up)
	EventBus.run_gold_changed.connect(_on_run_gold_changed)
	EventBus.run_started.connect(_on_run_started)
	_is_touch = DisplayServer.is_touchscreen_available() or "--touch-preview" in OS.get_cmdline_user_args()
	boss_health_container.visible = false
	combo_panel.visible = false
	room_clear_label.visible = false
	_build_player_panel()
	_build_boss_gauge()
	var player := get_tree().get_first_node_in_group("player")
	if player:
		_weapon_manager = player.get_node_or_null("WeaponManagerComponent")
		_active_skill = player.get_node_or_null("ActiveSkillComponent")
	_layout_exploration_hud()
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
		_weapon_manager.sector_style_changed.connect(_refresh_loadout)
		set_ability_stage(_weapon_manager.get_class_ability_level())
	if player:
		player.get_node("EquipmentComponent").equipment_changed.connect(func(_slot: String, _item: EquipmentData): _refresh_loadout())
	_refresh_weapon_tray()
	_refresh_loadout()
	RetroHUDStyle.apply_font(self)
	_on_run_gold_changed(GameManager.run_gold, 0, "hud_ready")

# ============================================================
# 配置（1600×900基準。タッチ横画面は操作ボタンと重ならない位置へ）
# ============================================================

func _layout_exploration_hud() -> void:
	# 左上: 職業・LV・HP・XP
	player_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	player_panel.offset_left = 24
	player_panel.offset_right = 394
	player_panel.offset_top = 20
	player_panel.offset_bottom = 140
	_compact_panel(player_panel)

	# 上中央: ステージ石板（時計 → ボス戦ではボスHP）
	_build_stage_panel()

	# 左上の下: 取得済み強化
	_upgrade_strip = HFlowContainer.new()
	_upgrade_strip.name = "UpgradeStrip"
	_upgrade_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_upgrade_strip.add_theme_constant_override("h_separation", 6)
	_upgrade_strip.add_theme_constant_override("v_separation", 6)
	add_child(_upgrade_strip)
	_upgrade_strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_upgrade_strip.offset_left = 24
	_upgrade_strip.offset_right = 24 + 560
	_upgrade_strip.offset_top = 150
	_upgrade_strip.offset_bottom = 210

	# 右上: 金貨
	gold_label.reparent(self)
	gold_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	gold_label.offset_left = -224
	gold_label.offset_right = -24
	gold_label.offset_top = 20
	gold_label.offset_bottom = 58
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_label.add_theme_font_size_override("font_size", 22)
	gold_label.add_theme_color_override("font_color", GOLD_TEXT)
	gold_label.add_theme_constant_override("outline_size", 0)
	gold_label.tooltip_text = "所持金貨。補給箱のショップで使う"
	gold_label.mouse_filter = Control.MOUSE_FILTER_STOP
	var coin_frame := PixelUIStyle.FrameArt.box(true, 10)
	coin_frame.content_margin_left = 46
	coin_frame.content_margin_right = 12
	coin_frame.content_margin_top = 6
	coin_frame.content_margin_bottom = 6
	gold_label.add_theme_stylebox_override("normal", coin_frame)
	var coin := TextureRect.new()
	coin.name = "CoinIcon"
	coin.texture = COIN_ICON
	coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.anchor_top = 0.5
	coin.anchor_bottom = 0.5
	coin.offset_left = 12
	coin.offset_right = 38
	coin.offset_top = -13
	coin.offset_bottom = 13
	gold_label.add_child(coin)

	# 右上の下: 武装・戦利品トレイ（中身がある時だけ）
	var tray := $MarginContainer as MarginContainer
	_tray_container = tray
	tray.theme = PixelUIStyle.shared_theme()
	tray.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tray.offset_left = -300
	tray.offset_right = -24
	var tray_top := 108.0 if not _is_touch else 236.0
	tray.offset_top = tray_top
	tray.offset_bottom = tray_top + 132
	var tray_backdrop := Panel.new()
	_tray_backdrop = tray_backdrop
	tray_backdrop.name = "RelicTrayBackdrop"
	tray_backdrop.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tray_backdrop.offset_left = -310
	tray_backdrop.offset_right = -14
	tray_backdrop.offset_top = tray_top - 8
	tray_backdrop.offset_bottom = tray_top + 142
	tray_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tray_backdrop)
	move_child(tray_backdrop, tray.get_index())
	PixelUIStyle.apply_panel(tray_backdrop, PixelUIStyle.BORDER, true)
	var tray_column := tray.get_node("VBoxContainer") as VBoxContainer
	_add_tray_header(tray_column, weapon_row, "武装", PixelUIStyle.BORDER_HOVER)
	_add_tray_header(tray_column, item_row, "戦利品", Color("e8bd58"))
	_add_tray_header(tray_column, completed_skill_row, "秘技", Color("ff9a5c"))
	_tray_header = Button.new()
	_tray_header.name = "TrayHeader"
	_tray_header.tooltip_text = "取得した武器・戦利品・完成大技を表示／折りたたみ"
	_tray_header.focus_mode = Control.FOCUS_NONE
	add_child(_tray_header)
	_tray_header.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_tray_header.offset_left = -200
	_tray_header.offset_right = -24
	_tray_header.offset_top = tray_top - 44
	_tray_header.offset_bottom = tray_top - 10
	_tray_header.add_theme_font_size_override("font_size", 18)
	PixelUIStyle.apply_button(_tray_header)
	_tray_header.pressed.connect(func():
		_tray_expanded = not _tray_expanded
		_refresh_tray_height()
	)
	_refresh_tray_height()

	# 右下: 職業技
	_build_skill_panel()

	# 下中央: コンボ・入手通知・中央告知は従来位置
	combo_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	combo_panel.offset_left = -65
	combo_panel.offset_right = 65
	combo_panel.offset_top = -115
	combo_panel.offset_bottom = -35
	combo_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	PixelUIStyle.FrameArt.hide_old_ornament(combo_panel)
	combo_value_label.add_theme_font_size_override("font_size", 24)

	# 上中央の下: 目的・短い案内（ステージ石板の直下）
	room_message_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	room_message_label.offset_left = -360
	room_message_label.offset_right = 360
	room_message_label.offset_top = 136
	room_message_label.offset_bottom = 168
	room_message_label.add_theme_font_size_override("font_size", 20)

	# 旧ボスHP(ProgressBar)は使わない。Containerの表示フラグだけ互換のため残す。
	boss_name_label.hide()
	boss_hp_bar.hide()
	boss_health_container.offset_top = 0
	boss_health_container.offset_bottom = 0

	_build_controls_guide()

	if _is_touch:
		# 画面下は仮想スティックと操作ボタン。HUDは上段へ寄せる。
		_skill_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_skill_panel.offset_left = -394
		_skill_panel.offset_right = -24
		_skill_panel.offset_top = 128
		_skill_panel.offset_bottom = 226
		_upgrade_strip.offset_top = 300
		_upgrade_strip.offset_bottom = 360
		_upgrade_strip.offset_right = 24 + 400
		_skill_key_label.hide()

func _compact_panel(host: RetroPanel) -> void:
	for child in host.get_children():
		if child is Panel:
			PixelUIStyle.FrameArt.hide_old_ornament(child)
			child.add_theme_stylebox_override("panel", PixelUIStyle.FrameArt.box(true, 8, Color.WHITE))
	for side in ["left", "right", "top", "bottom"]:
		host.content.add_theme_constant_override("margin_" + side, 12)

func _add_tray_header(container: VBoxContainer, before: Control, text: String, accent: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", accent)
	container.add_child(label)
	container.move_child(label, before.get_index())

## トレイは中身がある時だけ表示し、見出しボタンで折りたためる。
func _refresh_tray_height() -> void:
	if _tray_container == null or _tray_backdrop == null:
		return
	var has_content := weapon_row.get_child_count() + item_row.get_child_count() + completed_skill_row.get_child_count() > 0
	if _tray_header:
		_tray_header.visible = has_content
		_tray_header.text = "武装・戦利品 ▾" if _tray_expanded else "武装・戦利品 ▸"
	var show_tray := has_content and _tray_expanded
	_tray_container.visible = show_tray
	_tray_backdrop.visible = show_tray
	if not show_tray:
		return
	var row_count := ceili(weapon_row.get_child_count() / 2.0)
	row_count += ceili(item_row.get_child_count() / 2.0)
	row_count += ceili(completed_skill_row.get_child_count() / 2.0)
	var limit := 500.0 if not _is_touch else 190.0
	var height := clampf(132.0 + row_count * (TRAY_CHIP_HEIGHT + 2.0), 132.0, limit)
	_tray_container.offset_bottom = _tray_container.offset_top + height
	_tray_backdrop.offset_bottom = _tray_container.offset_bottom + 10.0

# ============================================================
# PlayerPanel(左上): LVバッジ・職業名・主武器・HPゲージ・XPバー
# ============================================================

func _build_player_panel() -> void:
	var content := player_panel.content
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	content.add_child(root)

	var lv_row := HBoxContainer.new()
	lv_row.add_theme_constant_override("separation", 8)
	root.add_child(lv_row)
	var lv_box := PanelContainer.new()
	var lv_style := StyleBoxFlat.new()
	lv_style.bg_color = RetroHUDStyle.VOID_DEEP
	lv_style.border_color = RetroHUDStyle.BRONZE_LIGHT
	lv_style.set_border_width_all(1)
	lv_style.set_corner_radius_all(0)
	lv_style.content_margin_left = 8.0
	lv_style.content_margin_right = 8.0
	lv_style.content_margin_top = 1.0
	lv_style.content_margin_bottom = 1.0
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
	_weapon_name_label = Label.new()
	_weapon_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon_name_label.clip_text = true
	_weapon_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_weapon_name_label.add_theme_font_size_override("font_size", 18)
	_weapon_name_label.add_theme_color_override("font_color", RetroHUDStyle.PARCHMENT_DIM)
	_weapon_name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	lv_row.add_child(_weapon_name_label)

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	root.add_child(hp_row)
	var hp_label := Label.new()
	hp_label.text = "HP"
	hp_label.custom_minimum_size = Vector2(30, 0)
	hp_label.add_theme_font_size_override("font_size", 18)
	hp_label.add_theme_color_override("font_color", RetroHUDStyle.PARCHMENT_DIM)
	hp_row.add_child(hp_label)
	_hp_gauge = ProgressBar.new()
	_hp_gauge.custom_minimum_size = Vector2(150, 16)
	_hp_gauge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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

	# XPはHPの直下。画面最下端の細い線はやめる。
	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 8)
	root.add_child(xp_row)
	var xp_label := Label.new()
	xp_label.text = "XP"
	xp_label.custom_minimum_size = Vector2(30, 0)
	xp_label.add_theme_font_size_override("font_size", 18)
	xp_label.add_theme_color_override("font_color", RetroHUDStyle.PARCHMENT_DIM)
	xp_row.add_child(xp_label)
	exp_bar.reparent(xp_row)
	exp_bar.custom_minimum_size = Vector2(0, 10)
	exp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	exp_bar.tooltip_text = "経験値。満たすとレベルアップ"
	exp_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	exp_bar.add_theme_stylebox_override("background", RetroHUDStyle.track_style())
	exp_bar.add_theme_stylebox_override("fill", RetroHUDStyle.segment_style(RetroHUDStyle.IAI_TEAL_LIGHT))

	RetroHUDStyle.apply_font(root)

## 主武器名（装備中の武器、無ければ職業の素の攻撃）と取得済み強化を更新する。
func _refresh_loadout() -> void:
	if _weapon_manager == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	if _weapon_name_label:
		var equipped := player.equipment_component.get_equipped("weapon") if player else null
		var main_name := equipped.display_name if equipped else "素手"
		_weapon_name_label.text = main_name
		_weapon_name_label.tooltip_text = "主武器: %s" % main_name
	_refresh_upgrade_strip(player)

func _refresh_upgrade_strip(player: Player) -> void:
	if _upgrade_strip == null:
		return
	for child in _upgrade_strip.get_children():
		child.queue_free()
	if player == null or player.upgrades_component == null:
		_upgrade_strip.hide()
		return
	var any := false
	for id in survival_ids_with_arcana(player):
		var rank: int = player.upgrades_component.get_survival_rank(id)
		if rank <= 0:
			continue
		var upgrade: UpgradeData = DataLoader.upgrades.get(id)
		if upgrade == null:
			continue
		_upgrade_strip.add_child(_build_upgrade_chip(upgrade, rank))
		any = true
	_upgrade_strip.visible = any

## 秘技（所持中のもの）を先頭に、戦闘強化をその後ろに並べる。
func survival_ids_with_arcana(player: Player) -> Array[String]:
	var ids: Array[String] = []
	for key in player.upgrades_component.survival_upgrade_counts.keys():
		if String(key).begins_with("arcana_"):
			ids.append(String(key))
	ids.append_array(SURVIVAL_UPGRADE_IDS)
	return ids

## 取得済み強化1つぶんの小さな石板：アイコンと段階ピップ（上限なしの強撃は回数）。
func _build_upgrade_chip(upgrade: UpgradeData, rank: int) -> Control:
	var chip := PanelContainer.new()
	var is_arcana := upgrade.category == "arcana"
	var style := PixelUIStyle.badge_style(Color("ff9a5c") if is_arcana else PixelUIStyle.JEWEL_DARK, Color("2a1a14") if is_arcana else Color("111c29"))
	style.set_content_margin_all(5)
	chip.add_theme_stylebox_override("panel", style)
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	var maximum := int(upgrade.effect_params.get("max_rank", 0))
	var stage_text := "Lv.%d / %d" % [rank, maximum] if maximum > 0 else "×%d" % rank
	chip.tooltip_text = "%s　%s\n%s" % [upgrade.display_name, stage_text, upgrade.description]
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(column)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(44, 44) if is_arcana else Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = load(upgrade.icon_path) as Texture2D if upgrade.icon_path != "" and ResourceLoader.exists(upgrade.icon_path) else preload("res://assets/ui/shop/weapon_icon.png")
	column.add_child(icon)
	if maximum > 0:
		var pips := RetroPipRow.build(maximum, rank, Color("ff9a5c") if is_arcana else RetroHUDStyle.IAI_TEAL_LIGHT)
		pips.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(pips)
	else:
		var count := Label.new()
		count.text = "×%d" % rank
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.add_theme_font_size_override("font_size", 18)
		count.add_theme_color_override("font_color", RetroHUDStyle.IAI_TEAL_LIGHT)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(count)
	RetroHUDStyle.apply_font(chip)
	return chip

# ============================================================
# 職業技パネル(右下): アイコン・クールダウンの影・キー・名前・状態・熟練ピップ
# ============================================================

func _build_skill_panel() -> void:
	_skill_panel = RetroPanel.new()
	_skill_panel.name = "SkillPanel"
	add_child(_skill_panel)
	_skill_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_skill_panel.offset_left = -394
	_skill_panel.offset_right = -24
	_skill_panel.offset_top = -122
	_skill_panel.offset_bottom = -24
	_compact_panel(_skill_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_skill_panel.content.add_child(row)

	var slot := Control.new()
	slot.custom_minimum_size = Vector2(62, 62)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(slot)
	var slot_frame := Panel.new()
	slot_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot_frame.add_theme_stylebox_override("panel", RetroHUDStyle.track_style(RetroHUDStyle.BRONZE, RetroHUDStyle.VOID_DEEP))
	slot_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(slot_frame)
	_skill_icon_rect = TextureRect.new()
	_skill_icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_skill_icon_rect.offset_left = 5
	_skill_icon_rect.offset_top = 5
	_skill_icon_rect.offset_right = -5
	_skill_icon_rect.offset_bottom = -5
	_skill_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_skill_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_skill_icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_skill_icon_rect.texture = _load_active_skill_icon()
	_skill_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(_skill_icon_rect)
	# クールダウンは下から満ちる影。残り時間の割合だけ影が残る。
	_skill_shade = ColorRect.new()
	_skill_shade.color = Color(0.02, 0.04, 0.06, 0.72)
	_skill_shade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_skill_shade.offset_left = 1
	_skill_shade.offset_right = -1
	_skill_shade.offset_bottom = -1
	_skill_shade.offset_top = -1
	_skill_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(_skill_shade)
	_skill_key_label = Label.new()
	_skill_key_label.text = "L"
	_skill_key_label.add_theme_font_size_override("font_size", 18)
	_skill_key_label.add_theme_color_override("font_color", RetroHUDStyle.BRONZE_LIGHT)
	var key_style := PixelUIStyle.badge_style(RetroHUDStyle.BRONZE_DARK, RetroHUDStyle.VOID_DEEP)
	key_style.content_margin_left = 6
	key_style.content_margin_right = 6
	key_style.content_margin_top = 0
	key_style.content_margin_bottom = 0
	key_style.shadow_size = 0
	_skill_key_label.add_theme_stylebox_override("normal", key_style)
	_skill_key_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_skill_key_label.offset_left = -6
	_skill_key_label.offset_top = -8
	_skill_key_label.offset_right = 18
	_skill_key_label.offset_bottom = 16
	_skill_key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(_skill_key_label)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 3)
	row.add_child(column)
	_skill_name_label = Label.new()
	_skill_name_label.add_theme_font_size_override("font_size", 20)
	_skill_name_label.clip_text = true
	_skill_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_skill_name_label)
	_skill_state_label = Label.new()
	_skill_state_label.add_theme_font_size_override("font_size", 18)
	_skill_state_label.add_theme_color_override("font_color", RetroHUDStyle.IAI_TEAL_LIGHT)
	column.add_child(_skill_state_label)
	_iai_pips_wrap = Control.new()
	_iai_pips_wrap.custom_minimum_size = Vector2(0, 16)
	_iai_pips_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_iai_pips_wrap)
	_refresh_iai_pips()
	_refresh_skill_caption()
	RetroHUDStyle.apply_font(_skill_panel)

func _load_active_skill_icon() -> Texture2D:
	var character_id := GameManager.selected_character_id
	var path := "res://assets/ui/icons/battle_skills/talents/swordsman_root.png" if character_id == "swordsman" else "res://assets/ui/icons/battle_skills/upgrades/class_%s_lv2.png" % character_id
	return load(path) as Texture2D if ResourceLoader.exists(path) else preload("res://assets/ui/shop/weapon_icon.png")

func _refresh_iai_pips() -> void:
	if _iai_pips_wrap == null:
		return
	for child in _iai_pips_wrap.get_children():
		child.queue_free()
	_iai_pips_wrap.add_child(RetroPipRow.build(IAI_PIP_COUNT, _ability_level, RetroHUDStyle.IAI_TEAL_LIGHT))

func _refresh_skill_caption() -> void:
	if _skill_name_label == null:
		return
	var cooling := _skill_cooldown_remaining > 0.01
	_skill_name_label.text = _skill_display_name if _skill_display_name != "" else "職業技"
	_skill_state_label.text = "あと %.1f秒" % _skill_cooldown_remaining if cooling else "使用可能"
	_skill_state_label.add_theme_color_override("font_color", RetroHUDStyle.PARCHMENT_DIM if cooling else RetroHUDStyle.IAI_TEAL_LIGHT)
	if _skill_shade:
		var ratio := clampf(_skill_cooldown_remaining / maxf(_skill_cooldown_total, 0.01), 0.0, 1.0) if cooling else 0.0
		_skill_shade.visible = ratio > 0.0
		_skill_shade.offset_top = -1.0 - floorf(60.0 * ratio)
	if _skill_icon_rect:
		_skill_icon_rect.modulate = Color(0.62, 0.62, 0.66, 1.0) if cooling else Color.WHITE

func _on_class_ability_level_changed(new_level: int) -> void:
	set_ability_stage(new_level)

## 職業スキルの熟練度(ability_level)を技パネルのピップで表示する
## (キャラクターの経験値ゲージ(set_experience())とは完全に別の概念・別のデータ)。
func set_ability_stage(ability_level: int) -> void:
	_ability_level = ability_level
	_refresh_iai_pips()

func _on_skill_configured(display_name: String, _icon_text: String, cooldown: float, _color: Color) -> void:
	_skill_display_name = display_name
	if "/" in _skill_display_name:
		_skill_display_name = _skill_display_name.get_slice("/", 1).strip_edges()
	_skill_cooldown_total = cooldown
	_on_skill_cooldown_changed(0.0, cooldown)

func _on_skill_cooldown_changed(remaining: float, total: float) -> void:
	_skill_cooldown_remaining = remaining
	_skill_cooldown_total = total
	_refresh_skill_caption()

func _on_skill_activated() -> void:
	if _skill_panel == null:
		return
	_skill_panel.pivot_offset = _skill_panel.size
	_skill_panel.scale = Vector2(0.97, 0.97)
	var tween := create_tween()
	tween.tween_property(_skill_panel, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK)

func _on_skill_became_ready() -> void:
	if _skill_state_label == null:
		return
	var tween := create_tween()
	tween.tween_property(_skill_state_label, "modulate", Color(1.8, 1.8, 1.8, 1.0), 0.12)
	tween.tween_property(_skill_state_label, "modulate", Color.WHITE, 0.35)

# ============================================================
# 上中央のステージ石板: 時計・終盤ボスまでの予告ゲージ → ボス戦ではボス名とHP
# ============================================================

func _build_stage_panel() -> void:
	_stage_panel = RetroPanel.new()
	_stage_panel.name = "StagePanel"
	add_child(_stage_panel)
	move_child(_stage_panel, 0)
	_stage_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_stage_panel.offset_left = -280
	_stage_panel.offset_right = 280
	_stage_panel.offset_top = 12
	_stage_panel.offset_bottom = 128
	_compact_panel(_stage_panel)
	for side in ["top", "bottom"]:
		_stage_panel.content.add_theme_constant_override("margin_" + side, 8)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_panel.content.add_child(column)

	# 1行目: ステージ名・撃破数（ボス戦ではボス名と経過）。既存のRichTextLabelを移す。
	room_status_label.reparent(column)
	room_status_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	room_status_label.custom_minimum_size = Vector2(0, 28)
	room_status_label.fit_content = true
	room_status_label.scroll_active = false
	room_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room_status_label.add_theme_font_size_override("normal_font_size", 20)

	# 2行目: 大きな時計
	_clock_row = HBoxContainer.new()
	_clock_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_clock_row.add_theme_constant_override("separation", 10)
	_clock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_clock_row)
	_clock_prefix_label = Label.new()
	_clock_prefix_label.text = "ボスまで"
	_clock_prefix_label.add_theme_font_size_override("font_size", 18)
	_clock_prefix_label.add_theme_color_override("font_color", RetroHUDStyle.PARCHMENT_DIM)
	_clock_prefix_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clock_row.add_child(_clock_prefix_label)
	_clock_label = Label.new()
	_clock_label.text = "4:00"
	_clock_label.add_theme_font_size_override("font_size", 34)
	_clock_label.add_theme_color_override("font_color", RetroHUDStyle.BRONZE_LIGHT)
	_clock_row.add_child(_clock_label)

	# 2行目（ボス戦）: ボスHPの20分割ゲージ
	_boss_hp_wrap = Control.new()
	_boss_hp_wrap.custom_minimum_size = Vector2(0, 18)
	_boss_hp_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_hp_wrap.visible = false
	column.add_child(_boss_hp_wrap)
	_boss_hp_gauge = RetroSegmentGauge.new()
	_boss_hp_gauge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_boss_hp_wrap.add_child(_boss_hp_gauge)
	_boss_hp_gauge.configure(BOSS_SEGMENT_COUNT, RetroHUDStyle.HP_RED_LIGHT, RetroHUDStyle.VOID, true)

	# 3行目: 終盤ボスまでの進行（既存のBossGaugeWrapを移す）
	boss_gauge_wrap.reparent(column)
	boss_gauge_wrap.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	boss_gauge_wrap.custom_minimum_size = Vector2(0, 10)
	boss_gauge_wrap.visible = true

func _build_boss_gauge() -> void:
	_boss_gauge = RetroSegmentGauge.new()
	_boss_gauge.set_anchors_preset(Control.PRESET_FULL_RECT)
	boss_gauge_wrap.add_child(_boss_gauge)
	_boss_gauge.configure(BOSS_SEGMENT_COUNT, RetroHUDStyle.BRONZE_LIGHT, RetroHUDStyle.VOID, false)

func _set_stage_mode(boss_mode: bool) -> void:
	if _clock_row:
		_clock_row.visible = not boss_mode
	if _boss_hp_wrap:
		_boss_hp_wrap.visible = boss_mode
	if boss_gauge_wrap:
		boss_gauge_wrap.visible = not boss_mode
	# ボス戦は2段（名前・HP）なので石板を低くし、余白を残さない。
	if _stage_panel:
		_stage_panel.offset_bottom = 90 if boss_mode else 128

func _format_clock(seconds: int) -> String:
	seconds = maxi(seconds, 0)
	return "%d:%02d" % [seconds / 60, seconds % 60]

## BossSpawnerがボスを出現させたときに呼ぶ。石板の中段をボスHPゲージへ切り替える。
func show_boss_health(display_name: String, current: float, max_hp: float) -> void:
	boss_health_container.visible = true
	_boss_display_name = display_name
	boss_name_label.text = display_name
	boss_hp_bar.max_value = max_hp
	boss_hp_bar.value = current
	_set_stage_mode(true)
	if _boss_hp_gauge:
		_boss_hp_gauge.set_value(current, max_hp)
	if not GameManager.survival_mode_active:
		room_status_label.text = "[center][color=#ff9a8f][b]ボス[/b][/color]　%s[/center]" % _bare_boss_name()

## BossSpawnerは「最終ボス　名前」の形で渡してくる。見出しの色分けは石板側で行うので、
## 接頭辞を外した名前だけを使う。
func _bare_boss_name() -> String:
	if _boss_display_name == "":
		return "終盤のボス"
	var pieces := _boss_display_name.split("　", false)
	if pieces.size() >= 2 and pieces[0] in ["最終ボス", "ボス"]:
		return "　".join(pieces.slice(1))
	return _boss_display_name

func update_boss_health(current: float, max_hp: float) -> void:
	boss_hp_bar.max_value = max_hp
	boss_hp_bar.value = current
	if _boss_hp_gauge:
		_boss_hp_gauge.set_value(current, max_hp)

func hide_boss_health() -> void:
	boss_health_container.visible = false
	_boss_display_name = ""
	_set_stage_mode(false)

## MapRunControllerが0.25秒ごとに呼ぶ。時計と文言はここでだけ組み立てる。
func set_survival_status(map_name: String, elapsed: float, duration: float, kills: int, phase: String, boss_phase: bool = false) -> void:
	var left := maxi(ceili(duration - elapsed), 0)
	var fight_time := maxi(int(elapsed - duration), 0)
	room_status_label.visible = true
	if GameManager.survival_completed:
		_set_stage_mode(false)
		room_status_label.text = "[center]%s　・　[color=#d6c29d][b]撃破成功[/b][/color]　・　撃破 %d[/center]" % [map_name, kills]
		_clock_prefix_label.text = "討伐時間"
		_clock_label.text = _format_clock(int(elapsed))
		if _boss_gauge: _boss_gauge.set_value(duration, duration)
	elif boss_phase:
		_set_stage_mode(true)
		room_status_label.text = "[center][color=#ff9a8f][b]最終ボス[/b][/color]　%s　ボス戦 %s　撃破 %d[/center]" % [_bare_boss_name(), _format_clock(fight_time), kills]
	else:
		_set_stage_mode(false)
		room_status_label.text = "[center]%s　・　撃破 %d[/center]" % [map_name, kills]
		_clock_prefix_label.text = "ボスまで"
		_clock_label.text = _format_clock(left)
		_clock_label.add_theme_color_override("font_color", RetroHUDStyle.HP_RED_LIGHT if left <= 30 else RetroHUDStyle.BRONZE_LIGHT)
		if _boss_gauge: _boss_gauge.set_value(minf(elapsed, duration), duration)
	room_message_label.text = ""
	_update_controls_guide(elapsed)

## 旧MAP進行（Developer Test Lab用）。時計の代わりに撃破数を石板へ出す。
func set_map_status(map_index: int, total_maps: int, map_name: String, elapsed: float, fallback_seconds: float, kills: int, required_kills: int, boss_ready: bool, objective: String = "") -> void:
	var fallback_left := maxi(int(ceil(fallback_seconds - elapsed)), 0)
	var map_line := "MAP [color=#%s][b]%d / %d[/b][/color] ・ %s" % [RetroHUDStyle.BRONZE_LIGHT.to_html(false), map_index, total_maps, map_name]
	if total_maps > 3:
		map_line = "深度 [color=#%s][b]%d / %d層[/b][/color] ・ %s" % [RetroHUDStyle.BRONZE_LIGHT.to_html(false), map_index, total_maps, map_name]
	var boss_line: String
	if boss_ready:
		boss_line = "[color=#%s]封印解除！ ボス門へ[/color]" % RetroHUDStyle.BRONZE_LIGHT.to_html(false)
	else:
		boss_line = "封印解除 [color=#%s]%d / %d[/color] ・ 時間解放まで [color=#%s]%s[/color]" % [
			RetroHUDStyle.BOSS_PURPLE_LIGHT.to_html(false), mini(kills, required_kills), required_kills,
			RetroHUDStyle.HP_RED_LIGHT.to_html(false), _format_clock(fallback_left),
		]
	if not objective.is_empty(): boss_line = objective
	room_status_label.text = "[center]%s\n%s[/center]" % [map_line, boss_line]
	room_message_label.text = ""
	if _clock_row: _clock_row.visible = false
	if boss_health_container.visible:
		return
	boss_gauge_wrap.visible = true
	if _boss_gauge:
		_boss_gauge.set_value(mini(kills, required_kills), required_kills)

func set_room_message(message: String) -> void:
	room_message_label.text = message

func set_exploration_status(map_index: int, map_name: String, region: String, objective: String, visited: int, total: int, floor_index: int = 1, floors_per_map: int = 20) -> void:
	room_status_label.text = "[center]MAP %d / 3 ・ 地下%d / %d層 ・ %s\n%s ・ %s  [M][/center]" % [map_index, floor_index, floors_per_map, map_name, region, objective]
	if _clock_row: _clock_row.visible = false
	if not boss_health_container.visible:
		boss_gauge_wrap.visible = false

# ============================================================
# 操作案内(左下、PCのみ): 開始20秒で畳み、小さな札のホバー／押下で再表示
# ============================================================

func _build_controls_guide() -> void:
	_guide_full = Label.new()
	_guide_full.name = "ControlsGuide"
	_guide_full.text = "K 回避　L 技　J 反撃　E 調べる\nC 所持品　T 天賦図　M 地図　Esc 停止"
	add_child(_guide_full)
	_guide_full.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_guide_full.offset_left = 24
	_guide_full.offset_right = 524
	_guide_full.offset_top = -96
	_guide_full.offset_bottom = -28
	_guide_full.add_theme_font_size_override("font_size", 18)
	_guide_full.add_theme_stylebox_override("normal", PixelUIStyle.badge_style(PixelUIStyle.STONE_DARK, Color("0d1622")))
	_guide_full.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide_chip = Button.new()
	_guide_chip.name = "ControlsGuideChip"
	_guide_chip.text = "操作一覧"
	_guide_chip.tooltip_text = "操作キーの一覧を表示"
	_guide_chip.focus_mode = Control.FOCUS_NONE
	add_child(_guide_chip)
	_guide_chip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_guide_chip.offset_left = 24
	_guide_chip.offset_right = 164
	_guide_chip.offset_top = -62
	_guide_chip.offset_bottom = -24
	_guide_chip.add_theme_font_size_override("font_size", 18)
	PixelUIStyle.apply_button(_guide_chip)
	_guide_chip.visible = false
	_guide_chip.mouse_entered.connect(func(): if _guide_collapsed: _guide_full.visible = true)
	_guide_chip.mouse_exited.connect(func(): if _guide_collapsed and not _guide_pinned: _guide_full.visible = false)
	_guide_chip.pressed.connect(func():
		_guide_pinned = not _guide_pinned
		_guide_full.visible = _guide_pinned or not _guide_collapsed
	)
	if _is_touch:
		_guide_full.hide()
		_guide_chip.hide()

func _update_controls_guide(elapsed: float) -> void:
	if _guide_full and not _guide_full.has_meta("survival_text"):
		# 5分サバイバルは地図なし。天賦図は内容がある職業だけ（D3）。
		var line2 := "C 所持品　T 天賦図　Esc 停止" if GameManager.selected_character_id == "swordsman" else "C 所持品　Esc 停止"
		_guide_full.text = "K 回避　L 技　E 調べる
%s" % line2
		_guide_full.set_meta("survival_text", true)
	if _is_touch or _guide_full == null or _guide_collapsed:
		return
	if elapsed < GUIDE_COLLAPSE_SECONDS:
		return
	_guide_collapsed = true
	_guide_chip.visible = true
	var tween := create_tween()
	tween.tween_property(_guide_full, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func():
		_guide_full.visible = _guide_pinned
		_guide_full.modulate.a = 1.0
	)

# ============================================================
# 金貨・HP・XP
# ============================================================

func _on_run_started() -> void:
	gold_label.visible = GameManager.map_mode_active
	_on_run_gold_changed(GameManager.run_gold, 0, "run_started")

func _on_run_gold_changed(current_gold: int, _delta: int, _source: String) -> void:
	if gold_label:
		gold_label.text = "%d G" % maxi(current_gold, 0)

func set_health(current: float, max_hp: float) -> void:
	if _hp_gauge:
		_hp_gauge.max_value = maxf(max_hp, 1.0)
		_hp_gauge.value = current
	if _hp_value_label:
		_hp_value_label.text = "%d/%d" % [int(round(current)), int(round(max_hp))]

## 経験値ゲージ。scenes/game.gdがExperienceComponent.exp_changed/leveled_upを購読して呼ぶ。
func set_experience(current_exp: int, exp_to_next_level: int, level: int) -> void:
	if _lv_badge_label:
		_lv_badge_label.text = "LV %d" % level
	exp_bar.max_value = maxf(exp_to_next_level, 1)
	exp_bar.value = current_exp

# ============================================================
# 入手通知・中央告知・コンボ
# ============================================================

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
		_loot_toast.offset_top = -160.0
		_loot_toast.offset_bottom = -126.0
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
## ボス出現を伝える。
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

# ============================================================
# 武装・戦利品トレイ（右上）。中身がある時だけ表示する。
# ============================================================

## 所持武器トレイ。WeaponManagerComponentが保持する完成武器（遺物武器）を一覧表示する。
func _refresh_weapon_tray() -> void:
	for child in weapon_row.get_children():
		child.queue_free()
	if _weapon_manager == null:
		_refresh_tray_height.call_deferred()
		return
	for instance in _weapon_manager.get_weapon_instances():
		weapon_row.add_child(_build_weapon_icon(instance))
	_refresh_tray_height.call_deferred()
	_refresh_loadout()

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
	popup.offset_top = 176.0
	popup.offset_bottom = 216.0
	popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	popup.modulate = Color(1.0, 0.9, 0.4, 0.0)
	add_child(popup)
	RetroHUDStyle.apply_font(popup)
	var tween := create_tween()
	tween.tween_property(popup, "modulate:a", 1.0, 0.25)
	tween.tween_interval(1.8)
	tween.tween_property(popup, "modulate:a", 0.0, 0.6)
	tween.finished.connect(popup.queue_free)
