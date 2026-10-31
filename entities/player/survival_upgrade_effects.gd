extends Node2D
## Direct hits alone seed bounded follow-ups; secondary damage cannot seed another.
var actor: Player
## 発動はクールダウンではなく命中回数で数える（Phase 2）。攻撃速度・連撃・弾数が
## そのまま発動回数に直結し、シナジーの土台になる。数値はdata/upgrades/*.jsonのnumbers。
var _echo_hits := 0
var _chain_accumulator := 0.0
var _guard_timer := 0.0
## 進化（Phase 3）：影走りの自律斬り、帯電結界のシールド割れ、雷帝落雷→連鎖。
var _shadow_timer := 0.0
var _last_hit_amount := 0.0
var _last_shield := 0.0
var debug_shadow_hits := 0
var debug_ward_hits := 0
var _echo_delay := -1.0
var _echo_target: WeakRef
var _echo_position := Vector2.ZERO
var _echo_damage := 0.0
var _pending_chain: Dictionary = {}
var _marks: Array[Dictionary] = []
# tools/vfx_unified/style.py のランプと同じ色（暗縁・明・芯）。
const STEEL_DARK := Color("2f5d8a")
const STEEL_LIGHT := Color("90ddff")
const STEEL_CORE := Color("f4fdff")
const LIGHTNING_DARK := Color("3f4fd0")
const LIGHTNING_LIGHT := Color("ffdf64")
const LIGHTNING_CORE := Color("fffbe8")
var _slash: Texture2D = preload("res://assets/vfx/equipment_comfy/slash_6f.png")
var debug_echo_hits := 0
var debug_chain_hits := 0

func _ready() -> void:
	actor = get_parent() as Player
	z_index = 4
	EventBus.enemy_damage_confirmed.connect(_on_hit)
	EventBus.upgrade_triggered.connect(_on_upgrade_triggered)
	if actor and actor.health_component:
		actor.health_component.shield_changed.connect(_on_shield_changed)
	set_process(true)

func has_evolution(id: String) -> bool:
	return is_instance_valid(actor) and actor.upgrades_component != null and actor.upgrades_component.has_evolution(id)

## 雷帝落雷（秘技）が落ちた場所から、雷光連鎖を持っていれば必ず連鎖させる（秘技×雷タグ）。
func _on_upgrade_triggered(upgrade_id: String, position: Vector2) -> void:
	if upgrade_id != "arcana_thunderlord_descent" or not is_instance_valid(actor) or actor._is_dead:
		return
	var rank := actor.upgrades_component.get_survival_rank("survival_chain")
	if rank <= 0 or not _pending_chain.is_empty():
		return
	_pending_chain = {"origin": position, "exclude": -1, "damage": maxf(_last_hit_amount, 10.0) * 0.6}

## 帯電結界：シールドが割れた瞬間、周囲の敵へ雷。
func _on_shield_changed(current_shield: float, _max_shield: float) -> void:
	var broke := _last_shield > 0.0 and current_shield <= 0.0
	_last_shield = current_shield
	if not broke or not has_evolution("evo_charged_ward") or actor._is_dead or GameManager.run_state != GameManager.RunState.PLAYING:
		return
	var numbers := _numbers("evo_charged_ward")
	var radius := float(numbers.get("radius", 150.0))
	var damage := float(numbers.get("damage_per_guard_rank", 12.0)) * actor.upgrades_component.get_survival_rank("survival_guard") + _last_hit_amount * float(numbers.get("hit_pct", 0.5))
	var origin := actor.global_position
	var struck := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or origin.distance_to(enemy.global_position) > radius:
			continue
		var health := enemy.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.current_hp <= 0:
			continue
		if health.apply_secondary_damage(damage, CombatEventMeta.create_secondary("player_evo_charged_ward", [], false)) > 0:
			struck += 1
			debug_ward_hits += 1
			_marks.append({"kind":"chain","from":origin,"to":enemy.global_position,"life":0.3,"rank":1})
	if struck > 0:
		EventBus.upgrade_triggered.emit("evo_charged_ward", origin)

