extends Node2D
class_name AttackVFXManager
## 通常攻撃開始と命中時のPixel Sprite Animationを実ゲームWorldへ生成する。

signal effect_spawned(effect_id: String, effect: AnimatedSprite2D)
signal element_effect_spawned(effect_id: String, effect: AnimatedSprite2D)
signal element_level_feedback_spawned(element_id: String, level: int, effect: Node2D)
signal fusion_effect_spawned(fusion_id: String, mode: String, effect: FusionVFXEffect)

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
# 画面上で読める上限を超えたTriggered presentationだけを間引く。
# Damage/Status/Procはこの入口より前に確定済みで、Gameplay結果は変えない。
const MAX_LIVE_FUSION_EFFECTS := 192
const FUSION_FORMATION_RESERVE := 16

var _frames_cache: Dictionary = {}
var _opaque_height_cache: Dictionary = {}
var _element_frames_cache: Dictionary = {}
var _element_opaque_height_cache: Dictionary = {}
var _element_opaque_size_cache: Dictionary = {}
var _player: Player
var _element_stack_snapshot: Dictionary = {}
var _live_fusion_effects: int = 0

func _ready() -> void:
	add_to_group("attack_vfx_manager")
	_element_stack_snapshot = GameManager.element_stacks.duplicate(true)
	if not EventBus.element_loadout_changed.is_connected(_on_element_loadout_changed):
		EventBus.element_loadout_changed.connect(_on_element_loadout_changed)
	if not EventBus.element_fusion_formed.is_connected(_on_element_fusion_formed):
		EventBus.element_fusion_formed.connect(_on_element_fusion_formed)
	call_deferred("_connect_player")

func _connect_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null or _player.weapon_manager == null:
		return
	if not _player.weapon_manager.attack_vfx_requested.is_connected(_on_attack_vfx_requested):
		_player.weapon_manager.attack_vfx_requested.connect(_on_attack_vfx_requested)

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
	# Automatic attacks keep their character/weapon presentation. Stack visuals belong
	# to confirmed element damage and Iai-specific paths below.
	play_effect(effect_id, origin, direction, _theme_color(character_data.vfx_theme_id), strength)

func play_hit(position: Vector2, theme_id: String, is_critical: bool) -> void:
	var effect_id := "hit_critical" if is_critical else "hit_normal"
	var color := _theme_color(theme_id)
	if is_critical:
		color = color.lerp(Color.WHITE, 0.35)
	play_effect(effect_id, position, Vector2.RIGHT, color)
	if is_critical:
		_spawn_critical_flash(position, color)

func play_element_hit(position: Vector2, data: ElementVFXData = null, stack_level: int = -1) -> AnimatedSprite2D:
	var resolved := data if data else _active_element_data()
	if resolved == null or resolved.hit_sprite_sheet == null or resolved.hit_vfx_id == "":
		return null
	var resolved_stack := GameManager.get_element_stack(resolved.element_id) if stack_level < 0 else stack_level
	var effect := _play_element_sprite(
		resolved.hit_vfx_id,
		resolved.hit_sprite_sheet,
		resolved.hit_fps,
		resolved.hit_lifetime,
		resolved.hit_visual_ratio,
		position,
		0.0,
		resolved_stack
	)
	if effect and resolved_stack >= 2:
		_spawn_stack_hit_accent(position, resolved, resolved_stack)
	return effect

## 居合の実移動区間1つに、現在属性のSprite Animationを1枚重ねる。
## 各dash stepから呼ぶため、連続した細い軌跡になり、壁で止まった区間はその実距離だけ描画される。
func play_iai_trail(segment_start: Vector2, segment_end: Vector2) -> AnimatedSprite2D:
	if GameManager.active_fusion_id != "":
		play_fusion_effect(GameManager.active_fusion_id, segment_start, segment_end, "trail", 1.12)
		return null
	var data := _active_element_data()
	var stack := GameManager.get_element_stack(GameManager.active_element_id)
	var segment := segment_end - segment_start
	if data == null or data.iai_trail_sprite_sheet == null or data.iai_trail_vfx_id == "" or segment.length_squared() <= 0.25:
		return null
	var effect := _play_element_sprite(
		data.iai_trail_vfx_id,
		data.iai_trail_sprite_sheet,
		data.iai_trail_fps,
		data.iai_trail_lifetime,
		data.iai_trail_visual_ratio,
		segment_start.lerp(segment_end, 0.5),
		segment.angle() - PI * 0.5,
		stack
	)
	if effect and stack >= 2:
		_spawn_stack_trail_accent(segment_start, segment_end, data, stack)
	return effect

