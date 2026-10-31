extends Resource
class_name ItemData
## ボス撃破時に獲得する「常時ステータス上昇アイテム」の定義データ。
## effect_typeはPlayerUpgradesComponent.apply_item()のmatch分岐に対応する。
## damage_up/crit_rate_upはdata/upgrades/の強化オプションと同じeffect_typeを
## 再利用しており、同じ蓄積値(damage_multiplier/crit_rate_bonus)に加算される。

@export var id: String = ""
@export var display_name: String = ""
@export var effect_type: String = ""
@export var value: float = 0.0
## 選択カードに表示する32x32 Pixel icon。空なら従来どおり文字だけ表示する。
@export var icon_path: String = ""
## 選択UI(ItemSelect)に表示する効果の説明文。空の場合はeffect_type/valueから
## 自動生成した説明文で補われる(ItemSelect._resolve_description参照)。
@export var description: String = ""
## trueのアイテムは、ボス撃破後の3択候補を組み立てる際に優先的に(必ず)候補へ
## 入れる。現状の6種はすべてfalse(通常アイテム)だが、将来「特別アイテム」を
## 追加する際にJSON側でtrueにするだけでこの優先ロジックがそのまま機能する。
@export var is_special: bool = false
