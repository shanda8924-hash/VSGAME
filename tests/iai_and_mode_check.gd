extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")
const TITLE_SCENE := preload("res://scenes/title.tscn")
const HOME_SCENE := preload("res://ui/home/home.tscn")
const OUTPUT_DIR := "res://artifacts/targeted_regression"

var failures: Array[String] = []
var iai_trail_events := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_check(OS.is_debug_build(), "test runtime is a debug build")
	_check_revoked_mark_feature_is_absent()
	_check_save_isolation()
	await _check_real_iai_hit_path()
	await _check_title_mode_selection()
	for failure in failures:
		push_error(failure)
	print("IAI_AND_MODE_CHECK failures=%d iai_trails=%d" % [failures.size(), iai_trail_events])
	AudioManager.stop_all()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_revoked_mark_feature_is_absent() -> void:
	_check(not FileAccess.file_exists("res://effects/iai_slash_mark_effect.gd"), "revoked enemy slash-mark effect script is absent")
	_check(not FileAccess.file_exists("res://resources/iai_slash_mark_style.gd"), "revoked attribute slash-mark style is absent")
	_check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://effects/iai_slash_marks")), "revoked slash-mark resource directory is absent")

func _check_save_isolation() -> void:
	var before := SaveManager.data.duplicate(true)
	SaveManager.begin_ephemeral_session()
	SaveManager.add_meta_currency(777)
	_check(SaveManager.is_ephemeral_session_active(), "ephemeral Test Mode save session activates")
	_check(SaveManager.data != before, "Test Mode can mutate its temporary in-memory state")
	SaveManager.end_ephemeral_session()
	_check(SaveManager.data == before, "ending Test Mode restores the exact pre-test save state")

func _check_real_iai_hit_path() -> void:
	GameManager.selected_character_id = "swordsman"
	var game := GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().physics_frame
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager"]:
		var automatic := game.get_node_or_null(node_name)
		if automatic:
			automatic.process_mode = Node.PROCESS_MODE_DISABLED
	for existing in get_tree().get_nodes_in_group("enemies"):
		existing.queue_free()
	await get_tree().process_frame
	var player := game.get_node("Player") as Player
	player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	var attack_vfx := game.get_node("AttackVFXManager") as AttackVFXManager
	attack_vfx.element_effect_spawned.connect(_on_element_effect_spawned)
	GameManager.debug_force_element_state({"element_fire": 1})
	var enemy_a := _spawn_enemy(game, player.global_position + Vector2(48, 0), "iai_no_mark_a")
	var enemy_b := _spawn_enemy(game, player.global_position + Vector2(88, 8), "iai_no_mark_b")
	var hp_a := enemy_a.health_component.current_hp
	var hp_b := enemy_b.health_component.current_hp
	var segment_start := player.global_position
	var segment_end := player.global_position + Vector2(120, 0)
	var hit_enemies: Dictionary = {}
	player.active_skill_component._damage_iai_segment(segment_start, segment_end, 22.0, 10.0, hit_enemies)
	var trail := attack_vfx.play_iai_trail(segment_start, segment_end)
	await get_tree().process_frame
	_check(hit_enemies.size() == 2, "one IAI segment damages both enemies once")
	_check(enemy_a.health_component.current_hp < hp_a and enemy_b.health_component.current_hp < hp_b, "IAI damage remains active after mark removal")
	_check(trail != null and iai_trail_events == 1, "attribute IAI space-slash effect remains connected")
	_check(get_tree().get_nodes_in_group("iai_slash_marks").is_empty(), "IAI creates no enemy-following horizontal mark")
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(0.12, true, false, true).timeout
		await _capture("%s/iai_space_slash_active.png" % OUTPUT_DIR)
	await get_tree().create_timer(0.9, true, false, true).timeout
	_check(get_tree().get_nodes_in_group("iai_slash_marks").is_empty(), "no horizontal line remains after the IAI effect ends")
	if DisplayServer.get_name() != "headless":
		await _capture("%s/iai_after_effect_no_enemy_mark.png" % OUTPUT_DIR)
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.debug_force_element_state({})

