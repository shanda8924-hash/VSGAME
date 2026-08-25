extends Resource
class_name FusionVFXData
## ImageGenで新規生成したFusion専用Pixel Artだけを参照するPresentation Resource。
## Gameplay値やCollisionは持たず、用途ごとの6-frame Sprite Sheetを管理する。

@export var fusion_id: String = ""
@export var attack_sprite_sheet: Texture2D
@export var trail_sprite_sheet: Texture2D
@export var hit_sprite_sheet: Texture2D
@export var burst_sprite_sheet: Texture2D
@export var intro_sprite_sheet: Texture2D
@export_range(6.0, 30.0, 1.0) var fps: float = 18.0

func sprite_sheet_for_mode(effect_mode: String) -> Texture2D:
	match effect_mode:
		"attack": return attack_sprite_sheet
		"trail", "soul": return trail_sprite_sheet
		"hit": return hit_sprite_sheet
		"formation", "intro", "state": return intro_sprite_sheet
		_: return burst_sprite_sheet
