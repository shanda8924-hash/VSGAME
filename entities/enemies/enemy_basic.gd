extends Entity
class_name EnemyBasic
## 基本敵(直進追跡型)。EnemyDataを差し込むだけでステータスが変わるため、
## 新しい敵はJSONデータを追加するだけでコード変更なしに増やせる。
## 通常敵・Elite部屋出現・Bossは全てこの単一シーン(enemy_basic.tscn)を
## enemy_scene(WaveSpawner/EliteRoomManager/BossSpawner共通のExportSlot)経由で
## 使い回すため、物理Body(CharacterBody2D本体)のcollision_layer/mask調整は
## ここ1箇所で全種別に反映される。
## 本体はlayer=8、mask=9。壁・Player・他Enemyに衝突する。
## 武器のHurtbox/Hitboxは本体と別レイヤーで判定する。
## HurtboxComponent/ContactHitboxのArea2D(2/4/16/32)、予備動作後の攻撃判定、
## 武器由来のKnockbackは独立しており維持する。

const BOSS_OUTLINE_SHADER := preload("res://effects/shaders/sprite_outline.gdshader")
## BossData.attack_pattern_id -> 対応するBossAttackStrategyスクリプトのパス。
## 新しい固有攻撃を追加する場合はsystems/boss_ai/にStrategyを追加し、ここへ
## 1行足すだけでよい(開放閉鎖の原則)。
const BOSS_ATTACK_STRATEGY_SCRIPTS := {
	"charge": "res://systems/boss_ai/charge_attack_strategy.gd",
	"summon": "res://systems/boss_ai/summon_strategy.gd",
	"nova": "res://systems/boss_ai/nova_strategy.gd",
	"slam": "res://systems/boss_ai/slam_strategy.gd",
	"minotaur_combo": "res://systems/boss_ai/minotaur_combo_strategy.gd",
}

@export var enemy_data: EnemyData
## 精鋭部屋(Elite Room)の敵を強化するための倍率。1.0なら通常個体と同じ。
## EliteRoomManagerがadd_child前にこの値を設定してから生成する。
@export var elite_stat_multiplier: float = 1.0
## ROOM番号による難易度補正。Elite扱い・Drop・Affixとは独立させ、通常ROOM敵が
## elite_enemiesグループへ誤登録されないようにする。
@export var room_hp_multiplier: float = 1.0
@export var room_damage_multiplier: float = 1.0
@export var room_attack_interval_multiplier: float = 1.0
## 予備動作の倍率。突撃型・群れ型は短く（WaveSpawnerが役割で設定）、見て避ける余地は残す。
@export var attack_windup_multiplier: float = 1.0
@export var room_move_speed_multiplier: float = 1.0
@export var boss_special_interval_multiplier: float = 1.0
@export var boss_status_duration_multiplier: float = 1.0
## 見た目のスケール倍率(既存のAnimatedSprite2D.scaleに乗算する)。既定値1.40は
## 通常の雑魚敵にも適用される表示サイズの底上げ(ドット絵の視認性向上、詳細は
## game_specification.md参照)。精鋭部屋の敵(EliteRoomManager.elite_visual_scale)・
## ボス(BossData.visual_scale)は、この既定値を上書きしてさらに大きい値を使う。
@export var visual_scale_multiplier: float = 1.40

@onready var ai_component: AIComponent = $AIComponent
@onready var contact_hitbox: HitboxComponent = $ContactHitbox
@onready var hurtbox_component: HurtboxComponent = $HurtboxComponent
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_collision_shape: CollisionShape2D = $CollisionShape2D
@onready var state_indicator: StateIndicator = $StateIndicator

var exploration_guard := false
var exploration_home := Vector2.ZERO
var exploration_room := -1
var _returning_home := false
var exploration_alert := false
var _is_dead: bool = false
## ボス固有攻撃(charge突進等)が発動中、通常のプレイヤー追跡移動を一時的に
## 止めてStrategy側にMovementComponentの制御を委ねるためのロック。
## BossAttackStrategy側からboss.set_movement_locked()経由で操作する。
var _movement_locked_by_attack: bool = false
## ROOM遷移中の事前生成ではNode/Animation/Physics登録を数Frameへ分散しつつ、
## 戦闘開始前に移動・攻撃だけを止める。
var _room_activation_locked := false
var boss_attack_component: BossAttackComponent = null
var strong_attack: Node2D = null

