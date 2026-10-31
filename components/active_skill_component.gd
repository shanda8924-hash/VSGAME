extends Node
class_name ActiveSkillComponent
## active_skillアクション(Space/ゲームパッド南ボタン)で発動する職業固有
## アクティブスキル。通常攻撃(WeaponManagerComponentの自動攻撃)とは完全に
## 独立しており、そちらは今まで通り動作し続ける。
##
## 【能動発動スキル(2026年8月試験実装、Swordsmanのみ)】
## 19.9の職業スキル流派分岐(school)と連動する形で、Swordsmanのactive_skill_id
## ("swordsman_iai")だけは発動可能回数(チャージ)をschoolで出し分ける。将来的に
## 全職業のLv.5奥義へこの仕組みを展開する前提のため、「characterごとに
## _try_activate_*()を用意してtry_activate()から分岐する」「_cooldown()も
## character/schoolで分岐できる」形にしておき、他職業を追加する際もこの
## ファイルの中だけで完結できるようにしている。
##
## 【重要】「居合」の技自体(モーション・当たり判定・ダメージ計算、
## _swordsman_iai())は、schoolに関わらず常に同じものを使う(変更しない)。
## schoolが変えるのは「1回のクールダウンサイクルで何回連続して発動できるか」
## というチャージ数だけ:
##   - school未確定(Lv1)/一閃派: max_charges = 1(1回発動したら即クールダウンへ)
##   - 乱撃派: max_charges = 2(1回目発動直後にもう一度押せば、間を置かず
##     2回目の同じ居合が発動する。2回使い切った時点でクールダウン開始)
## 一閃派だけは技そのものが異なる(確定クリティカルの一撃、_swordsman_issen_strike())。
## クールダウン終了時にチャージは最大値まで自動的に回復する。
##
## 【乱撃派のコンボキャンセル(2026年8月追加)】1回目の居合が完全に終わるのを
## 待たずに2回目を繋げられるよう、_swordsman_iai()のダッシュモーション内に
## キャンセル可能ポイント(全体の60〜70%地点、ダメージ判定発生直後)を設けている。
## この地点で2チャージ目が既に控えていれば、1回目の残りの硬直モーションを
## 打ち切って即座に2回目の居合へ引き継ぐ(対象は乱撃派のチャージ連携のみ)。

signal skill_configured(display_name: String, icon_text: String, cooldown: float, color: Color)
signal cooldown_changed(remaining: float, total: float)
signal skill_became_ready
signal skill_activated

const ALLY_SCENE := preload("res://entities/allies/ally_skeleton.tscn")
const PROJECTILE_SCENE := preload("res://entities/projectiles/projectile.tscn")
const VFX_SCRIPT := preload("res://effects/active_skill_vfx.gd")
const AFTERIMAGE_SCRIPT := preload("res://effects/character_afterimage.gd")

## 乱撃派のみmax_charges=2(それ以外のschool/他職業は常に1)。
const RENGEKI_MAX_CHARGES := 2
const DEFAULT_MAX_CHARGES := 1
const ISSEN_STRIKE_RADIUS := 100.0
const ISSEN_STRIKE_HALF_ANGLE := 62.0
const ISSEN_STRIKE_KNOCKBACK := 55.0

## 乱撃派/一閃派それぞれの能動発動専用クールダウン(@exportで調整可能)。
## 職業固有のactive_skill_cooldown(JSON、6.0秒=school未確定時の居合用)とは別枠。
@export var rengeki_cooldown: float = 5.0
@export var issen_cooldown: float = 7.0
## 一閃派の能動発動ダメージ倍率(通常の近接攻撃基準に対して)。
@export var issen_damage_multiplier: float = 1.65

var character_data: CharacterData
var cooldown_remaining: float = 0.0
var _was_ready: bool = true
var _guard_active := false
var _guard_countered := false
## Swordsmanのチャージ制(乱撃派/一閃派/school未確定)用。今のクールダウン
## サイクルで既に使ったチャージ数。cooldown_remaining<=0の間だけ消費でき、
## max_charges分使い切った瞬間にクールダウンが始まる。
var _swordsman_charges_used: int = 0
## _swordsman_iai()は複数フレームにまたがる非同期処理(ダッシュ演出)のため、
## 乱撃派の2チャージ目が1チャージ目の演出中に押された場合でも、2つの居合が
## 同時に動いて移動ロック/無敵状態を奪い合わないよう、順番に実行するキューにする。
var _swordsman_iai_pending: int = 0
var _swordsman_iai_running: bool = false
var _dodge_cancel_epoch := 0

