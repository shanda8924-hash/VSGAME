# VSGAME

朽ちた王国の地下を舞台にした、ピクセルアートの5分サバイバル。
6職から1人を選び、壁のない広い床で約4分の大群戦を戦い、240秒に現れる強敵由来のボスを倒すとクリア。

- エンジン: Godot 4.7.1、GDScript
- 画面: 1600×900 基準の横画面。PC と スマートフォン横画面（タッチ操作）を対象
- 正式な仕様: `game_specification.md`（唯一の正。実装と食い違う場合は仕様書と実装を同じ作業内で同期する）

## 開き方

1. Godot 4.7.1 を入れる（`C:\Users\USER\Desktop\Godot_v4.7.1-stable_win64.exe`）。
2. Godot の「プロジェクトをインポート」でこのフォルダの `project.godot` を開く。
3. F5 で実行。タイトル → 継承者（職業）とステージを選ぶホーム → 戦闘 → 結果。

## 操作

| 操作 | キーボード | ゲームパッド |
|---|---|---|
| 移動 | WASD / 矢印 | 十字キー / 左スティック |
| 通常攻撃 | 自動（射程内の敵へ向く） | 自動 |
| 回避 | K | 既定なし |
| 職業技 | L | A（南） |
| 反撃（ジャスト回避後） | J | 既定なし |
| 調べる（宝箱・階段・補給箱） | E | X |
| 所持品・装備 | C（I も同じ画面） | Y |
| 天賦図 | T | Back |
| 地図 | M | なし |
| 停止・戻る | Esc | B |

スマートフォンでは左に仮想スティック、右に回避・技・反撃・調べる・装備、上に地図・停止のボタンが出る。

## 1 Run の流れ

1. ホームで職業と約5分のステージ（3テーマ）を選ぶ。継承の欠片で未解放の職業を開ける。
2. 0〜240秒: 画面外から敵が湧き続ける。撃破の経験値でレベルアップし、8種の戦闘強化か職業技を1つ選ぶ（選択中は時間停止）。
3. 75秒に装備箱（60%）、150秒に補給箱。補給箱を開けると「灯火の遺物商」で買い物。
4. 240秒: 通常の増援が止まり、テーマの強敵2種から1体がボスとして出現。5分を過ぎても倒すまで続く。
5. 撃破後: 落ちた装備・討伐宝箱を回収し、帰還の階段を調べると結果へ。撃破数・残金・回収装備が継承の欠片になる。

## フォルダ

| 場所 | 内容 |
|---|---|
| `scenes/` | `title.tscn`（起動）、`game.tscn`（戦闘）、`developer_test_lab.tscn`（デバッグ版のみ） |
| `autoload/` | EventBus、DataLoader、GameManager、AudioManager、SaveManager |
| `systems/` | 出現（`wave_spawner.gd`）、進行（`map_run_controller.gd`）、ボス、ショップ、装備、状態異常 |
| `entities/` | Player、敵、投射物、宝箱、地形 |
| `components/` | HP・移動・攻撃・経験値などのコンポーネント |
| `ui/` | ホーム、HUD、レベルアップ、ショップ、所持品、天賦図、ポーズ、結果 |
| `data/` | JSON データ（職業、敵、ボス、強化、装備、難易度曲線、ショップ） |
| `assets/` | スプライト、タイル、UI、VFX、音、フォント |
| `tests/` | 実ゲーム経路の自動検証 |
| `tools/` | 素材生成・撮影用のスクリプト |
| `dashboard/dist/` | 開発ダッシュボード（静的サイト。`dist` を Web サーバーの root として配信） |
| `docs/` | 開発運用（`codex_workflow.md`）、現在状態（`codex_handoff.md`）、整理計画（`cleanup_and_brushup_plan.md`） |

`artifacts/`（実画面と検証ログ）、`tmp/`、`tools/source_art/`（生成元の素材）は git 管理外。

## 検証

全スクリプトの読み込み検査（プロジェクト直下で実行）:

```bash
Godot_v4.7.1-stable_win64_console.exe --headless --audio-driver Dummy --path . --script res://tests/script_load_check.gd
```

5分サバイバルの実経路検査（出撃から結果まで）:

```bash
Godot_v4.7.1-stable_win64_console.exe --path . --rendering-driver opengl3 --fixed-fps 60 --audio-driver Dummy --log-file <書込可能なパス> -- --survival-check --mute-audio
```

タッチ横画面は `--touch-preview` を追加する。他の検査は `tests/*.gd` の冒頭コメントと `docs/codex_handoff.md` を参照。

## 開発の進め方

- 作業前に `git status --short` と `docs/codex_handoff.md` を読み、Scope / Out of Scope を決める（`AGENTS.md`）。
- 仕様を変えたら同じ作業内で `game_specification.md` の該当章を更新する。
- 大きな変更の後は `docs/dashboard_update_rules.md` に従って `dashboard/dist/data/` を更新する。
- 整理と UI 改善の進め方は `docs/cleanup_and_brushup_plan.md` の Phase に従う。