## 通常攻撃は接触判定と分離し、予備動作とクールダウンを持つ状態遷移で管理する。
enum NormalAttackState { READY, WINDUP, COOLDOWN }
var _normal_attack_state := NormalAttackState.READY
var _normal_attack_timer: float = 0.0
var _attack_warning: WarningCircle = null
var _hit_reaction_tween: Tween = null
var _last_guard_pose_msec := -1000
var _base_sprite_scale: Vector2 = Vector2.ONE
static var _last_hit_stop_usec: int = 0
var _impact_cooldown_until := 0
var _impact_paused := false
var _impact_previous_mode := Node.PROCESS_MODE_INHERIT
var _impact_direction := Vector2.ZERO
var _impact_push := 0.0
var _impact_recovery := 0.0

func receive_hit_impact(metadata: Dictionary) -> void:
	if _is_dead or _impact_paused or not bool(metadata.get("is_direct", false)):
		return
	var now := Time.get_ticks_msec()
	if now < _impact_cooldown_until:
		return
	var heavy := bool(metadata.get("is_critical", false)) or String(metadata.get("source_kind", "")).contains("active_skill")
	var resistance := 0.4 if enemy_data is BossData else (0.65 if is_in_group("elite_enemies") else 1.0)
	if is_wall_role():
		resistance *= 0.5
	var duration := (0.08 if heavy else 0.05) * resistance
	_impact_cooldown_until = now + (400 if enemy_data is BossData else 220)
	_impact_push = (12.0 if heavy else 7.0) * resistance
	_impact_recovery = (0.12 if heavy else 0.08) * resistance
	if _movement_locked_by_attack or strong_attack or enemy_data is BossData:
		_impact_push = 0.0
		_impact_recovery = 0.0
	var target := ai_component.target
	if is_instance_valid(target):
		var origin: Vector2 = metadata.get("source_position", target.global_position)
		_impact_direction = (global_position - origin).normalized()
	_impact_previous_mode = process_mode
	_impact_paused = true
	process_mode = Node.PROCESS_MODE_DISABLED
	# The tree timer continues while this enemy alone is disabled, but respects menus.
	get_tree().create_timer(duration, false).timeout.connect(_finish_hit_impact)

func _finish_hit_impact() -> void:
	if not _impact_paused:
		return
	_impact_paused = false
	process_mode = _impact_previous_mode

func _body_spacing() -> float:
	var target_shape := ai_component.target.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var own_radius := (body_collision_shape.shape as CircleShape2D).radius
	var target_radius := 20.0
	if target_shape and target_shape.shape is CircleShape2D:
		target_radius = (target_shape.shape as CircleShape2D).radius
	return own_radius + target_radius + 2.0

func _normal_reach() -> float:
	if _is_ranged():
		return enemy_data.ranged_range
	return maxf(enemy_data.attack_range, _body_spacing() + 6.0)

## 遠距離型（EnemyData.ranged_range > 0）。立ち止まって弾を撃ち、近接判定は使わない。
func _is_ranged() -> bool:
	return enemy_data != null and enemy_data.ranged_range > 0.0 and not enemy_data is BossData

## 壁型（WaveSpawnerがmeta "wall"を付ける）。ノックバックと硬直への耐性を持つ。
func is_wall_role() -> bool:
	return get_meta("wall", false)

func _keep_melee_spacing(_delta: float) -> void:
	if not is_instance_valid(ai_component.target) or enemy_data == null or _movement_locked_by_attack:
		return
	var offset := global_position - ai_component.target.global_position
	var distance := offset.length()
	var spacing := _body_spacing()
	if distance < spacing + 2.0:
		movement_component.direction = Vector2.ZERO
		# Contact only stops pursuit. Never back away to maintain an artificial gap:
		# that turns forward walking into an unlimited push.

