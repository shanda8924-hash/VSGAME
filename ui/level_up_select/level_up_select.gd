extends CanvasLayer
class_name LevelUpSelect
signal option_selected(choice_id: String)
const SLOT_COUNT := 3
const MELEE_PATTERN_IDS := ["melee_arc","wide_cleave","self_pulse","piercing_thrust","charge_dash"]
const RANGED_PATTERN_IDS := ["spread_shot", "homing_bolt", "single_shot"]
const FrameArt := preload("res://ui/common/relic_frame_art.gd")
const UpgradePreview := preload("res://ui/level_up_select/upgrade_preview.gd")
## 色は強化の「種類」だけを表す(ショップの分類色と同じ: 汎用=青、職業/武器=金)。
## 枠には使わず種類名・段階ピップ・数値の強調にだけ使う。選択中のカードだけを
## 青緑の枠と光で示し、選んでいないカードが目立たないようにする(仕様書40.1)。
const COMBAT_COLOR := Color("79d7e8")
const CLASS_COLOR := Color("f2c14e")
## 秘技（新しく増える自動発動の大技）は橙。戦闘強化・職業技と一目で分ける。
const ARCANA_COLOR := Color("ff9a5c")
## 秘技の所持枠。
const ARCANA_SLOTS := 2
const SELECTED_COLOR := Color("8fe0d6")
const CARD_SIZE := Vector2(362, 450)
@onready var eyebrow: Label = $CenterContainer/Panel/Margin/VBox/Eyebrow
@onready var step_title: Label = $CenterContainer/Panel/Margin/VBox/StepTitle
@onready var grid_container: GridContainer = $CenterContainer/Panel/Margin/VBox/GridContainer
@onready var confirm_button: Button = $CenterContainer/Panel/Margin/VBox/Confirm
var _last_choice_ids: Array[String] = []
var _chosen: Array[UpgradeData] = []
var _selected := -1

func _ready() -> void:
	visible = false
	$CenterContainer.theme = PixelUIStyle.shared_theme()
	$CenterContainer/Panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	PixelUIStyle.apply_major_panel($CenterContainer/Panel, PixelUIStyle.BORDER_HOVER)
	PixelUIStyle.add_ornament($CenterContainer/Panel/Margin/VBox/Seal, "emblem")
	PixelUIStyle.apply_button(confirm_button, PixelUIStyle.JEWEL)
	confirm_button.pressed.connect(confirm_selection)
	EventBus.player_leveled_up.connect(_on_leveled_up)

func _on_leveled_up(new_level: int) -> void:
	GameManager.request_modal(_open.bind(new_level))

func _open(new_level: int = 0) -> void:
	GameManager.open_modal()
	visible = true
	var actor := get_tree().get_first_node_in_group("player") as Player
	eyebrow.text = "Lv.%d に到達　・　戦闘時間は停止中" % (new_level if new_level > 0 else (actor.experience_component.level if actor else 1))
	var upgrades := _get_compatible_upgrades()
	var chosen: Array[UpgradeData] = []
	var rest: Array[UpgradeData] = []
	for upgrade in upgrades:
		if upgrade.effect_type == "class_school_select" and chosen.size() < SLOT_COUNT:
			chosen.append(upgrade)
		else: rest.append(upgrade)
	# 秘技を1つも持っていない間は、毎回1枚は秘技を混ぜる（最初の数回で必ず手に入る）。
	if actor and actor.upgrades_component.get_arcana_count() == 0 and chosen.size() < SLOT_COUNT:
		var arcana_pool: Array[UpgradeData] = []
		for upgrade in rest:
			if upgrade.category == "arcana": arcana_pool.append(upgrade)
		if not arcana_pool.is_empty():
			var first_arcana: UpgradeData = arcana_pool.pick_random()
			chosen.append(first_arcana)
			rest.erase(first_arcana)
	while chosen.size() < SLOT_COUNT and not rest.is_empty():
		var picked := _take_weighted_upgrade(rest)
		if picked == null: break
		chosen.append(picked)
		rest.erase(picked)
	_show_choices(chosen)