## 影走り：0.5秒ごとに、影が自分で近くの敵を斬る（直前の一撃の40%）。
func _shadow_strike() -> void:
	if _last_hit_amount <= 0.0:
		return
	var target := actor.weapon_manager.find_nearest_enemy(actor.global_position, _limit(), true)
	var health := target.get_node_or_null("HealthComponent") as HealthComponent if target else null
	if health == null or health.current_hp <= 0:
		return
	var dealt := health.apply_secondary_damage(_last_hit_amount * float(_numbers("evo_shadow_run").get("damage_pct", 0.4)), CombatEventMeta.create_secondary("player_evo_shadow_run", [], false))
	if dealt > 0:
		debug_shadow_hits += 1
		_marks.append({"kind":"echo","from":target.global_position,"to":target.global_position,"life":0.24,"rank":3})
		EventBus.upgrade_triggered.emit("evo_shadow_run", target.global_position)

func _on_hit(target: Node, amount: float, _critical: bool, metadata: Dictionary) -> void:
	if not is_instance_valid(actor) or actor._is_dead or not is_instance_valid(target) or not bool(metadata.get("is_direct", false)) or amount <= 0:
		return
	var upgrades := actor.upgrades_component
	var pos: Vector2 = metadata.get("impact_position", (target as Node2D).global_position)
	_last_hit_amount = amount
	var echo_rank := upgrades.get_survival_rank("survival_echo")
	if echo_rank > 0:
		_echo_hits += 1
		if _echo_hits >= echo_every_n(echo_rank):
			_echo_hits = 0
			var numbers := _numbers("survival_echo")
			_echo_delay = 0.18
			_echo_target = weakref(target)
			_echo_position = pos
			_echo_damage = amount * (float(numbers.get("damage_pct", 0.25)) + float(numbers.get("damage_pct_per_rank", 0.05)) * echo_rank)
	var chain_rank := upgrades.get_survival_rank("survival_chain")
	if chain_rank > 0 and _pending_chain.is_empty():
		# 確率は貯金式（擬似乱数）。35%なら3回に1回は必ず渡り、運だけで空振りが続かない。
		_chain_accumulator += chain_chance(chain_rank)
		if _chain_accumulator >= 1.0:
			_chain_accumulator -= 1.0
			var damage_pct := float(_numbers("survival_chain").get("damage_pct", 0.35))
			if has_evolution("evo_thunder_strike"):
				damage_pct = float(_numbers("evo_thunder_strike").get("damage_pct", 0.5))
			_pending_chain = {"origin":pos,"exclude":target.get_instance_id(),"damage":amount * damage_pct}
	var power := upgrades.get_survival_rank("survival_power")
	if power > 0 and _marks.size() < 32:
		_marks.append({"kind":"power","from":pos,"to":pos,"life":0.20,"rank":power})

func _process(delta: float) -> void:
	if actor == null or actor._is_dead or GameManager.run_state != GameManager.RunState.PLAYING:
		return
	_guard_timer -= delta
	var guard := actor.upgrades_component.get_survival_rank("survival_guard")
	if guard > 0 and _guard_timer <= 0:
		var numbers := _numbers("survival_guard")
		_guard_timer = float(numbers.get("every_seconds", 8.0))
		actor.health_component.grant_temporary_shield(maxf(actor.health_component.shield_amount, guard * float(numbers.get("shield_per_rank", 8.0))))
		EventBus.upgrade_triggered.emit("survival_guard", actor.global_position)
	if has_evolution("evo_shadow_run"):
		_shadow_timer -= delta
		if _shadow_timer <= 0.0:
			_shadow_timer = float(_numbers("evo_shadow_run").get("interval", 0.5))
			_shadow_strike()
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

func _numbers(id: String) -> Dictionary:
	var upgrade: UpgradeData = DataLoader.upgrades.get(id)
	return upgrade.numbers if upgrade else {}

## 残影追撃が発動する命中回数（段階で短くなる）。カード・HUDの文もこれを使う。
func echo_every_n(rank: int) -> int:
	if has_evolution("evo_shadow_run"):
		return maxi(int(_numbers("evo_shadow_run").get("every_n", 1)), 1)
	var by_rank: Array = _numbers("survival_echo").get("every_n_by_rank", [3, 3, 2])
	if by_rank.is_empty():
		return 3
	return maxi(int(by_rank[clampi(rank - 1, 0, by_rank.size() - 1)]), 1)

