extends CanvasLayer
class_name EquipmentScreen
## C / gamepad Yで開くキャラクター・装備画面。既存Inventory/EquipmentComponentを再利用する。

signal closed()

const FIXED_STATS := ["attack_power", "defense", "max_hp"]
const STAT_NAMES := {
	"attack_power":"攻撃力", "defense":"防御力", "max_hp":"最大HP", "move_speed":"移動速度",
	"attack_speed":"攻撃速度", "crit_rate":"クリティカル率", "crit_damage":"クリティカルダメージ"
}
const SLOT_NAMES := {"weapon":"武器", "head":"頭", "body":"胴", "arms":"腕", "legs":"脚", "accessory":"アクセサリー"}
const RARITY_NAMES := {
	"uncommon":"アンコモン", "rare":"レア", "epic":"エピック", "legendary":"レジェンダリー", "mythic":"ミシック"
}
const MODE_EQUIPMENT := "equipment"
const MODE_MERGE := "merge"

@onready var character_panel: PanelContainer = $Background/Margin/Main/Columns/CharacterPanel
@onready var character_name: Label = $Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/CharacterName
@onready var character_portrait: TextureRect = $Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/CharacterStage/Center/PortraitFrame/CharacterPortrait
@onready var left_slots: VBoxContainer = $Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/CharacterStage/LeftSlots
@onready var top_slot: VBoxContainer = $Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/CharacterStage/Center/TopSlot
@onready var bottom_slot: VBoxContainer = $Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/CharacterStage/Center/BottomSlot
@onready var right_slots: VBoxContainer = $Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/CharacterStage/RightSlots
@onready var stats: RichTextLabel = $Background/Margin/Main/Columns/CharacterPanel/Margin/VBox/Stats
@onready var inventory_title: Label = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/Title
@onready var equipment_tab_button: Button = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/ModeTabs/EquipmentTab
@onready var merge_tab_button: Button = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/ModeTabs/MergeTab
@onready var rarity_counts: Label = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/RarityCounts
@onready var material_slots: HBoxContainer = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/MaterialSlots
@onready var merge_notice: Label = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/MergeNotice
@onready var inventory_list: VBoxContainer = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/Scroll/InventoryList
@onready var comparison_title: Label = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/ComparisonTitle
@onready var comparison: RichTextLabel = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/Comparison
@onready var merge_title: Label = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/MergeTitle
@onready var merge_preview_row: HBoxContainer = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/MergePreviewRow
@onready var merge_preview_icon: TextureRect = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/MergePreviewRow/MergePreviewIcon
@onready var merge_preview: RichTextLabel = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/MergePreviewRow/MergePreview
@onready var equip_button: Button = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/Buttons/EquipButton
@onready var unequip_button: Button = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/Buttons/UnequipButton
@onready var merge_button: Button = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/Buttons/MergeButton
@onready var animation_hint: Label = $Background/Margin/Main/Columns/InventoryPanel/Margin/VBox/AnimationHint
@onready var merge_animation_layer: Control = $Background/MergeAnimationLayer

var _equipment: EquipmentComponent
var _selected: EquipmentData
var _is_open := false
var _mode := MODE_EQUIPMENT
var _merge_system := EquipmentMergeSystem.new()
var _merge_materials: Array[EquipmentData] = []
var _merge_result: EquipmentData
var _pending_merge_result: EquipmentData
var _merge_in_progress := false
var _has_completed_merge_animation := false
var _merge_animation_tween: Tween
var _material_slot_buttons: Array[Button] = []

