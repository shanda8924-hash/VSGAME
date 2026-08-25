# Element Modifier Pixel VFX assets

ラン中の現在属性をAttack Typeへ重ねる、VSGAMEオリジナルの透明PNG Sprite Sheetです。
各ファイルは384×64px、64×64pxを横6フレーム、Nearest filterで再生します。
雷ProjectileだけLoopし、Trail / Hit / Chainは非Loopです。
参照画像の切り抜き・トレース・流用は行っていません。

## Effect ID

| Element ID | Iai Trail Effect / Asset | Hit Effect / Asset | Projectile / Chain |
|---|---|---|---|
| `element_fire` | `vfx_iai_fire_trail` / `iai_fire_trail_6f.png` | `vfx_fire_hit` / `fire_hit_6f.png` | なし |
| `element_ice` | `vfx_iai_ice_trail` / `iai_ice_trail_6f.png` | `vfx_ice_hit` / `ice_hit_6f.png` | なし |
| `element_lightning` | `vfx_iai_lightning_trail` / `iai_lightning_trail_6f.png` | `vfx_lightning_hit` / `lightning_hit_6f.png` | `vfx_lightning_projectile` / `lightning_projectile_6f.png`、`vfx_lightning_chain` / `lightning_chain_6f.png` |

## Visual Language

- 火: 細い燃焼帯が着火→揺れ→拡大→火の粉へ崩れる。Hitは外向きの火花。
- 氷: 冷気の線へ氷晶が成長し、破片と霧へ砕ける。Hitは結晶の放射破砕。
- 雷: 青〜紫の不規則な分岐線が瞬間発光して途切れる。Hitは短い電撃分岐。
  Projectileは武器・矢尻を含まない右向き電撃塊、Chainは敵間を伸縮して結ぶ細い電気Arc。
- 3属性は形状・動き・消え方を別設計とし、単純な色替えにしない。
- Stack Lv1/2/3はResourceを増やさず、実行時Scale 1.00/1.16/1.32、Opacity 0.78/0.90/1.00で強める。

## 生成・加工

- 生成モード: Codex組み込みImageGen（新規bitmap生成）
- 共通プロンプト方針: VSGAME project-bound、16-bit dark-fantasy pixel art、exactly six
  sequential frames in one horizontal strip、flat `#00ff00` chroma-key background、no text / border /
  grid / watermark。個別にfire=burning ribbon、ice=frost+shards、lightning=irregular forks、
  Hit=flame petals / crystal shatter / electrical branchesを指定した
- 雷Projectile追加プロンプト: compact right-facing white-blue / blue-violet lightning bolt、
  spark→form→extend→bright fork→break→residual loop、no arrow / weapon / text / grid。
  雷Chain追加プロンプト: thin horizontal blue-violet electrical arc between endpoints、
  spark bridge→thin→branching→bright→fractured→residual、stretchable、no arrow
- スキル付属`remove_chroma_key.py`で背景を透明化し、`tools/vfx_sprite_pipeline.py`で
  共通中心・Nearest 64px×6フレーム・二値アルファへ正規化した
- ImageGen原本はCodexのgenerated_imagesへ残し、実ゲームは本フォルダの最終PNGだけを参照する

素材・Resource・Effect IDを追加または変更した場合は、同じ作業内で
`game_specification.md` 27章と本READMEを更新してください。
