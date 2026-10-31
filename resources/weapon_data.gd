extends Resource
class_name WeaponData
## 完成武器のデータ。数値バランス(base_damage等)はJSONから読み込まれ、
## 参照系(projectile_scene, icon等)はここで保持する(ハイブリッド方針)。

@export var id: String
@export var display_name: String
@export var description: String = "" # 所持武器トレイ・ポーズメニューの武器一覧に表示する効果説明
@export var icon: Texture2D
@export var base_damage: float = 10.0
@export var attack_interval: float = 1.0
@export var attack_range: float = 150.0
@export var projectile_scene: PackedScene
@export var required_fragment_ids: Array[String] = [] # フュージョンに必要な欠片ID
@export var is_relic: bool = false # 旧Fusion武器を欠片条件から切り離したShop専用遺物武器
@export var vfx_theme_id: String = "default" # 演出テーマの識別子(将来EffectThemeDataに接続)
@export var crit_chance: float = 0.15 # クリティカル発生率(0.0〜1.0)
@export var crit_multiplier: float = 2.0 # クリティカル時のダメージ倍率