func _show_choices(chosen: Array[UpgradeData]) -> void:
	for child in grid_container.get_children():
		grid_container.remove_child(child)
		child.queue_free()
	_chosen = chosen
	_selected = -1
	_last_choice_ids.clear()
	confirm_button.disabled = true
	confirm_button.text = "強化を選択してください"
	for upgrade in chosen:
		_last_choice_ids.append(upgrade.id)
		grid_container.add_child(_build_choice_button(upgrade))
	if grid_container.get_child_count()>0:
		(grid_container.get_child(0) as Button).grab_focus.call_deferred()

## 持っている秘技は最大段階まで、新しい秘技は枠（2つ）が空いている時だけ出す。
func _can_offer_arcana(upgrade: UpgradeData) -> bool:
	var actor := get_tree().get_first_node_in_group("player") as Player
	if actor == null: return false
	var rank := actor.upgrades_component.get_survival_rank(upgrade.id)
	if rank > 0:
		return rank < int(upgrade.effect_params.get("max_rank", 5))
	return actor.upgrades_component.get_arcana_count() < ARCANA_SLOTS

func _can_offer_survival(upgrade: UpgradeData) -> bool:
	var actor := get_tree().get_first_node_in_group("player") as Player
	if actor == null: return false
	var maximum := int(upgrade.effect_params.get("max_rank",0))
	if maximum > 0 and actor.upgrades_component.get_survival_rank(upgrade.id) >= maximum: return false
	if bool(upgrade.effect_params.get("requires_projectile",false)):
		var pattern: String = actor.weapon_manager._character_data.attack_pattern_id
		return pattern in ["spread_shot","homing_bolt","single_shot"] or (actor.weapon_manager.equipment_attack.item != null and actor.weapon_manager.equipment_attack.kind in ["bow","magic"])
	return true

func _get_compatible_upgrades() -> Array[UpgradeData]:
	var result: Array[UpgradeData] = []
	var character: CharacterData = DataLoader.characters.get(GameManager.selected_character_id)
	var combat_category := "melee" if character and character.attack_pattern_id in MELEE_PATTERN_IDS else "ranged"
	var character_id := character.id if character else ""
	var current_ability_level := _get_current_ability_level()
	var current_school := _get_current_school()
	var usable_state_effects := _get_usable_state_effects()
	for upgrade in DataLoader.get_all_upgrades():
		if GameManager.survival_mode_active and upgrade.class_character_id == "":
			if upgrade.category == "survival" and _can_offer_survival(upgrade): result.append(upgrade)
			elif upgrade.category == "arcana" and _can_offer_arcana(upgrade): result.append(upgrade)
			continue
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
		# 状態異常カードは「現在の職業が付与する状態」のものだけを候補にする。
		# 付与しない状態のカードは効果が永久にゼロになるため出さない(仕様書36.7)。
		# 効果を失った旧属性カードもJSONを残したまま抽選から除外する。
		if upgrade.category.begins_with("element_"):
			if upgrade.effect_type in usable_state_effects:
				result.append(upgrade)
			continue
		if upgrade.category == "common" or upgrade.category == combat_category:
			result.append(upgrade)
	return result

func _take_weighted_upgrade(candidates: Array[UpgradeData]) -> UpgradeData:
	var weights: Array[float] = []
	var total := 0.0
	for upgrade in candidates:
		var weight := _upgrade_weight(upgrade)
		weights.append(weight)
		total += weight
	if total <= 0.0:
		return null
	var roll := randf() * total
	for index in candidates.size():
		roll -= weights[index]
		if roll <= 0.0:
			return candidates[index]
	return candidates.back()

func _upgrade_weight(upgrade: UpgradeData) -> float:
	if upgrade.category == "arcana":
		# 秘技は戦闘強化より出やすくする。育てている秘技はさらに出やすい。
		var arcana_actor := get_tree().get_first_node_in_group("player") as Player
		return 2.6 if arcana_actor and arcana_actor.upgrades_component.get_survival_rank(upgrade.id) > 0 else 2.0
	if upgrade.category == "survival":
		var actor := get_tree().get_first_node_in_group("player") as Player
		return 1.5 / (1.0 + 0.25 * actor.upgrades_component.get_survival_rank(upgrade.id)) if actor else 1.0
	if upgrade.class_character_id != "":
		return 2.0
	if upgrade.category.begins_with("element_"):
		var player := get_tree().get_first_node_in_group("player")
		var component := player.get_node_or_null("PlayerUpgradesComponent") as PlayerUpgradesComponent if player else null
		var acquired := component.get_state_upgrade_count(upgrade.effect_type) if component else 0
		# 候補に残るのは現在の職業が付与する状態のカードのみ(1〜2枚)。
		# 枚数が絞られたぶん、重みは控えめにして他の候補を圧迫しないようにする。
		return 1.5 / (1.0 + 0.7 * acquired)
	return 1.0