func _ready() -> void:
	# Hit-stop pauses logic, never removes the solid body or hurtbox.
	disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	$HurtboxComponent.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	$ContactHitbox.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_to_group("enemies")
	if elite_stat_multiplier != 1.0:
		add_to_group("elite_enemies")
	if enemy_data:
		health_component.max_hp = enemy_data.max_hp * elite_stat_multiplier * room_hp_multiplier
		health_component.current_hp = health_component.max_hp
		if enemy_data.id == "shield_guard":
			health_component.damage_taken_multiplier = 0.8
			health_component.damaged.connect(_on_shield_guard_damaged)
		movement_component.base_speed = enemy_data.move_speed * room_move_speed_multiplier
		contact_hitbox.damage = enemy_data.contact_damage * elite_stat_multiplier * room_damage_multiplier
		if enemy_data.sprite_folder != "":
			var frames := SpriteSheetBuilder.build_sprite_frames(enemy_data.sprite_folder)
			if frames:
				animated_sprite.sprite_frames = frames
	if visual_scale_multiplier != 1.0:
		animated_sprite.scale *= visual_scale_multiplier
		_scale_collision_shapes(visual_scale_multiplier)
	_base_sprite_scale = animated_sprite.scale
	if not enemy_data is BossData:
		var health_bar := preload("res://entities/enemies/enemy_health_bar.gd").new()
		health_bar.name = "EnemyHealthBar"
		add_child(health_bar)
	if enemy_data is BossData:
		status_effect_component.duration_multiplier = boss_status_duration_multiplier
		_apply_boss_outline()
		_setup_boss_attack(enemy_data as BossData)
	if ai_component.behavior == null:
		if _is_ranged():
			var ranged := RangedStrategy.new()
			ranged.hold_distance = enemy_data.ranged_range * 0.82
			ranged.retreat_distance = enemy_data.ranged_range * 0.42
			ai_component.behavior = ranged
		else:
			ai_component.behavior = ChaseStrategy.new()
	ai_component.target = get_tree().get_first_node_in_group("player")
	health_component.died.connect(_on_died)
	health_component.damaged.connect(_on_damaged)
	status_effect_component.states_changed.connect(_on_states_changed)
	_on_states_changed(status_effect_component.get_states())
	contact_hitbox.damage_enabled = false
	if enemy_data and enemy_data.special_attack_id != "":
		var special_script = load("res://systems/strong_enemy_special.gd")
		if enemy_data.special_attack_id == "orc_step_slash":
			strong_attack = load("res://systems/orc_step_slash.gd").new()
		elif special_script.MOVES.has(enemy_data.special_attack_id):
			strong_attack = special_script.new()
		else:
			push_warning("Unknown strong special: " + enemy_data.special_attack_id)
			return
		add_child(strong_attack)
		strong_attack.setup(self)

func _on_states_changed(states: Array[String]) -> void:
	if state_indicator:
		state_indicator.set_states(states)

func _on_damaged(amount: float, _current_hp: float, max_hp: float) -> void:
	exploration_alert = true
	if _is_dead or animated_sprite == null:
		return
	if _hit_reaction_tween and _hit_reaction_tween.is_valid():
		_hit_reaction_tween.kill()
	animated_sprite.modulate = Color(1.65, 1.65, 1.65, 1.0)
	animated_sprite.scale = _base_sprite_scale * Vector2(1.025, 0.975)
	_hit_reaction_tween = create_tween().set_ignore_time_scale(true)
	_hit_reaction_tween.tween_property(animated_sprite, "scale", _base_sprite_scale, 0.085).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hit_reaction_tween.parallel().tween_property(animated_sprite, "modulate", Color.WHITE, 0.075)
	# Direct hits pause this enemy in receive_hit_impact; no global time-scale change.

func _on_shield_guard_damaged(_amount: float, current_hp: float, _max_hp: float) -> void:
	var now := Time.get_ticks_msec()
	if current_hp > 0.0 and now - _last_guard_pose_msec >= 850 and _normal_attack_state != NormalAttackState.WINDUP:
		_last_guard_pose_msec = now
		animation_component.play_block()