func play_lightning_chain(from: Vector2, to: Vector2, stack_level: int, jump_index: int) -> AnimatedSprite2D:
	var data: ElementVFXData = DataLoader.element_vfx_effects.get("element_lightning")
	if data == null or data.chain_vfx_id == "" or data.chain_sprite_sheet == null:
		return null
	var segment := to - from
	if segment.length_squared() <= 1.0:
		return null
	var frames := _get_element_frames(data.chain_vfx_id, data.chain_sprite_sheet, data.chain_fps)
	if frames == null:
		return null
	var effect := AnimatedSprite2D.new()
	effect.name = "ElementVFX_%s_%d" % [data.chain_vfx_id, jump_index]
	effect.sprite_frames = frames
	effect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	effect.z_index = 47
	effect.global_position = from.lerp(to, 0.5)
	effect.rotation = segment.angle()
	var opaque_size := _get_element_opaque_size(data.chain_vfx_id, data.chain_sprite_sheet)
	var stack_scale := _visual_stack_value("visual_stack_scales", stack_level, 1.0)
	var target_height := clampf(_get_player_visual_height() * data.chain_visual_ratio * stack_scale, 10.0, 24.0)
	effect.scale = Vector2(segment.length() / maxf(opaque_size.x, 1.0), target_height / maxf(opaque_size.y, 1.0))
	effect.modulate.a = _visual_stack_value("visual_stack_opacity", stack_level, 1.0)
	add_child(effect)
	effect.animation_finished.connect(effect.queue_free)
	effect.play("play")
	_get_tree_timer(data.chain_lifetime + 0.1).timeout.connect(_free_weak_ref.bind(weakref(effect)))
	element_effect_spawned.emit(data.chain_vfx_id, effect)
	return effect

func play_fusion_effect(fusion_id: String, from: Vector2, to: Vector2, mode: String = "attack", intensity: float = 1.0) -> FusionVFXEffect:
	# Echo + multi-Chainを同一Frameへ人為的に集中させてもPresentation Nodeだけを
	# 有界に保つ。Gameplay Damage/Status/Procはこの入口より前に確定している。
	# Awakening表示が大量Hitの末尾で欠落しないよう、上限内に専用枠を予約する。
	var live_limit := MAX_LIVE_FUSION_EFFECTS if mode == "formation" else MAX_LIVE_FUSION_EFFECTS - FUSION_FORMATION_RESERVE
	if _live_fusion_effects >= live_limit:
		return null
	var effect := FusionVFXEffect.new()
	effect.name = "FusionVFX_%s_%s" % [fusion_id, mode]
	_live_fusion_effects += 1
	effect.tree_exited.connect(_on_fusion_effect_exited)
	add_child(effect)
	effect.configure(fusion_id, from, to, mode, intensity)
	fusion_effect_spawned.emit(fusion_id, mode, effect)
	return effect

func _on_fusion_effect_exited() -> void:
	_live_fusion_effects = maxi(0, _live_fusion_effects - 1)

func _on_element_fusion_formed(fusion_id: String, display_name: String, source_element_ids: Array) -> void:
	if _player == null or not is_instance_valid(_player):
		_connect_player()
	var position := _player.global_position if _player else Vector2.ZERO
	_spawn_fusion_source_convergence(position, source_element_ids)
	play_fusion_effect(fusion_id, position, position, "formation", 1.65)
	_spawn_fusion_banner(display_name, source_element_ids)
	var screen_effects := get_parent().get_node_or_null("ScreenEffects") as ScreenEffects
	if screen_effects:
		screen_effects.shake(10.0, 0.38)
		screen_effects.hit_stop(0.12)

