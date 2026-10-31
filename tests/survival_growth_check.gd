extends Node
var game: Node2D
var actor: Player
var failures: Array[String] = []
var OUT := "res://artifacts/survival_growth"
var report: Dictionary = {}
var _auto_choose := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	if "--touch-preview" in OS.get_cmdline_user_args(): OUT += "/mobile"
	DirAccess.make_dir_recursive_absolute(OUT)
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame
		if _auto_choose and is_instance_valid(game):
			var ui := game.get_node("LevelUpSelect") as LevelUpSelect
			if ui.visible and ui.grid_container.get_child_count()>0:
				(ui.grid_container.get_child(0) as Button).pressed.emit()
				ui.confirm_selection()

func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT+"/"+name+".png")

func click_control(button: Button) -> void:
	var point := get_viewport().get_stretch_transform() * button.get_global_rect().get_center()
	if "--touch-preview" in OS.get_cmdline_user_args():
		for pressed in [true,false]:
			var event := InputEventScreenTouch.new()
			event.index=0
			event.position=point
			event.pressed=pressed
			Input.parse_input_event(event)
			await frames(2)
	else:
		for pressed in [true,false]:
			var event := InputEventMouseButton.new()
			event.position=point
			event.global_position=point
			event.button_index=MOUSE_BUTTON_LEFT
			event.pressed=pressed
			Input.parse_input_event(event)
			await frames(2)

func enter(character: String) -> void:
	if is_instance_valid(game):
		get_tree().paused=false
		game.queue_free()
		await frames(4)
	GameManager.selected_character_id=character
	GameManager.selected_survival_map=1
	game=preload("res://scenes/game.tscn").instantiate()
	game.tree_entered.connect(func():get_tree().current_scene=game)
	get_tree().root.add_child(game)
	await frames(2)
	while not (game.get_node("MapRunController") as MapRunController)._active: await frames(1)
	game.get_node("WaveSpawner").set_process(false)
	game.get_node("MapRunController").set_process(false)
	actor=game.get_node("Player")
	actor.weapon_manager.set_process(false)
	actor.health_component.invincible=true

func enemy(point: Vector2) -> EnemyBasic:
	var e := preload("res://entities/enemies/enemy_basic.tscn").instantiate() as EnemyBasic
	e.enemy_data=DataLoader.enemies.slime
	e.room_hp_multiplier=200
	e.room_move_speed_multiplier=0
	e.position=point
	GameManager.get_runtime_world(actor).add_child(e)
	return e

