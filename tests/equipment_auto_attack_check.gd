extends Node
## Run: Godot --path . --scene res://tests/equipment_auto_attack_check.tscn
var game: Node2D
var player: Player
var drops: EquipmentDropSystem
var fired := 0
var failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	GameManager.selected_character_id = "swordsman"
	get_tree().create_timer(150.0, true).timeout.connect(func():
		push_error("Equipment attack test timed out")
		get_tree().quit(1))
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame

func _enemy(offset: Vector2) -> EnemyBasic:
	var enemy := preload("res://entities/enemies/enemy_basic.tscn").instantiate() as EnemyBasic
	enemy.enemy_data = DataLoader.enemies.slime
	game.add_child(enemy)
	enemy.global_position = player.global_position + offset
	enemy.set_room_activation_locked(true)
	enemy.health_component.max_hp = 10000.0
	enemy.health_component.current_hp = 10000.0
	return enemy

func _equip(id: String) -> EquipmentData:
	var item := drops.debug_generate_equipment(id, "uncommon")
	_check(player.equipment_component.add_item(item) and player.equipment_component.equip(item), "Real inventory equip failed: " + id)
	return item

func _clear_hits() -> void:
	for child in game.get_children():
		if child is Projectile or child is MeleeHit:
			child.queue_free()
	await _frames(3)

func _run() -> void:
	game = preload("res://scenes/game.tscn").instantiate()
	game.tree_entered.connect(func(): get_tree().current_scene = game)
	get_tree().root.add_child(game)
	var controller := game.get_node("MapRunController") as MapRunController
	while not controller._active:
		await _frames(1)
	controller.set_process(false)
	var wave := game.get_node("WaveSpawner") as WaveSpawner
	wave._sector_active = false
	wave.set_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	player = game.get_node("Player") as Player
	drops = game.get_node("EquipmentDropSystem") as EquipmentDropSystem
	player.health_component.invincible = true
	player.global_position = Vector2(-2000, -2000)
	var manager := player.weapon_manager
	# Prove equipment itself does real damage; no class attack can mask a missing link.
	manager.cancel_current_attack()
	manager._class_attack = null
	manager.equipment_attack_fired.connect(func(): fired += 1)
	if "--capture-only" in OS.get_cmdline_user_args():
		await _capture(controller)
		var capture_cleanup := preload("res://tests/runtime_exit_cleanup.gd").new()
		get_tree().root.add_child(capture_cleanup)
		capture_cleanup.begin(0 if failures.is_empty() else 1, "WEAPON_TRAITS_CAPTURE failures=%d" % failures.size())
		return
	_check(not Input.is_action_pressed("primary_attack"), "J must remain released")
	for template in drops.debug_get_templates():
		if template.slot == "weapon":
			var catalog_item := drops.debug_generate_equipment(template.id, template.rarity)
			_check(manager.equipment_attack.PROFILES.has(catalog_item.attack_kind), "Missing weapon attack profile: " + template.id)
	for id in ["moonblue_dagger", "wanderer_iron_sword", "rune_greatsword", "fallen_dynasty_02", "sunfire_battle_axe", "royal_guard_04", "abyss_watch_03", "traveler_shortbow", "star_sorcerer_staff"]:
		var item := _equip(id)
		await _frames(2)
		var radius: float = manager.equipment_attack.get_range(manager)
		var outside := _enemy(Vector2(radius + 24, 0))
		var before := fired
		await _frames(85)
		_check(fired == before and outside.health_component.current_hp == 10000, "Attacked beyond player-centred circle: " + id)
		outside.queue_free()
		await _frames(3)
		var target := _enemy(Vector2(radius - 22, 0))
		var blade_distance := INF
		var emitted_projectile := false
		for frame in 145:
			await _frames(1)
			blade_distance = minf(blade_distance, player.floating_weapons.get_muzzle("equipment").distance_to(target.global_position))
			for bolt in get_tree().get_nodes_in_group("projectiles"):
				if bolt.get_meta("equipment_attack", false): emitted_projectile = true
		_check(fired > before and target.health_component.current_hp < 10000, "Floating weapon dealt no automatic damage: " + id)
		if item.attack_kind not in ["bow", "magic"]:
			_check(blade_distance < 28.0 and not emitted_projectile, "Blade did not physically fly to cut the target: " + id)
		else:
			_check(emitted_projectile, "Ranged weapon did not fire from its muzzle: " + id)
		_check(player.global_position == Vector2(-2000,-2000), "Equipment attack moved the player")
		_check(player.floating_weapons._equipment_kind == item.attack_kind, "Animation did not match equipped type")
		target.queue_free()
		player.equipment_component.unequip("weapon")
		await _clear_hits()
		before = fired
		target = _enemy(Vector2(60,0))
		await _frames(30)
		_check(fired == before and target.health_component.current_hp == 10000, "Weapon kept firing after unequip")
		target.queue_free()
		print("EQUIPMENT profile PASS: ", id)
	await _check_weapon_traits()
	# A target leaving the circle during blade travel must not be hit remotely.
	_equip("wanderer_iron_sword")
	await _frames(2)
	var escapee := _enemy(Vector2(85,0))
	var initial_fired := fired
	while fired == initial_fired: await _frames(1)
	escapee.global_position = player.global_position + Vector2(260,0)
	await _frames(30)
	_check(escapee.health_component.current_hp == 10000, "Flying sword hit an enemy that left the circle")
	escapee.queue_free()
	await _clear_hits()
	# Removing a weapon during travel cancels that pending impact immediately.
	var cancelled := _enemy(Vector2(85,0))
	initial_fired = fired
	while fired == initial_fired: await _frames(1)
	player.equipment_component.unequip("weapon")
	await _frames(30)
	_check(cancelled.health_component.current_hp == 10000, "Unequipping did not cancel the travelling blade")
	cancelled.queue_free()
	await _clear_hits()
	# Wall occlusion in acquisition, plus moving projectile/scenery collision.
	_equip("traveler_shortbow")
	await _frames(2)
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(12,160)
	shape.shape = rectangle
	wall.add_child(shape)
	game.add_child(wall)
	wall.global_position = player.global_position + Vector2(65,0)
	var hidden := _enemy(Vector2(150,0))
	await _frames(3)
	var before := fired
	await _frames(80)
	_check(fired == before and hidden.health_component.current_hp == 10000, "Auto-target acquired enemy behind wall")
	wall.queue_free()
	await _frames(3)
	GameManager.open_modal()
	before = fired
	await get_tree().create_timer(0.4, true).timeout
	_check(fired == before, "Equipment fired under inventory pause")
	GameManager.close_modal()
	player.dodge_remaining = 0.4
	await _frames(6)
	_check(fired == before, "Equipment attack ignored dodge cancellation")
	await _frames(100)
	_check(hidden.health_component.current_hp < 10000, "Attack did not resume after dodge/pause")
	hidden.queue_free()
	await _clear_hits()
	# Targets above/below and behind the character are equally eligible.
	for offset in [Vector2(-150,0),Vector2(0,150),Vector2(0,-150)]:
		var target := _enemy(offset)
		await _frames(100)
		_check(target.health_component.current_hp < 10000, "360-degree acquisition failed: " + str(offset))
		target.queue_free()
		await _clear_hits()
	# Every rarity reaches the real animation, not only the inventory border.
	for rarity in ["uncommon","rare","epic","legendary","mythic"]:
		var item := drops.debug_generate_equipment("wanderer_iron_sword", rarity)
		player.equipment_component.add_item(item)
		player.equipment_component.equip(item)
		var target := _enemy(Vector2(85,0))
		initial_fired = fired
		while fired == initial_fired: await _frames(1)
		_check(player.floating_weapons._rarity_color == item.get_rarity_color(), "Rarity did not reach slash VFX: " + rarity)
		target.queue_free()
		await _clear_hits()
	player.equipment_component.unequip("weapon")
	manager._setup_class_attack_pattern()
	var fallback := _enemy(Vector2(48,0))
	await _frames(120)
	_check(fallback.health_component.current_hp < 10000, "Class automatic attack lost after unequip")
	fallback.queue_free()
	manager.cancel_current_attack()
	manager._class_attack = null
	await _clear_hits()
	if "--capture" in OS.get_cmdline_user_args():
		await _capture(controller)
	var cleanup := preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	manager.cancel_current_attack()
	await _frames(3)
	cleanup.begin(0 if failures.is_empty() else 1, "EQUIPMENT_AUTO_ATTACK failures=%d: nine profiles, measured strength/cadence, wide slash/narrow thrust, radius, walls, pause/dodge, 360 aim, unequip/class fallback" % failures.size())

