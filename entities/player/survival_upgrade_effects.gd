extends Node2D
## Direct hits alone seed bounded follow-ups; secondary damage cannot seed another.
var actor: Player
var _echo_cooldown := 0.0
var _chain_cooldown := 0.0
var _guard_timer := 0.0
var _echo_delay := -1.0
var _echo_target: WeakRef
var _echo_position := Vector2.ZERO
var _echo_damage := 0.0
var _pending_chain: Dictionary = {}
var _marks: Array[Dictionary] = []
var _slash: Texture2D = preload("res://assets/vfx/equipment_comfy/slash_6f.png")
var debug_echo_hits := 0
var debug_chain_hits := 0

func _ready() -> void:
	actor = get_parent() as Player
	z_index = 4
	EventBus.enemy_damage_confirmed.connect(_on_hit)
	set_process(true)

func _on_hit(target: Node, amount: float, _critical: bool, metadata: Dictionary) -> void:
	if not is_instance_valid(actor) or actor._is_dead or not is_instance_valid(target) or not bool(metadata.get("is_direct", false)) or amount <= 0:
		return
	var upgrades := actor.upgrades_component
	var pos: Vector2 = metadata.get("impact_position", (target as Node2D).global_position)
	if upgrades.get_survival_rank("survival_echo") > 0 and _echo_cooldown <= 0:
		_echo_cooldown = 0.6
		_echo_delay = 0.18
		_echo_target = weakref(target)
		_echo_position = pos
		_echo_damage = amount * (0.25 + 0.05 * upgrades.get_survival_rank("survival_echo"))
	if upgrades.get_survival_rank("survival_chain") > 0 and _chain_cooldown <= 0:
		_chain_cooldown = 0.7
		_pending_chain = {"origin":pos,"exclude":target.get_instance_id(),"damage":amount * 0.35}
	var power := upgrades.get_survival_rank("survival_power")
	if power > 0 and _marks.size() < 32:
		_marks.append({"kind":"power","from":pos,"to":pos,"life":0.20,"rank":power})

func _process(delta: float) -> void:
	if actor == null or actor._is_dead or GameManager.run_state != GameManager.RunState.PLAYING:
		return
	_echo_cooldown = maxf(_echo_cooldown - delta, 0)
	_chain_cooldown = maxf(_chain_cooldown - delta, 0)
	_guard_timer -= delta
	var guard := actor.upgrades_component.get_survival_rank("survival_guard")
	if guard > 0 and _guard_timer <= 0:
		_guard_timer = 8.0
		actor.health_component.grant_temporary_shield(maxf(actor.health_component.shield_amount, guard * 8.0))
	if _echo_delay >= 0:
		_echo_delay -= delta
		if _echo_delay < 0: _echo()
	if not _pending_chain.is_empty():
		var pending := _pending_chain
		_pending_chain = {}
		_chain(pending)
	for index in range(_marks.size()-1,-1,-1):
		_marks[index].life -= delta
		if _marks[index].life <= 0: _marks.remove_at(index)
	queue_redraw()

func _limit() -> float:
	var manager := actor.weapon_manager
	var radius := manager.get_class_attack_range()
	if manager.equipment_attack.item:
		radius = maxf(radius, manager.equipment_attack.get_range(manager))
	return radius + 16.0

func _echo() -> void:
	var target := _echo_target.get_ref() as Node2D if _echo_target else null
	var health := target.get_node_or_null("HealthComponent") as HealthComponent if is_instance_valid(target) else null
	if health == null or health.current_hp <= 0:
		target = actor.weapon_manager.find_nearest_enemy(_echo_position, 96.0, true)
		health = target.get_node_or_null("HealthComponent") as HealthComponent if target else null
	if health == null or actor.global_position.distance_to(target.global_position) > _limit(): return
	var ray := PhysicsRayQueryParameters2D.create(actor.global_position, target.global_position, 1, [actor.get_rid()])
	if not actor.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): return
	var point := target.global_position
	var dealt := health.apply_secondary_damage(_echo_damage, CombatEventMeta.create_secondary("player_survival_echo", [], false))
	if dealt > 0:
		debug_echo_hits += 1
		_marks.append({"kind":"echo","from":point,"to":point,"life":0.24,"rank":actor.upgrades_component.get_survival_rank("survival_echo")})

func _chain(pending: Dictionary) -> void:
	var from: Vector2 = pending.origin
	var visited := {int(pending.exclude):true}
	for index in actor.upgrades_component.get_survival_rank("survival_chain"):
		var target: Node2D
		var nearest := 120.0
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if visited.has(enemy.get_instance_id()) or actor.global_position.distance_to(enemy.global_position) > _limit(): continue
			var health := enemy.get_node_or_null("HealthComponent") as HealthComponent
			if health == null or health.current_hp <= 0: continue
			var distance: float = from.distance_to(enemy.global_position)
			if distance >= nearest: continue
			var ray := PhysicsRayQueryParameters2D.create(from, enemy.global_position, 1, [actor.get_rid()])
			if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): continue
			nearest = distance
			target = enemy
		if target == null: break
		visited[target.get_instance_id()] = true
		var point := target.global_position
		var dealt := (target.get_node("HealthComponent") as HealthComponent).apply_secondary_damage(float(pending.damage), CombatEventMeta.create_secondary("player_survival_chain", [], false))
		if dealt > 0:
			debug_chain_hits += 1
			_marks.append({"kind":"chain","from":from,"to":point,"life":0.24,"rank":1})
		from = point

func _draw() -> void:
	if actor == null: return
	if actor.upgrades_component.get_survival_rank("survival_guard") > 0 and actor.health_component.shield_amount > 0:
		var fraction := actor.health_component.shield_amount / maxf(actor.health_component.shield_max, 1)
		draw_arc(Vector2(0,-12),27.0,-PI * 0.5,-PI * 0.5+TAU*fraction,24,Color(0.35,0.85,1,0.7),2,false)
		var guard_rank := actor.upgrades_component.get_survival_rank("survival_guard")
		for index in 2+guard_rank:
			var p := Vector2.from_angle(index * TAU / (2+guard_rank) + Time.get_ticks_msec() * 0.001) * 27 + Vector2(0,-12)
			draw_rect(Rect2(p-Vector2(2,2),Vector2(4,4)),Color("80e4ff"))
	for mark in _marks:
		var point := to_local(mark.to)
		var color := Color("90ddff") if mark.kind == "echo" else Color("ffdf64")
		color.a = clampf(float(mark.life) / 0.12,0,1)
		if mark.kind == "chain":
			var start := to_local(mark.from)
			var mid := start.lerp(point,0.5) + Vector2(3,-7)
			draw_polyline(PackedVector2Array([start,mid,mid+Vector2(-6,5),point]),color,3,false)
		elif mark.kind == "echo":
			var frame := clampi(int((0.24-float(mark.life))/0.24*6),0,5)
			for index in int(mark.rank):
				draw_texture_rect_region(_slash,Rect2(point-Vector2(25+index*4,25),Vector2(50,50)),Rect2(Vector2(frame*_slash.get_width()/6.0,0),Vector2(_slash.get_width()/6.0,_slash.get_height())),Color(color,color.a*(1.0-index*0.22)))
		else:
			var radius := minf(10 + float(mark.rank) * 2.5,26)
			for index in 6:
				var direction := Vector2.from_angle(index*TAU/6)
				draw_line(point+direction*4,point+direction*radius,color,2,false)