@onready var player: Player = get_parent() as Player

func _ready() -> void:
	character_data = DataLoader.characters.get(GameManager.selected_character_id)
	call_deferred("_connect_player_health")
	call_deferred("_emit_configuration")

func _connect_player_health() -> void:
	if player and player.health_component and not player.health_component.damaged.is_connected(_on_player_damaged):
		player.health_component.damaged.connect(_on_player_damaged)

func _process(delta: float) -> void:
	if cooldown_remaining <= 0.0:
		return
	cooldown_remaining = maxf(0.0, cooldown_remaining - delta)
	cooldown_changed.emit(cooldown_remaining, _cooldown())
	if cooldown_remaining <= 0.0 and not _was_ready:
		_was_ready = true
		skill_became_ready.emit()

func _emit_configuration() -> void:
	if character_data == null:
		return
	skill_configured.emit(character_data.active_skill_name, character_data.active_skill_icon, _cooldown(), _skill_color())
	cooldown_changed.emit(0.0, _cooldown())

func try_activate() -> bool:
	if character_data == null or character_data.active_skill_id == "":
		return false
	if character_data.id == "swordsman":
		return _try_activate_swordsman()
	if cooldown_remaining > 0.0:
		return false
	if not _execute_skill(character_data.active_skill_id):
		return false
	_start_cooldown()
	return true

func _get_school() -> String:
	if player == null or player.weapon_manager == null:
		return "none"
	return player.weapon_manager.get_class_school()

## 演出・アニメーション・クールダウン開始をまとめた共通処理。従来の
## try_activate()末尾にあった内容をそのまま切り出したもの(school分岐後も
## 同じ演出を再利用するため)。
func _start_cooldown() -> void:
	cooldown_remaining = _cooldown()
	_was_ready = false
	cooldown_changed.emit(cooldown_remaining, _cooldown())
	skill_activated.emit()
	if player.animation_component:
		player.animation_component.play_attack(randi_range(1, 3))
	var screen_effects := player.get_tree().get_first_node_in_group("screen_effects") as ScreenEffects
	if screen_effects:
		screen_effects.shake(7.0, 0.22)
		screen_effects.hit_stop(0.08)

## Swordsmanのチャージ制発動。school(none/rengeki/issen)でmax_chargesと
## 発動する技だけが変わり、居合の技自体(_swordsman_iai())は共通のまま。
func _try_activate_swordsman() -> bool:
	if cooldown_remaining > 0.0:
		return false
	var school := _get_school()
	var max_charges := RENGEKI_MAX_CHARGES if school == "rengeki" else DEFAULT_MAX_CHARGES
	_swordsman_charges_used += 1
	var is_final_charge := _swordsman_charges_used >= max_charges
	if is_final_charge:
		_swordsman_charges_used = 0
		_start_cooldown()
	else:
		# まだチャージが残っている: クールダウンには入らず、演出だけ再生する
		# (「間を置かず2回目の居合が発動する」を満たすため、ここではまだ待たない)。
		skill_activated.emit()
		if player.animation_component:
			player.animation_component.play_attack(randi_range(1, 3))
	if school == "issen":
		_swordsman_issen_strike()
	else:
		_queue_swordsman_iai()
	return true

## _swordsman_iai()は複数フレームにまたがる非同期処理のため、前の発動が
## まだ終わっていない間に次のチャージが消費された場合は、キューに積んで
## 前の完了を待ってから順番に実行する(同時に2つ動いて移動ロック/無敵状態を
## 奪い合う事故を防ぐ)。
func _queue_swordsman_iai() -> void:
	_swordsman_iai_pending += 1
	if _swordsman_iai_running:
		return
	_run_swordsman_iai_queue()

