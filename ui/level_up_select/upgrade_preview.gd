extends Control
## レベルアップカードの「現在 → 強化後」比較場面。
##
## 各強化がゲーム内で実際に行う処理を、同じ数値・同じ色で小さく再現する。
## 参照元: entities/player/survival_upgrade_effects.gd(追撃/連鎖/結界/火花)、
## components/player_upgrades_component.gd(範囲/間隔/攻撃力/貫通)、
## systems/attack_patterns/melee_arc_attack.gd(扇の角度+12°/段)。
## 左右は同じ敵配置を使い、変わるのは強化段階だけにする。命中した敵だけが白く光り
## HPが減るので、「何体に当たるか」「何が増えるか」をそのまま数えられる。

const FrameArt := preload("res://ui/common/relic_frame_art.gd")
const SLASH: Texture2D = preload("res://assets/vfx/equipment_comfy/slash_6f.png")
const PERIOD := 1.6
const HIT_TIME := 0.30
const CAPTION_HEIGHT := 28.0
const BASE_COLOR := Color("d8d2c0")
const MUTED := Color("8d96a3")
## 以下3色はsurvival_upgrade_effects.gdのゲーム内描画と同じ値。
const ECHO_COLOR := Color("90ddff")
const SPARK_COLOR := Color("ffdf64")
const SHIELD_COLOR := Color(0.35, 0.85, 1.0, 0.7)
const ENEMY_HP := Color("c45d61")
const HERO_HP := Color("7fd88a")

var kind := "area"
var rank := 0
var accent := Color("79d7e8")
## arc(扇) / thrust(突き) / pulse(全周) / shot(弾)。職業の通常攻撃の形。
var attack_shape := "arc"
var base_half_angle := 55.0
var base_projectiles := 1
var base_interval := 1.0
## 職業技カードだけが使う。架空の動きは描かず、職業と技の図柄を段階付きで見せる。
var class_icon: Texture2D
## 秘技プレビュー用：実際の大技VFXシート（64px×6コマ）と段階ごとの同時発動数。
var arcana_sheet: Texture2D
var arcana_counts: Array = [1]
var arcana_unit := ""
var elapsed := 0.0
var _hero: Texture2D
var _enemy: Texture2D
## 毎フレームStyleBoxを作り直さないよう1度だけ作る。
var _inset_box: StyleBox = FrameArt.box(true, 0.0)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var character: CharacterData = DataLoader.characters.get(GameManager.selected_character_id)
	if character:
		_hero = SpriteSheetBuilder.build_portrait_texture(character.sprite_folder)
	_enemy = SpriteSheetBuilder.build_portrait_texture(DataLoader.enemies.slime.sprite_folder)

func _process(delta: float) -> void:
	if not is_visible_in_tree() or kind == "class":
		return
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	draw_style_box(_inset_box, Rect2(Vector2.ZERO, size))
	var half := size.x * 0.5
	draw_line(Vector2(half, 6.0), Vector2(half, size.y - 6.0), Color("343a46"), 1.0, false)
	_draw_arrow(Vector2(half, CAPTION_HEIGHT * 0.5 + 2.0))
	for side in 2:
		var after := side == 1
		var level := rank + (1 if after else 0)
		var origin := Vector2(half if after else 0.0, 0.0)
		var scene := Rect2(origin + Vector2(6.0, CAPTION_HEIGHT), Vector2(half - 12.0, size.y - CAPTION_HEIGHT - 6.0))
		var color := accent if after else BASE_COLOR
		_draw_caption(origin, half, _caption(level), accent if after else MUTED)
		match kind:
			"area": _draw_area(scene, level, after, color)
			"haste": _draw_haste(scene, level, color)
			"echo": _draw_echo(scene, level)
			"chain": _draw_chain(scene, level)
			"guard": _draw_guard(scene, level)
			"multishot": _draw_multishot(scene, level, color)
			"pierce": _draw_pierce(scene, level, color)
			"power": _draw_power(scene, level)
			"arcana": _draw_arcana(scene, level)
			_: _draw_class(scene, level, after)

# ---------------------------------------------------------------------------
# 数値の見出し。強化の実数値をそのまま出す(段階ごとの加算はゲーム側と同じ式)。

func _arcana_count(level: int) -> int:
	if level <= 0 or arcana_counts.is_empty():
		return 0
	return int(arcana_counts[clampi(level - 1, 0, arcana_counts.size() - 1)])