func debug_get_last_choice_ids() -> Array[String]:
	return _last_choice_ids.duplicate()

## 現在の職業が付与する状態異常に対応する強化カードのeffect_type一覧。
## 職業固有攻撃パターンを持たない場合は空(=状態異常カードを出さない)。
func _get_usable_state_effects() -> Array:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return []
	var weapon_manager: WeaponManagerComponent = player.get_node_or_null("WeaponManagerComponent")
	if weapon_manager == null:
		return []
	var state_id := weapon_manager.get_applied_status_id()
	return PlayerUpgradesComponent.UPGRADE_EFFECTS_BY_STATE.get(state_id, [])

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



## 比較プレビューの種類。戦闘強化はデータのeffect_params.previewをそのまま使う。
## 職業技は段階ごとの効果が職業で異なるため、架空の動きを描かず"class"(静止)にする。
## 以前は説明文の単語から推測していたため、内容と無関係な動きが出ていた。
func _preview_kind(upgrade: UpgradeData) -> String:
	if upgrade.category in ["survival", "arcana"]:
		return String(upgrade.effect_params.get("preview", "power"))
	return "class" if upgrade.class_character_id != "" else "static"

func _build_choice_button(upgrade: UpgradeData) -> Button:
	var actor := get_tree().get_first_node_in_group("player") as Player
	var is_class := upgrade.class_character_id != ""
	var is_arcana := upgrade.category == "arcana"
	var accent := ARCANA_COLOR if is_arcana else (CLASS_COLOR if is_class else COMBAT_COLOR)
	var rank := _current_rank(upgrade, actor)
	var button := Button.new()
	button.custom_minimum_size = CARD_SIZE
	button.toggle_mode = true
	button.set_meta("upgrade_id", upgrade.id)
	button.tooltip_text = "%s\n%s" % [upgrade.display_name, upgrade.description]
	_apply_card_style(button)
	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	button.add_child(margin)
	margin.minimum_size_changed.connect(func(): button.custom_minimum_size.y = maxf(CARD_SIZE.y, margin.get_combined_minimum_size().y))
	var column := VBoxContainer.new()
	column.name = "VBoxContainer"
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var icon := _build_header(column, button, upgrade, accent)
	column.add_child(_build_rank_row(rank, _max_rank(upgrade), accent, is_class))
	var preview := UpgradePreview.new()
	preview.name = "UpgradePreview"
	preview.custom_minimum_size.y = 190
	_configure_preview(preview, upgrade, rank, accent, actor)
	preview.class_icon = icon.texture
	column.add_child(preview)
	var body := RichTextLabel.new()
	body.name = "Description"
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("normal_font_size", 20)
	body.text = _highlight_numbers(_card_description(upgrade, rank), accent.lightened(0.25))
	column.add_child(body)
	var selected := Label.new()
	selected.name = "SelectionLabel"
	selected.text = " "
	selected.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selected.add_theme_color_override("font_color", SELECTED_COLOR)
	selected.add_theme_font_size_override("font_size", 18)
	column.add_child(selected)
	_ignore_mouse(margin)
	button.pressed.connect(_select_choice.bind(upgrade))
	return button

