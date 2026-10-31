# Codex Handoff — 2026-10-31（Phase 4まで）

## 次の主題（未着手）：遊びの骨組み — `docs/fun_loop_redesign.md`
- ユーザー評価「楽しくない」：退屈（敵が弱い・移動だけ）、単調（山場がない）、分かりにくい（目標と得が見えない・スキルの発動条件が読めない）、育成がない（1ダンジョンでキャラが終わる）。
- 打ち手はPhase 1 緊張と山場（サージ有効化・敵の役割・圧力曲線・次の波までの表示）→ Phase 2 スキルの可読性（trigger/tags/scales_withのデータ化、クールダウン→命中回数ごと、カード3行定型）→ Phase 3 シナジーと進化（連撃、進化レシピ、相性保証）→ Phase 4 育成（装備と熟練の持ち越し、深度付きステージの鎖、負けの持ち帰り）。
- 所在：`survival_upgrade_effects.gd`のecho 0.6秒／chain 0.7秒のクールダウン、`exploration_run.json`の`surge.enabled: false`、`equipment_component._on_run_ended`の全消去、`SaveManager`のキー。

## 今回（サバイバルの戦場の見た目：床の飾り・光だまり・空気感、2026-10-31）
- 床だけの連続戦場（floor_only）は同じ床素材の繰り返しだけだった。`entities/stage_environment/detailed_map_surfaces.gd`のfloor_only経路に、描画だけの3層を追加（当たり判定・湧き・経路は不変）：
  1. 床の飾り：`tools/map_unified/build.py`→`assets/visuals/floor_decals/map{1,2,3}.png`（1テーマ16種、64px、1ドット＝2px。ひび・瓦礫・欠け・水たまり・骨・苔・格子・染み＋MAP1 骸と鎖・古い紋、MAP2 紫晶と鉱脈、MAP3 熔岩のひび・鉱滓・歯車）。世界座標のハッシュで64px格子の約1割へ配置（同じ場所は常に同じ）。192px格子の約1/3に大きな染みを薄く敷いて調子を変える。位置の256px吸着時だけ再描画。
  2. 光だまり：光る飾り（紫晶・熔岩・紋）の上へ加算合成の`FloorGlow`（明滅）。
  3. 空気感：画面の縁の暗がり（`vignette.png`、テーマ色、HUDより下のCanvasLayer）と浮遊粒（MAP1 塵／MAP2 煌めき／MAP3 上昇する火の粉、CPUParticles2D 22〜34粒、世界座標）。床の色味もテーマ別（寒色／紫／暖色）。
- 検証：`script_load_check` 0件、`five_minute_survival_check` PASS、`map_theme_check` PASS。実画面は`tools/capture_survival_field.tscn`（change_sceneで通常起動と同じ経路）→`docs/screens/survival_field_after.png`。

## 今回（居合のブラッシュアップ、2026-10-31）
- 威力・判定・時間は変えず、見た目と手触りだけ。`components/active_skill_component.gd`：構え中に柄の閃き（`hit_light` 22px）と進路の点線（`IaiTelegraph`、青緑、構えの0.16秒で消える）＋抜刀音`iai_draw.wav`。残像を鋼色`#90ddff`の加算合成に。斬り抜け後に進路全体へ刀筋`assets/vfx/pixel/iai_trail.png`（新規6コマ、`tools/vfx_unified/effects.py`の`iai_trail`）を0.3秒、敵に当たっていれば0.03秒のヒットストップ。最後に`sheathe_hold`（既定0.12秒、`active_skill_params`で調整可）の納刀の静止と`iai_sheathe.wav`で移動ロック解除（乱撃派のコンボキャンセル時は静止しない）。
- `charges_changed(remaining, max)`信号を追加し、HUDは乱撃派のとき残りチャージを「◆◆／◆◇」で状態の横に表示。準備完了時はアイコンも一瞬白く光る。
- 仕様書19.6を`swordsman.json`の実数値（190px・2.0倍）と今回の演出に合わせて更新。
- 検証：`script_load_check` 0件、`iai_and_mode_check` 0件、`five_minute_survival_check` PASS。実画面は`tools/capture_iai.tscn`（xvfb。低fpsなので斬り抜けが実時間より長く見える）→`docs/screens/iai_brushup.png`。

