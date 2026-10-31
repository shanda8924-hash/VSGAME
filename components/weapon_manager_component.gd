extends Node
class_name WeaponManagerComponent
## 職業通常攻撃と欠片合成武器の自動攻撃を統括する。

signal weapon_fired
signal equipment_attack_fired
var equipment_attack = preload("res://systems/equipment_auto_attack.gd").new()
signal weapon_added(weapon_data: WeaponData)
signal sector_style_changed()
## 実際の職業通常攻撃開始時に1回だけ発火し、AttackVFXManagerがPixel Animationを再生する。
signal attack_vfx_requested(character_data: CharacterData, origin: Vector2, direction: Vector2)
## 職業専用強化のability_level(19.8/19.9参照)が変わるたびに通知する。
## HUD/天賦図の「5つの丸印」段階表示(ui/common/ability_stage_dots.gd)が
## 購読する。キャラクターの経験値(ExperienceComponent)とは別の値・別の
## シグナルであることに注意(2026年8月、EXPゲージから完全分離するために追加)。
signal class_ability_level_changed(new_level: int)

## 「攻撃は自動」を開始直後から成立させるための初期装備武器(任意)。
## 欠片合成で手に入る武器と違い、最初から持っている前提の武器なのでここで直接指定する。
@export var starting_weapon_id: String = ""

var _weapon_instances: Array[WeaponInstance] = []
var sector_arc_width_level := 0
var sector_pierce_level := 0
var sector_chain_level := 0
var sector_follow_up_level := 0
var _sector_style_next := 0

func grant_sector_style() -> void:
	var melee := _character_data and _character_data.attack_pattern_id in ["melee_arc", "wide_cleave", "charge_dash"]
	if melee:
		if _sector_style_next % 2 == 0:
			sector_arc_width_level = mini(sector_arc_width_level + 1, 3)
		else:
			sector_follow_up_level = mini(sector_follow_up_level + 1, 2)
	else:
		match _sector_style_next % 3:
			0: sector_pierce_level = mini(sector_pierce_level + 1, 2)
			1: sector_chain_level = mini(sector_chain_level + 1, 2)
			2: sector_follow_up_level = mini(sector_follow_up_level + 1, 2)
	_sector_style_next += 1
	sector_style_changed.emit()

func get_sector_style_summary() -> String:
	var upgrades := get_owner_upgrades()
	return "範囲%d  貫通%d  連鎖%d  追撃%d" % [sector_arc_width_level, sector_pierce_level, sector_chain_level + (upgrades.get_survival_rank("survival_chain") if upgrades else 0), sector_follow_up_level + (upgrades.get_survival_rank("survival_echo") if upgrades else 0)]

## 職業ごとの自動攻撃パターン(CharacterData.attack_pattern_id、systems/attack_patterns/参照)。
## "single_shot"(Soldier)は既存のWeaponInstance(欠片合成武器)のみで完結するため、
## ここは生成されずnullのままになる(既存の単発射撃に変更を加えないため)。
const ATTACK_PATTERN_SCRIPTS := {
	"melee_arc": "res://systems/attack_patterns/melee_arc_attack.gd",
	"wide_cleave": "res://systems/attack_patterns/melee_arc_attack.gd",
	"charge_dash": "res://systems/attack_patterns/charge_dash_attack.gd",
	"self_pulse": "res://systems/attack_patterns/self_pulse_attack.gd",
	"holy_pulse_heal": "res://systems/attack_patterns/holy_pulse_heal_attack.gd",
	"piercing_thrust": "res://systems/attack_patterns/piercing_thrust_attack.gd",
	"spread_shot": "res://systems/attack_patterns/spread_shot_attack.gd",
	"homing_bolt": "res://systems/attack_patterns/homing_bolt_attack.gd",
	"summon_minion": "res://systems/attack_patterns/summon_minion_attack.gd",
}
const MELEE_PATTERN_IDS := ["melee_arc", "wide_cleave", "self_pulse", "piercing_thrust"]

