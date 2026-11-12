extends AnimatedSprite2D
class_name PixelSpriteVFX
## ゲームのエフェクトはすべてpixelfx（https://github.com/patch-gg/pixelfx、MIT）から書き出したシートで再生する。
## キー（hit_fire など）→ pixelfxのID・パレット・fps・倍率は data/vfx/pixelfx_effects.json、
## 書き出しは tools/pixelfx_import/build.mjs → assets/vfx/pixelfx/<key>.png / .json。
##
## 置き方：シートの pivot（pixelfxの原点。地面に立つ効果は足元）をノードの原点に合わせる。
## 大きさ：fit "fixed" は scale 倍（1ドット=scale px）、"size" は display_size に近い整数倍（1〜4）、
## "stretch_x" は横だけ display_size.x に伸ばし（線・連鎖・突き）、中心をノードに合わせる。
## 向き：pixelfxの効果は右向き。左向き（|angle|>90°）は上下が逆さにならないよう左右反転して回す。
## 時間：シート本来の長さ ÷ speed。一発物は最後 tail_fade の割合で薄くして消える。looped は親が消すまで繰り返す。

const ASSET_DIRECTORY := "res://assets/vfx/pixelfx/"
const MAX_LIVE := 96
const MAX_SPAWNS_PER_FRAME := 32
## 呼び出し側の色（テーマ色・レア度色）はシートの配色を潰さない程度にだけ混ぜる。
const TINT_STRENGTH := 0.35
static var _meta_cache: Dictionary = {}
static var _frames_cache: Dictionary = {}
static var _missing_reported: Dictionary = {}
static var _live_count := 0
static var _spawn_frame := -1
static var _frame_spawns := 0

var pooled := false
## 常駐（床の柱・結界・浮遊武器の斬撃・弾の見た目）：同時数の上限と掃除グループに数えない。
var persistent := false
var ignore_time_scale := false
var active := false
var effect_key := ""
var _elapsed := 0.0
var _looped := false
var _counted := false
var _length := 0.3
var _fps := 15.0
var _count := 1
var _tail_fade := 0.0
var _base_alpha := 1.0

static func spawn(parent: Node, world_position: Vector2, effect_id: String, display_size: Vector2 = Vector2.ZERO, _duration: float = 0.0, angle: float = 0.0, tint: Color = Color.WHITE, looped: bool = false) -> PixelSpriteVFX:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	var current_frame := Engine.get_process_frames()
	if current_frame != _spawn_frame:
		_spawn_frame = current_frame
		_frame_spawns = 0
	# Cosmetic-only budget: callers must keep damage/status outside the spawn result.
	if _live_count >= MAX_LIVE or _frame_spawns >= MAX_SPAWNS_PER_FRAME:
		return null
	var effect := PixelSpriteVFX.new()
	if not effect.configure(effect_id, display_size, _duration, looped):
		effect.free()
		return null
	_frame_spawns += 1
	effect.set_angle(angle)
	effect.set_tint(tint)
	parent.add_child(effect)
	effect.play_once(world_position)
	return effect

## キーのメタ（json）。無ければ空。
static func meta_for(effect_id: String) -> Dictionary:
	if _meta_cache.has(effect_id):
		return _meta_cache[effect_id]
	var path := ASSET_DIRECTORY + effect_id + ".json"
	var meta: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			meta = parsed
	if meta.is_empty():
		_report_missing(effect_id, path)
	_meta_cache[effect_id] = meta
	return meta

static func has_effect(effect_id: String) -> bool:
	return not meta_for(effect_id).is_empty() and ResourceLoader.exists(ASSET_DIRECTORY + effect_id + ".png")

static func frames_for(effect_id: String) -> SpriteFrames:
	if _frames_cache.has(effect_id):
		return _frames_cache[effect_id] as SpriteFrames
	var meta := meta_for(effect_id)
	var path := ASSET_DIRECTORY + effect_id + ".png"
	if meta.is_empty() or not ResourceLoader.exists(path):
		_report_missing(effect_id, path)
		return null
	var texture := load(path) as Texture2D
	if texture == null:
		_report_missing(effect_id, path)
		return null
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("play")
	frames.set_animation_loop("play", bool(meta.get("loop", false)))
	frames.set_animation_speed("play", float(meta.get("fps", 15)) * float(meta.get("speed", 1.0)))
	for index in int(meta.get("count", 1)):
		frames.add_frame("play", frame_texture_from(texture, meta, index))
	_frames_cache[effect_id] = frames
	return frames

static func frame_texture_from(texture: Texture2D, meta: Dictionary, index: int) -> AtlasTexture:
	var size := frame_size_for_meta(meta)
	var columns := maxi(int(meta.get("columns", 1)), 1)
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(Vector2(index % columns, index / columns) * size, size)
	return atlas

## UIのプレビューなど、自前で描くとき用：index番目のコマ。
static func frame_texture(effect_id: String, index: int) -> Texture2D:
	var frames := frames_for(effect_id)
	if frames == null or frames.get_frame_count("play") == 0:
		return null
	return frames.get_frame_texture("play", clampi(index, 0, frames.get_frame_count("play") - 1))

static func frame_count(effect_id: String) -> int:
	return int(meta_for(effect_id).get("count", 0))

## シート1周の秒数（speed込み）。
static func length_for(effect_id: String) -> float:
	var meta := meta_for(effect_id)
	return float(meta.get("count", 1)) / maxf(float(meta.get("fps", 15)) * float(meta.get("speed", 1.0)), 0.01)

