# Royal Pixel Art ブラッシュアップ — 2026-09-05

## Scope / 状態

承認された設計を、追加依頼に合わせHUD/共通UI/Shop/LevelUp/宝物庫/鍛造/装備画像/Drop/MAP描画へ実装。
既存Sceneとicon_pathへ接続済み。前回は実行承認の利用上限によりRuntime未検証で引き渡し、
その後ユーザーの起動で型推論エラーが判明した。今回、承認されたGodot実行で修正と主要経路のRuntime確認まで実施。
全MAP/長時間検証は下記に残す。
data/、戦闘・経済数値、Inventory取引、DungeonMap生成・通行/障害物判定、セーブは今回変更していない。
大量の既存未コミット変更・属性/Fusion削除は保持。

## 主な変更

- UI: 古金/青紺/緑玉、翼付き紋章、角金具、商品台座。本文はM PLUS 1p Medium + OFL。
  Panelの常駐Glow/ガラス光沢を9-sliceへ置換。装飾はContainer外でサイズ変更時だけ再描画。
- Shop: 「灯火の遺物商」、4カード、ランタン/木箱、購入後focus維持、不足額を選択可能、完了文を保持。
- LevelUp: 「魂の刻印」3石板。候補/効果は変更せず画像と情報階層を変更。
- HUD: 左上HP/XP、右上Gold、下中央職業スキル、右下Combo。
- 宝物庫: レア度/部位/新規順、レア度Filter。表示コピーを整理し実Inventoryは不変。
- 宝物庫/装備/鍛造は3列常設。6列バッグ、比較/装備/解除/素材追加、右の3枠炉を同時に操作する。
  同レア3点セットは未装備・未Lockの候補提示のみ。Filterは任意で、素材を置いても他レア品を隠さない。
  古代炉への収束→火花→完成Icon、1.64秒。2回目以降Skip、全Tween停止、取引は既存1回のみ。
- 装備25種: 新規生成絵を既存PNGパスへ。Drop/宝物庫/装備/合成すべて同画像。
  Drop刻印1〜5、0.7秒出現演出、6〜14火花、常駐粒子最大6。GPU画像読出しをoffline Boundsへ。
- MAP: 新規原画から全床/壁/収納/柱/松明/結晶をpack。床は共通の青灰色。樽は全体が1tileに収まる。
  金縁壁/壁掛けは正面だけ。壁内入口柱・柱フェンス・柱画像のアーチ代用は廃止し敷居と旗へ。
  危険ventの描画範囲を実Damage矩形へ一致させた。
  2x2障害物は柱/噴水。危険範囲/衝突/生成内容は変えていない。

## 新規画像と再生成

| 素材 | 保存先 | 実ゲーム接続 |
|---|---|---|
| 装備25種 | assets/items/内の既存25 PNG | templates.json icon_path → 地面/宝物庫/装備/鍛造 |
| 全床/壁/小物atlas | assets/tiles/royal/dungeon_atlas.png | StageEnvironment TILESET_TEXTURE_PATH |
| 戦闘地形/柱/噴水atlas | assets/tiles/royal/combat_atlas.png | CombatTerrainTileMapLayer |
| torch / crystal | assets/tiles/royal/torch.png・crystal.png | StageEnvironment SpriteFrames |
| 金象嵌 | assets/tiles/royal/royal_inlay.png | 開始部屋RoyalCrest |

- 装備: `tools/equipment_icon_pipeline.py import-royal-atlas tools/source_art/royal_equipment_atlas.png .`
  / `validate-catalog .`。原画の正確な生成指示は`tools/source_art/royal_equipment_prompt.md`。
- MAP: `tools/build_royal_dungeon.py`。原画`tools/source_art/royal_dungeon_source.png`。
  画像生成方針: 新規16bit王国遺跡、青灰石/古金/緑玉/深紅旗、左上光源、4x4分類atlas、完全な小物、透過背景。
  生成1254px画像を切り出し、16px契約へnearest packing。原画はtools/source_art/.gdignoreでimport対象外。
