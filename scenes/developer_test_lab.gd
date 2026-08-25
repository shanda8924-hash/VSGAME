extends Control
class_name DeveloperTestLab
## Debug Build専用。game.tscnをSubViewportへそのまま載せ、本編Systemを左Panelから操作する。

signal lab_ready()

const GAME_SCENE := preload("res://scenes/game.tscn")
const ENEMY_SCENE := preload("res://entities/enemies/enemy_basic.tscn")
const PROJECTILE_SCENE := preload("res://entities/projectiles/projectile.tscn")
const FUSIONS := [
	{"id":"frostfire", "label":"THERMAL SHOCK  Fire + Ice", "a":"fire", "b":"ice"},
	{"id":"plasma", "label":"PLASMA  Fire + Lightning", "a":"fire", "b":"lightning"},
	{"id":"solar", "label":"SOLAR FLARE  Fire + Light", "a":"fire", "b":"light"},
	{"id":"inferno", "label":"INFERNO  Fire + Dark", "a":"fire", "b":"dark"},
	{"id":"superconductor", "label":"SUPERCONDUCTOR  Ice + Lightning", "a":"ice", "b":"lightning"},
	{"id":"aurora", "label":"AURORA  Ice + Light", "a":"ice", "b":"light"},
	{"id":"void_frost", "label":"BLACK ICE  Ice + Dark", "a":"ice", "b":"dark"},
	{"id":"judgment", "label":"RADIANT ARC  Lightning + Light", "a":"lightning", "b":"light"},
	{"id":"voidstorm", "label":"VOIDSTORM  Lightning + Dark", "a":"lightning", "b":"dark"},
	{"id":"eclipse", "label":"ECLIPSE  Light + Dark", "a":"light", "b":"dark"},
]
const ELEMENTS := ["fire", "ice", "lightning", "light", "dark"]
const ELEMENT_LABELS := {"fire":"FIRE / 火", "ice":"ICE / 氷", "lightning":"LIGHTNING / 雷", "light":"LIGHT / 光", "dark":"DARK / 闇"}
const RARITIES := ["uncommon", "rare", "epic", "legendary", "mythic"]
const BOSS_STRATEGIES := {
	"Charge":"res://systems/boss_ai/charge_attack_strategy.gd",
	"Slam":"res://systems/boss_ai/slam_strategy.gd",
	"Summon":"res://systems/boss_ai/summon_strategy.gd",
	"Nova":"res://systems/boss_ai/nova_strategy.gd",
}

var runtime_game: Node2D
var player: Player
var element_combat: ElementCombatSystem
var attack_vfx: AttackVFXManager
var boss_spawner: BossSpawner
var fragment_select: FragmentSelect
var equipment_drop: EquipmentDropSystem
var room_controller: RoomRunController
var concept_system: ConceptSystem
var concept_board: ConceptBoard
var combo_system: ComboSystem
var dummy: EnemyBasic

var _subviewport: SubViewport
var _tabs: TabContainer
var _status_label: Label
var _state_label: RichTextLabel
var _damage_label: RichTextLabel
var _element_mode: OptionButton
var _gallery_element: OptionButton
var _enemy_type: OptionButton
var _spawn_pattern: OptionButton
var _elite_toggle: CheckButton
var _boss_type: OptionButton
var _equipment_template: OptionButton
var _equipment_rarity: OptionButton
var _equipment_summary: RichTextLabel
var _room_number: SpinBox
var _dummy_hp_label: Label
var _dummy_infinite := true
var _dummy_freeze := true
var _dummy_show_hp := true
var _dummy_show_damage := true
var _gallery_mode := false
var _selected_equipment: EquipmentData
var _baseline := {}
var _preview_token := 0
var _compare_token := 0
var _damage_reset_msec := 0
var _damage_last := 0.0
var _damage_total := 0.0
var _damage_hits := 0
var _critical_hits := 0
var _damage_by_type := {}
var _meter_connected := false
var _ui_refresh_elapsed := 0.0
var _save_session_active := false
var _selected_character_before_lab := "soldier"
var _returning_to_title := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.is_debug_build():
		_build_release_guard()
		return
	_selected_character_before_lab = GameManager.selected_character_id
	SaveManager.begin_ephemeral_session()
	_save_session_active = true
	_build_shell()
	_connect_damage_meter()
	await _load_runtime_game()
	_build_control_tabs()
	PixelUIStyle.apply_tree(self)
	spawn_dummy()
	reset_damage_meter()
	_set_status("READY — WASD/Arrow: Move, Space: Active Skill, Esc: Stop Preview")
	lab_ready.emit()

func _exit_tree() -> void:
	_preview_token += 1
	_compare_token += 1
	if _meter_connected:
		if EventBus.damage_dealt.is_connected(_on_physical_damage):
			EventBus.damage_dealt.disconnect(_on_physical_damage)
		if EventBus.element_damage_dealt.is_connected(_on_element_damage):
			EventBus.element_damage_dealt.disconnect(_on_element_damage)
	AudioManager.stop_all()
	Engine.time_scale = 1.0
	get_tree().paused = false
	if OS.is_debug_build():
		GameManager.debug_force_element_state({})
		GameManager.run_state = GameManager.RunState.NONE
		GameManager.selected_character_id = _selected_character_before_lab
	if _save_session_active:
		SaveManager.end_ephemeral_session()
		_save_session_active = false

func _process(delta: float) -> void:
	_ui_refresh_elapsed += delta
	if _ui_refresh_elapsed < 0.15:
		return
	_ui_refresh_elapsed = 0.0
	_refresh_state_text()
	_refresh_damage_text()
	_refresh_dummy_label()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_preview_token += 1
		_compare_token += 1
		_set_status("Preview / Compare stopped")
		get_viewport().set_input_as_handled()

func _build_release_guard() -> void:
	var background := ColorRect.new()
	background.color = Color(0.025, 0.03, 0.045, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var label := Label.new()
	label.text = "DEVELOPER TEST LAB\nUnavailable in Release Build"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 30)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(label)

func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = Color(0.025, 0.03, 0.045, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var split := HSplitContainer.new()
	split.name = "LabSplit"
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.split_offset = 540
	add_child(split)

	var panel := PanelContainer.new()
	panel.name = "DeveloperControlPanel"
	panel.custom_minimum_size.x = 500.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.045, 0.055, 0.08, 0.99)
	panel_style.border_color = Color(0.22, 0.72, 0.92, 0.75)
	panel_style.set_border_width_all(2)
	panel_style.content_margin_left = 10
	panel_style.content_margin_right = 10
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", panel_style)
	split.add_child(panel)

	var panel_vbox := VBoxContainer.new()
	panel.add_child(panel_vbox)
	var title := Label.new()
	title.text = "DEVELOPER TEST LAB"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))
	panel_vbox.add_child(title)
	_status_label = Label.new()
	_status_label.name = "LabStatus"
	_status_label.text = "Booting real game runtime..."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size.y = 38
	_status_label.add_theme_color_override("font_color", Color(0.86, 0.88, 0.94))
	panel_vbox.add_child(_status_label)
	_state_label = RichTextLabel.new()
	_state_label.name = "BuildState"
	_state_label.bbcode_enabled = true
	_state_label.fit_content = false
	_state_label.custom_minimum_size.y = 68
	_state_label.scroll_active = false
	panel_vbox.add_child(_state_label)

	var header_buttons := HBoxContainer.new()
	panel_vbox.add_child(header_buttons)
	var first_header_button := _add_button(header_buttons, "RESET STATE", reset_lab_state, "Clear spawned objects and reset runtime state")
	_add_button(header_buttons, "RELOAD GAME", reload_runtime_game, "Reinstantiate the real game scene")
	_add_button(header_buttons, "STOP AUTO", stop_all_previews)
	_add_button(header_buttons, "RETURN TITLE", return_to_title, "Leave Test Mode without saving test results")
	first_header_button.grab_focus.call_deferred()

	_tabs = TabContainer.new()
	_tabs.name = "LabTabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_vbox.add_child(_tabs)

	var field_frame := PanelContainer.new()
	field_frame.name = "RealGameField"
	field_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(field_frame)
	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "GameViewportContainer"
	viewport_container.stretch = true
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field_frame.add_child(viewport_container)
	_subviewport = SubViewport.new()
	_subviewport.name = "GameViewport"
	_subviewport.size = Vector2i(1060, 900)
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_subviewport.gui_embed_subwindows = true
	viewport_container.add_child(_subviewport)

	var mode_badge := Label.new()
	mode_badge.name = "TestModeBadge"
	mode_badge.text = "テストモード — セーブ無効"
	mode_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_badge.add_theme_font_size_override("font_size", 18)
	mode_badge.add_theme_color_override("font_color", Color(1.0, 0.86, 0.3))
	mode_badge.add_theme_color_override("font_shadow_color", Color(0.02, 0.02, 0.03, 0.95))
	mode_badge.add_theme_constant_override("shadow_offset_x", 2)
	mode_badge.add_theme_constant_override("shadow_offset_y", 2)
	mode_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mode_badge.position = Vector2(-330, 12)
	mode_badge.size = Vector2(310, 34)
	mode_badge.z_index = 100
	add_child(mode_badge)

