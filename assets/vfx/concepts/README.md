# Concept Pixel VFX

`wind_blade_6f_v2.png`は、built-in ImageGenで新規生成した6段階Wind Bladeを、
`tools/build_wind_vfx_sheet.py`で透明384×64pxへ正規化したRuntime Assetです。

- Source prompt: hand-authored 16-bit pixel wind crescent, formation → impact → expansion → fragment、
  mint/off-white/teal palette、no blur/gradient/text、6 frames in one horizontal row。
- Runtime connection: `effects/concept_skill_vfx.gd` の `wind_blade`。
- Filter: Nearest。
