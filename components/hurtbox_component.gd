extends Area2D
class_name HurtboxComponent
## 被弾判定(被ダメージ側)。HitboxComponentとの接触を検知し、
## 紐付けられたHealthComponentへダメージを伝える。

@export var health_component_path: NodePath

var _health_component: HealthComponent

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
		metadata = CombatEventMeta.create_direct("player_direct_attack", hitbox.is_critical) if hitbox.applies_player_elements else CombatEventMeta.create_secondary("non_player_hit", [], false)
	metadata["is_critical"] = hitbox.is_critical
	var actual_damage := _health_component.apply_damage(hitbox.damage, metadata)
	if actual_damage <= 0.0:
		return
	var owner_entity := get_owner_entity()
	var hit_position := hitbox.global_position
	if owner_entity is Node2D:
		hit_position = (owner_entity as Node2D).global_position
	EventBus.damage_dealt.emit(actual_damage, hit_position, hitbox.is_critical)
	if owner_entity and owner_entity.is_in_group("enemies"):
		EventBus.enemy_physical_damage_dealt.emit(actual_damage, hit_position, hitbox.is_critical)
	if hitbox.applies_player_elements and owner_entity and owner_entity.is_in_group("enemies"):
		var element_system := get_tree().get_first_node_in_group("element_combat_system") as ElementCombatSystem
		if element_system:
			element_system.apply_element_damage(self, actual_damage, hitbox.global_position, {"combat_metadata": metadata})
	# 「敵にダメージが入った瞬間」のSEなので、被弾した側がenemiesグループの
	# 時だけ鳴らす(プレイヤー被弾側はplayer_hurt SEと別に扱うため)。
	if owner_entity and owner_entity.is_in_group("enemies"):
		AudioManager.play_sfx("hit_impact")

## 被弾した本体(Entity)を取得する。武器属性VFX(EffectThemeManager)が
## 状態異常付与や氷結判定のためにStatusEffectComponentへ辿り着くのに使う。
func get_owner_entity() -> Node:
	if _health_component == null:
		return null
	return _health_component.get_parent()
