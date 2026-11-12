extends Node

const LAB_SCENE := preload("res://scenes/developer_test_lab.tscn")
const OUTPUT_DIR := "res://artifacts/developer_test_lab"

var failures: Array[String] = []
var captures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var lab = LAB_SCENE.instantiate()
	add_child(lab)
	await lab.lab_ready
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture("01_player_and_game_field.png")

	_check(lab.select_tab("VFX GALLERY"), "VFX Gallery tab can be selected")
	lab.preview_wind_blade_vfx()
	await get_tree().create_timer(0.08, true, false, true).timeout
	await _capture("05_concept_wind_blade.png")

	_check(lab.select_tab("CONCEPT"), "Concept tab can be selected")
	lab._completed_skill_grant_all()
	lab._completed_skill_spawn_cluster()
	lab.dummy.global_position = lab.player.global_position + Vector2(80, 0)
	lab.concept_system.set_active(false)
	for skill_id in ["thunderlord_descent", "inferno_pillar", "glacial_spear_rain", "radiant_blade_array", "void_severance"]:
		lab.concept_system.debug_trigger_completed_skill(skill_id, lab._ensure_concept_target())
		await get_tree().create_timer(0.14, true, false, true).timeout
		await _capture("06_large_%s.png" % skill_id)
		await get_tree().create_timer(0.48, true, false, true).timeout
	lab.concept_system.set_active(true)

	_check(lab.select_tab("FUSION"), "Fusion tab can be selected")
	_check(lab.create_fusion("plasma", false), "Plasma can be prepared for visual capture")
	lab.spawn_enemies(10, "Around Player", lab._selected_enemy_id())
	lab.trigger_fusion_vfx("plasma", "signature")
	await get_tree().create_timer(0.12, true, false, true).timeout
	await _capture("02_fusion_runtime.png")

	lab._clear_enemies(false, true)
	await get_tree().process_frame
	_check(lab.select_tab("EQUIPMENT / LOOT"), "Equipment and Loot tab can be selected")
	lab.loot_preset_clean()
	await get_tree().create_timer(0.1, true, false, true).timeout
	await _capture("03_loot_visibility.png")


	for failure in failures:
		push_error(failure)
	print("DEVELOPER_TEST_LAB_VISUAL_CHECK failures=%d screenshots=%d" % [failures.size(), captures.size()])
	lab.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	AudioManager.stop_all()
	get_tree().quit(0 if failures.is_empty() else 1)

func _capture(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		failures.append("visual check requires a rendering display")
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUTPUT_DIR, file_name]
	var error := image.save_png(ProjectSettings.globalize_path(path))
	_check(error == OK, "%s screenshot writes" % file_name)
	if error == OK:
		captures.append(path)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
