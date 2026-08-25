# Fusion Pixel Art Generation Record

## Generation path

- Tool: Codex built-in `image_gen`（1 Fusionにつき1回、全10回）
- Transparency: flat chroma-key source → imagegen skillの`remove_chroma_key.py`
- Runtime build: `tools/build_fusion_pixel_vfx.py`
- Source order: Attack / Trail / Hit / Burst / Intro
- Final output: `assets/vfx/fusions/<fusion_id>/`、各6-frame RGBA Sprite Sheet

## Common final prompt

`現行Fire / Lightning / Ice / Light / Dark画像をStyle Referenceだけに使い、同じ64px密度、1〜3pxの細線、控えめGlow、非対称の小Particle、着弾中心の小Hitで、完全新規16-bit Pixel Art Fusion VFXを生成する。Attack / Trail / Hit / Burst / Introの5セルを横一列、背景は完全に均一な#00ff00。巨大紋章、柱、Portal、Ring、滑らかな高解像度表現、Text、Border、Grid、Watermarkを禁止する。`

背景色は全10種`#00ff00`。背景色は被写体内部に使用しない。

## Fusion-specific final prompt set

| Fusion | Generated phenomenon and five subjects |
|---|---|
| THERMAL SHOCK (`frostfire`) | ember streak with ice chips / thin hot-cold wake / opposing flame-shard hit / small pressure pop / two wisps snapping into one spark |
| PLASMA | thin lightning with embers / narrow residual chain / fire impact pierced by a fork / small fire AoE with hot core / compact unstable core with broken arcs |
| SOLAR FLARE (`solar`) | flame streak with white-gold edge / ember ribbon with tiny rays / holy-centered flame hit / small corona tongues / rising ember into one spark |
| INFERNO | crimson flame lash with violet tear / narrow black-red wake / hooked black-flame hit / inward pull then red sparks / soul embers consumed by one flame |
| SUPERCONDUCTOR | thin arc ending in ice shard / electrical frost thread / crystal shatter with forks / linked resonance fragments / cracked ice node with arcs |
| AURORA | shard streak splitting a ray / broken frost line with glints / refracted ice hit / small crystal fan / tiny prism splitting one ray |
| BLACK ICE (`void_frost`) | blue-black splinter / frost line with dark pixels / jagged shatter with dark center / inward-pulled fragments / compact dark ice seed |
| RADIANT ARC (`judgment`) | thin white-gold fork / broken afterglow line / Light starburst with short forks / small holy electric burst / short arcs converging into a star |
| VOIDSTORM | fork interrupted by dark crack / missing-segment purple chain / lightning through small tear / short forks from rift slits / two cracks bridged by one arc |
| ECLIPSE | light slash with shadow edge / alternating gold-violet streak / starburst split by dark crack / alternating small rays/fragments / tiny crescent crossing a spark |

`*_source.png`は組み込み生成の原本、`*_transparent.png`はクロマキー除去後の分割元。
`fusion_pixel_asset_manifest.json`に全出力PathとSHA-256、`fusion_pixel_asset_catalog.png`に全50素材の一覧を保存する。