func _caption(level: int) -> String:
	if kind == "arcana":
		return "なし" if level <= 0 else "%s ×%d　Lv.%d" % [arcana_unit, _arcana_count(level), level]
	match kind:
		"area": return ("射程 %d%%" if attack_shape == "shot" else "範囲 %d%%") % (100 + 18 * level)
		"haste": return "間隔 %d%%" % (100 - 10 * level)
		"echo": return "追撃 %d%%" % (25 + 5 * level) if level > 0 else "追撃なし"
		"chain": return "連鎖 %d体" % level if level > 0 else "連鎖なし"
		"guard": return "シールド %d" % (8 * level) if level > 0 else "シールドなし"
		"multishot": return "弾数 %d本" % (base_projectiles + level)
		"pierce": return "命中 %d体" % (level + 1)
		"power": return "攻撃力 %d%%" % (100 + 8 * level)
		_: return "段階 %d" % level

func _draw_caption(origin: Vector2, width: float, text: String, color: Color) -> void:
	var font := RetroHUDStyle.retro_font()
	if font:
		draw_string(font, origin + Vector2(0.0, 21.0), text, HORIZONTAL_ALIGNMENT_CENTER, width, 18, color)

func _draw_arrow(center: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([center + Vector2(-3, -5), center + Vector2(4, 0), center + Vector2(-3, 5)]), accent)

# ---------------------------------------------------------------------------
# 各強化の場面

## 広域攻撃: 射程×(1+0.18×段)、扇は半角+12°/段。現在の範囲のすぐ外(横と奥)に
## 敵を1体ずつ置くので、強化後だけがその2体を巻き込む。
func _draw_area(scene: Rect2, level: int, after: bool, color: Color) -> void:
	var hero := _hero_anchor(scene)
	var range_after := 1.0 + 0.18 * (rank + 1)
	var room := scene.end.x - hero.x - 14.0
	var vertical := scene.size.y * 0.5 - 8.0
	if attack_shape == "pulse":
		room = minf(scene.size.x * 0.5 - 8.0, vertical)
	elif attack_shape == "arc":
		room = minf(room, vertical / maxf(sin(deg_to_rad(minf(_half_angle(rank + 1), 90.0))), 0.35))
	var unit := room / range_after
	var radius := unit * (1.0 + 0.18 * level)
	var radius_now := unit * (1.0 + 0.18 * rank)
	var radius_next := unit * range_after
	var half_now := _half_angle(rank)
	var half_next := _half_angle(rank + 1)
	var half := _half_angle(level)
	var targets: Array[Vector2] = []
	if attack_shape == "pulse":
		targets.append(hero + Vector2(radius_now * 0.55, 0.0))
		targets.append(hero + Vector2.from_angle(deg_to_rad(150.0)) * (radius_now + radius_next) * 0.5)
	elif attack_shape in ["thrust", "shot"]:
		targets.append(hero + Vector2(radius_now * 0.5, 0.0))
		targets.append(hero + Vector2(radius_now + (radius_next - radius_now) * 0.75, 0.0))
	else:
		targets.append(hero + Vector2(radius_now * 0.55, 0.0))
		targets.append(hero + Vector2.from_angle(deg_to_rad(minf((half_now + half_next) * 0.5, 82.0))) * radius_now * 0.62)
		targets.append(hero + Vector2.from_angle(deg_to_rad(-8.0)) * (radius_now + radius_next) * 0.5)
	var t := fmod(elapsed, PERIOD)
	_draw_reach(hero, radius, half, Color(color, 0.32))
	_draw_hero(hero, 0.0)
	_draw_strike(hero, radius, half, t, color, after)
	for target in targets:
		var offset := target - hero
		var inside := offset.length() <= radius + 0.5
		if attack_shape == "arc":
			inside = inside and absf(rad_to_deg(offset.angle())) <= half + 0.5
		_draw_enemy(target, 1.0 - (0.3 if inside and t >= HIT_TIME else 0.0), _flash(t, HIT_TIME) if inside else 0.0)