func _spawn_fusion_source_convergence(position: Vector2, source_element_ids: Array) -> void:
	var root := Node2D.new()
	root.name = "FusionSourceConvergence"
	root.global_position = position
	root.z_index = 39
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_to_group("transient_vfx")
	root.set_meta("visual_only", true)
	add_child(root)
	for source_index in mini(source_element_ids.size(), 2):
		var element_id := String(source_element_ids[source_index])
		var data := DataLoader.element_vfx_effects.get(element_id) as ElementVFXData
		var color := data.attack_tint if data else Color.WHITE
		for shard_index in 7:
			var shard := Polygon2D.new()
			shard.name = "SourceShard_%d_%d" % [source_index, shard_index]
			shard.polygon = PackedVector2Array([Vector2(0, -4), Vector2(3, 0), Vector2(0, 4), Vector2(-3, 0)])
			shard.color = Color(color, 0.9)
			var side_angle := (-2.35 if source_index == 0 else -0.78) + shard_index * 0.13
			shard.position = Vector2.from_angle(side_angle) * (62.0 + shard_index * 6.0)
			root.add_child(shard)
			var tween := shard.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			tween.tween_property(shard, "position", Vector2.ZERO, 0.28 + shard_index * 0.014).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tween.tween_property(shard, "scale", Vector2(0.12, 0.12), 0.09)
	get_tree().create_timer(0.48, true, false, true).timeout.connect(root.queue_free)

func _spawn_fusion_banner(display_name: String, source_element_ids: Array) -> void:
	var layer := CanvasLayer.new()
	layer.name = "FusionFormationBanner"
	layer.layer = 80
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_to_group("transient_vfx")
	layer.set_meta("visual_only", true)
	add_child(layer)
	var source_names: Array[String] = []
	for element_id in source_element_ids:
		source_names.append(String(element_id).trim_prefix("element_").to_upper())
	var label := Label.new()
	label.text = "%s\n↓\n%s" % [" × ".join(source_names), display_name]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.position = Vector2(-310, -92)
	label.size = Vector2(620, 184)
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", Color(1.0, 0.91, 0.58, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 3)
	label.add_theme_constant_override("shadow_offset_y", 3)
	layer.add_child(label)
	label.modulate.a = 0.0
	var tween := layer.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(label, "modulate:a", 1.0, 0.18)
	tween.tween_interval(1.05)
	tween.tween_property(label, "modulate:a", 0.0, 0.30)
	tween.tween_callback(layer.queue_free)

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

func _play_element_sprite(effect_id: String, sprite_sheet: Texture2D, fps: float, lifetime: float, visual_ratio: float, position: Vector2, rotation_radians: float, stack_level: int = 1) -> AnimatedSprite2D:
	var frames := _get_element_frames(effect_id, sprite_sheet, fps)
	if frames == null:
		return null
	var effect := AnimatedSprite2D.new()
	effect.name = "ElementVFX_%s" % effect_id
	effect.sprite_frames = frames
	effect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	effect.z_index = 46
	effect.global_position = position
	effect.rotation = rotation_radians
	var player_height := _get_player_visual_height()
	var opaque_height := _get_element_opaque_height(effect_id, sprite_sheet)
	var stack_scale := _visual_stack_value("visual_stack_scales", stack_level, 1.0)
	var target_height := clampf(player_height * visual_ratio * stack_scale, 18.0, 84.0)
	effect.scale = Vector2.ONE * target_height / maxf(opaque_height, 1.0)
	effect.modulate.a = _visual_stack_value("visual_stack_opacity", stack_level, 1.0)
	add_child(effect)
	effect.animation_finished.connect(effect.queue_free)
	effect.play("play")
	_get_tree_timer(lifetime + 0.1).timeout.connect(_free_weak_ref.bind(weakref(effect)))
	element_effect_spawned.emit(effect_id, effect)
	return effect

