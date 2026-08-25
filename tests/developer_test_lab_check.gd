extends Node

const LAB_SCENE := preload("res://scenes/developer_test_lab.tscn")
const FUSION_IDS := ["frostfire", "plasma", "solar", "inferno", "superconductor", "aurora", "void_frost", "judgment", "voidstorm", "eclipse"]
var failures: Array[String] = []
var _stage := "boot"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(20.0, true, false, true).timeout.connect(_watchdog_timeout)
	var lab = LAB_SCENE.instantiate()
	add_child(lab)
	_stage = "await_lab_ready"
	print("LAB_CHECK stage=await_lab_ready")
	await lab.lab_ready
	_stage = "player"
	print("LAB_CHECK stage=player")
	_check(OS.is_debug_build(), "test runtime is a debug build")
	_check(lab.runtime_game != null and lab.player != null and lab.element_combat != null, "lab embeds the real game scene and systems")
	_check(lab.runtime_game.is_in_group("game_runtime_world"), "embedded game is the resolved runtime world")
	_check(lab.get_node_or_null("LabSplit/DeveloperControlPanel") != null, "developer control panel exists")
	_check(lab.get_node_or_null("LabSplit/RealGameField") != null, "real game field exists")
	_check(lab.get_node_or_null("TestModeBadge") != null, "TEST MODE save-disabled badge is visible")
	_check(SaveManager.is_ephemeral_session_active(), "Lab suspends persistent save writes")
	_check(_button_count(lab, "RETURN TITLE") == 1, "Lab exposes a return-to-title button")
	_check(_button_count(lab, "JUMP SELECTED") == 1 and _button_count(lab, "ROOM 36 FINAL") == 1, "Room Lab exposes arbitrary and Final ROOM jumps")
	_check(_button_count(lab, "TRANSITION STRESS x12") == 1, "Room Lab exposes transition stress")
	_check(_button_count(lab, "IAI (REAL HIT)") == 5, "all registered gameplay elements expose real IAI checks")
	for required_label in ["CREATE", "TRIGGER ATTACK", "TRIGGER HIT", "TRIGGER BONUS TRAIT", "TRIGGER INTRO"]:
		_check(_button_count(lab, required_label) >= 10, "Fusion Lab exposes %s for all ten Fusions" % required_label)
	_check(_button_count(lab, "PREVIEW ALL FUSIONS") == 1, "Fusion Lab exposes one continuous Pixel Art preview")
	_check(_button_count(lab, "LIGHTNING → PLASMA → LIGHTNING") == 1, "Fusion Lab exposes Lightning / Plasma comparison")
	_check(_button_count(lab, "FIRE → PLASMA → FIRE") == 1, "Fusion Lab exposes Fire / Plasma comparison")
	_check(_button_count(lab, "LIGHTNING → RADIANT ARC → LIGHTNING") == 1, "Fusion Lab exposes Lightning / Radiant Arc comparison")
	_check(_button_count(lab, "WIND BLADE / 風刃") == 1, "VFX Gallery exposes the generated Wind Concept preview")
	_check(_button_count(lab, "ACQUIRE ALL CONCEPT PARTS") == 1, "Test Lab exposes the Concept inventory preset")
	_check(_button_count(lab, "OPEN CONCEPT BOARD") == 1, "Test Lab exposes the real Concept Board")
	_check(_button_count(lab, "TRIGGER DIRECT CRITICAL") == 1 and _button_count(lab, "TRIGGER FIVE DIRECT HITS") == 1 and _button_count(lab, "TRIGGER 20 COMBO") == 1, "Test Lab exposes immediate Concept trigger controls")
	_check(_button_count(lab, "アンコモン素材 ×3") == 1 and _button_count(lab, "レア素材 ×3") == 1 and _button_count(lab, "エピック素材 ×3") == 1, "Test Lab exposes the three requested merge-material rarity presets")
	_check(_button_count(lab, "合成画面を開く") == 1, "Test Lab opens the real three-slot merge screen")
	_check(GameManager.get_fusion_display_name("judgment") == "RADIANT ARC / 聖雷", "legacy judgment id presents the redesigned Radiant Arc name")

	var start_level: int = lab.player.experience_component.level
	lab.add_player_levels(1)
	_check(lab.player.experience_component.level == start_level + 1, "Player Level +1 uses ExperienceComponent")
	var level_up_select: LevelUpSelect = lab.runtime_game.get_node("LevelUpSelect") as LevelUpSelect
	_check(level_up_select.visible, "Player Level +1 opens the real LevelUpSelect")
	for child in level_up_select.grid_container.get_children():
		if child is Button and not child.disabled:
			child.pressed.emit()
			break
	_check(not level_up_select.visible and not get_tree().paused, "real LevelUp selection closes before the next modal")
	lab.player.health_component.current_hp = 1.0
	lab.full_heal()
	_check(is_equal_approx(lab.player.health_component.current_hp, lab.player.health_component.max_hp), "Full Heal uses HealthComponent")

	_check(lab.set_element_level("fire", 3, false), "Normal mode reaches Fire Lv3 through acquisition")
	_check(GameManager.get_element_stack("element_fire") == 3, "Normal element state is stored by GameManager")
	var projectile_before := get_tree().get_nodes_in_group("projectiles").size()
	lab.trigger_element_transition("light", 1)
	_check(GameManager.get_element_stack("element_light") == 2, "one-click Light Lv1 to Lv2 transition works")
	_check(get_tree().get_nodes_in_group("projectiles").size() == projectile_before, "element level transition creates no projectile")
	_check(lab.set_element_level("dark", 3, true), "Force mode sets Dark Lv3 immediately")

	lab.reset_damage_meter()
	_stage = "element_attack"
	print("LAB_CHECK stage=element_attack")
	lab.trigger_element_attack("fire")
	await get_tree().process_frame
	_check(lab._damage_total > 0.0 and lab._damage_hits > 0, "real attack path reaches the damage meter")
	lab.preview_wind_blade_vfx()
	await get_tree().process_frame
	var wind_vfx := _find_concept_vfx("concept_wind_blade_v2")
	_check(wind_vfx != null and wind_vfx.get_node_or_null("WindBladePixelVFX") is AnimatedSprite2D, "Wind Concept preview displays its generated six-frame Pixel Art")

	for fusion_id in FUSION_IDS:
		_stage = "fusion_%s" % fusion_id
		print("LAB_CHECK stage=%s" % _stage)
		_check(lab.create_fusion(fusion_id, false), "Force creates %s" % fusion_id)
		lab.trigger_fusion_attack(fusion_id)
		_check(GameManager.active_fusion_id == fusion_id, "%s is active in GameManager" % fusion_id)
		lab.trigger_fusion_vfx(fusion_id, "hit")
		var hit_effect := _find_fusion_effect(fusion_id, "hit")
		_check(hit_effect != null and bool(hit_effect.get_meta("generated_pixel_art", false)), "%s Lab HIT displays generated Pixel Art" % fusion_id)
		lab.trigger_fusion_bonus(fusion_id)
		_check(GameManager.active_fusion_id == fusion_id, "%s Lab BONUS TRAIT runs in the selected Fusion" % fusion_id)
		lab.trigger_fusion_intro(fusion_id)
		var intro_effect := _find_fusion_effect(fusion_id, "formation")
		_check(intro_effect != null and bool(intro_effect.get_meta("generated_pixel_art", false)), "%s Lab INTRO displays generated Pixel Art" % fusion_id)
		# Human-paced gallery use lets the current formation finish before the next
		# Fusion. Avoid testing all ten presentations as a same-frame burst.
		await get_tree().create_timer(0.78, true, false, true).timeout
	_check(lab.create_fusion("plasma", true), "Natural Fusion uses two Lv3 acquisition paths")
	_check(GameManager.active_fusion_id == "plasma", "Natural Fusion resolves Plasma")

	lab.apply_reward_preset("NO ELEMENT")
	_stage = "reward"
	print("LAB_CHECK stage=reward")
	lab.open_boss_reward()
	_check(lab.fragment_select.visible, "Boss reward opens without killing a boss")
	_check(lab.fragment_select.grid_container.get_child_count() == 4, "Boss reward uses the real four-choice pool")
	for child in lab.fragment_select.grid_container.get_children():
		if child is Button and not child.disabled:
			child.pressed.emit()
			break
	_check(not lab.fragment_select.visible and not get_tree().paused, "reward selection closes the real modal")

	_stage = "concept"
	print("LAB_CHECK stage=concept")
	lab._concept_acquire_all()
	lab._concept_build_chain(0, "trigger_on_critical", "skill_thunder_strike", "modifier_chain")
	lab._concept_build_chain(1, "trigger_fifth_hit", "skill_fire_burst", "modifier_area")
	_check(lab.concept_system.acquired_ids.size() == 14, "Concept Lab acquires all data-driven Concept parts")
	_check(lab.concept_system.get_chain(0).get("skill") == "skill_thunder_strike" and lab.concept_system.get_chain(1).get("modifier") == "modifier_area", "Concept Lab equips both three-slot Chains")
	var lab_trigger_count := [0]
	lab.concept_system.skill_triggered.connect(func(_chain, _skill, _depth): lab_trigger_count[0] += 1)
	lab._concept_trigger_critical()
	_check(lab_trigger_count[0] >= 1, "Concept Lab direct Critical control triggers the equipped real Chain")
	lab.concept_board.show_board("DEVELOPER CONCEPT BOARD")
	_check(lab.concept_board.visible, "Concept Lab opens the real Board modal")
	lab.concept_board.done_button.pressed.emit()
	_check(not lab.concept_board.visible and not get_tree().paused, "Concept Board closes through the modal lifecycle")

	var spawned: Array = lab.spawn_enemies(10, "Line", lab._selected_enemy_id())
	_stage = "enemy"
	print("LAB_CHECK stage=enemy")
	_check(spawned.size() == 10 and spawned.all(func(enemy): return enemy.get_parent() == lab.runtime_game), "enemy controls spawn real enemies inside the game field")
	lab._clear_enemies(false, false)
	await get_tree().process_frame

	var boss := lab.spawn_selected_boss() as EnemyBasic
	_stage = "boss"
	print("LAB_CHECK stage=boss")
	_check(boss != null and boss.enemy_data is BossData, "Boss control spawns a real BossData enemy")
	lab.set_boss_hp_ratio(0.5)
	_check(boss != null and is_equal_approx(boss.health_component.current_hp, boss.health_component.max_hp * 0.5), "Boss HP preset updates the real HealthComponent")
	lab.clear_boss()
	await get_tree().process_frame

	var equipment: EquipmentData = lab.equipment_add_selected()
	_stage = "equipment"
	print("LAB_CHECK stage=equipment")
	_check(equipment != null and equipment in lab.player.equipment_component.inventory, "equipment factory adds a real EquipmentData instance")
	lab.equipment_equip_selected()
	_check(lab.player.equipment_component.is_equipped(equipment), "equipment control uses EquipmentComponent.equip")
	lab.equipment_give_rarity_materials("uncommon")
	var merged: EquipmentData = lab.equipment_merge_selected()
	_check(merged != null and merged in lab.player.equipment_component.inventory, "three different items merge through EquipmentMergeSystem")
	lab.clear_ground_loot()
	await get_tree().process_frame
	lab.drop_all_rarities()
	_check(get_tree().get_nodes_in_group("ground_equipment").size() == 5, "loot control drops all five real rarity visuals")

	lab.trigger_projectile()
	_stage = "projectile"
	print("LAB_CHECK stage=projectile")
	await get_tree().process_frame
	_check(not get_tree().get_nodes_in_group("projectiles").is_empty(), "projectile control uses WeaponManagerComponent")
	lab.clear_projectiles()
	_stage = "reset"
	print("LAB_CHECK stage=reset")
	await lab.reset_lab_state()
	_check(GameManager.get_active_element_ids().is_empty() and GameManager.active_fusion_id == "", "Reset clears Element and Fusion state")
	_check(lab.concept_system.acquired_ids.is_empty(), "Reset clears Concept inventory and Board state")
	_check(get_tree().get_nodes_in_group("projectiles").is_empty(), "Reset clears projectiles")

	_stage = "cleanup"
	lab.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not SaveManager.is_ephemeral_session_active(), "leaving Lab restores the normal save session")
	AudioManager.stop_all()
	await get_tree().create_timer(0.25, true, false, true).timeout
	for failure in failures:
		push_error(failure)
	print("DEVELOPER_TEST_LAB_CHECK failures=%d" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

func _button_count(root: Node, text_value: String) -> int:
	var button := root as Button
	var count := 1 if button != null and button.text == text_value else 0
	for child in root.get_children():
		count += _button_count(child, text_value)
	return count

func _find_fusion_effect(fusion_id: String, mode: String) -> FusionVFXEffect:
	for effect in get_tree().get_nodes_in_group("transient_vfx"):
		var fusion_effect := effect as FusionVFXEffect
		if fusion_effect != null and fusion_effect.fusion_id == fusion_id and fusion_effect.mode == mode:
			return fusion_effect
	return null

func _find_concept_vfx(pixel_vfx_id: String) -> ConceptSkillVFX:
	for effect in get_tree().get_nodes_in_group("transient_vfx"):
		var concept_effect := effect as ConceptSkillVFX
		if concept_effect != null and String(concept_effect.get_meta("pixel_vfx_id", "")) == pixel_vfx_id:
			return concept_effect
	return null

func _watchdog_timeout() -> void:
	push_error("DEVELOPER_TEST_LAB_CHECK watchdog stage=%s" % _stage)
	get_tree().paused = false
	get_tree().quit(1)
