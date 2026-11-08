extends HitboxComponent
class_name Projectile
## 飛翔武器の弾。HitboxComponentを継承し、移動ロジックのみを追加する。
## (弾は「移動する攻撃判定」そのものなので、コンポジションではなく継承が適切)


@export var speed: float = 320.0
## 矢の絵柄の背後に、武器Theme色のごく控えめな加算(ADD)グローを重ねる
## (「よく見ると色が付いている」程度に留め、矢の視認性を邪魔しないようにする)。
@export var glow_neutral_color: Color = Color(1, 1, 1, 0.18) # 属性テーマが無い武器(例: starter_sword)用の既定色
@export var glow_theme_alpha: float = 0.3
## Boss NovaもこのSceneを共有するため、敵弾側を明示的に識別する互換フラグ。
## 現在のElement LoadoutはPlayer/BossどちらのProjectile表示にも自動適用しない。
@export var uses_player_element_vfx: bool = true
var _velocity: Vector2 = Vector2.ZERO
var _lifetime: float = 3.0
var _weapon_data: WeaponData
var _empowerment_level: int = 1
var _origin_position: Vector2 = Vector2.ZERO
## homing_upgradeで蓄積したホーミング強度(0=直進のみ、大きいほど旋回が速い)。
var _homing_strength: float = 0.0
var pierce_remaining := 1
var chain_remaining := 0
var _hit_targets: Dictionary = {}
var chain_visited: Dictionary = {}

@onready var _glow: Sprite2D = $Glow

func _ready() -> void:
	# ROOM遷移・Boss死亡時に残弾を確実に回収できる共通識別子。
	add_to_group("projectiles")
	# 矢の背後の淡い光は pixelfx projectiles/plasma-shot の1コマ（projectile_core）。
	if _glow and _glow.texture == null:
		_glow.texture = PixelSpriteVFX.frame_texture("projectile_core", 2)

## 敵弾：矢の絵を隠し、赤いpixelfxの弾（enemy_shot、ループ）にする。プレイヤーの矢と一目で区別できる。
func use_enemy_shot() -> void:
	$Visual.visible = false
	if _glow:
		_glow.visible = false
	var shot := PixelSpriteVFX.make_persistent("enemy_shot", Vector2.ZERO, true)
	if shot == null:
		return
	shot.name = "EnemyShotVFX"
	shot.offset = -PixelSpriteVFX.frame_size_for("enemy_shot") * Vector2(0.8, 0.5)
	shot.scale = Vector2.ONE * 0.6
	add_child(shot)
	shot.play_once(global_position)
	shot.position = Vector2.ZERO

## 魔導士の追尾弾の見た目は pixelfx arcane/arcane-orb（wizard_bolt、ループ）。判定と属性命中演出は維持する。
func use_wizard_magic() -> void:
	$Visual.visible = false
	var magic := PixelSpriteVFX.make_persistent("wizard_bolt", Vector2.ZERO, true)
	if magic == null:
		return
	magic.name = "WizardMagic"
	magic.offset = -PixelSpriteVFX.frame_size_for("wizard_bolt") * 0.5
	magic.scale = Vector2.ONE * 0.5
	add_child(magic)
	magic.play_once(global_position)
	magic.position = Vector2.ZERO

func launch(target_position: Vector2, weapon_data: WeaponData, empowerment_level: int = 1, stat_modifier: StatModifierComponent = null, player_upgrades: PlayerUpgradesComponent = null) -> void:
	# クリティカル判定は「発射時」に一度だけ行う(弾は基本1回しか当たらないため命中時と実質同じだが、
	# 仕様上ここで確定させておく)。レベルアップ分の補正(StatModifierComponent、レベルに応じて
	# 自動成長)と、通常強化オプションの補正(PlayerUpgradesComponent、選択式)は独立して
	# 両方上乗せする。
	var crit_chance := weapon_data.crit_chance
	var damage_multiplier := 1.0
	var flat_damage := weapon_data.base_damage
	if stat_modifier:
		crit_chance += stat_modifier.get_crit_chance_bonus()
		flat_damage += stat_modifier.get_damage_flat_bonus()
	if player_upgrades:
		crit_chance += player_upgrades.crit_rate_bonus + player_upgrades.equipment_crit_rate_bonus
		flat_damage += player_upgrades.equipment_attack_flat
		damage_multiplier *= player_upgrades.damage_multiplier * player_upgrades.get_equipment_conditional_damage_multiplier()
		_homing_strength = player_upgrades.homing_strength
	is_critical = randf() < crit_chance
	var crit_multiplier := weapon_data.crit_multiplier + (player_upgrades.equipment_crit_damage_bonus if player_upgrades else 0.0)
	damage = flat_damage * damage_multiplier * (crit_multiplier if is_critical else 1.0)
	_weapon_data = weapon_data
	_empowerment_level = empowerment_level
	_origin_position = global_position
	_velocity = (target_position - global_position).normalized() * speed
	if _velocity.length() > 0.0:
		rotation = _velocity.angle()
	# 職業Projectileは武器本来のThemeを維持し、現在ElementやLv変更では置換・再着色しない。
	_apply_glow_color(weapon_data.vfx_theme_id)
	if weapon_data.is_relic:
		# 遺物武器は共通Projectileの移動・Hit処理だけを再利用し、Arrow画像は出さない。
		# 欠片条件の有無を見た旧判定から明示フラグへ移し、属性システム廃止後も
		# 職業Projectileと遺物VFXの責務を混同しない。
		$Visual.visible = false
		_glow.scale = Vector2(1.45, 1.45)