## アイコン・種類・名前・フォーカスカーソル(ショップと同じ▶)。アイコンを返す。
func _build_header(column: VBoxContainer, button: Button, upgrade: UpgradeData, accent: Color) -> TextureRect:
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.texture = _load_upgrade_icon(upgrade, preload("res://assets/ui/shop/upgrade_icon.png"))
	header.add_child(icon)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.alignment = BoxContainer.ALIGNMENT_CENTER
	heading.add_theme_constant_override("separation", 0)
	header.add_child(heading)
	var category := Label.new()
	category.name = "Category"
	category.text = _category_text(upgrade)
	category.add_theme_font_size_override("font_size", 18)
	category.add_theme_color_override("font_color", accent)
	heading.add_child(category)
	var title := Label.new()
	title.name = "Title"
	title.text = upgrade.display_name
	title.add_theme_font_size_override("font_size", 26)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_child(title)
	var cursor := Label.new()
	cursor.name = "Cursor"
	cursor.text = "▶"
	cursor.add_theme_font_size_override("font_size", 18)
	cursor.add_theme_color_override("font_color", PixelUIStyle.BORDER_HOVER)
	cursor.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cursor.modulate.a = 0.0
	header.add_child(cursor)
	button.focus_entered.connect(func(): cursor.modulate.a = 1.0)
	button.focus_exited.connect(func(): cursor.modulate.a = 0.0)
	return icon