var _character_data: CharacterData
var _class_attack: AttackPatternBase
var _class_attack_cooldown: float = 0.0
var _class_attack_in_progress: bool = false
var _attack_epoch := 0
var counter_strikes_remaining := 0
var _counter_haste_until := 0
const SWORD_STRIKE_FRAMES := {"attack1": [3], "attack2": [3, 6, 12], "attack3": [5, 7, 9, 11]}
signal animation_strike_resolved(animation: String, frame: int)
var _sword_animation := ""
var _sword_pending: Array = []
var _sword_facing := Vector2.RIGHT
var debug_next_sword_variant := 0
## Spaceスキルなどによる一時的な攻撃間隔倍率。1.0が通常、0.65なら35%高速化。
var active_skill_interval_multiplier: float = 1.0

func _ready() -> void:
	_setup_class_attack_pattern()
	# 職業固有の攻撃パターンを持つ職業(single_shot以外)は、それ自体が
	# 「見た目で分かる主力アクション」であるべきなので、既定の矢(starter_sword)は
	# 自動装備しない(以前は全職業が矢を撃ち続けており、パターンの違いが
	# 実際の見た目に埋もれてしまっていたため、2026年8月に変更)。
	# 現行ROOM RunのElement Fusionは職業攻撃へGameplay Traitを重ねるだけで、
	# 旧完成武器や追加Arrowを自動生成しない。
	if _should_use_starting_weapon():
		if starting_weapon_id != "" and DataLoader.weapons.has(starting_weapon_id):
			add_weapon(DataLoader.weapons[starting_weapon_id])

func _should_use_starting_weapon() -> bool:
	return _character_data == null or _character_data.attack_pattern_id == "single_shot"

## CharacterData.attack_pattern_idに対応するAttackPatternBaseサブクラスを
## 動的に生成する(BossAttackStrategyの選択ロジックと同じ考え方)。
func _setup_class_attack_pattern() -> void:
	_character_data = DataLoader.characters.get(GameManager.selected_character_id)
	if _character_data == null:
		return
	if not ATTACK_PATTERN_SCRIPTS.has(_character_data.attack_pattern_id):
		return
	var script: Script = load(ATTACK_PATTERN_SCRIPTS[_character_data.attack_pattern_id])
	_class_attack = script.new()
	_class_attack_cooldown = _class_attack.get_interval(_character_data, self)

func _process(delta: float) -> void:
	if _counter_haste_until > 0 and Time.get_ticks_msec() >= _counter_haste_until:
		_counter_haste_until = 0
		counter_strikes_remaining = 0
	var owner_entity := get_parent() as Player
	if is_instance_valid(owner_entity) and owner_entity.floating_weapons:
		equipment_attack.tick(delta, owner_entity, self)
	for instance in _weapon_instances:
		if _can_attack(owner_entity):
			instance.tick(delta, owner_entity, self)
	_tick_class_attack(delta, owner_entity)

func _can_attack(player: Player) -> bool:
	return is_instance_valid(player) and not player._is_dead and GameManager.run_state == GameManager.RunState.PLAYING and not get_tree().paused and player.dodge_remaining <= 0.0 and not player._movement_locked_by_attack and not player._counter_returning

func _tick_class_attack(delta: float, owner_entity: Player) -> void:
	_class_attack_cooldown -= delta
	if _class_attack == null or _class_attack_in_progress:
		return
	if _class_attack_cooldown <= 0.0 and _can_attack(owner_entity):
		var target := find_nearest_enemy(owner_entity.global_position, get_class_attack_range(), true)
		if target == null and not Input.is_action_pressed("primary_attack"):
			return
		if target: owner_entity.face_direction(owner_entity.global_position.direction_to(target.global_position))
		if _character_data.attack_pattern_id in MELEE_PATTERN_IDS:
			AudioManager.play_sfx("melee_swing")
			_start_melee_attack(owner_entity)
		else:
			_request_class_attack_vfx(owner_entity)
			_class_attack.execute(owner_entity, _character_data, self)
			_class_attack_cooldown = _class_attack.get_interval(_character_data, self)
			weapon_fired.emit()

