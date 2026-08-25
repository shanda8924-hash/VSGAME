extends Resource
class_name UpgradeData
## レベルアップ時の「通常強化オプション」の定義データ(JSON→DataLoader経由で読み込む)。
## 新しい強化オプションを追加する場合も、data/upgrades/にJSONを1つ増やし、
## PlayerUpgradesComponent.apply_upgrade()にeffect_typeの分岐を1つ足すだけでよい。

@export var id: String = ""
@export var display_name: String = ""
## PlayerUpgradesComponentがどの蓄積値に加算するかを決めるキー
## (例: "damage_up", "multishot_chance_up", "crit_rate_up", "homing_upgrade")。
@export var effect_type: String = ""
## 1回選択したときの効果量(例: damage_upなら0.15=+15%)。
@export var value: float = 0.0
## 選択UI(LevelUpSelect)に表示する効果の説明文。特にトレードオフ付きの
## オプションでは、代償の内容が一目で分かるよう必ず設定することを推奨する。
@export var description: String = ""
## "melee" / "ranged" / "common"。候補抽選時の適性フィルタに使用する。
@export var category: String = "common"
## 吸血上限など、効果固有の調整値。
@export var effect_params: Dictionary = {}
## トレードオフ(Brotato的な代償)を持つ強化オプション用。空文字なら代償なし
## (純粋な強化)。effect_typeと同じキー体系(例: "move_speed_multiplier",
## "attack_range_multiplier")を使い、PlayerUpgradesComponentが
## 「downside_valueぶんマイナス方向に」適用する。
@export var downside_type: String = ""
## 代償の効果量(常に正の値で記述する。例: 0.05=移動速度-5%)。
@export var downside_value: float = 0.0

## 職業専用の攻撃パターン強化(ability_level、2026年8月追加)。空文字なら
## 通常の汎用強化オプション(全職業共通の候補プールに乗る)。
## CharacterData.id(例: "swordsman")と一致する場合だけ候補に出現する
## (同じattack_pattern_idを複数職業が共有していても、職業ごとに別々の
## 強化ツリーを持たせるためcharacter_idで判定する)。
@export var class_character_id: String = ""
## この強化を選ぶとsystems/attack_patterns/のAttackPatternBase.ability_levelが
## 到達する段階(2〜5)。「現在のability_level+1」と一致する場合だけ候補に
## 出現させることで、Lv2→Lv3→Lv4→Lv5の順序を保証する(LevelUpSelect._get_compatible_upgrades()参照)。
@export var class_ability_level: int = 0

## 流派分岐(school、2026年8月試験実装、Swordsmanのみ)。effect_typeが
## "class_school_select"の場合はこの強化を選んだ時に確定するschool
## (例: "rengeki"/"issen")。それ以外の職業専用強化の場合は、この強化が
## 出現するために必要な「既に確定しているschool」を表す(空文字なら
## school分岐を持たない職業専用強化)。
@export var class_school: String = ""
