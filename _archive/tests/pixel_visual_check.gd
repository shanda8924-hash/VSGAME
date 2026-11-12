extends Node
## 製品Sceneを通す見た目・入力回帰。通常起動へのフックは不要。
var game: Node
var failures: Array[String] = []
var capture_prefix := "readability_after"

func _ready() -> void:
	SaveManager.begin_ephemeral_session() # この検証プロセスから通常セーブへ書き込まない。
	process_mode = Node.PROCESS_MODE_ALWAYS
	if "--before" in OS.get_cmdline_user_args(): capture_prefix = "pixel_before"
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func capture(suffix: String) -> void:
	await frames(3)
	check_world_fixture(suffix)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/%s_%s.png" % [capture_prefix, suffix])

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func check_world_fixture(context: String, require_playing: bool = false) -> void:
	var player := game.get_node("Player") as Player
	check(player.health_component.current_hp > 0.0, context + ": fixture player died")
	check(not (game.get_node("ResultScreen") as CanvasLayer).visible, context + ": result screen obscures UI")
	check(GameManager.run_state != GameManager.RunState.RESULT, context + ": run reached result state")
	if require_playing:
		check(GameManager.run_state == GameManager.RunState.PLAYING, context + ": run must be PLAYING")

func check_cards(container: Control, label: String) -> void:
	for child in container.get_children():
		if not child is Button: continue
		var card := child as Button
		check(get_viewport().get_visible_rect().encloses(card.get_global_rect()), label + " card outside viewport")
		for text_node in card.find_children("*", "Label", true, false):
			check(card.get_global_rect().grow(1).encloses((text_node as Label).get_global_rect()), label + " text outside card: " + text_node.text)

