extends Label
class_name DamageNumber
## ダメージ数値ポップアップ1個ぶんの見た目とアニメーションだけを担当する。
## DamageNumberManagerのプールに使い回される前提のため、再生のたびに
## play()で状態を初期化してからアニメーションを組み立て直す。

const NORMAL_COLOR := Color(0.95, 0.95, 0.95, 1.0)
const CRITICAL_COLOR := Color(1.0, 0.25, 0.2, 1.0)
const HEAL_COLOR := Color(0.3, 1.0, 0.45, 1.0)
const ELEMENT_COLORS := {
	"element_fire": Color(1.0, 0.38, 0.10, 1.0),
	"element_ice": Color(0.62, 0.92, 1.0, 1.0),
	"element_lightning": Color(0.72, 0.60, 1.0, 1.0),
	"element_light": Color(1.0, 0.92, 0.62, 1.0),
	"element_dark": Color(0.58, 0.18, 0.85, 1.0),
	"element_wind": Color(0.56, 0.96, 0.75, 1.0),
}
const NORMAL_FONT_SIZE := 19
const CRITICAL_FONT_SIZE := 26
const ELEMENT_FONT_SIZE := 16
const LIFETIME := 0.6

var _tween: Tween

func play(amount: float, at_position: Vector2, is_critical: bool) -> void:
	var color := CRITICAL_COLOR if is_critical else NORMAL_COLOR
	var font_size := CRITICAL_FONT_SIZE if is_critical else NORMAL_FONT_SIZE
	_play_popup(str(int(round(amount))), at_position, color, font_size, is_critical, 0.0)

func play_heal(amount: float, at_position: Vector2) -> void:
	_play_popup("+%d HP" % int(round(amount)), at_position, HEAL_COLOR, NORMAL_FONT_SIZE, false, 0.0)

func play_element(amount: float, at_position: Vector2, element_id: String, stack_level: int, chain_index: int) -> void:
	var color: Color = ELEMENT_COLORS.get(element_id, NORMAL_COLOR)
	var x_offset: float = float({"element_fire": -18.0, "element_ice": -6.0, "element_lightning": 6.0, "element_light": 18.0, "element_dark": -12.0}.get(element_id, 0.0))
	var y_offset := -10.0 - float(chain_index) * 3.0
	var size := ELEMENT_FONT_SIZE + clampi(stack_level - 1, 0, 2)
	if chain_index > 0:
		size = maxi(size - 2, 14)
	_play_popup(str(int(round(amount))), at_position + Vector2(x_offset, y_offset), color, size, false, float(chain_index))

func _play_popup(display_text: String, at_position: Vector2, font_color: Color, font_size: int, is_critical: bool, chain_index: float) -> void:
	if _tween:
		_tween.kill()

	text = display_text
	global_position = at_position
	scale = Vector2.ONE
	rotation = 0.0
	modulate = Color(1, 1, 1, 1)
	visible = true

	var rise_distance := 28.0
	var horizontal_kick := randf_range(-6.0, 6.0)
	var rise_trans := Tween.TRANS_SINE
	add_theme_color_override("font_color", font_color)
	add_theme_font_size_override("font_size", font_size)
	add_theme_color_override("font_outline_color", Color(0.015, 0.02, 0.025, 1.0))
	add_theme_constant_override("outline_size", 3 if is_critical else 2)
	if is_critical:
		rise_distance = 46.0
		horizontal_kick = randf_range(-18.0, 18.0)
		rise_trans = Tween.TRANS_EXPO
		scale = Vector2(0.6, 0.6) # 強化: 小さく生まれて弾けるように等倍まで戻す
	elif chain_index > 0.0:
		rise_distance = 22.0
		horizontal_kick += chain_index * 2.0

	var target_position := global_position + Vector2(horizontal_kick, -rise_distance)
	# 数字を寿命途中から薄くせず、読み終わる最後の短時間だけPixel圧縮して消す。
	var fade_delay := LIFETIME * 0.82
	var fade_duration := LIFETIME - fade_delay

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "global_position", target_position, LIFETIME).set_ease(Tween.EASE_OUT).set_trans(rise_trans)
	_tween.tween_property(self, "modulate:a", 0.0, fade_duration).set_delay(fade_delay)
	_tween.tween_property(self, "scale:y", 0.18, fade_duration).set_delay(fade_delay)
	if is_critical:
		_tween.tween_property(self, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_callback(_on_finished)

func _process(_delta: float) -> void:
	if visible:
		# Tweenのsub-pixel移動を描画Frameごとに整数座標へ揃える。
		global_position = global_position.round()

func _on_finished() -> void:
	visible = false
