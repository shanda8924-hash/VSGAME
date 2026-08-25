extends Resource
class_name EffectThemeData
## 武器属性ごとの演出テーマ定義(設計提案書 7.2「武器属性別テーマ例」に対応)。
## 雷/炎/氷/光/闇の単体属性テーマと、複数属性を合成した武器のテーマ(雷炎・蒸気等)を
## この1種類のResourceで表現する。単体テーマはcombo_idsを空にし、
## 合成テーマはcombo_idsに構成要素の属性idをカンマ区切りで指定する(例: "lightning,fire")。
## 新しい属性テーマを追加する際もこのResourceを1つ増やすだけでよく、
## 演出を呼び出す側のコードは変更不要(開放閉鎖の原則)。

@export var id: String = ""
@export var display_name: String = ""
@export var combo_ids: String = ""

@export var hit_particle_scene: PackedScene
@export var enhanced_particle_scene: PackedScene
@export var hit_color: Color = Color.WHITE
@export var enhanced_color: Color = Color.WHITE

## 被弾対象に付与する状態異常(例: 氷="slow")。効果を持たない属性は空文字のままでよい。
@export var status_effect: String = ""
@export var status_duration: float = 0.0

## 炎: 着弾からしばらく経ってから追加の爆発演出を出すまでの遅延秒数(0なら即時のみ)
@export var enhanced_delay: float = 0.0
## 光: 発射位置から着弾点まで貫通ビームの線を描画する
@export var is_beam: bool = false
## 雷: 着弾点から周囲の敵へ連鎖する稲妻の線を描画する(強化演出、character_level依存)
@export var is_chain: bool = false
## 闇: 着弾の少し後、発射位置(プレイヤー)側にも吸収演出を出す
@export var is_absorb: bool = false
## 氷: 強化演出(破砕)は対象がこの状態異常を持っている時のみ発生させる
@export var enhanced_requires_status: String = ""

func get_component_ids() -> Array:
	if combo_ids == "":
		return [id]
	return combo_ids.split(",")
