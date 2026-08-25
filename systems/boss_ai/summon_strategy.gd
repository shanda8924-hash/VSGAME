extends BossAttackStrategy
class_name SummonStrategy
## 「summon」攻撃: 定期的に周囲へ雑魚敵を2〜3体召喚する。
## 既存のdata/enemies/(WaveSpawnerが使うのと同じDataLoader.enemies)から
## 手頃な敵IDをランダムに選ぶだけなので、新しいデータを追加しなくても機能する。

@export var summon_count_min: int = 2
@export var summon_count_max: int = 3
@export var summon_enemy_ids: Array[String] = ["basic_enemy", "fast_enemy", "bat", "slime"]
@export var summon_radius: float = 130.0
@export var telegraph_duration: float = 0.75

func _init() -> void:
	interval = 9.0
	recovery_duration = 1.25

func execute(boss: EnemyBasic, _player: Node2D) -> void:
	if not is_instance_valid(boss):
		return
	boss.set_movement_locked(true)
	boss.movement_component.direction = Vector2.ZERO
	var warning := WarningCircle.new()
	warning.radius = summon_radius
	warning.fill_color = Color(0.35, 0.1, 0.45, 0.18)
	warning.border_color = Color(0.75, 0.35, 0.9, 0.9)
	GameManager.get_runtime_world(boss).add_child(warning)
	warning.global_position = boss.global_position
	await boss.get_tree().create_timer(telegraph_duration).timeout
	if is_instance_valid(warning):
		warning.queue_free()
	if not is_instance_valid(boss):
		return
	var enemy_scene: PackedScene = load("res://entities/enemies/enemy_basic.tscn")
	var count: int = randi_range(summon_count_min, summon_count_max)
	for i in count:
		if not is_instance_valid(boss):
			return
		var enemy_id: String = summon_enemy_ids[randi() % summon_enemy_ids.size()]
		var data: EnemyData = DataLoader.enemies.get(enemy_id)
		if data == null:
			continue
		var enemy := enemy_scene.instantiate()
		enemy.enemy_data = data
		enemy.room_hp_multiplier = float(boss.get_meta("summon_hp_multiplier", 1.0))
		enemy.room_damage_multiplier = float(boss.get_meta("summon_damage_multiplier", 1.0))
		enemy.add_to_group("boss_summons")
		GameManager.get_runtime_world(boss).add_child(enemy)
		var angle: float = TAU * float(i) / float(count) + randf_range(-0.3, 0.3)
		enemy.global_position = boss.global_position + Vector2(cos(angle), sin(angle)) * summon_radius
	await wait_recovery(boss)
