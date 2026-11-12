# VSGAME 仕様書（ピボット後）

2026-11-12、ゲームをほぼ作り直す形でピボットした。この文書は「新しい方向」と「いま実際に残っているもの」だけを書く。
ピボット前の仕様は `game_specification_old.md`、ピボット前のコードと素材は `_archive/`、ピボット直前の状態は git タグ `pre-pivot`。

## 1. 新しいゲームの方向

- 横画面。1プレイ約5分。片手で遊べる操作量。
- 中心は**3つ揃えて消すパズル**（2026-11-12決定。それまでの「3×3の盤面を回してホールドする」案は取りやめ、試作は `_archive/prototype_3x3/` へ退避）。
  - 盤のマスは「キャラクターの召喚アイコン」と「強化アイコン」。
  - 職業のアイコンを3つ揃えて消すと、その職業が1体出てくる（例：弓が3つ揃うと弓兵が1体）。強化のアイコンを揃えると強化が進む。
  - 「揃えて召喚し、軍を育てる」部分は Slotbound に近づけてよい。
- 戦闘は自動。プレイヤーは戦闘を直接操作しない。
- 重視する面白さ：ギャンブル性、ルールの分かりやすさ、時短、直感的な操作。
- 職業は10職すべて残す。召喚に使わない職業は敵キャラクターにできる。
- 音楽は作り直す。

### 未定（何も前提にしない）
パズルと戦闘の関係（同時に進むか、交互か）、主人公1人を置くか召喚した軍だけで戦うか、手数や時間の制限、部屋とボスの進行、
強化の中身、攻撃・属性・演出、敵、UI、育成と保存。

## 2. いま残っているもの

### 画面と基盤（`project.godot`）
- Godot 4.7、描画は mobile。画面 1600×900、伸縮 `canvas_items`／`expand`、横向き固定。ドット絵は最近傍。
- 起動シーンはパズルの試作 `res://scenes/puzzle_prototype.tscn`（下の「パズルの試作」）。既定のフォントは DotGothic16。
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

### パズルの試作（戦闘なし、中身は仮）
- ルール `systems/puzzle/match_board.gd`（`MatchBoard`、描画なし）：マスは index = y×幅+x。隣り合う2マスを入れ替え、縦か横に同じ種類が3つ以上並ぶと消える。
  揃わない入れ替えはできない（`swap()` が拒否）。`resolve_step()` は1回ぶん消して落とし、上から新しいマスで埋める。繰り返すと連鎖。
  最初の盤は揃いが無く、動かせる手が必ずある。手が無くなったら `reshuffle()`。報酬は並び1本につき 3つで1、以降1つ多いごとに+1（`reward_for()`）。
- 設定 `data/puzzle/puzzle.json`（すべて仮）：盤 8×8、マス 88px、種類7（職業4：弓兵・剣士・騎士・魔導士／強化3：攻撃・体力・速さ）、
  入れ替え0.12秒、消える光0.2秒、落下 1500px/秒、部屋に立たせる上限32体。強化は段階を数えるだけで効果は無い。
- 表示 `ui/puzzle/match_board_view.gd`（`MatchBoardView`）：職業のマスはその職業を象徴する道具のアイコン（キャラクターの絵は載せない）、強化のマスは図形。
  操作は「隣へドラッグ」か「タップしてから隣をタップ」。処理中は入力を受け付けない。信号 `groups_cleared(groups, chain)`／`swap_rejected`／`reshuffled`／`resolved(chain)`。
- 画面 `ui/puzzle/puzzle_prototype.gd`：左に盤、右に手数と最大連鎖、召喚数、強化の段階、一言、召喚先の部屋、やり直しボタン。
  職業を揃えると、その職業（`player.tscn` に `apply_character()`）が部屋に現れて待機する。
- 実画面 `docs/screens/puzzle_prototype.png`、撮影は `tools/capture_puzzle.tscn`。

### データ
- `resources/character_data.gd`：`id`、`display_name`、`sprite_folder`、`max_hp`、`move_speed`、`icon_path`／`icon_name`（職業を象徴する道具のアイコン）。
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
- `assets/icons/class/<id>.png`（10職の象徴アイコン、64px。弓兵＝弓、剣士＝剣、騎士＝騎士兜、魔導士＝杖、ソルジャー＝羽飾りの兜、重装斧兵＝戦斧、
  槍兵＝槍、司祭＝司祭杖、死霊術師＝大鎌、聖堂騎士＝戦鎚。退避した装備アイコンから選んだ）。
- `assets/sprites/player/`（10職。待機・歩行・攻撃・被弾・死亡のコマ）、`assets/fonts/`（DotGothic16、M PLUS 1p。OFL）。

### 検査（すべてheadlessで実行、エラー・警告0件が基準）
- `--script res://tests/script_load_check.gd`：全スクリプトの読込。
- `res://tests/character_base_check.tscn`：10職の生成、見た目とステータスの反映、待機アニメが進むこと、無入力で動かないこと。
- `res://tests/room_base_check.tscn`：起動シーンに選んだ職業が1人だけ立ち、待機アニメが進み、動かず、カメラ以外のノードとUIが無いこと。
- `res://tests/puzzle_prototype_check.tscn`：初期盤（揃いなし・手あり、30通り）、無効な入れ替えの拒否、消えて落ちて埋まること、報酬の数、
  実画面でスワイプとタップ、弓兵3つで弓兵が部屋に現れて待機、強化の段階、処理中の入力拒否、自動20手で盤が毎回きれいなこと、やり直し。
- `--quit-after 180`：起動シーンの起動。

## 3. 退避したもの（`_archive/`）
攻撃・属性・状態異常・弾・エフェクト（pixelfx含む）、天賦図と完成スキル、レベルアップ・装備・鍛造・ショップ・金貨、ダンジョン生成・敵・ボス・精鋭・波、
UI一式、音源、セーブ、旧検査と制作ツール、資料とダッシュボード。元のフォルダ構成のまま置き、`.gdignore` でGodotには読み込ませない。
書き換えたファイル（player、各Component、CharacterData、DataLoader、GameManager、職業JSON）の元の版も同じ場所にある。詳細は `_archive/README.md`。

## 4. 次に決めること
再利用の見込みは `docs/pivot_reuse_inventory.md`（ロードマップ案はパズルへの方向転換前のもの）。
着手前に決める点：パズルと戦闘の関係、主人公の有無、手数か時間の制限、1プレイの区切り方。