## 見た目(AnimatedSprite2D.scale)と当たり判定がズレないよう、本体の移動用
## CollisionShape2D・HurtboxComponent(被弾判定)・ContactHitbox(接触与ダメージ判定)の
## 3つすべてに同じ倍率をかける。.tscn内の[sub_resource]は既にinstantiate()ごとに
## 複製される仕様だが、念のためduplicate()してから書き換え、他個体への影響を確実に防ぐ。
func _scale_collision_shapes(multiplier: float) -> void:
	_scale_shape(body_collision_shape, multiplier)
	_scale_shape(hurtbox_component.get_node("CollisionShape2D"), multiplier)
	_scale_shape(contact_hitbox.get_node("CollisionShape2D"), multiplier)

func _scale_shape(collision_shape: CollisionShape2D, multiplier: float) -> void:
	if collision_shape == null or collision_shape.shape == null:
		return
	var shape: Shape2D = collision_shape.shape.duplicate()
	if shape is CircleShape2D:
		shape.radius *= multiplier
	elif shape is RectangleShape2D:
		shape.size *= multiplier
	elif shape is CapsuleShape2D:
		shape.radius *= multiplier
		shape.height *= multiplier
	collision_shape.shape = shape

## ボスであることが一目で分かるよう、AnimatedSprite2Dへ赤い縁取りシェーダーを適用する
## (通常個体・精鋭個体には適用しない、BossDataの時だけ)。
func _apply_boss_outline() -> void:
	var material := ShaderMaterial.new()
	material.shader = BOSS_OUTLINE_SHADER
	material.set_shader_parameter("outline_color", Color(0.9, 0.05, 0.05, 1.0))
	# Texture上の線幅はSprite倍率でも一緒に拡大されるため、画面上では約2pxに保つ。
	material.set_shader_parameter("outline_width", 2.0 / maxf(visual_scale_multiplier, 1.0))
	animated_sprite.material = material

## BossData.attack_pattern_idに対応するBossAttackStrategyを動的に生成し、
## BossAttackComponentとしてadd_childする(通常敵にはこのノード自体が
## 存在しないため、雑魚敵の大量湧きに余計な処理負荷を追加しない)。
func _setup_boss_attack(boss_data: BossData) -> void:
	if boss_data.attack_pattern_id == "":
		return
	if not BOSS_ATTACK_STRATEGY_SCRIPTS.has(boss_data.attack_pattern_id):
		push_warning("EnemyBasic: 未知のattack_pattern_id -> %s" % boss_data.attack_pattern_id)
		return
	var strategy_script: Script = load(BOSS_ATTACK_STRATEGY_SCRIPTS[boss_data.attack_pattern_id])
	var component := BossAttackComponent.new()
	component.attack_strategy = strategy_script.new()
	component.boss = self
	component.target = get_tree().get_first_node_in_group("player")
	component.interval_multiplier = boss_special_interval_multiplier
	add_child(component)
	boss_attack_component = component

## BossAttackStrategy(charge等)が突進中などにMovementComponentを直接制御したい
## 場合に、通常のプレイヤー追跡上書き(_physics_process内)を一時的に止める。
func set_movement_locked(locked: bool) -> void:
	_movement_locked_by_attack = locked

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	if _room_activation_locked:
		movement_component.direction = Vector2.ZERO
		contact_hitbox.damage_enabled = false
		return
	if exploration_guard and exploration_room >= 0:
		if exploration_alert and is_instance_valid(ai_component.target) and (exploration_home.distance_to(ai_component.target.global_position) > 420.0 or exploration_home.distance_to(global_position) > 360.0):
			_returning_home = true
			exploration_alert = false
			_cancel_exploration_attack()
		if _returning_home:
			contact_hitbox.damage_enabled = false
			if global_position.distance_to(exploration_home) < 12.0:
				_returning_home = false
				movement_component.direction = Vector2.ZERO
			else:
				movement_component.direction = ai_component.behavior.compute_direction(global_position, exploration_home) if ai_component.behavior else global_position.direction_to(exploration_home)
				super._physics_process(delta)
			return
	if exploration_guard and not _update_exploration_awareness():
		movement_component.direction = Vector2.ZERO
		contact_hitbox.damage_enabled = false
		return
	if _impact_push > 0.0:
		var step := minf(_impact_push, delta * maxf(65.0, _impact_push * 18.0))
		move_and_collide(_impact_direction * step)
		_impact_push -= step
	if _impact_recovery > 0.0 or _impact_push > 0.0:
		_impact_recovery = maxf(0.0, _impact_recovery - delta)
		movement_component.direction = Vector2.ZERO
		return
	if strong_attack and strong_attack.tick(delta):
		super._physics_process(delta)
		return
	if not _movement_locked_by_attack and ai_component and ai_component.target:
		movement_component.direction = ai_component.compute_direction(global_position)
		_keep_melee_spacing(delta)
	_update_normal_attack(delta)
	if movement_component.get_velocity().is_zero_approx():
		velocity = Vector2.ZERO
		return
	super._physics_process(delta)