func _ready() -> void:
	visible = false
	merge_animation_layer.visible = false
	PixelUIStyle.apply_tree(self)
	_material_slot_buttons = [
		material_slots.get_node("Slot1") as Button,
		material_slots.get_node("Slot2") as Button,
		material_slots.get_node("Slot3") as Button,
	]
	for index in _material_slot_buttons.size():
		_material_slot_buttons[index].pressed.connect(_remove_merge_material.bind(index))
	var player := get_tree().get_first_node_in_group("player")
	if player:
		_equipment = player.get_node_or_null("EquipmentComponent")
		if _equipment:
			_equipment.inventory_changed.connect(_refresh)
			_equipment.equipment_changed.connect(func(_slot, _item): _refresh())
	equipment_tab_button.pressed.connect(_set_mode.bind(MODE_EQUIPMENT))
	merge_tab_button.pressed.connect(_set_mode.bind(MODE_MERGE))
	equip_button.pressed.connect(_equip_selected)
	unequip_button.pressed.connect(_unequip_selected_slot)
	merge_button.pressed.connect(_merge_selected)
	_apply_mode_visibility()

func _process(_delta: float) -> void:
	if _merge_in_progress:
		return
	var toggle_pressed := Input.is_action_just_pressed("character_screen") or Input.is_action_just_pressed("equipment_menu")
	if _is_open and (toggle_pressed or Input.is_action_just_pressed("ui_cancel")):
		_close()
	elif toggle_pressed and GameManager.active_modal_count == 0 and GameManager.run_state == GameManager.RunState.PLAYING and _is_safe_timing():
		_open()

func _unhandled_input(event: InputEvent) -> void:
	if not _merge_in_progress or not _has_completed_merge_animation:
		return
	var skip_pressed := false
	if event is InputEventMouseButton:
		skip_pressed = (event as InputEventMouseButton).pressed
	skip_pressed = skip_pressed or event.is_action_pressed("ui_accept")
	if InputMap.has_action("interact"):
		skip_pressed = skip_pressed or event.is_action_pressed("interact")
	if not skip_pressed:
		return
	get_viewport().set_input_as_handled()
	_complete_merge_animation()

func is_open() -> bool:
	return _is_open

func _is_safe_timing() -> bool:
	if not GameManager.room_mode_active:
		return true
	var controller := get_parent().get_node_or_null("RoomRunController") as RoomRunController
	if controller == null:
		return false
	return controller.state in [RoomRunController.RoomState.CLEAR, RoomRunController.RoomState.REWARD, RoomRunController.RoomState.CHOOSING]

func _open() -> void:
	if _is_open:
		return
	_is_open = true
	GameManager.open_modal()
	_refresh()
	visible = true
	call_deferred("_focus_initial_control")

func _close() -> void:
	if not _is_open or _merge_in_progress:
		return
	_is_open = false
	visible = false
	GameManager.close_modal()
	closed.emit()

func _focus_initial_control() -> void:
	if not _is_open:
		return
	if _mode == MODE_MERGE:
		merge_tab_button.grab_focus()
	elif inventory_list.get_child_count() > 0:
		(inventory_list.get_child(0) as Control).grab_focus()
	else:
		equip_button.grab_focus()

func _set_mode(mode: String) -> void:
	if _merge_in_progress or mode not in [MODE_EQUIPMENT, MODE_MERGE]:
		return
	_mode = mode
	_refresh()
	call_deferred("_focus_initial_control")

func _refresh() -> void:
	if _equipment == null:
		return
	if not _merge_in_progress:
		_sync_merge_materials()
	_refresh_character()
	_refresh_slots()
	_clear(inventory_list)
	var items := _equipment.get_all_inventory()
	for item in items:
		inventory_list.add_child(_build_inventory_button(item))
	if _selected == null or _selected not in items:
		_selected = items[0] if not items.is_empty() else null
	_refresh_comparison()
	_refresh_rarity_counts()
	_refresh_merge_view()
	_apply_mode_visibility()

func _sync_merge_materials() -> void:
	var inventory := _equipment.get_all_inventory()
	for index in range(_merge_materials.size() - 1, -1, -1):
		if _merge_materials[index] not in inventory:
			_merge_materials.remove_at(index)

