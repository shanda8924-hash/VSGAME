# pixelfx → Godot シート書き出し

ゲームのエフェクトはすべて [pixelfx](https://github.com/patch-gg/pixelfx)（MIT、Patch / Hugo Duprez）のコード製エフェクトから書き出す。

```bash
git clone --depth 1 https://github.com/patch-gg/pixelfx ../patch-gg/pixelfx
(cd ../patch-gg/pixelfx && npm ci)
node tools/pixelfx_import/build.mjs --pixelfx ../patch-gg/pixelfx            # 全キー
node tools/pixelfx_import/build.mjs --pixelfx ../patch-gg/pixelfx hit_fire   # 1つだけ
node tools/pixelfx_import/build.mjs --pixelfx ../patch-gg/pixelfx --board DIR   # 確認用の帯画像も
```

- 対応表は `data/vfx/pixelfx_effects.json`（キー → pixelfxのID・パレット・fps・speed・scale・fit・max_seconds・tail_fade・z）。
- 出力は `assets/vfx/pixelfx/<key>.png`（全コマの不透明範囲で切り詰めた格子）と `<key>.json`、`LICENSE_pixelfx.txt`、`NOTICE_pixelfx.md`。
- 再生は `effects/pixel_sprite_vfx.gd`（`PixelSpriteVFX.spawn` / `make_persistent` / `frame_texture`）。
- 使わない種類：`impacts/hit-flash`・`holy/heal`・`arcane/blink-in/out`・`status/*` は灰色のダミー人形の体に描くので、書き出すと人形ごと出る。
- 検査は `tests/pixelfx_vfx_check.gd`（全キーの読込、ゲームが要求するキーの漏れ、旧フォルダの不在、置き方）。
