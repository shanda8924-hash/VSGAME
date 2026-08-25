extends Node2D
class_name FusionVFXEffect
## 新規生成Pixel Artを主描画にし、Canvas/Particleは短い補助層だけを担当する。

const PIXEL_FRAME_COUNT := 6

var fusion_id: String
var mode: String
var target_offset: Vector2
var intensity: float = 1.0
var lifetime: float = 0.72
var _age: float = 0.0
var _started_msec: int = 0
var _pixel_sprite: AnimatedSprite2D

func configure(id: String, from: Vector2, to: Vector2, effect_mode: String, strength: float = 1.0) -> void:
	fusion_id = id
	mode = effect_mode
	intensity = clampf(strength, 0.55, 2.0)
	global_position = from
	target_offset = to - from
	if mode in ["formation", "intro", "state"]:
		target_offset = Vector2.ZERO
		lifetime = 0.72
	elif mode in ["burst", "signature", "pillar", "portal"]:
		lifetime = 0.50
	elif mode == "soul":
		lifetime = 0.45
	elif mode == "trail":
		lifetime = 0.32
	elif mode == "hit":
		lifetime = 0.38
	else:
		lifetime = 0.42
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 38
	add_to_group("transient_vfx")
	set_meta("visual_only", true)
	set_meta("fusion_id", fusion_id)
	set_meta("effect_mode", mode)
	_started_msec = Time.get_ticks_msec()
	_spawn_generated_pixel_art()
	set_meta("generated_pixel_art", _pixel_sprite != null)
	_spawn_particles()
	queue_redraw()

func _process(_delta: float) -> void:
	# Fusion成立時のHit Stop中も実時間で寿命を進め、VFX Nodeを滞留させない。
	_age = (Time.get_ticks_msec() - _started_msec) / 1000.0
	_update_pixel_art_transform(clampf(_age / lifetime, 0.0, 1.0))
	queue_redraw()
	if _age >= lifetime:
		queue_free()

func _draw() -> void:
	var t := clampf(_age / lifetime, 0.0, 1.0)
	var pulse := sin(t * PI)
	# 本体を寿命途中から薄くしない。最後の短い残光だけAlphaを落とし、
	# 主Spriteは6-frame内の外周崩壊で消える。
	var alpha := 1.0 if t < 0.90 else 1.0 - smoothstep(0.90, 1.0, t)
	# 新規Pixel Spriteが主役。従来Canvas形状は奥行きを足す低Alphaの補助だけにする。
	if is_instance_valid(_pixel_sprite):
		alpha *= 0.04
	var power := intensity * (0.72 + pulse * 0.42)
	match fusion_id:
		"frostfire": _draw_frostfire(t, alpha, power)
		"plasma": _draw_plasma(t, alpha, power)
		"solar": _draw_solar(t, alpha, power)
		"inferno": _draw_inferno(t, alpha, power)
		"superconductor": _draw_superconductor(t, alpha, power)
		"aurora": _draw_aurora(t, alpha, power)
		"void_frost": _draw_void_frost(t, alpha, power)
		"judgment": _draw_judgment(t, alpha, power)
		"voidstorm": _draw_voidstorm(t, alpha, power)
		"eclipse": _draw_eclipse(t, alpha, power)
	_draw_mode_accent(t, alpha, power)

func _spawn_generated_pixel_art() -> void:
	var data := DataLoader.fusion_vfx_effects.get(fusion_id) as FusionVFXData
	if data == null:
		push_warning("FusionVFXEffect: generated Pixel Art Resource missing -> %s" % fusion_id)
		return
	var texture := data.sprite_sheet_for_mode(mode)
	if texture == null or texture.get_width() <= 0 or texture.get_width() % PIXEL_FRAME_COUNT != 0:
		push_warning("FusionVFXEffect: invalid Pixel Art Sprite Sheet -> %s / %s" % [fusion_id, mode])
		return
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("play")
	frames.set_animation_loop("play", false)
	frames.set_animation_speed("play", data.fps)
	var frame_size := Vector2(texture.get_width() / PIXEL_FRAME_COUNT, texture.get_height())
	for frame_index in PIXEL_FRAME_COUNT:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(Vector2(frame_size.x * frame_index, 0.0), frame_size)
		frames.add_frame("play", atlas)
	_pixel_sprite = AnimatedSprite2D.new()
	_pixel_sprite.name = "GeneratedFusionPixelArt"
	_pixel_sprite.sprite_frames = frames
	_pixel_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pixel_sprite.z_index = 5
	_pixel_sprite.scale = Vector2.ONE * _pixel_visual_scale()
	if mode in ["attack", "trail"] and target_offset.length_squared() > 1.0:
		_pixel_sprite.rotation = target_offset.angle()
	add_child(_pixel_sprite)
	_pixel_sprite.play("play")
	set_meta("pixel_art_texture", texture.resource_path)
	set_meta("pixel_art_resource", data.resource_path)
	_update_pixel_art_transform(0.0)

