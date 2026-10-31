extends AnimatedSprite2D
class_name PixelSpriteVFX
## 生成済み6-frame PNGの共通再生器。形状変化は画像に持たせ、移動/Alpha Tweenはしない。
## SpriteFrames/TextureはID単位で共有し、実行時のImage読み戻しは行わない。
## コマ寸法＝シート高さ×(シート幅/6)。各シートは表示サイズの約1/2で描いてあり
## （1ドット≒ワールド2px、tools/vfx_unified）、表示サイズ/コマ寸法で伸縮する。

const FRAME_COUNT := 6
const MAX_LIVE := 96
const MAX_SPAWNS_PER_FRAME := 32
const ASSET_DIRECTORY := "res://assets/vfx/pixel/"
static var _frames_cache: Dictionary = {}
static var _frame_size_cache: Dictionary = {}
static var _missing_reported: Dictionary = {}
static var _live_count := 0
static var _spawn_frame := -1
static var _frame_spawns := 0

var pooled := false
var ignore_time_scale := false
var active := false
var _duration := 0.3
var _elapsed := 0.0
var _looped := false
var _counted := false

static func spawn(parent: Node, world_position: Vector2, effect_id: String, display_size: Vector2, duration: float = 0.3, angle: float = 0.0, tint: Color = Color.WHITE, looped: bool = false) -> PixelSpriteVFX:
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
	if not effect.configure(effect_id, display_size, duration, looped):
		effect.free()
		return null
	_frame_spawns += 1
	effect.rotation = angle
	effect.modulate = tint
	parent.add_child(effect)
	effect.play_once(world_position)
	return effect

func configure(effect_id: String, display_size: Vector2, duration: float = 0.3, looped: bool = false) -> bool:
	var frames := frames_for(effect_id)
	if frames == null:
		return false
	sprite_frames = frames
	animation = "play"
	scale = Vector2(maxf(display_size.x, 1.0), maxf(display_size.y, 1.0)) / frame_size_for(effect_id)
	_duration = maxf(duration, 0.01)
	_looped = looped
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 45
	name = "PixelVFX_%s" % effect_id
	set_meta("pixel_vfx_id", effect_id)
	set_meta("pixel_vfx_texture", ASSET_DIRECTORY + effect_id + ".png")
	visible = false
	set_process(false)
	return true

static func frames_for(effect_id: String) -> SpriteFrames:
	if _frames_cache.has(effect_id):
		return _frames_cache[effect_id] as SpriteFrames
	var path := ASSET_DIRECTORY + effect_id + ".png"
	if not ResourceLoader.exists(path):
		_report_missing(effect_id, path)
		return null
	var texture := load(path) as Texture2D
	if texture == null or texture.get_height() <= 0 or texture.get_width() % FRAME_COUNT != 0:
		_report_missing(effect_id, path + " (expected %d equal frames in a row)" % FRAME_COUNT)
		return null
	var frame_size := Vector2(texture.get_width() / float(FRAME_COUNT), texture.get_height())
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("play")
	frames.set_animation_loop("play", false)
	for index in FRAME_COUNT:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(Vector2(index * frame_size.x, 0), frame_size)
		frames.add_frame("play", atlas)
	_frames_cache[effect_id] = frames
	_frame_size_cache[effect_id] = frame_size
	return frames

static func frame_size_for(effect_id: String) -> Vector2:
	return _frame_size_cache.get(effect_id, Vector2(64, 64)) as Vector2

static func _report_missing(effect_id: String, path: String) -> void:
	if not _missing_reported.has(effect_id):
		_missing_reported[effect_id] = true
		push_warning("PixelSpriteVFX asset unavailable: " + path)

func _ready() -> void:
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
	visible = true
	active = true
	set_process(true)

func _process(delta: float) -> void:
	if not active:
		return
	_elapsed += delta / maxf(Engine.time_scale, 0.001) if ignore_time_scale else delta
	if _elapsed >= _duration:
		if _looped:
			_elapsed = fmod(_elapsed, _duration)
		else:
			active = false
			visible = false
			set_process(false)
			animation_finished.emit()
			if not pooled:
				queue_free()
			return
	frame = mini(int(_elapsed / _duration * FRAME_COUNT), FRAME_COUNT - 1)
