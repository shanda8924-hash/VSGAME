# VSGAME 仕様書（ピボット後）

2026-11-12、ゲームをほぼ作り直す形でピボットした。この文書は「新しい方向」と「いま実際に残っているもの」だけを書く。
ピボット前の仕様は `game_specification_old.md`、ピボット前のコードと素材は `_archive/`、ピボット直前の状態は git タグ `pre-pivot`。

## 1. 新しいゲームの方向

- 横画面。1プレイ約5分。片手で遊べる操作量。
- 戦闘は自走式。主人公1人が自動で移動・攻撃する。プレイヤーは戦闘を操作しない。
- 進行は「1部屋＝1戦闘」の連続。8部屋前後のあとにボス。
- 成長は3×3の盤面。9マスが主人公のビルドそのもの。
  - 部屋をクリアするごとに1回回せる。残したいマスはタップでホールドできる。
  - 揃ったライン（縦・横・斜め）の効果が、次の部屋で発動し続ける。
- 重視する面白さ：ギャンブル性、ルールの分かりやすさ、時短、直感的な操作。
- 職業は10職すべて残す。主人公に使わない職業は敵キャラクターにできる。
- 音楽は作り直す。

### 未定（何も前提にしない）
盤面に何を載せるか、攻撃・属性・演出をどう作るか、敵・ボス・部屋の中身、UI、育成と保存。あとで1から決める。

## 2. いま残っているもの

### 画面と基盤（`project.godot`）
- Godot 4.7、描画は mobile。画面 1600×900、伸縮 `canvas_items`／`expand`、横向き固定。ドット絵は最近傍。
- 起動シーンは盤面の試作 `res://scenes/board_prototype.tscn`（下の「盤面の試作」）。既定のフォントは DotGothic16。
- 部屋のシーン `res://scenes/main.tscn`＋`scenes/main.gd`：何もない1部屋（床 704×384px、32px格子と枠を `_draw` で描くだけ。当たり判定なし）、
  原点に固定した `Camera2D`（2倍）、中央に `Player`。攻撃・敵・UIは無い。確認用に起動引数 `-- --character=<id>` で職業を選べる。実画面は `docs/screens/pivot_base_room.png`。
- オートロードは2つ：`DataLoader`、`GameManager`。
- オーディオバスは Master／Music／SFX（`default_bus_layout.tres`）。音源は無い。

### キャラクター
- `entities/player/player.tscn`：`Player`（CharacterBody2D、グループ `player`）＋ `AnimatedSprite2D`（1.65倍）＋ 円の当たり判定（半径20）＋
  `HealthComponent`／`MovementComponent`／`AnimationComponent`。カメラ・攻撃・入力は持たない。
- `entities/player/player.gd`：`GameManager.get_selected_character()` の職業を `apply_character()` で反映（見た目・HP・移動速度）し、待機アニメを再生する。
- `entities/entity_base/entity.gd`：`MovementComponent` の速度で `move_and_slide()` するだけの基底。
- `components/health_component.gd`：`max_hp`／`current_hp`、`apply_damage()`／`heal()`、信号 `damaged`／`healed`／`died`。防御や無敵時間は無い。
- `components/movement_component.gd`：`base_speed × speed_multiplier × direction`。
- `components/animation_component.gd`：移動方向で idle／walk と左右反転、`damaged` で hurt、`died` で death。`play_attack()` は残してあるが呼び出し元は無い。
- `entities/sprite_sheet_builder.gd`：`assets/sprites/<sprite_folder>/` の画像から `SpriteFrames` を組む。

### 盤面の試作（ロードマップ案Aの1段目。戦闘なし、中身は仮）
- ルール `systems/board/board_model.gd`（`BoardModel`、描画なし）：マスは左上から 0..8。`spin()` はホールドしていないマスだけ引き直す。
  ラインは横3・縦3・斜め2の8本で、3マスが同じ記号なら揃い（`matched_lines()`）。`toggle_hold()` は上限を超える追加を拒否する。抽選は記号の重みに従う。