## 高速攻撃: 攻撃間隔×(1−0.1×段)。現在の間隔4回分を1周とし、同じ時間内に
## 何回攻撃できるかを下の時間軸に刻む(現在4回 → 強化後5回)。
func _draw_haste(scene: Rect2, level: int, color: Color) -> void:
	var hero := _hero_anchor(scene) + Vector2(0.0, -8.0)
	var target := hero + Vector2(52.0, 0.0)
	var interval := base_interval * (1.0 - 0.1 * level)
	var window := 4.0 * base_interval * (1.0 - 0.1 * rank)
	var sim := fmod(elapsed, 2.4) / 2.4 * window
	var last_hit := -INF
	var hits: Array[float] = []
	var k := 0
	while k * interval < window - 0.001:
		hits.append(k * interval)
		if k * interval <= sim:
			last_hit = k * interval
		k += 1
	var since := (sim - last_hit) / window * 2.4
	_draw_hero(hero, 0.0)
	if since < 0.16:
		_draw_strike_shape(hero, 46.0, 50.0, clampf(since / 0.12, 0.0, 1.0), color)
	_draw_enemy(target, 1.0, clampf(1.0 - since / 0.15, 0.0, 1.0))
	var y := scene.end.y - 8.0
	var x0 := scene.position.x + 8.0
	var x1 := scene.end.x - 8.0
	draw_line(Vector2(x0, y), Vector2(x1, y), Color("3a4250"), 2.0, false)
	for hit in hits:
		var x := lerpf(x0, x1, hit / window)
		draw_rect(Rect2(Vector2(x - 1.0, y - 5.0), Vector2(3.0, 10.0)), color if hit <= sim else Color(color, 0.35))
	draw_line(Vector2(lerpf(x0, x1, sim / window), y - 8.0), Vector2(lerpf(x0, x1, sim / window), y + 8.0), Color(1, 1, 1, 0.8), 1.0, false)

## 残影追撃: 直撃の0.18秒後、同じ敵へ影の斬撃(威力25%+5%×段)。
func _draw_echo(scene: Rect2, level: int) -> void:
	var hero := _hero_anchor(scene)
	var target := hero + Vector2(60.0, 0.0)
	var t := fmod(elapsed, PERIOD)
	var echo_time := HIT_TIME + 0.18
	var hp := 1.0
	if t >= HIT_TIME:
		hp -= 0.3
	if level > 0 and t >= echo_time:
		hp -= 0.3 * (0.25 + 0.05 * level)
	_draw_hero(hero, 0.0)
	_draw_strike(hero, target.x - hero.x + 8.0, 40.0, t, BASE_COLOR, false)
	_draw_enemy(target, hp, maxf(_flash(t, HIT_TIME), _flash(t, echo_time) if level > 0 else 0.0))
	if level > 0 and t >= echo_time and t < echo_time + 0.24:
		var frame := clampi(int((t - echo_time) / 0.24 * 6.0), 0, 5)
		var frame_width := SLASH.get_width() / 6.0
		var region := Rect2(Vector2(frame * frame_width, 0.0), Vector2(frame_width, SLASH.get_height()))
		for index in mini(level, 3):
			draw_texture_rect_region(SLASH, Rect2(target - Vector2(20.0 + index * 2.0, 20.0), Vector2(40.0, 40.0)), region, Color(ECHO_COLOR, 1.0 - index * 0.22))

## 雷光連鎖: 命中点から近い敵へ順に雷が渡る(段数=渡る体数、威力35%)。
func _draw_chain(scene: Rect2, level: int) -> void:
	var hero := _hero_anchor(scene)
	var first := hero + Vector2(44.0, 6.0)
	var targets: Array[Vector2] = [first, first + Vector2(22.0, -24.0), first + Vector2(42.0, 6.0), first + Vector2(62.0, -20.0)]
	var t := fmod(elapsed, PERIOD)
	_draw_hero(hero, 0.0)
	_draw_strike(hero, first.x - hero.x + 8.0, 40.0, t, BASE_COLOR, false)
	for index in targets.size():
		var hit_time := HIT_TIME + 0.08 * index
		var reached := index == 0 or index <= level
		var hp := 1.0
		if reached and t >= hit_time:
			hp -= 0.3 if index == 0 else 0.3 * 0.35
		_draw_enemy(targets[index], hp, _flash(t, hit_time) if reached else 0.0)
	for index in range(1, mini(level, 3) + 1):
		var hit_time := HIT_TIME + 0.08 * index
		if t < hit_time or t > hit_time + 0.24:
			continue
		var alpha := clampf((hit_time + 0.24 - t) / 0.12, 0.0, 1.0)
		var start := targets[index - 1]
		var end := targets[index]
		var mid := start.lerp(end, 0.5) + Vector2(3.0, -7.0)
		draw_polyline(PackedVector2Array([start, mid, mid + Vector2(-6.0, 5.0), end]), Color(SPARK_COLOR, alpha), 2.0, false)