func _check_weapon_traits() -> void:
	var observations := {}
	var manager := player.weapon_manager
	var original_crit := manager._character_data.crit_chance
	manager._character_data.crit_chance = -1.0 # Remove random crits from equal-stat comparisons.
	for id in ["fallen_dynasty_02", "rune_greatsword", "sunfire_battle_axe", "royal_guard_04", "abyss_watch_03", "traveler_shortbow"]:
		var item := drops.debug_generate_equipment(id, "uncommon")
		item.stats = {"attack_power":10.0}
		item.special_effects.clear()
		player.equipment_component.add_item(item)
		player.equipment_component.equip(item)
		await _frames(2)
		manager.equipment_attack.cooldown = 0.0
		var target := _enemy(Vector2(80,0))
		var initial := fired
		var first_fire := -1
		var second_fire := -1
		var damage := 0.0
		for frame in 160:
			await _frames(1)
			if first_fire < 0 and fired > initial: first_fire = frame
			if second_fire < 0 and fired > initial + 1: second_fire = frame
			if damage == 0.0 and target.health_component.current_hp < 10000:
				damage = 10000.0 - target.health_component.current_hp
				target.health_component.invincible = true
		_check(damage > 0.0 and second_fire > first_fire, "No measurable strike/cadence: " + id)
		observations[item.attack_kind] = {"first_hit_damage":damage, "interval_frames":second_fire-first_fire}
		if item.attack_kind not in ["bow", "magic"]:
			_check(player.floating_weapons._effect.texture.resource_path.ends_with(item.attack_kind + "_6f.png"), "Wrong type effect: " + id)
		target.queue_free()
		player.equipment_component.unequip("weapon")
		await _clear_hits()
	_check(observations.axe.first_hit_damage > observations.heavy.first_hit_damage * 1.3, "Axe lacks a stronger single impact")
	_check(observations.heavy.first_hit_damage > observations.thrust.first_hit_damage, "Greatsword lacks weight compared with rapier")
	_check(observations.axe.interval_frames > observations.heavy.interval_frames and observations.heavy.interval_frames > observations.thrust.interval_frames, "Axe/greatsword/rapier cadence is not distinct")
	_check(observations.hammer.interval_frames > observations.axe.interval_frames, "Hammer lacks a slower windup cycle")
	# A side enemy must be cleaved by a greatsword but excluded by a rapier thrust.
	for id in ["rune_greatsword", "fallen_dynasty_02"]:
		_equip(id)
		await _frames(2)
		manager.equipment_attack.cooldown = 0.0
		var target := _enemy(Vector2(80,0))
		var side_target := _enemy(Vector2(80,28))
		var initial := fired
		while fired == initial: await _frames(1)
		await _frames(30)
		_check(target.health_component.current_hp < 10000, "Centre strike missed in shape comparison")
		_check((side_target.health_component.current_hp < 10000) == (id == "rune_greatsword"), "Wide slash and narrow thrust do not differ in actual hits")
		target.queue_free()
		side_target.queue_free()
		player.equipment_component.unequip("weapon")
		await _clear_hits()
	manager._character_data.crit_chance = original_crit
	DirAccess.make_dir_recursive_absolute("res://artifacts/equipment_attacks")
	var evidence := FileAccess.open("res://artifacts/equipment_attacks/weapon_traits_check.json", FileAccess.WRITE)
	evidence.store_string(JSON.stringify(observations, "\t"))
	print("WEAPON_TRAITS actual equal-stat impacts/cadence: ", JSON.stringify(observations))

