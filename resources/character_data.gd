extends Resource
class_name CharacterData
## 職業(キャラクター)のデータ。見た目と基本ステータスだけを持つ。
## 数値は data/characters/*.json から読み込む(DataLoader)。
## ピボット前の戦闘項目(攻撃パターン・職業技・属性・パッシブ)は _archive/ に退避済み。

@export var id: String
@export var display_name: String
@export var sprite_folder: String # 例: "player/Soldier"(assets/sprites/ 以下の実フォルダ名と一致させる)
@export var max_hp: float = 100.0
@export var move_speed: float = 140.0
## 職業を象徴する道具のアイコン（弓兵＝弓、剣士＝剣など）。パズルのマスなど、キャラクターの絵を出さない所で使う。
@export var icon_path: String = ""
@export var icon_name: String = ""
## 転職の段階（1＝最下位）。同じ職業を fusion_count 体融合すると promotes_to の職業になる。空なら最上位。
@export var tier: int = 1
@export var promotes_to: String = ""
@export var fusion_count: int = 2
