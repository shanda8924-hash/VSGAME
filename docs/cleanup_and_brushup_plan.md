# VSGAME 整理・ブラッシュアップ実施計画（2026-10-31）

2026-10-31時点の調査（`docs/codex_handoff.md`、`game_specification.md` 末尾の現行節、
実コード、`artifacts/` の実画面）に基づく実施計画。ゲーム仕様を変える項目は
「判断事項」として分け、ユーザーの決定後に `game_specification.md` の差分として確定する。

## 0. 前提と原則

- 現行のゲームは「5分サバイバル」（床のみの広い戦場、約4分の大群戦、240秒で強敵由来のボス、撃破でクリア）。
- `game_specification.md` が唯一の正。仕様に無いことは実装しない。仕様が変わる作業は差分（Markdown patch）を成果物に含める。
- 1 Session は1 Phase（または1 Phase内の1 Step）に限定し、開始時に Scope / Out of Scope を明示する。
- 各 Phase の終了時に `docs/codex_handoff.md` と関係する `dashboard/dist/data/*.json` を更新する。
- 無関係な未コミット変更は触らない。ただし Phase 0 は「全ての未コミット変更を保存する」作業なので例外。

## 1. 全体像

| Phase | 内容 | 仕様変更 | 目安 | 依存 |
|---|---|---|---|---|
| 0 | 保全：未コミット変更の保存、`.gitignore`、スナップショット削除 | なし | 1 Session | なし |
| 1 | 文書整理：仕様書 v4.0（現行／履歴の分離）、README 書き直し、ダッシュボード一本化 | 記述整理のみ | 2〜3 Session | 0 |
| 2 | 不要物の削除・退避（コード、データ、テスト、ツール） | なし（廃止済みのものだけ） | 2 Session | 0, 1 |
| 3 | 判断事項の確定と仕様パッチ（メタループ、ステージ差、残す機能、ボス転用、所持品） | あり | ユーザー判断＋1 Session | 1 |
| 4 | 戦闘HUDブラッシュアップ | なし（§35/§40 の範囲内） | 2 Session | 0 |
| 5 | ホーム、リザルト、スマホ操作、所持品画面 | 一部あり（Phase 3 の結果に従う） | 3 Session | 3, 4 |
| 6 | 実プレイ検証と既知バグ修正 | なし | 2 Session | 2, 4, 5 |

Phase 4 は Phase 0 の直後から Phase 1〜3 と並行できる。Phase 5 の所持品画面だけは Phase 3 の判断を待つ。

## 2. 判断事項（ユーザー決定が必要）

| ID | 問い | 推奨 | 決定が無い場合の既定 |
|---|---|---|---|
| D1 | 継承の欠片の使い道（職業解放の後） | ステージ解放 or 恒常強化の小さな木を追加 | 現状維持（職業解放のみ）。Phase 5 のリザルトは「次の解放まで」の表示だけ行う |
| D2 | 3ステージの差別化 | 床色・出現曲線・箱の時刻を変え、ボス肖像付きの選択へ | 現状維持（敵の顔ぶれとボスのみ） |
| D3 | 5分アリーナに合わない機能：M地図、T天賦図、C所持品、J反撃／ジャスト回避、コンボ表示 | 地図は撤去。天賦図は内容がある職業だけ表示。J反撃は撤去かボス戦限定。コンボは撤去か効果を定義 | 全て残し、HUDの常駐案内だけ畳む |
| D4 | 職業転用ボス（槍兵、死霊術師、聖堂騎士＋司祭） | 作らないなら4職のデータと強化16件を削除。作るなら別 Phase として計画 | 保持（削除も実装もしない） |
| D5 | 所持品と鍛造の深さ | Run中は「装備中5部位＋新規取得との比較」のみ。鍛造は Run 間へ | 現状維持 |
| D6 | 旧テストの扱い | `tests/legacy/` へ移し、`script_load_check` の対象から外す | 削除せず移動 |
| D7 | ダッシュボードの正本 | リポジトリ内 `dashboard/dist` を正本にし GitHub Pages で公開。ChatGPT Sites 側は停止 | 両方残す（更新は repo 側のみ） |
| D8 | `artifacts/` の扱い | git 管理から外し、最新の実画面だけ `docs/screens/` に残す | 外すだけ |

## 3. Phase 詳細

### Phase 0 保全

