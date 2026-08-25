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

var _is_dead: bool = false
## charge_dash等、攻撃パターンが突進中に一時的にプレイヤーの移動入力を
## 無効化するためのロック(EnemyBasicのBossAttackStrategy用ロックと同じ考え方)。
var _movement_locked_by_attack: bool = false
var _facing_direction: Vector2 = Vector2.RIGHT
var _next_attack_animation_speed: float = 1.0
var _nearby_ground_equipment: Array[GroundEquipmentItem] = []
var _nearby_interactables: Array[Node] = []

func _ready() -> void:
	_apply_character_data()
	health_component.died.connect(_on_died)
	health_component.damaged.connect(_on_damaged)
	weapon_manager.weapon_fired.connect(_on_weapon_fired)
	EventBus.player_leveled_up.connect(_on_leveled_up)
	EventBus.enemy_physical_damage_dealt.connect(_on_enemy_physical_damage)
	EventBus.element_damage_dealt.connect(_on_enemy_element_damage)

## ホーム画面で選んだ職業(GameManager.selected_character_id)に応じて、
## 見た目(AnimatedSprite2D)とステータス(HP/移動速度)を実行時に差し替える。
func _apply_character_data() -> void:
	var character_data: CharacterData = DataLoader.characters.get(GameManager.selected_character_id)
	if character_data == null:
		return
	health_component.max_hp = character_data.max_hp
	health_component.current_hp = character_data.max_hp
	movement_component.base_speed = character_data.move_speed
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
	var min_world := map.grid_to_world(map.get_min_coords())
	var max_world := map.grid_to_world(map.get_max_coords() + Vector2i.ONE)
	camera.limit_left = int(min_world.x)
	camera.limit_top = int(min_world.y)
	camera.limit_right = int(max_world.x)
	camera.limit_bottom = int(max_world.y)

func _process(_delta: float) -> void:
	if _is_dead:
		return
	if Input.is_action_just_pressed("interact"):
		if not _try_interact_nearest():
			_pick_up_nearest_equipment()
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
	health_component.current_hp = health_component.max_hp
	health_component.damaged.emit(0.0, health_component.current_hp, health_component.max_hp)

func _on_weapon_fired() -> void:
	if animation_component:
		animation_component.play_attack(randi_range(1, 3), _next_attack_animation_speed)
	_next_attack_animation_speed = 1.0

## 死亡演出(死亡アニメーション)を最後まで見せてからリザルト画面へ遷移させたいので、
## GameManager.end_run()はアニメーション再生完了(死亡)を待ってから呼ぶ。
func _on_died() -> void:
	_is_dead = true
	movement_component.direction = Vector2.ZERO
	if animation_component:
		animation_component.death_finished.connect(GameManager.end_run, CONNECT_ONE_SHOT)
	else:
		GameManager.end_run()

func _on_enemy_physical_damage(amount: float, _position: Vector2, _critical: bool) -> void:
	_apply_treasure_lifesteal(amount)

func _on_enemy_element_damage(amount: float, _position: Vector2, _element_id: String, _stack: int, _chain: int) -> void:
	_apply_treasure_lifesteal(amount)

func _apply_treasure_lifesteal(amount: float) -> void:
	if _is_dead or upgrades_component.lifesteal_percent <= 0.0 or amount <= 0.0:
		return
	health_component.heal(minf(amount * upgrades_component.lifesteal_percent, 3.0))