func set_room_activation_locked(locked: bool) -> void:
	_room_activation_locked = locked
	if locked and is_node_ready():
		if strong_attack:
			strong_attack.cancel()
		movement_component.direction = Vector2.ZERO
		contact_hitbox.damage_enabled = false

## 攻撃範囲へ入ると停止して予備動作を開始し、予備時間終了時にもう一度距離を
## 判定する。その時点で範囲外なら空振りとなるため、プレイヤーは見て回避できる。
func _update_normal_attack(delta: float) -> void:
	# ContactHitboxは常時無効。接触そのものからダメージが発生する経路を作らない。
	contact_hitbox.damage_enabled = false
	if _movement_locked_by_attack or enemy_data == null or ai_component.target == null:
		return
	_normal_attack_timer = maxf(0.0, _normal_attack_timer - delta)
	match _normal_attack_state:
		NormalAttackState.READY:
			if global_position.distance_to(ai_component.target.global_position) <= _normal_reach():
				_start_normal_attack()
		NormalAttackState.WINDUP:
			movement_component.direction = Vector2.ZERO
			if _normal_attack_timer <= 0.0:
				_resolve_normal_attack()
				_normal_attack_state = NormalAttackState.COOLDOWN
				_normal_attack_timer = maxf(enemy_data.attack_interval * room_attack_interval_multiplier, 0.1)
		NormalAttackState.COOLDOWN:
			if _normal_attack_timer <= 0.0:
				_normal_attack_state = NormalAttackState.READY

func _start_normal_attack() -> void:
	_normal_attack_state = NormalAttackState.WINDUP
	_normal_attack_timer = maxf(enemy_data.attack_windup * attack_windup_multiplier, 0.1)
	movement_component.direction = Vector2.ZERO
	if animation_component:
		animation_component.play_attack(randi_range(1, 2))
	if is_in_group("elite_enemies") or enemy_data is BossData:
		_attack_warning = WarningCircle.new()
		_attack_warning.radius = _normal_reach()
		_attack_warning.duration = _normal_attack_timer
		_attack_warning.source = self
		GameManager.get_runtime_world(self).add_child(_attack_warning)
		_attack_warning.global_position = global_position

func _resolve_normal_attack() -> void:
	if is_instance_valid(_attack_warning):
		_attack_warning.queue_free()
	_attack_warning = null
	var target := ai_component.target
	if target == null:
		return
	if _is_ranged():
		if global_position.distance_to(target.global_position) <= _normal_reach() * 1.25:
			_fire_ranged_shot(target)
		return
	if global_position.distance_to(target.global_position) > _normal_reach():
		return
	var ray := PhysicsRayQueryParameters2D.create(global_position, target.global_position, 1)
	ray.exclude = [get_rid(), (target as CollisionObject2D).get_rid()]
	if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
		return
	var target_hurtbox: HurtboxComponent = target.get_node_or_null("HurtboxComponent")
	if target_hurtbox:
		target_hurtbox.apply_hitbox_damage(contact_hitbox)
		contact_hitbox.on_hit(target_hurtbox)