func _start_melee_attack(owner_entity: Player) -> void:
	if _character_data.id == "swordsman":
		_start_sword_motion(owner_entity)
		return
	# Capture the auto-selected facing for the whole authored swing.
	var facing := owner_entity.get_facing_direction()
	owner_entity.face_direction(facing)
	_class_attack_in_progress = true
	_attack_epoch += 1
	var attack_epoch := _attack_epoch
	_class_attack_cooldown = _class_attack.get_interval(_character_data, self)
	var timing_multiplier := get_melee_attack_interval_multiplier()
	owner_entity.set_next_attack_animation_speed(1.0 / maxf(timing_multiplier, 0.2))
	attack_vfx_requested.emit(_character_data, owner_entity.global_position, facing)
	weapon_fired.emit()
	var impact_delay: float = float(_character_data.attack_pattern_params.get("impact_delay", 0.18)) * timing_multiplier
	await get_tree().create_timer(maxf(impact_delay, 0.01), false).timeout
	if attack_epoch == _attack_epoch and is_instance_valid(owner_entity) and not owner_entity._is_dead and owner_entity.dodge_remaining <= 0.0 and _class_attack:
		# Movement input may rotate Player during the windup. Resolve the hit using
		# the target direction captured when this auto attack actually started.
		owner_entity.face_direction(facing)
		_class_attack.execute(owner_entity, _character_data, self)
	if attack_epoch == _attack_epoch:
		_class_attack_in_progress = false

func _request_class_attack_vfx(owner_entity: Player) -> void:
	if owner_entity == null or _character_data == null:
		return
	var direction := owner_entity.get_facing_direction()
	var target := find_nearest_enemy(owner_entity.global_position)
	if target:
		var offset := target.global_position - owner_entity.global_position
		if offset != Vector2.ZERO:
			direction = offset.normalized()
			owner_entity.face_direction(direction)
	attack_vfx_requested.emit(_character_data, owner_entity.global_position, direction)

func get_class_attack_range() -> float:
	if _character_data == null:
		return 0.0
	var base_range: float = float(_character_data.attack_pattern_params.get("radius", _character_data.attack_range))
	return base_range * (get_melee_range_multiplier() if _character_data.attack_pattern_id in MELEE_PATTERN_IDS else get_attack_range_multiplier())

func add_weapon(weapon_data: WeaponData) -> void:
	if weapon_data == null or has_weapon(weapon_data.id):
		return
	var instance := WeaponInstance.new(weapon_data)
	_weapon_instances.append(instance)
	weapon_added.emit(weapon_data)

## HUDの所持武器トレイ・ポーズメニューの武器一覧が参照するための読み取り専用アクセサ。
func get_weapon_instances() -> Array[WeaponInstance]:
	return _weapon_instances

func has_weapon(weapon_id: String) -> bool:
	for instance in _weapon_instances:
		if instance.data.id == weapon_id:
			return true
	return false

func find_nearest_enemy(from_position: Vector2, max_distance: float = INF, clear_sight: bool = false) -> Node2D:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var nearest: Node2D = null
	var nearest_dist := max_distance
	for e in enemies:
		var health: HealthComponent = e.get_node_or_null("HealthComponent")
		if health == null or health.current_hp <= 0.0:
			continue
		var d := from_position.distance_to(e.global_position)
		if d < nearest_dist:
			if clear_sight:
				var ray := PhysicsRayQueryParameters2D.create(from_position, e.global_position, 1)
				ray.exclude = [(get_parent() as Player).get_rid()]
				if not (get_parent() as Player).get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
					continue
			nearest_dist = d
			nearest = e
	return nearest

func get_survival_extra_projectiles() -> int:
	var upgrades := get_owner_upgrades()
	return upgrades.get_survival_rank("survival_multishot") if upgrades else 0

func spawn_projectile(weapon_data: WeaponData, from_position: Vector2, target_position: Vector2, play_feedback: bool = true) -> void:
	if weapon_data.projectile_scene == null:
		return
	var owner_entity := get_parent() as Player
	if owner_entity and owner_entity.floating_weapons and from_position.distance_to(owner_entity.global_position) < 8.0:
		from_position = owner_entity.floating_weapons.get_muzzle(weapon_data.id)
	var upgrades := _get_owner_upgrades()
	_fire_single_projectile(weapon_data, from_position, target_position, upgrades)
	if _character_data == null or _character_data.attack_pattern_id != "spread_shot":
		for index in get_survival_extra_projectiles():
			_fire_single_projectile(weapon_data, from_position, _offset_target(from_position, target_position, (14.0 if index % 2 == 0 else -14.0) * (index / 2 + 1)), upgrades)
	# multishot_chance_up: 一定確率で、少し角度をずらしたもう1本を追加発射する
	# (完全に同じ軌道だと重なって見えず「追加の矢」感が無いため)。
	if upgrades and randf() < upgrades.multishot_chance:
		var offset_target := _offset_target(from_position, target_position, 18.0)
		_fire_single_projectile(weapon_data, from_position, offset_target, upgrades)
	if sector_follow_up_level > 0 and randf() < 0.23 * sector_follow_up_level:
		_fire_sector_follow_up(weapon_data, from_position)
	if play_feedback:
		AudioManager.play_sfx("attack_shoot")
		weapon_fired.emit()