func _check_title_mode_selection() -> void:
	var home := HOME_SCENE.instantiate() as HomeScreen
	get_tree().root.add_child(home)
	await get_tree().process_frame
	await get_tree().process_frame
	var first_character := home.character_grid.get_child(0) as Button if home.character_grid.get_child_count() > 0 else null
	_check(first_character != null and get_viewport().gui_get_focus_owner() == first_character, "character selection receives initial keyboard focus")
	home.queue_free()
	await get_tree().process_frame
	var title := TITLE_SCENE.instantiate() as TitleScreen
	get_tree().root.add_child(title)
	get_tree().current_scene = title
	await get_tree().process_frame
	var start := title.get_node("CenterContainer/VBoxContainer/StartButton") as Button
	var mode_select := title.get_node("CenterContainer/VBoxContainer/ModeSelect") as VBoxContainer
	var test_button := title.get_node("CenterContainer/VBoxContainer/ModeSelect/TestButton") as Button
	_check(start.text == "ゲームスタート", "title exposes the Japanese game start action")
	_check(not mode_select.visible, "mode selection stays hidden before game start")
	_check(get_viewport().gui_get_focus_owner() == start, "game start receives initial keyboard focus")
	start.pressed.emit()
	await get_tree().process_frame
	var normal_button := title.get_node("CenterContainer/VBoxContainer/ModeSelect/NormalButton") as Button
	_check(mode_select.visible and not start.visible, "game start opens Normal Game / Test Mode selection")
	_check(get_viewport().gui_get_focus_owner() == normal_button, "Normal Game receives keyboard focus after opening mode selection")
	_check(not test_button.disabled and test_button.text.begins_with("テストモード"), "debug build exposes the player-selectable Test Mode")
	test_button.pressed.emit()
	var lab: DeveloperTestLab
	for _frame in 180:
		await get_tree().process_frame
		lab = get_tree().current_scene as DeveloperTestLab
		if lab and lab.player:
			break
	_check(lab != null and lab.player != null, "pressing Test Mode enters the real Developer Test Lab")
	if lab:
		var return_button := _find_button_by_text(lab, "RETURN TITLE")
		_check(return_button != null and return_button.focus_mode != Control.FOCUS_NONE, "RETURN TITLE is keyboard-focusable")
		lab.return_to_title()
	var returned_title: TitleScreen
	for _frame in 120:
		await get_tree().process_frame
		returned_title = get_tree().current_scene as TitleScreen
		if returned_title:
			break
	_check(returned_title != null, "RETURN TITLE leaves Test Mode and restores the title scene")
	get_tree().current_scene = self
	if returned_title:
		returned_title.queue_free()
	await get_tree().process_frame

func _spawn_enemy(game: Node, position: Vector2, enemy_id: String) -> EnemyBasic:
	var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
	var data := EnemyData.new()
	data.id = enemy_id
	data.display_name = enemy_id
	data.max_hp = 1000.0
	data.move_speed = 0.0
	data.contact_damage = 0.0
	data.attack_range = 0.0
	data.attack_interval = 99.0
	data.attack_windup = 99.0
	data.sprite_folder = "enemies/Orc"
	enemy.enemy_data = data
	game.add_child(enemy)
	enemy.global_position = position
	return enemy

func _on_element_effect_spawned(effect_id: String, _effect: AnimatedSprite2D) -> void:
	if effect_id.contains("iai_") and effect_id.contains("trail"):
		iai_trail_events += 1

func _find_button_by_text(root: Node, text_value: String) -> Button:
	if root is Button and (root as Button).text == text_value:
		return root as Button
	for child in root.get_children():
		var found := _find_button_by_text(child, text_value)
		if found:
			return found
	return null

func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	_check(error == OK, "%s screenshot saves" % path)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