func _run_swordsman_iai_queue() -> void:
	_swordsman_iai_running = true
	while _swordsman_iai_pending > 0:
		_swordsman_iai_pending -= 1
		await _swordsman_iai()
	_swordsman_iai_running = false

func _swordsman_issen_strike() -> void:
	_cone_attack(ISSEN_STRIKE_RADIUS, ISSEN_STRIKE_HALF_ANGLE, _melee_multiplier_to_base_ratio(issen_damage_multiplier), ISSEN_STRIKE_KNOCKBACK, true)

## _cone_attack()系ヘルパーは_base_damage()(character_data.base_damageそのまま、
## 強化オプション等のスケーリング無し)を基準にしているが、能動発動スキルは
## 通常の近接攻撃(_melee_skill_base_damage()、強化オプション込み)と地続きの
## 強さであるべきなので、比率へ変換してから既存ヘルパーへ渡す。
func _melee_multiplier_to_base_ratio(multiplier: float) -> float:
	var melee_damage := _melee_skill_base_damage() * multiplier
	return melee_damage / _base_damage()

func _execute_skill(skill_id: String) -> bool:
	match skill_id:
		"soldier_war_cry": _soldier_war_cry()
		"swordsman_iai": _swordsman_iai()
		"archer_arrow_rain": _archer_arrow_rain()
		"lancer_cavalry_charge": _lancer_cavalry_charge()
		"knight_perfect_guard": _knight_perfect_guard()
		"axeman_execution": _axeman_execution()
		"priest_sanctuary": _priest_sanctuary()
		"templar_holy_chains": _templar_holy_chains()
		"wizard_time_freeze": _wizard_time_freeze()
		"necromancer_raise_dead": _necromancer_raise_dead()
		_:
			return false
	return true

func _param(key: String, fallback: float) -> float:
	return float(character_data.active_skill_params.get(key, fallback))

func _soldier_war_cry() -> void:
	var duration := _param("duration", 5.0)
	player.weapon_manager.active_skill_interval_multiplier = _param("attack_interval_multiplier", 0.6)
	player.movement_component.bonus_speed_multiplier *= _param("move_speed_multiplier", 1.35)
	_spawn_vfx(150.0, 180.0, "aura")
	await player.get_tree().create_timer(duration).timeout
	if is_instance_valid(player):
		player.weapon_manager.active_skill_interval_multiplier = 1.0
		player.movement_component.bonus_speed_multiplier /= _param("move_speed_multiplier", 1.35)

## 乱撃派の2チャージ目コンボキャンセル(2026年8月追加)向け: モーション
## 全体のうち、これ以降ならキャンセル可能とみなす比率(60〜70%目安)。
## dash_steps(既定10)に対しceil(10*0.65)=7 → 0始まりでstep index 6、
## つまり全10ステップ中7ステップ目(70%)完了時点からキャンセル可能になる。
const IAI_CANCEL_POINT_RATIO := 0.65

## 「居合」の技自体(モーション・当たり判定・ダメージ計算)。schoolに関わらず
## 常にこの関数を使う(19.9/19.10参照、school分岐が変えるのはチャージ数だけ)。
##
## 乱撃派の2チャージ目コンボキャンセル: ダッシュのステップループがキャンセル
## 可能ポイント(IAI_CANCEL_POINT_RATIO、ダメージ判定発生直後)に達した時点で、
## 次のチャージが既に控えている(_swordsman_iai_pending > 0)場合は、残りの
## 硬直モーションを打ち切ってここで即return する。呼び出し元の
## _run_swordsman_iai_queue()がawaitからすぐ復帰し、間を置かず次の
## _swordsman_iai()を開始する(1回目のダメージ判定はキャンセル前の各ステップで
## 既に適用済みのため、打ち切ってもダメージが失われることはない)。この場合は
## 移動ロック/無敵状態の解除も行わない(次の居合へそのまま引き継ぐことで、
## 2回の居合の間に一瞬だけ無敵が切れる、といった隙間を作らないため)。
## チャージが残っていない(school未確定/一閃派、または既に使い切っている)
## 場合はこれまで通り最後まで通常再生する。
func cancel_for_dodge() -> void:
	_dodge_cancel_epoch += 1
	_swordsman_iai_pending = 0
	if player and player._movement_locked_by_attack and _swordsman_iai_running:
		player.health_component.invincible = false
		player.set_movement_locked(false)