## 再生結界: 8秒ごとに8×段のシールド。敵の一撃をシールドが受けるかを見せる。
func _draw_guard(scene: Rect2, level: int) -> void:
	var hero := _hero_anchor(scene) + Vector2(10.0, -4.0)
	var t := fmod(elapsed, PERIOD)
	var impact := 0.55
	var lunge := 0.0
	if t > 0.35 and t <= impact:
		lunge = (t - 0.35) / (impact - 0.35)
	elif t > impact and t < 0.9:
		lunge = 1.0 - (t - impact) / (0.9 - impact)
	var rest := Vector2(scene.end.x - 22.0, hero.y)
	var enemy := rest.lerp(hero + Vector2(36.0, 0.0), lunge)
	var flash := _flash(t, impact)
	var shield := 8 * level
	if shield > 0:
		_draw_hero(hero, 0.0)
		draw_arc(hero, 30.0, 0.0, TAU, 24, Color(SHIELD_COLOR, minf(1.0, SHIELD_COLOR.a + flash * 0.4)), 2.0 + flash * 2.0, false)
		var dots := 2 + level
		for index in dots:
			var p := hero + Vector2.from_angle(index * TAU / dots + elapsed * 1.2) * 30.0
			draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), Color("80e4ff"))
		var remaining := float(shield) - (8.0 if t >= impact else 0.0)
		_draw_bar(hero + Vector2(-16.0, 34.0), 32.0, clampf(remaining / 24.0, 0.0, 1.0), Color("59d9ff"))
		_draw_bar(hero + Vector2(-16.0, 39.0), 32.0, 1.0, HERO_HP)
	else:
		_draw_hero(hero, flash, Color(1.7, 0.55, 0.55))
		_draw_bar(hero + Vector2(-16.0, 34.0), 32.0, 0.82 if t >= impact else 1.0, HERO_HP)
	_draw_enemy(enemy, 1.0, 0.0)

## 多重射撃: 一度の発射が+1本/段。縦に並んだ敵へ1本ずつ当たる。
func _draw_multishot(scene: Rect2, level: int, color: Color) -> void:
	var hero := _hero_anchor(scene)
	var column_x := scene.end.x - 16.0
	var slots := base_projectiles + rank + 1
	var spacing := minf(30.0, (scene.size.y - 20.0) / maxf(slots, 1))
	var t := fmod(elapsed, PERIOD)
	var shots := base_projectiles + level
	_draw_hero(hero, 0.0)
	for index in slots:
		var target := Vector2(column_x, hero.y + (index - (slots - 1) * 0.5) * spacing)
		var shot := index < shots
		if shot and t >= 0.12 and t < HIT_TIME:
			var p := hero.lerp(target, (t - 0.12) / (HIT_TIME - 0.12))
			var direction := (target - hero).normalized()
			draw_line(p - direction * 9.0, p, color, 2.0, false)
		_draw_enemy(target, 0.7 if shot and t >= HIT_TIME else 1.0, _flash(t, HIT_TIME) if shot else 0.0)

## 貫通射撃: 弾は「段+1」体に当たってから消える(projectile.gdのpierce_remaining)。
func _draw_pierce(scene: Rect2, level: int, color: Color) -> void:
	var hero := _hero_anchor(scene)
	var hits := level + 1
	var targets: Array[Vector2] = []
	for index in 4:
		targets.append(hero + Vector2(38.0 + index * 25.0, 0.0))
	var t := fmod(elapsed, PERIOD)
	var start := 0.12
	var step := 0.07
	_draw_hero(hero, 0.0)
	var stop := targets[hits - 1]
	var travel_end := start + step * hits
	if t >= start and t < travel_end:
		var p := hero.lerp(stop, (t - start) / (travel_end - start))
		draw_line(p - Vector2(10.0, 0.0), p, color, 2.0, false)
		draw_rect(Rect2(p - Vector2(1.0, 2.0), Vector2(4.0, 4.0)), color.lightened(0.35))
	for index in targets.size():
		var hit_time := start + step * (index + 1)
		var hit := index < hits
		_draw_enemy(targets[index], 0.7 if hit and t >= hit_time else 1.0, _flash(t, hit_time) if hit else 0.0, 20.0)

