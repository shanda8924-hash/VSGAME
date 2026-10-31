extends Node2D

const ENEMY := preload("res://entities/enemies/enemy_basic.tscn")
var failures: Array[String] = []
var target: Node2D
var health: HealthComponent

func _ready() -> void:
	SaveManager.begin_ephemeral_session()
	GameManager.dungeon_map = null
	GameManager.run_state = GameManager.RunState.PLAYING
	add_to_group("game_runtime_world")
	target = Node2D.new()
	target.add_to_group("player")
	health = HealthComponent.new()
	health.name = "HealthComponent"
	target.add_child(health)
	var hurtbox := HurtboxComponent.new()
	hurtbox.name = "HurtboxComponent"
	hurtbox.health_component_path = NodePath("../HealthComponent")
	target.add_child(hurtbox)
	add_child(target)
	_run.call_deferred()

func _enemy(id: String, boss := false) -> EnemyBasic:
	var enemy := ENEMY.instantiate() as EnemyBasic
	enemy.enemy_data = DataLoader.bosses[id] if boss else DataLoader.enemies[id]
	enemy.position = Vector2(300,300)
	add_child(enemy)
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.ai_component.target = target
	return enemy

func _run() -> void:
	for id in ["armored_orc","armored_skeleton","greatsword_skeleton","blood_monster_b","elite_orc","werebear"]:
		var enemy := _enemy(id)
		target.position = enemy.position + Vector2(32,0)
		await get_tree().physics_frame
		var move = enemy.strong_attack
		move.cooldown = 0.0
		_check(move.tick(0.01), id+" starts real special")
		var aim: Vector2 = move.direction
		move.tick(0.19)
		_check(move.eye.visible and move.eye.modulate.a > 0.9, id+" eye holds at 0.20s")
		_check(is_equal_approx(move.eye.scale.x,1.6), id+" eye is enlarged")
		var hp := health.current_hp
		target.position = enemy.position + Vector2(-200,0)
		move.tick(0.15)
		_check(move.eye.visible and move.eye.modulate.a > 0.3, id+" eye fades at 0.35s")
		move.tick(0.06)
		_check(not move.eye.visible, id+" cue ends before strike")
		_check(move.direction == aim, id+" does not retarget after cue")
		move.tick(0.39)
		_check(is_equal_approx(health.current_hp,hp), id+" side escape avoids strike")
		_check(move.active and enemy._movement_locked_by_attack, id+" has committed attack/recovery")
		if id == "elite_orc":
			move.tick(0.2)
			_check(move.eye.visible,id+" repeats cue before second slash")
		move.cancel()
		_check(not move.eye.visible and not enemy._movement_locked_by_attack,id+" cancellation clears tell")
		enemy.queue_free()
		await get_tree().process_frame
	var elite := _enemy("armored_orc")
	target.position = Vector2(32,0)
	var hazard := EliteHazard.new()
	hazard.source = elite
	hazard.radius = 64.0
	hazard.damage = 7.0
	hazard.warning_only = true
	hazard.warning_duration = 0.75
	add_child(hazard)
	hazard.set_process(false)
	var hp := health.current_hp
	hazard._process(0.5)
	_check(health.current_hp == hp,"No damage during elite tell")
	_check(is_equal_approx(hazard._ring.scale.x*WarningCircle.RING_PIXEL_RADIUS,64.0),"Elite boundary stays at real damage radius")
	target.position = Vector2(65,0)
	hazard._process(0.26)
	_check(health.current_hp == hp,"Outside elite boundary is safe")
	hazard.queue_free()
	var component := EliteAffixComponent.new()
	component.configure(elite,["fire","lightning"],{"fire":{"warning_time":0.1},"lightning":{"warning_time":0.1}})
	elite.add_child(component)
	component._timers = {"fire":0.0,"lightning":0.0}
	component._process(0.01)
	_check(component._ability_left >= 1.3,"Elite tell includes 0.75s warning and counter recovery")
	_check(elite._movement_locked_by_attack,"Elite holds still for its ability")
	elite.strong_attack.cooldown = 0.0
	_check(not elite.strong_attack.tick(0.01),"Elite special cannot overlap periodic ability")
	var hazards := 0
	for child in get_children():
		if child is EliteHazard and not child.is_queued_for_deletion(): hazards += 1
	_check(hazards == 1,"Only one periodic ability starts at once")
	elite._is_dead = true
	await get_tree().process_frame
	await get_tree().process_frame
	hazards = 0
	for child in get_children():
		if child is EliteHazard and not child.is_queued_for_deletion(): hazards += 1
	_check(hazards == 0,"Death cancels elite hazards")
	elite.queue_free()
	await get_tree().process_frame
	var boss := _enemy("demon_a",true)
	var slam := SlamStrategy.new()
	target.position = boss.position + Vector2(120,0)
	hp = health.current_hp
	slam.execute(boss,target)
	await get_tree().create_timer(0.1).timeout
	_check(boss._movement_locked_by_attack,"Boss locks aim during warning")
	var circles := get_children().filter(func(n): return n is WarningCircle)
	_check(circles.size() == 1 and is_equal_approx(circles[0].duration,0.9),"Boss warning exposes exact countdown")
	target.position += Vector2(0,200)
	await get_tree().create_timer(0.85).timeout
	_check(health.current_hp == hp,"Leaving boss marked area avoids damage")
	_check(boss._movement_locked_by_attack,"Boss leaves recovery window after missing")
	await get_tree().create_timer(1.6).timeout
	_check(not boss._movement_locked_by_attack,"Boss recovery releases normally")
	slam.execute(boss,target)
	await get_tree().create_timer(0.1).timeout
	boss._is_dead = true
	await get_tree().create_timer(0.95).timeout
	_check(health.current_hp == hp,"Dead boss cannot finish delayed attack")
	boss.queue_free()
	await get_tree().process_frame
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	_check(not game.has_node("RoomRunController") and not game.has_node("RoomSelect"),"Production scene has no ROOM mode")
	game.free()
	_check(not FileAccess.file_exists("res://prototypes/hd2d/hd2d_arena.tscn"),"HD-2D entry deleted")
	for message in failures: push_error(message)
	print("COMBAT_TELEGRAPH_CHECK failures=%d; six strong cues, fixed aim, elite serialization, cancel, boss recovery, retired modes" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
