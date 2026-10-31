# VSGAME UI世界観刷新

## 目的

現行の読みやすさと操作経路を保ったまま、全画面を「朽ちた王国の地下を踏破する、鮮やかな16bit遺跡ファンタジー」へ統一する。戦闘数値、報酬抽選、セーブ形式、入力規則は変更しない。

## 参照したゲームと採用する考え方

- [Halls of Torment](https://store.steampowered.com/app/2218750/Halls_of_Torment/)：暗い石造空間でも文字と選択肢が埋もれない素材密度、円形アイコンを中心にした成長選択。
- [Death Must Die](https://store.steampowered.com/app/2334730/Death_Must_Die/)：装備・祝福・報酬を、名前より先に絵で判別できる情報設計。
- [Hades](https://store.steampowered.com/app/1145360/Hades/)：画面ごとに一つの強い象徴と色を置き、選択の意味を演出する構図。
- [Children of Morta](https://store.steampowered.com/app/330020/Children_of_Morta/)：細かなPixel artと現代的な明暗を両立し、天賦を段階ごとに読ませる整理。

画面構成や既存素材を複製せず、上記の原則をVSGAME固有の王家の封印意匠へ翻訳する。

## 共通UI文法

### 色と素材

- 背景：濃紺から青灰の地下石壁。
- 構造：古金の金具、細い石板の継ぎ目、黒い影。
- 主役色：青緑の封印石。危険と鍛造だけ朱赤・橙を使う。
- 文字：生成画像へ焼き込まず、Godot側のPixel fontで表示する。

### 装飾の三段階

1. **主画面**：王家の紋章と太い九分割枠。タイトル、レベルアップ、戦利品、結果に限定する。
2. **区画**：石板と隅金具。装備、HUD、タブ、一覧を分ける。
3. **選択カード**：上部の素材帯、左の色線、下部の決定帯。アイコン背面の菱形は使わない。

すべてへ同じ紋章を重ねず、重要度に応じて密度を変える。これにより統一感を保ちながら、画面の主役を見失わない。

## 画面別の変更

- タイトル／キャラクター選択：生成した地下王宮の門を背景にし、封印を解いて探索へ入る導線にする。
- 戦闘HUD：HP・経験値・職業技を石板化。武装、戦利品、完成大技は実アイコン付きの小型札にする。
- レベルアップ／ボス報酬／完成大技／部屋選択：共通の祭壇枠とカードを使う。英語併記を外し、日本語名を一行で優先する。
- Shop：同じ祭壇だが金貨色を強め、購入状態をカード下部で判別させる。
- Pause／天賦：選択中タブだけ青緑の封印色を強め、天賦ノードは段階と取得状態を優先する。
- コンセプト構築：王家の戦術盤として祭壇化し、起点・スキル・補助を金・青緑・紫で分ける。
- 装備／鍛造：装備者、所持品、炉を金・青緑・橙の三領域に分ける。
- Result：探索失敗と古王国踏破を一枚の記録石板として表示する。

## 生成素材

- `tools/source_art/royal_gate_title_source.png`：ImageGen原画。
- `assets/ui/backgrounds/royal_gate_title.png`：1600×900、Nearestで整えた実装用画像。
- `assets/ui/royal/royal_frame_major.png`：64×64の九分割用Pixel枠。
- 再生成用Promptは`tools/source_art/royal_gate_title_prompt.md`に保存する。

## 実装上の境界

- UIスクリプトのシグナル、ボタン処理、報酬確定、画面遷移は既存のまま使う。
- 動的カードとHUD札は共通`PixelUIStyle`から生成する。
- 画像filterはNearest。装飾は常時processせず、サイズ・選択状態が変わった時だけ再描画する。

## 検証

- 全191 GDScript実load：failure 0。
- `secondary_ui_readability_check`：Level Up、Pause、天賦上下、Boss Item、完成大技、Title通常／経路選択を実描画しPASS。
- `pixel_visual_check`：通常HUDと最大表示HUD、Level Up、Shop購入前後を1600×900で確認しPASS。HUDトレイ幅276px、動的Label 18px以上。
- `shop_runtime_check`：4カテゴリ、購入、同枠補充、価格不足、再抽選、退出を確認しPASS。
- `map_exploration_runtime_check`：3MAPのBoss報酬、遷移、Run ClearまでPASS。
- `room_mvp_visual_check`：宝箱報酬、コンセプト構築、戦闘復帰を確認しPASS。
- `iai_and_mode_check`／`equipment_integration_check`：Title経路選択と装備操作を確認しPASS。
- 目視画像：`artifacts/ui_world_home.png`、`ui_world_equipment.png`、`ui_world_result.png`、`secondary_readability_*.png`、`readability_after_*.png`。