## 今回（装備の流れ：ドロップ演出・アイテムボックス・詳細・鍛造、2026-10-31）
- 発見：実行時の装備アイコンは`assets/visuals/ember_v5/equipment/`（64px）が最優先で、ここが旧素材の混在だった。`tools/icon_unified/build.py`でこの200点も同じ原画・同じ手順で生成するようにし（本体56px）、`equipment_icon_metrics.gd`に範囲を追加。`equipment_catalog_200`の期待パスもember_v5へ。
- ドロップ演出（Diablo参考）：`GroundEquipmentItem`にレア度色の光の柱`LootBeam`（高さ56〜168px・幅7〜20px・明滅・加算合成）、名札（暗い板＋レア度色の左帯。レア以上は常時、アンコモンは接近時）、落下して弾む着地（0.5秒、柱は着地後に立つ）、伝説以上は着地の閃光`hit_light`と鐘の音`legendary_drop.wav`。`equipment_drop.wav`も新規（どちらもnumpyで合成した短い音）。`loot_visibility_check`は柱ありを期待するよう更新。
- アイテムボックス：マスにレア度の下地（薄い色＋下辺の色帯）、装備中より強ければ▲緑／弱ければ▼を左上に表示（`item_score`＝固定値と割合値を一つの尺度にした装備スコア）。鍛造タブでは所持品の1クリックで素材の出し入れ、素材にできない品は沈める。
- 詳細ポップアップ：名前（レア度色）／「レア・武器・細剣・槍」／「装備スコア 27　+25 ▲ 強くなる」、直下に「装備する／外す」（常時表示）、武器は間隔・一撃・射程、能力は0でない行だけ、装備中カードは「得る／失う」だけを短く。
- 鍛造の合理化：完成品は主素材（枠1）の部位を受け継ぎ、武器は攻撃種別も優先。`preview_result`で合成前に完成品の名前・部位・スコア・能力を表示（素材IDのハッシュで決まるので一致する）。`drop_table.json`のmerge_rules success_rateを全段1.0に（失敗消費を廃止。戻すなら数値だけ）。「同部位でセット」は主素材と同じ部位を優先し、弱い順に埋める。
- 検証：`script_load_check` 0件、`equipment_merge_check` 0件、`loot_visibility_check` 0件、`equipment_auto_attack_check` 0件、`five_minute_survival_check` PASS。実画面は`tools/capture_item_flow.tscn`（xvfb）→`docs/screens/loot_drop_diablo_style.png`、`item_box_detail.png`、`item_box_forge.png`。`forge_balance_check`は変更前から500秒で終わらない。

## 今回（UIスキン：石板と古金の9-sliceを全メニューへ、2026-10-31）
- 画像生成環境は無いため、`tools/ui_unified/build.py`で1ドット＝2pxのドット絵として部品を描き、`assets/ui/stoneworks/`へ出力（panel_major=石のレール＋金の角金具、panel_inset=石の縁＋飾り鋲、button_normal/hover/pressed/disabled、plaque=槍頭の見出し板、slot=所持品のマス、well=金具なしの窪み、bar_track/bar_fill、backdrop_tile）。中央はタイル繰り返し。`python3 tools/ui_unified/build.py [--board DIR]`。
- `ui/common/relic_frame_art.gd`を書き直し（旧`assets/visuals/ember_v5/ui_panel.png`等は未参照に）。`box(inset)`＝大パネル/内側パネル、`button_box(state)`、`well_box`、`bar_box`、`styled(kind)`、`plaque()`。`pixel_ui_style.gd`のボタン・区画・ゲージ・カードをこれに接続。使い分け：モーダルと3列パネル＝major、カード・区画＝inset、カード内の小区画＝well、所持品マス＝slot。
- HUDのHP/XPゲージと技アイコン枠、所持品画面の背景（石畳タイル）と各マス、ホームの出撃先カード（inset）/職業カード（major）も切替。`tools/capture_crafted_ui.gd`にポーズ・ショップの撮影を追加。
- 検証：`script_load_check` 0件、`five_minute_survival_check` PASS、`xvfb-run`で`tools/capture_crafted_ui.tscn`を撮影し8画面を目視（`docs/screens/ui_stoneworks_*.png`）。

## 今回（装備アイコン：原画200点を同じ手順でドット化、2026-10-31）
- 実行時の装備アイコンは`assets/ui/equipment_readable_v4/*.png`（48px）。約170点が単色シルエットで、残り30点の細密なドット絵と画風が揃っていなかった。細密な30点は`assets/items/painted_200/sheet_*.png`の原画（200点すべて同じ画風）をドット化したものなので、`tools/icon_unified/build.py`で200点すべてを同じ手順（art_regionで切り出し→長辺44pxへ面積平均縮小→明るさ/コントラスト/彩度を持ち上げ→14色へ減色→二値アルファ→飛び除去→明るい縁1px）で描き直し、同名上書き。`python3 tools/icon_unified/build.py [--board DIR] [--dry]`。
- 最初に試した図形生成（平坦なドット絵）はユーザー判断で不採用。
- 所持品画面のスロット絞り込みタブ用6点（`assets/items/weapons/weapon_sword_uncommon_001.png`など、64px・本体54px）も同じ原画・同じ手順で上書き（`build.py`の`TAB_ICONS`）。
- `resources/equipment_icon_metrics.gd`へreadable_v4の200件とタブ用6件のBoundsを追加（床Dropと浮遊武器の寸法換算に使う）。
- 検証：`script_load_check` 0件、`loot_visibility_check` 0件。比較は`docs/screens/icons_unified_compare.png`、一覧は`icons_unified_all.png`。