func _load_runtime_game() -> void:
	GameManager.selected_character_id = "swordsman"
	runtime_game = GAME_SCENE.instantiate()
	_subviewport.add_child(runtime_game)
	await get_tree().process_frame
	await get_tree().physics_frame
	for node_name in ["WaveSpawner", "BossSpawner", "EliteRoomManager", "RoomRunController", "ComboSystem", "ConceptSystem"]:
		var automatic := runtime_game.get_node_or_null(node_name)
		if automatic:
			automatic.process_mode = Node.PROCESS_MODE_DISABLED
	player = runtime_game.get_node("Player") as Player
	element_combat = runtime_game.get_node("ElementCombatSystem") as ElementCombatSystem
	attack_vfx = runtime_game.get_node("AttackVFXManager") as AttackVFXManager
	boss_spawner = runtime_game.get_node("BossSpawner") as BossSpawner
	fragment_select = runtime_game.get_node("FragmentSelect") as FragmentSelect
	equipment_drop = runtime_game.get_node("EquipmentDropSystem") as EquipmentDropSystem
	room_controller = runtime_game.get_node("RoomRunController") as RoomRunController
	concept_system = runtime_game.get_node("ConceptSystem") as ConceptSystem
	concept_board = runtime_game.get_node("ConceptBoard") as ConceptBoard
	combo_system = runtime_game.get_node("ComboSystem") as ComboSystem
	_clear_enemies(true, true)
	_baseline = {
		"max_hp": player.health_component.max_hp,
		"move_speed": player.movement_component.base_speed,
		"damage": player.upgrades_component.damage_multiplier,
		"attack_speed": player.upgrades_component.attack_interval_multiplier,
		"crit": player.upgrades_component.crit_rate_bonus,
	}

func reload_runtime_game() -> void:
	stop_all_previews()
	if is_instance_valid(runtime_game):
		runtime_game.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	await _load_runtime_game()
	spawn_dummy()
	reset_damage_meter()
	_set_status("Real game scene reloaded")

func return_to_title() -> void:
	if _returning_to_title:
		return
	_returning_to_title = true
	stop_all_previews()
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/title.tscn")

func _build_control_tabs() -> void:
	_build_player_tab()
	_build_room_tab()
	_build_element_tab()
	_build_fusion_tab()
	_build_vfx_tab()
	_build_combat_tab()
	_build_boss_tab()
	_build_equipment_tab()
	_build_concept_tab()

func _build_room_tab() -> void:
	var body := _new_tab("ROOM")
	_section(body, "36 ROOM TRANSITION / PERFORMANCE")
	_room_number = SpinBox.new()
	_room_number.min_value = 1
	_room_number.max_value = 36
	_room_number.value = 4
	_room_number.step = 1
	body.add_child(_room_number)
	var jump_buttons := _grid(body, 3)
	_add_button(jump_buttons, "JUMP SELECTED", _room_jump_selected)
	_add_button(jump_buttons, "ROOM 4 BOSS", func(): _room_jump(4))
	_add_button(jump_buttons, "ROOM 12 BOSS", func(): _room_jump(12))
	_add_button(jump_buttons, "ROOM 24 BOSS", func(): _room_jump(24))
	_add_button(jump_buttons, "ROOM 36 FINAL", func(): _room_jump(36))
	_add_button(jump_buttons, "TRANSITION STRESS x12", _room_transition_stress)

func _room_jump_selected() -> void:
	await _room_jump(int(_room_number.value))

func _room_jump(room_number: int) -> void:
	room_controller.debug_jump_to_room(room_number)
	var deadline := Time.get_ticks_msec() + 6000
	while room_controller.current_room != room_number or room_controller.state != RoomRunController.RoomState.COMBAT:
		if Time.get_ticks_msec() >= deadline:
			_set_status("ROOM %d jump timed out" % room_number)
			return
		await get_tree().process_frame
	_set_status("ROOM %d ready / %s" % [room_number, room_controller.last_transition_profile])

func _room_transition_stress() -> void:
	_set_status("ROOM transition stress running...")
	var result := await room_controller.debug_transition_stress(12)
	_set_status("Transition stress complete: %s" % result)

func _build_concept_tab() -> void:
	var body := _new_tab("CONCEPT")
	_section(body, "CONCEPT INVENTORY / BOARD")
	_add_button(body, "ACQUIRE ALL CONCEPT PARTS", _concept_acquire_all)
	_add_button(body, "BUILD A: CRIT → THUNDER → CHAIN", func(): _concept_build_chain(0, "trigger_on_critical", "skill_thunder_strike", "modifier_chain"))
	_add_button(body, "BUILD B: 5TH → FIRE → AREA", func(): _concept_build_chain(1, "trigger_fifth_hit", "skill_fire_burst", "modifier_area"))
	_add_button(body, "BUILD A: COMBO → ICE → ECHO", func(): _concept_build_chain(0, "trigger_combo", "skill_ice_nova", "modifier_echo"))
	_add_button(body, "BUILD B: KILL → WIND → FOCUS", func(): _concept_build_chain(1, "trigger_on_kill", "skill_wind_blade", "modifier_focus"))
	_add_button(body, "OPEN CONCEPT BOARD", func(): concept_board.show_board("DEVELOPER CONCEPT BOARD"))
	_add_button(body, "TRIGGER DIRECT CRITICAL", _concept_trigger_critical)
	_add_button(body, "TRIGGER FIVE DIRECT HITS", _concept_trigger_five_hits)
	_add_button(body, "TRIGGER 20 COMBO", _concept_trigger_combo)
	_add_button(body, "CLEAR CONCEPT STATE", _concept_clear)

func _concept_acquire_all() -> void:
	concept_system.set_active(true)
	for data in DataLoader.get_all_concepts():
		concept_system.acquire_concept(data.id)
	_set_status("All 12 Concepts acquired — open Board to equip")

func _concept_build_chain(chain_index: int, trigger_id: String, skill_id: String, modifier_id: String) -> void:
	concept_system.set_active(true)
	for concept_id in [trigger_id, skill_id, modifier_id]:
		concept_system.acquire_concept(concept_id)
	concept_system.equip_concept(chain_index, "trigger", trigger_id)
	concept_system.equip_concept(chain_index, "skill", skill_id)
	concept_system.equip_concept(chain_index, "modifier", modifier_id)
	_set_status("Concept Chain %s equipped: %s → %s → %s" % [String.chr(65 + chain_index), trigger_id, skill_id, modifier_id])

func _concept_clear() -> void:
	concept_system.reset_runtime()
	concept_system.set_active(true)
	combo_system.reset_combo()
	_set_status("Concept inventory / board / hit counters reset")

func _concept_trigger_critical() -> void:
	var target := _ensure_concept_target()
	if target:
		target.health_component.apply_secondary_damage(1.0, CombatEventMeta.create_direct("lab_direct_critical", true))
		_set_status("Direct Critical event sent through real Health pipeline")

func _concept_trigger_five_hits() -> void:
	var target := _ensure_concept_target()
	if target:
		for _index in 5:
			target.health_component.apply_secondary_damage(1.0, CombatEventMeta.create_direct("lab_fifth_hit"))
		_set_status("Five direct Hit events sent to the same Dummy")

func _concept_trigger_combo() -> void:
	var target := _ensure_concept_target()
	if target:
		combo_system.set_active(true)
		combo_system.reset_combo()
		for _index in 20:
			target.health_component.apply_secondary_damage(1.0, CombatEventMeta.create_direct("lab_combo"))
		_set_status("20 confirmed Damage events sent through ComboSystem")