func _refresh_character() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	var data: CharacterData = DataLoader.characters.get(GameManager.selected_character_id)
	character_name.text = data.display_name if data else GameManager.selected_character_id
	var sprite := player.animated_sprite
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(sprite.animation):
		var frame_count := sprite.sprite_frames.get_frame_count(sprite.animation)
		if frame_count > 0:
			var frame_texture := sprite.sprite_frames.get_frame_texture(sprite.animation, mini(sprite.frame, frame_count - 1))
			character_portrait.texture = _crop_transparent_margin(frame_texture)
	var health := player.health_component
	var movement := player.movement_component
	var upgrades := player.upgrades_component
	var modifier := player.get_node_or_null("StatModifierComponent") as StatModifierComponent
	var base_attack := data.base_damage if data else 10.0
	var level_flat := modifier.get_damage_flat_bonus() if modifier else 0.0
	var flat_attack := base_attack + level_flat + _equipment.get_total_stat("attack_power")
	var final_attack := flat_attack * upgrades.damage_multiplier * upgrades.get_equipment_conditional_damage_multiplier()
	var base_crit := data.crit_chance if data else 0.0
	var crit_rate := base_crit + (modifier.get_crit_chance_bonus() if modifier else 0.0) + upgrades.crit_rate_bonus + upgrades.equipment_crit_rate_bonus
	var crit_damage := (data.crit_multiplier if data else 2.0) + upgrades.equipment_crit_damage_bonus
	var attack_speed_bonus := upgrades.attack_interval_multiplier + upgrades.equipment_attack_speed_bonus
	var move_speed := movement.base_speed * movement.bonus_speed_multiplier * movement.equipment_speed_multiplier
	stats.text = "[b]現在ステータス[/b]\nHP  %.0f / %.0f    攻撃力  %.1f    防御力  %.0f\n攻撃速度  +%.1f%%    移動速度  %.1f    クリティカル率  %.1f%%    クリティカルダメージ  %.1f%%" % [
		health.current_hp, health.max_hp, final_attack, _equipment.get_total_stat("defense"),
		attack_speed_bonus * 100.0, move_speed, crit_rate * 100.0, crit_damage * 100.0]

## SpriteFramesの各frameは透明余白を多く含む素材がある。元ピクセルを最近傍のまま
## 透明外周だけ切り出し、中央キャラクターをスロット間で十分な大きさに表示する。
func _crop_transparent_margin(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.01:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return texture
	var cropped := image.get_region(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))
	return ImageTexture.create_from_image(cropped)

func _refresh_slots() -> void:
	for container in [left_slots, top_slot, bottom_slot, right_slots]:
		_clear(container)
	left_slots.add_child(_build_slot_button("weapon"))
	left_slots.add_child(_build_slot_button("arms"))
	top_slot.add_child(_build_slot_button("head"))
	bottom_slot.add_child(_build_slot_button("legs"))
	right_slots.add_child(_build_slot_button("body"))
	right_slots.add_child(_build_slot_button("accessory"))

func _build_slot_button(slot: String) -> Button:
	var item := _equipment.get_equipped(slot)
	var button := Button.new()
	button.custom_minimum_size = Vector2(210, 78)
	button.text = "%s\n%s" % [SLOT_NAMES.get(slot, slot), item.display_name if item else "－ 空スロット －"]
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if item and item.icon_path != "" and ResourceLoader.exists(item.icon_path):
		button.icon = load(item.icon_path)
		button.expand_icon = true
	PixelUIStyle.apply_button(button, item.get_rarity_color() if item else Color(0.3, 0.3, 0.37))
	if item:
		button.add_theme_color_override("font_color", item.get_rarity_color())
	button.pressed.connect(func():
		if item:
			_selected = item
			_refresh_comparison()
	)
	return button