func _swordsman_iai() -> void:
	var epoch := _dodge_cancel_epoch
	var direction := player.get_facing_direction()
	var distance := _param("dash_distance", 280.0)
	var half_width := _param("half_width", 38.0)
	var damage := _melee_skill_base_damage() * _param("damage_multiplier", 4.8)
	player.set_movement_locked(true)
	player.health_component.invincible = true
	await player.get_tree().create_timer(_param("windup", 0.16)).timeout
	if not is_instance_valid(player) or epoch != _dodge_cancel_epoch:
		return
	# 扇状Polygonは使わず、実移動区間の細いTrail・残像・Hitだけで居合を見せる。
	var hit_enemies: Dictionary = {}
	var collision_exceptions: Array[CollisionObject2D] = []
	var steps := maxi(int(_param("dash_steps", 10.0)), 1)
	var cancel_step_index := int(ceil(float(steps) * IAI_CANCEL_POINT_RATIO)) - 1
	var was_combo_cancelled := false
	for step in steps:
		if not is_instance_valid(player) or epoch != _dodge_cancel_epoch:
			break
		var segment_start := player.global_position
		_spawn_iai_afterimage()
		var reached_full_segment := _move_iai_segment(direction * distance / float(steps), collision_exceptions)
		_damage_iai_segment(segment_start, player.global_position, half_width, damage, hit_enemies)
		if not reached_full_segment:
			break
		if step >= cancel_step_index and _swordsman_iai_pending > 0:
			was_combo_cancelled = true
			break
		await player.get_tree().create_timer(0.025).timeout
	for enemy_body in collision_exceptions:
		if is_instance_valid(enemy_body):
			player.remove_collision_exception_with(enemy_body)
	if was_combo_cancelled or epoch != _dodge_cancel_epoch:
		return
	player.health_component.invincible = false
	player.set_movement_locked(false)
	_spawn_iai_afterimage()

func _spawn_iai_afterimage() -> void:
	var afterimage := AFTERIMAGE_SCRIPT.new() as CharacterAfterimage
	GameManager.get_runtime_world(player).add_child(afterimage)
	var alpha := clampf(_param("afterimage_alpha", 0.48), 0.0, 1.0)
	var base_color := Color(0.18, 0.32, 0.58, 1.0)
	var tint := Color(base_color.r, base_color.g, base_color.b, alpha)
	afterimage.setup(player.animated_sprite, tint, _param("afterimage_lifetime", 0.28))


func _move_iai_segment(motion: Vector2, collision_exceptions: Array[CollisionObject2D]) -> bool:
	var remaining := motion
	for attempt in 8:
		if remaining.length_squared() <= 0.01:
			return true
		var collision := player.move_and_collide(remaining)
		if collision == null:
			return true
		var collider := collision.get_collider() as CollisionObject2D
		if collider is EnemyBasic:
			if not collision_exceptions.has(collider):
				collision_exceptions.append(collider)
				player.add_collision_exception_with(collider)
			remaining = collision.get_remainder()
			continue
		return false
	return false

func _damage_iai_segment(segment_start: Vector2, segment_end: Vector2, half_width: float, amount: float, hit_enemies: Dictionary) -> void:
	var segment := segment_end - segment_start
	var length_squared := segment.length_squared()
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or hit_enemies.has(enemy.get_instance_id()):
			continue
		var t := 0.0
		if length_squared > 0.0:
			t = clampf((enemy.global_position - segment_start).dot(segment) / length_squared, 0.0, 1.0)
		var closest := segment_start + segment * t
		if closest.distance_to(enemy.global_position) <= half_width:
			hit_enemies[enemy.get_instance_id()] = true
			_damage_enemy(enemy, amount, 20.0)

func _archer_arrow_rain() -> void:
	var center := player.global_position + player.get_facing_direction() * _param("forward_offset", 170.0)
	var radius := _param("range", 175.0)
	_spawn_vfx_at(center, radius, "rain")
	for tick in int(_param("ticks", 6.0)):
		await player.get_tree().create_timer(_param("tick_interval", 0.45)).timeout
		_damage_circle_at(center, radius, _base_damage() * _param("damage_multiplier", 1.15), 12.0)