目的: 2026-08-25 以降の未コミット変更（1390件）を git 履歴に残し、手動バックアップ依存をやめる。

Scope: git 操作、`.gitignore`、`tools/source_art/` のコードスナップショット。
Out of Scope: ゲームコード・データの内容変更。

手順:

1. 安全策として現在の状態へタグを付ける: `git tag backup/pre-cleanup-20261031`。
2. `.gitignore` に追加: `artifacts/`、`tmp/`、`tools/source_art/`、`.codex-runtime-test/`、`.godot-test-user-visual/`。
   既に追跡中の `artifacts/`（370件）は `git rm -r --cached artifacts` で追跡だけ外す。
3. `tools/source_art/{open_field_survival,five_minute_survival,survival_growth}` を削除する（コードのコピー。
   `change.diff` は参考として `docs/history/` へ移してよい）。
4. 次の単位でコミットする（順序どおり）。各コミットの前に `git add` の対象を `git status --short <path>` で確認する。
   1. `chore: ignore artifacts, tmp, source_art snapshots`（`.gitignore`、`git rm --cached`）
   2. `refactor: remove fusion/element/room runtime`（`D` 扱いの `systems/`、`effects/`、`ui/room_select`、`ui/fragment_select`、`assets/vfx/fusions`、`assets/vfx/elements`、`resources/`）
   3. `feat: survival runtime`（`systems/`、`entities/`、`components/`、`autoload/`、`scenes/`、`effects/` の追加・変更）
   4. `data: survival curve, strong-enemy bosses, survival upgrades, shop`（`data/`）
   5. `feat: survival UI`（`ui/`）
   6. `assets: survival art`（`assets/`）
   7. `test: survival checks`（`tests/`）
   8. `tools: capture and build scripts`（`tools/`）
   9. `docs: spec, handoff, dashboard`（`game_specification.md`、`docs/`、`dashboard/`、`AGENTS.md`、`README.md`、`project.godot`）
5. `main` ブランチを現在のブランチから作り、以後は `main` で作業する（`git branch main && git checkout main`）。
   旧ブランチ `codex/*` は履歴として残す。

完了条件: `git status --short` が空。`script_load_check` が失敗0。`five_minute_survival_check` が PASS。

### Phase 1 文書整理

目的: 「現行仕様」を1か所で読める状態にする。

Step 1-1 仕様書 v4.0
- `game_specification.md` を「第I部 現行仕様」「第II部 履歴」に分ける。
- 第I部は現行の章だけを再構成する: 概要、アーキテクチャ、コアループ（5分サバイバル）、ステージと出現曲線（2026-10-13）、
  敵階級と Roster（2026-09-21）、強敵とボス（2026-10-13）、職業6職と職業技・流派（§19、§42.1）、
  レベルアップ8強化（2026-10-13、2026-10-25）、装備と浮遊武器（§23〜25 の現行部分、2026-10-01、2026-10-04）、
  ショップ（§37）、状態異常（§36）、UI（§35、§40、2026-10-25）、音（§18）、性能（§38）、保存データ、検証方法、Developer Test Lab（§30）。
- 第II部へ移すもの: §3 旧コアループ、§4〜§5 ダンジョン生成と精鋭部屋、§15 Fusion、§31 ROOM、§32 Concept、§33、§34 3MAP、
  §35.9〜35.15 HD-2D、2026-09-13〜09-27 の各モード、2026-10-12 アリーナ、§41 の初期ダッシュボード記述。
- 各章の末尾に「根拠ファイル」（コード・データ・テスト）を1行で書く。
- 成果物: `game_specification.md`（v4.0）、変更の要約を `docs/spec_v4_migration.md`。

Step 1-2 README
- 1ページにする: 開き方（Godot 4.7.1）、操作、現行の流れ、仕様書への誘導、検証コマンド。存在しない `design_proposal_v1.md` への参照を消す。

Step 1-3 ダッシュボード一本化（D7）
- `dashboard/dist`（1.6.19）を正本とし、外部チェックアウト（1.6.6）との差分で必要な表示改善だけを取り込む。
- `project.json` の `updatedAt`、`roadmap.json` の Task 状態を Phase 0〜1 の結果へ更新する。
- 公開は `.github/workflows/dashboard-pages.yml`。リモートが無いため、公開先リポジトリの作成はユーザー作業。

完了条件: 第I部だけ読めば現行の作り方が分かる。README から仕様書と検証へ辿れる。

