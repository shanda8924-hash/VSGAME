extends Node

const LAB_SCENE := preload("res://scenes/developer_test_lab.tscn")
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
	_check(lab.runtime_game != null and lab.player != null and lab.status_apply != null, "lab embeds the real game scene and systems")
	_check(lab.runtime_game.is_in_group("game_runtime_world"), "embedded game is the resolved runtime world")
	_check(lab.get_node_or_null("LabSplit/DeveloperControlPanel") != null, "developer control panel exists")
	_check(lab.get_node_or_null("LabSplit/RealGameField") != null, "real game field exists")
	_check(lab.get_node_or_null("TestModeBadge") != null, "TEST MODE save-disabled badge is visible")
	_check(SaveManager.is_ephemeral_session_active(), "Lab suspends persistent save writes")
	_check(_button_count(lab, "RETURN TITLE") == 1, "Lab exposes a return-to-title button")
	_check(_button_count(lab, "JUMP SELECTED") == 0 and _button_count(lab, "ROOM 36 FINAL") == 0, "Retired ROOM controls are absent")
	_check(_button_count(lab, "TRANSITION STRESS x12") == 0, "Retired ROOM stress control is absent")
	_check(_button_count(lab, "WIND BLADE / 風刃") == 1, "VFX Gallery exposes the generated Wind Concept preview")
	_check(_button_count(lab, "ACQUIRE ALL CONCEPT PARTS") == 1, "Test Lab exposes the Concept inventory preset")
	_check(_button_count(lab, "OPEN CONCEPT BOARD") == 1, "Test Lab exposes the real Concept Board")
	_check(_button_count(lab, "TRIGGER DIRECT CRITICAL") == 1 and _button_count(lab, "TRIGGER FIVE DIRECT HITS") == 1 and _button_count(lab, "TRIGGER 20 COMBO") == 1, "Test Lab exposes immediate Concept trigger controls")
	_check(_button_count(lab, "GRANT / LEVEL UP") == 1 and _button_count(lab, "TRIGGER NOW") == 1 and _button_count(lab, "RESET COOLDOWN") == 1, "Test Lab exposes completed Large Skill grant/trigger/cooldown controls")
	var signature_skill_count := 0
	for definition in lab.concept_system.get_completed_skill_definitions():
		if bool(definition.get("signature_skill", false)):
			signature_skill_count += 1
	_check(lab._completed_skill_select != null and signature_skill_count > 0 and lab._completed_skill_select.item_count == signature_skill_count, "Test Lab selector lists every signature Large Skill")
	_check(_button_count(lab, "アンコモン素材 ×3") == 1 and _button_count(lab, "レア素材 ×3") == 1 and _button_count(lab, "エピック素材 ×3") == 1, "Test Lab exposes the three requested merge-material rarity presets")
	_check(_button_count(lab, "合成画面を開く") == 1, "Test Lab opens the real three-slot merge screen")

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

	# 旧ELEMENTタブ(属性Lv設定・属性攻撃)は属性システムごと廃止済み。
	# 代替のSTATUSボタンがStatusApplySystemへ繋がっていること、および燃焼の
	# 継続ダメージが実ダメージ経路を通ってDamage Meterへ届くことを確認する。
	var dummy: EnemyBasic = lab.spawn_dummy()
	var dummy_status := dummy.get_node("StatusEffectComponent") as StatusEffectComponent
	_stage = "status_apply"
	print("LAB_CHECK stage=status_apply")
	for state_id in ["burning", "frozen", "charged", "marked", "cursed"]:
		lab._apply_status_to_dummy(state_id)
	await get_tree().process_frame
	_check(dummy_status.get_states().size() == 5, "Lab STATUS buttons apply all five states to the dummy")

	# Damage Meterは実WeaponManager経路(Lab の TRIGGER PROJECTILE と同じ)で確認する。
	lab.reset_damage_meter()
	lab.trigger_projectile()
	var meter_hit := false
	for _frame in 180:
		await get_tree().process_frame
		if lab._damage_total > 0.0 and lab._damage_hits > 0:
			meter_hit = true
			break
	_check(meter_hit, "real attack path reaches the damage meter")
	lab._clear_dummy_status()
	await get_tree().process_frame
	_check(dummy_status.get_states().is_empty(), "Lab CLEAR removes every applied state")
	lab.preview_wind_blade_vfx()
	await get_tree().process_frame
	var wind_vfx := _find_concept_vfx("concept_wind_blade")
	_check(wind_vfx != null and wind_vfx.get_node_or_null("WindBladePixelVFX") is AnimatedSprite2D, "Wind Concept preview displays its generated six-frame Pixel Art")

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
	lab._completed_skill_grant_all()
	_check(lab.concept_system.get_completed_skill_count() == 5, "Concept Lab grants all five Large Skills without exceeding the six-slot cap")
	lab._completed_skill_trigger_selected()
	_check(_find_signature_vfx("thunderlord_descent") != null, "Concept Lab TRIGGER NOW spawns the selected dedicated Large Skill VFX")
	lab._completed_skill_ready_selected()
	_check(is_zero_approx(lab.concept_system.get_completed_skill_cooldown("thunderlord_descent")), "Concept Lab RESET COOLDOWN exposes the real cooldown state")
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
	_check(lab.concept_system.acquired_ids.is_empty() and lab.concept_system.get_completed_skill_count() == 0, "Reset clears Concept inventory, Board, and completed Large Skills")
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

func _find_concept_vfx(pixel_vfx_id: String) -> ConceptSkillVFX:
	for effect in get_tree().get_nodes_in_group("transient_vfx"):
		var concept_effect := effect as ConceptSkillVFX
		if concept_effect != null and String(concept_effect.get_meta("pixel_vfx_id", "")) == pixel_vfx_id:
			return concept_effect
	return null


func _find_signature_vfx(profile: String) -> ConceptSkillVFX:
	for effect in get_tree().get_nodes_in_group("transient_vfx"):
		var concept_effect := effect as ConceptSkillVFX
		if concept_effect != null and String(concept_effect.get_meta("signature_vfx_profile", "")) == profile:
			return concept_effect
	return null

func _watchdog_timeout() -> void:
	push_error("DEVELOPER_TEST_LAB_CHECK watchdog stage=%s" % _stage)
	get_tree().paused = false
	get_tree().quit(1)
