extends Node2D
class_name AttackVFXManager
## 通常攻撃開始と命中時のPixel Sprite Animationを実ゲームWorldへ生成する。

signal effect_spawned(effect_id: String, effect: AnimatedSprite2D)

const PATTERN_EFFECT_IDS := {
	"melee_arc": "attack_slash",
	"wide_cleave": "attack_slash",
	"charge_dash": "attack_slash",
	"piercing_thrust": "attack_projectile",
	"spread_shot": "attack_projectile",
	"homing_bolt": "attack_projectile",
	"self_pulse": "attack_pulse",
	"holy_pulse_heal": "attack_pulse",
	"summon_minion": "attack_pulse",
}

var _frames_cache: Dictionary = {}
var _opaque_height_cache: Dictionary = {}
var _player: Player
var _player_visual_height_cache: float = -1.0
## Debug/性能Harness用。Gameplay/VFX結果には影響せず、高頻度経路の呼び出しと
## 実際にTexture.get_image()へ到達した回数だけを記録する。
var _player_visual_height_call_count: int = 0
var _player_visual_height_image_read_count: int = 0

func _ready() -> void:
	add_to_group("attack_vfx_manager")
	if not EventBus.run_started.is_connected(_on_run_started):
		EventBus.run_started.connect(_on_run_started)
	call_deferred("_connect_player")

func _connect_player() -> void:
	var connected_player := get_tree().get_first_node_in_group("player") as Player
	if connected_player != _player:
		_player = connected_player
		_player_visual_height_cache = -1.0
	if _player == null or _player.weapon_manager == null:
		return
	if _player_visual_height_cache < 0.0:
		_player_visual_height_cache = _calculate_player_visual_height()
	if not _player.weapon_manager.attack_vfx_requested.is_connected(_on_attack_vfx_requested):
		_player.weapon_manager.attack_vfx_requested.connect(_on_attack_vfx_requested)

func _on_run_started() -> void:
	# Player Scene再生成やRun再開後のscaleを1回だけ取り直す。VFX生成側では
	# Texture/Imageへ触れず、この値を参照するだけにする。
	_player_visual_height_cache = -1.0
	call_deferred("_connect_player")

func _on_attack_vfx_requested(character_data: CharacterData, origin: Vector2, direction: Vector2) -> void:
	if character_data == null:
		return
	var effect_id: String = PATTERN_EFFECT_IDS.get(character_data.attack_pattern_id, "attack_projectile")
	var strength := 1.0
	if character_data.attack_pattern_id == "wide_cleave":
		strength = 1.35
	elif character_data.attack_pattern_id == "charge_dash":
		strength = 1.25
	# Melee collision, damage, timing, and character animation live in the attack
	# pattern. This detached crescent sprite was presentation-only.
	if effect_id == "attack_slash":
		return
	play_effect(effect_id, origin, direction, _theme_color(character_data.vfx_theme_id), strength)

func play_hit(position: Vector2, theme_id: String, is_critical: bool) -> void:
	var effect_id := "hit_critical" if is_critical else "hit_normal"
	var color := _theme_color(theme_id)
	if is_critical:
		color = color.lerp(Color.WHITE, 0.35)
	play_effect(effect_id, position, Vector2.RIGHT, color)
	# hit_criticalの6-frame Pixel Spriteが局所閃光も担う。半透明Polygonを重ねない。

