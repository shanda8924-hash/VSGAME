extends AttackPatternBase
class_name SummonMinionAttack
## Necromancer(summon_minion): 一定間隔で味方スケルトン(entities/allies/
## ally_skeleton.tscn)を1体召喚する。既存のEnemyBasic/AIComponentの仕組み
## (ChaseStrategyによる追跡・HitboxComponent/HurtboxComponentによる被弾/与ダメージ)を
## そのまま流用しつつ、追跡対象を敵に、衝突レイヤーを味方用に入れ替えたものを使う
## (entities/allies/ally_skeleton.gd参照)。同時召喚数の上限を超える場合は召喚しない。

const DEFAULT_MAX_COUNT := 3
const DEFAULT_MINION_HP := 40.0
const DEFAULT_MINION_SPEED := 110.0
const DEFAULT_MINION_DAMAGE := 8.0
const DEFAULT_MINION_LIFETIME := 25.0
const DEFAULT_SPRITE_FOLDER := "enemy/Skeleton"
const ALLY_SCENE_PATH := "res://entities/allies/ally_skeleton.tscn"
## 職業専用強化(ability_level、2026年8月追加、Necromancer固有)。
## Lv2 召喚上限+1 / Lv3 味方ステータス+20% / Lv4 召喚間隔-20% /
## Lv5 味方死亡時に爆発ダメージ。
const LV3_STAT_MULTIPLIER := 1.2
const LV5_DEATH_EXPLOSION_RADIUS := 60.0

var _active_minion_ids: Array = []

func get_interval(character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> float:
	var interval := super.get_interval(character_data, weapon_manager)
	if ability_level >= 4:
		interval *= 0.8
	return interval

func execute(attacker: Player, character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> void:
	if not is_instance_valid(attacker):
		return
	_prune_dead_minions()

	var params := character_data.attack_pattern_params
	var max_count: int = params.get("minion_max_count", DEFAULT_MAX_COUNT)
	if ability_level >= 2:
		max_count += 1
	if _active_minion_ids.size() >= max_count:
		return

	var stat_multiplier := character_data.minion_stat_multiplier
	if ability_level >= 3:
		stat_multiplier *= LV3_STAT_MULTIPLIER
	var minion_hp: float = params.get("minion_hp", DEFAULT_MINION_HP) * stat_multiplier
	var minion_speed: float = params.get("minion_speed", DEFAULT_MINION_SPEED)
	var minion_damage: float = params.get("minion_damage", DEFAULT_MINION_DAMAGE) * stat_multiplier
	var minion_lifetime: float = params.get("minion_lifetime", DEFAULT_MINION_LIFETIME)
	var sprite_folder: String = params.get("minion_sprite_folder", DEFAULT_SPRITE_FOLDER)

	var ally_scene: PackedScene = load(ALLY_SCENE_PATH)
	var ally := ally_scene.instantiate()
	# setup()はHealthComponent等の@onready参照へ直接書き込むため、
	# ノードがツリーに入って_ready()が済んだ後(add_child後)に呼ぶ必要がある。
	GameManager.get_runtime_world(attacker).add_child(ally)
	ally.setup(minion_hp, minion_speed, minion_damage, sprite_folder, minion_lifetime)
	var spawn_angle := randf() * TAU
	ally.global_position = attacker.global_position + Vector2(cos(spawn_angle), sin(spawn_angle)) * 40.0
	_active_minion_ids.append(ally.get_instance_id())
	if ability_level >= 5:
		var health: HealthComponent = ally.get_node_or_null("HealthComponent")
		if health:
			health.died.connect(_on_minion_died.bind(ally, character_data, weapon_manager))

## Lv5: 味方スケルトンが死亡した瞬間、その場に周囲へダメージを与える爆発を発生させる。
## died signalは実際にqueue_free()される前(HealthComponent.apply_damage内)に
## 同期発火するため、この時点でのally.global_positionはまだ有効。
func _on_minion_died(ally: Node2D, character_data: CharacterData, weapon_manager: WeaponManagerComponent) -> void:
	if ally == null or not is_instance_valid(ally):
		return
	apply_area_damage(ally.get_world_2d(), ally.global_position, LV5_DEATH_EXPLOSION_RADIUS, character_data, weapon_manager, ally.global_position)

func _prune_dead_minions() -> void:
	var alive: Array = []
	for id in _active_minion_ids:
		if is_instance_id_valid(id) and is_instance_valid(instance_from_id(id)):
			alive.append(id)
	_active_minion_ids = alive

## この攻撃パターンが命中時に付与する状態異常。死霊術が対象を呪う。
func applied_status_id() -> String:
	return "cursed"
