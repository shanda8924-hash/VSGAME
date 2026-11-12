# VSGAME PIXEL VISUAL GUIDE

このGuideは、VSGAMEのWorld・Combat VFX・UIを同じ解像度感へ揃えるための実装基準です。
既存のGameplay判定を変えず、ReadabilityとPerformanceを優先します。

## 基準

| 項目 | 採用値 / 方針 |
|---|---|
| 基準セル | World VFXは64×64px、6 frame横Sprite Sheetは384×64px |
| Pixel cluster | 主形状2〜4px、補助Fragment 1〜2px |
| World outline | 1〜2pxの暗色輪郭。Smooth blurは主形状に使わない |
| UI border | 通常3px、Focus 4px、角丸0px |
| UI shadow | 右下3〜4pxの硬い影。Gradient・Blurなし |
| Highlight | 上辺/Focus borderの色切替。Smooth scaleは使わない |
| Glow | 主形状を読める状態でのみ、短寿命・局所・低密度の補助として使う |
| Particle | 1〜3px相当の四角いFragment。Triggered VFXはPrimaryより少なくする |
| Icon | HUD 24〜32px、Card 32〜48px、World drop 24〜42px |
| Button | 高さ48px以上。Pressedは右下へ2px相当ずらし、Border/Shadowを反転 |
| Panel padding | 12px基準、選択Cardは14pxまで |
| Animation | 通常Hit 0.18〜0.36秒、居合0.36〜0.60秒、Fusion 0.32〜0.62秒 |
| 消滅 | Edge欠け、Fragment、Spark、圧縮。全体Alpha低下は最後の10%以内だけ |

## Color hierarchy

- 基本UI: `#090d13` / `#111821` / `#40546b`。UI全体を属性色で染めない。
- Player neutral hit: off-white / cyan-white。敵攻撃のDanger redと分離する。
- Fire: red `#ff4a2d`、orange `#ff8a32`、yellow core `#ffe16a`。
- Ice: cyan `#71dcff`、pale blue `#bceeff`、white core。
- Lightning: violet-blue `#8f7cff`、white-blue core。黄単色の巨大斬撃は禁止。
- Wind Concept: mint `#8ff5c0`、off-white `#e9fff2`、teal outline。
- Light: white/gold `#fff1a8`。BloomではなくCross Spark/Sharp Fragmentを主形状にする。
- Dark: purple `#b56cff`、near-black `#13091f`、magenta edge。背景へ埋没させない。
- Fusion:各Fusion固有paletteを使い、構成属性VFXを三重表示しない。
- Enemy/Boss danger: red-orange `#ff5c55`。Player attribute colorと同じ線色にしない。
- Rarity: Uncommon green / Rare blue / Epic purple / Legendary orange / Mythic red。

## VFX lifecycle

`発生 → Shape形成 → Impact → Pixel Fragment → 消滅`を共通文法とします。
Sprite一枚を始点から終点へ横Slideさせず、攻撃区間の中央に固定して形状自体を展開します。
Line2Dを使う場合はantialiasedを無効にし、短い階段状Segmentとして数Frameだけ表示します。
Timer/Tween/await後は対象Node・Effect IDの有効性を再確認し、すべての一時Nodeを
`transient_vfx`へ登録します。全画面ColorRectはBoss節目の短い局所Flash以外で使いません。

## Build growth

- Lv1: 主形状だけ。
- Lv2: 形状を少し拡大し、3〜5 Fragmentを追加。
- Lv3: 形状をもう一段進化させ、6〜10 Fragmentを追加。
- MAX: 色を白くするだけでなくShapeを変える。
- Fusion: 独立した専用Sprite Sheetを主役にし、通常属性の重複描画を抑える。

## Typography / resolution

日本語本文は可読性優先の既存Fontを維持します。数字・短いLabelは2px outlineと硬いShadowで
Pixel UIへ寄せます。ProjectのCanvas texture filterはNearestを基本とし、各Pixel Spriteも
`TEXTURE_FILTER_NEAREST`を明示します。Pixel Snapは操作感を悪化させる全体強制をせず、
静的UIとVFXの整数座標・Nearest表示で安定させます。