func _fire_single_projectile(weapon_data: WeaponData, from_position: Vector2, target_position: Vector2, upgrades: PlayerUpgradesComponent) -> void:
	var projectile := weapon_data.projectile_scene.instantiate()
	# Playerが撃つ弾は、職業の攻撃Strategyが定める状態異常を運ぶ(仕様書36.3)。
	# spread_shot等の職業攻撃も装備武器もこの1経路に集約されている。
	projectile.applied_status_id = get_applied_status_id()
	if projectile is Projectile:
		projectile.pierce_remaining = sector_pierce_level + 1
		projectile.chain_remaining = sector_chain_level
	GameManager.get_runtime_world(self).add_child(projectile)
	projectile.global_position = from_position
	if projectile.has_method("launch"):
		projectile.launch(target_position, weapon_data, _get_owner_character_level(), _get_owner_stat_modifier(), upgrades)

func spawn_chain_projectile(weapon_data: WeaponData, from_position: Vector2, target_position: Vector2, chains_left: int = 0, visited: Dictionary = {}) -> void:
	if weapon_data == null or weapon_data.projectile_scene == null:
		return
	var projectile := weapon_data.projectile_scene.instantiate() as Projectile
	if projectile == null:
		return
	projectile.applied_status_id = get_applied_status_id()
	projectile.chain_remaining = chains_left
	projectile.chain_visited = visited.duplicate()
	projectile.pierce_remaining = 1
	GameManager.get_runtime_world(self).add_child(projectile)
	projectile.global_position = from_position
	projectile.launch(target_position, weapon_data, _get_owner_character_level(), _get_owner_stat_modifier(), _get_owner_upgrades())

func _fire_sector_follow_up(weapon_data: WeaponData, from_position: Vector2) -> void:
	await get_tree().create_timer(0.18).timeout
	if not is_inside_tree() or GameManager.run_state != GameManager.RunState.PLAYING:
		return
	var owner_entity := get_parent() as Player
	if owner_entity:
		from_position = owner_entity.floating_weapons.get_muzzle(weapon_data.id) if owner_entity.floating_weapons else owner_entity.global_position
	var target := find_nearest_enemy(from_position, weapon_data.attack_range * get_attack_range_multiplier(), true)
	if target:
		_fire_single_projectile(weapon_data, from_position, target.global_position, _get_owner_upgrades())

func _offset_target(from_position: Vector2, target_position: Vector2, angle_degrees: float) -> Vector2:
	var direction := target_position - from_position
	return from_position + direction.rotated(deg_to_rad(angle_degrees))

## 武器属性VFXの「強化」演出をどの程度出すかの基準として、
## 所有者(Player)のExperienceComponent.levelを参照する。
func _get_owner_character_level() -> int:
	var owner_entity := get_parent()
	if owner_entity == null:
		return 1
	var exp_component: ExperienceComponent = owner_entity.get_node_or_null("ExperienceComponent")
	return exp_component.level if exp_component else 1

## レベルアップによる攻撃力・クリティカル率の底上げをProjectile側で反映できるよう、
## 所有者のStatModifierComponentを渡す(無ければProjectile側で無補正として扱う)。
func _get_owner_stat_modifier() -> StatModifierComponent:
	var owner_entity := get_parent()
	if owner_entity == null:
		return null
	return owner_entity.get_node_or_null("StatModifierComponent")

