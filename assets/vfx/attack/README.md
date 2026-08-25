# Attack / Hit Pixel VFX assets

通常攻撃開始と命中に使う透明PNG Sprite Sheetです。各ファイルは384×64px、
64×64pxを横6フレーム、Nearest filter、非Loopで再生します。主役は形状そのものが変化する
Pixel Sprite Animationであり、Particleは既存属性Themeの補助表示に限定します。

## Effect ID

| Effect ID | Asset | Animation |
|---|---|---|
| `attack_slash` | `attack_slash_6f.png` | 小さな弧→伸長→最大→破片→Fade |
| `attack_projectile` | `attack_projectile_6f.png` | 発生→伸長→飛翔→分裂→Fade |
| `attack_pulse` | `attack_pulse_6f.png` | 中心核→円環拡大→破砕→Fade |
| `hit_normal` | `hit_normal_6f.png` | 小さなImpact→拡張→破片→Fade |
| `hit_critical` | `hit_critical_6f.png` | 強い星形Burst→最大→破片→Fade |

## 生成と加工

- 生成モード: Codex内蔵のImageGen（新規ビットマップ生成）
- 共通プロンプト方針: 16-bit dark-fantasy pixel-art VFX、exactly six sequential frames in one
  horizontal strip、flat `#00ff00` chroma-key background、no text/border/grid、white/pale neutral
  effect pixels、clear frame-to-frame silhouette change、64px in-game target
- 個別指示: slash arc、projectile streak、radial pulse、small impact、strong critical starburstの5種
- `tools/vfx_sprite_pipeline.py`でクロマキー除去、共通中心・共通倍率、Nearest downsample、
  アルファ境界の硬化を行い、透明384×64pxへ変換する
- 生成元は最終Assetへ焼き込み済みで、実行時は本フォルダ内PNGだけを参照する

素材・Resource・Effect IDを追加または変更した場合は、同じ作業内で
`game_specification.md` 25.6〜25.7および25.12を更新してください。
