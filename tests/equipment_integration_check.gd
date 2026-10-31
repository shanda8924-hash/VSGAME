extends Node

var failures: Array[String] = []

func _ready() -> void:
	SaveManager.begin_ephemeral_session() # Keep fixture rewards out of the player's save.
	await get_tree().process_frame
	await _run_checks()
	await _run_drop_runtime_check()
	await _run_affix_runtime_check()
	for failure in failures:
		push_error(failure)
	print("EQUIPMENT_INTEGRATION_CHECK failures=%d" % failures.size())
	AudioManager.stop_all()
	await get_tree().create_timer(0.2, true, false, true).timeout
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _run_checks() -> void:
	_check(DataLoader.bosses.size() == 10, "boss data count")
	_check(InputMap.has_action("interact") and not InputMap.action_get_events("interact").is_empty(), "equipment pickup input remains registered")
	_check(InputMap.has_action("equipment_menu") and not InputMap.action_get_events("equipment_menu").is_empty(), "equipment menu input remains registered")
	_check(InputMap.has_action("character_screen") and not InputMap.action_get_events("character_screen").is_empty(), "character screen input registered")
	var has_c_key := false
	for event in InputMap.action_get_events("character_screen"):
		if event is InputEventKey and event.physical_keycode == KEY_C:
			has_c_key = true
	_check(has_c_key, "character screen uses C through InputMap")
	var minotaur: BossData = DataLoader.bosses.get("minotaur")
	_check(is_equal_approx(minotaur.max_hp, 510.0), "boss hp multiplier")
	_check(is_equal_approx(minotaur.contact_damage, 50.625), "boss damage multiplier")
	_check(is_equal_approx(minotaur.move_speed, 71.5), "boss speed multiplier")
	var equipment_scene := load("res://entities/pickups/ground_equipment_item.tscn") as PackedScene
	_check(equipment_scene != null, "ground equipment scene loads")
	if equipment_scene:
		await _check_all_character_ground_icon_sizes(equipment_scene)
	var ui_scene := load("res://ui/equipment/equipment_screen.tscn") as PackedScene
	_check(ui_scene != null, "equipment UI scene loads")
	var equipment := EquipmentData.new()
	equipment.instance_id = "test"
	equipment.display_name = "Test Blade"
	equipment.slot = "weapon"
	equipment.rarity = "legendary"
	equipment.icon_path = "res://assets/items/weapons/weapon_axe_legendary_001.png"
	equipment.stats = {"attack_power":15.0, "defense":5.0, "max_hp":10.0, "crit_rate":0.05}
	equipment.special_effects = ["kill_heal"]
	equipment.special_effect_values = {"kill_heal":{"heal_flat":8.0}}
	var player := load("res://entities/player/player.tscn").instantiate() as Player
	add_child(player)
	var component := player.get_node("EquipmentComponent") as EquipmentComponent
	component.add_item(equipment)
	_check(component.get_all_inventory().size() == 1, "pickup adds inventory")
	_check(component.equip(equipment), "equipment can equip")
	_check(component.get_equipped("weapon") == equipment, "slot contains equipment")
	_check(is_equal_approx(player.upgrades_component.equipment_attack_flat, 15.0), "flat attack stat applied")
	_check(is_equal_approx(player.health_component.equipment_defense_flat, 5.0), "flat defense stat applied")
	_check(is_equal_approx(player.health_component.max_hp, 110.0), "max hp stat applied")
	player.health_component.current_hp = 100.0
	player.health_component.apply_damage(20.0)
	_check(is_equal_approx(player.health_component.current_hp, 85.0), "flat defense is subtracted before percentage")
	player.health_component._iframe_remaining = 0.0
	player.health_component.current_hp = 100.0
	player.health_component.damage_taken_multiplier = 0.8
	player.health_component.apply_damage(20.0)
	_check(is_equal_approx(player.health_component.current_hp, 88.0), "percentage reduction runs after flat defense")
	player.health_component.damage_taken_multiplier = 1.0
	var equipment_ui := ui_scene.instantiate() as EquipmentScreen
	add_child(equipment_ui)
	# The real open path now builds the inventory lazily, including rarity headings.
	equipment_ui._open()
	_check(_count_equipment_slots(equipment_ui) == 6, "character UI shows six slots around portrait")
	var inventory_buttons: Array[Button] = []
	for child in equipment_ui.inventory_list.get_children():
		if child is Button:
			inventory_buttons.append(child)
	_check(inventory_buttons.size() == 1, "equipment UI shows inventory")
	_check(not inventory_buttons.is_empty() and inventory_buttons[0].icon != null, "inventory UI shows item icon")
	_check((equipment_ui.left_slots.get_child(0) as Button).icon != null, "equipped slot UI shows item icon")
	_check(equipment_ui.character_portrait.texture != null, "character UI reuses current character sprite")
	_check(get_tree().paused and equipment_ui.visible and equipment_ui.process_mode == Node.PROCESS_MODE_ALWAYS, "character UI pauses world and remains interactive")
	Input.action_press("ui_cancel")
	equipment_ui._process(0.0)
	Input.action_release("ui_cancel")
	_check(not get_tree().paused and not equipment_ui.visible, "ESC action closes character UI and resumes world")
	equipment_ui._open()
	Input.action_press("character_screen")
	equipment_ui._process(0.0)
	Input.action_release("character_screen")
	_check(not get_tree().paused and not equipment_ui.visible, "character_screen action closes character UI")
	_check(component.unequip("weapon"), "equipment can unequip")
	_check(is_equal_approx(player.upgrades_component.equipment_attack_flat, 0.0), "unequip restores flat attack")
	_check(is_equal_approx(player.health_component.max_hp, 100.0), "unequip restores max hp")
	_check(component.equip(equipment), "equipment can re-equip without duplicate addition")
	equipment_ui.queue_free()
	var ground := equipment_scene.instantiate() as GroundEquipmentItem
	ground.setup(EquipmentData.new())
	add_child(ground)
	ground.equipment.instance_id = "ground_test"
	ground.equipment.display_name = "Ground Test"
	ground.equipment.slot = "head"
	ground.equipment.icon_path = "res://assets/items/head/head_helm_rare_001.png"
	_check(ground.collect(player), "ground equipment can be collected")
	_check(component.get_all_inventory().size() == 2, "ground pickup reaches inventory")
	_check(component.get_all_inventory().back().icon_path == ground.equipment.icon_path, "pickup keeps the same icon path in inventory")
	var guard := EquipmentData.new()
	guard.instance_id = "guard_special"
	guard.display_name = "Guard Special"
	guard.slot = "accessory"
	guard.rarity = "legendary"
	guard.stats = {"move_speed":0.10, "attack_speed":0.10}
	guard.special_effects = ["negate_hit"]
	guard.special_effect_values = {"negate_hit":{"chance":0.10}}
	component.add_item(guard)
	component.equip(guard)
	_check(is_equal_approx(player.health_component.equipment_negate_chance, 0.10), "negate special uses data-driven chance")
	_check(is_equal_approx(player.movement_component.equipment_speed_multiplier, 1.10), "percentage move speed affix applied")
	_check(is_equal_approx(player.upgrades_component.equipment_attack_speed_bonus, 0.10), "percentage attack speed affix applied")
	var low_hp := EquipmentData.new()
	low_hp.instance_id = "low_hp_special"
	low_hp.display_name = "Low HP Special"
	low_hp.slot = "body"
	low_hp.rarity = "mythic"
	low_hp.stats = {"crit_damage":0.25}
	low_hp.special_effects = ["low_hp_power"]
	low_hp.special_effect_values = {"low_hp_power":{"hp_threshold":0.35, "damage_bonus":0.35}}
	component.add_item(low_hp)
	component.equip(low_hp)
	_check(is_equal_approx(player.upgrades_component.equipment_crit_damage_bonus, 0.25), "percentage critical damage affix applied")
	player.health_component.current_hp = player.health_component.max_hp * 0.30
	_check(is_equal_approx(player.upgrades_component.get_equipment_conditional_damage_multiplier(), 1.35), "low HP power special activates")
	player.health_component.current_hp = player.health_component.max_hp
	_check(is_equal_approx(player.upgrades_component.get_equipment_conditional_damage_multiplier(), 1.0), "low HP power special deactivates")
	player.health_component.current_hp = 40.0
	component._on_enemy_died(null, Vector2.ZERO)
	_check(is_equal_approx(player.health_component.current_hp, 48.0), "kill heal special restores fixed HP")
	var mythic_data := EquipmentData.new()
	mythic_data.instance_id = "mythic_visual"
	mythic_data.display_name = "Mythic Test"
	mythic_data.slot = "accessory"
	mythic_data.rarity = "mythic"
	mythic_data.icon_path = "res://assets/items/accessories/accessory_relic_mythic_001.png"
	var mythic_ground := equipment_scene.instantiate() as GroundEquipmentItem
	mythic_ground.setup(mythic_data)
	add_child(mythic_ground)
	var has_particles := false
	for child in mythic_ground.get_node("Visual").get_children():
		if child is CPUParticles2D:
			has_particles = true
	_check(not has_particles, "mythic ground item needs no persistent CPU emitters")
	_check(mythic_ground.get_node_or_null("Visual/RarityRing") == null, "large rarity ring removed")
	_check(mythic_ground.get_node_or_null("Visual/RarityGlow") == null, "large rarity ring glow removed")
	_check(mythic_ground.get_node_or_null("Visual/PixelLootPlate") == null and mythic_ground.get_node_or_null("Visual/PixelLootOutline") == null, "procedural plate and line are replaced by authored pixel art")
	var loot_seal := mythic_ground.get_node_or_null("Visual/RoyalLootSeal") as Sprite2D
	_check(loot_seal != null and loot_seal.texture != null and loot_seal.texture.resource_path == GroundEquipmentItem.LOOT_SEAL_TEXTURE_PATH, "drop uses the generated royal seal PNG")
	_check(loot_seal != null and loot_seal.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and loot_seal.modulate == mythic_data.get_rarity_color(), "seal keeps nearest pixels and mythic rarity color")
	_check(loot_seal != null and not loot_seal.is_processing() and loot_seal.scale.x * 64.0 <= 62.0, "persistent loot effect is one static compact sprite")
	var awakening := mythic_ground.get_node_or_null("Visual/LootAwakening") as PixelSpriteVFX
	_check(awakening != null and awakening.get_meta("pixel_vfx_id", "") == "loot_awaken", "drop plays the generated awakening PNG")
	_check(awakening != null and awakening.sprite_frames.get_frame_count("play") == 6 and is_equal_approx(awakening._duration, 0.7), "awakening has six frames and a bounded 0.7 second lifetime")
	_check(mythic_ground.get_node_or_null("Visual/LootAmbientParticles") == null and mythic_ground.get_node_or_null("Visual/LootSpawnBurst") == null, "duplicated particle VFX are removed")
	_check(mythic_ground.get_node_or_null("Visual/LootParticles") == null, "duplicate high-rarity emitter removed")
	_check(mythic_ground.get_node_or_null("Visual/LootBeam") == null and mythic_ground.get_node_or_null("Visual/LootBeamGlow") == null, "long equipment loot beams stay removed")
	var player_visual_height := mythic_ground._get_player_visual_height()
	var item_visual_height := mythic_ground._icon_visual_size.y
	_check(item_visual_height >= player_visual_height * 0.7 and item_visual_height <= player_visual_height, "ground icon is 70-100 percent of player visual height")
	_check(not _has_panel_container(mythic_ground.get_node("Visual")), "ground item has no card panel")
	var before_position: Vector2 = mythic_ground.get_node("Visual").position
	await get_tree().create_timer(0.08).timeout
	_check(mythic_ground.get_node("Visual").position == before_position, "ground item does not bob")
	await get_tree().create_timer(0.72).timeout
	_check(mythic_ground.get_node_or_null("Visual/LootAwakening") == null, "awakening removes itself after its short lifetime")
	mythic_ground.queue_free()
	var affix_data := _read_json("res://data/elite_affixes/default.json")
	_check(affix_data.get("affixes", {}).size() == 6, "six elite affixes configured")
	var elite_manager_text := FileAccess.get_file_as_string("res://systems/elite_room_manager.gd")
	_check("StaticBody2D.new" not in elite_manager_text and "_seal_room" not in elite_manager_text, "invisible barrier removed")
	component._on_run_ended(0.0, 0)
	_check(component.get_all_inventory().is_empty() and component.get_equipped("weapon") == null, "run end resets equipment")
	_check(is_equal_approx(player.health_component.max_hp, 100.0), "run end removes equipment stats")
	_check(is_equal_approx(player.upgrades_component.equipment_attack_flat, 0.0), "run end removes flat attack")