func _pixel_visual_scale() -> float:
	var base := 0.76
	match mode:
		"trail", "soul": base = 0.74
		"hit": base = 0.80
		"burst", "signature", "pillar", "portal": base = 0.96
		"formation", "intro", "state": base = 1.12
	return base * clampf(intensity, 0.72, 1.6)

func _update_pixel_art_transform(t: float) -> void:
	if not is_instance_valid(_pixel_sprite):
		return
	# Sprite一枚を始点から終点へ滑らせない。Attack/Trailは実区間の中央に固定し、
	# Sprite Sheet内の中央展開→外周崩壊で「現象が進行する」ように見せる。
	_pixel_sprite.position = target_offset * 0.5 if mode in ["attack", "trail"] else target_offset
	set_meta("sprite_translation_ratio", 0.0)
	set_meta("phenomenon_extent", _phenomenon_extent(t))

func _phenomenon_extent(t: float) -> float:
	if t < 0.34:
		return smoothstep(0.0, 0.34, t)
	if t < 0.68:
		return 1.0
	return lerpf(1.0, 0.12, smoothstep(0.68, 1.0, t))

## Fusion固有の主形状は上の10描画で決め、用途差だけを短い共通文法で補強する。
## Element Spriteを再利用せず、Attack/Trail/Hit/Burst/Formationが同じ瞬間でも
## 読み分けられるようにする。すべてCanvas描画だけでCollisionは持たない。
func _draw_mode_accent(t: float, alpha: float, power: float) -> void:
	var primary := _primary_color()
	var secondary := _secondary_color()
	var focus := target_offset
	match mode:
		"attack":
			if target_offset.length_squared() > 1.0:
				var extent := _phenomenon_extent(t)
				var center := target_offset * 0.5
				var half_span := target_offset * extent * 0.5
				draw_line(center - half_span, center + half_span, _with_alpha(primary, alpha * 0.82), maxf(1.0, 2.0 * power), false)
				draw_circle(center - half_span, 2.2 * power, _with_alpha(secondary, alpha * 0.88))
				draw_circle(center + half_span, 2.2 * power, _with_alpha(Color.WHITE, alpha))
		"trail":
			if target_offset.length_squared() > 1.0:
				var normal := target_offset.normalized().orthogonal()
				for index in 6:
					var start_ratio := float(index) / 6.0
					var end_ratio := minf(start_ratio + 0.105, 1.0)
					var wave := normal * sin(index * 2.1 + t * 11.0) * 3.0 * power
					draw_line(target_offset * start_ratio + wave, target_offset * end_ratio + wave, _with_alpha(primary if index % 2 == 0 else secondary, alpha * 0.85), maxf(1.0, (3.2 - index * 0.25) * power), false)
		"hit":
			var hit_radius := (8.0 + t * 25.0) * power
			draw_arc(focus, hit_radius, 0.0, TAU, 20, _with_alpha(secondary, alpha), maxf(1.5, 3.0 * power), false)
			for index in 8:
				var direction := Vector2.from_angle(index * TAU / 8.0 + t * 0.35)
				draw_line(focus + direction * hit_radius * 0.55, focus + direction * hit_radius * (1.05 + 0.16 * (index % 2)), _with_alpha(primary, alpha * 0.9), maxf(1.0, 2.2 * power), false)
		"burst", "signature":
			var burst_radius := (13.0 + t * 48.0) * power
			draw_arc(focus, burst_radius, -0.5 + t, 5.75 + t, 28, _with_alpha(primary, alpha * 0.78), maxf(1.5, 4.0 * power), false)
			for index in 6:
				var angle := index * TAU / 6.0 - t * 0.4
				var shard_center := focus + Vector2.from_angle(angle) * burst_radius * 0.78
				var shard := PackedVector2Array([shard_center + Vector2(0, -4) * power, shard_center + Vector2(3, 3) * power, shard_center + Vector2(-3, 3) * power])
				draw_colored_polygon(shard, _with_alpha(secondary, alpha * 0.8))
		"formation":
			var formation_radius := (38.0 + sin(t * PI) * 13.0) * power
			draw_arc(focus, formation_radius, t * 2.2, t * 2.2 + 4.8, 30, _with_alpha(primary, alpha), maxf(2.0, 4.0 * power), false)
			draw_arc(focus, formation_radius + 9.0 * power, -t * 1.8 + 1.2, -t * 1.8 + 4.5, 26, _with_alpha(secondary, alpha * 0.8), maxf(1.0, 2.5 * power), false)
			for index in 8:
				var direction := Vector2.from_angle(index * TAU / 8.0 + t)
				draw_line(focus + direction * formation_radius * 1.35, focus + direction * formation_radius * 0.78, _with_alpha(primary, alpha * 0.65), maxf(1.0, 1.8 * power), false)
		"pillar":
			draw_arc(focus, (11.0 + t * 27.0) * power, 0.0, TAU, 20, _with_alpha(secondary, alpha), maxf(2.0, 3.0 * power), false)
		"portal":
			for center in [Vector2.ZERO, focus]:
				draw_arc(center, (23.0 + sin(t * PI) * 5.0) * power, -t * 3.0, 4.8 - t * 3.0, 22, _with_alpha(secondary, alpha * 0.72), maxf(1.5, 2.5 * power), false)
		"soul":
			var soul_position := focus.lerp(Vector2.ZERO, clampf(t, 0.0, 1.0))
			draw_circle(soul_position, 5.0 * power, _with_alpha(secondary, alpha))
		"state":
			draw_arc(focus, (67.0 + sin(t * TAU) * 4.0) * power, 0.0, TAU, 40, _with_alpha(primary, alpha * 0.85), maxf(2.0, 4.0 * power), false)