func play_effect(effect_id: String, position: Vector2, direction: Vector2, color: Color, strength: float = 1.0) -> AnimatedSprite2D:
	var data: AttackVFXData = DataLoader.attack_vfx_effects.get(effect_id)
	if data == null or data.sprite_sheet == null:
		push_warning("AttackVFXManager: Effect IDを解決できません -> %s" % effect_id)
		return null
	var frames := _get_frames(data)
	if frames == null:
		return null
	var normalized_direction := direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	var player_height := _get_player_visual_height()
	var effect := AnimatedSprite2D.new()
	effect.name = "PixelVFX_%s" % effect_id
	effect.sprite_frames = frames
	effect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	effect.z_index = 45
	effect.modulate = color
	effect.global_position = position + normalized_direction * player_height * data.spawn_offset_ratio
	if data.directional:
		effect.rotation = normalized_direction.angle()
	var opaque_height := _get_opaque_height(data)
	var target_height := clampf(player_height * data.visual_ratio * strength, 14.0, 84.0)
	var visual_scale := target_height / maxf(opaque_height, 1.0)
	effect.scale = Vector2.ONE * visual_scale
	add_child(effect)
	effect.animation_finished.connect(effect.queue_free)
	effect.play("play")
	_get_tree_timer(data.lifetime + 0.1).timeout.connect(_free_weak_ref.bind(weakref(effect)))
	effect_spawned.emit(effect_id, effect)
	return effect

func _get_frames(data: AttackVFXData) -> SpriteFrames:
	if _frames_cache.has(data.id):
		return _frames_cache[data.id]
	var frame_height := data.sprite_sheet.get_height()
	if frame_height <= 0:
		return null
	var available_count: int = int(data.sprite_sheet.get_width() / frame_height)
	var count: int = mini(data.frame_count, available_count)
	if count <= 0:
		return null
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("play")
	frames.set_animation_loop("play", false)
	frames.set_animation_speed("play", data.fps)
	for index in count:
		var atlas := AtlasTexture.new()
		atlas.atlas = data.sprite_sheet
		atlas.region = Rect2(index * frame_height, 0, frame_height, frame_height)
		frames.add_frame("play", atlas)
	_frames_cache[data.id] = frames
	return frames

func _get_opaque_height(data: AttackVFXData) -> float:
	if _opaque_height_cache.has(data.id):
		return float(_opaque_height_cache[data.id])
	var image := data.sprite_sheet.get_image()
	var height := float(image.get_used_rect().size.y) if image else float(data.sprite_sheet.get_height())
	_opaque_height_cache[data.id] = maxf(height, 1.0)
	return maxf(height, 1.0)

func _get_player_visual_height() -> float:
	if OS.is_debug_build():
		_player_visual_height_call_count += 1
	return _player_visual_height_cache if _player_visual_height_cache >= 0.0 else 32.0

func _calculate_player_visual_height() -> float:
	if _player == null or not is_instance_valid(_player) or _player.animated_sprite == null:
		return 32.0
	var sprite := _player.animated_sprite
	var frames := sprite.sprite_frames
	if frames == null or not frames.has_animation(sprite.animation):
		return 32.0
	var texture := frames.get_frame_texture(sprite.animation, sprite.frame)
	if texture == null:
		return 32.0
	if OS.is_debug_build():
		_player_visual_height_image_read_count += 1
	var image := texture.get_image()
	if image == null:
		return 32.0
	var used := image.get_used_rect()
	if used.size.y <= 0:
		return 32.0
	return clampf(float(used.size.y) * absf(sprite.global_scale.y), 24.0, 56.0)

func debug_reset_spawn_cost_counters() -> void:
	_player_visual_height_call_count = 0
	_player_visual_height_image_read_count = 0

func debug_get_spawn_cost_counters() -> Dictionary:
	return {
		"player_visual_height_calls": _player_visual_height_call_count,
		"player_visual_height_image_reads": _player_visual_height_image_read_count,
		"player_visual_height_cache": _player_visual_height_cache,
	}

func _theme_color(theme_id: String) -> Color:
	var theme: EffectThemeData = DataLoader.effect_themes.get(theme_id)
	return theme.hit_color if theme else Color(0.92, 0.95, 1.0, 1.0)

func _get_tree_timer(seconds: float) -> SceneTreeTimer:
	return get_tree().create_timer(maxf(seconds, 0.05), false)

func _free_weak_ref(node_ref: WeakRef) -> void:
	var node := node_ref.get_ref() as Node
	if node and is_instance_valid(node):
		node.queue_free()
