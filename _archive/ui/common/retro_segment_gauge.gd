class_name RetroSegmentGauge
extends Control
## 桝目状(セグメント)ゲージの再利用部品(HP10分割・ボス撃破カウント20分割などで共用)。
## 値の計算(現在値/最大値)は呼び出し側(既存のset_health()等)が持ったまま、
## set_value()に渡すだけでよい。表示ロジック(何マス塗るか)はここに閉じる。
##
## 1マスごとに「Glow(発光、埋まっている時だけ表示)」+「Fill(実体、埋/空の色)」の
## 2枚のColorRectを持たせる方式(RetroPanelの四隅鋲と同じ、入れ子矩形の考え方)。
## こうすることでゲージ全体の幅を跨いだピクセル計算が不要になり、マス数やゲージ幅が
## 変わっても常に正しく動く。

const GLOW_BLEED := 2.0

var _segments: Array[Dictionary] = [] # {glow: ColorRect, fill: ColorRect, tween: Tween}
var _track: Panel
var _row: HBoxContainer
var _segment_count := 10
var _filled_color := Color.WHITE
var _empty_color := Color.WHITE
var _pulse_enabled := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track = Panel.new()
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.set_anchors_preset(Control.PRESET_FULL_RECT)
	_track.add_theme_stylebox_override("panel", RetroHUDStyle.track_style())
	add_child(_track)

	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_row.offset_left = 3.0
	_row.offset_top = 3.0
	_row.offset_right = -3.0
	_row.offset_bottom = -3.0
	_row.add_theme_constant_override("separation", 1)
	add_child(_row)

	if _segment_count > 0:
		_rebuild_segments()

## count: マス数。filled_color/empty_color: 塗り/空の色。glow_color省略時はfilled_colorを使う。
## pulse: trueならボスゲージのように塗り済みマスがゆっくり明滅する(1.8秒周期)。
func configure(count: int, filled_color: Color, empty_color: Color = RetroHUDStyle.VOID, pulse: bool = false) -> void:
	_segment_count = maxi(count, 1)
	_filled_color = filled_color
	_empty_color = empty_color
	_pulse_enabled = pulse
	if is_inside_tree():
		_rebuild_segments()

func _rebuild_segments() -> void:
	for child in _row.get_children():
		child.queue_free()
	_segments.clear()
	for i in _segment_count:
		var slot := Control.new()
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row.add_child(slot)

		var glow := ColorRect.new()
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.set_anchors_preset(Control.PRESET_FULL_RECT)
		glow.offset_left = -GLOW_BLEED
		glow.offset_top = -GLOW_BLEED
		glow.offset_right = GLOW_BLEED
		glow.offset_bottom = GLOW_BLEED
		glow.color = Color(_filled_color.r, _filled_color.g, _filled_color.b, 0.55)
		glow.visible = false
		slot.add_child(glow)

		var fill := ColorRect.new()
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.set_anchors_preset(Control.PRESET_FULL_RECT)
		fill.color = _empty_color
		slot.add_child(fill)

		_segments.append({"glow": glow, "fill": fill, "tween": null})

## current/max_valueから塗りマス数を算出して反映する。既存のHP/撃破カウント計算式には
## 一切触れず、結果の2値を受け取るだけ(0マス目から順に埋める、四捨五入ではなく
## 「到達した分だけ」floorで塗ることでゲージが実際の割合を超えて見えないようにする)。
func set_value(current: float, max_value: float) -> void:
	var ratio: float = clampf(current / maxf(max_value, 0.0001), 0.0, 1.0)
	var filled_count: int = int(floor(ratio * _segment_count + 0.0001))
	if is_equal_approx(ratio, 1.0):
		filled_count = _segment_count
	set_filled_count(filled_count)

func set_filled_count(filled_count: int) -> void:
	filled_count = clampi(filled_count, 0, _segments.size())
	for i in _segments.size():
		var seg: Dictionary = _segments[i]
		var filled: bool = i < filled_count
		var fill: ColorRect = seg["fill"]
		var glow: ColorRect = seg["glow"]
		fill.color = _filled_color if filled else _empty_color
		glow.visible = filled
		_update_pulse(seg, filled)

func _update_pulse(seg: Dictionary, filled: bool) -> void:
	if not _pulse_enabled:
		return
	var tween: Tween = seg["tween"]
	if filled and (tween == null or not tween.is_valid()):
		var fill: ColorRect = seg["fill"]
		var glow: ColorRect = seg["glow"]
		fill.modulate = Color(1, 1, 1, 1)
		glow.modulate = Color(1, 1, 1, 1)
		var new_tween := create_tween().set_loops()
		new_tween.set_parallel(true)
		new_tween.tween_property(fill, "modulate", Color(1.35, 1.35, 1.35, 1.0), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		new_tween.tween_property(glow, "modulate", Color(1.35, 1.35, 1.35, 1.0), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		new_tween.chain().tween_property(fill, "modulate", Color(1, 1, 1, 1), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		new_tween.parallel().tween_property(glow, "modulate", Color(1, 1, 1, 1), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		seg["tween"] = new_tween
	elif not filled and tween != null and tween.is_valid():
		tween.kill()
		seg["tween"] = null
		(seg["fill"] as ColorRect).modulate = Color(1, 1, 1, 1)
		(seg["glow"] as ColorRect).modulate = Color(1, 1, 1, 1)
