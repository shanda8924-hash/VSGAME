extends Node
class_name ScreenEffects
## 爽快感演出の中枢: 画面シェイク・ヒットストップ・スローモーション。
## quality_settingsを書き換えることで、低スペック端末向けに演出を軽量化できる。

var quality_settings := {
	"screen_shake_enabled": true,
	"particle_quality": "high", # low / medium / high
	"damage_numbers_enabled": true,
}
var _next_time_effect_id: int = 1
var _time_effects: Dictionary = {}
var _base_time_scale: float = 1.0
var _active_flash_layer: CanvasLayer = null

@onready var _camera: Camera2D = get_tree().get_first_node_in_group("main_camera")

func _ready() -> void:
	# DamageNumberManagerなど、シーンの別ブランチからも
	# NodePathを介さずquality_settingsへ辿れるようにグループへ登録しておく。
	add_to_group("screen_effects")

func _exit_tree() -> void:
	_time_effects.clear()
	if is_instance_valid(_active_flash_layer):
		_active_flash_layer.queue_free()
	_active_flash_layer = null
	Engine.time_scale = 1.0

func shake(strength: float, duration: float) -> void:
	if not quality_settings.get("screen_shake_enabled", true):
		return
	if _camera == null:
		return
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	tween.tween_method(_apply_shake, strength, 0.0, duration)

func _apply_shake(value: float) -> void:
	if _camera:
		_camera.offset = Vector2(randf_range(-value, value), randf_range(-value, value))

func hit_stop(duration: float) -> void:
	_start_time_effect(0.05, duration)

func slow_motion(scale: float, duration: float) -> void:
	_start_time_effect(clampf(scale, 0.05, 1.0), duration)

func _start_time_effect(scale: float, duration: float) -> void:
	if _time_effects.is_empty():
		_base_time_scale = Engine.time_scale
	var request_id := _next_time_effect_id
	_next_time_effect_id += 1
	_time_effects[request_id] = scale
	_apply_time_effects()
	await get_tree().create_timer(maxf(duration, 0.001), true, false, true).timeout
	_time_effects.erase(request_id)
	_apply_time_effects()

func _apply_time_effects() -> void:
	var resolved_scale := 1.0
	for value in _time_effects.values():
		resolved_scale = minf(resolved_scale, float(value))
	Engine.time_scale = _base_time_scale * resolved_scale

## Boss死亡・ROOM遷移で遅延中のHitStopやShakeが残らないよう、画面状態を
## 演出開始前の値へ即時復元する。遅れて戻るTimerは存在しないIDをeraseするだけになる。
func restore_runtime_state() -> void:
	_time_effects.clear()
	Engine.time_scale = _base_time_scale
	if is_instance_valid(_active_flash_layer):
		_active_flash_layer.queue_free()
	_active_flash_layer = null
	if _camera:
		_camera.offset = Vector2.ZERO

## 属性VFX(光属性の強化演出等)向けの短い画面フラッシュ。
## CanvasLayerを都度生成して最前面に重ね、フェードイン/アウト後に自ら破棄する。
func flash(color: Color, duration: float) -> void:
	# 同じFrameの複数Hitが全画面ColorRectを積み重ねない。
	if is_instance_valid(_active_flash_layer):
		return
	var layer := CanvasLayer.new()
	_active_flash_layer = layer
	layer.layer = 100
	layer.add_to_group("transient_vfx")
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color(color.r, color.g, color.b, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	# Boss報酬Modalはflash()を開始した同じSignal経路でSceneTreeをpauseする。
	# 通常Tweenのままだと最前面ColorRectが停止して画面を覆い続けるため、
	# 短時間の画面演出だけはpause/time_scaleに関係なく完走・解放させる。
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	# Pixel VFXの主形状を隠さない、短く低Alphaの節目演出に制限する。
	tween.tween_property(rect, "color:a", 0.16, duration * 0.25)
	tween.tween_property(rect, "color:a", 0.0, duration * 0.7)
	# NodeをLambdaへ直接captureすると、reset側が先に解放した場合にGodotが
	# callback本体へ入る前に「capture was freed」を報告する。Instance IDだけを
	# bindし、遅延完了とScene cleanupの競合を安全に収束させる。
	tween.finished.connect(_finish_flash.bind(layer.get_instance_id()))

func _finish_flash(layer_instance_id: int) -> void:
	var layer := instance_from_id(layer_instance_id) as CanvasLayer
	if is_instance_valid(_active_flash_layer) and _active_flash_layer.get_instance_id() == layer_instance_id:
		_active_flash_layer = null
	if is_instance_valid(layer):
		layer.queue_free()

## 超融合(3属性以上のフュージョン)専用の演出: 武器名を画面中央へ大きく
## カットイン風に表示してから消す。flash()と同じく、CanvasLayerを都度生成して
## 自ら破棄する(常設ノードを増やさない)。
func weapon_cut_in(weapon_name: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 101
	layer.add_to_group("transient_vfx")
	add_child(layer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)

	var label := Label.new()
	label.text = weapon_name
	label.add_theme_font_size_override("font_size", 64)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color(0.2, 0.08, 0.0, 1.0))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	label.scale = Vector2(0.6, 0.6)
	label.pivot_offset = Vector2.ZERO
	center.add_child(label)

	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	tween.tween_property(label, "modulate:a", 1.0, 0.15)
	tween.parallel().tween_property(label, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.3)
	tween.finished.connect(layer.queue_free)