func _build_inventory_button(item: EquipmentData) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 62)
	var state_badges: Array[String] = []
	if _equipment.is_equipped(item):
		state_badges.append("装備中")
	if item.is_locked:
		state_badges.append("ロック")
	if item in _merge_materials:
		state_badges.append("素材選択中")
	var state_text := "  [%s]" % " / ".join(state_badges) if not state_badges.is_empty() else ""
	button.text = "%s  [%s]%s\n%s" % [item.display_name, item.get_slot_display_name(), state_text, RARITY_NAMES.get(item.rarity, item.rarity)]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if item.icon_path != "" and ResourceLoader.exists(item.icon_path):
		button.icon = load(item.icon_path)
		button.expand_icon = true
	PixelUIStyle.apply_button(button, item.get_rarity_color())
	button.add_theme_color_override("font_color", item.get_rarity_color())
	if _mode == MODE_MERGE:
		button.disabled = _merge_in_progress or item.is_locked or _equipment.is_equipped(item)
		if not _merge_materials.is_empty() and item.rarity != _merge_materials[0].rarity:
			button.modulate = Color(0.62, 0.62, 0.66, 0.72)
	button.pressed.connect(_on_inventory_item_pressed.bind(item))
	return button

func _on_inventory_item_pressed(item: EquipmentData) -> void:
	if _mode == MODE_MERGE:
		_toggle_merge_material(item)
		return
	_selected = item
	_refresh_comparison()

func _refresh_comparison() -> void:
	if _selected == null:
		comparison.text = "所持装備はありません"
		equip_button.disabled = true
		unequip_button.disabled = true
		return
	equip_button.disabled = false
	var current := _equipment.get_equipped(_selected.slot)
	unequip_button.disabled = current == null
	var current_name := current.display_name if current else "未装備"
	var lines: Array[String] = ["[b]現在: %s[/b]  →  [color=#%s][b]候補: %s[/b][/color]" % [current_name, _selected.get_rarity_color().to_html(false), _selected.display_name], RARITY_NAMES.get(_selected.rarity, _selected.rarity)]
	for stat_name in STAT_NAMES.keys():
		var before := current.get_stat(stat_name) if current else 0.0
		var after := _selected.get_stat(stat_name)
		if before == 0.0 and after == 0.0:
			continue
		var arrow := "↑" if after > before else ("↓" if after < before else "=")
		var color := "#65e878" if after > before else ("#ff6969" if after < before else "#cccccc")
		var scale := 1.0 if stat_name in FIXED_STATS else 100.0
		var suffix := "" if stat_name in FIXED_STATS else "%"
		lines.append("%s: +%.1f%s → +%.1f%s [color=%s]%s[/color]" % [STAT_NAMES[stat_name], before * scale, suffix, after * scale, suffix, color, arrow])
	if not _selected.special_effects.is_empty():
		for effect in _selected.special_effects:
			lines.append("[color=#ffd36a]特殊効果: %s[/color]" % _special_description(_selected, effect))
	comparison.text = "\n".join(lines)

func _refresh_rarity_counts() -> void:
	var counts := {"uncommon":0, "rare":0, "epic":0, "legendary":0, "mythic":0}
	for item in _equipment.get_all_inventory():
		if not item.is_locked and not _equipment.is_equipped(item):
			counts[item.rarity] = int(counts.get(item.rarity, 0)) + 1
	rarity_counts.text = "素材候補　アンコモン %d　レア %d　エピック %d　レジェンダリー %d　ミシック %d" % [
		counts.uncommon, counts.rare, counts.epic, counts.legendary, counts.mythic]

