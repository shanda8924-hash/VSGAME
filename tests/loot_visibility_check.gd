extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")
const GROUND_SCENE := preload("res://entities/pickups/ground_equipment_item.tscn")
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")
const PROJECTILE_SCENE := preload("res://entities/projectiles/projectile.tscn")
const OUTPUT_DIR := "res://artifacts/equipment_element_polish"

var failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run_checks()
	for failure in failures:
		push_error(failure)
	print("LOOT_VISIBILITY_CHECK failures=%d" % failures.size())
	AudioManager.stop_all()
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func _run_checks() -> void:
	GameManager.selected_character_id = "swordsman"
	var game := GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		var background := game.get_node_or_null(node_name)
		if background:
			background.process_mode = Node.PROCESS_MODE_DISABLED
	var player := game.get_node("Player") as Player
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	var before_drop_count := get_tree().get_nodes_in_group("ground_equipment").size()
	var origin := GameManager.dungeon_map.grid_to_world(GameManager.dungeon_map.spawn_point)
	var drop_system := game.get_node("EquipmentDropSystem") as EquipmentDropSystem
	drop_system.debug_force_enemy_drop(origin, true, false)
	await get_tree().process_frame
	await get_tree().process_frame
	var dropped_items := get_tree().get_nodes_in_group("ground_equipment")
	_check(dropped_items.size() == before_drop_count + 1, "elite equipment drop creates one ground item")
	var dropped := dropped_items.back() as GroundEquipmentItem
	_check(dropped.get_node_or_null("Visual/PixelLootPlate") is Polygon2D, "drop creates a compact pixel loot plate")
	var dropped_outline := dropped.get_node_or_null("Visual/PixelLootOutline") as Line2D
	_check(dropped_outline != null and not dropped_outline.antialiased, "drop creates a hard pixel outline")
	_check(dropped.get_node_or_null("Visual/LootBeam") == null and dropped.get_node_or_null("Visual/LootBeamGlow") == null, "drop creates no long loot beam")
	_check(dropped.get_node_or_null("Visual/LootAmbientParticles") is CPUParticles2D, "drop creates persistent ambient particles")
	_check(dropped.get_node_or_null("Visual/LootSpawnBurst") is CPUParticles2D, "drop creates one-shot arrival burst")

	var rarities := ["uncommon", "rare", "epic", "legendary", "mythic"]
	var ambient_amounts: Array[int] = []
	var ambient_alphas: Array[float] = []
	var matrix: Array[GroundEquipmentItem] = []
	for index in rarities.size():
		var item := EquipmentData.new()
		item.instance_id = "loot_visibility_%d" % index
		item.template_id = "wanderer_iron_sword"
		item.display_name = "Loot Visibility"
		item.slot = "weapon"
		item.rarity = rarities[index]
		item.icon_path = "res://assets/items/weapons/weapon_sword_uncommon_001.png"
		var ground := GROUND_SCENE.instantiate() as GroundEquipmentItem
		ground.setup(item)
		add_child(ground)
		ground.global_position = origin + Vector2((index - 2) * 54, 90)
		matrix.append(ground)
		var ambient := ground.get_node("Visual/LootAmbientParticles") as CPUParticles2D
		ambient_amounts.append(ambient.amount)
		ambient_alphas.append(ambient.color.a)
		_check(ground.get_node_or_null("Visual/PixelLootPlate") is Polygon2D, "%s keeps its compact pixel plate" % rarities[index])
		_check(ambient != null, "%s has persistent particles" % rarities[index])
	for index in range(1, rarities.size()):
		_check(ambient_amounts[index] > ambient_amounts[index - 1], "pixel fragment count increases with rarity: %s" % rarities[index])
		_check(ambient_alphas[index] > ambient_alphas[index - 1], "pixel fragment contrast increases with rarity: %s" % rarities[index])
	if DisplayServer.get_name() != "headless":
		await _capture_mass_combat_loot(game, player, origin)

	await get_tree().create_timer(0.62, false).timeout
	for ground in matrix:
		_check(ground.get_node_or_null("Visual/PixelLootPlate") != null and ground.get_node_or_null("Visual/PixelLootOutline") != null, "%s compact plate remains after arrival" % ground.equipment.rarity)
		_check(ground.get_node_or_null("Visual/LootBeam") == null and ground.get_node_or_null("Visual/LootSpawnBeam") == null, "%s never creates a vertical beam" % ground.equipment.rarity)

	var dropped_ref: WeakRef = weakref(dropped)
	var inventory_before := player.equipment_component.get_all_inventory().size()
	_check(dropped.collect(player), "equipment pickup succeeds")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(dropped_ref.get_ref() == null, "pickup removes the ground item and all compact VFX children")
	_check(player.equipment_component.get_all_inventory().size() == inventory_before + 1, "pickup adds equipment to inventory")
	_check(get_tree().get_nodes_in_group("ground_equipment").size() == before_drop_count + matrix.size(), "pickup leaves no ghost VFX/ground item")

	for ground in matrix:
		ground.queue_free()
	game.queue_free()
	await get_tree().process_frame

func _capture_mass_combat_loot(game: Node, player: Player, origin: Vector2) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	player.global_position = origin
	var capture_nodes: Array[Node] = []
	var manager := game.get_node("AttackVFXManager") as AttackVFXManager
	var element_ids := ["element_fire", "element_ice", "element_lightning", "element_light", "element_dark"]
	for index in 14:
		var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
		var data := EnemyData.new()
		data.id = "loot_capture_%d" % index
		data.display_name = "Combat Target"
		data.max_hp = 999.0
		data.move_speed = 0.0
		data.contact_damage = 0.0
		enemy.enemy_data = data
		game.add_child(enemy)
		var angle := TAU * float(index) / 14.0
		enemy.global_position = origin + Vector2.from_angle(angle) * (150.0 + float(index % 3) * 38.0)
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		capture_nodes.append(enemy)
		var element_data := DataLoader.element_vfx_effects.get(element_ids[index % element_ids.size()]) as ElementVFXData
		manager.play_element_hit(enemy.global_position, element_data, 2 + index % 2)
		EventBus.damage_dealt.emit(18.0 + index * 2.0, enemy.global_position + Vector2(0, -12), index % 4 == 0)
	var weapon := WeaponData.new()
	weapon.id = "loot_capture_projectile"
	weapon.base_damage = 1.0
	weapon.vfx_theme_id = "ice"
	for index in 9:
		var projectile := PROJECTILE_SCENE.instantiate() as Projectile
		game.add_child(projectile)
		projectile.global_position = origin + Vector2(-180 + index * 44, -70 + (index % 3) * 34)
		projectile.speed = 0.0
		projectile.launch(projectile.global_position + Vector2(300, 0), weapon)
		capture_nodes.append(projectile)
	await get_tree().process_frame
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	if image:
		image.save_png("%s/mass_combat_loot_visibility.png" % OUTPUT_DIR)
	for node in capture_nodes:
		if is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
