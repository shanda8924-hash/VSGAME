extends Area2D
class_name HitboxComponent
## 攻撃判定(与ダメージ側)。プロジェクタイルや敵の接触ダメージ判定に使う汎用コンポーネント。
## monitoring=false / monitorable=true で運用し、HurtboxComponent側から検知させる。

signal landed(hurtbox: HurtboxComponent)

@export var damage: float = 10.0
@export var destroy_on_hit: bool = true
## Playerの通常攻撃／Spaceスキル由来Hitだけtrueにし、属性追加ダメージの入口にする。
## Enemy ContactHitboxなどはfalseのままなので、プレイヤー被弾へ属性が逆流しない。
@export var applies_player_elements: bool = false
var is_critical: bool = false # クリティカル判定は攻撃側(Projectile等)が発射時に決める
## 空の場合はHurtbox側がPlayer直撃/非Playerを判定して既定Metadataを生成する。
var combat_metadata: Dictionary = {}
## trueの間だけHurtboxComponentが実際にダメージを適用する。Projectile/MeleeHit等の
## 単発ヒットは既定のtrueのままでよい。EnemyBasicのContactHitboxのように「常に
## 重なっているが、特定の瞬間だけ当てたい」判定は、外部からこのフラグを
## 切り替えて有効期間を制御する(接触ダメージが攻撃モーション中だけ発生する仕様、参照)。
@export var damage_enabled: bool = true

## ダメージ適用前の拡張判定。MeleeHitは角度・幅・重複命中を絞り込む。
func can_hit(_hurtbox: HurtboxComponent) -> bool:
	return damage_enabled

func on_hit(hurtbox: HurtboxComponent) -> void:
	landed.emit(hurtbox)
	if destroy_on_hit:
		queue_free()
