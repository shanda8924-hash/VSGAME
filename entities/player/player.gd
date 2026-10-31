extends Entity
class_name Player
## プレイヤー本体。
## 【操作方針】PC(Steam)向け: キーボード(矢印キー/WASD)またはゲームパッドの
## スティック/十字キーで移動する。通常攻撃は自動、Spaceは職業固有スキル。

@onready var weapon_manager: WeaponManagerComponent = $WeaponManagerComponent
@onready var experience_component: ExperienceComponent = $ExperienceComponent
@onready var upgrades_component: PlayerUpgradesComponent = $PlayerUpgradesComponent
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var camera: Camera2D = $Camera2D
@onready var active_skill_component: ActiveSkillComponent = $ActiveSkillComponent
@onready var equipment_component: EquipmentComponent = $EquipmentComponent

## 逃走だけで安全を確保できる速度差を縮める。職業間の相対差はCharacterDataのまま維持する。
const MOVE_SPEED_MULTIPLIER := 0.90

var dodge_remaining := 0.0
var dodge_cooldown := 0.0
var dodge_direction := Vector2.RIGHT
var _perfect_dodge_epoch := 0
var _counter_target: WeakRef
var _counter_return_enemy: WeakRef
var _counter_ready_until := 0
var _counter_return_target := Vector2.ZERO
var _counter_returning := false
var _counter_return_time := 0.0
var _counter_afterimage_time := 0.0
var _is_dead: bool = false
## charge_dash等、攻撃パターンが突進中に一時的にプレイヤーの移動入力を
## 無効化するためのロック(EnemyBasicのBossAttackStrategy用ロックと同じ考え方)。
var _movement_locked_by_attack: bool = false
var _facing_direction: Vector2 = Vector2.RIGHT
var _next_attack_animation_speed: float = 1.0
var next_attack_animation_variant := 0
var _nearby_ground_equipment: Array[GroundEquipmentItem] = []
var _nearby_interactables: Array[Node] = []
var floating_weapons: FloatingWeapons

func _ready() -> void:
	for action in {"primary_attack": KEY_J, "dodge": KEY_K}:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = {"primary_attack": KEY_J, "dodge": KEY_K}[action]
		if not InputMap.action_has_event(action, key): InputMap.action_add_event(action, key)
	_apply_character_data()
	health_component.died.connect(_on_died)
	health_component.damaged.connect(_on_damaged)
	weapon_manager.weapon_fired.connect(_on_weapon_fired)
	floating_weapons = preload("res://entities/player/floating_weapons.gd").new()
	floating_weapons.name = "FloatingWeapons"
	add_child(floating_weapons)
	floating_weapons.bind_player(self)
	var survival_effects := preload("res://entities/player/survival_upgrade_effects.gd").new()
	survival_effects.name = "SurvivalUpgradeEffects"
	add_child(survival_effects)
	EventBus.player_leveled_up.connect(_on_leveled_up)
	EventBus.enemy_physical_damage_dealt.connect(_on_enemy_physical_damage)

## ホーム画面で選んだ職業(GameManager.selected_character_id)に応じて、
## 見た目(AnimatedSprite2D)とステータス(HP/移動速度)を実行時に差し替える。
func _apply_character_data() -> void:
	var character_data: CharacterData = DataLoader.characters.get(GameManager.selected_character_id)
	if character_data == null:
		return
	health_component.max_hp = character_data.max_hp
	health_component.current_hp = character_data.max_hp
	movement_component.base_speed = character_data.move_speed * MOVE_SPEED_MULTIPLIER
	if character_data.sprite_folder != "":
		var frames := SpriteSheetBuilder.build_sprite_frames(character_data.sprite_folder)
		if frames:
			animated_sprite.sprite_frames = frames
	# 職業固有パッシブ(被ダメージ軽減・会心率・攻撃力倍率・獲得経験値倍率)を、
	# 強化オプション/アイテムと同じ蓄積値へ初期値として合成する(詳細はPlayerUpgradesComponent参照)。
	upgrades_component.apply_character_passives(character_data)

