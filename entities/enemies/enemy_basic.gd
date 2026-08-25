extends Entity
class_name EnemyBasic
## 基本敵(直進追跡型)。EnemyDataを差し込むだけでステータスが変わるため、
## 新しい敵はJSONデータを追加するだけでコード変更なしに増やせる。

const BOSS_OUTLINE_SHADER := preload("res://effects/shaders/sprite_outline.gdshader")
## BossData.attack_pattern_id -> 対応するBossAttackStrategyスクリプトのパス。
## 新しい固有攻撃を追加する場合はsystems/boss_ai/にStrategyを追加し、ここへ
## 1行足すだけでよい(開放閉鎖の原則)。
const BOSS_ATTACK_STRATEGY_SCRIPTS := {
	"charge": "res://systems/boss_ai/charge_attack_strategy.gd",
	"summon": "res://systems/boss_ai/summon_strategy.gd",
	"nova": "res://systems/boss_ai/nova_strategy.gd",
	"slam": "res://systems/boss_ai/slam_strategy.gd",
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
@export var boss_special_interval_multiplier: float = 1.0
@export var boss_status_duration_multiplier: float = 1.0
## 見た目のスケール倍率(既存のAnimatedSprite2D.scaleに乗算する)。既定値1.25は
## 通常の雑魚敵にも適用される表示サイズの底上げ(ドット絵の視認性向上、詳細は
## game_specification.md参照)。精鋭部屋の敵(EliteRoomManager.elite_visual_scale)・
## ボス(BossData.visual_scale)は、この既定値を上書きしてさらに大きい値を使う。
@export var visual_scale_multiplier: float = 1.25

@onready var ai_component: AIComponent = $AIComponent
@onready var contact_hitbox: HitboxComponent = $ContactHitbox
@onready var hurtbox_component: HurtboxComponent = $HurtboxComponent
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_collision_shape: CollisionShape2D = $CollisionShape2D

var _is_dead: bool = false
## ボス固有攻撃(charge突進等)が発動中、通常のプレイヤー追跡移動を一時的に
## 止めてStrategy側にMovementComponentの制御を委ねるためのロック。
## BossAttackStrategy側からboss.set_movement_locked()経由で操作する。
var _movement_locked_by_attack: bool = false
## ROOM遷移中の事前生成ではNode/Animation/Physics登録を数Frameへ分散しつつ、
## 戦闘開始前に移動・攻撃だけを止める。
var _room_activation_locked := false
var boss_attack_component: BossAttackComponent = null

## 通常攻撃は接触判定と分離し、予備動作とクールダウンを持つ状態遷移で管理する。
enum NormalAttackState { READY, WINDUP, COOLDOWN }
var _normal_attack_state := NormalAttackState.READY
var _normal_attack_timer: float = 0.0
var _attack_warning: WarningCircle = null
var _hit_reaction_tween: Tween = null
var _base_sprite_scale: Vector2 = Vector2.ONE
static var _last_hit_stop_usec: int = 0

func _ready() -> void:
	add_to_group("enemies")
	if elite_stat_multiplier != 1.0:
		add_to_group("elite_enemies")
	if enemy_data:
		health_component.max_hp = enemy_data.max_hp * elite_stat_multiplier * room_hp_multiplier
		health_component.current_hp = health_component.max_hp
		movement_component.base_speed = enemy_data.move_speed
		contact_hitbox.damage = enemy_data.contact_damage * elite_stat_multiplier * room_damage_multiplier
		if enemy_data.sprite_folder != "":
			var frames := SpriteSheetBuilder.build_sprite_frames(enemy_data.sprite_folder)
			if frames:
				animated_sprite.sprite_frames = frames
	if visual_scale_multiplier != 1.0:
		animated_sprite.scale *= visual_scale_multiplier
		_scale_collision_shapes(visual_scale_multiplier)
	_base_sprite_scale = animated_sprite.scale
	if enemy_data is BossData:
		status_effect_component.duration_multiplier = boss_status_duration_multiplier
		_apply_boss_outline()
		_setup_boss_attack(enemy_data as BossData)
	if ai_component.behavior == null:
		ai_component.behavior = ChaseStrategy.new()
	ai_component.target = get_tree().get_first_node_in_group("player")
	health_component.died.connect(_on_died)
	health_component.damaged.connect(_on_damaged)
	contact_hitbox.damage_enabled = false

func _on_damaged(amount: float, _current_hp: float, max_hp: float) -> void:
	if _is_dead or animated_sprite == null:
		return
	if _hit_reaction_tween and _hit_reaction_tween.is_valid():
		_hit_reaction_tween.kill()
	animated_sprite.modulate = Color(1.65, 1.65, 1.65, 1.0)
	animated_sprite.scale = _base_sprite_scale * Vector2(1.08, 0.92)
	_hit_reaction_tween = create_tween().set_ignore_time_scale(true)
	_hit_reaction_tween.tween_property(animated_sprite, "scale", _base_sprite_scale, 0.085).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hit_reaction_tween.parallel().tween_property(animated_sprite, "modulate", Color.WHITE, 0.075)
	# 全Hitで停止し続けないよう全Enemy共通120ms Cooldown。Freeze/Stunとは独立した短い手応えだけを加える。
	var now_usec := Time.get_ticks_usec()
	if amount >= maxf(max_hp * 0.035, 6.0) and now_usec - _last_hit_stop_usec >= 120000:
		_last_hit_stop_usec = now_usec
		var screen_effects := get_tree().get_first_node_in_group("screen_effects") as ScreenEffects
		if screen_effects:
			screen_effects.hit_stop(0.014)

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
	material.set_shader_parameter("outline_width", 2.0)
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
	if not _movement_locked_by_attack and ai_component and ai_component.target:
		movement_component.direction = ai_component.compute_direction(global_position)
	_update_normal_attack(delta)
	super._physics_process(delta)

func set_room_activation_locked(locked: bool) -> void:
	_room_activation_locked = locked
	if locked and is_node_ready():
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
			if global_position.distance_to(ai_component.target.global_position) <= enemy_data.attack_range:
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
	_normal_attack_timer = maxf(enemy_data.attack_windup, 0.1)
	movement_component.direction = Vector2.ZERO
	if animation_component:
		animation_component.play_attack(randi_range(1, 2))
	if is_in_group("elite_enemies") or enemy_data is BossData:
		_attack_warning = WarningCircle.new()
		_attack_warning.radius = enemy_data.attack_range
		GameManager.get_runtime_world(self).add_child(_attack_warning)
		_attack_warning.global_position = global_position

func _resolve_normal_attack() -> void:
	if is_instance_valid(_attack_warning):
		_attack_warning.queue_free()
	_attack_warning = null
	var target := ai_component.target
	if target == null or global_position.distance_to(target.global_position) > enemy_data.attack_range:
		return
	var target_hurtbox: HurtboxComponent = target.get_node_or_null("HurtboxComponent")
	if target_hurtbox:
		target_hurtbox.apply_hitbox_damage(contact_hitbox)
		contact_hitbox.on_hit(target_hurtbox)

func apply_knockback(direction: Vector2, distance: float) -> void:
	if _is_dead or direction == Vector2.ZERO or distance <= 0.0:
		return
	move_and_collide(direction.normalized() * distance)

## 死亡アニメーションを最後まで見せてからノードを消したいので、
## HealthComponent.diedの時点ではqueue_free()せず、行動を止めてアニメーション完了を待つ。
func _on_died() -> void:
	if _is_dead:
		return
	_is_dead = true
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
