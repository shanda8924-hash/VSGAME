extends EnemyData
class_name BossData
## ボス敵専用のデータ。EnemyDataを継承しているため、EnemyBasic.enemy_dataへ
## そのまま渡すだけで既存のダメージ計算/移動/描画(SpriteSheetBuilder)ロジックを
## 再利用できる(開放閉鎖の原則。EnemyBasic側の変更は不要)。

## 通常の敵より大きく見せるための表示倍率(EnemyBasic.visual_scale_multiplierへ渡す。
## AnimatedSprite2D.scaleと当たり判定(CollisionShape2D)の両方に乗算されるため、
## 見た目と判定はズレない)。
@export var visual_scale: float = 1.35

## ボス固有攻撃の種類("charge"/"summon"/"nova"/"slam"/"minotaur_combo"。
## 空文字なら固有攻撃なし)。
## EnemyBasicがこの値を見てsystems/boss_ai/以下の対応するBossAttackStrategyを
## 動的に生成・アタッチする。
@export var attack_pattern_id: String = ""
