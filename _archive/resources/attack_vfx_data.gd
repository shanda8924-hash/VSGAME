extends Resource
class_name AttackVFXData
## 実ゲームのAttack/Hitで再生するエフェクトの置き方。見た目は assets/vfx/pixelfx/<id>（PixelSpriteVFX）。

@export var id: String = ""
## 旧6コマ画像。現在の見た目は assets/vfx/pixelfx/<id> （PixelSpriteVFX）で、ここは使わない。
@export_range(1, 12, 1) var frame_count: int = 6
@export var fps: float = 16.0
@export var lifetime: float = 0.45
## プレイヤー本体の実Visual heightに対する最大フレームの目標比率。
@export var visual_ratio: float = 1.0
@export var directional: bool = false
## directional時にプレイヤー本体heightの何倍だけ前方へずらすか。
@export var spawn_offset_ratio: float = 0.0
