extends Resource
class_name WeaponFragmentData
## 「合体武器(フュージョン)」システムにおける武器の欠片データ。
## 数値要素を持たないためJSONで読み込むだけの単純な定義。

@export var id: String
@export var display_name: String
@export var element: String # "fire" / "ice" / "lightning" / "light" / "dark" 等
@export var icon: Texture2D # 後からアイコン差し替え可能にするための参照(任意)
