extends Node
class_name AnimationComponent
## 見た目のアニメーション状態(idle/walk/attack/hurt/death)の再生だけを責務とするコンポーネント。
## MovementComponent.directionとHealthComponent.damaged/died Signalを購読し、
## 「今どのアニメーションを再生すべきか」を決めるだけで、攻撃タイミング自体は
## 呼び出し側(Player/EnemyBasic)がplay_attack()を呼んで教える(単一責任の原則)。
## Player/Enemy共通で使えるよう、兄弟ノードは固定名(HealthComponent/MovementComponent/
## AnimatedSprite2D)で参照する(Entity配下の他Componentと同じ規約)。

signal death_finished

const IDLE_ANIM := "idle"
const WALK_ANIM := "walk"
const HURT_ANIM := "hurt"
const DEATH_ANIM := "death"

@onready var _sprite: AnimatedSprite2D = get_parent().get_node("AnimatedSprite2D")
@onready var _health: HealthComponent = get_parent().get_node_or_null("HealthComponent")
@onready var _movement: MovementComponent = get_parent().get_node_or_null("MovementComponent")

var _locked_until_msec: int = 0
var _dead: bool = false
var _pose_controlled := false

func set_pose_controlled(value: bool) -> void:
	_pose_controlled = value
	_locked_until_msec = 0
	_attack_speed_reset_msec = 0
	_sprite.speed_scale = 1.0

var _attack_speed_reset_msec: int = 0

func _ready() -> void:
	if _health:
		_health.damaged.connect(_on_damaged)
		_health.died.connect(_on_died)
	_sprite.animation_finished.connect(_on_animation_finished)
	if _sprite.sprite_frames and _sprite.sprite_frames.has_animation(IDLE_ANIM):
		_sprite.play(IDLE_ANIM)

func _process(_delta: float) -> void:
	var player := get_parent() as Player
	if player and player.weapon_manager._class_attack_in_progress and String(_sprite.animation) == player.weapon_manager._sword_animation and _sprite.is_playing():
		# Keep the authored motion (including menu pauses) until its last frame.
		_sprite.flip_h = player.weapon_manager._sword_facing.x < 0.0
		return
	if _pose_controlled and not _dead:
		return
	if _attack_speed_reset_msec > 0 and Time.get_ticks_msec() >= _attack_speed_reset_msec:
		_sprite.speed_scale = 1.0
		_attack_speed_reset_msec = 0
	if _dead or _movement == null:
		return
	# 向き(flip_h)は攻撃/被弾アニメのロック中も常に更新する。ロック判定より前に
	# 行わないと、攻撃間隔が短い(≒ほぼ常にロック中の)キャラクターで
	# 移動方向を反映した反転がほとんど発生しなくなってしまう
	# (「キャラクターが常に同じ向きのまま」というバグの原因だった)。
	_update_facing()
	if Time.get_ticks_msec() < _locked_until_msec:
		return
	if _movement.direction.length() > 0.01:
		_play(WALK_ANIM)
	else:
		_play(IDLE_ANIM)

## 左右の移動成分がある間だけflip_hを更新し、上下移動のみ(または停止中)は
## 直前の左右の向きを維持する。
func _update_facing() -> void:
	if absf(_movement.direction.x) > 0.01:
		_sprite.flip_h = _movement.direction.x < 0.0

## 呼び出し側(Player=武器発射時 / EnemyBasic=接触ダメージ着弾時)が攻撃演出を要求する。
## variantはSpriteFramesに定義した"attack1"/"attack2"等の番号。無ければattack1にフォールバックする。
func cancel_attack_pose() -> void:
	_locked_until_msec = 0
	_attack_speed_reset_msec = 0
	_sprite.speed_scale = 1.0
	if not _dead and _sprite.sprite_frames and _sprite.sprite_frames.has_animation(IDLE_ANIM):
		_sprite.play(IDLE_ANIM)

func play_attack(variant: int = 1, speed_multiplier: float = 1.0) -> void:
	if _dead:
		return
	var anim_name := "attack%d" % variant
	if _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(anim_name):
		anim_name = "attack1"
	_sprite.speed_scale = maxf(speed_multiplier, 0.1)
	_play_locked(anim_name, _sprite.speed_scale)

func play_block() -> void:
	if not _dead:
		_play_locked("block")

func _on_damaged(_amount: float, _current_hp: float, _max_hp: float) -> void:
	if _dead or _pose_controlled:
		return
	_play_locked(HURT_ANIM)

func _on_died() -> void:
	_dead = true
	_play(DEATH_ANIM)

func _on_animation_finished() -> void:
	if _dead and _sprite.animation == DEATH_ANIM:
		death_finished.emit()

func _play(anim_name: String) -> void:
	if _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(anim_name):
		return
	if _sprite.animation != anim_name or not _sprite.is_playing():
		_sprite.play(anim_name)

func _play_locked(anim_name: String, speed_multiplier: float = 1.0) -> void:
	if _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(anim_name):
		return
	_sprite.speed_scale = maxf(speed_multiplier, 0.1)
	_sprite.play(anim_name)
	var fps := _sprite.sprite_frames.get_animation_speed(anim_name)
	var frame_count := _sprite.sprite_frames.get_frame_count(anim_name)
	var duration := ((frame_count / fps) / maxf(speed_multiplier, 0.1)) if fps > 0.0 else 0.3
	_locked_until_msec = Time.get_ticks_msec() + int(duration * 1000.0)
	_attack_speed_reset_msec = _locked_until_msec
