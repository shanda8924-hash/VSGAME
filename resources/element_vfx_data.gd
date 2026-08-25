extends Resource
class_name ElementVFXData
## ラン中の現在属性がAttack Typeへ重ねるVisual定義。
## Gameplay値は持たず、居合軌跡と確定HitのSprite Animationだけを管理する。

@export var element_id: String = "element_none"
@export var display_name: String = "なし"
@export var attack_tint: Color = Color.WHITE
@export var secondary_tint: Color = Color.WHITE
@export_enum("embers", "crystals", "arcs", "rays", "rifts") var stack_accent_style: String = "embers"
@export_range(1, 16, 1) var level2_accent_count: int = 4
@export_range(2, 24, 1) var level3_accent_count: int = 8

@export var iai_trail_vfx_id: String = ""
@export var iai_trail_sprite_sheet: Texture2D
@export var iai_trail_fps: float = 14.0
@export var iai_trail_lifetime: float = 0.8
@export var iai_trail_visual_ratio: float = 1.15
@export_range(0.0, 1.0, 0.05) var iai_afterimage_alpha_multiplier: float = 1.0

@export var hit_vfx_id: String = ""
@export var hit_sprite_sheet: Texture2D
@export var hit_fps: float = 20.0
@export var hit_lifetime: float = 0.36
@export var hit_visual_ratio: float = 0.62

## 将来の専用飛翔体と敵間Chain用。現在Element/Lv変更や職業Projectileからは呼び出さない。
@export var projectile_vfx_id: String = ""
@export var projectile_sprite_sheet: Texture2D
@export var projectile_fps: float = 18.0
@export var projectile_visual_pixels: float = 28.0

@export var chain_vfx_id: String = ""
@export var chain_sprite_sheet: Texture2D
@export var chain_fps: float = 22.0
@export var chain_lifetime: float = 0.28
@export var chain_visual_ratio: float = 0.42
