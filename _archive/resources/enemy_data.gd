extends Resource
class_name EnemyData
## 敵のデータ。数値バランスはJSONから読み込む想定(DataLoader参照)。

@export var special_attack_id: String = ""
@export var id: String
@export var display_name: String
@export var sprite_folder: String # 例: "enemy/Orc"(assets/sprites/以下の実フォルダ名と一致させる)
@export var max_hp: float = 20.0
@export var move_speed: float = 60.0
@export var contact_damage: float = 5.0
@export var exp_value: int = 1
@export var min_elapsed_seconds: float = 0.0 # この秒数を過ぎるまでWaveSpawnerの出現候補にならない
## 通常攻撃が命中した後、次に攻撃を開始できるまでの時間。
@export var attack_interval: float = 1.0
## 通常攻撃を開始・命中判定する距離。接触判定とは独立して扱う。
@export var attack_range: float = 52.0
## 攻撃モーション開始から命中判定までの、回避可能な予備時間。
@export var attack_windup: float = 0.45
## 0より大きいと遠距離型。この距離で立ち止まり、予備動作の後に弾を1発撃つ
## （立ち止まりを罰する役割、Phase 1）。近接判定は使わない。
@export var ranged_range: float = 0.0
