extends Node
## 実game.tscnで属性Lv、2スロット、追加Damage Number、雷飛翔体／連鎖、居合表示を検証する。

const GAME_SCENE := preload("res://scenes/game.tscn")
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")
const PROJECTILE_SCENE := preload("res://entities/projectiles/projectile.tscn")

var failures: Array[String] = []
var element_damage_events: Array[Dictionary] = []
var chain_links: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.element_damage_dealt.connect(_on_element_damage)
	GameManager.selected_character_id = "swordsman"
	var game := GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().physics_frame
	_disable_background_spawners(game)
	await _clear_enemies()
	await _run_checks(game)
	for failure in failures:
		push_error(failure)
	print("ELEMENT_STACK_COMBAT_CHECK failures=%d" % failures.size())
	get_tree().paused = false
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	AudioManager.stop_all()
	await get_tree().create_timer(0.2, true, false, true).timeout
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _run_checks(game: Node) -> void:
	var player := game.get_node("Player") as Player
	var hud := game.get_node("HUD") as HUD
	var vfx := game.get_node("AttackVFXManager") as AttackVFXManager
	var combat := game.get_node("ElementCombatSystem") as ElementCombatSystem
	var number_manager := game.get_node("DamageNumberManager") as DamageNumberManager
	combat.chain_link_spawned.connect(_on_chain_link)
	_check(GameManager.get_active_element_ids().is_empty(), "run starts with empty element loadout")
	_check("なし" in hud.active_element_label.text, "HUD starts with no element")
	_check(int(DataLoader.element_combat_config.get("max_stack", 0)) == 3, "element stack cap is three")
	_check(int(DataLoader.element_combat_config.get("max_active_elements", 0)) == 2, "element loadout has two slots")

	# 火Lv1→Lv3、Lv4相当取得の頭打ち、VFX scaleの段階差。
	var fire_trail_scales: Array[float] = []
	for expected_level in range(1, 5):
		GameManager.add_fragment("fire")
		var expected_stack := mini(expected_level, 3)
		_check(GameManager.get_element_stack("element_fire") == expected_stack, "fire stack reaches Lv%d and caps at Lv3" % expected_level)
		if expected_level <= 3:
			var trail := vfx.play_iai_trail(player.global_position, player.global_position + Vector2(72.0, 0.0))
			_check(trail != null, "fire Lv%d Iai trail spawns" % expected_level)
			if trail:
				fire_trail_scales.append(trail.scale.y)
	_check(fire_trail_scales.size() == 3 and fire_trail_scales[0] < fire_trail_scales[1] and fire_trail_scales[1] < fire_trail_scales[2], "fire Iai VFX scales at Lv1/Lv2/Lv3")
	_check("火 Lv3" in hud.active_element_label.text, "HUD shows fire stack Lv3")

	# 2属性保持。2枠確定後は3種類目で置換せず、Run中のBuildをLockする。
	GameManager.add_fragment("ice")
	_check(GameManager.get_active_element_ids() == ["element_fire", "element_ice"], "different element fills second slot")
	_check(GameManager.get_element_stack("element_fire") == 3 and GameManager.get_element_stack("element_ice") == 1, "two element stacks coexist")
	GameManager.add_fragment("lightning")
	_check(GameManager.get_active_element_ids() == ["element_fire", "element_ice"], "third element cannot replace locked slots")
	_check(GameManager.get_element_stack("element_lightning") == 0, "rejected third element receives no stack")
	_check("火 Lv3" in hud.active_element_label.text and "氷 Lv1" in hud.active_element_label.text and "LOCKED" in hud.active_element_label.text, "HUD shows locked two-slot build and levels")

	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	GameManager.add_fragment("fire")
	GameManager.add_fragment("ice")
	GameManager.add_fragment("lightning")
	_check(GameManager.get_active_element_ids() == ["element_fire", "element_ice"], "equal-stack build also rejects a third element")

	# 各属性の比率はLvごとに単調増加し、実ダメージと色付き数値を発生させる。
	for element_entry in [["fire", "element_fire"], ["ice", "element_ice"], ["lightning", "element_lightning"]]:
		var ratios: Array = DataLoader.element_combat_config["elements"][element_entry[1]]["damage_ratios"]
		_check(ratios.size() == 3 and float(ratios[0]) < float(ratios[1]) and float(ratios[1]) < float(ratios[2]), "%s damage ratio rises through Lv3" % element_entry[0])
		GameManager.set_active_element(GameManager.ELEMENT_NONE)
		GameManager.add_fragment(element_entry[0])
		var target := _spawn_enemy(game, player.global_position + Vector2(100.0, 0.0))
		element_damage_events.clear()
		var hp_before := target.health_component.current_hp
		combat.apply_element_damage(target.hurtbox_component, 100.0, player.global_position)
		var expected := 100.0 * float(ratios[0])
		_check(is_equal_approx(hp_before - target.health_component.current_hp, expected), "%s Lv1 applies separate element damage" % element_entry[0])
		_check(not element_damage_events.is_empty() and element_damage_events[0]["element_id"] == element_entry[1], "%s emits typed element damage event" % element_entry[0])
		await get_tree().process_frame
		_check(_has_visible_element_number(number_manager, element_entry[1]), "%s colored damage number is visible" % element_entry[0])
		target.queue_free()
		await get_tree().process_frame
		if element_entry[0] == "fire":
			await get_tree().process_frame
			_check(combat._burning_targets.is_empty(), "fire burn tracking removes a freed target without recurring errors")

	# 本番Space Hit経路でベースDamageとは別に火追加Damageが通る。
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	GameManager.add_fragment("fire")
	var actual_target := _spawn_enemy(game, player.global_position + Vector2(90.0, 0.0))
	var actual_before := actual_target.health_component.current_hp
	player.active_skill_component._damage_enemy(actual_target, 100.0, 0.0)
	_check(is_equal_approx(actual_before - actual_target.health_component.current_hp, 110.0), "actual active-skill hit applies base 100 plus fire Lv1 10")
	actual_target.queue_free()
	await get_tree().process_frame

	# 雷Lv3はArrowを隠し、Loopする電撃Spriteへ置換する。
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	for _i in 3:
		GameManager.add_fragment("lightning")
	var weapon := WeaponData.new()
	weapon.base_damage = 10.0
	weapon.crit_chance = 0.0
	weapon.crit_multiplier = 2.0
	weapon.vfx_theme_id = "lightning"
	var projectile := PROJECTILE_SCENE.instantiate() as Projectile
	game.add_child(projectile)
	projectile.global_position = player.global_position
	projectile.launch(player.global_position + Vector2(300.0, 0.0), weapon)
	var lightning_sprite := projectile.get_node_or_null("ElementProjectile_vfx_lightning_projectile") as AnimatedSprite2D
	_check(projectile.get_node("Visual").visible, "lightning modifier keeps intentional class projectile visual")
	_check(projectile.get_node("Glow").visible, "class projectile keeps compact weapon-theme glow")
	_check(lightning_sprite == null, "active element does not replace intentional class projectile")
	projectile.queue_free()

	# 雷Lv3: 初撃+最大4連鎖、310px、同一敵再Hitなし、78/62/50%...の減衰。
	await _clear_enemies()
	element_damage_events.clear()
	chain_links.clear()
	var chain_targets: Array[EnemyBasic] = []
	for index in 4:
		chain_targets.append(_spawn_enemy(game, player.global_position + Vector2(70.0 + index * 110.0, 0.0)))
	combat.apply_element_damage(chain_targets[0].hurtbox_component, 100.0, player.global_position)
	_check(chain_links.size() == 3, "lightning Lv3 creates three chain jumps")
	_check(element_damage_events.size() == 4, "lightning initial hit plus three chain damage events")
	if element_damage_events.size() == 4:
		_check(float(element_damage_events[1]["amount"]) > float(element_damage_events[2]["amount"]) and float(element_damage_events[2]["amount"]) > float(element_damage_events[3]["amount"]), "lightning chain damage decays per jump")
		_check(is_equal_approx(float(element_damage_events[1]["amount"]), 28.08), "first chain is 78 percent of lightning bonus")
		_check(is_equal_approx(float(element_damage_events[2]["amount"]), 22.32), "second chain is 62 percent of lightning bonus")
		_check(is_equal_approx(float(element_damage_events[3]["amount"]), 18.0), "third chain is 50 percent of lightning bonus")
	var unique_targets := {}
	for event in element_damage_events:
		unique_targets[Vector2(event["position"])] = true
	_check(unique_targets.size() == 4, "lightning chain never re-hits the same enemy")
	for index in range(1, chain_targets.size()):
		chain_targets[index].queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	chain_links.clear()
	combat.apply_element_damage(chain_targets[0].hurtbox_component, 100.0, player.global_position)
	_check(chain_links.is_empty(), "lightning chain ends naturally without another target")

	# ベース攻撃が起点敵を倒した場合も、その命中から近隣の生存敵へ連鎖する。
	await _clear_enemies()
	element_damage_events.clear()
	chain_links.clear()
	var killing_blow_targets: Array[EnemyBasic] = []
	for index in 4:
		killing_blow_targets.append(_spawn_enemy(game, player.global_position + Vector2(70.0 + index * 110.0, 0.0)))
	killing_blow_targets[0].health_component.current_hp = 5.0
	player.active_skill_component._damage_enemy(killing_blow_targets[0], 100.0, 0.0)
	_check(killing_blow_targets[0].health_component.current_hp <= 0.0, "lightning test base hit defeats its first target")
	_check(chain_links.size() == 3, "lightning chain still starts from a base-hit killing blow")
	_check(element_damage_events.size() == 3, "killing-blow chain damages only the three living jump targets")

	# 居合の旧扇Polygon呼び出しは存在せず、Trailは主属性Lvに応じて残る。
	var active_skill_text := FileAccess.get_file_as_string("res://components/active_skill_component.gd")
	_check("_spawn_vfx(distance * 0.55, 14.0, \"slash\")" not in active_skill_text, "Iai fan-shaped slash polygon call is removed")
	var lightning_trail := vfx.play_iai_trail(player.global_position, player.global_position + Vector2(72.0, 0.0))
	_check(lightning_trail != null and lightning_trail.scale.y > fire_trail_scales[0], "Iai keeps a stack-strengthened elemental slash trail")

	# 新Fusion Buildは欠片消費を行わず、run終了で2スロット・Lv・Masteryを消去する。
	GameManager.held_fragment_ids.clear()
	GameManager.add_fragment("fire")
	GameManager.add_fragment("ice")
	await get_tree().process_frame
	_check(not GameManager.get_active_element_ids().is_empty(), "Fusion fragment consumption does not erase element loadout")
	GameManager.end_run()
	_check(GameManager.get_active_element_ids().is_empty() and GameManager.active_element_id == GameManager.ELEMENT_NONE, "run end clears active element slots")
	_check(GameManager.get_element_stack("element_fire") == 0 and GameManager.get_element_stack("element_ice") == 0 and GameManager.get_element_stack("element_lightning") == 0, "run end resets all element stacks")
	_check("なし" in hud.active_element_label.text, "HUD resets after run end")

