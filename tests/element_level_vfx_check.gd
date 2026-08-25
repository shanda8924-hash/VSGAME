extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")
const PROJECTILE_SCENE := preload("res://entities/projectiles/projectile.tscn")

var failures: Array[String] = []
var feedback_events: Array[Dictionary] = []
var element_effect_count := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run_checks()
	for failure in failures:
		push_error(failure)
	print("ELEMENT_LEVEL_VFX_CHECK failures=%d feedback=%d" % [failures.size(), feedback_events.size()])
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
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	var player := game.get_node("Player") as Player
	var manager := game.get_node("AttackVFXManager") as AttackVFXManager
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	manager.element_level_feedback_spawned.connect(_on_feedback)
	manager.element_effect_spawned.connect(func(_id, _effect): element_effect_count += 1)
	var cases := [
		["fire", "element_fire", "embers"],
		["ice", "element_ice", "crystals"],
		["lightning", "element_lightning", "arcs"],
		["light", "element_light", "rays"],
		["dark", "element_dark", "rifts"],
	]
	var seen_styles := {}
	for entry in cases:
		GameManager.set_active_element(GameManager.ELEMENT_NONE)
		GameManager.held_fragment_ids.clear()
		feedback_events.clear()
		var projectile_count_before := _count_projectiles(game)
		var weapon_count_before := player.weapon_manager.get_weapon_instances().size()
		for expected_level in range(1, 4):
			GameManager.add_fragment(entry[0])
			_check(GameManager.get_active_element_ids() == [entry[1]], "%s Lv%d keeps one unique active slot" % [entry[0], expected_level])
			_check(GameManager.get_element_stack(entry[1]) == expected_level, "%s reaches Lv%d" % [entry[0], expected_level])
			_check(_count_projectiles(game) == projectile_count_before, "%s Lv%d transition spawns no projectile" % [entry[0], expected_level])
			_check(player.weapon_manager.get_weapon_instances().size() == weapon_count_before, "%s Lv%d transition creates no weapon/attack" % [entry[0], expected_level])
		_check(feedback_events.size() == 2, "%s only Lv2/Lv3 create level feedback" % entry[0])
		if feedback_events.size() == 2:
			_check(int(feedback_events[0]["level"]) == 2 and int(feedback_events[1]["level"]) == 3, "%s feedback order is Lv2 then Lv3" % entry[0])
			for event in feedback_events:
				var effect := event["effect"] as Node2D
				_check(effect != null and _count_projectiles(effect) == 0, "%s feedback contains no projectile node" % entry[0])
		var data := DataLoader.element_vfx_effects.get(entry[1]) as ElementVFXData
		_check(data != null and data.stack_accent_style == entry[2], "%s uses its own accent style" % entry[0])
		_check(data != null and data.level3_accent_count > data.level2_accent_count, "%s Lv3 adds more secondary detail than Lv2" % entry[0])
		seen_styles[entry[2]] = true
		var accent_before := _count_prefix(manager, "ElementStackAccent_")
		manager.play_element_hit(player.global_position + Vector2(70, 0), data, 1)
		_check(_count_prefix(manager, "ElementStackAccent_") == accent_before, "%s Lv1 hit remains unchanged" % entry[0])
		manager.play_element_hit(player.global_position + Vector2(70, 0), data, 2)
		var level2_accent := _find_latest_accent(manager, entry[1], 2)
		_check(level2_accent != null and int(level2_accent.get_meta("accent_count")) == data.level2_accent_count, "%s Lv2 hit adds secondary accent" % entry[0])
		manager.play_element_hit(player.global_position + Vector2(70, 0), data, 3)
		var level3_accent := _find_latest_accent(manager, entry[1], 3)
		_check(level3_accent != null and int(level3_accent.get_meta("accent_count")) == data.level3_accent_count, "%s Lv3 hit adds denser secondary accent" % entry[0])
		manager.play_iai_trail(player.global_position, player.global_position + Vector2(72, 0))
		_check(_find_latest_trail_accent(manager, entry[1], 3) != null, "%s Lv3 Iai adds a local secondary trail" % entry[0])
		await get_tree().create_timer(0.82, true, false, true).timeout
	_check(seen_styles.size() == 5, "all five elements have distinct visual languages")

	GameManager.set_active_element("element_fire")
	element_effect_count = 0
	manager.play_hit(player.global_position + Vector2(40, 0), "fire", false)
	_check(element_effect_count == 0, "physical auto-hit no longer injects element/Fusion overlay")

	GameManager.set_active_element("element_lightning")
	var class_weapon := WeaponData.new()
	class_weapon.id = "class_projectile_visual_probe"
	class_weapon.base_damage = 1.0
	class_weapon.vfx_theme_id = "lightning"
	var class_projectile := PROJECTILE_SCENE.instantiate() as Projectile
	game.add_child(class_projectile)
	class_projectile.global_position = player.global_position
	class_projectile.speed = 0.0
	class_projectile.launch(player.global_position + Vector2(300, 0), class_weapon)
	_check(class_projectile.get_node("Visual").visible, "Archer/Wizard-style class projectile keeps its original visual")
	_check(class_projectile.get_node("Glow").visible, "original class projectile keeps its compact weapon glow")
	_check(class_projectile.get_node_or_null("ElementProjectile_vfx_lightning_projectile") == null, "active element does not replace a class projectile")
	class_projectile.queue_free()

	var fusion_weapon := WeaponData.new()
	fusion_weapon.id = "fusion_projectile_visual_probe"
	fusion_weapon.base_damage = 1.0
	fusion_weapon.vfx_theme_id = "fire"
	fusion_weapon.required_fragment_ids = ["fire", "ice"]
	var fusion_projectile := PROJECTILE_SCENE.instantiate() as Projectile
	game.add_child(fusion_projectile)
	fusion_projectile.global_position = player.global_position
	fusion_projectile.speed = 0.0
	fusion_projectile.launch(player.global_position + Vector2(300, 0), fusion_weapon)
	_check(not fusion_projectile.get_node("Visual").visible and fusion_projectile.get_node("Glow").visible, "Fusion gameplay projectile remains arrow-free with its own glow")
	fusion_projectile.queue_free()

	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	GameManager.held_fragment_ids.clear()
	game.queue_free()
	await get_tree().process_frame

func _on_feedback(element_id: String, level: int, effect: Node2D) -> void:
	feedback_events.append({"element_id": element_id, "level": level, "effect": effect})

func _find_latest_accent(manager: Node, element_id: String, level: int) -> Node2D:
	for child in manager.get_children():
		if child is Node2D and child.name.begins_with("ElementStackAccent_") and child.get_meta("element_id", "") == element_id and int(child.get_meta("variant_level", 0)) == level:
			return child
	return null

func _find_latest_trail_accent(manager: Node, element_id: String, level: int) -> Node2D:
	for child in manager.get_children():
		if child is Node2D and "_Trail_" in child.name and child.get_meta("element_id", "") == element_id and int(child.get_meta("variant_level", 0)) == level:
			return child
	return null

func _count_prefix(root: Node, prefix: String) -> int:
	var count := 1 if root.name.begins_with(prefix) else 0
	for child in root.get_children():
		count += _count_prefix(child, prefix)
	return count

func _count_projectiles(root: Node) -> int:
	var count := 1 if root is Projectile else 0
	for child in root.get_children():
		count += _count_projectiles(child)
	return count

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