func _draw_frostfire(t: float, alpha: float, power: float) -> void:
	var center := target_offset
	var radius := (24.0 + t * 52.0) * power
	draw_circle(center, 7.0 * power, _c("#ff9b54", alpha * 0.9))
	for index in 5:
		var offset := Vector2(cos(index * 1.31), sin(index * 1.31)) * radius * 0.34
		draw_arc(center + offset, radius * (0.24 + index * 0.035), -1.8 + index, 1.8 + index, 12, _c("#dffaff", alpha * (0.75 - index * 0.07)), maxf(2.0, 5.0 * power), false)
	draw_arc(center, radius, 0.0, TAU, 30, _c("#f4ffff", alpha * 0.7), maxf(2.0, 4.0 * power), false)

func _draw_plasma(t: float, alpha: float, power: float) -> void:
	var end := target_offset
	var points := PackedVector2Array([Vector2.ZERO])
	for index in range(1, 9):
		var ratio := index / 8.0
		var base := target_offset * ratio
		var normal := target_offset.normalized().orthogonal()
		points.append(base + normal * sin(index * 4.7 + t * 18.0) * 7.0 * power)
	draw_polyline(points, _c("#7cf8ff", alpha * 0.45), 8.0 * power, false)
	draw_polyline(points, _c("#d6fbff", alpha), 2.0 * power, false)
	draw_circle(end, (12.0 + sin(t * 20.0) * 2.0) * power, _c("#8f46ff", alpha * 0.8))
	draw_circle(end, 5.0 * power, _c("#edffff", alpha))
	draw_arc(end, 20.0 * power, t * TAU, t * TAU + 4.7, 18, _c("#d56cff", alpha), 3.0 * power, false)

func _draw_solar(t: float, alpha: float, power: float) -> void:
	var center := target_offset
	draw_circle(center, 15.0 * power, _c("#fffbd1", alpha))
	draw_circle(center, 9.0 * power, _c("#ffffff", alpha))
	for index in 3:
		var radius := (24.0 + index * 8.0) * power
		var start := t * TAU * (1.0 if index % 2 == 0 else -1.0) + index * 1.8
		draw_arc(center, radius, start, start + 2.2, 18, _c("#ffc84d", alpha * (0.92 - index * 0.18)), (5.0 - index) * power, false)
	draw_polyline(PackedVector2Array([Vector2.ZERO, target_offset * 0.45 + Vector2(0, -18) * power, target_offset]), _c("#fff2a6", alpha * 0.7), 6.0 * power, false)