## Game.gdがGameManager.start_run()(ダンジョン生成)の直後に呼び出す。
## カメラがダンジョンの外側(空白の壁の外)を映さないよう、生成したマップの
## ワールド座標範囲でCamera2Dのlimitを設定する。
func setup_camera_limits(map: DungeonMap) -> void:
	if map == null:
		return
	if map.get_meta("floor_only", false):
		camera.limit_left = -10000000
		camera.limit_top = -10000000
		camera.limit_right = 10000000
		camera.limit_bottom = 10000000
		camera.zoom = Vector2.ONE
		camera.offset = Vector2.ZERO
		camera.reset_smoothing()
		return
	var min_world := map.grid_to_world(map.get_min_coords())
	var max_world := map.grid_to_world(map.get_max_coords() + Vector2i.ONE)
	camera.limit_left = int(min_world.x)
	camera.limit_top = int(min_world.y) - (64 if map.get_meta("isolated_room", false) else 0)
	camera.limit_right = int(max_world.x)
	camera.limit_bottom = int(max_world.y)
	# A compact room has generous framing instead of a scrolling empty maze.
	camera.zoom = Vector2.ONE * (1.15 if map.get_meta("isolated_room", false) else 1.5)
	# Leave the wall-mounted entrance clear of the top-centre objective HUD.
	camera.offset = Vector2(0, -64) if map.get_meta("isolated_room", false) else Vector2.ZERO
	camera.reset_smoothing()

func _process(_delta: float) -> void:
	if _is_dead:
		return
	if Input.is_action_just_pressed("interact"):
		if not _try_interact_nearest():
			_pick_up_nearest_equipment()
	if Input.is_action_just_pressed("dodge") and try_dodge():
		return
	if dodge_remaining > 0.0:
		return
	if _counter_ready_until > Time.get_ticks_msec() and Input.is_action_just_pressed("primary_attack"):
		_begin_counter_return()
	if _counter_returning:
		return

	if _movement_locked_by_attack:
		return
	# ui_left/right/up/downは矢印キー・WASD・ゲームパッドの十字キー/左スティックに
	# 対応済み(GameManager._ready()でWASDバインドを追加登録している)。
	movement_component.direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if movement_component.direction.length_squared() > 0.01:
		_facing_direction = movement_component.direction.normalized()
	if Input.is_action_just_pressed("active_skill"):
		active_skill_component.try_activate()

## Area2Dへ入った宝箱などを共通interact Actionで操作するための最小共通窓口。
## 対象Nodeはcan_interact(player)とinteract(player)を実装すれば再利用できる。
func register_interactable(interactable: Node) -> void:
	if is_instance_valid(interactable) and interactable not in _nearby_interactables:
		_nearby_interactables.append(interactable)

func unregister_interactable(interactable: Node) -> void:
	_nearby_interactables.erase(interactable)

func _try_interact_nearest() -> bool:
	_nearby_interactables = _nearby_interactables.filter(func(target): return is_instance_valid(target))
	_nearby_interactables.sort_custom(func(a, b):
		var a_node := a as Node2D
		var b_node := b as Node2D
		var a_distance := global_position.distance_squared_to(a_node.global_position) if a_node else INF
		var b_distance := global_position.distance_squared_to(b_node.global_position) if b_node else INF
		return a_distance < b_distance
	)
	for target in _nearby_interactables:
		if not target.has_method("interact"):
			continue
		if target.has_method("can_interact") and not bool(target.call("can_interact", self)):
			continue
		if bool(target.call("interact", self)):
			return true
	return false

func register_ground_equipment(item: GroundEquipmentItem) -> void:
	if item not in _nearby_ground_equipment:
		_nearby_ground_equipment.append(item)

func unregister_ground_equipment(item: GroundEquipmentItem) -> void:
	_nearby_ground_equipment.erase(item)