func _get_element_frames(effect_id: String, sprite_sheet: Texture2D, fps: float, loop: bool = false) -> SpriteFrames:
	var cache_id := "%s::%s" % [effect_id, "loop" if loop else "once"]
	if _element_frames_cache.has(cache_id):
		return _element_frames_cache[cache_id]
	if sprite_sheet == null or sprite_sheet.get_height() <= 0:
		return null
	var frame_size := sprite_sheet.get_height()
	var count := mini(6, int(sprite_sheet.get_width() / frame_size))
	if count <= 0:
		return null
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("play")
	frames.set_animation_loop("play", loop)
	frames.set_animation_speed("play", fps)
	for index in count:
		var atlas := AtlasTexture.new()
		atlas.atlas = sprite_sheet
		atlas.region = Rect2(index * frame_size, 0, frame_size, frame_size)
		frames.add_frame("play", atlas)
	_element_frames_cache[cache_id] = frames
	return frames

func _get_element_opaque_size(effect_id: String, sprite_sheet: Texture2D) -> Vector2:
	if _element_opaque_size_cache.has(effect_id):
		return _element_opaque_size_cache[effect_id]
	var image := sprite_sheet.get_image()
	if image == null:
		return Vector2(sprite_sheet.get_height(), sprite_sheet.get_height())
	var frame_size := image.get_height()
	var frame_count := mini(6, int(image.get_width() / maxi(frame_size, 1)))
	var max_size := Vector2.ONE
	for index in frame_count:
		var frame := image.get_region(Rect2i(index * frame_size, 0, frame_size, frame_size))
		var used := frame.get_used_rect()
		max_size.x = maxf(max_size.x, used.size.x)
		max_size.y = maxf(max_size.y, used.size.y)
	_element_opaque_size_cache[effect_id] = max_size
	return max_size

func _get_element_opaque_height(effect_id: String, sprite_sheet: Texture2D) -> float:
	if _element_opaque_height_cache.has(effect_id):
		return float(_element_opaque_height_cache[effect_id])
	var height := _get_element_opaque_size(effect_id, sprite_sheet).y
	_element_opaque_height_cache[effect_id] = maxf(height, 1.0)
	return maxf(height, 1.0)

func _get_opaque_height(data: AttackVFXData) -> float:
	if _opaque_height_cache.has(data.id):
		return float(_opaque_height_cache[data.id])
	var image := data.sprite_sheet.get_image()
	var height := float(image.get_used_rect().size.y) if image else float(data.sprite_sheet.get_height())
	_opaque_height_cache[data.id] = maxf(height, 1.0)
	return maxf(height, 1.0)

func _get_player_visual_height() -> float:
	if _player == null or not is_instance_valid(_player) or _player.animated_sprite == null:
		return 32.0
	var sprite := _player.animated_sprite
	var frames := sprite.sprite_frames
	if frames == null or not frames.has_animation(sprite.animation):
		return 32.0
	var texture := frames.get_frame_texture(sprite.animation, sprite.frame)
	if texture == null:
		return 32.0
	var image := texture.get_image()
	if image == null:
		return 32.0
	var used := image.get_used_rect()
	if used.size.y <= 0:
		return 32.0
	return clampf(float(used.size.y) * absf(sprite.global_scale.y), 24.0, 56.0)

func _theme_color(theme_id: String) -> Color:
	var theme: EffectThemeData = DataLoader.effect_themes.get(theme_id)
	return theme.hit_color if theme else Color(0.92, 0.95, 1.0, 1.0)

func _active_element_data() -> ElementVFXData:
	return DataLoader.element_vfx_effects.get(GameManager.active_element_id) as ElementVFXData

func _visual_stack_value(key: String, stack_level: int, fallback: float) -> float:
	var values: Array = DataLoader.element_combat_config.get(key, [])
	if values.is_empty() or stack_level <= 0:
		return fallback
	return float(values[clampi(stack_level - 1, 0, values.size() - 1)])

func _spawn_critical_flash(position: Vector2, color: Color) -> void:
	var radius := clampf(_get_player_visual_height() * 0.32, 8.0, 16.0)
	var flash := Polygon2D.new()
	flash.name = "CriticalLocalFlash"
	flash.polygon = PackedVector2Array([
		Vector2(-radius, 0), Vector2(0, -radius * 0.45),
		Vector2(radius, 0), Vector2(0, radius * 0.45),
	])
	flash.color = Color(color.r, color.g, color.b, 0.72)
	flash.global_position = position
	flash.z_index = 44
	flash.scale = Vector2(0.35, 0.35)
	add_child(flash)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector2.ONE, 0.08)
	tween.tween_property(flash, "modulate:a", 0.0, 0.1)
	tween.finished.connect(flash.queue_free)