## 矢の背後に重ねたグローの色を、武器のvfx_theme_id(EffectThemeData.hit_color)に
## 合わせる(炎=オレンジ、氷=水色、雷=黄色〜紫)。対応するテーマが無い武器
## (例: starter_sword)は、視認性のためだけの控えめな白グローにする。
func _apply_glow_color(theme_id: String) -> void:
	if _glow == null:
		return
	var theme: EffectThemeData = DataLoader.effect_themes.get(theme_id)
	if theme:
		var c := theme.hit_color
		_glow.modulate = Color(c.r, c.g, c.b, glow_theme_alpha)
	else:
		_glow.modulate = glow_neutral_color

## homing_bolt攻撃パターン(Wizard)専用: 強化オプション(homing_upgrade)未取得でも
## 最低限のホーミング性能を持たせるための下限設定。取得済みの強化値の方が高ければ
## そちらを優先する(値を下げることはしない)。
func set_minimum_homing(strength: float) -> void:
	_homing_strength = maxf(_homing_strength, strength)

func _physics_process(delta: float) -> void:
	if _homing_strength > 0.0:
		_apply_homing(delta)
	global_position += _velocity * delta
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()

## homing_upgradeで蓄積した強度に応じて、毎フレーム少しずつ最も近い敵の方向へ
## 速度ベクトルを旋回させる(Vector2.slerpで滑らかに向きを変える、瞬時には向かない)。
func _apply_homing(delta: float) -> void:
	var target := _find_nearest_enemy()
	if target == null:
		return
	var desired := (target.global_position - global_position).normalized() * speed
	var turn_weight: float = clampf(_homing_strength * 6.0 * delta, 0.0, 1.0)
	_velocity = _velocity.slerp(desired, turn_weight)
	if _velocity.length() > 0.0:
		rotation = _velocity.angle()

func _find_nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		var health: HealthComponent = e.get_node_or_null("HealthComponent")
		if health == null or health.current_hp <= 0.0:
			continue
		var dist := global_position.distance_to(e.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = e
	return nearest

## 命中時、武器のvfx_theme_idに応じた属性VFX(EffectThemeManager)を発火させてから
## 通常のヒット処理(HitboxComponent.on_hit、弾の消滅)を行う。
func on_hit(hurtbox: HurtboxComponent) -> void:
	var target := hurtbox.get_owner_entity()
	if target == null or _hit_targets.has(target.get_instance_id()):
		return
	_hit_targets[target.get_instance_id()] = true
	chain_visited[target.get_instance_id()] = true
	if _weapon_data:
		var manager: Node = get_tree().get_first_node_in_group("effect_theme_manager")
		if manager:
			manager.play_weapon_hit(_weapon_data.vfx_theme_id, global_position, _empowerment_level, hurtbox, _origin_position, is_critical)
	if chain_remaining > 0 and _weapon_data:
		var player := get_tree().get_first_node_in_group("player") as Player
		if player:
			var next_target: Node2D = null
			var distance := 200.0
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if enemy == target or not is_instance_valid(enemy) or not enemy is Node2D or chain_visited.has(enemy.get_instance_id()):
					continue
				var health := enemy.get_node_or_null("HealthComponent") as HealthComponent
				if health == null or health.current_hp <= 0.0:
					continue
				var candidate_distance := global_position.distance_to(enemy.global_position)
				if candidate_distance < distance:
					distance = candidate_distance
					next_target = enemy
			if next_target:
				player.weapon_manager.spawn_chain_projectile(_weapon_data, global_position, next_target.global_position, chain_remaining - 1, chain_visited)
		chain_remaining = 0
	pierce_remaining -= 1
	destroy_on_hit = pierce_remaining <= 0
	super.on_hit(hurtbox)

func can_hit(hurtbox: HurtboxComponent) -> bool:
	var target := hurtbox.get_owner_entity()
	return super.can_hit(hurtbox) and target != null and not _hit_targets.has(target.get_instance_id())