func _refresh_merge_view() -> void:
	_refresh_merge_slots()
	merge_preview_icon.texture = null
	if _merge_result != null:
		_show_merge_result(_merge_result)
	else:
		_show_merge_preview()
	var validation := _merge_system.get_merge_validation(_equipment, _merge_materials)
	var valid := bool(validation.get("valid", false)) and not _merge_in_progress
	merge_button.disabled = not valid
	merge_button.text = "合成中…" if _merge_in_progress else ("合成する" if valid else "素材を3個選択")
	if _merge_in_progress:
		merge_notice.text = "3つの装備を合成しています…"
		merge_notice.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35))
	elif _has_mixed_material_rarity():
		merge_notice.text = "素材3個のレアリティを統一してください"
		merge_notice.add_theme_color_override("font_color", Color(1.0, 0.42, 0.34))
	else:
		merge_notice.text = String(validation.get("reason", "素材を3個選択してください"))
		merge_notice.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35) if valid else Color(0.68, 0.68, 0.74))
	var accent := _merge_materials[0].get_rarity_color() if valid and not _merge_materials.is_empty() else Color(0.32, 0.36, 0.42)
	PixelUIStyle.apply_button(merge_button, accent)

func _refresh_merge_slots() -> void:
	for index in _material_slot_buttons.size():
		var button := _material_slot_buttons[index]
		button.icon = null
		if index >= _merge_materials.size():
			button.text = "素材 %d\n－ 空き －" % (index + 1)
			button.disabled = true
			PixelUIStyle.apply_button(button, Color(0.30, 0.34, 0.40))
			continue
		var item := _merge_materials[index]
		button.text = "素材 %d　%s\n%s" % [index + 1, RARITY_NAMES.get(item.rarity, item.rarity), item.display_name]
		button.disabled = _merge_in_progress
		if item.icon_path != "" and ResourceLoader.exists(item.icon_path):
			button.icon = load(item.icon_path)
			button.expand_icon = true
		PixelUIStyle.apply_button(button, item.get_rarity_color())

func _show_merge_preview() -> void:
	if _merge_materials.is_empty():
		merge_preview.text = "[b]合成プレビュー[/b]\n同じレアリティの装備を3個選択\n完成品は次レアリティの既存装備から1個生成"
		return
	var source_rarity := _merge_materials[0].rarity
	var next_rarity := _merge_system.get_next_rarity(source_rarity)
	if next_rarity == "":
		merge_preview.text = "[b]%s[/b]\n最高レアリティのため合成できません" % RARITY_NAMES.get(source_rarity, source_rarity)
		return
	var color := _rarity_color(next_rarity).to_html(false)
	merge_preview.text = "[b]%s ×3[/b]  →  [color=#%s][b]%s ×1[/b][/color]\n完成品の種類・部位・能力は合成完了時に確定" % [
		RARITY_NAMES.get(source_rarity, source_rarity), color, RARITY_NAMES.get(next_rarity, next_rarity)]

func _show_merge_result(result: EquipmentData) -> void:
	if result.icon_path != "" and ResourceLoader.exists(result.icon_path):
		merge_preview_icon.texture = load(result.icon_path)
	var current := _equipment.get_equipped(result.slot)
	var lines: Array[String] = [
		"[color=#%s][b]合成完了　%s[/b][/color]" % [result.get_rarity_color().to_html(false), result.display_name],
		"%s / %s　現在: %s" % [RARITY_NAMES.get(result.rarity, result.rarity), result.get_slot_display_name(), current.display_name if current else "未装備"],
	]
	for stat_name in result.stats:
		var before := current.get_stat(stat_name) if current else 0.0
		var after := result.get_stat(stat_name)
		var scale := 1.0 if stat_name in FIXED_STATS else 100.0
		var suffix := "" if stat_name in FIXED_STATS else "%"
		lines.append("%s  +%.1f%s → +%.1f%s" % [STAT_NAMES.get(stat_name, stat_name), before * scale, suffix, after * scale, suffix])
	for effect_id in result.special_effects:
		lines.append("[color=#ffd36a]%s[/color]" % _special_description(result, effect_id))
	merge_preview.text = "\n".join(lines)