## 雷光連鎖が命中1回で渡る確率（段階で上がる）。
func chain_chance(rank: int) -> float:
	if has_evolution("evo_thunder_strike"):
		return clampf(float(_numbers("evo_thunder_strike").get("chance", 1.0)), 0.0, 1.0)
	var numbers := _numbers("survival_chain")
	return clampf(float(numbers.get("chance", 0.35)) + float(numbers.get("chance_per_rank", 0.15)) * (rank - 1), 0.0, 1.0)

## 連鎖する体数。雷帝の連撃で+1。
func chain_targets(rank: int) -> int:
	return rank + (int(_numbers("evo_thunder_strike").get("extra_targets", 1)) if has_evolution("evo_thunder_strike") else 0)

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
		EventBus.upgrade_triggered.emit("survival_echo", point)

func _chain(pending: Dictionary) -> void:
	var from: Vector2 = pending.origin
	var visited := {int(pending.exclude):true}
	for index in chain_targets(actor.upgrades_component.get_survival_rank("survival_chain")):
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
			if index == 0:
				EventBus.upgrade_triggered.emit("survival_chain", point)
		from = point

func _draw() -> void:
	if actor == null: return
	if actor.upgrades_component.get_survival_rank("survival_guard") > 0 and actor.health_component.shield_amount > 0:
		var fraction := actor.health_component.shield_amount / maxf(actor.health_component.shield_max, 1)
		# 色は tools/vfx_unified/style.py の steel ランプ（暗縁→本体→明）。
		draw_arc(Vector2(0,-12),27.0,-PI * 0.5,-PI * 0.5+TAU*fraction,24,Color(STEEL_DARK,0.8),4,false)
		draw_arc(Vector2(0,-12),27.0,-PI * 0.5,-PI * 0.5+TAU*fraction,24,Color(STEEL_LIGHT,0.85),2,false)
		var guard_rank := actor.upgrades_component.get_survival_rank("survival_guard")
		for index in 2+guard_rank:
			var p := Vector2.from_angle(index * TAU / (2+guard_rank) + Time.get_ticks_msec() * 0.001) * 27 + Vector2(0,-12)
			draw_rect(Rect2(p-Vector2(3,3),Vector2(6,6)),STEEL_DARK)
			draw_rect(Rect2(p-Vector2(2,2),Vector2(4,4)),STEEL_LIGHT)
			draw_rect(Rect2(p-Vector2(1,1),Vector2(2,2)),STEEL_CORE)
	for mark in _marks:
		var point := to_local(mark.to)
		var color := STEEL_LIGHT if mark.kind == "echo" else LIGHTNING_LIGHT
		color.a = clampf(float(mark.life) / 0.12,0,1)
		if mark.kind == "chain":
			var start := to_local(mark.from)
			var mid := start.lerp(point,0.5) + Vector2(3,-7)
			var bolt := PackedVector2Array([start,mid,mid+Vector2(-6,5),point])
			draw_polyline(bolt,Color(LIGHTNING_DARK,color.a),5,false)
			draw_polyline(bolt,color,3,false)
			draw_polyline(bolt,Color(LIGHTNING_CORE,color.a),1,false)
		elif mark.kind == "echo":
			var frame := clampi(int((0.24-float(mark.life))/0.24*6),0,5)
			for index in int(mark.rank):
				draw_texture_rect_region(_slash,Rect2(point-Vector2(25+index*4,25),Vector2(50,50)),Rect2(Vector2(frame*_slash.get_width()/6.0,0),Vector2(_slash.get_width()/6.0,_slash.get_height())),Color(color,color.a*(1.0-index*0.22)))
		else:
			var radius := minf(10 + float(mark.rank) * 2.5,26)
			for index in 6:
				var direction := Vector2.from_angle(index*TAU/6)
				draw_line(point+direction*4,point+direction*radius,Color(LIGHTNING_DARK,color.a),4,false)
				draw_line(point+direction*4,point+direction*radius,color,2,false)
