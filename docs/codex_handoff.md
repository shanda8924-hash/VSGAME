# Codex Handoff — 2026-10-31

## 今回（整理計画 Phase 0：保全）
- 2026-08-25以降の未コミット変更1390件を9コミットに分けて保存し、`main`ブランチを作成。保全前の状態は`backup/pre-cleanup-20261031`タグ。
- `.gitignore`に`artifacts/`、`tmp/`、`tools/source_art/`、`.codex-runtime-test/`、`.godot-test-user-visual/`を追加。`artifacts/`は追跡から外しただけで、ファイルはそのまま。
- `tools/source_art/{open_field_survival,five_minute_survival,survival_growth}`のコード退避コピーはリポジトリ外（`../_backup_20261031/source_art_snapshots/`）へ移動。各`change.diff`は`docs/history/`へ。
- `README.md`を現行の5分サバイバル向け1ページに書き直し。`dashboard/dist/data/decisions.json`と`project.json`（1.6.20、2026-10-31）を更新。
- ゲーム本体のコード・データ・素材は未変更。
- 検証：`script_load_check` 209件・失敗0。`five_minute_survival_check`（PC/OpenGL、`res://scenes/game.tscn`を直接起動して`-- --survival-check --mute-audio`）はOPEN_FIELD PASS、failures=[]。終了時の`!is_inside_tree()`エラー1件は既存の退出処理由来で検査結果に影響しない。
- 次は`docs/cleanup_and_brushup_plan.md`のPhase 1（仕様書v4.0の現行／履歴分離、ダッシュボード一本化）。Phase 4（HUD）は並行可。判断事項D1〜D8はユーザー待ち。

## 直前の状態（2026-10-25まで、参考）

## 現行
- 3テーマ共通で床だけの連続戦場。RoomLayoutのsurvival生成がfloor_only=trueの96×96参照地図。床描画はDetailedMapSurfacesの反復1枚、カメラへ256px周期で追従。壁/柱/地形小物なし。旧世界の床素材を保持。
- floor_onlyの空間/通行判定は領域外も床。Chaseは直進。Waveは表示範囲外の周囲から、装備は現在地の近傍セルから。遠方へ移動しても原点へ出現しない。有限BFSのvalidate_reachabilityはboundsを確認。
- 約4分の大群戦→240秒に終盤Boss→撃破必須。経過時計は300秒で止めない。5分後も生存Bossは継続。Player火力へBoss HPを合わせない。通常敵/強敵混在・巡回精鋭・途中Bossは廃止。
- Strong6種をBossDataとして別JSON追加。元のSprite・特技・赤い予兆を保持、特技IDをBoss Loader/EnemyBasicでも接続。ベースHP7800/9000＋テーマ15%、既存倍率1.5で11700〜17550、見た目倍率1.7。旧BossはTest Lab/履歴。
- Curve：1.0秒/3〜4体→0.45秒/8〜10体、PC128/タッチ96。標準敵は45秒25%→150秒45%。通常HPは4分時点で序盤比約+72%/攻撃約+32%（300秒基準の係数0.9/0.4）、XP必要量0.6（初回EXP9）。75秒60%装備箱、150秒手動補給箱→ショップ。
- 討伐後は消失予約停止、装備・討伐箱・階段を離し、手動帰還のみ結果へ。残金＋取得装備×5の継承報酬を維持。本・200装備・9武器攻撃・浮遊オーラは保持。
- Dashboard1.6.19、仕様末尾の10-13節、docs/crazy_gunner_survival.mdへ同期。artifacts/open_field_survival/に実画面・結果。6Bossの256px図鑑は元のidle素材をGodotで描画（tools/export_stage_boss_portraits）。

## 成長・強化の更新
- 敵の歩行を35%減速し、主人公の通常歩行速度の75%以内へ。経験値倍率を2.1から0.6へ、初回必要EXPは32→9。5分の中で強化を試しやすくした。
- 大きなアイコン・現在→強化後の動く比較・選択チェック・独立した取得ボタン。タップだけでは取得せず、選択中は戦闘時間を止める。上限に達した強化と、使えない遠距離強化は候補に出さない。
- 広域攻撃・高速攻撃・残影追撃・雷光連鎖・再生結界・強撃・多重射撃・貫通射撃。旧数値/状態カードを現行レベルアップから外し、職業技と流派は維持。通常攻撃と浮遊装備の実命中・弾数・貫通へ接続。
- survival_upgrade_effectsは直接命中から有限追撃/連鎖と実シールド。新8JSON、職業/装備の追加弾/貫通、既存ComfyUI斬撃を接続。旧Shop/天賦/セーブは維持。

## レベルアップ画面（2026-10-25）
- 枠・配色をショップと同じ共通部品へ統一（major panel／emblem／FrameArt石枠）。色は種類だけ（戦闘強化=青、職業技=金）、選択中だけ青緑の枠と光。
- 段階ピップ（最大段階まで）と「新規 Lv.1 / 3」「Lv.1 → Lv.2 / 3」表記へ整理。説明文の数値を強調。全Label 18px以上。
- 比較プレビュー（upgrade_preview.gd）を全8強化の実処理に合わせて作り直し。同じ敵配置で命中した敵だけ光りHPが減る。職業技は静止表示。抽選・2段階取得・時間停止は不変。
- 詳細は仕様書末尾の2026-10-25節、実画面はartifacts/level_up_brushup/。pixel_visual_check(HUD 17件)とsecondary_ui_readability_check(天賦図114行目)の失敗は変更前から同一の既存不具合。

## 検証
- five_minute_survival_checkが現行：実出撃、自然戦闘、壁なし、遠方の実歩行/カメラ/画面外Spawn/Drop、メニュー/補給停止、305秒後の生存Boss/HP、撃破後の回収/期限取消/帰還/継承、6種類の実固有動作。PC/OpenGL・横画面/Vulkan、音はDummy＋mute-audio。
- 無敵・自動選択の通し例：初回17.4秒、Lv5は32.9秒、Lv10は68.6秒、終盤Lv25。全体293.0秒、Boss52.9秒。勝率の証明ではない。
- survival_growth_check：6職、マウス/タッチの選択と確定、画面内と文字収まり、連続Lv/Pause解除、範囲/速射、実追撃/連鎖、DOT再帰なし、結界消費/再生、職業と装備の弾数と実貫通。PC/OpenGL・横画面/Vulkan、Dummy＋mute-audio。
- survival_home_checkは3テーマを実出撃。equipment_auto_attack_checkは9系統をPASS。Godotは書込可能な--log-fileと--fixed-fps 60、--audio-driver Dummy -- --mute-audio。既定user://ログ/Shader cache不可は環境由来。

## 次
- Android/iOS実機、無敵なし全職の勝率・成長/装備/価格、タッチと発熱を評価。旧部屋/60層やタイムクリア専用Testは履歴。新スキル・縦画面・永続装備は未追加。
- 多数の既存未コミット変更あり。全体restore/reset禁止。今回のファイル差分はworkspaceのwork/open-field-survival/beforeを基準にする。