- フォント: [Google Fonts公式 M PLUS 1p](https://github.com/google/fonts/tree/main/ofl/mplus1p)のMedium。
  `assets/fonts/MPLUS1p-Medium.ttf`と`MPLUS1p-OFL.txt`を同梱。旧DotGothic16ファイルは保持するが共通UIで使用しない。

## 実施済み確認

- `build_royal_dungeon.py`: PASS。5画像、収納全4タイルの透明余白、二値alphaを検査。
- `equipment_icon_pipeline.py validate-catalog .`: PASS。25枚、64x64、画像重複なし、二値alpha、Bounds一致。
- 画像一覧/マップ素材組立見本を目視。`artifacts/royal_equipment_contact_sheet.png`、
  `artifacts/royal_dungeon_asset_preview.png`。後者は**オフライン組立**でGodotスクリーンショットではない。
- 交差コードレビューで選択の残留/Filterロック/Skip入力/Shop完了文/装飾配置/危険表示範囲を修正。
- 対象コードの静的参照/タブインデント/差分空白検査を実施。検査内の動的出力名`artifacts/%s_%s.png`は入力Resourceではなく対象外。
- 先行UI版（新Royal素材・最終フォント変更の前）のVulkan `pixel_visual_check`はPASS。
  `artifacts/pixel_after.log`。静止fixtureの3窓avg 0.436/0.428/0.438ms、p95 0.693/0.636/0.695ms、draws45。
  これは戦闘ベンチでも最終版の性能証拠でもない。初回pixel_baseline.logはcurrent_scene設定エラーで棄却。

## 起動障害の修正と追検証

- `ground_equipment_item.gd:32`の`var x := ... * side`は、未型付けArrayの要素`side`がVariantで推論不能。
  同じ問題が`equipment_screen.gd`の炉描画にも存在した。loop変数にfloat/intを付ける2行修正で解消。
- 実行検査で`EquipmentScreen._refresh()`のfocusがタブ等の場合のmetaエラーも検出。`has_meta`で対象を区別した。
- Equipment Integrationの古い検査は閉じた画面を直接_refreshし、見出しLabelをButtonと仮定していた。
  実際の_open経路とButton一覧で検査するよう更新した。製品の遅延構築は維持。
- `artifacts/startup_script_load_final.log`: 全147 GDScript load、failures=0。
- `startup_title.log` / `startup_home.log` / `startup_repair_probe.log` / `startup_developer_test_lab.log`: 各Scene起動、ERRORなし。
- `startup_vulkan_visual.log`: RTX4060/Vulkan Mobile、PIXEL_VISUAL_CHECK PASS。MAP/HUD、3択とキーボード決定、
  4商品/購入/同枠focus/Modal解除、文字収容、DotGothic16を検査。`royal_after_*.png`を目視。
- `startup_equipment_merge_check_fixed.log`: failures=0、ERRORなし。収束/結果の画像を目視、Filter/補助/保護/二重取引/Skip/即装備。
- `startup_equipment_integration_check_fixed.log`: failures=0、ERRORなし。新Drop/画像サイズ/刻印・粒子上限/取得/装備/開閉。
- 初回`startup_equipment_*_check.log`は修正前失敗記録。成功の根拠は末尾`_fixed.log`だけ。
- 動作仕様・数値・新規美術の追加変更はなし。起動復旧と関連実行エラー修正に限定。

## 壁配置・可読性・統合装備UIの追修正

- 壁の中に柱が残る原因は、入口柱の最大3セル壁奥フォールバック、void前の柱フェンス、
  柱画像をアーチとして散布する3経路だった。いずれも撤去し、入口は床敷居と正面壁の旗へ変更。
  旗/格子/松明も直下に床がある正面壁だけに限定。物理2x2柱/噴水は残す。
- 本文の小さなドット書体・過剰な縁取りを廃止。日本語Medium、本文20px・補助18px、grayscale AA。
  RichTextのnormal/bold等も同じフォント。Pixel枠/装備画像/MAPのnearest描画は変更しない。
- HUDのHP/技欄を拡大、MAP進捗に静的濃紺背景。Shop/LevelUpの本文20px、名称26px。
  Pauseの武器詳細と天賦図、戦利品、タイトルも拡大・折返し/スクロール対応。
  LVは金地/金文字を濃紺地/金文字へ変更。右上トレイは132px×2列のFlow、名前だけ省略し個数/Lv/全文Tooltipを維持。
- 装備と合成のモード状態・タブを廃止。装備済み品も一覧から選べ、同じ画面で解除して素材へ送れる。
  所持数50点でもバッグだけをスクロール、比較の長文も文字を縮めずスクロールする。
  素材は明示的に追加し、装備中/Lockの保護、二重合成防止、即装備を既存取引で維持。

### 追検証の証拠

- `artifacts/readability_vulkan_final.log`: Pixel Visual PASS。HUD/MAP、LevelUp3択、Shop4商品/購入/Focus/Modal解除、
  4武器/6Item+overflow/6Skillの幅276px・新フォント・個数/Lvを検査。
  追加fixture初回は未停止のEliteManagerから再出現した敵にPlayerが倒され、HUD画像がResultに覆われたため棄却。
  最終fixtureは全背景Manager停止、固定Map/Camera確定後にWorldを凍結、無敵Playerで撮影し、
  各captureで生存/Result非表示、HUD前後でPLAYINGを必須にした。製品の敵/ダメージ/無敵条件は変更しない。
- `artifacts/unified_equipment_vulkan_final.log`: Equipment Merge failures=0。
  全3列/装備解除→素材化→再装備/Filter/自動補助/取引/Skip/即装備に加え、
  全25Template×2=50点/6部位装備/長い日本語名/7Affix+3Special/末尾focus/比較scrollを検査。
  同じ装備の再描画で読んでいる位置を維持し、別の長文装備へ選び直すと先頭へ戻ることも確認。
  途中で一度だけ画面が閉じた14件の失敗は`unified_equipment_unexpected_close_failure.log`へ保存。
  入力/close時のstack記録付き通常focus再実行（`unified_equipment_input_probe.log`）では再現せずPASS。
  テストWindowだけunfocusableにし、外部操作を隔離した最終版を2回実行。
  `unified_equipment_vulkan_final.log` / `unified_equipment_vulkan_repeat.log`ともfailures=0/exit0。
  注入したInputMap決定操作は維持している。過去のclose原因は断定できず、外部入力混入の疑いに留める。
  製品の入力処理はこの推測で変更せず、予期しないclose時のphase/actions/stack記録をテストだけに残す。
- `artifacts/unified_equipment_integration_vulkan.log`: Equipment Integration failures=0。Drop/取得/画像接続/開閉。
- `artifacts/wall_decor_terrain_vulkan.log`: Map Terrain PASS。36seed実描画で廃止柱0、正面壁装飾、
  到達性・床/障害物不変、本編Hazard tick/柱Collision/敵追跡を確認。
- `artifacts/secondary_readability_vulkan_final.log`: Pause/天賦図最下段Tab/実Item3択/Title/モード選択PASS。
  初回`secondary_readability_vulkan.log`の4失敗はfixtureの誤り（剣士は初期WeaponInstanceなし、
  装飾段階dotまでtalentとして列挙）だった。実遺物取得/操作対象9nodeの厳密検査へ修正。
- 上記はGodot4.7.1、RTX4060/Vulkan Mobile、1600×900。採取PNGを実際に目視した。
  `readability_after_*.png`、`equipment_merge_overhaul/equipment_unified_*.png`、`secondary_readability_*.png`。
  Static fixtureのサブmsログは戦闘中の性能問題の再現/解決の証拠には使わない。
- 表示/装備検証SceneはSaveManagerの既存ephemeral sessionを使い、テスト取得/結果を通常セーブへ書き込まない。

## 残る検証

1. `tests/vfx_spawn_stall_check.tscn`: 全体のVFX上限・初回画像読出し0。
2. 物理Gamepad操作、1600×900以外のウィンドウ/OS倍率。
3. 全商品文言の組み合わせ（通常4商品・装備50点/長文の代表ケースは確認済み）。
4. 3MAPを実移動し、樽/柱/床色・Sprite重なり・HUD干渉と長時間の安定性を確認。

## 性能調査の停止境界

ユーザーよりエディタ抜き単体起動では「重たくならない」と報告。
performance_findings §5-1で止め、§5-2記録機構/§5-3職業計測へ進んでいない。
エディタ/remote debugger起因は疑いに留まり、単体で再現なしだけでは原因確定とはしない。