## レベルアップの通常強化オプション(damage_up等)で蓄積した補正値を、
## Projectile側のダメージ計算・複数射撃・クリティカル・ホーミングへ渡すために使う。
func _get_owner_upgrades() -> PlayerUpgradesComponent:
	var owner_entity := get_parent()
	if owner_entity == null:
		return null
	return owner_entity.get_node_or_null("PlayerUpgradesComponent")

## アイテム(quick_hands等)で蓄積した攻撃間隔短縮率を、実際にattack_intervalへ
## 掛ける倍率(0〜1)に変換して返す。WeaponInstance.tick()がクールダウンを
## セットする際に使う。短縮率はPlayerUpgradesComponent側で上限クリップ済みのため、
## ここでは単純に1から引くだけでよい。
func get_attack_interval_multiplier() -> float:
	var upgrades := _get_owner_upgrades()
	if upgrades == null:
		return active_skill_interval_multiplier
	return maxf(0.2, 1.0 - upgrades.attack_interval_multiplier - upgrades.equipment_attack_speed_bonus) * active_skill_interval_multiplier

func get_melee_attack_interval_multiplier() -> float:
	var upgrades := _get_owner_upgrades()
	var melee_multiplier := 1.0 - upgrades.melee_attack_speed_bonus if upgrades else 1.0
	return get_attack_interval_multiplier() * melee_multiplier * (0.82 if Time.get_ticks_msec() < _counter_haste_until else 1.0)

func begin_counter_haste() -> void:
	_counter_haste_until = Time.get_ticks_msec() + 1000
	counter_strikes_remaining = 1
	_class_attack_cooldown = 0.0

func trigger_counter_attack() -> void:
	var player := get_parent() as Player
	if player == null or player._is_dead or _class_attack == null or _class_attack_in_progress:
		return
	if _character_data.attack_pattern_id in MELEE_PATTERN_IDS:
		_start_melee_attack(player)

## rapid_barrageのようなトレードオフ強化(攻撃間隔短縮の代償に射程が縮む等)で
## 蓄積したattack_range_multiplierを、実際にWeaponData.attack_rangeへ掛ける
## 倍率に変換して返す。WeaponInstance.tick()が射程判定に使う。
func get_attack_range_multiplier() -> float:
	var upgrades := _get_owner_upgrades()
	if upgrades == null:
		return 1.0
	return 1.0 + upgrades.attack_range_multiplier

func get_melee_range_multiplier() -> float:
	var upgrades := _get_owner_upgrades()
	return get_attack_range_multiplier() * (1.0 + upgrades.melee_range_bonus if upgrades else 1.0)

# --- systems/attack_patterns/以下のAttackPatternBaseサブクラス向けの公開アクセサ ---
# (このコンポーネントの外(systems/)から読み取る必要があるため、既存の
# _get_owner_*()とは別に公開名で薄いラッパーを用意する)。
func get_owner_upgrades() -> PlayerUpgradesComponent:
	return _get_owner_upgrades()

func get_owner_stat_modifier() -> StatModifierComponent:
	return _get_owner_stat_modifier()

func get_owner_character_level() -> int:
	return _get_owner_character_level()

# --- 職業専用強化(ability_level、2026年8月追加)向けアクセサ ---
## レベルアップ選択肢の抽選(LevelUpSelect)が「現在のability_level+1」に
## 対応する職業専用強化だけを候補に出すために使う。職業固有攻撃パターンを
## 持たない場合(_class_attackが無い)は0を返す。
func get_class_ability_level() -> int:
	return _class_attack.ability_level if _class_attack else 0

## LevelUpSelectが「現在選択中の職業」を判定するために使う
## (GameManager.selected_character_idを直接見てもよいが、既存の
## get_owner_*()系アクセサと同じくWeaponManagerComponent経由に統一する)。
func get_class_character_id() -> String:
	return _character_data.id if _character_data else ""

## PlayerUpgradesComponentが職業専用強化(class_ability_level_up)を適用する際に呼ぶ。
## AttackPatternBase.MAX_ABILITY_LEVELで頭打ちにする。
func increase_class_ability_level() -> void:
	if _class_attack:
		_class_attack.ability_level = mini(_class_attack.ability_level + 1, AttackPatternBase.MAX_ABILITY_LEVEL)
		class_ability_level_changed.emit(_class_attack.ability_level)