func _lancer_cavalry_charge() -> void:
	var direction := player.get_facing_direction()
	var distance := _param("dash_distance", 430.0)
	player.health_component.invincible = true
	_spawn_vfx(distance * 0.55, 10.0, "charge")
	var hit: Dictionary = {}
	for step in 10:
		player.move_and_collide(direction * distance / 10.0)
		for enemy in _enemies_in_radius(_param("hit_radius", 62.0)):
			if not hit.has(enemy):
				hit[enemy] = true
				_damage_enemy(enemy, _base_damage() * _param("damage_multiplier", 4.0), 95.0)
		await player.get_tree().create_timer(0.025).timeout
	player.health_component.invincible = false
	_spawn_vfx(90.0, 180.0, "impact")

func _knight_perfect_guard() -> void:
	_guard_active = true
	_guard_countered = false
	player.health_component.active_skill_damage_multiplier = _param("damage_taken_multiplier", 0.05)
	_spawn_vfx(105.0, 180.0, "shield")
	await player.get_tree().create_timer(_param("duration", 2.0)).timeout
	if is_instance_valid(player):
		_guard_active = false
		player.health_component.active_skill_damage_multiplier = 1.0

func _on_player_damaged(_amount: float, _current: float, _maximum: float) -> void:
	if not _guard_active or _guard_countered:
		return
	_guard_countered = true
	_circle_attack(_param("counter_range", 155.0), _param("counter_multiplier", 5.0), 120.0, "counter")

func _axeman_execution() -> void:
	var target: Node = null
	var highest_hp := -1.0
	for enemy in _enemies_in_radius(_param("range", 230.0)):
		var health: HealthComponent = enemy.get_node_or_null("HealthComponent")
		if health and health.current_hp > highest_hp:
			target = enemy
			highest_hp = health.current_hp
	if target == null: return
	_spawn_vfx_at(target.global_position, 90.0, "execution")
	await player.get_tree().create_timer(_param("windup", 0.45)).timeout
	if not is_instance_valid(target): return
	var health: HealthComponent = target.get_node_or_null("HealthComponent")
	var amount := _base_damage() * _param("damage_multiplier", 7.0)
	if health and not (target.enemy_data is BossData) and health.current_hp / health.max_hp <= _param("execute_threshold", 0.25):
		amount = health.current_hp
	_damage_enemy(target, amount, 40.0)

func _priest_sanctuary() -> void:
	var center := player.global_position
	var radius := _param("range", 175.0)
	_spawn_vfx_at(center, radius, "sanctuary")
	for tick in int(_param("ticks", 6.0)):
		player.health_component.heal(player.health_component.max_hp * _param("heal_percent_per_tick", 0.035))
		_damage_circle_at(center, radius, _base_damage() * _param("damage_multiplier", 0.8), 8.0)
		await player.get_tree().create_timer(_param("tick_interval", 0.75)).timeout

func _templar_holy_chains() -> void:
	var radius := _param("range", 230.0)
	_spawn_vfx(radius, 180.0, "chains")
	for enemy in _enemies_in_radius(radius):
		var toward: Vector2 = (player.global_position - enemy.global_position).normalized()
		if enemy.has_method("apply_knockback"): enemy.apply_knockback(toward, _param("pull_distance", 95.0))
	await player.get_tree().create_timer(_param("delay", 0.55)).timeout
	_circle_attack(155.0, _param("damage_multiplier", 3.8), 70.0, "holy_burst")

func _wizard_time_freeze() -> void:
	var affected := _enemies_in_radius(_param("range", 280.0))
	_spawn_vfx(_param("range", 280.0), 180.0, "time")
	for enemy in affected:
		enemy.movement_component.bonus_speed_multiplier = _param("boss_slow", 0.25) if enemy.enemy_data is BossData else 0.0
	await player.get_tree().create_timer(_param("duration", 2.0)).timeout
	for enemy in affected:
		if is_instance_valid(enemy):
			enemy.movement_component.bonus_speed_multiplier = 1.0
			_damage_enemy(enemy, _base_damage() * _param("burst_multiplier", 2.4), 25.0)