## 今回（VFX統一スタイル：全シート描き直し、2026-10-31）
- `tools/vfx_unified/`（style.py=ランプ5段・縁取り・6コマの時間配分、effects.py=全55シート、build.py=生成と旧新比較ボード）で実行時の全VFXシートを同名上書き。`python3 tools/vfx_unified/build.py [--board DIR]`。
- ドット密度：コマ寸法＝表示サイズの約1/2。`PixelSpriteVFX`はコマ寸法＝シート高さ×(幅/6)で読む。浮遊武器・装備弾・魔導士弾・回避/宝箱・宝箱封印・警告円（128px、RING_PIXEL_RADIUS=51）・弾のGlow（12px×2）も寸法から換算。
- 秘技の雷帝落雷・氷槍豪雨・虚無断界を強化。コード描画の線色（雷光連鎖・残影・結界、ボス予兆・斬撃帯、属性テーマ色）をランプへ統一。比較は`docs/screens/vfx_unified_*.png`。
- 検証：`script_load_check` 0件、`five_minute_survival_check` PASS。`pixel_hazard_check`の毒沼5件・予兆1件は変更前から失敗（予兆フェーズ追加前のテスト前提）。

## 今回（秘技：レベルアップで増える大技、2026-10-31）
- 旧完成大技のうち自動発動の5種（雷帝落雷・煉火天柱・氷槍豪雨・光刃陣・虚無断界）を、属性と無関係の「秘技」としてレベルアップに出す。§43の「通常Runに出さない」をユーザー判断で撤回。
- `data/upgrades/arcana_*.json`（category `arcana`、max_rank 5、`level_lines`・`strike_counts`・`vfx_sheet`）。`data/skills/completed_skills.json`の5種を5段階化し`strike_count_by_level`を追加。
- 所持枠2。未所持の間は毎回1枚は秘技が出る。重みは新規2.0・育成中2.6。カードは橙で「秘技 NEW!」、プレビューは実VFXシートを段階の数だけ落として見せる。
- `ConceptSystem._activate_signature_skill`は段階の数だけ離れた別の敵へ0.12秒ずつずらして落とす。`PlayerUpgradesComponent`は`arcana`で`acquire_completed_skill`、`get_arcana_count()`。HUDは左上の強化石板の先頭に秘技（橙ピップ）、トレイ見出しは「秘技」。
- 次の段階（未着手）：戦技8種の見た目強化、覚醒（150秒補給箱）、全取得後の金貨／回復カード。
- 検証：`script_load_check`、`five_minute_survival_check` PC、`survival_growth_check`（秘技をプールに許可する1行を修正）。実画面は`docs/screens/arcana_*.png`。

## 直前（D5〜D8、2026-10-31）
- D5 所持品：サバイバル中に[C]で開くと「入手順（新しい順）」で並び、最新の装備を選択して装備中との比較を先に見せる。鍛造は従来どおり画面内のタブから使える（Run間への移動は装備の永続化が必要なので見送り）。
- D6 旧テスト：廃止モード向け22件を`tests/legacy/`へ移動（`tests/legacy/README.md`）。`script_load_check`は`legacy`を走査しない。`scenes/game.gd`が参照する`map_*`/`shop_runtime`/`run_economy_balance`/`imported_assets`は`tests/`直下に残した。
- D7 ダッシュボード：リポジトリ内`dashboard/dist`を正本に（`dashboard/README.md`冒頭）。公開はGitHub Pagesのworkflow。リモート作成はユーザー作業。
- D8 実画面：`artifacts/`の中身（432MB）を`../_backup_20261031/artifacts/`へ退避し、空の`artifacts/`（`.gdignore`）だけ残した。検査は従来どおり`artifacts/`へ書く。保存版は`docs/screens/`。
- 検証は`script_load_check`と`five_minute_survival_check`（PC）。

