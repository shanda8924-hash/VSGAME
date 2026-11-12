extends Node
## Render/attack integration only. Uses DeveloperTestLab's actual embedded game.tscn.
## Fixed fixture + sprite frame holds are test-only; no production scripts or data are patched.
const LAB_SCENE := preload("res://scenes/developer_test_lab.tscn")
const OUTPUT_DIR := "res://artifacts/pixel_world"
var failures: Array[String] = []
var lab: DeveloperTestLab
var game: Node2D
var fixture_map: DungeonMap
var _own_save_session := false
var _stage := "boot"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.begin_ephemeral_session()
	_own_save_session = true
	get_tree().create_timer(40.0, true, false, true).timeout.connect(_watchdog)
	_run.call_deferred()

func _exit_tree() -> void:
	if _own_save_session:
		SaveManager.end_ephemeral_session()
		_own_save_session = false

func _watchdog() -> void:
	push_error("PIXEL_WORLD_CHECK timeout: " + _stage)
	get_tree().quit(1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("PIXEL_WORLD_CHECK: " + message)

func _frames(count: int) -> void:
	for _frame in count:
		await get_tree().process_frame

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	lab = LAB_SCENE.instantiate() as DeveloperTestLab
	add_child(lab)
	await lab.lab_ready
	game = lab.runtime_game
	_check(game != null and game.scene_file_path == "res://scenes/game.tscn", "Lab loads real production game.tscn")
	_check(SaveManager.is_ephemeral_session_active(), "All fixture actions are save-isolated")
	await _prepare_world()
	await _capture("walls")
	await _capture_lab("lab_overview")
	await _check_real_projectile()
	await _check_space()
	await _check_completed_skill()
	await _check_theme_and_drop()
	_check(SaveManager.is_ephemeral_session_active(), "Save protection survives all gameplay callbacks")
	_check(lab.player.health_component.current_hp > 0.0, "Player remains alive")
	_check(not game.get_node("ResultScreen").visible, "Result screen never replaces world")
	print("PIXEL_WORLD_CHECK failures=%d frames=1,2,4 native_zoom=1.5 fixture=two_wall_islands" % failures.size())
	lab.queue_free()
	await _frames(2)
	get_tree().quit(0 if failures.is_empty() else 1)

func _prepare_world() -> void:
	_stage = "wall fixture"
	for node_name in ["WaveSpawner", "EliteRoomManager", "BossSpawner", "MapRunController", "ComboSystem"]:
		var controller := game.get_node_or_null(node_name)
		if controller:
			controller.process_mode = Node.PROCESS_MODE_DISABLED
	lab.player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED
	lab.player.health_component.invincible = true
	lab.player.set_movement_locked(true)
	lab._clear_enemies(false, true)
	await _frames(2)
	fixture_map = DungeonMap.new(48, 36)
	for y in range(-14, 14):
		for x in range(-20, 20):
			fixture_map.set_floor(Vector2i(x, y), true)
	# A room with two stone islands: all three improved floor-facing edges and
	# the approved south/front face are visible together at normal camera scale.
	for island: Rect2i in [Rect2i(-8, -5, 6, 4), Rect2i(3, -5, 7, 4)]:
		for y in range(island.position.y, island.end.y):
			for x in range(island.position.x, island.end.x):
				fixture_map.set_floor(Vector2i(x, y), false)
	fixture_map.rooms.append(Rect2i(-20, -14, 40, 28))
	fixture_map.spawn_point = Vector2i(-2, 3)
	GameManager.dungeon_map = fixture_map
	seed(90205)
	var environment := game.get_node("StageEnvironment") as StageEnvironment
	await environment.build_dungeon_async(fixture_map, 5)
	_check((environment._wall_neighbor_mask(fixture_map, Vector2i(-6, -5)) & 1) != 0, "back/top edge faces floor")
	_check((environment._wall_neighbor_mask(fixture_map, Vector2i(-8, -4)) & 8) != 0, "left edge faces floor")
	_check((environment._wall_neighbor_mask(fixture_map, Vector2i(-3, -4)) & 2) != 0, "right edge faces floor")
	_check((environment._wall_neighbor_mask(fixture_map, Vector2i(-6, -2)) & 4) != 0, "south/front uses same wall material")
	lab.player.global_position = fixture_map.grid_to_world(fixture_map.spawn_point)
	lab.player.camera.enabled = false
	var camera := Camera2D.new()
	camera.name = "PixelWorldFixtureCamera"
	camera.zoom = lab.player.camera.zoom
	camera.position = Vector2(0, 40)
	game.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	_check(camera.zoom == Vector2(1.5, 1.5), "fixture keeps native in-game zoom")
	lab.dummy.global_position = Vector2(112, 120)
	lab.dummy.set_movement_locked(true)
	if lab._dummy_hp_label:
		lab._dummy_hp_label.visible = false
	# Keep the Lab controls visible in full captures; field-only captures inspect
	# tile/sprite density without a HUD plate hiding either island.
	(game.get_node("HUD") as CanvasLayer).visible = false
	await _frames(4)

func _check_real_projectile() -> void:
	_stage = "real weapon manager damage"
	lab.reset_damage_meter()
	lab._clear_dummy_status()
	var projectile := lab.trigger_projectile()
	_check(projectile != null, "Lab TRIGGER PROJECTILE spawns through WeaponManager")
	var expected_damage := projectile.damage if projectile else -1.0
	var deadline := Time.get_ticks_msec() + 3000
	while lab._damage_hits == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	_check(lab._damage_hits == 1 and lab._damage_total > 0.0, "One real projectile produces one confirmed hit")
	_check(is_equal_approx(lab._damage_total, expected_damage), "Real hurtbox damage matches unmodified projectile damage")
	print("PIXEL_WORLD_DAMAGE projectile=%.2f actual=%.2f hits=%d" % [expected_damage, lab._damage_total, lab._damage_hits])
	await get_tree().create_timer(0.65).timeout

func _check_space() -> void:
	_stage = "Space entry + chain art"
	# Isolated Lab preset: select an existing class definition, never mutate JSON
	# or resource values. Character appearance stays the Lab's swordsman.
	var active := lab.player.active_skill_component
	active.character_data = DataLoader.characters.get("knight_templar") as CharacterData
	active.cooldown_remaining = 0.0
	var old_total := lab._damage_total
	_check(active.try_activate(), "Real Space ActiveSkillComponent entry activates")
	_check(_has_pixel("active_chains"), "Space entry creates generated chain animation")
	await _capture_sequence("space", "active_chains")
	await get_tree().create_timer(0.85).timeout
	_check(lab._damage_total > old_total, "Space delayed Holy Chains still deals actual damage")
	print("PIXEL_WORLD_DAMAGE space_delta=%.2f" % (lab._damage_total - old_total))
	lab.player.health_component.invincible = true
	lab.dummy.global_position = Vector2(112, 120)
	await get_tree().create_timer(0.45).timeout

func _check_completed_skill() -> void:
	_stage = "Lab completed skill trigger now"
	lab.concept_system.set_active(true)
	for index in lab._completed_skill_select.item_count:
		if String(lab._completed_skill_select.get_item_metadata(index)) == "thunderlord_descent":
			lab._completed_skill_select.select(index)
			break
	lab._completed_skill_grant_selected()
	lab._completed_skill_ready_selected()
	var old_total := lab._damage_total
	# Exactly the same bound callback as the Lab's TRIGGER NOW button.
	lab._completed_skill_trigger_selected()
	_check(_has_pixel("signature_thunderlord_descent"), "TRIGGER NOW produces generated signature sprite")
	_check(lab._damage_total > old_total, "TRIGGER NOW keeps actual completed-skill damage")
	await _capture_sequence("signature", "signature_thunderlord_descent")
	print("PIXEL_WORLD_DAMAGE signature_delta=%.2f" % (lab._damage_total - old_total))
	await get_tree().create_timer(0.7).timeout
	lab.concept_system.set_active(false)

func _check_theme_and_drop() -> void:
	_stage = "world theme + equipment drop"
	var manager := game.get_node("EffectThemeManager") as EffectThemeManager
	var hurtbox := lab.dummy.get_node("HurtboxComponent") as HurtboxComponent
	manager.play_weapon_hit("fire", lab.dummy.global_position, 3, hurtbox, lab.player.global_position)
	var item: EquipmentData
	for template: Dictionary in lab.equipment_drop.debug_get_templates():
		if String(template.get("rarity", "")) == "legendary" and String(template.get("slot", "")) == "weapon":
			item = lab.equipment_drop.debug_generate_equipment(String(template.get("id", "")), "legendary")
			break
	_check(item != null, "Real equipment catalog supplies drop fixture")
	var ground: GroundEquipmentItem
	if item:
		ground = lab.equipment_drop.debug_drop_equipment(item, Vector2(-144, 172))
	_check(ground != null and ground.get_parent() == game, "Real drop system attaches item to game world")
	_check(_has_pixel("hit_fire"), "Weapon theme hit renders near actual enemy")
	_check(_has_pixel("loot_awaken"), "Real drop activates generated awakening sprite")
	await _capture_sequence("hit_drop", "hit_fire")
	await get_tree().create_timer(0.9).timeout
	_check(not _has_pixel("hit_fire"), "Hit sprite releases after capture and lifetime")
	await _capture("world_after_effects")

func _pixels(parent: Node, result: Array[PixelSpriteVFX]) -> void:
	for child in parent.get_children():
		if child is PixelSpriteVFX:
			result.append(child as PixelSpriteVFX)
		_pixels(child, result)

func _has_pixel(id: String) -> bool:
	var sprites: Array[PixelSpriteVFX] = []
	_pixels(game, sprites)
	for sprite in sprites:
		if sprite.active and String(sprite.get_meta("pixel_vfx_id", "")) == id:
			return true
	return false

func _capture_sequence(prefix: String, expected_id: String) -> void:
	var sprites: Array[PixelSpriteVFX] = []
	_pixels(game, sprites)
	var held: Array[PixelSpriteVFX] = []
	for sprite in sprites:
		if sprite.active:
			sprite.set_process(false)
			held.append(sprite)
	_check(_has_pixel(expected_id), prefix + ": expected animation exists")
	for index in [1, 2, 4]:
		for sprite in held:
			if is_instance_valid(sprite):
				sprite.frame = index
		await _capture("%s_frame%d" % [prefix, index])
	for sprite in held:
		if is_instance_valid(sprite):
			sprite.set_process(true)

func _capture(suffix: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _frames(2)
	await RenderingServer.frame_post_draw
	var image := lab._subviewport.get_texture().get_image()
	_check(image != null and not image.is_empty(), suffix + ": Vulkan viewport image exists")
	if image:
		_check(image.save_png(OUTPUT_DIR + "/" + suffix + ".png") == OK, suffix + ": PNG saved")
	print("PIXEL_WORLD_CAPTURE ", suffix)

func _capture_lab(suffix: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(OUTPUT_DIR + "/" + suffix + ".png") == OK, suffix + ": Lab GUI saved")