- 設定 `data/board/board.json`（すべて仮）：1プレイ8回、ホールド上限4、ホールドは回したあとも残る、列が止まる時刻 0.35／0.55／0.75秒、
  記号6種（丸・三角・四角・菱・星・十字。意味も効果も無く、重みは等しい）。
- 表示 `ui/board/board_view.gd`（`BoardView`）：マスのタップ（マウス／タッチ）でホールド、上限を超えると赤く弾く。回すと列が左から順に止まり、
  揃ったラインを1本ずつ光らせてから `spin_finished(lines)` を出す。回転中は操作を受け付けない。記号は図形を描くだけで画像は使わない。
- 画面 `ui/board/board_prototype.gd`：「回す」ボタン（Space・Enterでも可）、回した回数、ホールド数、揃ったラインの合計、結果の一言。8回で終わり、「もう一度」で始め直す。
- 実画面 `docs/screens/board_prototype_*.png`、撮影は `tools/capture_board.tscn`。

### データ
- `resources/character_data.gd`：`id`、`display_name`、`sprite_folder`、`max_hp`、`move_speed`。
- `data/characters/*.json`（10職）。

| id | 名前 | HP | 移動速度 |
|---|---|---|---|
| archer | 弓兵 | 85 | 168 |
| armored_axeman | 重装斧兵 | 150 | 105 |
| knight | 騎士 | 100 | 182 |
| knight_templar | 聖堂騎士 | 140 | 119 |
| lancer | 槍兵 | 105 | 161 |
| necromancer | 死霊術師 | 80 | 140 |
| priest | 司祭 | 100 | 140 |
| soldier | ソルジャー | 100 | 140 |
| swordsman | 剣士 | 110 | 147 |
| wizard | 魔導士 | 75 | 140 |

- `autoload/data_loader.gd`：`characters`（id → CharacterData）、`get_all_characters()`。
- `autoload/game_manager.gd`：`selected_character_id`（既定 `soldier`）、`get_selected_character()`（無効なIDは既定へ戻す）。

### 素材
- `assets/sprites/player/`（10職。待機・歩行・攻撃・被弾・死亡のコマ）、`assets/fonts/`（DotGothic16、M PLUS 1p。OFL）。

### 検査（すべてheadlessで実行、エラー・警告0件が基準）
- `--script res://tests/script_load_check.gd`：全スクリプトの読込。
- `res://tests/character_base_check.tscn`：10職の生成、見た目とステータスの反映、待機アニメが進むこと、無入力で動かないこと。
- `res://tests/room_base_check.tscn`：起動シーンに選んだ職業が1人だけ立ち、待機アニメが進み、動かず、カメラ以外のノードとUIが無いこと。
- `res://tests/board_prototype_check.tscn`：ライン判定8本、ホールド上限、ホールド以外だけ引き直すこと、重みどおりの抽選、実画面でのクリックとボタン操作、
  回転中の入力拒否、8回で終了と始め直し。
- `--quit-after 180`：起動シーンの起動。

## 3. 退避したもの（`_archive/`）
攻撃・属性・状態異常・弾・エフェクト（pixelfx含む）、天賦図と完成スキル、レベルアップ・装備・鍛造・ショップ・金貨、ダンジョン生成・敵・ボス・精鋭・波、
UI一式、音源、セーブ、旧検査と制作ツール、資料とダッシュボード。元のフォルダ構成のまま置き、`.gdignore` でGodotには読み込ませない。
書き換えたファイル（player、各Component、CharacterData、DataLoader、GameManager、職業JSON）の元の版も同じ場所にある。詳細は `_archive/README.md`。

## 4. 次に決めること
再利用の見込みと、実装順のロードマップ案（A：盤面を先に／B：戦闘を先に／C：最小の1周を先に）は `docs/pivot_reuse_inventory.md`。
着手前に決める点：部屋の見せ方（上から／横から）、1戦闘の長さ、ラインの効果の持続、負けたときの扱い。