static func frame_size_for_meta(meta: Dictionary) -> Vector2:
	var size: Array = meta.get("frame_size", [64, 64])
	return Vector2(float(size[0]), float(size[1]))

static func frame_size_for(effect_id: String) -> Vector2:
	return frame_size_for_meta(meta_for(effect_id))

static func pivot_for(effect_id: String) -> Vector2:
	var pivot: Array = meta_for(effect_id).get("pivot", [0, 0])
	return Vector2(float(pivot[0]), float(pivot[1]))

## 表示倍率（1ドット＝何px）。fit "size" は display_size に近い整数倍。
static func scale_for(effect_id: String, display_size: Vector2) -> Vector2:
	var meta := meta_for(effect_id)
	var base := float(meta.get("scale", 2))
	var size := frame_size_for_meta(meta)
	match String(meta.get("fit", "fixed")):
		"size":
			if display_size == Vector2.ZERO:
				return Vector2.ONE * base
			var k := clampf(roundf(maxf(display_size.x, display_size.y) / maxf(size.x, size.y)), 1.0, 4.0)
			return Vector2.ONE * k
		"stretch_x":
			var sx := display_size.x / maxf(size.x, 1.0) if display_size.x > 0.0 else base
			return Vector2(maxf(sx, 0.05), base)
	return Vector2.ONE * base

static func _report_missing(effect_id: String, path: String) -> void:
	if not _missing_reported.has(effect_id):
		_missing_reported[effect_id] = true
		push_warning("PixelSpriteVFX asset unavailable: " + path)

func configure(effect_id: String, display_size: Vector2 = Vector2.ZERO, _duration: float = 0.0, looped: bool = false) -> bool:
	var frames := frames_for(effect_id)
	if frames == null:
		return false
	var meta := meta_for(effect_id)
	effect_key = effect_id
	sprite_frames = frames
	animation = "play"
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var size := frame_size_for_meta(meta)
	if String(meta.get("fit", "fixed")) == "stretch_x":
		offset = -size * 0.5
	else:
		offset = -pivot_for(effect_id)
	scale = scale_for(effect_id, display_size)
	_fps = float(meta.get("fps", 15)) * float(meta.get("speed", 1.0))
	_count = int(meta.get("count", 1))
	_length = float(_count) / maxf(_fps, 0.01)
	_looped = looped or bool(meta.get("loop", false))
	_tail_fade = 0.0 if _looped else clampf(float(meta.get("tail_fade", 0.0)), 0.0, 0.9)
	z_index = int(meta.get("z", 45))
	name = "PixelVFX_%s" % effect_id
	set_meta("pixel_vfx_id", effect_id)
	set_meta("pixel_vfx_texture", ASSET_DIRECTORY + effect_id + ".png")
	set_meta("pixel_vfx_source", String(meta.get("fx", "")))
	visible = false
	set_process(false)
	return true

## 右向きの効果を angle へ向ける。左向きは左右反転して上下を保つ。
func set_angle(angle: float) -> void:
	var a := wrapf(angle, -PI, PI)
	if absf(a) > PI * 0.5:
		scale.x = -absf(scale.x)
		rotation = a - PI if a > 0.0 else a + PI
	else:
		scale.x = absf(scale.x)
		rotation = a

func set_tint(tint: Color) -> void:
	_base_alpha = tint.a
	var mixed := Color.WHITE.lerp(Color(tint.r, tint.g, tint.b), TINT_STRENGTH)
	modulate = Color(mixed.r, mixed.g, mixed.b, tint.a)

## 常駐用に1つ作る（親へ add_child するのは呼び出し側）。
static func make_persistent(effect_id: String, display_size: Vector2 = Vector2.ZERO, looped: bool = false) -> PixelSpriteVFX:
	var effect := PixelSpriteVFX.new()
	effect.persistent = true
	effect.pooled = true
	if not effect.configure(effect_id, display_size, 0.0, looped):
		effect.free()
		return null
	return effect

func _ready() -> void:
	# 再生していない間は処理を止める（床の紋などの静止コマは毎フレーム動かさない）。
	set_process(active)
	if persistent:
		return
	_live_count += 1
	_counted = true
	if not pooled:
		add_to_group("transient_vfx")

func _exit_tree() -> void:
	if _counted:
		_live_count = maxi(_live_count - 1, 0)
		_counted = false

func play_once(world_position: Vector2) -> void:
	global_position = world_position
	_elapsed = 0.0
	frame = 0
	modulate.a = _base_alpha
	visible = true
	active = true
	set_process(true)

func get_length() -> float:
	return _length

func _process(delta: float) -> void:
	if not active:
		return
	_elapsed += delta / maxf(Engine.time_scale, 0.001) if ignore_time_scale else delta
	if _elapsed >= _length:
		if _looped:
			_elapsed = fmod(_elapsed, _length)
		else:
			active = false
			visible = false
			set_process(false)
			animation_finished.emit()
			if not pooled:
				queue_free()
			return
	frame = mini(int(_elapsed * _fps), _count - 1)
	if _tail_fade > 0.0:
		var t := _elapsed / _length
		var start := 1.0 - _tail_fade
		modulate.a = _base_alpha * (1.0 if t < start else clampf((1.0 - t) / _tail_fade, 0.0, 1.0))
