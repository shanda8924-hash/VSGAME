extends Node
## Actual game presentation/interaction check. Dummy audio + --mute-audio required.
var OUTPUT := "res://artifacts/ember_visual_v5"
var failures: Array[String] = []
var shots: Array[String] = []
var game: Node2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	if "--touch-preview" in OS.get_cmdline_user_args(): OUTPUT += "/mobile"
	get_tree().create_timer(150,true).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _frames(count: int) -> void:
	for _i in count: await get_tree().process_frame

func _capture(id: String) -> void:
	await _frames(4)
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT+"/"+id+".png")
	shots.append(id)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	_check(AudioServer.is_bus_mute(0) and AudioServer.get_driver_name() == "Dummy", "Tests must have muted Dummy audio")
	var title := preload("res://scenes/title.tscn").instantiate()
	add_child(title)
	await _capture("title")
	remove_child(title)
	title.queue_free()
	var home := preload("res://ui/home/home.tscn").instantiate()
	add_child(home)
	await _capture("characters")
	remove_child(home)
	home.queue_free()
	GameManager.selected_character_id = "swordsman"
	game = preload("res://scenes/game.tscn").instantiate()
	game.tree_entered.connect(func(): get_tree().current_scene = game)
	get_tree().root.add_child(game)
	var controller := game.get_node("MapRunController") as MapRunController
	while not controller._active: await _frames(1)
	controller.set_process(false)
	var wave := game.get_node("WaveSpawner") as WaveSpawner
	wave._sector_active = false
	wave.set_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"): enemy.queue_free()
	var player := game.get_node("Player") as Player
	player.health_component.invincible = true
	player.weapon_manager.cancel_current_attack()
	player.weapon_manager.set_process(false)
	var stage := game.get_node("StageEnvironment") as StageEnvironment
	var surface := stage.get_node_or_null("PaintedSurfaces")
	_check(surface != null and surface.theme == 1,"MAP1 real isolated-room path is missing new surfaces")
	var cells_before: Array[Vector2i] = GameManager.dungeon_map.get_floor_cells().duplicate()
	stage._refresh_painted_surfaces(GameManager.dungeon_map)
	_check(cells_before == GameManager.dungeon_map.get_floor_cells(),"Visual refresh changed collision floor cells")
	# Remove this extra presentation probe, keeping the original real map renderer.
	stage.get_children()[-1].queue_free()
	var drops := game.get_node("EquipmentDropSystem") as EquipmentDropSystem
	var count := 0
	for template in drops.debug_get_templates():
		var item := drops.debug_generate_equipment(template.id,template.rarity)
		if not "--preview" in OS.get_cmdline_user_args():
			_check(item.icon_path.begins_with("res://assets/visuals/ember_v5/equipment/"),"Old art remains active: "+template.id)
		if count < 50:
			player.equipment_component.add_item(item)
			if not player.equipment_component.get_equipped(item.slot):player.equipment_component.equip(item)
		count += 1
	_check(count == 200,"Equipment catalog must remain 200 distinct items")
	await _capture("hud_map1")
	var bag := game.get_node("EquipmentScreen") as EquipmentScreen
	bag._open()
	await _capture("inventory")
	var source := bag.inventory_list.get_child(0) as Button
	var item: EquipmentData = source.get_meta("inventory_item")
	bag._show_item_hover(item,source,true)
	await _capture("inventory_detail")
	var double := InputEventMouseButton.new()
	double.button_index = MOUSE_BUTTON_LEFT
	double.pressed = true
	double.double_click = true
	if player.equipment_component.is_equipped(item): player.equipment_component.unequip(item.slot)
	bag._on_equipment_double_click(double,item,"")
	await _frames(2)
	_check(player.equipment_component.get_equipped(item.slot) == item,"Double click equip broke during visual update")
	bag._on_equipment_double_click(double,item,item.slot)
	await _frames(2)
	_check(player.equipment_component.get_equipped(item.slot) == null,"Double click unequip broke during visual update")
	bag._set_right_mode("forge")
	await _capture("forge")
	var layout := []
	for node in bag.forge_panel.find_children("*", "Control", true, false):
		if node.is_visible_in_tree(): layout.append({"name":node.name,"rect":str(node.get_global_rect()),"minimum":str(node.get_combined_minimum_size())})
	FileAccess.open(OUTPUT+"/forge_layout.json",FileAccess.WRITE).store_string(JSON.stringify(layout,"  "))
	_check(get_viewport().get_visible_rect().encloses(bag.forge_panel.get_global_rect()),"Forge popup exceeds the viewport")
	_check(bag.forge_panel.get_global_rect().encloses(bag.merge_button.get_global_rect()),"Forge action is outside the crafting panel")
	# Two real crafting rituals must retain the new scrolling forge and its modal.
	var component := player.equipment_component
	component.clear_all()
	var merge_id := ""
	for template in drops.debug_get_templates():
		if template.rarity == "uncommon":
			merge_id = template.id
			break
	for _attempt in 2:
		var materials: Array[EquipmentData] = []
		for _i in EquipmentMergeSystem.required_count("uncommon"):
			var material := drops.debug_generate_equipment(merge_id,"uncommon")
			component.add_item(material)
			materials.append(material)
		bag._merge_result = null
		bag._merge_materials.assign(materials)
		bag._refresh()
		var old_rate: float = bag._merge_system._drop_table.merge_rules.uncommon.success_rate
		bag._merge_system._drop_table.merge_rules.uncommon.success_rate = 1.0
		bag._merge_selected()
		bag._merge_system._drop_table.merge_rules.uncommon.success_rate = old_rate
		await _frames(105)
		_check(bag._merge_result != null and not bag._merge_in_progress,"Crafting animation failed to finish")
		_check(bag._is_open and bag.forge_view.visible and bag._forge_scroll.visible,"Crafting closed the forge")
		_check(GameManager.active_modal_count == 1 and get_tree().paused,"Crafting lost its pause modal")
		_check(component.inventory.has(bag._merge_result),"Crafting lost the resulting equipment")
	await _capture("forge_after_two_merges")
	bag._close()
	var menu := game.get_node("PauseMenu") as PauseMenu
	menu._active_tab = "talent"
	menu._open()
	_check(menu.talent_book.opening and menu.talent_book.canvas.get_parent() == menu.talent_book._ink_viewport,"Opening ink must render on the turning paper")
	_check(GameManager.active_modal_count == 1 and get_tree().paused,"Book entrance must pause combat exactly once")
	for i in 29:
		await _capture("book_%02d" % i)
		_check(menu.talent_book.canvas.get_parent() == menu.talent_book._ink_viewport or menu.talent_book._intro.phase >= menu.talent_book.BookArt.DURATION,"Interactive controls returned before pages settled")
	_check(not menu.talent_book.opening and menu.talent_book.canvas.visible,"Book entrance did not finish")
	_check(menu.talent_book._intro.visible and is_equal_approx(menu.talent_book._intro.modulate.a,1.0),"Open book must remain beneath the two talent pages")
	menu.talent_book.nodes[1].grab_focus()
	await _capture("talents")
	menu._close()
	_check(GameManager.active_modal_count == 0 and not get_tree().paused,"Closing talents did not resume combat")
	menu._open()
	await _frames(10)
	menu._close()
	await _frames(80)
	_check(not menu._is_open and not menu.talent_book.opening and GameManager.active_modal_count == 0,"Closing during animation leaked a modal or reopened the book")
	menu._open()
	await _frames(115)
	_check(menu.talent_book.nodes.size()==9 and not menu.talent_book.opening,"Immediate reopen broke talent focus/tree")
	menu._close()
	var level := game.get_node("LevelUpSelect") as LevelUpSelect
	level._open()
	await _capture("level_up")
	level.hide()
	GameManager.close_modal()
	var shop := game.get_node("ShopScreen") as ShopScreen
	shop._open(1)
	await _capture("shop")
	shop._close()
	for theme in [2,3]:
		controller._transition_to_map(theme,1)
		while controller._transitioning: await _frames(1)
		wave._sector_active = false
		wave.set_process(false)
		for enemy in get_tree().get_nodes_in_group("enemies"):enemy.queue_free()
		await _capture("hud_map%d" % theme)
		_check(stage.get_node("PaintedSurfaces").theme == theme,"Theme surface missing from actual stage transition")
		var architecture := stage.get_node_or_null("ScenicLandmarks")
		if architecture and architecture.get_child_count() > 0:
			var landmark := architecture.get_child(0) as Sprite2D
			if landmark:
				player.global_position = landmark.global_position + Vector2(0,160)
				await _frames(20)
				await _capture("landmark_map%d" % theme)
	var report := {"failures":failures,"screenshots":shots,"catalog":count,"audioDriver":AudioServer.get_driver_name(),"muted":AudioServer.is_bus_mute(0),"bookAnimation":"persistent-two-page-book"}
	FileAccess.open(OUTPUT+"/check.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	var cleanup := preload("res://tests/runtime_exit_cleanup.gd").new()
	get_tree().root.add_child(cleanup)
	cleanup.begin(0 if failures.is_empty() else 1,"EMBER_VISUAL_POLISH failures=%d catalog=%d muted=true" % [failures.size(),count])
