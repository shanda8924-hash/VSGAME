extends Resource
class_name CharacterData
## 職業(プレイヤーキャラクター)のデータ。WeaponData/EnemyDataと同じく、
## 数値バランスはJSON(data/characters/*.json)から読み込む想定。

@export var id: String
@export var display_name: String
@export var sprite_folder: String # 例: "player/Soldier"(assets/sprites/以下の実フォルダ名と一致させる)
@export var max_hp: float = 100.0
@export var move_speed: float = 140.0
@export var unlock_cost: int = 0 # メタ通貨での解放コスト。0=最初から解放済み
## この職業のキャラクター性に合う属性("fire"/"ice"/"lightning"/"light"/"dark")。
## 将来の属性傾向・報酬重み付け用。欠片が特別報酬化された現在もデータ互換のため保持する。
@export var preferred_element: String = ""

## 職業ごとの自動攻撃パターン識別子(systems/attack_patterns/参照)。
## "single_shot"は既存のWeaponManagerComponent/WeaponInstance(欠片合成武器)の
## 自動射撃をそのまま使う(追加のクラス攻撃パターンなし)。それ以外のIDは
## WeaponManagerComponentが対応するAttackPatternBaseサブクラスを生成し、
## 欠片合成武器とは独立した「職業固有の自動攻撃」として並行して発動する。
@export var attack_pattern_id: String = "single_shot"
## 以下はattack_pattern_idの実行に使う基礎数値(WeaponDataの対応フィールドと同じ意味)。
@export var base_damage: float = 10.0
@export var attack_interval: float = 1.0
@export var attack_range: float = 200.0
@export var vfx_theme_id: String = "default"
@export var crit_chance: float = 0.15
@export var crit_multiplier: float = 2.0
## 攻撃パターン固有の追加パラメータ(扇の角度・貫通数・召喚間隔等)。
## data/characters/*.jsonの対応キーがそのままここに入る(パターンごとに
## 必要なキーだけを使う。JSON編集だけで数値調整が完結するようにするため)。
@export var attack_pattern_params: Dictionary = {}

# --- Space職業固有アクティブスキル ---
@export var active_skill_id: String = ""
@export var active_skill_name: String = ""
@export var active_skill_icon: String = "SK"
@export var active_skill_cooldown: float = 10.0
@export var active_skill_params: Dictionary = {}

# --- 職業固有パッシブ(2026年8月追加) ---
## 被ダメージ軽減率(0.0〜1.0)。PlayerUpgradesComponentが蓄積した軽減率と
## 掛け合わさってHealthComponent.damage_taken_multiplierへ反映される。
@export var damage_reduction: float = 0.0
## 獲得経験値倍率。ExperienceComponentが敵撃破時のexp_valueに掛ける。
@export var exp_gain_multiplier: float = 1.0
## 戦利品/欠片の取得範囲倍率。現状このプロジェクトには「歩いて拾う」
## ワールドピックップの仕組みが無い(欠片・アイテムはEventBus経由で直接付与される)ため、
## 将来ピックアップ範囲の概念が実装された際にそのまま使える値として保持するのみで、
## 現時点ではゲームプレイに反映される先が無い(値は保持するが効果は未接続)。
@export var pickup_range_multiplier: float = 1.0
## 会心率の恒常加算値。PlayerUpgradesComponentのcrit_rate_bonusへ起動時に
## そのまま加算される(強化オプションのcrit_rate_upと同じ蓄積値を共有する)。
@export var crit_rate_bonus: float = 0.0
## 近接系攻撃パターン(melee_arc/wide_cleave)がヒットした際、与えたダメージの
## この割合ぶん自分のHPを回復する(0.0〜1.0)。
@export var melee_lifesteal_percent: float = 0.0
@export var melee_lifesteal_cap_per_hit: float = 0.0
## summon_minionパターンで召喚する味方のステータス倍率。
@export var minion_stat_multiplier: float = 1.0
## 自身の攻撃パターンのダメージに掛かる倍率(Necromancerの本体攻撃力ダウン等)。
@export var self_damage_multiplier: float = 1.0
## charge_dashパターンの突進中、被ダメージを完全無効化するかどうか。
@export var dash_invincible: bool = false
