extends RefCounted
## The inventory weapon has its own cadence; class attacks and active skills stay intact.
const PROFILES := {
	"light": {"name":"短剣・爪", "trait":"小さく素早い連撃", "power":0.72, "knockback":4.0, "range":96.0, "interval":0.62, "angle":42.0, "cut":25.0, "flight":0.06, "swing":0.12, "return":0.12},
	"slash": {"name":"片手剣", "trait":"扱いやすい斬撃", "power":1.0, "knockback":6.0, "range":112.0, "interval":0.95, "angle":58.0, "cut":36.0, "flight":0.09, "swing":0.15, "return":0.14},
	"heavy": {"name":"大剣", "trait":"幅広く敵を薙ぎ払う", "power":1.2, "knockback":10.0, "range":124.0, "interval":1.25, "angle":82.0, "cut":52.0, "flight":0.14, "swing":0.20, "return":0.20},
	"thrust": {"name":"細剣・槍", "trait":"細い直線を素早く貫く", "power":0.85, "knockback":5.0, "range":148.0, "interval":0.78, "angle":12.0, "cut":44.0, "width":7.0, "flight":0.08, "swing":0.12, "return":0.12},
	"axe": {"name":"斧", "trait":"間隔は長く、一撃が重い", "power":2.0, "knockback":18.0, "range":116.0, "interval":1.8, "angle":52.0, "cut":38.0, "flight":0.22, "swing":0.16, "return":0.24},
	"hammer": {"name":"鎚・棍", "trait":"溜めて叩き、強く押し返す", "power":2.25, "knockback":22.0, "range":108.0, "interval":2.1, "angle":100.0, "cut":32.0, "flight":0.26, "swing":0.16, "return":0.24},
	"scythe": {"name":"大鎌", "trait":"長い弧で広く刈り取る", "power":1.05, "knockback":7.0, "range":132.0, "interval":1.38, "angle":110.0, "cut":58.0, "flight":0.14, "swing":0.22, "return":0.19},
	"bow": {"name":"弓・弩", "trait":"遠くへ速い矢を放つ", "power":0.9, "knockback":0.0, "speed":390.0, "range":232.0, "interval":1.0, "angle":0.0, "cut":0.0, "flight":0.0, "swing":0.30, "return":0.0},
	"magic": {"name":"杖・魔導書", "trait":"魔法弾で遠距離を攻撃", "power":1.1, "knockback":0.0, "speed":280.0, "range":216.0, "interval":1.15, "angle":0.0, "cut":0.0, "flight":0.0, "swing":0.30, "return":0.0},
}
var item: EquipmentData
var kind := "slash"
var cooldown := 0.0
var windup := -1.0
var direction := Vector2.RIGHT
var _scan_delay := 0.0
var _damage_data: CharacterData
var _damage_pattern := AttackPatternBase.new()
var _target: WeakRef
var _strike_position := Vector2.ZERO

func get_range(manager: WeaponManagerComponent) -> float:
	return float(PROFILES[kind].range) * (manager.get_attack_range_multiplier() if kind in ["bow", "magic"] else manager.get_melee_range_multiplier())

func tick(delta: float, player: Player, manager: WeaponManagerComponent) -> void:
	var equipped := player.equipment_component.get_equipped("weapon")
	if equipped != item:
		item = equipped
		kind = item.attack_kind if item and PROFILES.has(item.attack_kind) else "slash"
		windup = -1.0
		cooldown = maxf(cooldown, 0.15)
		_damage_data = manager._character_data.duplicate() if manager._character_data else CharacterData.new()
		_damage_data.base_damage = 3.0
		_damage_data.attack_pattern_id = "single_shot" if kind in ["bow", "magic"] else "melee_arc"
		_damage_data.vfx_theme_id = "default"
	if item == null:
		return
	if not manager._can_attack(player):
		windup = -1.0
		player.floating_weapons.cancel_equipment_motion()
		return
	cooldown -= delta
	if windup >= 0.0:
		var target := _target.get_ref() as Node2D if _target else null
		if not is_instance_valid(target) or player.global_position.distance_to(target.global_position) > get_range(manager):
			windup = -1.0
			player.floating_weapons.cancel_equipment_motion()
			return
		var health := target.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.current_hp <= 0.0:
			windup = -1.0
			player.floating_weapons.cancel_equipment_motion()
			return
		var ray := PhysicsRayQueryParameters2D.create(player.global_position, target.global_position, 1, [player.get_rid()])
		if not player.get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
			windup = -1.0
			player.floating_weapons.cancel_equipment_motion()
			return
		_strike_position = target.global_position
		player.floating_weapons.track_equipment_target(_strike_position)
		windup -= delta
		if windup <= 0.0:
			windup = -1.0
			_hit(player, manager)
		return
	_scan_delay -= delta
	if cooldown > 0.0 or _scan_delay > 0.0:
		return
	_scan_delay = 0.08
	var target := manager.find_nearest_enemy(player.global_position, get_range(manager), true)
	if target == null:
		return
	direction = player.global_position.direction_to(target.global_position)
	_target = weakref(target)
	_strike_position = target.global_position
	var interval_multiplier := manager.get_attack_interval_multiplier() if kind in ["bow", "magic"] else manager.get_melee_attack_interval_multiplier()
	var profile: Dictionary = PROFILES[kind]
	cooldown = maxf(float(profile.interval) * interval_multiplier, float(profile.flight + profile.swing + profile["return"]))
	player.floating_weapons.start_equipment_motion(kind, direction, get_range(manager), target.global_position, item)
	manager.equipment_attack_fired.emit()
	if kind in ["bow", "magic"]:
		_shoot(player, manager, target.global_position)
	else:
		AudioManager.play_sfx("melee_swing")
		windup = float(profile.flight) + float(profile.swing) / 3.0