## 遠距離型の通常攻撃。ボスのnovaと同じ共通Projectileを敵弾（layer 16）として1発撃つ。
## 予備動作の時点の位置ではなく発射時のプレイヤー位置へ向けるので、動き続ければ外れる。
func _fire_ranged_shot(target: Node2D) -> void:
	var projectile_scene: PackedScene = load("res://entities/projectiles/projectile.tscn")
	var weapon := WeaponData.new()
	weapon.base_damage = contact_hitbox.damage
	weapon.crit_chance = 0.0
	weapon.crit_multiplier = 1.0
	weapon.vfx_theme_id = ""
	var bullet := projectile_scene.instantiate()
	bullet.name = "EnemyShot"
	bullet.collision_layer = 16 # PLAYER_HIT_LAYER: PlayerのHurtboxComponent.collision_maskと一致
	bullet.is_player_attack = false
	bullet.uses_player_element_vfx = false
	bullet.speed = 230.0
	GameManager.get_runtime_world(self).add_child(bullet)
	bullet.global_position = global_position + (target.global_position - global_position).normalized() * 18.0
	bullet.launch(target.global_position, weapon)
	bullet.add_to_group("enemy_shots")
	bullet.use_enemy_shot()
	AudioManager.play_sfx("attack_shoot")

func apply_knockback(direction: Vector2, distance: float) -> void:
	if _is_dead or direction == Vector2.ZERO or distance <= 0.0:
		return
	if is_wall_role():
		distance *= 0.35
	if _impact_paused:
		_impact_direction = direction.normalized()
		_impact_push = maxf(_impact_push, distance)
		return
	_impact_direction = direction.normalized()
	_impact_push = maxf(_impact_push, minf(distance, 80.0))
	_impact_recovery = maxf(_impact_recovery, 0.08)

## 死亡アニメーションを最後まで見せてからノードを消したいので、
## HealthComponent.diedの時点ではqueue_free()せず、行動を止めてアニメーション完了を待つ。
func _on_died() -> void:
	if _is_dead:
		return
	_finish_hit_impact()
	_impact_push = 0.0
	if strong_attack:
		strong_attack.cancel()
	_is_dead = true
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	body_collision_shape.set_deferred("disabled", true)
	if boss_attack_component:
		boss_attack_component.stop()
	if is_instance_valid(_attack_warning):
		_attack_warning.queue_free()
	GameManager.register_kill()
	if enemy_data:
		EventBus.enemy_drop_requested.emit(global_position, is_in_group("elite_enemies"), enemy_data is BossData)
		EventBus.enemy_died.emit(enemy_data, global_position)
	ai_component.target = null
	movement_component.direction = Vector2.ZERO
	# 死亡アニメ再生中も一瞬ノードが残るため、その間に接触ダメージ判定や
	# 追加ヒットが発生しないよう当たり判定を切っておく(set_deferredで安全に変更)。
	contact_hitbox.set_deferred("monitorable", false)
	hurtbox_component.set_deferred("monitorable", false)
	if animation_component:
		animation_component.death_finished.connect(queue_free, CONNECT_ONE_SHOT)
	else:
		queue_free()

func _update_exploration_awareness() -> bool:
	if not is_instance_valid(ai_component.target):
		return false
	var distance := global_position.distance_to(ai_component.target.global_position)
	if exploration_alert:
		if distance <= 380.0:
			return true
		exploration_alert = false
		_returning_home = exploration_room >= 0 and global_position.distance_to(exploration_home) > 12.0
		_cancel_exploration_attack()
		return false
	if distance > 200.0:
		return false
	var ray := PhysicsRayQueryParameters2D.create(global_position, ai_component.target.global_position, 1)
	ray.exclude = [get_rid(), (ai_component.target as CollisionObject2D).get_rid()]
	if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
		return false
	exploration_alert = true
	return true

func _cancel_exploration_attack() -> void:
	if strong_attack: strong_attack.cancel()
	_normal_attack_state = NormalAttackState.READY
	_normal_attack_timer = 0.0
	if is_instance_valid(_attack_warning): _attack_warning.queue_free()
	_attack_warning = null
