# MAP建築整理（2026-09-05）

## 対象と原因

ユーザー画像の橙の格子状エリアは`DungeonGenerator._apply_hazard()`で作るHazard矩形。
通常MAPの地形割当と`MapRunController`のArea生成を撤去した。見えない床ダメージは残さない。
旧Resource/Dataや敵の毒床などは今回の削除対象ではない。

旗の暗い穴は、原画に透過があってもpack時に壁天面を焼き込み、さらに主TileMapの正面壁を
旗タイルへ上書きしていたため。元画像の透過部分を保持し、主壁を変更しないOverlayへ分離した。
床柱/噴水も同様に、焼き込まれた矩形床をやめ、連続した床の上に透過画像を置く。
2×2の通行不可判定は下地のCollision alternative 3に保持する。

緑の横短壁はChokepointの横配置分岐。天面/正面のランダム混在も不自然さの原因だった。
横配置は撤去し、赤の縦短壁は中央3セルの開口とともに保持。表示は主壁の方向別画像に統一した。

## Boss広間

- 最遠部屋を`DungeonMap.boss_room_index`としてGenerator/Stage/Controllerで共有。
- 最遠候補を受理する前に14×14の広さを確保し、隣室間隔と外周条件を検査。
  後から拡幅して他室へ食い込ませない。同距離は後indexで決定的。
- 全196床を空け、柱/短壁/Hazard/Elite/探索宝箱/回復祭壇を除外する。
- 青灰色の既存床、内周の古金象嵌、256world pxの中央床紋章、
  実在する正面壁に左右一対の旗/壁付柱/松明。置けない片側装飾を無理に追加しない。
- 樽/瓦礫/結晶を広間へ無作為に散布しない。ゲートの旧紫矩形は描かず、紋章下に20pxの案内。
- 撃破/時間の封印条件、E/X、Boss出現位置、Boss戦/報酬/ショップ仕様は維持。

## 画像

| 保存先（`assets/tiles/royal/`） | 内容 | 本編接続先 |
|---|---|---|
| `wall_overlays.png` 128×64 | 元の透過原画から旗/壁付柱/格子/浮彫/床柱/噴水を抽出 | `WallOverlayTileMapLayer` Source 3 |
| `boss_floor_seal.png` 128×128 | 新規生成の王冠・同心環の床象嵌 | `StageEnvironment/BossFloorSeal` |
| `boss_floor_border.png` 48×48 | 新規生成の9-slice古金の床縁 | `DecorationTileMapLayer` Source 4 |

組み込み`image_gen`を使用。全プロンプトと原画の対応は`tools/source_art/map_architecture_manifest.json`。
画像生成後はユーザー承認済みのPythonで切り出し、最近傍縮小、二値Alpha整理だけを行った。
`tools/build_royal_dungeon.py`で全て再生成できる。透過は0/255、Nearest、原画は`.gdignore`で実行時import対象外。
常時process、Shader、Particle、全画面エフェクトを追加しない。

## 変更ファイル

- `systems/dungeon_generator.gd` / `dungeon_map.gd` / `map_run_controller.gd`
- `entities/stage_environment/stage_environment.gd` / `.tscn` / `map_landmark.gd`
- `tools/build_royal_dungeon.py`、上記画像と原画/manifest
- `tests/dungeon_reservation_check.gd/.tscn`、`tests/map_architecture_check.gd/.tscn`
- `tests/map_terrain_rhythm_check.gd`（撤回Hazardと透過柱に合わせた期待値。追跡Collision検証は保持）
- `game_specification.md` §34.3/34.4/35.7、`docs/codex_handoff.md`

既存の未コミット変更を保持。`data/`、装備UI、戦闘/経済数値、Save構造は変更していない。
性能調査は引き続き単体起動切り分け後で停止し、別の記録機構は追加していない。

## 検証

Godot 4.7.1 / Vulkan Forward+ / NVIDIA RTX 4060。

| 検証 | 結果・ログ |
|---|---|
| 3製品MAPサイズ×128 seed | 384MAP全床到達可能、14×14 Boss広間、隣室非重複、Elite数1/2/2維持、Hazard 0。`artifacts/dungeon_reservation_check.log` |
| 小MAP・同距離・短壁の向き | 8/16/24/32マスのfallback、同距離の選定、縦壁保持/横壁なし PASS。同上 |
| 本編Scene統合 Headless/Vulkan | 36seed、同期3/非同期4build、壁Overlay296セル/床柱96セル/縦壁26セル、下地Collisionと透過PNGを検証。`artifacts/map_architecture_headless.log` / `map_architecture_vulkan.log` |
| Bossの実進行 | 封印中の操作→解放→Interaction→実Boss生成→二重起動拒否→死亡→報酬宝箱1個。通常Saveはephemeral sessionで保護 |
| 既存地形回帰 | 36seed、18,248壁境界セル、柱の迂回追跡135.8→81.9px、危険床なし。`artifacts/map_terrain_architecture_check.log` |
| 起動前のScript検査 | 全156script実load失敗0。`artifacts/map_architecture_script_load.log` |

最終検証ログの実行エラーは0。初回`map_architecture_import.log`は制限環境のOSキャッシュアクセス失敗と
編集中の未定義helperを記録している。編集完了後の`map_architecture_import_verified.log`は正常。
初回ログを現行Runtimeの成功証拠にはしていない。

実描画画像は`artifacts/map_architecture/`の`normal_room.png`、`banner_wall.png`、`vertical_wall.png`、
`boss_chamber.png`、`boss_active.png`。本編の生成/描画/Interactionを使い、テスト用に配置とCameraを操作した画像。
`boss_chamber_overview.png` / `boss_alive_overview.png`はHUDを隠しCameraを1.0倍にした全景確認用。
撮影後にCamera制限/倍率/HUDを復元し、製品の表示設定は変更していない。
自然プレイでの3MAP通し、長時間、別GPU/解像度は未実施。変更は新しいランの生成から反映される。
