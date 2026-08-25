extends Node

const LAB_SCENE := preload("res://scenes/developer_test_lab.tscn")
const OUTPUT_DIR := "res://artifacts/fusion_pixel_vfx_gui"
const FUSIONS := ["frostfire", "plasma", "solar", "inferno", "superconductor", "aurora", "void_frost", "judgment", "voidstorm", "eclipse"]
const MODES := ["attack", "trail", "hit", "burst", "formation"]

var failures: Array[String] = []
var captures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var lab = LAB_SCENE.instantiate()
	add_child(lab)
	await lab.lab_ready
	lab.remove_dummy()
	await get_tree().process_frame
	_check(lab.select_tab("FUSION"), "Developer Test Lab Fusion tab is visible")
	for fusion_id in FUSIONS:
		await _capture_fusion_modes(lab, fusion_id)
	await _capture_all_intros(lab)
	await _capture_required_comparison(lab, "lightning", "plasma", "12_lightning_plasma_lightning.png")
	await _capture_required_comparison(lab, "fire", "plasma", "13_fire_plasma_fire.png")
	await _capture_required_comparison(lab, "lightning", "judgment", "14_lightning_radiant_arc_lightning.png")
	_check(captures.size() == 14, "ten per-Fusion, one all-Intro, and three base/Fusion comparisons were written")
	for failure in failures:
		push_error(failure)
	print("FUSION_PIXEL_ART_LAB_VISUAL_CHECK failures=%d screenshots=%d" % [failures.size(), captures.size()])
	lab.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	AudioManager.stop_all()
	get_tree().quit(0 if failures.is_empty() else 1)

func _capture_fusion_modes(lab: DeveloperTestLab, fusion_id: String) -> void:
	await _clear_transient_vfx()
	_check(lab.create_fusion(fusion_id, false), "%s can be created instantly in Lab" % fusion_id)
	lab._refresh_state_text()
	var origin: Vector2 = lab.player.global_position
	var labels: Array[Label] = []
	for index in MODES.size():
		var mode: String = MODES[index]
		var point: Vector2 = origin + Vector2((index - 2) * 126.0, -72.0)
		var start: Vector2 = point - Vector2(64, 0) if mode in ["attack", "trail"] else point
		var effect: FusionVFXEffect = lab.attack_vfx.play_fusion_effect(fusion_id, start, point, mode, 1.05 if mode != "formation" else 1.18)
		_check(effect != null and bool(effect.get_meta("generated_pixel_art", false)), "%s %s uses generated Pixel Art in Lab runtime" % [fusion_id, mode])
		labels.append(_add_world_label(lab.runtime_game, point + Vector2(-54, -72), "INTRO" if mode == "formation" else mode.to_upper()))
	await get_tree().create_timer(0.18, true, false, true).timeout
	await _capture("%02d_%s_pixel_modes_lab.png" % [FUSIONS.find(fusion_id) + 1, fusion_id])
	for label in labels:
		label.queue_free()

func _capture_all_intros(lab: DeveloperTestLab) -> void:
	await _clear_transient_vfx()
	var origin: Vector2 = lab.player.global_position
	var labels: Array[Label] = []
	for index in FUSIONS.size():
		var column := index % 5
		var row := index / 5
		var point := origin + Vector2((column - 2) * 126.0, (row - 0.5) * 190.0)
		var fusion_id: String = FUSIONS[index]
		var effect: FusionVFXEffect = lab.attack_vfx.play_fusion_effect(fusion_id, point, point, "formation", 0.88)
		_check(effect != null and bool(effect.get_meta("generated_pixel_art", false)), "%s all-Intro preview uses generated Pixel Art" % fusion_id)
		var display_name := GameManager.get_fusion_display_name(fusion_id).get_slice(" / ", 0)
		labels.append(_add_world_label(lab.runtime_game, point + Vector2(-62, 62), display_name))
	await get_tree().create_timer(0.18, true, false, true).timeout
	await _capture("11_all_fusion_intros_lab.png")
	for label in labels:
		label.queue_free()

func _capture_required_comparison(lab: DeveloperTestLab, fragment_id: String, fusion_id: String, file_name: String) -> void:
	await _clear_transient_vfx()
	var origin := lab.player.global_position + Vector2(0, -36)
	var left := origin + Vector2(-220, 0)
	var center := origin
	var right := origin + Vector2(220, 0)
	var labels: Array[Label] = []
	GameManager.debug_force_element_state({"element_%s" % fragment_id: 3})
	var element_data := DataLoader.element_vfx_effects.get("element_%s" % fragment_id) as ElementVFXData
	for point in [left, right]:
		lab.attack_vfx.play_element_hit(point, element_data, 3)
		lab.attack_vfx.play_iai_trail(point - Vector2(58, 20), point + Vector2(58, 20))
		labels.append(_add_world_label(lab.runtime_game, point + Vector2(-62, -72), "%s LV3" % fragment_id.to_upper()))
	_check(lab.create_fusion(fusion_id, false), "%s comparison can create Fusion" % fusion_id)
	lab._refresh_state_text()
	lab.attack_vfx.play_fusion_effect(fusion_id, center - Vector2(64, 0), center, "attack", 1.0)
	lab.attack_vfx.play_fusion_effect(fusion_id, center - Vector2(64, 20), center + Vector2(64, 20), "trail", 0.92)
	lab.attack_vfx.play_fusion_effect(fusion_id, center, center, "hit", 1.0)
	var fusion_name := GameManager.get_fusion_display_name(fusion_id).get_slice(" / ", 0)
	labels.append(_add_world_label(lab.runtime_game, center + Vector2(-62, -72), fusion_name))
	await get_tree().create_timer(0.14, true, false, true).timeout
	await _capture(file_name)
	for label in labels:
		label.queue_free()

func _add_world_label(world: Node, position: Vector2, text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.size = Vector2(124, 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	world.add_child(label)
	label.global_position = position
	return label

func _clear_transient_vfx() -> void:
	for effect in get_tree().get_nodes_in_group("transient_vfx"):
		effect.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

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
