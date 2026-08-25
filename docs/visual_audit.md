# VSGAME Visual Audit

2026-08-15時点の実コード・Scene・Resource・Data・Asset・Vulkan captureを対象にした監査結果です。

| 分類 | 現状 | 判定 / 対応 |
|---|---|---|
| Player / Enemy / Boss | Pixel sprite sheetとAnimationComponentを使用 | 維持。Boss outlineとtelegraphのDanger色だけ整理 |
| 通常攻撃 | 6-frame Pixel Attack/Hitが接続済み。旧黄色crescentは既に抑止 | 維持し、通常Hitを小さく、Criticalだけ強化 |
| 居合 | 属性別6-frame trailが接続済み。敵へ残る傷線なし | 位置固定・横展開・端崩壊を維持 |
| Fire / Ice / Lightning / Light / Dark | 属性Hit/居合SpriteはPixel化済み。旧GPUParticles/Lineが一部重複 | Spriteを主役にしてLegacy particle/長線を削減 |
| Wind | 独立Attributeは存在せずConcept Skillのみ | 新属性は追加せず、Wind Blade専用6-frame Pixel VFXを生成・接続 |
| 全10 Fusion | Attack/Trail/Hit/Burst/Introの専用6-frame PNGとResource接続あり | 既存専用画像を維持し、Canvas補助と粒子密度を下げる |
| Projectile / Chain / Area | Pixel projectile/chainあり。旧Line2Dと半透明areaが混在 | 階段線・短寿命・低Alpha補助へ限定 |
| Damage Number | 数字色分け済みだが長いSmooth移動/Fade | 整数Step移動と終端短時間消滅へ変更 |
| Screen Effect | lifecycle復元あり。Boss/Fusionで全画面ColorRect flashが残存 | Alphaと回数を制限し、Fusion成立の全画面flashを廃止 |
| Floor / Wall / Decoration | Pixel tileset。戦闘背景とのcontrastは概ね良好 | 大規模Map変更なし。装飾をPlayer/Enemyより暗く維持 |
| Treasure | コード描画の矩形Chest、3 rarity色差 | Pixel outline/lock/sparkを強化し巨大Glowは使わない |
| Equipment Drop | Pixel iconはNearest。長いsmooth beam/ellipse/particle過多 | Beamを撤去し、短い四角Fragmentと硬い台座へ変更 |
| Title / Button | Standard Button、状態差が弱い | 共通Pixel border/shadow/pressed/focusへ統一 |
| Panel / Card | 画面ごとに角丸半径7〜12px、padding/borderが不統一 | 共通3px square border、12px paddingへ統一 |
| HP / Boss HP / Combo / Room | 情報は読めるが大文字英語と大outlineが混在 | 日本語を基本にし、硬いBarと優先度別sizeへ整理 |
| Attribute / Skill / Treasure UI | 機能・Controller focusあり。Card visualがSmooth | 属性/rarity borderを残してPixel stateへ統一 |
| Equipment / Inventory | Drop→Pickup→Inventory→Equip/Unequip/MergeがRun内接続済み | Room intermissionを維持し、Pixel gridへ統一 |
| Settings / Pause / Result | 標準/角丸Style混在 | 共通Pixel themeを適用 |
| Test Mode | Runtime検証導線あり。左PanelがModern UI | 機能を維持し共通Pixel styleを適用 |
| ROOM選択 | Sceneは互換用に存在するが通常Runでは非表示 | Runtime経路から除外した状態を検証 |

## Filter / snap audit

- `project.godot`の`textures/canvas_textures/default_texture_filter=0`はNearest。
- VFX/Equipment Spriteも`TEXTURE_FILTER_NEAREST`を明示している。
- 1600×900の`canvas_items` stretchを使用。
- 全体Pixel Snap強制は移動の滑らかさを損なうため不採用。UI style・Sprite座標・VFX sheet側で
  Pixel整合を取る。

## Performance / lifecycle audit

- ROOM build、Enemy instantiate、Texture初回登録がTransition frameへ集中していた。
- Stage map buildとEnemy prepareは複数Frameへ分散済み。Enemyは全準備完了後に一斉表示する。
- SpriteFrames、floor cells、stage decoration、spawn候補をcacheする。
- 前ROOMのEnemy/Projectile/VFX/Drop/Timer相当を遷移前にcleanupし、Stress testでNode蓄積を監視する。
- Plasma/FusionのDictionary callbackはepoch/存在確認と上限を持ち、effectは実時間寿命で解放する。
