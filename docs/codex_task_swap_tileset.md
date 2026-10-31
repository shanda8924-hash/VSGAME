# Codex Task — 戦闘地形タイルの差し替え

MAP/Surge Phase 3の実装は受理済み。**ロジックは変更しない。地形レイヤーが参照する
タイル画像と座標だけを差し替える。**

```text
Scope: CombatTerrainTileMapLayerが使うテクスチャの差し替えと座標の再マップ、柱の2x2化
Out of Scope: 生成ロジック、Surge、Hazardのダメージ処理、Element/Equipment/HUD、Balance数値
```

差し替える理由は美術方針の統一であり、既存実装の不具合ではない。**ゾーンの配置ロジック、
到達性検証、Hazardのダメージ、Surgeの挙動は一切触らないこと。**

---

## 何を差し替えるか

| | 現在 | 差し替え後 |
|---|---|---|
| テクスチャ | `res://assets/tilesets/dungeon/terrain_regions.png` (8×1) | `res://assets/tiles/dungeon_tileset_retro.png` (8列×6行 = 128×96px) |
| 生成元 | `tools/generate_map_tiles.ps1` の terrain_regions 出力部 | `tools/generate_dungeon_tileset.ps1` |

**`Dungeon tileset_retro.png`(基礎タイルセットのHUDパレット版)はそのまま使い続けること。**
松明・旗・樽・檻・階段などの装飾は引き続きそちらが担当する。今回差し替えるのは
`CombatTerrainTileMapLayer`(4ゾーンの床と柱)だけ。

`tools/generate_map_tiles.ps1`の`terrain_regions.png`を出力する部分は、二重管理を避けるため
無効化またはコメントアウトすること。基礎タイルセットの色調変換部分は残す。
`assets/tiles/_preview_tileset.png`は目視確認用なのでゲームには読み込まないこと。

---

## 座標の対応表(必ずこの通りに)

新タイルセットは **8列×6行**。現在の定数は全て`row 0`にあるが、新レイアウトでは行が分かれる。

```gdscript
const COMBAT_TERRAIN_TEXTURE_PATH := "res://assets/tiles/dungeon_tileset_retro.png"

# 床は4変種ずつある。1種類だけ敷き詰めると継ぎ目が規則的に並んで見えるため、
# 必ず4変種を混ぜて使うこと(既存の_hash_index方式をそのまま流用してよい)。
const ARENA_TILES      := [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0), Vector2i(3,0)]
const HAZARD_TILES     := [Vector2i(4,0), Vector2i(5,0), Vector2i(6,0), Vector2i(7,0)]
const PILLAR_FLOOR     := [Vector2i(0,1), Vector2i(1,1), Vector2i(2,1), Vector2i(3,1)]
const CHOKEPOINT_FLOOR := [Vector2i(4,1), Vector2i(5,1), Vector2i(6,1), Vector2i(7,1)]
```

その他の使用可能タイル:

```
壁            (0,2)-(3,2)        壁(bronze装飾)  (4,2)-(7,2)
柱A 2x2       (0,3)(1,3)(0,4)(1,4)
柱B 2x2       (2,3)(3,3)(2,4)(3,4)
危険地帯 噴出口 2x2  (4,3)(5,3)(4,4)(5,4)
瓦礫 2x2      (6,3)(7,3)(6,4)(7,4)
小物(行5): (0,5)小瓦礫 (1,5)ひび (2,5)bronze格子 (3,5)苔
           (4,5)危険地帯の縁 (5,5)床標 (6,5)骨 (7,5)壁際の傷
```

### `CHOKEPOINT_BLOCK_TILE`の置き換え

新タイルセットに隘路専用のブロックタイルは無い。**壁タイル`(0,2)`〜`(3,2)`を使うこと。**
隘路を絞っている縁は意味的に壁そのものなので、専用タイルを作る必要はない。

---

## 柱を2x2セルに直す(設計仕様との不一致の修正)

現在`PILLAR_BLOCK_TILE`は16x16の1タイル=1セルだが、**設計仕様
(`docs/map_design_spec.md`)では柱は2×2セル**であり、新タイルセットの柱もその寸法で
描かれている。1タイルだけ切り出すと柱の上半分だけが表示される。

### 配置

セル`(cx, cy)`に柱を1本置く場合、4セルすべてを埋める:

```
(cx,   cy  ) = Vector2i(0,3)     (cx+1, cy  ) = Vector2i(1,3)
(cx,   cy+1) = Vector2i(0,4)     (cx+1, cy+1) = Vector2i(1,4)
```

柱Bを使う場合は`(2,3)(3,3)(2,4)(3,4)`。2種類を混ぜて単調さを避けること。

### 間隔

- **柱同士の間隔は3セル(96px)を基本**とする。柱本体2セル + 間隔3セル = **ピッチ5セル**。
- 間隔が1セル以下になる配置を絶対に作らないこと(プレイヤー直径40px・敵直径28pxが
  挟まって動けなくなる)。

### 当たり判定

**4セルすべてに衝突を設定し、`collision_layer = 1`(壁と同じ)にすること。**
敵の`collision_mask = 1`がそのまま効くため、敵も柱を回り込む。
Phase 3で確認済みの「柱越し追跡」テストが引き続き通ることを確認すること。

---

## 検証

1. `--map-gui-capture`で4ゾーンのスクリーンショットを撮り直し、
   **4種の床が組積パターンで判別できること**を目視確認する。
   - 大広間=1枚板 / 柱林=格子 / 隘路=馬目地(ずらしレンガ) / 危険地帯=紫の亀裂
   - 色ではなく石の積み方で区別している。暗い画面でも読めるはず。
2. **床の上でキャラクター・敵・エフェクト・戦利品が埋もれていないこと。**
   地形は背景に徹する設計なので、床が主張していたら報告すること。
3. 柱が2x2で正しく表示され、上半分だけ・4枚並列などになっていないこと。
4. `--map-terrain-rhythm-check`が引き続きPASS(到達性、柱越し追跡、Physics layer 1)。
5. `--map-runtime-check` / `--map-performance-check`が引き続きPASS。
   タイル差し替えで性能が変わることは無いはずだが、念のため確認する。
6. `--headless --editor --quit`が0エラー。

---

## 完了条件

1. `CombatTerrainTileMapLayer`が`assets/tiles/dungeon_tileset_retro.png`を使っている。
2. 4種の床が4変種ずつ混ざって配置されている。
3. 柱が2x2セルで表示され、4セルすべてに`collision_layer = 1`の衝突がある。
4. `terrain_regions.png`の生成が二重管理になっていない。
5. 上記の検証が全てPASSし、目視スクリーンショットで4ゾーンが判別できる。
6. **生成ロジック・Surge・Hazardダメージ・Balance数値を変更していない。**
7. `game_specification.md` §34の該当箇所と`docs/codex_handoff.md`を更新。

**色や密度を調整したくなった場合は、`tools/generate_dungeon_tileset.ps1`を直して
再実行すること。** PowerShell 5.1はBOMなしUTF-8を誤読して日本語コメントで構文エラーを
起こすため、編集後は必ずBOM付きUTF-8で保存してから実行する。
**タイルPNGを直接編集しないこと**(再生成で失われる)。