func _hit(player: Player, manager: WeaponManagerComponent) -> void:
	var profile: Dictionary = PROFILES[kind]
	var radius := float(profile.cut) * manager.get_melee_range_multiplier()
	var contact_origin := _strike_position - direction * (radius * 0.45)
	var hit: MeleeHit
	if kind == "thrust":
		hit = _damage_pattern.spawn_line_hit(player, radius, float(profile.width), direction, 0.06, float(profile.knockback), _damage_data, manager, float(profile.power))
	else:
		hit = _damage_pattern.spawn_arc_hit(player, radius, direction, float(profile.angle) + manager.sector_arc_width_level * 10.0, 0.06, float(profile.knockback), _damage_data, manager, float(profile.power))
	hit.applied_status_id = manager.get_applied_status_id()
	# The hit follows the flying blade to the enemy, not a giant wedge at the player.
	hit.global_position = contact_origin
	hit.setup("default", manager.get_owner_character_level(), contact_origin)
	hit.set_meta("equipment_attack", true)
	# Keep the drawn circle and hit boundary identical, including enemy hurtbox edges.
	hit.target_range_limit = get_range(manager)
	hit.target_range_origin = player.global_position

func _shoot(player: Player, manager: WeaponManagerComponent, target: Vector2) -> void:
	_shoot_single(player, manager, target)
	for index in manager.get_survival_extra_projectiles():
		var offset := (target - player.global_position).rotated(deg_to_rad(16.0 if index % 2 == 0 else -16.0))
		_shoot_single(player, manager, player.global_position + offset)

func _shoot_single(player: Player, manager: WeaponManagerComponent, target: Vector2) -> void:
	var origin := player.floating_weapons.get_muzzle("equipment")
	var ray := PhysicsRayQueryParameters2D.create(player.global_position, origin, 1, [player.get_rid()])
	if not player.get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
		return # A floating sprite behind a wall must not fire through it.
	var data := WeaponData.new()
	data.id = "equipped_weapon"
	data.base_damage = _damage_data.base_damage
	data.crit_chance = _damage_data.crit_chance
	data.crit_multiplier = _damage_data.crit_multiplier
	data.vfx_theme_id = "default"
	# WeaponData loads the base projectile during startup; load its subclass on use
	# so Projectile -> Player -> manager cannot preload that same scene recursively.
	var scene := load("res://entities/projectiles/equipment_projectile.tscn") as PackedScene
	var bolt := scene.instantiate()
	bolt.actor = player
	bolt.attack_radius = get_range(manager)
	bolt.magic = kind == "magic"
	bolt.speed = float(PROFILES[kind].speed)
	bolt.applied_status_id = manager.get_applied_status_id()
	bolt.pierce_remaining = 1 + manager.sector_pierce_level
	GameManager.get_runtime_world(player).add_child(bolt)
	bolt.global_position = origin
	bolt.launch(target, data, manager.get_owner_character_level(), manager.get_owner_stat_modifier(), manager.get_owner_upgrades())
	bolt.damage *= float(PROFILES[kind].power)
	AudioManager.play_sfx("wizard_cast" if kind == "magic" else "attack_shoot")