### Phase 2 不要物の削除・退避

目的: 本編から到達しないコード・データ・テストを減らし、`script_load_check` とテストの対象を現行に絞る。

Scope: 下表の対象。Out of Scope: 本編に接続中のシステムの変更、バランス変更。

| 対象 | 処置 | 事前確認 |
|---|---|---|
| `tmp/`、`.codex-runtime-test/`、`.godot-test-user-visual/` | 削除 | なし |
| `data/difficulty/default.json`、`data/difficulty/map_exploration.json`、`data/rooms/`、`data/stages/` | 削除 | `difficulty_curve_id` の参照が `five_minute_survival` のみであること |
| `data/fragments/`、`data/concepts/`、`data/balance/concept_system.json`、`data/skills/completed_skills.json` | 削除 | `grep -rn` で文字列参照が Test Lab と削除対象テストだけであること |
| `ui/concept_board/`、`ui/concept_select/`、`systems/concept_system.gd`、`scenes/game.tscn` の `ConceptSystem` ノード、`hud.gd` の `completed_skill_row` | 削除 | `scenes/developer_test_lab.gd` の該当タブを同時に外す |
| `systems/elite_room_manager.gd`、`systems/elite_hazard.gd`、`systems/orc_step_slash.gd`、`entities/stage_environment/miner_worker.gd`、`painted_map_props.gd` | 削除候補 | クラス名と `preload("...")` 文字列の両方で参照0を確認。`strong_enemy_special.gd` は文字列参照があるため保持 |
| `systems/dungeon_generator.gd`、`exploration_layout.gd`、`GameManager.generate_exploration_map` の非サバイバル分岐 | 保持（Test Lab が使用） | D3 で Test Lab を縮小する場合に再検討 |
| 旧テスト（`floor_run`、`sector`、`RoomRun`、`hd2d`、`elite_room`、`fusion`、`fragment` を参照する32件） | `tests/legacy/` へ移動（D6）。`script_load_check` の除外対象に `legacy` を追加 | 現行6件（`five_minute_survival_check`、`survival_growth_check`、`survival_home_check`、`equipment_auto_attack_check`、`script_load_check`、`runtime_exit_cleanup`）は残す |
| `tools/capture_*`、`tools/preview_*`、`tools/*.py`、`*.ps1` | 用途を1行ずつ `tools/README.md` に書く。書けないものは削除 | なし |
| `data/characters/{lancer,knight_templar,priest,necromancer}.json`、`data/upgrades/class_{lancer,knight_templar,priest,necromancer}_*`（16件） | D4 の結果に従う | D4 |

手順: 1件の削除ごとに `script_load_check` を回し、Phase の最後に現行テスト6件を回す。削除は1コミット1テーマ。

完了条件: `script_load_check` 失敗0、現行テスト6件 PASS、`git status` が空。削除一覧を `docs/codex_handoff.md` と `dashboard/dist/data/decisions.json` に記録。

### Phase 3 判断事項の確定と仕様パッチ

目的: D1〜D5 を決め、`game_specification.md` 第I部に反映する。

手順:
1. D1〜D5 それぞれに、現状・選択肢・推奨・影響範囲（ファイル、テスト、ダッシュボード）を1枚にまとめて提示する。
2. ユーザーの決定ごとに仕様の差分を書き、第I部へ適用する。
3. 決定を `dashboard/dist/data/decisions.json` と `relations.json` の判断区分へ反映する。

完了条件: 仕様書とダッシュボードの判断区分が一致。実装はこの Phase では行わない。

### Phase 4 戦闘HUDブラッシュアップ

目的: メニュー画面と同じ石板・古金の言語を HUD に適用し、5分ゲームとしての情報優先度を正す。仕様 §35.3 と §40 の範囲内で行い、数値・入力・保存は変えない。

Scope: `ui/hud/hud.gd`、`ui/hud/hud.tscn`、`ui/common/retro_*`、`ui/hud/mobile_controls.gd` の表示部分。
Out of Scope: 戦闘ロジック、レベルアップ・ショップ画面、D3 で決まる機能の撤去。

