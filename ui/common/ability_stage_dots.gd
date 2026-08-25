class_name AbilityStageDots
extends RefCounted
## HUD(スキルアイコン付近)と天賦図パネルの両方で共通利用する、職業スキルの
## 熟練度(ability_level、systems/attack_patterns/AttackPatternBase参照)を
## 示す「5つの丸印」段階表示(基本形態+Lv.2〜Lv.5の計5段階)。
##
## 【重要】これはキャラクターの経験値(ExperienceComponent.current_exp/
## exp_to_next_level、HUDのなめらかなEXPバー)とは完全に別の概念・別のデータ
## (WeaponManagerComponent.get_class_ability_level())を参照する。見た目も
## EXPバーとは別の場所に配置し、同じバーに重ねたり色を似せたりしない。

const STAGE_COUNT := 5

## ability_level(1〜5)に応じて、到達済みの段は塗りつぶし・未到達は輪郭のみの
## 丸をSTAGE_COUNT個並べたHBoxContainerを返す。
static func build(ability_level: int, dot_size: float, filled_color: Color, empty_color: Color, border_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for stage in range(1, STAGE_COUNT + 1):
		var filled := ability_level >= stage
		row.add_child(_build_dot(dot_size, filled, filled_color, empty_color, border_color))
	return row

static func _build_dot(size: float, filled: bool, filled_color: Color, empty_color: Color, border_color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(size, size)
	var style := StyleBoxFlat.new()
	style.bg_color = filled_color if filled else empty_color
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	panel.add_theme_stylebox_override("panel", style)
	return panel
