extends Entity
class_name AllySkeleton
## Necromancerのsummon_minion攻撃パターンが召喚する味方ユニット。
## entities/enemies/enemy_basic.gdと同じComponent構成(AIComponent+ChaseStrategy/
## HurtboxComponent/ContactHitbox)を流用するが、追跡・攻撃対象が「プレイヤー」ではなく
## 「最も近い敵」であり、被弾判定・接触ダメージ判定の衝突レイヤーが敵ではなく
## 味方用(ally_skeleton.tscn参照)に入れ替わっている点が異なる。

@onready var ai_component: AIComponent = $AIComponent
@onready var contact_hitbox: HitboxComponent = $ContactHitbox
@onready var hurtbox_component: HurtboxComponent = $HurtboxComponent
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var _is_dead: bool = false
var _lifetime: float = 0.0

func setup(max_hp: float, move_speed: float, contact_damage: float, sprite_folder: String, lifetime: float) -> void:
	health_component.max_hp = max_hp
	health_component.current_hp = max_hp
	movement_component.base_speed = move_speed
	contact_hitbox.damage = contact_damage
	_lifetime = lifetime
	if sprite_folder != "":
		var frames := SpriteSheetBuilder.build_sprite_frames(sprite_folder)
		if frames:
			animated_sprite.sprite_frames = frames
	# 敵のスケルトンと見分けが付くよう、味方は青みがかった色味にする。
	animated_sprite.modulate = Color(0.55, 0.85, 1.0, 1.0)

func _ready() -> void:
	add_to_group("allies")
	ai_component.behavior = ChaseStrategy.new()
	health_component.died.connect(_on_died)
	# 召喚した味方の攻撃も、召喚主(Player)の職業が付与する状態異常を運ぶ。
	# Necromancerは本体が直接殴らずこの接触ダメージが唯一の与ダメージ経路なので、
	# ここを繋がないと職業に割り当てたcursedが一度も立たない(仕様書36.3)。
	var summoner := get_tree().get_first_node_in_group("player") as Player
	if summoner and summoner.weapon_manager:
		contact_hitbox.applied_status_id = summoner.weapon_manager.get_applied_status_id()

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	_lifetime -= delta
	if _lifetime <= 0.0:
		_on_died()
		return
	ai_component.target = _find_nearest_enemy()
	if ai_component.target:
		movement_component.direction = ai_component.compute_direction(global_position)
	else:
		movement_component.direction = Vector2.ZERO
	super._physics_process(delta)

func _find_nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		var health: HealthComponent = e.get_node_or_null("HealthComponent")
		if health == null or health.current_hp <= 0.0:
			continue
		var d := global_position.distance_to(e.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e
	return nearest

func _on_died() -> void:
	if _is_dead:
		return
	_is_dead = true
	contact_hitbox.set_deferred("monitorable", false)
	hurtbox_component.set_deferred("monitorable", false)
	queue_free()
