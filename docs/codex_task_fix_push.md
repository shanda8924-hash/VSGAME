# Codex Task — プレイヤーが敵を押しのける不具合の修正

**これは以前の敵衝突レイヤー修正(未コミット差分「1. 敵密集時の重さ」)の副作用による不具合。**
新機能ではなく回帰の修正。実プレイで「前進すると敵を押し出せる」状態になっている。

```text
Scope: Player/Enemy/壁のcollision layer・maskの整理
Out of Scope: Gameplay Balance、Damage、AI、地形生成、VFX
```

---

## 原因

| 対象 | layer | mask |
|---|---|---|
| Player本体 (`player.tscn` CharacterBody2D) | 1 (Godot既定) | 1 (Godot既定) |
| Enemy本体 (`enemy_basic.tscn` CharacterBody2D) | **8** | 1 |
| 壁・柱 (`stage_environment.gd` `WALL_COLLISION_LAYER_BIT`) | **1** | 0 |

壁とPlayerが**同じbit 1を共有している**ことが問題。

- 敵のmask=1には壁だけでなく**Player本体(layer 1)も含まれる** → 敵はPlayerに押し返される
- Playerのmask=1には**敵のlayer 8が含まれない** → Playerは敵を素通りする

結果、**Playerだけが一方的に敵を押しのける**。

---

## 修正: 壁を専用bitへ移す

Playerを別bitへ移す案は、Playerのlayer 1を検知している既存のArea2Dが多数あるため
影響範囲が大きい(`ground_equipment_item.gd` / `heart_pickup.gd` / `treasure_chest.gd` /
`map_landmark.gd` / `elite_room_manager.gd` はいずれも`mask = 1`でPlayerを検知している)。

**壁側を動かす方が影響範囲が小さい。** 柱も同じ`WALL_PHYSICS_LAYER`を使っているため、
1箇所の変更で柱にも反映される。

| 対象 | layer | mask | 変更 |
|---|---|---|---|
| 壁・柱 | **64** | 0 | `WALL_COLLISION_LAYER_BIT` を 1 → 64 |
| Player本体 | 1 (据置) | **64** | maskのみ変更 |
| Enemy本体 | 8 (据置) | **64** | maskのみ変更 |

結果:

- Player ↔ 壁/柱: 衝突する(Playerのmask 64 ⊃ 壁のlayer 64)
- Enemy ↔ 壁/柱: 衝突する
- **Player ↔ Enemy: 物理衝突しない**(相互にmaskへ相手のlayerを含まない)
- Enemy ↔ Enemy: 衝突しない(既存の性能修正を維持)
- Playerはlayer 1のままなので、**既存のPickup/祭壇/Elite部屋の検知は全て無変更で動く**

接触ダメージは`ContactHitbox`(Area2D、layer 16 / mask 2)が担当しており、物理衝突とは
別系統なので影響しない。このジャンルでは敵とPlayerが重なるのが標準の挙動。

### 注意: bit 1で「壁」を検知している箇所を洗い出すこと

壁のbitを動かすため、**壁に当てる意図で`mask = 1`や`collision_mask = 1`を使っている箇所**が
あれば全て64へ更新すること。Player検知が目的の`mask = 1`は**変更しない**(Playerはlayer 1のまま)。

`ShapeCast2D` / `RayCast2D` / `PhysicsRayQueryParameters2D` / `move_and_collide`を使った
壁判定、`_find_safe_drop_position`のような配置判定が該当し得る。**用途を1件ずつ確認すること。**
「Player検知」と「壁検知」がどちらも`mask=1`で書かれているため、機械的な一括置換は禁止。

bit 64が他で使われていないことも確認すること(既知の使用状況: 1=壁/Player本体、
2=Player Hurtbox、4=Enemy Hurtbox、8=Enemy本体、16=Enemy ContactHitbox、32=Projectile/MeleeHit)。

---

## 検証

1. **実機で、前進してもPlayerが敵を押しのけないこと。** 敵とPlayerが重なって通り抜ける。
2. Playerが壁・柱にめり込まず、正しく止まること。
3. 敵が壁・柱にめり込まず、柱を回り込むこと(`--map-terrain-rhythm-check`の柱越し追跡)。
4. 敵の接触ダメージが従来通り入ること。
5. 床の装備・ハート・宝箱・祭壇・Elite部屋の入室検知が従来通り動くこと
   (Playerのlayerを変えていないので壊れないはずだが、実機で必ず確認する)。
6. `--map-runtime-check` / `--map-terrain-rhythm-check` / `--map-performance-check` がPASS。
7. `--headless --editor --quit` が0エラー。

---

## 完了条件

1. 実機でPlayerが敵を押しのけない。
2. 壁・柱への衝突がPlayer/敵とも従来通り。
3. 上記の検知系が全て動作。
4. 壁検知目的の`mask=1`が漏れなく64へ更新され、Player検知目的の`mask=1`は据え置かれている。
5. `docs/codex_handoff.md`を更新(未コミット差分「1. 敵密集時の重さ」の記述も現状に合わせて修正)。
