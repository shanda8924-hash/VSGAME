# Fusion Pixel VFX Runtime Assets

全画像は今回、組み込み`image_gen`でFusionごとに新規生成したPixel Artを元にしている。
既存Element Spriteの合成・色替えではない。

## Layout

- `<fusion_id>/fx_fusion_<fusion_id>_attack_6f.png`
- `<fusion_id>/fx_fusion_<fusion_id>_trail_6f.png`
- `<fusion_id>/fx_fusion_<fusion_id>_hit_6f.png`
- `<fusion_id>/fx_fusion_<fusion_id>_burst_6f.png`
- `<fusion_id>/fx_fusion_<fusion_id>_intro_6f.png`

全50画像は`384×64 RGBA`、1 frame `64×64`、横6 frame。
Godot import後も`AnimatedSprite2D.texture_filter = NEAREST`、18fpsで再生する。

## 2026-08-11 Redesign

- 現行Fire / Lightning / Ice / Light / Darkを直接Style Referenceとして再生成した。
- 旧巨大紋章、白金柱、Portal Ring、Event Horizon、巨大Coronaを廃止し、
  細いTrail・小Hit・短寿命・非対称Particleへ統一した。
- 安定した内部ID/Pathは維持し、表示名だけ`frostfire`=THERMAL SHOCK、`solar`=SOLAR FLARE、
  `void_frost`=BLACK ICE、`judgment`=RADIANT ARCへ更新した。
- Attack/Trail/Hit/Burst/Introの表示寿命は0.42/0.32/0.38/0.50/0.72秒。
- 連続Chainでは各着弾点に小Hitを出す。Gameplayを変えずPresentationだけを有界化する
  同時Fusion VFX上限は480。

## Runtime Connection

- `effects/fusion_vfx/<fusion_id>.tres` → 5画像
- `DataLoader.fusion_vfx_effects` → `FusionVFXData`
- `FusionVFXEffect` → `GeneratedFusionPixelArt` (`AnimatedSprite2D`)
- Formation/State → Intro、Signature/Pillar/Portal → Burst、Soul → Trail

生成元、透過版、SHA-256、全50画像カタログは
`artifacts/fusion_vfx_pixel_sources/`に保存する。