func _read_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _check_all_character_ground_icon_sizes(equipment_scene: PackedScene) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment/templates.json"))
	var templates: Array = parsed if typeof(parsed) == TYPE_ARRAY else []
	_check(templates.size() == 25, "ground icon size matrix uses all 25 equipment icons")
	var original_character_id := GameManager.selected_character_id
	var character_ids: Array = DataLoader.characters.keys()
	character_ids.sort()
	_check(character_ids.size() == 10, "ground icon size matrix uses all 10 characters")
	for character_id in character_ids:
		GameManager.selected_character_id = String(character_id)
		var sample_player := load("res://entities/player/player.tscn").instantiate() as Player
		add_child(sample_player)
		await get_tree().process_frame
		for template in templates:
			var item := EquipmentData.new()
			item.instance_id = "visual_matrix"
			item.display_name = "Visual Matrix"
			item.slot = String(template.get("slot", "weapon"))
			item.rarity = String(template.get("rarity", "uncommon"))
			item.icon_path = String(template.get("icon_path", ""))
			var ground := equipment_scene.instantiate() as GroundEquipmentItem
			ground.setup(item)
			add_child(ground)
			var player_height := ground._get_player_visual_height()
			var item_height := ground._icon_visual_size.y
			_check(
				item_height >= player_height * 0.7 - 0.01 and item_height <= player_height + 0.01,
				"ground icon visual height 70-100%%: %s / %s" % [character_id, template.get("id", "")]
			)
			ground.queue_free()
		sample_player.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	GameManager.selected_character_id = original_character_id