作業項目（優先順）:
1. 時計: 上中央に残り時間（または「ボスまで」）を大きく独立させ、240秒までの進行バーを付ける。ボス戦中はボス名とゲージに切り替える。
2. XPバー: 最下端の細線をやめ、HP枠の下に高さ8px以上で置く。
3. ボスHP: `RetroSegmentGauge` 20分割の赤い石枠ゲージにし、名前を上に置く。
4. 左上パネル: 「斬幅0 貫通0 連鎖0 追撃0」を、取得済み強化のアイコン＋段階ピップ（`AbilityStageDots`）へ置き換える。主武器・副武器・技は1行ずつ。
5. 操作案内: 開始後20秒で自動的に畳み、Esc／ホバー／ポーズで再表示。スマホでは非表示。
6. 武装・戦利品トレイ: 中身がある時だけ表示。
7. 技パネル: アイコン＋クールダウン円＋「L」1行。折り返しを無くす。
8. 全パネルを `RetroPanel` 9-slice に統一し、サイズを §35.3 の基準（HP枠370×132、技枠560×96）へ揃える。
9. `pixel_visual_check` の「label outside flow」17件をこの作業の中で解消する。

完了条件: `pixel_visual_check` PASS、`survival_growth_check` PASS、PC（OpenGL）と横画面（Vulkan）で実画面を `docs/screens/hud_after.png` に保存。仕様 §35.3 を実装に合わせて更新。

### Phase 5 ホーム・リザルト・スマホ・所持品

Step 5-1 ホーム（仕様変更なし）
- 6枚のカードの共通文「決定で出撃・終盤ボスを撃破」を、役割タグ（近接／技量／射撃／機動防御／重量／魔法）と HP・速度の小表示に置き換える。
- ステージ選択をプルダウンからボス肖像付きの3枚へ（D2 の結果で内容が増える）。

Step 5-2 リザルト（D1 に依存）
- 倒したボスの肖像、自己ベストとの比較、欠片の内訳（撃破／残金／装備）の行表示、次の解放までの残量。

Step 5-3 スマホ操作
- 仮想ボタンをアイコン付きの石枠ボタンにし、右下に1クラスタでまとめる。モーダル表示中は隠す。安全領域を考慮。
- D3 で撤去が決まった機能のボタン（地図、反撃）を外す。

Step 5-4 所持品画面（D5 に依存）
- D5 が「軽量化」の場合: 装備中5部位＋新規取得比較のポップアップへ置き換え、鍛造は Run 間へ。
- D5 が「現状維持」の場合: 5分のRun中に開く前提で、初期表示を「新規取得」タブにするだけに留める。

完了条件: `survival_home_check` PASS、`secondary_ui_readability_check` の停止（天賦図114行目）を解消して PASS、横画面のタッチ操作で結果画面まで到達。

### Phase 6 実プレイ検証と既知バグ修正

目的: 無敵・自動選択に依らない勝率データを取り、バランスの初回調整に必要な事実を集める。

- 6職×3ステージを無敵なしで各3回、人が通しプレイし、到達時間・レベル・死亡要因・ボス撃破時間を `docs/playtest/20261xxx.md` に記録する。
- 既知の未修正: `pixel_visual_check` 17件（Phase 4 で対応）、`secondary_ui_readability_check` の停止（Phase 5 で対応）。残れば `bugs.json` に登録。
- Android／iOS 実機は書き出し環境が整ってから。本 Phase では PC と横画面プレビューまで。

完了条件: 記録が揃い、`bugs.json` と `roadmap.json` が実態と一致。数値調整は次の計画で扱う。

## 4. 検証ゲート

Godot は `C:\Users\USER\Desktop\Godot_v4.7.1-stable_win64_console.exe`。プロジェクト直下で実行する。

```bash
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/script_load_check.gd
```

実ゲーム経路のテストは `scenes/game.gd` のコマンドライン引数で起動する（`--survival-check` など）。
共通オプションは `--fixed-fps 60 --audio-driver Dummy --log-file <書込可能なパス> -- --mute-audio`。
各 Phase の完了条件に書いたテストを、Phase の最後に必ず実行し、結果の要約を `docs/codex_handoff.md` に残す。

## 5. 運用

- Session の開始: `git status --short` → `docs/codex_handoff.md` → この計画の該当 Phase → Scope / Out of Scope を宣言。
- Session の終了: テスト結果、仕様差分、`docs/codex_handoff.md`、`dashboard/dist/data/` の更新、コミット。
- Phase の順番を飛ばすときは理由を handoff に書く。Phase 4 の並行実施は認める。
- この計画自体の変更は、この文書を直接編集して履歴に残す。
