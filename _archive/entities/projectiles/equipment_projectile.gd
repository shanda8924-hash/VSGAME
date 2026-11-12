extends Projectile
## Equipment shots stay inside the player-centred attack circle and stop at scenery.
var actor: Player
var attack_radius := 232.0
var magic := false
var _age := 0.0

func _ready() -> void:
	super._ready()
	set_meta("equipment_attack", true)
	if magic:
		# 魔法弾の見た目は pixelfx projectiles/plasma-shot（equip_magic、ループ）。向きは弾ノードの回転に従う。
		var bolt := PixelSpriteVFX.make_persistent("equip_magic", Vector2.ZERO, true)
		if bolt:
			bolt.name = "MagicBolt"
			bolt.offset = -PixelSpriteVFX.frame_size_for("equip_magic") * Vector2(0.8, 0.5)
			$Visual.visible = false
			add_child(bolt)
			bolt.play_once(global_position)
			bolt.position = Vector2.ZERO

func _physics_process(delta: float) -> void:
	if not is_instance_valid(actor) or actor._is_dead:
		queue_free()
		return
	var previous := global_position
	super._physics_process(delta)
	var ray := PhysicsRayQueryParameters2D.create(previous, global_position, 1, [actor.get_rid()])
	if global_position.distance_to(actor.global_position) > attack_radius or not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
		damage_enabled = false
		queue_free()
	_age += delta

func _find_nearest_enemy() -> Node2D:
	return actor.weapon_manager.find_nearest_enemy(actor.global_position, attack_radius, true) if is_instance_valid(actor) else null

func can_hit(hurtbox: HurtboxComponent) -> bool:
	var target := hurtbox.get_owner_entity() as Node2D
	if not is_instance_valid(actor) or target == null or actor.global_position.distance_to(target.global_position) > attack_radius:
		return false
	var ray := PhysicsRayQueryParameters2D.create(actor.global_position, target.global_position, 1, [actor.get_rid()])
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty() and super.can_hit(hurtbox)
