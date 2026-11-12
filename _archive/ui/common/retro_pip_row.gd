class_name RetroPipRow
extends RefCounted
## 居合ゲージ用「ピップ(個別の縁取り四角)」表示。既存のAbilityStageDots(5段階の丸印)と
## 同じ「到達済み/未到達をN個並べる」考え方を踏襲しつつ、レトロHUDの意匠(bronze枠+
## 到達分はteal発光)に合わせて別実装にしてある。データ元は既存のset_ability_stage()と
## 同じability_level(WeaponManagerComponent.get_class_ability_level())で、ロジックは変えない。

const PIP_SIZE := 14.0
const GLOW_BLEED := 1.0

## filled_count個ぶんを塗った状態のHBoxContainerを新規に組み立てて返す
## (AbilityStageDots.build()と同じく、呼び出し側は子を全部差し替える運用)。
static func build(total: int, filled_count: int, on_color: Color, border_color: Color = RetroHUDStyle.BRONZE) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in total:
		row.add_child(_build_pip(i < filled_count, on_color, border_color))
	return row

static func _build_pip(on: bool, on_color: Color, border_color: Color) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(PIP_SIZE, PIP_SIZE)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if on:
		var glow := ColorRect.new()
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.set_anchors_preset(Control.PRESET_FULL_RECT)
		glow.offset_left = -GLOW_BLEED
		glow.offset_top = -GLOW_BLEED
		glow.offset_right = GLOW_BLEED
		glow.offset_bottom = GLOW_BLEED
		glow.color = Color(on_color.r, on_color.g, on_color.b, 0.5)
		wrap.add_child(glow)

	var pip := Panel.new()
	pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pip.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = on_color if on else RetroHUDStyle.VOID_DEEP
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	pip.add_theme_stylebox_override("panel", style)
	wrap.add_child(pip)
	return wrap