func _disable_background_spawners(game: Node) -> void:
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		var node := game.get_node_or_null(node_name)
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED

func _clear_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _spawn_enemy(game: Node, position: Vector2) -> EnemyBasic:
	var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.id = "element_stack_target"
	data.display_name = "Element Stack Target"
	data.max_hp = 1000.0
	data.move_speed = 0.0
	data.contact_damage = 0.0
	data.attack_range = 0.0
	data.attack_interval = 99.0
	data.attack_windup = 99.0
	enemy.enemy_data = data
	game.add_child(enemy)
	enemy.global_position = position
	return enemy

func _has_visible_element_number(manager: DamageNumberManager, element_id: String) -> bool:
	var expected: Color = DamageNumber.ELEMENT_COLORS.get(element_id, DamageNumber.NORMAL_COLOR)
	for child in manager.get_children():
		if child is DamageNumber and child.visible and child.get_theme_color("font_color").is_equal_approx(expected):
			return true
	return false

func _on_element_damage(amount: float, position: Vector2, element_id: String, stack_level: int, chain_index: int) -> void:
	element_damage_events.append({"amount": amount, "position": position, "element_id": element_id, "stack": stack_level, "chain_index": chain_index})

func _on_chain_link(from: Vector2, to: Vector2, jump_index: int, damage: float) -> void:
	chain_links.append({"from": from, "to": to, "jump_index": jump_index, "damage": damage})

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