func _run() -> void:
	check(AudioServer.get_driver_name()=="Dummy" and AudioServer.is_bus_mute(0),"Checks must be silent")
	for character in ["soldier","swordsman","armored_axeman","knight","archer","wizard"]:
		await enter(character)
		var wave := game.get_node("WaveSpawner") as WaveSpawner
		for index in 12: wave._spawn_enemy()
		for e in get_tree().get_nodes_in_group("enemies"):
			check(e.movement_component.base_speed <= actor.movement_component.base_speed*0.75+0.01,"Fast walking pursuer: "+character)
			e.queue_free()
		await frames(3)
		check(actor.experience_component.exp_to_next_level==9,"Initial XP gate is still slow")
		var ui := game.get_node("LevelUpSelect") as LevelUpSelect
		var pool := ui._get_compatible_upgrades()
		for upgrade in pool:
			check(upgrade.category=="survival" or upgrade.class_character_id==character,"Legacy numeric/status-only card in new pool")
		check(pool.size()>=7,"Not enough meaningful choices: "+character)
		actor.experience_component.add_exp(9)
		await frames(3)
		check(ui.visible and get_tree().paused and actor.experience_component.level==2,"Real XP does not open choice UI")
		var choices: Array[UpgradeData]=[DataLoader.upgrades.survival_area,DataLoader.upgrades.survival_echo,DataLoader.upgrades.survival_chain]
		ui._show_choices(choices)
		await frames(2)
		var size:=get_viewport().get_visible_rect().size
		for card: Control in ui.grid_container.get_children():
			var rect:=card.get_global_rect()
			check(rect.position.x>=0 and rect.end.x<=size.x and rect.position.y>=0 and rect.end.y<=size.y,"Choice card outside screen")
			var preview:=card.get_node("MarginContainer/VBoxContainer/UpgradePreview") as Control
			check(preview.size.y>=100,"Animated comparison is too small")
			var column := card.get_node("MarginContainer/VBoxContainer") as VBoxContainer
			check(column.get_global_rect().end.y <= rect.end.y,"Card text overflows its frame")
		check(ui.confirm_button.get_global_rect().end.y<=size.y,"Confirm button outside screen")
		var time:=GameManager.elapsed_seconds
		await click_control(ui.grid_container.get_child(0) as Button)
		await frames(4)
		check(ui.visible and actor.upgrades_component.get_survival_rank("survival_area")==0,"Tap applied without confirmation")
		check(is_equal_approx(time,GameManager.elapsed_seconds),"Selection consumes survival time")
		if character=="soldier":
			await capture("choices")
			for i in 16:
				await frames(5)
				await capture("preview_%02d"%i)
		await click_control(ui.confirm_button)
		await frames(2)
		check(not ui.visible and actor.upgrades_component.get_survival_rank("survival_area")==1,"Confirmed choice not applied once")
		check(is_equal_approx(actor.weapon_manager.get_attack_range_multiplier(),1.18),"Area range is only decorative")
		for i in 4: actor.upgrades_component.apply_upgrade(DataLoader.upgrades.survival_area)
		check(actor.upgrades_component.get_survival_rank("survival_area")==3 and is_equal_approx(actor.weapon_manager.get_attack_range_multiplier(),1.54),"Area cap not enforced")
		check(DataLoader.upgrades.survival_area not in ui._get_compatible_upgrades(),"Maxed upgrade still offered")
		actor.upgrades_component.apply_upgrade(DataLoader.upgrades.survival_haste)
		check(is_equal_approx(actor.weapon_manager.get_attack_interval_multiplier(),0.9),"Haste doesn't speed actual attacks")
		actor.upgrades_component.apply_upgrade(DataLoader.upgrades.survival_echo)
		for i in 3: actor.upgrades_component.apply_upgrade(DataLoader.upgrades.survival_chain)
		actor.upgrades_component.apply_upgrade(DataLoader.upgrades.survival_power)
		var targets: Array[EnemyBasic]=[]
		for point in [Vector2(45,0),Vector2(66,0),Vector2(80,16),Vector2(98,0)]: targets.append(enemy(point))
		await frames(2)
		var effects:=actor.get_node("SurvivalUpgradeEffects")
		var baseline:=targets[0].health_component.current_hp
		targets[0].health_component.apply_damage(50,CombatEventMeta.create_direct("player_upgrade_test"))
		await frames(14)
		check(effects.debug_echo_hits==1 and effects.debug_chain_hits==3,"Follow-up/chain didn't deal bounded damage: "+character)
		check(targets[0].health_component.current_hp<baseline-50,"Echo has no real damage")
		if character=="soldier": await capture("effects")
		var triggered: int = effects.debug_echo_hits+effects.debug_chain_hits
		targets[0].health_component.apply_secondary_damage(1,CombatEventMeta.create_secondary("element_dot",[],false))
		await frames(50)
		check(effects.debug_echo_hits+effects.debug_chain_hits==triggered,"Secondary hit recursively retriggers upgrades")
		actor.upgrades_component.apply_upgrade(DataLoader.upgrades.survival_guard)
		await frames(2)
		check(actor.health_component.shield_amount==8,"Guard isn't a real shield")
		actor.health_component.invincible=false
		actor.health_component._iframe_remaining=0
		var hp:=actor.health_component.current_hp
		actor.health_component.apply_damage(9)
		var incoming := 9 * actor.health_component.damage_taken_multiplier * actor.health_component.active_skill_damage_multiplier
		check(is_equal_approx(actor.health_component.current_hp,hp-maxf(incoming-8,0)) and is_equal_approx(actor.health_component.shield_amount,maxf(8-incoming,0)),"Shield visual disagrees with absorption")
		actor.health_component.invincible=true
		await frames(490)
		check(actor.health_component.shield_amount==8,"Shield failed to recharge in game time")
		if character in ["archer","wizard"]:
			actor.upgrades_component.apply_upgrade(DataLoader.upgrades.survival_multishot)
			actor.upgrades_component.apply_upgrade(DataLoader.upgrades.survival_multishot)
			var before:=get_tree().get_nodes_in_group("projectiles").size()
			actor.weapon_manager._class_attack.execute(actor,DataLoader.characters[character],actor.weapon_manager)
			var count:=get_tree().get_nodes_in_group("projectiles").size()-before
			var base:=int(DataLoader.characters[character].attack_pattern_params.get("projectile_count",1))
			check(count==base+2,"Extra shots not reflected in actual class volley: "+character)
			actor.upgrades_component.apply_upgrade(DataLoader.upgrades.survival_pierce)
			actor.upgrades_component.apply_upgrade(DataLoader.upgrades.survival_pierce)
			actor.weapon_manager._class_attack.execute(actor,DataLoader.characters[character],actor.weapon_manager)
			check((get_tree().get_nodes_in_group("projectiles").back() as Projectile).pierce_remaining==3,"Pierce is missing on actual projectiles")
			for bolt in get_tree().get_nodes_in_group("projectiles"): bolt.queue_free()
			actor.upgrades_component.survival_upgrade_counts["survival_chain"]=0
			actor.upgrades_component.survival_upgrade_counts["survival_echo"]=0
			var gear := game.get_node("EquipmentDropSystem").debug_generate_equipment("traveler_shortbow" if character=="archer" else "star_sorcerer_staff","uncommon") as EquipmentData
			check(actor.equipment_component.add_item(gear) and actor.equipment_component.equip(gear),"Ranged inventory gear failed")
			await frames(4)
			var origin := actor.floating_weapons.get_muzzle("equipment")
			for index in targets.size(): targets[index].global_position=origin+Vector2(55+index*25,0)
			await frames(2)
			var hits: Dictionary={}
			var listener := func(target: Node,_amount: float,_crit: bool,meta: Dictionary):
				if bool(meta.get("is_direct",false)) and target in targets: hits[target.get_instance_id()]=true
			EventBus.enemy_damage_confirmed.connect(listener)
			var before_gear := get_tree().get_nodes_in_group("projectiles").size()
			actor.weapon_manager.equipment_attack.tick(0.01,actor,actor.weapon_manager)
			for tick in 12:
				actor.weapon_manager.equipment_attack.tick(1.0/60,actor,actor.weapon_manager)
				await frames(1)
			check(get_tree().get_nodes_in_group("projectiles").size()-before_gear==3,"Inventory ranged weapon missed guaranteed extra shots")
			await frames(6)
			await capture("ranged_equipment_"+character)
			await frames(40)
			check(hits.size()>=3,"Equipped projectile failed to physically pierce the enemy row")
			EventBus.enemy_damage_confirmed.disconnect(listener)
		var old_level := actor.experience_component.level
		var choices_taken: Dictionary={"count":0}
		var count_choice := func(_id: String): choices_taken.count+=1
		ui.option_selected.connect(count_choice)
		actor.experience_component.add_exp(120)
		var levels_added := actor.experience_component.level-old_level
		_auto_choose=true
		await frames(120)
		_auto_choose=false
		check(choices_taken.count==levels_added and not ui.visible and GameManager.active_modal_count==0,"Queued levels lose choices or leave pause behind")
		ui.option_selected.disconnect(count_choice)
		report[character]={"choice_confirmation":true,"visible_effect_damage":true,"slower_pursuers":true,"caps":true}
	var f:=FileAccess.open(OUT+"/check.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"failures":failures,"classes":report,"silent":true,"ephemeral_save":true},"\t"));f.close()
	var cleanup:=preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	cleanup.begin(0 if failures.is_empty() else 1,"SURVIVAL_GROWTH "+("PASS" if failures.is_empty() else "FAIL"))
