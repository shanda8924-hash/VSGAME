extends BossAttackStrategy
class_name MinotaurComboStrategy
## HD-2D試作で成立した4攻撃を、通常2D MAPの座標・描画へ移植する。

const ZONE := preload("res://systems/boss_ai/boss_attack_zone_2d.gd")
const PERFORMANCE := preload("res://systems/boss_ai/boss_attack_performance_2d.gd")
const SWEEP_DURATION := 0.18

var next_pattern := 0
var last_pattern := ""
var attack_count := 0
var active_zone: Node2D
var active_performance: Node2D
var sweep_progress := 0.0

func _init() -> void:
	interval = 2.2
	recovery_duration = 1.5

func alive(boss: EnemyBasic) -> bool:
	return is_instance_valid(boss) and not boss.is_queued_for_deletion() and boss.health_component.current_hp > 0.0 and boss.boss_attack_component != null and boss.boss_attack_component.process_mode != Node.PROCESS_MODE_DISABLED

func execute(boss: EnemyBasic, player: Node2D) -> void:
	var runtime_world := GameManager.get_runtime_world(boss)
	if not alive(boss) or not is_instance_valid(player) or runtime_world == null:
		return
	var pattern: String = ["charge", "cleave", "ring", "barrage"][next_pattern]
	next_pattern = (next_pattern + 1) % 4
	last_pattern = pattern
	attack_count += 1
	boss.set_meta("active_boss_pattern", pattern)
	if is_instance_valid(boss._attack_warning):
		boss._attack_warning.queue_free()
	boss._attack_warning = null
	boss._normal_attack_state = EnemyBasic.NormalAttackState.COOLDOWN
	boss._normal_attack_timer = 0.7
	boss.set_movement_locked(true)
	boss.movement_component.direction = Vector2.ZERO
	var repeats := 3 if pattern == "barrage" else 1
	for _step in repeats:
		if not alive(boss) or not is_instance_valid(player):
			break
		active_zone = ZONE.new()
		active_zone.origin = player.global_position if pattern == "barrage" else boss.global_position
		active_zone.direction = (player.global_position - boss.global_position).normalized()
		if active_zone.direction.is_zero_approx():
			active_zone.direction = Vector2.RIGHT
		active_zone.kind = {"charge": "line", "cleave": "cone", "ring": "circle", "barrage": "circle"}[pattern]
		active_zone.radius = 145.0 if pattern == "cleave" else 180.0 if pattern == "ring" else 62.0
		active_zone.inner_radius = 75.0 if pattern == "ring" else 0.0
		runtime_world.add_child(active_zone)
		var cleanup := active_zone.queue_free
		boss.health_component.died.connect(cleanup, CONNECT_ONE_SHOT)
		var tree := boss.get_tree()
		var tell := 0.85 if pattern == "barrage" else 1.05
		if is_instance_valid(active_performance):
			active_performance.cancel()
		active_performance = PERFORMANCE.new()
		active_performance.setup(boss, pattern, active_zone, tell)
		runtime_world.add_child(active_performance)
		sweep_progress = 0.0
		var committed_position := boss.global_position
		var displaced := false
		for tick in 7:
			await tree.create_timer(tell / 7.0, false).timeout
			if not alive(boss) or not is_instance_valid(active_zone):
				break
			if pattern == "cleave" and boss.global_position.distance_to(committed_position) > 2.0:
				displaced = true
				break
			active_zone.progress = float(tick + 1) / 7.0
			active_zone.redraw()
		if displaced or not alive(boss) or not is_instance_valid(player) or not is_instance_valid(active_zone):
			_cleanup_step(boss, cleanup)
			break
		active_zone.impact = true
		active_zone.redraw()
		if is_instance_valid(active_performance):
			active_performance.strike()
		if pattern == "charge":
			await _execute_charge(boss, player, active_zone)
		elif pattern == "cleave":
			await _execute_cleave(boss, player, active_zone, active_performance, committed_position)
		elif active_zone.contains(player.global_position):
			player.health_component.apply_damage(boss.contact_hitbox.damage)
		if pattern != "cleave":
			await tree.create_timer(0.18, false).timeout
		_cleanup_step(boss, cleanup)
	if alive(boss):
		boss.set_meta("active_boss_pattern", "recovery")
		boss.set_movement_locked(true)
		boss.movement_component.direction = Vector2.ZERO
		await boss.get_tree().create_timer(recovery_duration, false).timeout
		if alive(boss):
			boss.set_movement_locked(false)
			boss.set_meta("active_boss_pattern", "chase")

func _execute_charge(boss: EnemyBasic, player: Node2D, zone: Node2D) -> void:
	var original_speed := boss.movement_component.base_speed
	boss.movement_component.base_speed = 700.0
	boss.movement_component.direction = zone.direction
	var elapsed := 0.0
	var hit := false
	while elapsed < 0.4 and alive(boss):
		await boss.get_tree().physics_frame
		if boss.get_tree().paused:
			continue
		elapsed += boss.get_physics_process_delta_time()
		if not hit and is_instance_valid(player) and zone.contains(player.global_position) and boss.global_position.distance_to(player.global_position) <= 55.0:
			player.health_component.apply_damage(boss.contact_hitbox.damage)
			hit = true
	if is_instance_valid(boss):
		boss.movement_component.base_speed = original_speed
		boss.movement_component.direction = Vector2.ZERO

func _execute_cleave(boss: EnemyBasic, player: Node2D, zone: Node2D, performance: Node2D, committed_position: Vector2) -> void:
	var hit := false
	var elapsed := 0.0
	while sweep_progress < 1.0 and alive(boss):
		await boss.get_tree().physics_frame
		if not is_instance_valid(zone) or not is_instance_valid(performance):
			break
		if boss.get_tree().paused:
			continue
		if boss.global_position.distance_to(committed_position) > 2.0:
			performance.cancel()
			break
		var previous := sweep_progress
		elapsed += boss.get_physics_process_delta_time()
		sweep_progress = minf(elapsed / SWEEP_DURATION, 1.0)
		performance.set_sweep_progress(sweep_progress)
		if not hit and is_instance_valid(player) and zone.contains_sweep(player.global_position, previous, sweep_progress, performance.reverse_sweep):
			player.health_component.apply_damage(boss.contact_hitbox.damage)
			hit = true
	if is_instance_valid(performance):
		performance.finish_sweep()

func _cleanup_step(boss: EnemyBasic, cleanup: Callable) -> void:
	if is_instance_valid(boss) and boss.health_component.died.is_connected(cleanup):
		boss.health_component.died.disconnect(cleanup)
	if is_instance_valid(active_zone):
		active_zone.queue_free()
	active_zone = null
	if is_instance_valid(active_performance):
		active_performance.cancel()