func _draw_inferno(t: float, alpha: float, power: float) -> void:
	var center := target_offset
	for index in 5:
		var x := (index - 2) * 7.0
		var flame := PackedVector2Array([center + Vector2(x - 6, 16) * power, center + Vector2(x, -22 - index * 3) * power, center + Vector2(x + 7, 15) * power])
		draw_colored_polygon(flame, _c("#160713", alpha * 0.95))
		draw_polyline(PackedVector2Array([flame[0], flame[1], flame[2], flame[0]]), _c("#d52b7b", alpha), 2.5 * power, false)
	for index in 4:
		var ratio := fmod(t * 1.6 + index * 0.23, 1.0)
		var soul := target_offset.lerp(Vector2.ZERO, ratio) + Vector2(sin(ratio * 12.0 + index), cos(ratio * 9.0)) * 10.0
		draw_circle(soul, 3.0 * power, _c("#ff477e", alpha * (1.0 - ratio * 0.4)))

func _draw_superconductor(t: float, alpha: float, power: float) -> void:
	var bend_a := Vector2(target_offset.x * 0.38, 0)
	var bend_b := Vector2(target_offset.x * 0.38, target_offset.y)
	var circuit := PackedVector2Array([Vector2.ZERO, bend_a, bend_b, target_offset])
	draw_polyline(circuit, _c("#e8feff", alpha), 3.0 * power, false)
	for point in circuit:
		var diamond := PackedVector2Array([point + Vector2(0, -8) * power, point + Vector2(7, 0) * power, point + Vector2(0, 8) * power, point + Vector2(-7, 0) * power])
		draw_colored_polygon(diamond, _c("#84eaff", alpha * 0.55))
		draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), _c("#ffffff", alpha), 2.0 * power, false)
	var wave_pos := target_offset * t
	draw_circle(wave_pos, 7.0 * power, _c("#b8ffff", alpha))

func _draw_aurora(t: float, alpha: float, power: float) -> void:
	var colors := ["#85fff2", "#a9a4ff", "#ffb6df"]
	for index in 3:
		var normal := target_offset.normalized().orthogonal()
		var ribbon := PackedVector2Array([normal * (index - 1) * 5.0, target_offset * 0.33 + normal * sin(t * 8.0 + index) * 20.0, target_offset * 0.67 - normal * cos(t * 7.0 + index) * 18.0, target_offset])
		draw_polyline(ribbon, _c(colors[index], alpha * (0.75 - index * 0.08)), (7.0 - index * 1.5) * power, false)
	var prism := PackedVector2Array([target_offset + Vector2(0, -15) * power, target_offset + Vector2(14, 11) * power, target_offset + Vector2(-14, 11) * power, target_offset + Vector2(0, -15) * power])
	draw_polyline(prism, _c("#f0ffff", alpha), 2.5 * power, false)

func _draw_void_frost(t: float, alpha: float, power: float) -> void:
	var center := target_offset
	var radius := (54.0 - t * 30.0) * power
	draw_circle(center, 13.0 * power, _c("#050510", alpha))
	draw_arc(center, 19.0 * power, 0, TAU, 20, _c("#7c72ff", alpha), 3.0 * power, false)
	for index in 9:
		var angle := index * TAU / 9.0 + t * 0.7
		var outer := center + Vector2.from_angle(angle) * radius
		var inner := center + Vector2.from_angle(angle) * 22.0 * power
		draw_line(outer, inner, _c("#b8e9ff", alpha * 0.85), 2.0 * power, false)
		draw_circle(outer, 3.0 * power, _c("#7064b8", alpha))

func _draw_judgment(t: float, alpha: float, power: float) -> void:
	# Legacy internal id "judgment" now presents Radiant Arc.  Keep a thin,
	# Lightning-like afterglow instead of the old sigil and vertical pillar.
	if target_offset.length_squared() <= 1.0:
		return
	var normal := target_offset.normalized().orthogonal()
	var points := PackedVector2Array([Vector2.ZERO])
	for index in range(1, 7):
		var ratio := float(index) / 6.0
		points.append(target_offset * ratio + normal * sin(index * 3.7 + t * 13.0) * 2.0 * power)
	draw_polyline(points, _c("#fff3a8", alpha), maxf(1.0, 1.5 * power), false)