## 直前（D3：5分アリーナに合わない機能の整理、2026-10-31）
- 地図（M）：サバイバルでは`ExplorationMapOverlay`を生成しない。スマホの「地図」ボタンもサバイバル中は非表示。Test Labの旧モードでは従来どおり。
- 天賦図（T）：内容がある職業（剣士）だけ`[T]`とポーズのタブを出す（`pause_menu.gd`の`TALENT_CHARACTER_IDS`）。
- ジャスト回避→J反撃：サバイバルでは終盤ボス（`survival_boss`グループ）が居る間だけ発生。スマホの「反撃」ボタンもその間だけ表示。
- コンボ：効果が無いのでサバイバルでは`ComboSystem`を止め、HUDに出さない。
- HUDの操作案内から「M 地図」を外し、「T 天賦図」は剣士のみ。検証は`script_load_check`と`five_minute_survival_check`（PC）。

## 直前（D1・D2：ステージ解放と3ステージの差別化、2026-10-31）
- 判断D1＝「継承の欠片はキャラ解放＋ステージ解放。恒常強化は保留」、D2＝「出現曲線・補給箱の時刻・ボス肖像付きカードで差別化」をユーザーが決定し、実装した。
- `data/maps/exploration_run.json`：MAPごとに`unlock_cost`（0/150/400）、`difficulty_curve_id`（map2/map3は新規`data/difficulty/five_minute_survival_map2.json`、`_map3.json`）、`survival_supply_seconds`（[75,150]/[60,140]/[60,120,195]）、`tagline`、`stage_note`を追加。MAP3は補給箱（ショップ）が2回。
- `SaveManager`：`unlocked_survival_maps`（既定[1]）、`is_map_unlocked`、`unlock_map`。`GameManager.start_run`は未解放MAPならMAP1へ戻す。`MapRunController`はMAP別の補給時刻を読む。
- `ui/home`：OptionButtonを廃止し、ボス候補2体の肖像・名前・特徴・解放状態／補給時刻のカード3枚を職業グリッドの上に置く。未解放カードは決定で欠片を消費して解放し、解放したステージが出撃先になる。職業カードは350×250へ縮めて1画面に収めた。
- 検証は`script_load_check`と`survival_home_check`（カード3枚、画面内、欠片0での封印維持、150→400の解放、出撃先切替、3テーマの実出撃）のみ。ユーザー指示により仕様書・ダッシュボードは更新していない。

## 直前（整理計画 Phase 4：戦闘HUD）
- `ui/hud/hud.gd`の描画層を組み直した。呼び出し元（MapRunController／BossSpawner／ComboSystem／Player／game.gd）の関数名と引数、Signal購読、`hud.tscn`のノード名は変更していない。戦闘ロジック・数値・入力・保存は未変更。
- 上中央の石板：「ボスまで m:ss」34px＋240秒までの20分割ゲージ。ボス戦は同じ石板が「最終ボス 名前　ボス戦 m:ss　撃破 N」と朱赤の20分割HPゲージに切り替わる（`room_status_label`の本文に「ボス戦」を含める既存検査は維持）。
- 左上：LV・職業・主武器名・HP16px・XP10px（370×120）。その下に取得済み強化のアイコン＋段階ピップ。旧「範囲0 貫通0 連鎖0 追撃0」は廃止。
- 右上：コイン付き所持金。「武装・戦利品」は中身がある時だけ見出しボタンと石板を出す。右下：職業技（アイコン枠・キー札L・クールダウンの影・名前／状態・熟練ピップ）。
- 操作案内は戦闘20秒で畳み「操作一覧」札へ。タッチでは案内を出さず、HPは左上・技は右上（128〜226）・強化石板は地図ボタンの下。
- 仕様：§35.3を現行値へ書き換え、末尾に「2026-10-31 戦闘HUDのブラッシュアップ」節を追加。実画面は`docs/screens/hud_before_*.png`／`hud_after_*.png`。
- 検証：`script_load_check` 209件・失敗0。`pixel_visual_check` PASS（旧HUDで失敗していた「label outside flow」17件は、トレイを非表示のまま検査していたことが原因で、中身がある時に表示する仕様へ変えたことで解消）。`survival_growth_check` PASS。`five_minute_survival_check` PC/OpenGLとタッチ横画面（`--touch-preview`、1280×720）でOPEN_FIELD PASS。
- 検査の起動：`res://scenes/game.tscn`または`res://tests/*.tscn`をシーン指定で起動する。複数のGodotを同時に走らせると途中で止まる（単独なら完走）ので、検査は直列に回す。
- 残り：Phase 1（仕様書v4.0・ダッシュボード一本化）、Phase 2（削除）、判断事項D1〜D8。Phase 5のホーム／リザルト／スマホボタンはD1・D3・D5待ち。

## 直前（整理計画 Phase 0：保全）
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
