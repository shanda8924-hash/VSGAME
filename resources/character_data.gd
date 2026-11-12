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