## 現在の職業の攻撃パターンが命中時に付与する状態異常(仕様書36.3)。
## LevelUpSelectが「その状態を参照するカードだけ」を候補に出すために使う。
## 職業固有攻撃パターンを持たない場合は空文字を返す。
func get_applied_status_id() -> String:
	return _class_attack.applied_status_id() if _class_attack else ""

## 流派分岐(school、2026年8月試験実装、Swordsmanのみ)向け。LevelUpSelectが
## 天賦図(ui/pause_menu/)の表示にも使う。school分岐を持たないパターンでは
## 常に"none"を返す。
func get_class_school() -> String:
	return _class_attack.school if _class_attack else "none"

## PlayerUpgradesComponentが職業専用の流派選択強化(class_school_select)を
## 適用する際に呼ぶ。schoolを確定させ、同時にability_levelも+1する
## (流派選択そのものがLv2到達を兼ねるため)。
func select_class_school(school: String) -> void:
	if _class_attack:
		_class_attack.school = school
		increase_class_ability_level()

func _start_sword_motion(player: Player) -> void:
	var variant := debug_next_sword_variant if debug_next_sword_variant in [1, 2, 3] else randi_range(1, 3)
	debug_next_sword_variant = 0
	if _class_attack.school == "issen":
		variant = 1
	_sword_facing = player.get_facing_direction()
	_sword_animation = "attack%d" % variant
	_sword_pending = SWORD_STRIKE_FRAMES[_sword_animation].duplicate()
	_class_attack_in_progress = true
	_attack_epoch += 1
	var attack_epoch := _attack_epoch
	_class_attack_cooldown = _class_attack.get_interval(_character_data, self)
	player.next_attack_animation_variant = variant
	player.set_next_attack_animation_speed(1.65 / maxf(get_melee_attack_interval_multiplier(), 0.2))
	player.animated_sprite.frame_changed.connect(_on_sword_frame)
	weapon_fired.emit()
	player.animated_sprite.frame = 0
	player.animated_sprite.frame_progress = 0.0
	while attack_epoch == _attack_epoch and is_instance_valid(player) and not player._is_dead and player.animated_sprite.animation == _sword_animation and player.animated_sprite.is_playing():
		await get_tree().process_frame
	if attack_epoch != _attack_epoch:
		return
	if is_instance_valid(player) and player.animated_sprite.frame_changed.is_connected(_on_sword_frame):
		player.animated_sprite.frame_changed.disconnect(_on_sword_frame)
	_sword_pending.clear()
	if attack_epoch == _attack_epoch:
		_sword_animation = ""
		_class_attack_in_progress = false

func cancel_current_attack() -> void:
	equipment_attack.windup = -1.0
	_attack_epoch += 1
	_class_attack_in_progress = false
	_sword_pending.clear()
	_sword_animation = ""
	var player := get_parent() as Player
	if player and player.floating_weapons:
		player.floating_weapons.cancel_equipment_motion()
	if player and player.animated_sprite.frame_changed.is_connected(_on_sword_frame):
		player.animated_sprite.frame_changed.disconnect(_on_sword_frame)
	if player and player.animation_component:
		player.animation_component.cancel_attack_pose()

func get_attack_epoch() -> int:
	return _attack_epoch

func consume_counter_bonus() -> float:
	if counter_strikes_remaining <= 0:
		return 1.0
	counter_strikes_remaining -= 1
	return 1.35

func _on_sword_frame() -> void:
	var player := get_parent() as Player
	if not _class_attack_in_progress or player._is_dead or player.dodge_remaining > 0.0 or player.animated_sprite.animation != _sword_animation:
		return
	var frame := player.animated_sprite.frame
	# Each authored strike frame is consumed exactly once, even at low rendering FPS.
	while not _sword_pending.is_empty() and int(_sword_pending[0]) <= frame:
		var strike_frame := int(_sword_pending.pop_front())
		var strike_count: int = SWORD_STRIKE_FRAMES[_sword_animation].size()
		player.face_direction(_sword_facing)
		(_class_attack as MeleeArcAttack).execute_animation_strike(player, _character_data, self, strike_count, _sword_pending.is_empty(), _sword_animation == "attack3")
		animation_strike_resolved.emit(_sword_animation, strike_frame)