func _pick_up_nearest_equipment() -> void:
	_nearby_ground_equipment = _nearby_ground_equipment.filter(func(item): return is_instance_valid(item))
	if _nearby_ground_equipment.is_empty():
		return
	_nearby_ground_equipment.sort_custom(func(a, b): return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	_nearby_ground_equipment[0].collect(self)

func get_facing_direction() -> Vector2:
	return _facing_direction

func face_direction(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return
	_facing_direction = direction.normalized()
	if absf(_facing_direction.x) > 0.01:
		animated_sprite.flip_h = _facing_direction.x < 0.0

## charge_dash攻撃パターンが突進中、通常の入力移動を一時的に止めて
## MovementComponentを直接制御できるようにする(EnemyBasic.set_movement_lockedと同じ役割)。
func set_movement_locked(locked: bool) -> void:
	_movement_locked_by_attack = locked
	if locked:
		movement_component.direction = Vector2.ZERO

func set_next_attack_animation_speed(speed_multiplier: float) -> void:
	_next_attack_animation_speed = maxf(speed_multiplier, 0.1)

func _on_damaged(amount: float, current_hp: float, max_hp: float) -> void:
	EventBus.player_damaged.emit(amount, current_hp, max_hp)

## レベルアップの瞬間にHPを全回復させる(次の強敵に備えられる安心感のため)。
## アイテムのmax_hp_bonus等でmax_hpが動的に増減していても、常にその時点のmax_hpまで
## 満タンにするだけでよい。
func _on_leveled_up(_new_level: int) -> void:
	if GameManager.map_mode_active:
		# MAPでは回復Drop/祭壇/宝箱を探索する意味を残し、Level Upは小回復に留める。
		health_component.heal(health_component.max_hp * 0.12)
	else:
		health_component.current_hp = health_component.max_hp
		health_component.damaged.emit(0.0, health_component.current_hp, health_component.max_hp)

func _on_weapon_fired() -> void:
	if animation_component:
		animation_component.play_attack(next_attack_animation_variant if next_attack_animation_variant > 0 else randi_range(1, 3), _next_attack_animation_speed)
	next_attack_animation_variant = 0
	_next_attack_animation_speed = 1.0

## 死亡演出(死亡アニメーション)を最後まで見せてからリザルト画面へ遷移させたいので、
## GameManager.end_run()はアニメーション再生完了(死亡)を待ってから呼ぶ。
func _on_died() -> void:
	_is_dead = true
	_counter_ready_until = 0
	_counter_returning = false
	_counter_target = null
	_counter_return_enemy = null
	var effects := get_tree().get_first_node_in_group("screen_effects") as ScreenEffects
	if effects: effects.restore_runtime_state()
	Engine.time_scale = 1.0
	movement_component.direction = Vector2.ZERO
	if animation_component:
		animation_component.death_finished.connect(GameManager.end_run, CONNECT_ONE_SHOT)
	else:
		GameManager.end_run()

func _on_enemy_physical_damage(amount: float, _position: Vector2, _critical: bool) -> void:
	_apply_treasure_lifesteal(amount)


func _apply_treasure_lifesteal(amount: float) -> void:
	if _is_dead or upgrades_component.lifesteal_percent <= 0.0 or amount <= 0.0:
		return
	health_component.heal(minf(amount * upgrades_component.lifesteal_percent, 3.0))

func try_dodge() -> bool:
	if _is_dead or dodge_cooldown > 0.0 or get_tree().paused or GameManager.run_state != GameManager.RunState.PLAYING:
		return false
	var class_dash := weapon_manager._class_attack as ChargeDashAttack
	if _movement_locked_by_attack and not active_skill_component._swordsman_iai_running and not (class_dash and class_dash.running):
		return false
	var precise_target := _get_precise_attack_target()
	_counter_ready_until = 0
	_counter_target = null
	_counter_returning = false
	weapon_manager.cancel_current_attack()
	active_skill_component.cancel_for_dodge()
	dodge_direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if dodge_direction.is_zero_approx(): dodge_direction = get_facing_direction()
	dodge_remaining = 0.20
	dodge_cooldown = 0.85
	health_component.dodge_iframe_remaining = 0.12
	movement_component.direction = Vector2.ZERO
	# 5分サバイバルではジャスト回避→反撃を終盤ボス戦だけに限定する（D3、2026-10-31）。
	if precise_target and (not GameManager.survival_mode_active or get_tree().get_first_node_in_group("survival_boss") != null):
		_start_perfect_dodge(precise_target)
	return true

func _has_precise_attack_window() -> bool:
	return _get_precise_attack_target() != null

func _get_precise_attack_target() -> EnemyBasic:
	for candidate in get_tree().get_nodes_in_group("enemies"):
		var enemy := candidate as EnemyBasic
		if enemy == null or enemy._is_dead or enemy.ai_component.target != self:
			continue
		if enemy._normal_attack_state == EnemyBasic.NormalAttackState.WINDUP:
			if enemy._normal_attack_timer <= 0.12 and enemy.global_position.distance_to(global_position) <= enemy._normal_reach() + 18.0:
				return enemy
		var special := enemy.strong_attack
		if special and bool(special.get("active")) and special.has_method("time_until_next_hit"):
			var to_hit := float(special.call("time_until_next_hit"))
			if to_hit >= 0.0 and to_hit <= 0.12 and enemy.global_position.distance_to(global_position) <= 90.0 and bool(special.call("_clear_path", self)):
				return enemy
	return null

func _start_perfect_dodge(target: EnemyBasic) -> void:
	_perfect_dodge_epoch += 1
	var epoch := _perfect_dodge_epoch
	_counter_target = weakref(target)
	_counter_ready_until = Time.get_ticks_msec() + 1500
	weapon_manager.counter_strikes_remaining = 0
	ImportedBurstVFX.spawn(get_parent() as Node2D, global_position + Vector2(0, -12), "dodge")
	AudioManager.play_sfx("fusion_success")
	var hud := get_parent().get_node_or_null("HUD") as HUD
	if hud: hud.set_room_message("ジャスト回避！　[J] で反撃")
	await get_tree().create_timer(1.5, true, false, true).timeout
	if is_instance_valid(self) and epoch == _perfect_dodge_epoch:
		_counter_ready_until = 0
		_counter_target = null

func _begin_counter_return() -> void:
	_counter_ready_until = 0
	var target := _counter_target.get_ref() as EnemyBasic if _counter_target else null
	_counter_target = null
	if target == null or target._is_dead or global_position.distance_to(target.global_position) > 180.0:
		weapon_manager.begin_counter_haste()
		weapon_manager.trigger_counter_attack()
		return
	_counter_return_enemy = weakref(target)
	var side := (global_position - target.global_position).normalized().rotated(PI * 0.5)
	if side.is_zero_approx():
		side = dodge_direction.rotated(PI * 0.5).normalized()
	var left := target.global_position + side * 54.0
	var right := target.global_position - side * 54.0
	_counter_return_target = left if global_position.distance_squared_to(left) < global_position.distance_squared_to(right) else right
	_counter_returning = true
	_counter_return_time = 0.14
	_counter_afterimage_time = 0.0
	movement_component.direction = Vector2.ZERO
	health_component.dodge_iframe_remaining = maxf(health_component.dodge_iframe_remaining, 0.14)
	_spawn_counter_afterimage()

func _spawn_counter_afterimage() -> void:
	var afterimage := CharacterAfterimage.new()
	GameManager.get_runtime_world(self).add_child(afterimage)
	afterimage.setup(animated_sprite, Color(0.17, 0.3, 0.48, 0.42), 0.2)

func _finish_counter_return() -> void:
	_counter_returning = false
	var target := _counter_return_enemy.get_ref() as EnemyBasic if _counter_return_enemy else null
	_counter_return_enemy = null
	if target and global_position.distance_to(target.global_position) < 90.0:
		face_direction(target.global_position - global_position)
	weapon_manager.begin_counter_haste()
	weapon_manager.trigger_counter_attack()

func _physics_process(delta: float) -> void:
	dodge_cooldown = maxf(0.0, dodge_cooldown - delta)
	if _counter_returning:
		_counter_return_time -= delta
		_counter_afterimage_time -= delta
		if _counter_afterimage_time <= 0.0:
			_spawn_counter_afterimage()
			_counter_afterimage_time = 0.045
		var motion := _counter_return_target - global_position
		if motion.length() > 2.0 and _counter_return_time > 0.0:
			move_and_collide(motion.limit_length(650.0 * delta))
		else:
			_finish_counter_return()
		return
	if dodge_remaining > 0.0:
		move_and_collide(dodge_direction * 400.0 * minf(delta, dodge_remaining))
		dodge_remaining = maxf(0.0, dodge_remaining - delta)
		return
	super._physics_process(delta)
