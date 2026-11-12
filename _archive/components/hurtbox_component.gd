extends Area2D
class_name HurtboxComponent
## 被弾判定(被ダメージ側)。HitboxComponentとの接触を検知し、
## 紐付けられたHealthComponentへダメージを伝える。

@export var health_component_path: NodePath

var _health_component: HealthComponent
## 命中ごとにGroup検索するのを避けるための遅延Cache(被弾はゲーム中もっとも頻度が高い経路)。
var _status_system_cache: StatusApplySystem = null

func _ready() -> void:
	if health_component_path != NodePath():
		_health_component = get_node(health_component_path)
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	if area is HitboxComponent:
		var hitbox := area as HitboxComponent
		# damage_enabled=falseの間(例: 敵が攻撃モーション中でない接触)は
		# 「触れた」こと自体はhitbox.on_hit()で相手(EnemyBasic等)に伝えつつ、
		# 実際のダメージ適用だけをスキップする(EnemyBasicはこれを合図に
		# 攻撃モーションを開始できる)。
		if hitbox.can_hit(self):
			apply_hitbox_damage(hitbox)
			hitbox.on_hit(self)

## Hitbox1つぶんのダメージを実際に適用する(会心通知・damage_dealt通知・hit_impact SE込み)。
## 通常はarea_entered経由の_on_area_entered()から呼ばれるが、EnemyBasicのContactHitboxのように
## 「既に重なった状態のまま攻撃モーション窓が開く」ケースでは新たなarea_enteredが
## 発生しないため、EnemyBasic側からこのメソッドを直接呼んで適用する。
func apply_hitbox_damage(hitbox: HitboxComponent) -> void:
	if _health_component == null:
		return
	var metadata := hitbox.combat_metadata.duplicate(true)
	if metadata.is_empty():
		metadata = CombatEventMeta.create_direct("player_direct_attack", hitbox.is_critical) if hitbox.is_player_attack else CombatEventMeta.create_secondary("non_player_hit", [], false)
	metadata["is_critical"] = hitbox.is_critical
	var actual_damage := _health_component.apply_animation_strike_damage(hitbox.damage, metadata) if hitbox is MeleeHit and hitbox.animation_strike else _health_component.apply_damage(hitbox.damage, metadata)
	if actual_damage <= 0.0:
		return
	var owner_entity := get_owner_entity()
	var hit_position := hitbox.global_position
	if owner_entity is Node2D:
		hit_position = (owner_entity as Node2D).global_position
	EventBus.damage_dealt.emit(actual_damage, hit_position, hitbox.is_critical)
	if owner_entity and owner_entity.is_in_group("enemies"):
		EventBus.enemy_physical_damage_dealt.emit(actual_damage, hit_position, hitbox.is_critical)
		_apply_hitbox_status(hitbox, owner_entity, actual_damage)
	# 「敵にダメージが入った瞬間」のSEなので、被弾した側がenemiesグループの
	# 時だけ鳴らす(プレイヤー被弾側はplayer_hurt SEと別に扱うため)。
	if owner_entity and owner_entity.is_in_group("enemies"):
		AudioManager.play_sfx("combat_hit")

## Hitboxが運んできた状態異常を敵へ付与する。ダメージ適用の「後」に呼ぶこと
## (先に付与すると、その状態を条件にするダメージ強化が、状態を付けた当のHitにも
## 乗ってしまう)。AttackPatternBase.apply_direct_damage()と同じ順序に揃えてある。
func _apply_hitbox_status(hitbox: HitboxComponent, owner_entity: Node, actual_damage: float) -> void:
	if hitbox.applied_status_id == "":
		return
	if _status_system_cache == null or not is_instance_valid(_status_system_cache):
		_status_system_cache = get_tree().get_first_node_in_group("status_apply_system") as StatusApplySystem
	if _status_system_cache:
		_status_system_cache.apply_state(owner_entity as Node2D, hitbox.applied_status_id, actual_damage)

## 被弾した本体(Entity)を取得する。状態異常の付与・判定のために
## StatusEffectComponentへ辿り着くのに使う。
func get_owner_entity() -> Node:
	if _health_component == null:
		return null
	return _health_component.get_parent()