func _run_affix_runtime_check() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	var enemy := load("res://entities/enemies/enemy_basic.tscn").instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.id = "affix_test"
	data.display_name = "Affix Test"
	data.max_hp = 200.0
	data.move_speed = 0.0
	data.contact_damage = 10.0
	enemy.enemy_data = data
	enemy.elite_stat_multiplier = 1.5
	add_child(enemy)
	enemy.global_position = player.global_position + Vector2(24, 0)
	var settings := _read_json("res://data/elite_affixes/default.json")
	var ids: Array[String] = ["fire", "lightning", "freeze", "poison", "vampiric", "fortified"]
	var affixes := EliteAffixComponent.new()
	affixes.configure(enemy, ids, settings.get("affixes", {}))
	enemy.add_child(affixes)
	for id in ["fire", "lightning", "poison", "fortified"]:
		affixes._activate_periodic(id)
	affixes._on_elite_attack_landed(player.get_node("HurtboxComponent"))
	await get_tree().create_timer(1.1).timeout
	var found_affix := false
	for child in enemy.get_children():
		if child is EliteAffixComponent:
			found_affix = true
	_check(found_affix and affixes.affix_ids.size() == 6, "multiple affixes run together")
	_check(player.status_effect_component.has_effect("slow"), "freeze applies slow")
	enemy.queue_free()
	player.queue_free()
	for child in get_children():
		if child is EliteHazard or child is GroundEquipmentItem:
			child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _run_drop_runtime_check() -> void:
	# 直前のVisual検証でqueue_freeした地面装備をgroupから確実に除外してから差分を取る。
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.dungeon_map = DungeonGenerator.generate(40, 40, 5, 1)
	var system := EquipmentDropSystem.new()
	system.ground_item_scene = load("res://entities/pickups/ground_equipment_item.tscn")
	add_child(system)
	_check_template_catalog(system)
	_check(is_equal_approx(float(system._drop_table.get("normal_enemy_drop_chance", 0.0)), 0.02), "normal enemy equipment chance is two percent")
	_check(is_equal_approx(float(system._drop_table.get("strong_enemy_drop_chance", 0.0)), 0.04), "strong enemy equipment chance is four percent")
	_check(int(system._drop_table.get("boss_minimum_drop_count", 0)) == 1, "boss minimum drop count is one")
	var origin := GameManager.dungeon_map.grid_to_world(GameManager.dungeon_map.spawn_point)
	var before_count := get_tree().get_nodes_in_group("ground_equipment").size()
	for _elite_kill in 3:
		system.debug_force_enemy_drop(origin, true, false)
	await get_tree().process_frame
	await get_tree().process_frame
	var ground_items := get_tree().get_nodes_in_group("ground_equipment")
	_check(ground_items.size() - before_count == 3, "debug-forced strong enemy drops create three ground items (before=%d after=%d)" % [before_count, ground_items.size()])
	for index in range(before_count, ground_items.size()):
		var ground := ground_items[index] as GroundEquipmentItem
		_check(GameManager.dungeon_map.is_floor(GameManager.dungeon_map.world_to_grid(ground.global_position)), "equipment drop stays on floor")
		_check(ground.equipment.icon_path != "" and ResourceLoader.exists(ground.equipment.icon_path), "ground drop keeps catalog icon path")
		_check(ground.equipment.rarity in ["uncommon", "rare", "epic", "legendary", "mythic"], "guaranteed drop still uses rarity lottery")
		_check(_has_sprite_2d(ground.get_node("Visual")), "ground drop shows world item icon")
	var before_boss := get_tree().get_nodes_in_group("ground_equipment").size()
	system._on_enemy_drop_requested(origin, false, true)
	await get_tree().process_frame
	await get_tree().process_frame
	var after_boss := get_tree().get_nodes_in_group("ground_equipment").size()
	_check(after_boss == before_boss + 1, "actual boss death request guarantees at least one equipment drop")
	var final_weights: Dictionary = system._drop_table.get("boss_rarity_by_phase", {}).get("final", {})
	_check(float(final_weights.get("uncommon", -1.0)) == 0.0 and float(final_weights.get("legendary", 0.0)) + float(final_weights.get("mythic", 0.0)) >= 60.0, "ROOM 36 table removes uncommon and strongly favors top rarity")
	system.queue_free()