## 強撃: 攻撃力+8%/段、命中の火花の半径は10+2.5×段(段0では火花なし)。
func _draw_power(scene: Rect2, level: int) -> void:
	var hero := _hero_anchor(scene)
	var target := hero + Vector2(60.0, 0.0)
	var t := fmod(elapsed, PERIOD)
	_draw_hero(hero, 0.0)
	_draw_strike(hero, target.x - hero.x + 8.0, 40.0, t, BASE_COLOR, false)
	_draw_enemy(target, 1.0 - (0.3 * (1.0 + 0.08 * level) if t >= HIT_TIME else 0.0), _flash(t, HIT_TIME))
	if level > 0 and t >= HIT_TIME and t < HIT_TIME + 0.2:
		var alpha := clampf((HIT_TIME + 0.2 - t) / 0.12, 0.0, 1.0)
		var radius := minf(10.0 + level * 2.5, 26.0)
		for index in 6:
			var direction := Vector2.from_angle(index * TAU / 6.0)
			draw_line(target + direction * 4.0, target + direction * radius, Color(SPARK_COLOR, alpha), 2.0, false)

## 職業技: 段階ごとの効果は職業ごとに異なるため動く場面は作らず、職業と技の図柄を
## 段階付きで並べる(実際と異なる動きを見せないため)。強化後側だけ図柄を明るく出す。
## 秘技：敵の群れに実際のVFXを段階ごとの数だけ落として見せる。0段階は敵だけ。
func _draw_arcana(scene: Rect2, level: int) -> void:
	var spots := [Vector2(0.30, 0.42), Vector2(0.70, 0.40), Vector2(0.50, 0.72), Vector2(0.22, 0.78)]
	var count := _arcana_count(level)
	var cycle := fmod(elapsed, 1.6)
	for index in spots.size():
		var at: Vector2 = scene.position + scene.size * spots[index]
		var hit := index < count
		var strike_t := cycle - index * 0.12
		_draw_enemy(at + Vector2(0, 10), 0.35 if hit and strike_t > 0.25 else 1.0, _flash(strike_t, 0.25) if hit else 0.0)
	if arcana_sheet == null:
		return
	var frame_w := arcana_sheet.get_width() / 6.0
	for index in count:
		var at: Vector2 = scene.position + scene.size * spots[index]
		var strike_t := cycle - index * 0.12
		if strike_t < 0.0 or strike_t > 0.9:
			continue
		var frame := clampi(int(strike_t / 0.15), 0, 5)
		var draw_size := 72.0
		draw_texture_rect_region(arcana_sheet, Rect2(at - Vector2(draw_size * 0.5, draw_size * 0.75), Vector2(draw_size, draw_size)), Rect2(frame * frame_w, 0, frame_w, arcana_sheet.get_height()))

func _draw_class(scene: Rect2, _level: int, after: bool) -> void:
	var center := scene.get_center() + Vector2(0.0, 4.0)
	_draw_hero(center + Vector2(-22.0, 10.0), 0.0)
	if class_icon:
		var icon_size := Vector2(40.0, 40.0)
		draw_texture_rect(class_icon, Rect2(center + Vector2(4.0, -16.0), icon_size), false, Color(1, 1, 1, 1.0 if after else 0.4))

# ---------------------------------------------------------------------------
# 共通描画

## 攻撃が届く範囲の境界。扇は弧、全周は円、弾と突きは到達点の縦線。
func _draw_reach(hero: Vector2, reach: float, half_angle: float, color: Color) -> void:
	match attack_shape:
		"pulse":
			draw_arc(hero, reach, 0.0, TAU, 32, color, 1.0, false)
		"thrust", "shot":
			for y in range(-14, 15, 4):
				draw_line(Vector2(hero.x + reach, hero.y + y), Vector2(hero.x + reach, hero.y + y + 2.0), color, 1.0, false)
		_:
			draw_arc(hero, reach, deg_to_rad(-half_angle), deg_to_rad(half_angle), 20, color, 1.0, false)

func _half_angle(level: int) -> float:
	return base_half_angle + 12.0 * level

func _hero_anchor(scene: Rect2) -> Vector2:
	var x := scene.get_center().x if kind == "area" and attack_shape == "pulse" else scene.position.x + 26.0
	return Vector2(x, scene.get_center().y + 4.0)

