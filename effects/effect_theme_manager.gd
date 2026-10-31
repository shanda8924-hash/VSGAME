extends Node
class_name EffectThemeManager
## 職業/武器Themeの命中・Beam・Chainを生成Pixel画像で再生する。
## Themeの状態付与と強化条件はそのまま。廃止済み属性/Fusionシステムは使用しない。

const ENHANCED_CHARACTER_LEVEL := 3
const CHAIN_BASE_COUNT := 1
const CHAIN_COUNT_PER_LEVEL := 1
const CHAIN_MAX_COUNT := 5

func _ready() -> void:
	add_to_group("effect_theme_manager")

## theme_id: WeaponData.vfx_theme_id。character_level: プレイヤーのExperienceComponent.level。
## origin_position: 攻撃の発射位置(光属性のビーム描画・闇属性の吸収演出に使用)。
func play_weapon_hit(theme_id: String, position: Vector2, character_level: int, hit_hurtbox: HurtboxComponent = null, origin_position: Vector2 = Vector2.ZERO, is_critical: bool = false, suppress_class_yellow_hit: bool = false) -> void:
	# 属性Themeが無いstarter_swordでも、実命中を伝えるPixel Hit VFXは必ず要求する。
	var attack_vfx := get_tree().get_first_node_in_group("attack_vfx_manager") as AttackVFXManager
	if attack_vfx and not suppress_class_yellow_hit:
		attack_vfx.play_hit(position, theme_id, is_critical)
	var theme: EffectThemeData = DataLoader.effect_themes.get(theme_id)
	if theme == null:
		return
	for element_id in theme.get_component_ids():
		_play_element(element_id, position, character_level, hit_hurtbox, origin_position, suppress_class_yellow_hit)

func _play_element(element_id: String, position: Vector2, character_level: int, hit_hurtbox: HurtboxComponent, origin_position: Vector2, suppress_class_yellow_hit: bool = false) -> void:
	var theme: EffectThemeData = DataLoader.effect_themes.get(element_id)
	if theme == null:
		return

	var enhanced := character_level >= ENHANCED_CHARACTER_LEVEL
	if enhanced and theme.enhanced_requires_status != "":
		enhanced = _target_has_status(hit_hurtbox, theme.enhanced_requires_status)

	var suppress_base_hit := suppress_class_yellow_hit and element_id == "lightning"
	if not suppress_base_hit:
		_spawn_hit_sprite(element_id, position, enhanced)

	if theme.status_effect != "":
		_apply_status(hit_hurtbox, theme.status_effect, theme.status_duration)

	if theme.is_beam:
		var from := origin_position if origin_position != Vector2.ZERO else position
		var width := 6.0 if enhanced else 3.0
		var color := theme.enhanced_color if enhanced else theme.hit_color
		_spawn_line(from, position, color, width, 0.2)
		# 以前は強化時にscreen_effects.flash()で画面全体をフラッシュさせていたが、
		# 攻撃速度上昇で点滅頻度が上がり不快感・光過敏性リスクにつながるため廃止。
		# 着弾位置周辺の局所的なビーム線(上記_spawn_line)のみに留める。

	# ThemeのChainは描画だけ。ここからダメージや状態付与へ再帰しない。
	if theme.is_chain and enhanced:
		var count: int = clamp(CHAIN_BASE_COUNT + (character_level - ENHANCED_CHARACTER_LEVEL) * CHAIN_COUNT_PER_LEVEL, CHAIN_BASE_COUNT, CHAIN_MAX_COUNT)
		_spawn_chain(position, theme.enhanced_color, count)

	if theme.is_absorb and enhanced and origin_position != Vector2.ZERO:
		await get_tree().create_timer(0.15).timeout
		if is_inside_tree():
			_spawn_hit_sprite(element_id, origin_position, true)

func _spawn_hit_sprite(theme_id: String, position: Vector2, enhanced: bool) -> void:
	PixelSpriteVFX.spawn(self, position, "hit_" + theme_id, Vector2.ONE * (52.0 if enhanced else 36.0), 0.34 if enhanced else 0.26)

func _apply_status(hurtbox: HurtboxComponent, effect_name: String, duration: float) -> void:
	var status := _get_status_component(hurtbox)
	if status:
		status.apply_effect(effect_name, duration)

func _target_has_status(hurtbox: HurtboxComponent, effect_name: String) -> bool:
	var status := _get_status_component(hurtbox)
	return status.has_effect(effect_name) if status else false

func _get_status_component(hurtbox: HurtboxComponent) -> StatusEffectComponent:
	if hurtbox == null:
		return null
	var entity := hurtbox.get_owner_entity()
	if entity == null:
		return null
	return entity.get_node_or_null("StatusEffectComponent")

func _spawn_line(from: Vector2, to: Vector2, color: Color, width: float, fade_duration: float, effect_id: String = "beam") -> void:
	if from.distance_squared_to(to) <= 1.0:
		return
	var segment := to - from
	# 先端から後端まで固定した描画領域内で、画像の形状だけが展開・分解する。
	# 線のシート（beam=光、chain=雷）は統一ランプで着色済みなので、テーマ色は掛けない。
	PixelSpriteVFX.spawn(self, (from + to) * 0.5, effect_id, Vector2(segment.length(), maxf(width * 4.0, 12.0)), minf(fade_duration, 0.16), segment.angle(), Color.WHITE)

func _spawn_chain(origin: Vector2, color: Color, count: int) -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	enemies.sort_custom(func(a, b): return origin.distance_to(a.global_position) < origin.distance_to(b.global_position))
	var previous := origin
	var made := 0
	for e in enemies:
		if made >= count:
			break
		var health: HealthComponent = e.get_node_or_null("HealthComponent")
		if health == null or health.current_hp <= 0.0:
			continue
		_spawn_line(previous, e.global_position, color, 3.0, 0.25, "chain")
		previous = e.global_position
		made += 1