func _check_template_catalog(system: EquipmentDropSystem) -> void:
	_check(system._templates.size() == 25, "equipment template count is 25")
	var rarity_counts := {"uncommon":0, "rare":0, "epic":0, "legendary":0, "mythic":0}
	var slot_counts := {"weapon":0, "head":0, "body":0, "arms":0, "legs":0, "accessory":0}
	var template_rarities := {}
	for template in system._templates:
		var rarity := String(template.get("rarity", ""))
		var slot := String(template.get("slot", ""))
		rarity_counts[rarity] = int(rarity_counts.get(rarity, 0)) + 1
		slot_counts[slot] = int(slot_counts.get(slot, 0)) + 1
		template_rarities[String(template.get("id", ""))] = rarity
		var icon_path := String(template.get("icon_path", ""))
		_check(ResourceLoader.exists(icon_path), "catalog icon exists: %s" % icon_path)
		var texture := load(icon_path) as Texture2D
		_check(texture != null and texture.get_width() == 64 and texture.get_height() == 64, "catalog icon is 64x64: %s" % icon_path)
	for rarity in rarity_counts:
		_check(rarity_counts[rarity] == 5, "five designs for rarity: %s" % rarity)
	_check(slot_counts["weapon"] == 10, "ten weapon designs")
	for slot in ["head", "body", "arms", "legs", "accessory"]:
		_check(slot_counts[slot] == 3, "three designs for slot: %s" % slot)
	var original_rarities: Array = system._drop_table.get("rarities", []).duplicate(true)
	for rarity in rarity_counts:
		var expected_affixes: int = int({"uncommon":1, "rare":2, "epic":3, "legendary":3, "mythic":4}[rarity])
		system._drop_table["rarities"] = [{"id":rarity, "weight":1.0, "affix_count":expected_affixes, "special_effect":rarity in ["legendary", "mythic"]}]
		var generated := system._generate_equipment()
		_check(generated != null and generated.rarity == rarity, "rolled rarity is preserved: %s" % rarity)
		if generated:
			_check(template_rarities.get(generated.template_id, "") == rarity, "rarity-specific physical design selected: %s" % rarity)
			_check(generated.stats.size() == expected_affixes, "exact affix count: %s" % rarity)
			_check((not generated.special_effects.is_empty()) == (rarity in ["legendary", "mythic"]), "special effect tier: %s" % rarity)
			if rarity in ["legendary", "mythic"] and not generated.special_effects.is_empty():
				var effect_id: String = generated.special_effects[0]
				_check(not Dictionary(generated.special_effect_values.get(effect_id, {})).is_empty(), "special effect values stored: %s" % rarity)
	system._drop_table["rarities"] = original_rarities

func _has_texture_rect(root: Node) -> bool:
	if root is TextureRect and (root as TextureRect).texture != null:
		return true
	for child in root.get_children():
		if _has_texture_rect(child):
			return true
	return false

func _has_panel_container(root: Node) -> bool:
	if root is PanelContainer:
		return true
	for child in root.get_children():
		if _has_panel_container(child):
			return true
	return false

func _has_sprite_2d(root: Node) -> bool:
	if root is Sprite2D and (root as Sprite2D).texture != null:
		return true
	for child in root.get_children():
		if _has_sprite_2d(child):
			return true
	return false

func _count_equipment_slots(screen: EquipmentScreen) -> int:
	return screen.left_slots.get_child_count() + screen.top_slot.get_child_count() + screen.bottom_slot.get_child_count() + screen.right_slots.get_child_count()

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