func _apply_mode_visibility() -> void:
	var is_merge := _mode == MODE_MERGE
	inventory_title.text = "合成素材を選択" if is_merge else "ラン中の所持装備"
	rarity_counts.visible = is_merge
	material_slots.visible = is_merge
	merge_notice.visible = is_merge
	merge_title.visible = is_merge
	merge_preview_row.visible = is_merge
	animation_hint.visible = is_merge
	comparison_title.visible = not is_merge
	comparison.visible = not is_merge
	merge_button.visible = is_merge
	unequip_button.visible = not is_merge
	equip_button.visible = not is_merge or _merge_result != null
	equip_button.text = "完成装備を装備" if is_merge else "装備する"
	PixelUIStyle.apply_button(equipment_tab_button, Color(0.95, 0.75, 0.28) if not is_merge else Color(0.30, 0.36, 0.44))
	PixelUIStyle.apply_button(merge_tab_button, Color(0.95, 0.75, 0.28) if is_merge else Color(0.30, 0.36, 0.44))

func _toggle_merge_material(item: EquipmentData) -> void:
	if _merge_in_progress or item == null or item.is_locked or _equipment.is_equipped(item):
		return
	_merge_result = null
	if item in _merge_materials:
		_merge_materials.erase(item)
	elif _merge_materials.size() < EquipmentMergeSystem.MATERIAL_COUNT:
		_merge_materials.append(item)
	_refresh()

func _remove_merge_material(index: int) -> void:
	if _merge_in_progress or index < 0 or index >= _merge_materials.size():
		return
	_merge_result = null
	_merge_materials.remove_at(index)
	_refresh()

func _has_mixed_material_rarity() -> bool:
	if _merge_materials.size() < 2:
		return false
	var rarity := _merge_materials[0].rarity
	for item in _merge_materials:
		if item.rarity != rarity:
			return true
	return false

func _special_description(item: EquipmentData, effect_id: String) -> String:
	match effect_id:
		"kill_heal": return "命喰らい（敵撃破時HPを%.0f回復）" % item.get_special_value(effect_id, "heal_flat")
		"negate_hit": return "守護の残響（%.0f%%で被弾無効）" % (item.get_special_value(effect_id, "chance") * 100.0)
		"low_hp_power": return "窮地の力（HP%.0f%%以下で攻撃力+%.0f%%）" % [item.get_special_value(effect_id, "hp_threshold") * 100.0, item.get_special_value(effect_id, "damage_bonus") * 100.0]
		_: return effect_id

func _equip_selected() -> void:
	if _equipment and _selected:
		_equipment.equip(_selected)

func _unequip_selected_slot() -> void:
	if _equipment and _selected:
		_equipment.unequip(_selected.slot)

func _merge_selected() -> void:
	if _equipment == null or _merge_in_progress:
		return
	var validation := _merge_system.get_merge_validation(_equipment, _merge_materials)
	if not bool(validation.get("valid", false)):
		_refresh_merge_view()
		return
	var animation_sources := _capture_animation_sources()
	_merge_in_progress = true
	_pending_merge_result = null
	_refresh_merge_view()
	var result := _merge_system.merge_materials(_equipment, _merge_materials)
	if result == null:
		_merge_in_progress = false
		_refresh()
		return
	_pending_merge_result = result
	_play_merge_animation(result, animation_sources)

func _capture_animation_sources() -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	for index in _merge_materials.size():
		var button := _material_slot_buttons[index]
		var texture: Texture2D
		if _merge_materials[index].icon_path != "" and ResourceLoader.exists(_merge_materials[index].icon_path):
			texture = load(_merge_materials[index].icon_path)
		sources.append({"center": button.global_position + button.size * 0.5, "texture": texture})
	return sources