func _ensure_concept_target() -> EnemyBasic:
	if not is_instance_valid(dummy):
		spawn_dummy()
	return dummy

func _new_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title.replace("/", "_")
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(scroll)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, title)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 7)
	scroll.add_child(body)
	return body

func _section(parent: Control, text: String) -> void:
	var separator := HSeparator.new()
	parent.add_child(separator)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.32))
	parent.add_child(label)

func _grid(parent: Control, columns: int = 4) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)
	return grid

func _add_button(parent: Control, text_value: String, callback: Callable, tooltip: String = "") -> Button:
	var button := Button.new()
	button.text = text_value
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(96, 34)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _add_spin(parent: Control, label_text: String, min_value: float, max_value: float, step: float, value: float, callback: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 150
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	spin.value_changed.connect(callback)
	return spin

func _add_check(parent: Control, text_value: String, initial: bool, callback: Callable) -> CheckButton:
	var check := CheckButton.new()
	check.text = text_value
	check.button_pressed = initial
	check.toggled.connect(callback)
	parent.add_child(check)
	return check

func _build_player_tab() -> void:
	var body := _new_tab("PLAYER")
	_section(body, "PLAYER — real Components")
	_add_spin(body, "Current HP", 0, 10000, 1, player.health_component.current_hp, _set_player_hp)
	_add_spin(body, "Max HP", 1, 10000, 1, player.health_component.max_hp, _set_player_max_hp)
	_add_check(body, "Invincible", player.health_component.invincible, func(v): player.health_component.invincible = v)
	_add_spin(body, "Move Speed", 10, 1000, 5, player.movement_component.base_speed, func(v): player.movement_component.base_speed = v)
	_add_spin(body, "Attack Power x", 0.1, 10.0, 0.1, player.upgrades_component.damage_multiplier, func(v): player.upgrades_component.damage_multiplier = v)
	_add_spin(body, "Attack Speed Bonus", 0.0, 0.8, 0.05, player.upgrades_component.attack_interval_multiplier, func(v): player.upgrades_component.attack_interval_multiplier = v)
	_add_spin(body, "Critical Rate", 0.0, 1.0, 0.05, player.upgrades_component.crit_rate_bonus, func(v): player.upgrades_component.crit_rate_bonus = v)
	_add_spin(body, "Player Level (Force)", 1, 100, 1, player.experience_component.level, _force_player_level)
	_add_spin(body, "EXP (Force)", 0, 999999, 1, player.experience_component.current_exp, _force_player_exp)
	var buttons := _grid(body, 3)
	_add_button(buttons, "FULL HEAL", full_heal)
	_add_button(buttons, "KILL PLAYER", kill_player)
	_add_button(buttons, "RESET PLAYER", reset_player)
	_add_button(buttons, "LEVEL +1", func(): add_player_levels(1))
	_add_button(buttons, "LEVEL +10", func(): add_player_levels(10))
	_add_button(buttons, "MAX Lv50", func(): add_player_levels(maxi(0, 50 - player.experience_component.level)))

func _build_element_tab() -> void:
	var body := _new_tab("ELEMENT")
	_section(body, "ELEMENT TEST")
	_element_mode = OptionButton.new()
	_element_mode.add_item("NORMAL — Acquire/Level Up runtime")
	_element_mode.add_item("FORCE — final state only")
	body.add_child(_element_mode)
	for fragment_id in ELEMENTS:
		var element_id := "element_%s" % fragment_id
		var label := Label.new()
		label.text = ELEMENT_LABELS[fragment_id]
		label.add_theme_color_override("font_color", _element_color(element_id))
		body.add_child(label)
		var levels := _grid(body, 4)
		for level in 4:
			_add_button(levels, "NONE" if level == 0 else "Lv%d" % level, _on_element_level_button.bind(fragment_id, level))
		var transitions := _grid(body, 3)
		_add_button(transitions, "Trigger Lv1", trigger_element_transition.bind(fragment_id, 0))
		_add_button(transitions, "Lv1 → Lv2", trigger_element_transition.bind(fragment_id, 1))
		_add_button(transitions, "Lv2 → Lv3", trigger_element_transition.bind(fragment_id, 2))
		var actions := _grid(body, 4)
		_add_button(actions, "ATTACK", trigger_element_attack.bind(fragment_id))
		_add_button(actions, "HIT", trigger_element_hit.bind(fragment_id))
		_add_button(actions, "STATUS", trigger_element_status.bind(fragment_id))
		_add_button(actions, "IAI (REAL HIT)", trigger_element_iai.bind(fragment_id))
	_add_button(body, "CLEAR ELEMENT BUILD", func(): set_element_level("fire", 0, true); GameManager.debug_force_element_state({}); element_combat.reset_runtime())

func _build_fusion_tab() -> void:
	var body := _new_tab("FUSION")
	_section(body, "FUSION TEST — all 10 runtime pairs")
	var preview := _grid(body, 2)
	_add_button(preview, "PREVIEW ALL FUSIONS", preview_all_fusions)
	_add_button(preview, "STOP (Esc)", stop_all_previews)
	var compare := _grid(body, 1)
	_add_button(compare, "LIGHTNING → PLASMA → LIGHTNING", compare_base_fusion.bind("lightning", "plasma"))
	_add_button(compare, "FIRE → PLASMA → FIRE", compare_base_fusion.bind("fire", "plasma"))
	_add_button(compare, "LIGHTNING → RADIANT ARC → LIGHTNING", compare_base_fusion.bind("lightning", "judgment"))
	for entry in FUSIONS:
		var label := Label.new()
		label.text = entry["label"]
		label.add_theme_font_size_override("font_size", 15)
		body.add_child(label)
		var actions := _grid(body, 3)
		_add_button(actions, "CREATE", create_fusion.bind(entry["id"], false))
		_add_button(actions, "NATURAL", create_fusion.bind(entry["id"], true))
		_add_button(actions, "TRIGGER ATTACK", trigger_fusion_attack.bind(entry["id"]))
		_add_button(actions, "TRIGGER HIT", trigger_fusion_vfx.bind(entry["id"], "hit"))
		_add_button(actions, "TRIGGER BONUS TRAIT", trigger_fusion_bonus.bind(entry["id"]))
		_add_button(actions, "TRIGGER INTRO", trigger_fusion_intro.bind(entry["id"]))
		_add_button(actions, "RESET", reset_fusion)

func _build_vfx_tab() -> void:
	var body := _new_tab("VFX GALLERY")
	_section(body, "VFX GALLERY — combat can be frozen")
	_add_check(body, "Gallery Mode / freeze spawned enemies", false, _set_gallery_mode)
	_gallery_element = OptionButton.new()
	for element in ELEMENTS:
		_gallery_element.add_item(ELEMENT_LABELS[element])
		_gallery_element.set_item_metadata(_gallery_element.item_count - 1, element)
	body.add_child(_gallery_element)
	_add_button(body, "COMPARE LV1 / LV2 / LV3", compare_selected_element)
	var element_grid := _grid(body, 3)
	for element in ELEMENTS:
		for level in range(1, 4):
			_add_button(element_grid, "%s Lv%d" % [element.capitalize(), level], play_element_gallery.bind(element, level))
	_section(body, "CONCEPT PIXEL VFX")
	_add_button(body, "WIND BLADE / 風刃", preview_wind_blade_vfx)
	_section(body, "FUSION VFX")
	var fusion_grid := _grid(body, 2)
	for entry in FUSIONS:
		_add_button(fusion_grid, entry["id"].to_upper(), trigger_fusion_vfx.bind(entry["id"], "attack"))

func _build_combat_tab() -> void:
	var body := _new_tab("COMBAT")
	_section(body, "DUMMY ENEMY")
	var dummy_buttons := _grid(body, 2)
	_add_button(dummy_buttons, "SPAWN / RESET DUMMY", spawn_dummy)
	_add_button(dummy_buttons, "REMOVE DUMMY", remove_dummy)
	_add_check(body, "Infinite HP", true, _set_dummy_infinite)
	_add_check(body, "Freeze Position", true, _set_dummy_freeze)
	_add_check(body, "Show Hitbox", false, _set_dummy_hitbox)
	_add_check(body, "Show HP", true, func(v): _dummy_show_hp = v)
	_add_check(body, "Show Damage Received", true, func(v): _dummy_show_damage = v)
	_add_check(body, "Status Immunity", false, _set_dummy_status_immunity)

	_section(body, "DAMAGE METER")
	_damage_label = RichTextLabel.new()
	_damage_label.bbcode_enabled = true
	_damage_label.custom_minimum_size.y = 210
	_damage_label.scroll_active = false
	body.add_child(_damage_label)
	_add_button(body, "RESET DAMAGE METER", reset_damage_meter)

	_section(body, "ENEMY SPAWN CONTROL")
	_enemy_type = OptionButton.new()
	var enemy_ids := DataLoader.enemies.keys()
	enemy_ids.sort()
	for enemy_id in enemy_ids:
		var data: EnemyData = DataLoader.enemies[enemy_id]
		_enemy_type.add_item("%s / %s" % [enemy_id, data.display_name])
		_enemy_type.set_item_metadata(_enemy_type.item_count - 1, enemy_id)
	body.add_child(_enemy_type)
	_spawn_pattern = OptionButton.new()
	for pattern in ["Near Player", "Around Player", "Random Field", "Line", "Cluster"]:
		_spawn_pattern.add_item(pattern)
	body.add_child(_spawn_pattern)
	_elite_toggle = _add_check(body, "Elite multiplier", false, func(_v): pass)
	var spawn_buttons := _grid(body, 3)
	for count in [1, 10, 50, 100]:
		_add_button(spawn_buttons, "SPAWN %d" % count, spawn_selected_enemies.bind(count))
	_add_button(spawn_buttons, "CLEAR ENEMIES", func(): _clear_enemies(false, false))
	_add_button(spawn_buttons, "PROJECTILE", trigger_projectile)
	_add_button(spawn_buttons, "CLEAR PROJECTILES", clear_projectiles)

func _build_boss_tab() -> void:
	var body := _new_tab("BOSS / REWARD")
	_section(body, "BOSS TEST")
	_boss_type = OptionButton.new()
	var boss_ids := DataLoader.bosses.keys()
	boss_ids.sort()
	for boss_id in boss_ids:
		var data: BossData = DataLoader.bosses[boss_id]
		_boss_type.add_item("%s / %s / %s" % [boss_id, data.display_name, data.attack_pattern_id])
		_boss_type.set_item_metadata(_boss_type.item_count - 1, boss_id)
	body.add_child(_boss_type)
	var boss_buttons := _grid(body, 3)
	_add_button(boss_buttons, "SPAWN BOSS", spawn_selected_boss)
	_add_button(boss_buttons, "HP 50%", func(): set_boss_hp_ratio(0.5))
	_add_button(boss_buttons, "HP 1%", func(): set_boss_hp_ratio(0.01))
	_add_button(boss_buttons, "KILL BOSS", kill_boss)
	_add_button(boss_buttons, "CLEAR BOSS", clear_boss)
	for strategy_name in BOSS_STRATEGIES:
		_add_button(boss_buttons, strategy_name.to_upper(), trigger_boss_strategy.bind(strategy_name))

	_section(body, "BOSS REWARD STATE PRESET")
	var presets := _grid(body, 3)
	for preset in ["NO ELEMENT", "ONE ELEMENT", "TWO ELEMENT", "ONE MAX", "TWO MAX", "FUSION ACTIVE"]:
		_add_button(presets, preset, apply_reward_preset.bind(preset))
	_add_button(body, "OPEN BOSS REWARD", open_boss_reward)

func _build_equipment_tab() -> void:
	var body := _new_tab("EQUIPMENT / LOOT")
	_section(body, "EQUIPMENT TEST")
	_equipment_template = OptionButton.new()
	for template in equipment_drop.debug_get_templates():
		_equipment_template.add_item("%s / %s" % [template.get("id", ""), template.get("display_name", "")])
		_equipment_template.set_item_metadata(_equipment_template.item_count - 1, template.get("id", ""))
	body.add_child(_equipment_template)
	_equipment_rarity = OptionButton.new()
	for rarity in RARITIES:
		_equipment_rarity.add_item(rarity.to_upper())
		_equipment_rarity.set_item_metadata(_equipment_rarity.item_count - 1, rarity)
	body.add_child(_equipment_rarity)
	var equipment_buttons := _grid(body, 3)
	_add_button(equipment_buttons, "DROP", equipment_drop_selected)
	_add_button(equipment_buttons, "ADD INVENTORY", equipment_add_selected)
	_add_button(equipment_buttons, "EQUIP", equipment_equip_selected)
	_add_button(equipment_buttons, "UNEQUIP", equipment_unequip_selected)
	_add_button(equipment_buttons, "REMOVE", equipment_remove_selected)
	_add_button(equipment_buttons, "CLEAR", equipment_clear)

	_section(body, "EQUIPMENT MERGE")
	var merge_buttons := _grid(body, 3)
	_add_button(merge_buttons, "アンコモン素材 ×3", equipment_give_rarity_materials.bind("uncommon"))
	_add_button(merge_buttons, "レア素材 ×3", equipment_give_rarity_materials.bind("rare"))
	_add_button(merge_buttons, "エピック素材 ×3", equipment_give_rarity_materials.bind("epic"))
	_add_button(merge_buttons, "合成画面を開く", open_equipment_merge_screen)
	_add_button(merge_buttons, "MERGE", equipment_merge_selected)
	_add_button(merge_buttons, "CLEAR", equipment_clear)

	_section(body, "LOOT VISIBILITY")
	var loot_buttons := _grid(body, 3)
	_add_button(loot_buttons, "DROP 1 ITEM", func(): drop_loot_count(1))
	_add_button(loot_buttons, "DROP 10 ITEMS", func(): drop_loot_count(10))
	_add_button(loot_buttons, "ALL RARITIES", drop_all_rarities)
	_add_button(loot_buttons, "LOOT CLEAN", loot_preset_clean)
	_add_button(loot_buttons, "LOOT COMBAT", loot_preset_combat)
	_add_button(loot_buttons, "LOOT STRESS", loot_preset_stress)
	_equipment_summary = RichTextLabel.new()
	_equipment_summary.bbcode_enabled = true
	_equipment_summary.custom_minimum_size.y = 135
	_equipment_summary.scroll_active = false
	body.add_child(_equipment_summary)
	player.equipment_component.inventory_changed.connect(_refresh_equipment_summary)
	_refresh_equipment_summary()

# PLAYER ----------------------------------------------------------------------
func _set_player_hp(value: float) -> void:
	player.health_component.current_hp = clampf(value, 0.0, player.health_component.max_hp)
	player.health_component.damaged.emit(0.0, player.health_component.current_hp, player.health_component.max_hp)

func _set_player_max_hp(value: float) -> void:
	player.health_component.max_hp = maxf(value, 1.0)
	player.health_component.current_hp = minf(player.health_component.current_hp, player.health_component.max_hp)
	player.health_component.damaged.emit(0.0, player.health_component.current_hp, player.health_component.max_hp)

func _force_player_level(value: float) -> void:
	player.experience_component.level = maxi(1, int(value))
	player.experience_component.exp_changed.emit(player.experience_component.current_exp, player.experience_component.exp_to_next_level)

func _force_player_exp(value: float) -> void:
	player.experience_component.current_exp = maxi(0, int(value))
	player.experience_component.exp_changed.emit(player.experience_component.current_exp, player.experience_component.exp_to_next_level)

func full_heal() -> void:
	player.health_component.heal(player.health_component.max_hp)
	_set_status("Player fully healed through HealthComponent")

func kill_player() -> void:
	player.health_component.invincible = false
	player.health_component.current_hp = 1.0
	player.health_component.apply_secondary_damage(1.0)
	_set_status("Player death runtime triggered — use RELOAD GAME to restart")

func reset_player() -> void:
	GameManager.run_state = GameManager.RunState.PLAYING
	player._is_dead = false
	player.health_component.invincible = false
	player.health_component.max_hp = float(_baseline.get("max_hp", 100.0))
	player.health_component.current_hp = player.health_component.max_hp
	player.health_component.clear_shield()
	player.movement_component.base_speed = float(_baseline.get("move_speed", 100.0))
	player.upgrades_component.damage_multiplier = float(_baseline.get("damage", 1.0))
	player.upgrades_component.attack_interval_multiplier = float(_baseline.get("attack_speed", 0.0))
	player.upgrades_component.crit_rate_bonus = float(_baseline.get("crit", 0.0))
	player.experience_component.level = 1
	player.experience_component.current_exp = 0
	player.experience_component.exp_to_next_level = 5
	player.experience_component.exp_changed.emit(0, 5)
	_set_status("Player Component values reset")

func add_player_levels(count: int) -> void:
	for _index in maxi(count, 0):
		player.experience_component.add_exp(player.experience_component.exp_to_next_level - player.experience_component.current_exp)
	_set_status("Player Level -> %d via ExperienceComponent" % player.experience_component.level)

# ELEMENT / FUSION ------------------------------------------------------------
func _on_element_level_button(fragment_id: String, level: int) -> void:
	set_element_level(fragment_id, level, _element_mode.selected == 1)

func set_element_level(fragment_id: String, level: int, force: bool = false) -> bool:
	var element_id := "element_%s" % fragment_id
	level = clampi(level, 0, 3)
	if force:
		var stacks := {}
		for active_id in GameManager.get_active_element_ids():
			stacks[active_id] = GameManager.get_element_stack(active_id)
		if level <= 0:
			stacks.erase(element_id)
		else:
			stacks[element_id] = level
		if stacks.size() > 2:
			_set_status("FORCE rejected: Element Slot is already 2 / 2")
			return false
		element_combat.reset_runtime()
		var forced := GameManager.debug_force_element_state(stacks)
		_set_status("FORCE %s -> Lv%d" % [fragment_id.to_upper(), level])
		return forced
	var current := GameManager.get_element_stack(element_id)
	if level == 0 or level < current:
		var rebuild := {}
		for active_id in GameManager.get_active_element_ids():
			if active_id != element_id:
				rebuild[active_id] = GameManager.get_element_stack(active_id)
		if level > 0:
			rebuild[element_id] = level
		GameManager.set_active_element(GameManager.ELEMENT_NONE)
		element_combat.reset_runtime()
		for active_id in rebuild:
			for _rank in int(rebuild[active_id]):
				GameManager.add_fragment(String(active_id).trim_prefix("element_"))
	else:
		for _rank in level - current:
			GameManager.add_fragment(fragment_id)
	var success := GameManager.get_element_stack(element_id) == level
	_set_status("NORMAL %s -> Lv%d%s" % [fragment_id.to_upper(), level, "" if success else " (rejected by runtime rule)"])
	return success

func trigger_element_transition(fragment_id: String, from_level: int) -> void:
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	element_combat.reset_runtime()
	for _rank in from_level:
		GameManager.add_fragment(fragment_id)
	var before_projectiles := get_tree().get_nodes_in_group("projectiles").size()
	GameManager.add_fragment(fragment_id)
	var after_projectiles := get_tree().get_nodes_in_group("projectiles").size()
	_set_status("%s Lv%d→Lv%d | Projectile delta %d" % [fragment_id.to_upper(), from_level, from_level + 1, after_projectiles - before_projectiles])

func trigger_element_attack(fragment_id: String) -> void:
	set_element_level(fragment_id, maxi(GameManager.get_element_stack("element_%s" % fragment_id), 1), true)
	var target := _ensure_dummy()
	player.active_skill_component._damage_enemy(target, 100.0, 0.0)
	_set_status("Real physical + %s Element attack applied" % fragment_id.to_upper())

func trigger_element_hit(fragment_id: String) -> void:
	set_element_level(fragment_id, maxi(GameManager.get_element_stack("element_%s" % fragment_id), 1), true)
	var target := _ensure_dummy()
	element_combat.apply_element_damage(target.hurtbox_component, 100.0, player.global_position)
	_set_status("ElementCombatSystem hit: %s" % fragment_id.to_upper())

func trigger_element_status(fragment_id: String) -> void:
	set_element_level(fragment_id, 3, true)
	var target := _ensure_dummy()
	for _index in 5:
		element_combat.apply_element_damage(target.hurtbox_component, 80.0, player.global_position)
	_set_status("%s Lv3 status/mechanic triggered" % fragment_id.to_upper())

func trigger_element_iai(fragment_id: String) -> void:
	set_element_level(fragment_id, maxi(GameManager.get_element_stack("element_%s" % fragment_id), 1), true)
	var target := _ensure_dummy()
	var direction := player.get_facing_direction()
	if direction.length_squared() <= 0.01:
		direction = Vector2.RIGHT
	target.global_position = _safe_world_position(player.global_position + direction * 150.0)
	player.active_skill_component._swordsman_iai()
	_set_status("Real IAI attack: %s" % fragment_id.to_upper())

func create_fusion(fusion_id: String, natural: bool = false) -> bool:
	var entry := _fusion_entry(fusion_id)
	if entry.is_empty():
		return false
	element_combat.reset_runtime()
	if natural:
		GameManager.set_active_element(GameManager.ELEMENT_NONE)
		for _rank in 3:
			GameManager.add_fragment(entry["a"])
		for _rank in 3:
			GameManager.add_fragment(entry["b"])
	else:
		var stacks := {"element_%s" % entry["a"]: 3, "element_%s" % entry["b"]: 3}
		GameManager.debug_force_element_state(stacks, fusion_id)
	_set_status("%s Fusion: %s" % ["NATURAL" if natural else "FORCE", GameManager.get_fusion_display_name(fusion_id)])
	return GameManager.active_fusion_id == fusion_id

func trigger_fusion_attack(fusion_id: String) -> void:
	if GameManager.active_fusion_id != fusion_id:
		create_fusion(fusion_id, false)
	var target := _ensure_dummy()
	element_combat.apply_element_damage(target.hurtbox_component, 120.0, player.global_position)
	_set_status("Fusion attack runtime: %s" % GameManager.get_fusion_display_name(fusion_id))

func trigger_fusion_bonus(fusion_id: String) -> void:
	create_fusion(fusion_id, false)
	_clear_developer_targets()
	var targets := spawn_enemies(7, "Cluster", _selected_enemy_id(), false, true)
	if targets.is_empty():
		return
	var target := targets[0]
	for _index in 7:
		if is_instance_valid(target) and target.health_component.current_hp > 0.0:
			element_combat.apply_element_damage(target.hurtbox_component, 95.0, player.global_position)
	if fusion_id in ["plasma", "solar", "inferno"] and is_instance_valid(target) and target.health_component.current_hp > 0.0:
		target.health_component.current_hp = 1.0
		target.health_component.apply_secondary_damage(1.0)
	_set_status("Fusion Bonus Trait exercised: %s" % GameManager.get_fusion_display_name(fusion_id))

func trigger_fusion_vfx(fusion_id: String, mode: String = "attack") -> void:
	var target := _ensure_dummy()
	var start := player.global_position + Vector2(42, -12)
	attack_vfx.play_fusion_effect(fusion_id, start, target.global_position, mode, 1.15)
	_set_status("Fusion VFX: %s / %s" % [GameManager.get_fusion_display_name(fusion_id), mode])

func trigger_fusion_intro(fusion_id: String) -> void:
	var entry := _fusion_entry(fusion_id)
	if entry.is_empty():
		return
	create_fusion(fusion_id, false)
	var sources := ["element_%s" % entry["a"], "element_%s" % entry["b"]]
	EventBus.element_fusion_formed.emit(fusion_id, GameManager.get_fusion_display_name(fusion_id), sources)
	_set_status("Fusion formation presentation: %s" % GameManager.get_fusion_display_name(fusion_id))

func reset_fusion() -> void:
	GameManager.set_active_element(GameManager.ELEMENT_NONE)
	element_combat.reset_runtime()
	_set_status("Fusion and Element runtime reset")

func preview_all_fusions() -> void:
	_preview_token += 1
	var token := _preview_token
	_set_status("PREVIEW ALL FUSIONS — generated Attack / Trail / Hit / Burst / Intro")
	for entry in FUSIONS:
		if token != _preview_token:
			return
		create_fusion(entry["id"], true)
		trigger_fusion_attack(entry["id"])
		await get_tree().create_timer(0.72, true, false, true).timeout
		if token != _preview_token:
			return
		trigger_fusion_vfx(entry["id"], "trail")
		await get_tree().create_timer(0.62, true, false, true).timeout
		if token != _preview_token:
			return
		trigger_fusion_vfx(entry["id"], "hit")
		await get_tree().create_timer(0.62, true, false, true).timeout
		if token != _preview_token:
			return
		trigger_fusion_bonus(entry["id"])
		await get_tree().create_timer(1.05, true, false, true).timeout
		if token != _preview_token:
			return
		trigger_fusion_intro(entry["id"])
		await get_tree().create_timer(1.85, true, false, true).timeout
		_clear_developer_targets()
		reset_fusion()
	_set_status("PREVIEW ALL FUSIONS complete")

func compare_base_fusion(fragment_id: String, fusion_id: String) -> void:
	_compare_token += 1
	var token := _compare_token
	play_element_gallery(fragment_id, 3)
	await get_tree().create_timer(0.78, true, false, true).timeout
	if token != _compare_token:
		return
	create_fusion(fusion_id, false)
	trigger_fusion_attack(fusion_id)
	await get_tree().create_timer(0.78, true, false, true).timeout
	if token != _compare_token:
		return
	GameManager.debug_force_element_state({"element_%s" % fragment_id: 3})
	element_combat.reset_runtime()
	play_element_gallery(fragment_id, 3)
	_set_status("Compare complete: %s Lv3 → %s → %s Lv3" % [fragment_id.to_upper(), GameManager.get_fusion_display_name(fusion_id), fragment_id.to_upper()])

func stop_all_previews() -> void:
	_preview_token += 1
	_compare_token += 1
	_set_status("Automatic previews stopped")

func _fusion_entry(fusion_id: String) -> Dictionary:
	for entry in FUSIONS:
		if entry["id"] == fusion_id:
			return entry
	return {}

# VFX GALLERY -----------------------------------------------------------------
func _set_gallery_mode(enabled: bool) -> void:
	_gallery_mode = enabled
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyBasic and enemy != dummy:
			enemy.set_movement_locked(enabled)
			enemy.movement_component.direction = Vector2.ZERO
	_set_status("VFX Gallery %s" % ["ON" if enabled else "OFF"])

func play_element_gallery(fragment_id: String, level: int) -> void:
	set_element_level(fragment_id, level, true)
	var target := _ensure_dummy()
	var data: ElementVFXData = DataLoader.element_vfx_effects.get("element_%s" % fragment_id)
	attack_vfx.play_element_hit(target.global_position, data, level)
	attack_vfx.play_iai_trail(target.global_position + Vector2(-120, 36), target.global_position + Vector2(120, 36))
	_set_status("Gallery: %s Lv%d" % [fragment_id.to_upper(), level])

func compare_selected_element() -> void:
	_compare_token += 1
	var token := _compare_token
	var fragment_id := String(_gallery_element.get_item_metadata(_gallery_element.selected))
	for level in range(1, 4):
		if token != _compare_token:
			return
		play_element_gallery(fragment_id, level)
		await get_tree().create_timer(1.15, true, false, true).timeout
	_set_status("Compare complete: %s Lv1 / Lv2 / Lv3" % fragment_id.to_upper())

func preview_wind_blade_vfx() -> void:
	var target := _ensure_dummy()
	ConceptSkillVFX.spawn(runtime_game, target.global_position, "wind_blade", 92.0, Color("8ff5c0"))
	_set_status("Gallery: generated Wind Blade 6-frame Pixel VFX")

# DUMMY / DAMAGE / ENEMY ------------------------------------------------------
func spawn_dummy() -> EnemyBasic:
	remove_dummy()
	var source: EnemyData = DataLoader.enemies.values()[0] if not DataLoader.enemies.is_empty() else null
	var data := source.duplicate(true) as EnemyData if source else EnemyData.new()
	data.id = "developer_dummy"
	data.display_name = "DEVELOPER DUMMY"
	data.max_hp = 1000000000.0 if _dummy_infinite else 10000.0
	data.move_speed = 0.0
	data.contact_damage = 0.0
	data.exp_value = 0
	data.attack_interval = 99.0
	data.attack_windup = 99.0
	dummy = ENEMY_SCENE.instantiate() as EnemyBasic
	dummy.enemy_data = data
	dummy.set_meta("developer_dummy", true)
	dummy.add_to_group("developer_dummy")
	runtime_game.add_child(dummy)
	dummy.global_position = _safe_world_position(player.global_position + Vector2(250, 0))
	dummy.health_component.damaged.connect(_on_dummy_damaged)
	dummy.health_component.died.connect(_on_dummy_died)
	_dummy_hp_label = Label.new()
	_dummy_hp_label.name = "DeveloperDummyLabel"
	_dummy_hp_label.position = Vector2(-110, -72)
	_dummy_hp_label.size = Vector2(220, 56)
	_dummy_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dummy_hp_label.add_theme_color_override("font_color", Color(0.65, 1.0, 0.75))
	dummy.add_child(_dummy_hp_label)
	_set_dummy_freeze(_dummy_freeze)
	_set_dummy_status_immunity(bool(dummy.get_meta("status_immune", false)))
	_refresh_dummy_label()
	return dummy

func remove_dummy() -> void:
	if is_instance_valid(dummy):
		dummy.queue_free()
	dummy = null
	_dummy_hp_label = null

func _ensure_dummy() -> EnemyBasic:
	return dummy if is_instance_valid(dummy) else spawn_dummy()

func _on_dummy_damaged(amount: float, _current: float, _max_hp: float) -> void:
	_damage_last = amount
	if _dummy_infinite and is_instance_valid(dummy):
		dummy.health_component.current_hp = dummy.health_component.max_hp
	_refresh_dummy_label()

func _on_dummy_died() -> void:
	if _dummy_infinite:
		call_deferred("spawn_dummy")

func _set_dummy_infinite(value: bool) -> void:
	_dummy_infinite = value
	if is_instance_valid(dummy):
		dummy.health_component.max_hp = 1000000000.0 if value else 10000.0
		dummy.health_component.current_hp = dummy.health_component.max_hp

func _set_dummy_freeze(value: bool) -> void:
	_dummy_freeze = value
	if is_instance_valid(dummy):
		dummy.set_movement_locked(value)
		dummy.movement_component.direction = Vector2.ZERO

func _set_dummy_hitbox(value: bool) -> void:
	if not is_instance_valid(dummy):
		return
	var overlay := dummy.get_node_or_null("DeveloperHitbox") as Line2D
	if value and overlay == null:
		overlay = Line2D.new()
		overlay.name = "DeveloperHitbox"
		overlay.width = 2.0
		overlay.default_color = Color(0.2, 1.0, 0.45, 0.9)
		var points := PackedVector2Array()
		for index in 33:
			points.append(Vector2.from_angle(TAU * index / 32.0) * 28.0)
		overlay.points = points
		overlay.z_index = 90
		dummy.add_child(overlay)
	elif not value and overlay:
		overlay.queue_free()

func _set_dummy_status_immunity(value: bool) -> void:
	if is_instance_valid(dummy):
		dummy.set_meta("status_immune", value)

func _refresh_dummy_label() -> void:
	if not is_instance_valid(dummy) or not is_instance_valid(_dummy_hp_label):
		return
	var lines: Array[String] = ["DEVELOPER DUMMY"]
	if _dummy_show_hp:
		lines.append("HP %.0f / %.0f%s" % [dummy.health_component.current_hp, dummy.health_component.max_hp, " ∞" if _dummy_infinite else ""])
	if _dummy_show_damage:
		lines.append("Last %.1f" % _damage_last)
	_dummy_hp_label.text = "\n".join(lines)

func _connect_damage_meter() -> void:
	if not EventBus.damage_dealt.is_connected(_on_physical_damage):
		EventBus.damage_dealt.connect(_on_physical_damage)
	if not EventBus.element_damage_dealt.is_connected(_on_element_damage):
		EventBus.element_damage_dealt.connect(_on_element_damage)
	_meter_connected = true

func _on_physical_damage(amount: float, _position: Vector2, is_critical: bool) -> void:
	_record_damage("physical", amount, is_critical)

func _on_element_damage(amount: float, _position: Vector2, element_id: String, _stack: int, _chain: int) -> void:
	var category := "fusion" if element_id.begins_with("fusion_") else element_id.trim_prefix("element_")
	_record_damage(category, amount, false)

func _record_damage(category: String, amount: float, critical: bool) -> void:
	if amount <= 0.0:
		return
	_damage_last = amount
	_damage_total += amount
	_damage_hits += 1
	_critical_hits += 1 if critical else 0
	_damage_by_type[category] = float(_damage_by_type.get(category, 0.0)) + amount

func reset_damage_meter() -> void:
	_damage_reset_msec = Time.get_ticks_msec()
	_damage_last = 0.0
	_damage_total = 0.0
	_damage_hits = 0
	_critical_hits = 0
	_damage_by_type.clear()
	_refresh_damage_text()

func _refresh_damage_text() -> void:
	if _damage_label == null:
		return
	var seconds := maxf((Time.get_ticks_msec() - _damage_reset_msec) / 1000.0, 0.001)
	var lines := ["[b]LAST HIT[/b]  %.1f", "[b]DPS[/b]  %.1f", "[b]TOTAL[/b]  %.1f", "HIT COUNT  %d    CRITICAL  %d"]
	var text := "%s\n%s\n%s\n%s" % [lines[0] % _damage_last, lines[1] % (_damage_total / seconds), lines[2] % _damage_total, lines[3] % [_damage_hits, _critical_hits]]
	for category in ["physical", "fire", "ice", "lightning", "light", "dark", "fusion"]:
		text += "\n%-10s %9.1f" % [category.to_upper(), float(_damage_by_type.get(category, 0.0))]
	_damage_label.text = text

func spawn_selected_enemies(count: int) -> void:
	spawn_enemies(count, _spawn_pattern.get_item_text(_spawn_pattern.selected), _selected_enemy_id(), _elite_toggle.button_pressed)
	_set_status("Spawned %d real enemies" % count)

func spawn_enemies(count: int, pattern: String, enemy_id: String, elite: bool = false, developer_targets: bool = false) -> Array[EnemyBasic]:
	var result: Array[EnemyBasic] = []
	var data: EnemyData = DataLoader.enemies.get(enemy_id)
	if data == null:
		return result
	for index in count:
		var enemy := ENEMY_SCENE.instantiate() as EnemyBasic
		enemy.enemy_data = data
		enemy.elite_stat_multiplier = 2.0 if elite else 1.0
		if developer_targets:
			enemy.set_meta("developer_target", true)
		runtime_game.add_child(enemy)
		enemy.global_position = _spawn_position(pattern, index, count)
		if _gallery_mode:
			enemy.set_movement_locked(true)
		result.append(enemy)
	return result

func _selected_enemy_id() -> String:
	if _enemy_type and _enemy_type.item_count > 0:
		return String(_enemy_type.get_item_metadata(_enemy_type.selected))
	return String(DataLoader.enemies.keys()[0]) if not DataLoader.enemies.is_empty() else ""

func _spawn_position(pattern: String, index: int, count: int) -> Vector2:
	var center := player.global_position + Vector2(220, 0)
	match pattern:
		"Around Player":
			return _safe_world_position(player.global_position + Vector2.from_angle(TAU * index / maxf(count, 1)) * (140.0 + index % 4 * 35.0))
		"Random Field":
			var floor_cells := GameManager.dungeon_map.get_floor_cells() if GameManager.dungeon_map else []
			return GameManager.dungeon_map.grid_to_world(floor_cells[randi() % floor_cells.size()]) if not floor_cells.is_empty() else center
		"Line":
			return _safe_world_position(center + Vector2((index - count * 0.5) * 36.0, 0))
		"Cluster":
			return _safe_world_position(center + Vector2((index % 5) * 30.0, (index / 5) * 30.0))
		_:
			return _safe_world_position(center + Vector2(index % 3 * 34.0, index / 3 * 34.0))

func _safe_world_position(candidate: Vector2) -> Vector2:
	var map := GameManager.dungeon_map as DungeonMap
	if map == null:
		return candidate
	var cell := map.world_to_grid(candidate)
	if map.is_floor(cell):
		return map.grid_to_world(cell)
	var nearest := Vector2.INF
	var nearest_distance := INF
	for floor_cell in map.get_floor_cells():
		var world := map.grid_to_world(floor_cell)
		var distance := world.distance_squared_to(candidate)
		if distance < nearest_distance:
			nearest = world
			nearest_distance = distance
	return candidate if nearest == Vector2.INF else nearest

func _clear_enemies(include_dummy: bool, include_boss: bool) -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == dummy and not include_dummy:
			continue
		if enemy is EnemyBasic and enemy.enemy_data is BossData and not include_boss:
			continue
		enemy.queue_free()
	if include_dummy:
		dummy = null

func _clear_developer_targets() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if bool(enemy.get_meta("developer_target", false)):
			enemy.queue_free()

func trigger_projectile() -> Projectile:
	var projectile_weapon: WeaponData
	for weapon in DataLoader.weapons.values():
		if weapon is WeaponData and weapon.projectile_scene != null:
			projectile_weapon = weapon
			if weapon.required_fragment_ids.is_empty():
				break
	if projectile_weapon == null:
		# Character attacks own their attack pattern rather than registering a
		# projectile WeaponData.  Keep the Lab probe on the real WeaponManager
		# path with an isolated debug-only data object.
		projectile_weapon = WeaponData.new()
		projectile_weapon.id = "developer_projectile_probe"
		projectile_weapon.display_name = "Developer Projectile Probe"
		projectile_weapon.base_damage = 10.0
		projectile_weapon.attack_range = 320.0
		projectile_weapon.projectile_scene = PROJECTILE_SCENE
	var existing_projectiles := runtime_game.get_children().filter(func(child): return child is Projectile)
	var target := _ensure_dummy()
	player.weapon_manager.spawn_projectile(projectile_weapon, player.global_position, target.global_position)
	var spawned: Projectile
	for child in runtime_game.get_children():
		if child is Projectile and child not in existing_projectiles:
			spawned = child as Projectile
			spawned.add_to_group("projectiles")
			spawned.set_meta("developer_projectile", true)
			break
	_set_status("Real WeaponManager projectile spawned: %s" % projectile_weapon.id)
	return spawned

func clear_projectiles() -> void:
	for projectile in get_tree().get_nodes_in_group("projectiles"):
		projectile.queue_free()
	_set_status("All projectiles cleared")

# BOSS / REWARD ---------------------------------------------------------------
func spawn_selected_boss() -> Node:
	var boss_id := String(_boss_type.get_item_metadata(_boss_type.selected))
	var position := _safe_world_position(player.global_position + Vector2(300, 0))
	var boss := boss_spawner.debug_spawn_boss(boss_id, position)
	_set_status("Boss spawned: %s" % boss_id)
	return boss

func _current_boss() -> EnemyBasic:
	return boss_spawner.debug_get_current_boss() as EnemyBasic

func set_boss_hp_ratio(ratio: float) -> void:
	var boss := _current_boss()
	if boss == null:
		boss = spawn_selected_boss() as EnemyBasic
	if boss:
		boss.health_component.current_hp = boss.health_component.max_hp * clampf(ratio, 0.001, 1.0)
		boss.health_component.damaged.emit(0.0, boss.health_component.current_hp, boss.health_component.max_hp)
		_set_status("Boss HP -> %.1f%%" % (ratio * 100.0))

func kill_boss() -> void:
	var boss := _current_boss()
	if boss == null:
		return
	boss.health_component.current_hp = 1.0
	boss.health_component.apply_secondary_damage(1.0)
	_set_status("Boss death and real reward queue triggered")

func clear_boss() -> void:
	boss_spawner.debug_clear_boss()
	_set_status("Boss cleared without rewards")

func trigger_boss_strategy(strategy_name: String) -> void:
	var boss := _current_boss()
	if boss == null:
		boss = spawn_selected_boss() as EnemyBasic
	if boss == null:
		return
	if boss.boss_attack_component:
		boss.boss_attack_component.process_mode = Node.PROCESS_MODE_DISABLED
	var script := load(BOSS_STRATEGIES[strategy_name]) as Script
	var strategy := script.new() as BossAttackStrategy
	_set_status("Boss Strategy executing: %s" % strategy_name)
	await strategy.execute(boss, player)
	_set_status("Boss Strategy complete: %s" % strategy_name)

func apply_reward_preset(preset: String) -> void:
	element_combat.reset_runtime()
	match preset:
		"NO ELEMENT": GameManager.debug_force_element_state({})
		"ONE ELEMENT": GameManager.debug_force_element_state({"element_fire":1})
		"TWO ELEMENT": GameManager.debug_force_element_state({"element_fire":1, "element_lightning":1})
		"ONE MAX": GameManager.debug_force_element_state({"element_fire":3})
		"TWO MAX": GameManager.debug_force_element_state({"element_fire":3, "element_lightning":3})
		"FUSION ACTIVE": GameManager.debug_force_element_state({"element_fire":3, "element_lightning":3}, "plasma")
	_set_status("Reward preset: %s" % preset)

func open_boss_reward() -> void:
	fragment_select.show_choices("DEVELOPER：本番Element Reward Pool")
	_set_status("Real FragmentSelect opened from current build state")

# EQUIPMENT / LOOT ------------------------------------------------------------
func _equipment_selection() -> Dictionary:
	return {
		"template": String(_equipment_template.get_item_metadata(_equipment_template.selected)),
		"rarity": String(_equipment_rarity.get_item_metadata(_equipment_rarity.selected)),
	}

func _make_selected_equipment() -> EquipmentData:
	var selection := _equipment_selection()
	_selected_equipment = equipment_drop.debug_generate_equipment(selection["template"], selection["rarity"])
	return _selected_equipment

func equipment_drop_selected() -> GroundEquipmentItem:
	var item := _make_selected_equipment()
	var dropped := equipment_drop.debug_drop_equipment(item, player.global_position + Vector2(110, 0))
	_set_status("Equipment dropped: %s / %s" % [item.display_name, item.rarity] if item else "Equipment generation failed")
	return dropped

func equipment_add_selected() -> EquipmentData:
	var item := _make_selected_equipment()
	player.equipment_component.add_item(item)
	_set_status("Equipment added to real inventory")
	return item

func equipment_equip_selected() -> void:
	if _selected_equipment == null or _selected_equipment not in player.equipment_component.inventory:
		equipment_add_selected()
	var ok := player.equipment_component.equip(_selected_equipment)
	_set_status("Equip %s" % ["OK" if ok else "FAILED"])

func equipment_unequip_selected() -> void:
	if _selected_equipment:
		player.equipment_component.unequip(_selected_equipment.slot)
	_set_status("Unequip requested")

func equipment_remove_selected() -> void:
	if _selected_equipment == null:
		return
	if player.equipment_component.is_equipped(_selected_equipment):
		player.equipment_component.unequip(_selected_equipment.slot)
	var ok := player.equipment_component.remove_item(_selected_equipment)
	_set_status("Remove %s" % ["OK" if ok else "FAILED"])

func equipment_give_copies(count: int) -> void:
	var first: EquipmentData
	for _index in count:
		var item := _make_selected_equipment()
		player.equipment_component.add_item(item)
		if first == null:
			first = item
	_selected_equipment = first
	_set_status("Added %d merge copies" % count)

func equipment_give_rarity_materials(rarity: String) -> Array[EquipmentData]:
	var added: Array[EquipmentData] = []
	for template in equipment_drop.debug_get_templates():
		if String(template.get("rarity", "")) != rarity:
			continue
		var item := equipment_drop.debug_generate_equipment(String(template.get("id", "")), rarity)
		if item:
			player.equipment_component.add_item(item)
			added.append(item)
		if added.size() >= EquipmentMergeSystem.MATERIAL_COUNT:
			break
	_selected_equipment = added[0] if not added.is_empty() else null
	_set_status("%sの異なる装備を%d個追加" % [rarity.to_upper(), added.size()])
	return added

func open_equipment_merge_screen() -> void:
	var screen := runtime_game.get_node_or_null("EquipmentScreen") as EquipmentScreen
	if screen == null:
		_set_status("装備画面が見つかりません")
		return
	screen._open()
	screen._set_mode("merge")
	_set_status("3スロット合成画面を開きました")

func equipment_merge_selected() -> EquipmentData:
	if _selected_equipment == null:
		return null
	var merger := EquipmentMergeSystem.new()
	var result := merger.merge(player.equipment_component, _selected_equipment)
	if result:
		_selected_equipment = result
	_set_status("Merge -> %s" % [result.rarity.to_upper() if result else "not enough safe copies"])
	return result

func equipment_clear() -> void:
	player.equipment_component.clear_all()
	_selected_equipment = null
	clear_ground_loot()
	_set_status("Inventory / equipped / ground loot cleared")

func drop_loot_count(count: int) -> void:
	for index in count:
		var item := _make_selected_equipment()
		equipment_drop.debug_drop_equipment(item, player.global_position + Vector2(100 + (index % 5) * 42, -80 + (index / 5) * 54))
	_set_status("Dropped %d equipment items" % count)

func drop_all_rarities() -> void:
	for index in RARITIES.size():
		var selection := _equipment_selection()
		var item := equipment_drop.debug_generate_equipment(selection["template"], RARITIES[index])
		equipment_drop.debug_drop_equipment(item, player.global_position + Vector2(90 + index * 58, 50))
	_set_status("Dropped all five rarities")

func clear_ground_loot() -> void:
	for item in get_tree().get_nodes_in_group("ground_equipment"):
		item.queue_free()

func loot_preset_clean() -> void:
	_clear_enemies(false, false)
	clear_ground_loot()
	drop_all_rarities()
	_set_status("LOOT CLEAN: five rarities, no combat clutter")

func loot_preset_combat() -> void:
	clear_ground_loot()
	spawn_enemies(100, "Around Player", _selected_enemy_id())
	drop_loot_count(10)
	_set_status("LOOT COMBAT: 100 enemies + 10 drops")

func loot_preset_stress() -> void:
	clear_ground_loot()
	spawn_enemies(100, "Cluster", _selected_enemy_id())
	for _round in 4:
		drop_all_rarities()
	_set_status("LOOT STRESS: 100 enemies + 20 rarity beams")

func _refresh_equipment_summary() -> void:
	if _equipment_summary == null or player == null:
		return
	var component := player.equipment_component
	var equipped_lines: Array[String] = []
	for slot in EquipmentComponent.SLOTS:
		var item := component.get_equipped(slot)
		if item:
			equipped_lines.append("%s: %s" % [slot, item.display_name])
	_equipment_summary.text = "[b]INVENTORY[/b] %d\n[b]EQUIPPED[/b]\n%s\nGround Loot %d" % [component.inventory.size(), "\n".join(equipped_lines) if not equipped_lines.is_empty() else "None", get_tree().get_nodes_in_group("ground_equipment").size()]

# RESET / STATUS --------------------------------------------------------------
func reset_lab_state() -> void:
	stop_all_previews()
	clear_boss()
	_clear_enemies(true, true)
	clear_projectiles()
	clear_ground_loot()
	for vfx_node in get_tree().get_nodes_in_group("transient_vfx"):
		vfx_node.queue_free()
	player.equipment_component.clear_all()
	GameManager.debug_force_element_state({})
	element_combat.reset_runtime()
	concept_system.reset_runtime()
	concept_system.set_active(true)
	combo_system.reset_combo()
	combo_system.set_active(false)
	reset_player()
	reset_damage_meter()
	await get_tree().process_frame
	spawn_dummy()
	_set_status("Lab state reset; real game scene retained")

func select_tab(tab_name: String) -> bool:
	for index in _tabs.get_tab_count():
		if _tabs.get_tab_title(index) == tab_name:
			_tabs.current_tab = index
			return true
	return false

func _refresh_state_text() -> void:
	if _state_label == null or player == null:
		return
	var parts: Array[String] = []
	for element_id in GameManager.get_active_element_ids():
		parts.append("%s Lv%d" % [element_id.trim_prefix("element_").to_upper(), GameManager.get_element_stack(element_id)])
	var fusion := GameManager.active_fusion_id.to_upper() if GameManager.active_fusion_id != "" else "NONE"
	var concept_parts: Array[String] = []
	if concept_system:
		for chain_index in 2:
			var chain := concept_system.get_chain(chain_index)
			concept_parts.append("%s>%s>%s" % [String(chain.get("trigger", "-")).trim_prefix("trigger_"), String(chain.get("skill", "-")).trim_prefix("skill_"), String(chain.get("modifier", "-")).trim_prefix("modifier_")])
	_state_label.text = "[b]BUILD[/b] %s   SLOT %d/2\n[b]FUSION[/b] %s\n[b]CONCEPT[/b] %s\n[b]FIELD[/b] Enemy %d  Projectile %d  VFX %d" % [" + ".join(parts) if not parts.is_empty() else "NONE", parts.size(), fusion, " | ".join(concept_parts), get_tree().get_nodes_in_group("enemies").size(), get_tree().get_nodes_in_group("projectiles").size(), get_tree().get_nodes_in_group("transient_vfx").size()]

func _set_status(message: String) -> void:
	if _status_label:
		_status_label.text = message

func _element_color(element_id: String) -> Color:
	var data := DataLoader.element_vfx_effects.get(element_id) as ElementVFXData
	return data.attack_tint if data else Color.WHITE