func _draw_voidstorm(t: float, alpha: float, power: float) -> void:
	for center in [Vector2.ZERO, target_offset]:
		draw_arc(center, 18.0 * power, t * TAU, t * TAU + 5.0, 20, _c("#9f4dff", alpha), 5.0 * power, false)
		draw_circle(center, 10.0 * power, _c("#090313", alpha * 0.95))
	for index in 5:
		var ratio := fmod(t * 2.0 + index * 0.17, 1.0)
		if ratio > 0.45 and ratio < 0.62:
			continue
		var jump_ratio := ratio / 0.45 if ratio <= 0.45 else (ratio - 0.62) / 0.38
		draw_circle(Vector2.ZERO.lerp(target_offset, clampf(jump_ratio, 0.0, 1.0)), 3.5 * power, _c("#d387ff", alpha))

func _draw_eclipse(t: float, alpha: float, power: float) -> void:
	var center := target_offset
	var radius := (24.0 if mode not in ["formation", "state"] else 58.0) * power
	draw_circle(center, radius, _c("#030308", alpha))
	draw_arc(center, radius + 3.0 * power, 0, TAU, 40, _c("#ffe07a", alpha), 6.0 * power, false)
	draw_arc(center, radius + 13.0 * power, -1.1 + t, 1.8 + t, 24, _c("#fff3b5", alpha * 0.75), 3.0 * power, false)
	for index in 12:
		var angle := index * TAU / 12.0 + t * 0.3
		var inner := center + Vector2.from_angle(angle) * (radius + 9.0 * power)
		var outer := center + Vector2.from_angle(angle) * (radius + (18.0 if index % 2 == 0 else 13.0) * power)
		draw_line(inner, outer, _c("#ffd24f", alpha * 0.9), 2.0 * power, false)

func _spawn_particles() -> void:
	var particles := CPUParticles2D.new()
	particles.name = "FusionParticles_%s" % fusion_id
	particles.amount = 8 if mode in ["formation", "state"] else 4
	particles.lifetime = minf(lifetime, 0.48)
	particles.one_shot = true
	particles.explosiveness = 0.88
	particles.emitting = true
	particles.position = target_offset * 0.5 if mode in ["attack", "trail"] else target_offset
	particles.direction = Vector2.RIGHT
	particles.spread = 180.0
	particles.initial_velocity_min = 16.0 * intensity
	particles.initial_velocity_max = 42.0 * intensity
	particles.gravity = Vector2.ZERO
	particles.scale_amount_min = 0.7
	particles.scale_amount_max = 1.6
	particles.color = _with_alpha(_primary_color(), 0.78 if is_instance_valid(_pixel_sprite) else 1.0)
	add_child(particles)

func _primary_color() -> Color:
	return {
		"frostfire": Color("dffaff"), "plasma": Color("9f68ff"), "solar": Color("fff0a0"),
		"inferno": Color("c92c6d"), "superconductor": Color("a4f7ff"), "aurora": Color("9fffe0"),
		"void_frost": Color("7770d8"), "judgment": Color("ffe27d"), "voidstorm": Color("a653ff"),
		"eclipse": Color("ffd55a"),
	}.get(fusion_id, Color.WHITE)

func _secondary_color() -> Color:
	return {
		"frostfire": Color("ffad63"), "plasma": Color("86fbff"), "solar": Color("ffffff"),
		"inferno": Color("ff477e"), "superconductor": Color("ffffff"), "aurora": Color("ffb6df"),
		"void_frost": Color("b8e9ff"), "judgment": Color("fffde0"), "voidstorm": Color("d387ff"),
		"eclipse": Color("fff3b5"),
	}.get(fusion_id, Color.WHITE)

func _with_alpha(color: Color, alpha: float) -> Color:
	color.a = clampf(alpha, 0.0, 1.0)
	return color

func _c(hex: String, alpha: float) -> Color:
	var color := Color(hex)
	color.a = clampf(alpha, 0.0, 1.0)
	return color