func _play_merge_animation(result: EquipmentData, sources: Array[Dictionary]) -> void:
	_clear(merge_animation_layer)
	merge_animation_layer.visible = true
	var target := merge_preview_icon.global_position + merge_preview_icon.size * 0.5
	var rarity_index := maxi(0, EquipmentMergeSystem.RARITY_ORDER.find(result.rarity))
	var accent := result.get_rarity_color()
	for index in sources.size():
		var ghost := TextureRect.new()
		ghost.custom_minimum_size = Vector2(58, 58)
		ghost.size = Vector2(58, 58)
		ghost.texture = sources[index].get("texture") as Texture2D
		ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ghost.pivot_offset = ghost.size * 0.5
		merge_animation_layer.add_child(ghost)
		ghost.global_position = Vector2(sources[index].get("center")) - ghost.size * 0.5
		var ghost_tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		ghost_tween.tween_property(ghost, "global_position", target - ghost.size * 0.5, 0.52).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		ghost_tween.parallel().tween_property(ghost, "scale", Vector2(0.38, 0.38), 0.52).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		ghost_tween.parallel().tween_property(ghost, "rotation", (-0.16 + index * 0.16), 0.52)
		ghost_tween.tween_property(ghost, "modulate", Color(accent.r, accent.g, accent.b, 0.0), 0.16)
	_merge_animation_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_merge_animation_tween.tween_interval(0.52)
	_merge_animation_tween.tween_callback(_spawn_merge_impact.bind(target, accent, rarity_index))
	_merge_animation_tween.tween_interval(0.68)
	_merge_animation_tween.tween_callback(_complete_merge_animation)

func _spawn_merge_impact(target: Vector2, accent: Color, rarity_index: int) -> void:
	AudioManager.play_sfx("level_up")
	var impact := ColorRect.new()
	impact.color = Color(accent.r, accent.g, accent.b, 0.95)
	impact.size = Vector2(12, 12)
	impact.pivot_offset = impact.size * 0.5
	merge_animation_layer.add_child(impact)
	impact.global_position = target - impact.size * 0.5
	var impact_tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	impact_tween.tween_property(impact, "scale", Vector2(4.0 + rarity_index * 0.55, 4.0 + rarity_index * 0.55), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	impact_tween.tween_property(impact, "modulate:a", 0.0, 0.16)
	impact_tween.tween_callback(impact.queue_free)

	var fragment_count := 9 + rarity_index * 3
	for index in fragment_count:
		var fragment := ColorRect.new()
		var pixel_size := 3.0 + float(index % 3)
		fragment.size = Vector2(pixel_size, pixel_size)
		fragment.color = accent.lightened(0.18 if index % 2 == 0 else 0.0)
		merge_animation_layer.add_child(fragment)
		fragment.global_position = target - fragment.size * 0.5
		var angle := TAU * float(index) / float(fragment_count) + 0.21 * float(index % 3)
		var distance := 34.0 + float(index % 4) * 10.0 + rarity_index * 5.0
		var destination := fragment.global_position + Vector2.from_angle(angle) * distance
		var fragment_tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		fragment_tween.tween_property(fragment, "global_position", destination, 0.34 + float(index % 3) * 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fragment_tween.parallel().tween_property(fragment, "modulate:a", 0.0, 0.42)
		fragment_tween.tween_callback(fragment.queue_free)

func _complete_merge_animation() -> void:
	if not _merge_in_progress:
		return
	if _merge_animation_tween and _merge_animation_tween.is_valid():
		_merge_animation_tween.kill()
	_merge_in_progress = false
	_has_completed_merge_animation = true
	_merge_result = _pending_merge_result
	_pending_merge_result = null
	_merge_materials.clear()
	if _merge_result:
		_selected = _merge_result
	_clear(merge_animation_layer)
	merge_animation_layer.visible = false
	_refresh()
	if _merge_result:
		equip_button.grab_focus()

func _rarity_color(rarity: String) -> Color:
	var probe := EquipmentData.new()
	probe.rarity = rarity
	return probe.get_rarity_color()

func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