func _necromancer_raise_dead() -> void:
	_summon_empowered_minions(int(_param("summon_count", 3.0)), _param("duration", 18.0))

func _base_damage() -> float:
	var damage := maxf(character_data.base_damage, 1.0)
	var stat_modifier: StatModifierComponent = player.get_node_or_null("StatModifierComponent")
	if stat_modifier:
		damage += stat_modifier.get_damage_flat_bonus()
	var upgrades: PlayerUpgradesComponent = player.get_node_or_null("PlayerUpgradesComponent")
	if upgrades:
		damage += upgrades.equipment_attack_flat
	return damage

## 居合は近接通常攻撃と同じ成長軸を使う。固有倍率4.8はこの値へ最後に掛ける。
func _melee_skill_base_damage() -> float:
	var damage := _base_damage()
	var upgrades: PlayerUpgradesComponent = player.get_node_or_null("PlayerUpgradesComponent")
	if upgrades:
		damage *= upgrades.damage_multiplier * upgrades.get_equipment_conditional_damage_multiplier()
		damage *= upgrades.melee_damage_multiplier
	return damage

func _cone_attack(radius: float, half_angle: float, multiplier: float, knockback: float, is_critical: bool = false) -> void:
	var facing := player.get_facing_direction()
	for enemy in _enemies_in_radius(radius):
		var direction: Vector2 = enemy.global_position - player.global_position
		if direction != Vector2.ZERO and rad_to_deg(absf(facing.angle_to(direction.normalized()))) <= half_angle:
			_damage_enemy(enemy, _base_damage() * multiplier, knockback, is_critical)
	_spawn_vfx(radius, half_angle)

func _circle_attack(radius: float, multiplier: float, knockback: float, style: String = "burst") -> void:
	for enemy in _enemies_in_radius(radius):
		_damage_enemy(enemy, _base_damage() * multiplier, knockback)
	_spawn_vfx(radius, 180.0, style)

func _line_attack(length: float, half_width: float, multiplier: float, knockback: float, show_vfx: bool = true) -> void:
	var facing := player.get_facing_direction()
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var offset: Vector2 = enemy.global_position - player.global_position
		var forward := offset.dot(facing)
		var side := absf(offset.cross(facing))
		if forward >= 0.0 and forward <= length and side <= half_width:
			_damage_enemy(enemy, _base_damage() * multiplier, knockback)
	if show_vfx:
		_spawn_vfx(length * 0.55, 18.0, "charge")

func _swordsman_flurry() -> void:
	# HealthComponentの被弾iframeと競合しないよう、ダメージは連斬の総量を
	# 初段で一括適用し、後続2段は斬撃VFXとして見せる。
	_cone_attack(170.0, 72.0, 5.4, 80.0)
	await player.get_tree().create_timer(0.10).timeout
	if is_instance_valid(player):
		_spawn_vfx(155.0, 65.0)
	await player.get_tree().create_timer(0.10).timeout
	if is_instance_valid(player):
		_spawn_vfx(170.0, 72.0)

func _arrow_storm() -> void:
	var manager := player.weapon_manager
	var data := WeaponData.new()
	data.projectile_scene = PROJECTILE_SCENE
	# Projectile側でレベル/装備固定攻撃力を足すため、ここでは職業基礎値だけを倍率化する。
	data.base_damage = maxf(character_data.base_damage, 10.0) * 2.0
	data.attack_range = 560.0
	data.crit_chance = character_data.crit_chance
	data.crit_multiplier = character_data.crit_multiplier
	var facing := player.get_facing_direction()
	for i in 9:
		var angle := deg_to_rad(lerpf(-42.0, 42.0, float(i) / 8.0))
		manager.spawn_projectile(data, player.global_position, player.global_position + facing.rotated(angle) * 560.0, i == 0)
	_spawn_vfx(190.0, 50.0)

