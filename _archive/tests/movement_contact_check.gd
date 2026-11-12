extends Node2D
## Real Player/Enemy scenes, real physics steps: body contact must not become knockback.

const PLAYER_SCENE := preload("res://entities/player/player.tscn")
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")
const MELEE_SCENE := preload("res://entities/melee_hit/melee_hit.tscn")

var failures: Array[String] = []
var player: Player

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	SaveManager.begin_ephemeral_session()
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	GameManager.selected_character_id = "soldier"
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	player.set_process(false)
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	player.health_component.invincible = true
	player.camera.enabled = false
	await _check_legacy_reproduction()
	await _check_pass_through(1, false)
	await _check_pass_through(32, false)
	await _check_pass_through(1, true)
	await _check_walls_and_attack_knockback()
	await _check_enemy_attack_and_pickup_detection()
	for failure in failures:
		push_error("MOVEMENT_CONTACT_CHECK: " + failure)
	print("MOVEMENT_CONTACT_CHECK failures=%d" % failures.size())
	player.queue_free()
	await get_tree().process_frame
	AudioManager.stop_all(false)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func _spawn_enemy(at: Vector2, boss: bool = false) -> EnemyBasic:
	var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
	if boss:
		enemy.enemy_data = (DataLoader.bosses.get("minotaur") as BossData).duplicate() as BossData
		(enemy.enemy_data as BossData).attack_pattern_id = ""
		enemy.visual_scale_multiplier = (enemy.enemy_data as BossData).visual_scale
	else:
		enemy.enemy_data = EnemyData.new()
		enemy.enemy_data.max_hp = 1000.0
		enemy.enemy_data.move_speed = 0.0
		enemy.enemy_data.contact_damage = 5.0
		enemy.enemy_data.attack_windup = 0.2
	enemy.position = at
	add_child(enemy)
	enemy.set_movement_locked(true)
	return enemy

func _walk(frames: int) -> void:
	player.movement_component.direction = Vector2.RIGHT
	for _frame in frames:
		await get_tree().physics_frame
	player.movement_component.direction = Vector2.ZERO
	await get_tree().physics_frame

func _check_legacy_reproduction() -> void:
	player.position = Vector2(-90, 0)
	var enemy := _spawn_enemy(Vector2.ZERO)
	# Restore the old asymmetric body contract only in this fixture, not product code.
	enemy.remove_collision_exception_with(player)
	player.remove_collision_exception_with(enemy)
	await _walk(90)
	var displacement := enemy.position.length()
	print("MOVEMENT_CONTACT A legacy single enemy displacement=%.3f px" % displacement)
	_check(displacement > 60.0, "legacy asymmetric masks reproduce walking push")
	enemy.queue_free()
	await get_tree().physics_frame

func _check_pass_through(count: int, boss: bool) -> void:
	player.position = Vector2(-90, 0)
	var enemies: Array[EnemyBasic] = []
	var origins: Array[Vector2] = []
	for index in count:
		var at := Vector2((index % 8) * 8, (index / 8) * 8 - 12) if count > 1 else Vector2.ZERO
		var enemy := _spawn_enemy(at, boss)
		enemies.append(enemy)
		origins.append(at)
	await _walk(120)
	var maximum_drift := 0.0
	for index in count:
		maximum_drift = maxf(maximum_drift, enemies[index].position.distance_to(origins[index]))
	print("MOVEMENT_CONTACT B count=%d boss=%s max enemy displacement=%.3f px player x=%.3f" % [count, boss, maximum_drift, player.position.x])
	_check(maximum_drift < 0.01, "walking does not push %d enemies (boss=%s)" % [count, boss])
	_check(player.position.x > 170.0, "player crosses body contact without trapping")
	for enemy in enemies:
		enemy.queue_free()
	await get_tree().physics_frame

func _check_walls_and_attack_knockback() -> void:
	player.position = Vector2(-90, 0)
	var enemy := _spawn_enemy(Vector2.ZERO)
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = Vector2(100, 0)
	var collider := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(20, 400)
	collider.shape = box
	wall.add_child(collider)
	add_child(wall)
	await get_tree().physics_frame
	# Real Area2D hit pipeline still applies damage and intentional attack displacement.
	var hit := MELEE_SCENE.instantiate() as MeleeHit
	hit.damage = 5.0
	hit.setup("", 1, player.position)
	add_child(hit)
	hit.position = player.position
	hit.configure_arc(110.0, Vector2.RIGHT, 70.0, 0.1, 30.0)
	await get_tree().create_timer(0.16).timeout
	_check(enemy.health_component.current_hp < enemy.health_component.max_hp, "Area2D melee still damages enemy")
	_check(is_equal_approx(enemy.position.x, 30.0), "attack knockback remains 30 px")
	enemy.apply_knockback(Vector2.RIGHT, 200.0)
	_check(enemy.position.x <= 72.51, "enemy knockback stops at wall")
	await _walk(120)
	_check(player.position.x <= 70.01 and player.position.x > 69.0, "player movement stops at wall")
	enemy.queue_free()
	wall.queue_free()
	await get_tree().physics_frame
	# Existing Boss 0.1 knockback resistance is owned by MeleeHit and must not change.
	player.position = Vector2(-90, 0)
	var boss := _spawn_enemy(Vector2.ZERO, true)
	var boss_hit := MELEE_SCENE.instantiate() as MeleeHit
	boss_hit.damage_enabled = false
	boss_hit.setup("", 1, player.position)
	add_child(boss_hit)
	boss_hit.configure_arc(110.0, Vector2.RIGHT, 70.0, 0.1, 30.0)
	boss_hit.on_hit(boss.hurtbox_component)
	_check(is_equal_approx(boss.position.x, 3.0), "Boss attack knockback remains 10 percent")
	boss.queue_free()
	await get_tree().create_timer(0.15).timeout

func _check_enemy_attack_and_pickup_detection() -> void:
	player.position = Vector2.ZERO
	player.health_component.invincible = false
	player.health_component._iframe_remaining = 0.0
	var enemy := _spawn_enemy(Vector2.ZERO)
	var hp_before := player.health_component.current_hp
	await get_tree().create_timer(0.12).timeout
	_check(is_equal_approx(player.health_component.current_hp, hp_before), "overlap alone does not create new contact damage")
	enemy.set_movement_locked(false)
	await get_tree().create_timer(0.32).timeout
	_check(is_equal_approx(player.health_component.current_hp, hp_before - 5.0), "overlapping enemy telegraphed attack still hits")
	player.health_component._iframe_remaining = 0.0
	enemy._normal_attack_state = EnemyBasic.NormalAttackState.READY
	enemy._normal_attack_timer = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.position = Vector2(200, 0)
	var hp_after_hit := player.health_component.current_hp
	await get_tree().create_timer(0.32).timeout
	_check(is_equal_approx(player.health_component.current_hp, hp_after_hit), "leaving windup range still avoids damage")
	var detector := Area2D.new()
	detector.collision_layer = 0
	detector.collision_mask = 1
	detector.position = player.position
	var collider := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 35.0
	collider.shape = shape
	detector.add_child(collider)
	add_child(detector)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(player in detector.get_overlapping_bodies(), "existing layer-1 pickup/treasure/interact detection remains valid")
	detector.queue_free()
	enemy.queue_free()
	await get_tree().physics_frame

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