## 職業の通常攻撃をtの進行に合わせて描く。命中はHIT_TIME。
func _draw_strike(hero: Vector2, reach: float, half_angle: float, t: float, color: Color, emphasize: bool) -> void:
	if t < 0.14 or t > 0.46:
		return
	var progress := clampf((t - 0.14) / (HIT_TIME - 0.14), 0.0, 1.0)
	var fade := clampf((0.46 - t) / 0.16, 0.0, 1.0)
	_draw_strike_shape(hero, reach, half_angle, progress, Color(color, color.a * fade), emphasize)

func _draw_strike_shape(hero: Vector2, reach: float, half_angle: float, progress: float, color: Color, emphasize: bool = false) -> void:
	var width := 3.0 if emphasize else 2.0
	match attack_shape:
		"pulse":
			draw_arc(hero, reach * progress, 0.0, TAU, 28, color, width, false)
		"thrust":
			draw_line(hero, hero + Vector2(reach * progress, 0.0), color, width + 1.0, false)
		"shot":
			var p := hero + Vector2(reach * progress, 0.0)
			draw_line(p - Vector2(10.0, 0.0), p, color, 2.0, false)
			draw_rect(Rect2(p - Vector2(1.0, 2.0), Vector2(4.0, 4.0)), color.lightened(0.3))
		_:
			var start := deg_to_rad(-half_angle)
			var sweep := start + deg_to_rad(half_angle * 2.0) * progress
			var points := PackedVector2Array([hero])
			var steps := 12
			for index in steps + 1:
				points.append(hero + Vector2.from_angle(lerpf(start, sweep, float(index) / steps)) * reach)
			if points.size() >= 3:
				draw_colored_polygon(points, Color(color, color.a * 0.16))
			draw_arc(hero, reach, start, sweep, 16, color, width, false)

func _draw_hero(center: Vector2, flash: float, flash_tint: Color = Color(1.8, 1.8, 1.8)) -> void:
	draw_rect(Rect2(center + Vector2(-12.0, 18.0), Vector2(24.0, 3.0)), Color(0, 0, 0, 0.35))
	if _hero == null:
		draw_rect(Rect2(center - Vector2(7.0, 15.0), Vector2(14.0, 30.0)), Color("dfdfcc"))
		return
	var draw_size := _fit(_hero, 40.0)
	var tint := Color.WHITE.lerp(flash_tint, clampf(flash, 0.0, 1.0))
	draw_texture_rect(_hero, Rect2(center - draw_size * 0.5, draw_size), false, tint)

func _draw_enemy(center: Vector2, hp: float, flash: float, longest: float = 26.0) -> void:
	var top := -10.0
	if _enemy:
		var draw_size := _fit_longest(_enemy, longest)
		var tint := Color.WHITE.lerp(Color(2.2, 2.2, 2.2), clampf(flash, 0.0, 1.0))
		draw_texture_rect(_enemy, Rect2(center - draw_size * 0.5, draw_size), false, tint)
		top = -draw_size.y * 0.5
	else:
		draw_rect(Rect2(center - Vector2(8, 8), Vector2(16, 16)), Color("6fb36a"))
	var bar_width := minf(22.0, longest - 4.0)
	_draw_bar(center + Vector2(-bar_width * 0.5, top - 6.0), bar_width, hp, ENEMY_HP)

func _draw_bar(at: Vector2, width: float, ratio: float, color: Color) -> void:
	draw_rect(Rect2(at, Vector2(width, 3.0)), Color("1c1f26"))
	draw_rect(Rect2(at, Vector2(width * clampf(ratio, 0.0, 1.0), 3.0)), color)

## 拡大は整数倍に揃えてドットを崩さない。縮小が必要な場合だけ実数倍にする。
func _fit(texture: Texture2D, height: float) -> Vector2:
	var source := texture.get_size()
	if source.y <= 0.0:
		return Vector2(height, height)
	var scale_factor := height / source.y
	if scale_factor >= 1.0:
		scale_factor = maxf(1.0, roundf(scale_factor))
	return source * scale_factor

## 敵は元絵が横長なので長辺で合わせる(高さ基準だと横幅が主人公より大きくなる)。
## 複数体を並べる場面で枠からはみ出さないことを優先し、実数倍を許す。
func _fit_longest(texture: Texture2D, longest: float) -> Vector2:
	var source := texture.get_size()
	var edge := maxf(source.x, source.y)
	if edge <= 0.0:
		return Vector2(longest, longest)
	return source * (longest / edge)

func _flash(t: float, hit_time: float) -> float:
	if t < hit_time:
		return 0.0
	return clampf(1.0 - (t - hit_time) / 0.15, 0.0, 1.0)