func check_populated_hud() -> void:
	check_world_fixture("before populated HUD", true)
	var hud := game.get_node("HUD") as HUD
	# 表示のみのfixture。WeaponManager/Concept/Item効果やSaveには触れない。
	for row in [hud.weapon_row, hud.item_row, hud.completed_skill_row]:
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()
	hud._item_rows.clear()
	hud._completed_skill_labels.clear()
	hud._item_overflow_count = 0
	hud._item_overflow_label = null
	for index in range(4):
		var weapon := WeaponData.new()
		weapon.display_name = "古王国の忘れられた英雄の剣%d" % (index + 1)
		hud.weapon_row.add_child(hud._build_weapon_icon(WeaponInstance.new(weapon)))
	for index in range(7):
		hud._on_item_acquired("readability_item_%d" % index, "悠久の地下王国の守護の証%d" % (index + 1))
	hud._on_item_acquired("readability_item_0", "悠久の地下王国の守護の証1")
	for index in range(6):
		hud.set_completed_skill("readability_skill_%d" % index, "伝説のインフェルノピラー%d" % (index + 1), 12 + index)
	await get_tree().create_timer(3.1).timeout # 取得Popupが残った画像にしない。
	await frames(5)
	check_world_fixture("after populated HUD popups", true)
	var tray := hud.get_node("MarginContainer") as Control
	check(tray.size.x <= 276.1, "Populated HUD expanded beyond 276px")
	check(get_viewport().get_visible_rect().encloses(tray.get_global_rect()), "Populated HUD tray outside viewport")
	for row in [hud.weapon_row, hud.item_row, hud.completed_skill_row]:
		check(tray.get_global_rect().grow(1).encloses(row.get_global_rect()), "Populated HUD row outside tray")
		for child in row.get_children():
			var label := child as Label
			check(row.get_global_rect().grow(1).encloses(label.get_global_rect()), "HUD label outside flow: " + label.text)
			check(get_viewport().get_visible_rect().encloses(label.get_global_rect()), "HUD label outside viewport: " + label.text)
			check(label.get_theme_font("font") == RetroHUDStyle.retro_font(), "Dynamic HUD label missing readable font")
			check(label.get_theme_font_size("font_size") >= 18, "Dynamic HUD label font too small")
			check(label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x <= label.size.x + 1, "HUD abbreviated text is clipped: " + label.text)
			check(not label.tooltip_text.is_empty(), "HUD abbreviated label missing full tooltip")
	check(hud.item_row.get_child_count() == 7, "HUD item six + overflow badge missing")
	check((hud._item_rows["readability_item_0"]["label"] as Label).text.ends_with("×2"), "HUD count was abbreviated away")
	for index in range(6):
		check((hud._completed_skill_labels["readability_skill_%d" % index] as Label).text.ends_with("Lv.%d" % (12 + index)), "HUD skill level was abbreviated away")
	await capture("populated_hud")
	print("HUD_POPULATED_CHECK weapons=4 items=6 overflow=1 skills=6 width=", tray.size.x, " font=", RetroHUDStyle.retro_font().resource_path)

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	game = load("res://scenes/game.tscn").instantiate()
	game.tree_entered.connect(func(): get_tree().current_scene = game)
	get_tree().root.add_child(game)
	# 見た目検証だけの無敵。初期化待ちや遅延callback中の接触Damageも遮断する。
	(game.get_node("Player") as Player).health_component.invincible = true
	await frames(180)
	check_world_fixture("initial world", true)
	for node_name in ["WaveSpawner", "EliteRoomManager", "BossSpawner", "MapRunController"]:
		game.get_node(node_name).process_mode = Node.PROCESS_MODE_DISABLED
	game.get_node("Player").weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	for e in get_tree().get_nodes_in_group("enemies"): e.queue_free()
	await frames(3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90205
	var map := DungeonGenerator.generate(78, 78, 10, 1, rng)
	GameManager.dungeon_map = map
	await game.get_node("StageEnvironment").build_dungeon_async(map, 5)
	game.get_node("Player").global_position = map.grid_to_world(map.spawn_point)
	game.get_node("Player").setup_camera_limits(map)
	var camera := (game.get_node("Player") as Player).camera
	camera.reset_smoothing()
	camera.force_update_scroll()
	game.get_node("HUD").set_map_status(1, 3, "忘却の地下回廊", 180, 900, 244, 420, false)
	# Cameraが新位置を反映してから戦闘Worldを固定。UIの本物のALWAYS経路は維持。
	await frames(5)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.get_node("HUD").process_mode = Node.PROCESS_MODE_ALWAYS
	for e in get_tree().get_nodes_in_group("enemies"): e.queue_free()
	check_world_fixture("frozen visual world", true)
	await capture("map")
	var ui_font := RetroHUDStyle.retro_font() as FontFile
	check(ui_font != null and ui_font.antialiasing == TextServer.FONT_ANTIALIASING_GRAY, "UI font must use grayscale antialiasing")
	check(game.get_node("HUD").room_status_label.get_theme_font_size("normal_font_size") >= 20, "MAP text too small")
	# 静止同条件の描画回帰。実症状の再現や戦闘負荷帰属を目的としない。
	for window in 3:
		var times: Array[float] = []
		var begin := Time.get_ticks_usec()
		var last := begin
		while Time.get_ticks_usec() - begin < 3000000:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			times.append((now-last)/1000.0)
			last = now
		times.sort()
		var total := 0.0
		for t in times: total += t
		print("PIXEL_BENCH ", capture_prefix, " window=", window, " avg=",total/times.size()," p95=",times[int(times.size()*0.95)]," max=",times.back()," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," vram=",Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	var level = game.get_node("LevelUpSelect")
	level._on_leveled_up(2)
	await frames(5)
	await capture("level")
	check(RetroHUDStyle.retro_font() != null, "Readable Japanese UI font not imported")
	check_cards(level.grid_container, "LevelUp")
	check(level.grid_container.get_child_count() == 3, "LevelUp choices != 3")
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	Input.parse_input_event(event)
	await frames(1)
	event = InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = false
	Input.parse_input_event(event)
	await frames(4)
	check(level.visible, "First accept should only select a card")
	event = InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	Input.parse_input_event(event)
	await frames(1)
	event = InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = false
	Input.parse_input_event(event)
	await frames(4)
	check(not level.visible, "Confirmed keyboard selection did not close LevelUp")
	var shop = game.get_node("ShopScreen")
	GameManager.add_run_gold(750, "visual_check")
	shop.show_shop(1)
	await frames(5)
	await capture("shop")
	check_cards(shop.stock_grid, "Shop")
	check(shop.stock_grid.get_child_count() == 4, "Shop slots != 4")
	var button: Button = shop.stock_grid.get_child(0)
	button.grab_focus()
	var gold: int = GameManager.run_gold
	button.pressed.emit()
	await frames(5)
	check(GameManager.run_gold < gold, "Shop purchase did not spend gold")
	if capture_prefix != "pixel_before":
		check(shop.stock_grid.get_child(0).has_focus(), "Purchase lost slot focus")
	await capture("shop_after_purchase")
	shop.debug_close_shop()
	await frames(5)
	check(not get_tree().paused and GameManager.active_modal_count == 0,"Modal pause leak")
	await check_populated_hud()
	for f in failures: push_error(f)
	print("PIXEL_VISUAL_CHECK ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
