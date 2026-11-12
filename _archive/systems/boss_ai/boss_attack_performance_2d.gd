extends Node2D
## ミノタウロスの予備動作・全身薙ぎ払い・剣撃を同じ時計で同期する2D表示担当。

const CLEAVE := preload("res://systems/boss_ai/boss_cleave_slash_2d.gd")
const RECOVERY := 0.62

var boss: EnemyBasic
var pattern := ""
var animation_name := "attack1"
var strike_frame := 5
var windup_duration := 1.05
var elapsed := 0.0
var stage := "windup"
var origin := Vector2.ZERO
var direction := Vector2.RIGHT
var radius := 145.0
var half_angle := deg_to_rad(70.0)
var slash: Node2D
var reverse_sweep := false
var _animation_was_processing := false
var _released := false
var _pose_frame := 0

func setup(actor: EnemyBasic, attack: String, zone: Node2D, tell: float) -> void:
	boss = actor
	pattern = attack
	origin = zone.origin
	direction = zone.direction
	radius = zone.radius
	half_angle = zone.half_angle
	windup_duration = tell
	animation_name = "attack3" if pattern == "ring" else "attack1"
	strike_frame = 4 if pattern == "ring" else 5
	if pattern == "cleave":
		_install_cleave_frames()
		animation_name = "cleave_side"
		if absf(direction.y) > absf(direction.x):
			animation_name = "cleave_back" if direction.y < 0.0 else "cleave_front"
		reverse_sweep = animation_name == "cleave_side" and direction.x < 0.0
		strike_frame = 3

func _install_cleave_frames() -> void:
	if boss.animated_sprite.sprite_frames.has_animation("cleave_side"):
		return
	var frames := boss.animated_sprite.sprite_frames.duplicate() as SpriteFrames
	for view: String in ["side", "back", "front"]:
		var texture := load("res://assets/sprites/boss/Minotaur/hd2d/source_edit/minotaur_cleave_%s_8f.png" % view) as Texture2D
		var clip := "cleave_" + view
		frames.add_animation(clip)
		frames.set_animation_loop(clip, false)
		frames.set_animation_speed(clip, 16.0)
		for index in 8:
			var frame := AtlasTexture.new()
			frame.atlas = texture
			frame.region = Rect2(index * 100, 0, 100, 100)
			frames.add_frame(clip, frame)
	boss.animated_sprite.sprite_frames = frames

func _ready() -> void:
	add_to_group("boss_attack_transient")
	process_priority = -20
	_animation_was_processing = boss.animation_component.is_processing()
	boss.animation_component.set_process(false)
	boss.health_component.died.connect(cancel, CONNECT_ONE_SHOT)
	boss.health_component.damaged.connect(_keep_attack_pose)
	_pose(0)

func _process(delta: float) -> void:
	if not _boss_alive():
		cancel()
		return
	elapsed += delta
	if stage == "windup":
		var windup_progress := clampf(elapsed / (windup_duration * 0.72), 0.0, 1.0)
		_pose(mini(int(windup_progress * strike_frame), strike_frame - 1))
	elif stage != "sweep":
		var count := boss.animated_sprite.sprite_frames.get_frame_count(animation_name)
		_pose(mini((6 if pattern == "cleave" else strike_frame) + int(elapsed / 0.085), count - 1))
		if elapsed >= RECOVERY:
			cancel()

func strike() -> void:
	if _released or not _boss_alive():
		return
	stage = "strike"
	elapsed = 0.0
	_pose(strike_frame)
	if pattern == "cleave":
		stage = "sweep"
		slash = CLEAVE.new()
		slash.origin = origin
		slash.direction = direction
		slash.radius = radius
		slash.half_angle = half_angle
		slash.reverse_sweep = reverse_sweep
		GameManager.get_runtime_world(boss).add_child(slash)
		set_sweep_progress(0.0)

func set_sweep_progress(value: float) -> void:
	if _released or stage != "sweep":
		return
	_pose(3 + mini(2, int(clampf(value, 0.0, 1.0) * 3.0)))
	if is_instance_valid(slash):
		slash.set_sweep_progress(value)

func finish_sweep() -> void:
	if _released:
		return
	stage = "strike"
	elapsed = 0.0
	if is_instance_valid(slash):
		slash.finish_sweep()

func _pose(frame_index: int) -> void:
	_pose_frame = frame_index
	var sprite := boss.animated_sprite
	sprite.animation = animation_name
	sprite.pause()
	sprite.frame = frame_index
	sprite.flip_h = direction.x < 0.0 if animation_name not in ["cleave_front", "cleave_back"] else false

func _keep_attack_pose(_amount: float, _hp: float, _max_hp: float) -> void:
	if not _released and _boss_alive():
		_pose(_pose_frame)

func _boss_alive() -> bool:
	return is_instance_valid(boss) and not boss.is_queued_for_deletion() and boss.health_component.current_hp > 0.0

func cancel() -> void:
	_release_pose()
	set_process(false)
	hide()
	queue_free()

func _exit_tree() -> void:
	_release_pose()

func _release_pose() -> void:
	if _released:
		return
	_released = true
	if not is_instance_valid(boss) or boss.is_queued_for_deletion():
		return
	if boss.health_component.died.is_connected(cancel):
		boss.health_component.died.disconnect(cancel)
	if boss.health_component.damaged.is_connected(_keep_attack_pose):
		boss.health_component.damaged.disconnect(_keep_attack_pose)
	boss.animation_component.set_process(_animation_was_processing)
	if boss.health_component.current_hp > 0.0:
		boss.animated_sprite.speed_scale = 1.0
		boss.animated_sprite.play("idle")
