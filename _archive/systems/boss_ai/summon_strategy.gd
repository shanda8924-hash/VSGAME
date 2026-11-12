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
	if not alive(boss):
		return
	begin_attack(boss)
	var warning := warning_circle(boss, boss.global_position, summon_radius, telegraph_duration)
	warning.border_color = Color("bb8fe8")
	warning.get_node("PixelRing").modulate = warning.border_color
	await boss.get_tree().create_timer(telegraph_duration, false).timeout
	if is_instance_valid(warning):
		warning.queue_free()
	if not alive(boss):
		return
	var enemy_scene: PackedScene = load("res://entities/enemies/enemy_basic.tscn")
	var count: int = randi_range(summon_count_min, summon_count_max)
	var wave := GameManager.get_runtime_world(boss).get_node_or_null("WaveSpawner") as WaveSpawner
	for i in count:
		if GameManager.survival_mode_active and (wave == null or wave._spawning_paused or wave._active_enemy_count() >= wave._map_enemy_cap):
			break
		if not alive(boss):
			return
		var enemy_id: String = summon_enemy_ids[randi() % summon_enemy_ids.size()]
		var data: EnemyData = DataLoader.enemies.get(enemy_id)
		if data == null:
			continue
		var angle: float = TAU * float(i) / float(count) + randf_range(-0.3, 0.3)
		var spawn_position := boss.global_position + Vector2(cos(angle), sin(angle)) * summon_radius
		if GameManager.dungeon_map != null:
			spawn_position = GameManager.dungeon_map.find_spawn_position_near(spawn_position)
		if not spawn_position.is_finite():
			continue
		var enemy := enemy_scene.instantiate()
		enemy.enemy_data = data
		enemy.room_hp_multiplier = float(boss.get_meta("summon_hp_multiplier", 1.0))
		enemy.room_damage_multiplier = float(boss.get_meta("summon_damage_multiplier", 1.0))
		enemy.add_to_group("boss_summons")
		GameManager.get_runtime_world(boss).add_child(enemy)
		enemy.global_position = spawn_position
	await wait_recovery(boss)
