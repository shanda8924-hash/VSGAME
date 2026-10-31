extends Area2D
class_name HitboxComponent
## 攻撃判定(与ダメージ側)。プロジェクタイルや敵の接触ダメージ判定に使う汎用コンポーネント。
## monitoring=false / monitorable=true で運用し、HurtboxComponent側から検知させる。

signal landed(hurtbox: HurtboxComponent)

@export var damage: float = 10.0
@export var destroy_on_hit: bool = true
## Playerの通常攻撃／Spaceスキル由来Hitだけtrueにする。HurtboxComponentが
## combat_metadataを自動生成する際に「Player直撃(player_direct_attack)」と
## 「非Player由来(non_player_hit)」を区別するために使う。
## Enemy ContactHitboxやBoss弾はfalseのままにすること(nova_strategy.gd参照)。
@export var is_player_attack: bool = false
var is_critical: bool = false # クリティカル判定は攻撃側(Projectile等)が発射時に決める
## このHitが命中した敵へ付与する状態異常ID(burning/frozen/charged/marked/cursed)。
## 空文字なら何も付与しない。Playerの攻撃だけが生成時に職業の
## AttackPatternBase.applied_status_id()を書き込む(仕様書36.3)。
## Enemy ContactHitboxやBoss弾は空のままにすること。
var applied_status_id: String = ""
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