func _capture(controller: MapRunController) -> void:
	var room := GameManager.dungeon_map.rooms[controller._sector_room_index] as Rect2i
	player.global_position = GameManager.dungeon_map.grid_to_world(room.get_center())
	player.camera.reset_smoothing()
	player.weapon_manager._class_attack = null
	DirAccess.make_dir_recursive_absolute("res://artifacts/equipment_attacks")
	var captures := {}
	var examples := [["moonblue_dagger","rare"],["wanderer_iron_sword","uncommon"],["rune_greatsword","mythic"],["fallen_dynasty_02","rare"],["sunfire_battle_axe","legendary"],["royal_guard_04","epic"],["abyss_watch_03","epic"],["traveler_shortbow","legendary"],["star_sorcerer_staff","epic"]]
	for example in examples:
		var id := String(example[0])
		var item := drops.debug_generate_equipment(id, example[1])
		item.stats = {"attack_power":10.0}
		item.special_effects.clear()
		player.equipment_component.add_item(item)
		player.equipment_component.equip(item)
		await _frames(2)
		var radius: float = player.weapon_manager.equipment_attack.get_range(player.weapon_manager)
		var target := _enemy(Vector2(radius-24,0))
		var before := fired
		for frame in 110:
			await _frames(1)
			if fired > before: break
		var profile: Dictionary = player.weapon_manager.equipment_attack.PROFILES[item.attack_kind]
		var frame_count := ceili(float(profile.interval) * 30.0)
		captures[id] = {"frames":frame_count, "kind":item.attack_kind, "frame_duration_ms":33}
		for frame in frame_count:
			await _frames(2)
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			image.save_png("res://artifacts/equipment_attacks/%s_%02d.png" % [id,frame])
			if frame == 4:
				image.save_png("res://artifacts/equipment_attacks/%s.png" % id)
		target.queue_free()
		await _clear_hits()
	var capture_manifest := FileAccess.open("res://artifacts/equipment_attacks/capture_manifest.json", FileAccess.WRITE)
	capture_manifest.store_string(JSON.stringify(captures, "\t"))
	var bag := game.get_node("EquipmentScreen") as EquipmentScreen
	var axe := player.equipment_component.inventory.filter(func(entry: EquipmentData): return entry.attack_kind == "axe")[0] as EquipmentData
	bag._open()
	bag._on_inventory_item_pressed(axe)
	for frame in 4: await get_tree().process_frame
	_check(bag.comparison.text.contains("基準間隔") and bag.comparison.text.contains("一撃 ×2.00"), "Weapon traits missing from real inventory details")
	var popup := bag.forge_panel.get_global_rect()
	var screen := bag.get_viewport().get_visible_rect()
	_check(screen.encloses(popup), "Weapon detail popup lies outside the screen")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/equipment_attacks/weapon_traits_inventory.png")
	bag._close()
