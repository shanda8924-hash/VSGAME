extends CanvasLayer
class_name MobileControls

## Landscape touch controls. Only the local finger is released; keyboard/gamepad actions remain usable.
const DIRECTIONS := ["ui_left", "ui_right", "ui_up", "ui_down"]
var _stick: Control
var _knob: Panel
var _finger := -1
var _pressed: Dictionary = {}
var _button_pressed: Dictionary = {}
var _enabled := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_enabled = DisplayServer.is_touchscreen_available() or "--touch-preview" in OS.get_cmdline_user_args()
	visible = _enabled
	if not visible:
		return
	layer = 70
	_build()

func _build() -> void:
	_stick = Control.new()
	_stick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_stick.offset_left = 34
	_stick.offset_right = 238
	_stick.offset_top = -240
	_stick.offset_bottom = -36
	_stick.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_stick)
	var base := Panel.new()
	base.add_theme_stylebox_override("panel", _round_style(Color(0.04, 0.10, 0.16, 0.62), Color(0.47, 0.72, 0.75, 0.60), 102))
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick.add_child(base)
	_knob = Panel.new()
	_knob.add_theme_stylebox_override("panel", _round_style(Color(0.34, 0.66, 0.72, 0.80), Color(0.73, 0.91, 0.92, 0.88), 36))
	_knob.size = Vector2(72, 72)
	_knob.position = Vector2(66, 66)
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick.add_child(_knob)
	_stick.gui_input.connect(_on_stick_input)
	_add_button("回避", "dodge", -280, -205)
	_add_button("技", "active_skill", -175, -290)
	_add_button("反撃", "primary_attack", -385, -120)
	_add_button("調べる", "interact", -175, -115, 116)
	_add_button("装備", "character_screen", -120, -405, 104)
	_add_top_button("停止", "ui_cancel", true)
	_add_top_button("地図", "", false)

func _round_style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(radius)
	return style

func _process(_delta: float) -> void:
	if _enabled:
		var can_control := GameManager.active_modal_count == 0 and GameManager.run_state == GameManager.RunState.PLAYING
		if not can_control and visible:
			_release_stick()
			for action in _button_pressed:
				Input.action_release(action)
			_button_pressed.clear()
		visible = can_control

func _add_top_button(title: String, action: String, on_right: bool) -> void:
	var button := Button.new()
	button.text = title
	button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT if on_right else Control.PRESET_TOP_LEFT)
	button.offset_left = -112 if on_right else 28
	button.offset_right = -28 if on_right else 112
	button.offset_top = 232
	button.offset_bottom = 294
	button.add_theme_font_size_override("font_size", 18)
	button.focus_mode = Control.FOCUS_NONE
	add_child(button)
	PixelUIStyle.apply_button(button)
	button.modulate.a = 0.90
	if action == "":
		button.pressed.connect(func():
			var map_ui := get_tree().get_first_node_in_group("map_overlay") as ExplorationMapOverlay
			if map_ui: map_ui.toggle_map()
		)
	else:
		_bind_action_button(button, action)

func _add_button(title: String, action: String, x: float, y: float, width: float = 92) -> void:
	var button := Button.new()
	button.text = title
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	button.offset_left = x
	button.offset_right = x + width
	button.offset_top = y
	button.offset_bottom = y + 82
	button.add_theme_font_size_override("font_size", 22)
	button.focus_mode = Control.FOCUS_NONE
	add_child(button)
	PixelUIStyle.apply_button(button)
	button.modulate.a = 0.90
	_bind_action_button(button, action)

func _bind_action_button(button: Button, action: String) -> void:
	button.button_down.connect(func():
		_button_pressed[action] = true
		Input.action_press(action)
	)
	button.button_up.connect(func():
		_button_pressed.erase(action)
		Input.action_release(action)
	)

func _on_stick_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _finger < 0:
			_finger = event.index
			_update_stick(event.position)
		elif not event.pressed and event.index == _finger:
			_finger = -1
			_release_stick()
	elif event is InputEventScreenDrag and event.index == _finger:
		_update_stick(event.position)
	elif event is InputEventMouseButton:
		if event.pressed:
			_finger = -2
			_update_stick(event.position)
		elif _finger == -2:
			_finger = -1
			_release_stick()
	elif event is InputEventMouseMotion and _finger == -2:
		_update_stick(event.position)

func _update_stick(local_position: Vector2) -> void:
	var vector := (local_position - _stick.size * 0.5) / 72.0
	vector = vector.limit_length(1.0)
	_knob.position = _stick.size * 0.5 + vector * 65.0 - _knob.size * 0.5
	var values := [-vector.x, vector.x, -vector.y, vector.y]
	for index in DIRECTIONS.size():
		var action: String = DIRECTIONS[index]
		var strength: float = maxf(values[index], 0.0)
		if strength > 0.15:
			Input.action_press(action, strength)
			_pressed[action] = true
		elif _pressed.has(action):
			Input.action_release(action)
			_pressed.erase(action)

func _release_stick() -> void:
	_finger = -1
	_knob.position = _stick.size * 0.5 - _knob.size * 0.5
	for action in _pressed:
		Input.action_release(action)
	_pressed.clear()

func _exit_tree() -> void:
	for action in _pressed:
		Input.action_release(action)
	for action in _button_pressed:
		Input.action_release(action)