## 段階ピップ。取得済みは灰、今回増える1段だけ種類の色、未到達は空枠。
## 上限が無い強化(強撃)はピップを出さず数字だけ見せる。
func _build_rank_row(rank: int, max_rank: int, accent: Color, is_class: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "RankRow"
	row.add_theme_constant_override("separation", 5)
	for index in max_rank:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(14, 14)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var box := StyleBoxFlat.new()
		box.anti_aliasing = false
		box.set_border_width_all(1)
		if index < rank:
			box.bg_color = Color("8d96a3")
			box.border_color = Color("b9c0ca")
		elif index == rank:
			box.bg_color = accent
			box.border_color = accent.lightened(0.45)
		else:
			box.bg_color = Color("161a22")
			box.border_color = Color("4a4f5c")
		pip.add_theme_stylebox_override("panel", box)
		row.add_child(pip)
	var text := Label.new()
	text.name = "RankText"
	text.add_theme_font_size_override("font_size", 18)
	text.add_theme_color_override("font_color", PixelUIStyle.TEXT_MUTED)
	var limit := " / %d" % max_rank if max_rank > 0 else ""
	if is_class:
		text.text = "  段階 %d → %d%s" % [rank, rank + 1, limit]
	elif rank == 0:
		text.text = "  新規 Lv.1%s" % limit
	else:
		text.text = "  Lv.%d → Lv.%d%s" % [rank, rank + 1, limit]
	row.add_child(text)
	return row

## 秘技は段階ごとに何が増えるかが違うので、次の段階の説明文を出す。
func _card_description(upgrade: UpgradeData, rank: int) -> String:
	if upgrade.category == "arcana":
		var lines: Array = upgrade.effect_params.get("level_lines", [])
		if not lines.is_empty():
			return String(lines[clampi(rank, 0, lines.size() - 1)])
	return upgrade.description

func _configure_preview(preview: Control, upgrade: UpgradeData, rank: int, accent: Color, actor: Player) -> void:
	preview.set("kind", _preview_kind(upgrade))
	preview.set("rank", rank)
	preview.set("accent", accent)
	if upgrade.category == "arcana":
		var sheet_path := String(upgrade.effect_params.get("vfx_sheet", ""))
		preview.set("arcana_sheet", load(sheet_path) as Texture2D if ResourceLoader.exists(sheet_path) else null)
		preview.set("arcana_counts", upgrade.effect_params.get("strike_counts", [1]))
		preview.set("arcana_unit", String(upgrade.effect_params.get("unit", "")))
	var character: CharacterData = actor.weapon_manager._character_data if actor else null
	if character == null:
		return
	preview.set("attack_shape", _attack_shape(character.attack_pattern_id))
	preview.set("base_half_angle", float(character.attack_pattern_params.get("arc_half_angle_degrees", 55.0)))
	preview.set("base_interval", character.attack_interval)
	var projectiles := 1
	if actor.weapon_manager.equipment_attack.item == null:
		projectiles = int(character.attack_pattern_params.get("projectile_count", 1))
		if character.attack_pattern_id == "spread_shot" and _get_current_ability_level() >= 2:
			projectiles += 1
	preview.set("base_projectiles", projectiles)

## 職業の通常攻撃の形。比較プレビューの「現在」の攻撃をこれで描く。
func _attack_shape(pattern: String) -> String:
	if pattern in RANGED_PATTERN_IDS: return "shot"
	if pattern in ["piercing_thrust", "charge_dash"]: return "thrust"
	if pattern in ["self_pulse", "holy_pulse_heal"]: return "pulse"
	return "arc"

func _current_rank(upgrade: UpgradeData, actor: Player) -> int:
	if upgrade.class_character_id != "":
		return _get_current_ability_level()
	if actor and upgrade.category in ["survival", "arcana"]:
		return actor.upgrades_component.get_survival_rank(upgrade.id)
	return 0

func _max_rank(upgrade: UpgradeData) -> int:
	if upgrade.class_character_id != "":
		return AttackPatternBase.MAX_ABILITY_LEVEL
	if upgrade.category in ["survival", "arcana"]:
		return int(upgrade.effect_params.get("max_rank", 0))
	return 0

func _category_text(upgrade: UpgradeData) -> String:
	if upgrade.effect_type == "class_school_select":
		return "流派の選択"
	if upgrade.class_character_id != "":
		return "職業技"
	if upgrade.category == "arcana":
		var arcana_actor := get_tree().get_first_node_in_group("player") as Player
		var owned := arcana_actor != null and arcana_actor.upgrades_component.get_survival_rank(upgrade.id) > 0
		return "秘技" if owned else "秘技　NEW!"
	return "戦闘強化" if upgrade.category == "survival" else "強化"

## 説明文の数値(18%・0.18秒・1体など)だけを種類の色で強調する。
static func _highlight_numbers(text: String, color: Color) -> String:
	var safe := text.replace("[", "[lb]")
	var regex := RegEx.create_from_string("[+\\-−]?[0-9]+(?:\\.[0-9]+)?(?:%|秒|体|本|倍|段階)?")
	return regex.sub(safe, "[color=#%s]$0[/color]" % color.to_html(false), true)

func _apply_card_style(button: Button) -> void:
	# フォーカス枠は共通スタイル、地の枠はショップ/宝物選択と同じ石枠。
	PixelUIStyle.apply_button(button, PixelUIStyle.BORDER_HOVER)
	button.add_theme_stylebox_override("normal", FrameArt.box(false, 0.0))
	button.add_theme_stylebox_override("hover", FrameArt.box(false, 0.0, Color(1.1, 1.12, 1.0)))
	var selected := StyleBoxFlat.new()
	selected.bg_color = Color("15282a")
	selected.border_color = SELECTED_COLOR
	selected.set_border_width_all(2)
	selected.shadow_color = Color(SELECTED_COLOR, 0.42)
	selected.shadow_size = 10
	selected.anti_aliasing = false
	button.add_theme_stylebox_override("pressed", selected)
	button.add_theme_stylebox_override("hover_pressed", selected)

func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control: _ignore_mouse(child)

func _load_upgrade_icon(upgrade: UpgradeData, fallback: Texture2D) -> Texture2D:
	return load(upgrade.icon_path) as Texture2D if ResourceLoader.exists(upgrade.icon_path) else fallback

func _select_choice(upgrade: UpgradeData) -> void:
	_selected = _chosen.find(upgrade)
	for index in grid_container.get_child_count():
		var button := grid_container.get_child(index) as Button
		button.button_pressed = index==_selected
		var label := button.get_node("MarginContainer/VBoxContainer/SelectionLabel") as Label
		label.text = "✓ 選択中" if index==_selected else " "
	confirm_button.disabled = false
	confirm_button.text = "「%s」を取得" % upgrade.display_name
	confirm_button.grab_focus()

func confirm_selection() -> void:
	if not visible or _selected<0 or _selected>=_chosen.size(): return
	_on_choice_pressed(_chosen[_selected])

func _on_choice_pressed(upgrade: UpgradeData) -> void:
	AudioManager.play_sfx("ui_click")
	var actor := get_tree().get_first_node_in_group("player") as Player
	if actor: actor.upgrades_component.apply_upgrade(upgrade)
	option_selected.emit(upgrade.id)
	visible = false
	GameManager.close_modal()
