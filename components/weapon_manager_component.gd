extends Node
class_name WeaponManagerComponent
## 職業通常攻撃と欠片合成武器の自動攻撃を統括する。

signal weapon_fired
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
	var owner_entity := get_parent() as Player
	for instance in _weapon_instances:
		instance.tick(delta, owner_entity, self)
	_tick_class_attack(delta, owner_entity)

func _tick_class_attack(delta: float, owner_entity: Player) -> void:
	if _class_attack == null or _class_attack_in_progress:
		return
	_class_attack_cooldown -= delta
	if _class_attack_cooldown <= 0.0:
		if _character_data.attack_pattern_id in MELEE_PATTERN_IDS:
			_start_melee_attack(owner_entity)
		else:
			_request_class_attack_vfx(owner_entity)
			_class_attack.execute(owner_entity, _character_data, self)
			_class_attack_cooldown = _class_attack.get_interval(_character_data, self)
			weapon_fired.emit()

func _start_melee_attack(owner_entity: Player) -> void:
	var target := find_nearest_enemy(owner_entity.global_position)
	if target == null:
		return
	var attack_range := get_class_attack_range()
	var offset := target.global_position - owner_entity.global_position
	if offset.length() > attack_range:
		return
	var facing := offset.normalized() if offset != Vector2.ZERO else owner_entity.get_facing_direction()
	owner_entity.face_direction(facing)
	var step_distance: float = float(_character_data.attack_pattern_params.get("step_distance", 14.0))
	var stop_distance: float = minf(24.0, attack_range * 0.35)
	var actual_step := minf(step_distance, maxf(offset.length() - stop_distance, 0.0))
	if actual_step > 0.0:
		owner_entity.move_and_collide(facing * actual_step)
	_class_attack_in_progress = true
	_class_attack_cooldown = _class_attack.get_interval(_character_data, self)
	var timing_multiplier := get_melee_attack_interval_multiplier()
	owner_entity.set_next_attack_animation_speed(1.0 / maxf(timing_multiplier, 0.2))
	attack_vfx_requested.emit(_character_data, owner_entity.global_position, facing)
	weapon_fired.emit()
	var impact_delay: float = float(_character_data.attack_pattern_params.get("impact_delay", 0.18)) * timing_multiplier
	await get_tree().create_timer(maxf(impact_delay, 0.01), false).timeout
	if is_instance_valid(owner_entity) and _class_attack:
		# Movement input may rotate Player during the windup. Resolve the hit using
		# the target direction captured when this auto attack actually started.
		owner_entity.face_direction(facing)
		_class_attack.execute(owner_entity, _character_data, self)
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
	var instance := WeaponInstance.new(weapon_data)
	_weapon_instances.append(instance)

## HUDの所持武器トレイ・ポーズメニューの武器一覧が参照するための読み取り専用アクセサ。
func get_weapon_instances() -> Array[WeaponInstance]:
	return _weapon_instances

func has_weapon(weapon_id: String) -> bool:
	for instance in _weapon_instances:
		if instance.data.id == weapon_id:
			return true
	return false

func find_nearest_enemy(from_position: Vector2) -> Node2D:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var nearest: Node2D = null
	var nearest_dist := INF
	for e in enemies:
		var health: HealthComponent = e.get_node_or_null("HealthComponent")
		if health == null or health.current_hp <= 0.0:
			continue
		var d := from_position.distance_to(e.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e
	return nearest

func spawn_projectile(weapon_data: WeaponData, from_position: Vector2, target_position: Vector2, play_feedback: bool = true) -> void:
	if weapon_data.projectile_scene == null:
		return
	var upgrades := _get_owner_upgrades()
	_fire_single_projectile(weapon_data, from_position, target_position, upgrades)
	# multishot_chance_up: 一定確率で、少し角度をずらしたもう1本を追加発射する
	# (完全に同じ軌道だと重なって見えず「追加の矢」感が無いため)。
	if upgrades and randf() < upgrades.multishot_chance:
		var offset_target := _offset_target(from_position, target_position, 18.0)
		_fire_single_projectile(weapon_data, from_position, offset_target, upgrades)
	if play_feedback:
		AudioManager.play_sfx("attack_shoot")
		weapon_fired.emit()

func _fire_single_projectile(weapon_data: WeaponData, from_position: Vector2, target_position: Vector2, upgrades: PlayerUpgradesComponent) -> void:
	var projectile := weapon_data.projectile_scene.instantiate()
	GameManager.get_runtime_world(self).add_child(projectile)
	projectile.global_position = from_position
	if projectile.has_method("launch"):
		projectile.launch(target_position, weapon_data, _get_owner_character_level(), _get_owner_stat_modifier(), upgrades)

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
	return get_attack_interval_multiplier() * melee_multiplier

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