func _on_element_loadout_changed(_active_ids: Array, stacks: Dictionary) -> void:
	# Final Lv3でFusionが成立した場合は通常Level feedbackを重ねず、格上の成立演出だけを見せる。
	if GameManager.active_fusion_id != "":
		_element_stack_snapshot = stacks.duplicate(true)
		return
	for element_id in stacks:
		var old_level := int(_element_stack_snapshot.get(element_id, 0))
		var new_level := int(stacks.get(element_id, 0))
		if new_level > old_level and new_level >= 2:
			_play_element_level_feedback(String(element_id), new_level)
	_element_stack_snapshot = stacks.duplicate(true)

## Pure visual feedback for Lv2/Lv3. This path never calls attack, damage, weapon,
## Fusion, projectile, deferred-spawn, or recursive timer APIs.
func _play_element_level_feedback(element_id: String, level: int) -> Node2D:
	var data := DataLoader.element_vfx_effects.get(element_id) as ElementVFXData
	if data == null or _player == null or not is_instance_valid(_player):
		return null
	var root := Node2D.new()
	root.name = "ElementLevelFeedback_%s_Lv%d" % [element_id.trim_prefix("element_"), level]
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.z_index = 49
	root.set_meta("element_id", element_id)
	root.set_meta("variant_level", level)
	root.set_meta("visual_only", true)
	add_child(root)
	root.global_position = _player.global_position + Vector2(0, -_get_player_visual_height() * 0.15)

	var radius := 18.0 if level == 2 else 24.0
	var ring := Line2D.new()
	ring.name = "LevelRing"
	ring.points = _circle_points(radius, 28)
	ring.width = 1.6 if level == 2 else 2.2
	ring.default_color = Color(data.attack_tint, 0.82)
	ring.antialiased = false
	root.add_child(ring)

	var core := Polygon2D.new()
	core.name = "LevelCoreGlow"
	match data.stack_accent_style:
		"rays":
			# 光は横へ飛ぶ弾に見えない、Player中心の細い縦コアにする。
			core.polygon = PackedVector2Array([
				Vector2(-1.4, 0), Vector2(0, -radius * 0.58),
				Vector2(1.4, 0), Vector2(0, radius * 0.58),
			])
			core.color = Color(data.secondary_tint, 0.58 if level == 2 else 0.78)
		"rifts":
			# 闇は面を塗らず、細い不規則な虚無の割れ目だけを残す。
			core.polygon = PackedVector2Array([
				Vector2(-1.8, -radius * 0.56), Vector2(1.2, -radius * 0.18),
				Vector2(-1.0, radius * 0.12), Vector2(1.6, radius * 0.56),
				Vector2(-2.2, radius * 0.2), Vector2(0.8, -radius * 0.2),
			])
			core.color = Color(0.025, 0.005, 0.045, 0.88)
		_:
			core.polygon = PackedVector2Array([
				Vector2(-radius * 0.42, 0), Vector2(0, -radius * 0.22),
				Vector2(radius * 0.42, 0), Vector2(0, radius * 0.22),
			])
			core.color = Color(data.secondary_tint, 0.48 if level == 2 else 0.68)
	root.add_child(core)
	if data.stack_accent_style == "rifts":
		var seam := _accent_line(PackedVector2Array([
			Vector2(-1.5, -radius * 0.56), Vector2(1.0, -radius * 0.18),
			Vector2(-0.8, radius * 0.12), Vector2(1.3, radius * 0.56),
		]), Color(data.secondary_tint, 0.74), 0.85)
		seam.name = "DarkLevelRiftEdge"
		root.add_child(seam)

	var particles := CPUParticles2D.new()
	particles.name = "LevelBurstParticles"
	particles.amount = data.level2_accent_count + 3 if level == 2 else data.level3_accent_count + 5
	particles.one_shot = true
	particles.explosiveness = 1.0
	var is_light_or_dark := data.stack_accent_style in ["rays", "rifts"]
	particles.lifetime = 0.52 if is_light_or_dark else 0.62
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 5.0
	particles.direction = Vector2(0, -1)
	particles.spread = 180.0
	# 光/闇は遠くへ飛ぶ攻撃に誤認されないよう、Player周囲の短い漂いに限定する。
	particles.initial_velocity_min = 5.0 if is_light_or_dark else 22.0
	particles.initial_velocity_max = (12.0 if level == 2 else 17.0) if is_light_or_dark else (42.0 if level == 2 else 58.0)
	particles.gravity = Vector2.ZERO if is_light_or_dark else Vector2(0, 18)
	particles.color = Color(data.secondary_tint, 0.9)
	root.add_child(particles)
	particles.emitting = true

	var label := Label.new()
	label.name = "LevelLabel"
	label.text = "%s  %s" % [data.display_name, "LEVEL 2" if level == 2 else "LEVEL MAX"]
	label.position = Vector2(-100, -radius - 34)
	label.size = Vector2(200, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17 if level == 2 else 19)
	label.add_theme_color_override("font_color", data.secondary_tint)
	label.add_theme_color_override("font_shadow_color", Color(0.02, 0.02, 0.04, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(label)

	root.scale = Vector2.ONE * 0.55
	var tween := create_tween()
	tween.tween_property(root, "scale", Vector2.ONE * (1.12 if level == 2 else 1.28), 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.24)
	tween.tween_property(root, "scale", Vector2(0.12, 0.12), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.finished.connect(root.queue_free)
	element_level_feedback_spawned.emit(element_id, level, root)
	return root

func _spawn_stack_hit_accent(position: Vector2, data: ElementVFXData, stack_level: int) -> Node2D:
	var root := Node2D.new()
	root.name = "ElementStackAccent_%s_Hit_Lv%d" % [data.element_id.trim_prefix("element_"), stack_level]
	root.z_index = 47
	root.set_meta("element_id", data.element_id)
	root.set_meta("variant_level", stack_level)
	root.set_meta("accent_style", data.stack_accent_style)
	root.set_meta("whole_sprite_fade", false)
	var count := data.level2_accent_count if stack_level == 2 else data.level3_accent_count
	root.set_meta("accent_count", count)
	add_child(root)
	root.global_position = position
	var radius := 14.0 if stack_level == 2 else 20.0
	for index in count:
		var angle := TAU * float(index) / float(maxi(count, 1)) + (0.12 if stack_level >= 3 else 0.0)
		var direction := Vector2.from_angle(angle)
		match data.stack_accent_style:
			"embers":
				var ember := Polygon2D.new()
				ember.polygon = PackedVector2Array([Vector2(-1.3, 1.8), Vector2(0, -2.8), Vector2(1.3, 1.8), Vector2(0, 1.0)])
				ember.color = Color(data.secondary_tint, 0.9)
				ember.position = direction * (radius * (0.45 + 0.45 * float(index % 3) / 2.0))
				ember.rotation = angle + PI * 0.5
				root.add_child(ember)
			"crystals":
				root.add_child(_accent_line(PackedVector2Array([direction * radius * 0.28, direction * radius]), data.secondary_tint, 1.2))
			"arcs":
				var normal := direction.orthogonal()
				root.add_child(_accent_line(PackedVector2Array([
					direction * radius * 0.22,
					direction * radius * 0.58 + normal * (2.2 if index % 2 == 0 else -2.2),
					direction * radius,
				]), data.secondary_tint, 1.15))
			"rays":
				var ray_end := direction * radius * (0.82 if index % 2 == 0 else 1.0)
				var ray := _accent_line(PackedVector2Array([direction * radius * 0.4, ray_end]), data.secondary_tint, 0.9)
				ray.name = "LightRay_%02d" % index
				root.add_child(ray)
				if index % 2 == 0:
					var sparkle := _accent_line(PackedVector2Array([ray_end - direction.orthogonal() * 1.8, ray_end + direction.orthogonal() * 1.8]), Color(data.secondary_tint, 0.9), 0.75)
					sparkle.name = "LightSpark_%02d" % index
					root.add_child(sparkle)
			"rifts":
				var shard := Polygon2D.new()
				shard.polygon = PackedVector2Array([Vector2(-1.2, 0), Vector2(0, -4.0), Vector2(1.2, 0), Vector2(0, 2.0)])
				shard.color = Color(data.secondary_tint, 0.82)
				shard.position = direction * radius * (0.55 + 0.3 * float(index % 2))
				shard.rotation = angle - PI * 0.5
				root.add_child(shard)
	if data.stack_accent_style == "rifts":
		var axis := Vector2(0.34, -1.0).normalized()
		var side := axis.orthogonal()
		var rift_points := PackedVector2Array([
			-axis * radius * 0.72,
			-axis * radius * 0.24 + side * 2.2,
			axis * radius * 0.18 - side * 1.6,
			axis * radius * 0.72,
		])
		var void_rift := _accent_line(rift_points, Color(0.015, 0.0, 0.025, 0.92), 2.6 if stack_level == 2 else 3.2)
		void_rift.name = "DarkVoidRift"
		root.add_child(void_rift)
		var rift_edge := _accent_line(rift_points, Color(data.secondary_tint, 0.82), 0.85)
		rift_edge.name = "DarkRiftEdge"
		root.add_child(rift_edge)
	elif data.stack_accent_style == "rays" and stack_level >= 3:
		var star := Polygon2D.new()
		star.name = "LightSacredStar"
		star.polygon = _star_points(6.0, 1.5, 4)
		star.color = Color(data.secondary_tint, 0.72)
		root.add_child(star)
	elif stack_level >= 3:
		var core_ring := Line2D.new()
		core_ring.name = "CoreGlowRing"
		core_ring.points = _circle_points(radius * 0.46, 20)
		core_ring.width = 1.5
		core_ring.default_color = Color(data.secondary_tint, 0.72)
		root.add_child(core_ring)
	root.scale = Vector2.ONE * 0.72
	var tween := create_tween()
	tween.tween_property(root, "scale", Vector2.ONE * (1.08 if stack_level == 2 else 1.22), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.finished.connect(_collapse_hit_accent.bind(root))
	return root

func _collapse_hit_accent(root: Node2D) -> void:
	if not is_instance_valid(root):
		return
	# 発光面を薄くせず、外周形状を中心へ畳みながら粒子/欠片として終える。
	var collapse := root.create_tween()
	collapse.tween_property(root, "scale", root.scale * 0.16, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	collapse.finished.connect(root.queue_free)

func _spawn_stack_trail_accent(segment_start: Vector2, segment_end: Vector2, data: ElementVFXData, stack_level: int) -> Node2D:
	var segment := segment_end - segment_start
	if segment.length_squared() <= 0.25:
		return null
	var root := Node2D.new()
	root.name = "ElementStackAccent_%s_Trail_Lv%d" % [data.element_id.trim_prefix("element_"), stack_level]
	root.z_index = 45
	root.set_meta("element_id", data.element_id)
	root.set_meta("variant_level", stack_level)
	root.set_meta("accent_style", data.stack_accent_style)
	root.set_meta("whole_sprite_fade", false)
	add_child(root)
	root.global_position = segment_start
	var normal := segment.normalized().orthogonal()
	var layer_count := 1 if stack_level == 2 else 2
	root.set_meta("accent_count", layer_count)
	for layer in layer_count:
		var side := -1.0 if layer == 0 else 1.0
		var offset := normal * (3.0 + float(layer) * 1.5) * side
		var points := PackedVector2Array([offset, segment + offset])
		if data.stack_accent_style == "arcs":
			points = PackedVector2Array([offset, segment * 0.34 + offset + normal * 2.5, segment * 0.67 + offset - normal * 2.0, segment + offset])
		elif data.stack_accent_style == "rifts":
			points = PackedVector2Array([
				segment * 0.06 + offset,
				segment * 0.3 + offset + normal * side * 2.2,
				segment * 0.52 + offset - normal * side * 1.8,
				segment * 0.72 + offset + normal * side * 1.4,
				segment * 0.94 + offset,
			])
		var trail_line := _accent_line(points, Color(data.secondary_tint, 0.62 if stack_level == 2 else 0.78), 1.05 if stack_level == 2 else 1.35)
		trail_line.name = "%sTrailLayer_%d" % ["Light" if data.stack_accent_style == "rays" else ("Dark" if data.stack_accent_style == "rifts" else "Element"), layer]
		root.add_child(trail_line)
	if data.stack_accent_style == "rifts":
		var void_points := PackedVector2Array([
			segment * 0.05,
			segment * 0.3 + normal * 1.4,
			segment * 0.52 - normal * 1.2,
			segment * 0.72 + normal,
			segment * 0.95,
		])
		var void_line := _accent_line(void_points, Color(0.012, 0.0, 0.022, 0.86), 2.0 if stack_level == 2 else 2.6)
		void_line.name = "DarkVoidTrail"
		root.add_child(void_line)
	elif data.stack_accent_style == "rays":
		var sparkle_count := 3 if stack_level == 2 else 5
		var tangent := segment.normalized()
		for index in sparkle_count:
			var center := segment * (float(index + 1) / float(sparkle_count + 1)) + normal * (2.0 if index % 2 == 0 else -2.0)
			var sparkle := _accent_line(PackedVector2Array([center - normal * 1.8, center + normal * 1.8]), Color(data.secondary_tint, 0.72), 0.75)
			sparkle.name = "LightTrailSpark_%02d" % index
			root.add_child(sparkle)
			if stack_level >= 3:
				var sparkle_cross := _accent_line(PackedVector2Array([center - tangent * 1.2, center + tangent * 1.2]), Color(data.secondary_tint, 0.62), 0.7)
				sparkle_cross.name = "LightTrailSparkCross_%02d" % index
				root.add_child(sparkle_cross)
	if data.stack_accent_style in ["embers", "crystals"]:
		var marker_count := 3 if stack_level == 2 else 5
		for index in marker_count:
			var marker := Polygon2D.new()
			marker.polygon = PackedVector2Array([Vector2(-1, 0), Vector2(0, -2.5), Vector2(1, 0), Vector2(0, 2.5)])
			marker.color = Color(data.secondary_tint, 0.72)
			marker.position = segment * (float(index + 1) / float(marker_count + 1)) + normal * (2.0 if index % 2 == 0 else -2.0)
			marker.rotation = segment.angle()
			root.add_child(marker)
	_get_tree_timer(0.18 if stack_level == 2 else 0.24).timeout.connect(_collapse_trail_accent.bind(root, 0.16 if stack_level == 2 else 0.2))
	return root

func _collapse_trail_accent(root: Node2D, duration: float) -> void:
	if not is_instance_valid(root):
		return
	var original_points: Dictionary = {}
	for child in root.get_children():
		if child is Line2D:
			original_points[child] = (child as Line2D).points
	var steps := 5
	for step in range(1, steps + 1):
		if not is_instance_valid(root):
			return
		var keep := 1.0 - float(step) / float(steps + 1)
		for line_node in original_points:
			if not is_instance_valid(line_node):
				continue
			var source: PackedVector2Array = original_points[line_node]
			if source.is_empty():
				continue
			var center := source[0].lerp(source[source.size() - 1], 0.5)
			var collapsed := PackedVector2Array()
			for point in source:
				collapsed.append(center + (point - center) * keep)
			(line_node as Line2D).points = collapsed
		for child in root.get_children():
			if child is Polygon2D and absf((child as Polygon2D).position.x) > 0.0:
				(child as Polygon2D).visible = keep > 0.28 + float(child.get_index() % 3) * 0.16
		await _get_tree_timer(duration / float(steps)).timeout
	if is_instance_valid(root):
		root.queue_free()

func _accent_line(points: PackedVector2Array, color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.width = width
	line.default_color = color
	line.antialiased = false
	return line

func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in segments + 1:
		points.append(Vector2.from_angle(TAU * float(index) / float(segments)) * radius)
	return points

func _star_points(outer_radius: float, inner_radius: float, arms: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in arms * 2:
		var radius := outer_radius if index % 2 == 0 else inner_radius
		points.append(Vector2.from_angle(-PI * 0.5 + PI * float(index) / float(arms)) * radius)
	return points

func _get_tree_timer(seconds: float) -> SceneTreeTimer:
	return get_tree().create_timer(maxf(seconds, 0.05), false)

func _free_weak_ref(node_ref: WeakRef) -> void:
	var node := node_ref.get_ref() as Node
	if node and is_instance_valid(node):
		node.queue_free()