func _summon_empowered_minions(count: int = 2, lifetime: float = 18.0) -> void:
	var params := character_data.attack_pattern_params
	for i in count:
		var ally := ALLY_SCENE.instantiate()
		GameManager.get_runtime_world(player).add_child(ally)
		ally.setup(
			float(params.get("minion_hp", 40.0)) * character_data.minion_stat_multiplier * 2.0,
			float(params.get("minion_speed", 110.0)) * 1.15,
			float(params.get("minion_damage", 8.0)) * character_data.minion_stat_multiplier * 2.2,
			String(params.get("minion_sprite_folder", "enemy/Skeleton")),
			lifetime
		)
		ally.global_position = player.global_position + Vector2.from_angle(TAU * float(i) / float(maxi(count, 1))) * 48.0
	_spawn_vfx(150.0, 180.0, "summon")

func _temporary_defense(multiplier: float, duration: float) -> void:
	player.health_component.active_skill_damage_multiplier = multiplier
	await player.get_tree().create_timer(duration).timeout
	if is_instance_valid(player):
		player.health_component.active_skill_damage_multiplier = 1.0

func _enemies_in_radius(radius: float) -> Array[Node]:
	var result: Array[Node] = []
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and player.global_position.distance_to(enemy.global_position) <= radius:
			result.append(enemy)
	return result

func _damage_enemy(enemy: Node, amount: float, knockback: float, is_critical: bool = false) -> void:
	var health: HealthComponent = enemy.get_node_or_null("HealthComponent")
	if health == null:
		return
	var metadata := CombatEventMeta.create_direct("player_active_skill", is_critical)
	var actual_damage := health.apply_damage(amount, metadata)
	if actual_damage <= 0.0:
		return
	EventBus.damage_dealt.emit(actual_damage, enemy.global_position, is_critical)
	EventBus.enemy_physical_damage_dealt.emit(actual_damage, enemy.global_position, is_critical)
	var hurtbox: HurtboxComponent = enemy.get_node_or_null("HurtboxComponent")
	var status_system := player.get_tree().get_first_node_in_group("status_apply_system") as StatusApplySystem
	# Space技も通常攻撃と同じ「職業が付与する状態」に揃える。ここだけburning固定だと、
	# 例えばcursed職のPlayerが自分では使えないburning系カードの条件を満たしてしまう。
	var skill_status_id := player.weapon_manager.get_applied_status_id() if player.weapon_manager else ""
	if status_system and skill_status_id != "" and enemy.is_in_group("enemies"):
		status_system.apply_state(enemy, skill_status_id, actual_damage)
	AudioManager.play_sfx("hit_impact")
	if enemy.has_method("apply_knockback"):
		enemy.apply_knockback((enemy.global_position - player.global_position).normalized(), knockback)
	var manager := player.get_tree().get_first_node_in_group("effect_theme_manager")
	if manager and hurtbox:
		manager.play_weapon_hit("", enemy.global_position, player.experience_component.level, hurtbox, player.global_position, is_critical)

func _damage_circle_at(center: Vector2, radius: float, amount: float, knockback: float) -> void:
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and center.distance_to(enemy.global_position) <= radius:
			_damage_enemy(enemy, amount, knockback)

func _spawn_vfx(radius: float, half_angle: float, style: String = "burst") -> void:
	_spawn_vfx_at(player.global_position, radius, style, half_angle)

func _spawn_vfx_at(position: Vector2, radius: float, style: String, half_angle: float = 180.0) -> void:
	var vfx := VFX_SCRIPT.new() as ActiveSkillVFX
	vfx.setup(radius, _skill_color(), player.get_facing_direction(), half_angle, style)
	GameManager.get_runtime_world(player).add_child(vfx)
	vfx.global_position = position

## school確定後のSwordsman(乱撃派/一閃派)だけ専用クールダウンを使う。
## school未確定(Lv1、居合のまま)・他職業は従来通りcharacter_data側の値を使う。
func _cooldown() -> float:
	if character_data == null:
		return 10.0
	if character_data.id == "swordsman":
		match _get_school():
			"rengeki":
				return maxf(rengeki_cooldown, 0.1)
			"issen":
				return maxf(issen_cooldown, 0.1)
	return maxf(character_data.active_skill_cooldown, 0.1)

func _skill_color() -> Color:
	return Color(0.95, 0.8, 0.3, 1.0)
