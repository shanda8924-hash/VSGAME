# 移動接触・壁の厚み・生成Pixel VFX

2026-09-05 / Godot 4.7.1 / 既存の未コミット変更を保持。

## 移動の調査と採用案

市場の方向性は[Brotatoの公式説明](https://store.steampowered.com/app/1942280/Brotato/)の
自動攻撃・大量敵の殲滅と、[Halls of Tormentの公式説明](https://store.steampowered.com/app/2218750/Halls_of_Torment/)の
地下探索・敵群との連続戦闘を参考にした。以下は本作への設計提案であり、他作品の内部collision設定が同一と確認したものではない。

| 案 | 判断 |
|---|---|
| 本体は通過、攻撃だけKnockback | 採用。歩行で敵を運ばず、大量敵の中でも操作が詰まらない |
| Playerも敵を障害物として扱う | 不採用。密集でプレイヤーが動けなくなる性質が強い |
| 雑魚は通過、Bossだけ通行を塞ぐ | 今回は不採用。押し出し修正以上の新しい当たり判定規則になる |

原因は非対称のBody設定。Playerはlayer1/mask1、Enemyはlayer8/mask1で、PlayerだけがEnemyへめり込めた。
その後Enemyの`move_and_slide()`が重なりを回復し、敵を外へ押し出した。
[Godotのsafe_margin説明](https://docs.godotengine.org/en/stable/classes/class_characterbody2d.html#class-characterbody2d-property-safe-margin)にも
近接Bodyを衝突として押し戻す回復動作が説明されている。

修正は`EnemyBasic._ready()`でPlayer/Enemy本体だけ相互collision exceptionにするもの。
Player先→Spawner敵生成の本編/Developer Lab経路を確認。壁layerを消さず、拾得・武器Hit・予備攻撃を維持。

実Player/Enemy Scene、90 physics frameのA/B:

| 条件 | 停止敵の移動 |
|---|---:|
| テスト内で旧設定を復元 | 154.895px |
| 修正後・1体 / 32体 / Boss | いずれも0.000px |

Melee実Areaの命中、30px Knockback、Boss耐性で3px、壁停止、予備攻撃の命中/回避、拾得layer1もテストする。
敵の通常攻撃は既存の「予備動作→距離再判定」で、重なった瞬間の新規ダメージは加えていない。

## 壁

旧selectorは「直下が床＝正面、それ以外＝同じ天面」のみで、背面/側面の縁がなかった。
新しい画像`assets/tiles/royal/wall_edges.png`の上1/左2/右4 Maskで、床に接する境界だけ厚みを付ける。
正面は元画像を優先。同期/非同期buildを共通selectorに接続し、元の16px矩形Collisionを維持する。
36seed・18,618境界セル・全7Mask・正面優先・柱追跡のHeadless検査に合格。

## 全生成画像と接続先

保存先はすべて`assets/vfx/pixel/<ID>.png`。34動画は384×64（64px×6コマ）、静止3画像は64/24px。

| ID（各々PNGを生成） | 実ゲームの接続先 |
|---|---|
| `active_burst`, `active_charge`, `active_aura`, `active_shield`, `active_sanctuary`, `active_time`, `active_summon`, `active_chains`, `active_holy_burst`, `active_execution`, `active_impact`, `active_rain` | `ActiveSkillComponent._spawn_vfx_at` → `ActiveSkillVFX` |
| `concept_thunder_strike`, `concept_fire_burst`, `concept_ice_nova`, `concept_wind_blade`, `concept_light_burst`, `concept_dark_rift` | `ConceptSystem._play_skill_vfx` → `ConceptSkillVFX` |
| `signature_thunderlord_descent`, `signature_inferno_pillar`, `signature_glacial_spear_rain`, `signature_radiant_blade_array`, `signature_void_severance` | 同上のsignature_profile |
| `hit_fire`, `hit_ice`, `hit_lightning`, `hit_light`, `hit_dark` | 武器/Projectile → `EffectThemeManager.play_weapon_hit`（旧属性成長ではない） |
| `beam`, `chain` | `EffectThemeManager._spawn_line/_spawn_chain` |
| `mass_kill` | `VFXPoolManager`の6個プール、MassKill/Boss/精鋭報酬 |
| `loot_awaken` | `GroundEquipmentItem._build_ground_effects`、0.7秒 |
| `forge_awaken` | `EquipmentScreen._spawn_merge_impact`、独立1枚 |
| `poison` | `EliteHazard`の子としてループ、親と同時終了 |
| `warning_ring`（静止64px） | `WarningCircle` / `EliteHazard`、見える円周と判定半径を一致 |
| `projectile_core`（静止24px） | `projectile.tscn::Glow`、旧GradientTextureだけを置換 |
| `loot_seal`（静止64px） | `GroundEquipmentItem::RoyalLootSeal`、レアリティ色/寸法 |

組み込みimage_genで実際に生成。Pythonは承認された切り出し・Nearest縮小・Alpha整理のみ。
採用した元PNGと全プロンプトは`assets/vfx/pixel/sources/`、`source_manifest.json`に保存。
コマ境界が混ざった初回Concept/Signature atlasは不採用とし、効果ごとの3×2コマ画像で再生成した。
再実行: `python tools/import_generated_pixel_vfx.py --manifest assets/vfx/pixel/source_manifest.json`。
各コマの不透明画素数と接続ファイルは`asset_inventory.json`。全204コマが非空、透過0/255。

共通再生器はSpriteFrames/Textureを共有し、毎HitのGPU→CPU画像読み戻しを行わない。
Position/AlphaのTweenなし。画像そのものの形成/拡張/外周破砕で演出する。
Vulkan確認で広範囲Space画像が人物を覆い過ぎたため、Space/Conceptの表示だけ192world pxを上限にした。
ダメージ範囲は変更しない。敵の警告輪は上限対象外で、半径を正確に表示する。

旧GPUパーティクルResourceは互換のため残るが、新しい実行経路からinstantiateしない。
既存の攻撃Projectile/Pulse/通常Hit/Critical HitのPixel画像と本人の残像は維持。
Criticalの追加Polygonだけ除去。削除済みの黄色い通常攻撃三日月・属性/Fusion・傷跡は復活させない。
UI枠/文字、状態情報バー、カメラ/Hit-stop/短い画面flash、Boss silhouette outline、静的な宝箱/炉/地形オブジェクトは別扱いで維持する。

## 検証

- `generated_pixel_vfx_vulkan_final.log`: Vulkan Mobile / RTX4060、34動画全接続、frame/cache、実VFX公開入口、位置/alpha固定、遅延解放、生成予算、6プール、failures=0。
- `pixel_world_vulkan_final.log`: Developer Lab内の実`game.tscn`。Projectile16.00→実Damage16.00/1hit、Space104.50、完成技67.24、failures=0。
  表示上限調整の前後で上記ダメージは同一。自然ラン全体のバランスを測った値ではない。
- `wall_edges_runtime_check.log`: 36seed / 18,618境界セル。
- `pixel_hazard_check.log`（Headless）/ `pixel_hazard_vulkan_final.log`: 円周実画素25px→正しい攻撃半径、毒床のframe/loop/親終了、予告中非攻撃、範囲内外Damage、Projectile6px判定。
- `pixel_loot_equipment_integration.log`, `pixel_loot_visibility.log`, `pixel_loot_cap_feature_fixed.log`: 取得/表示/短命終了/装備/上限24/保護対象、すべてPASS。
- `pixel_vfx_script_load_final.log`: 全154 Script実load、failures=0。
- `movement_contact_vulkan.log`: 旧設定154.895px→修正版1体/32体/Boss全0.000px、壁/Knockback/敵攻撃/拾得、failures=0。
- `pixel_forge_vulkan.log`: 実装備画面の合成/Skip/即装備/二重取引防止、failures=0。
- `forge_vfx_budget_vulkan_final.log`: 実際の96個飽和とPause中にもForge1枚が表示/進行/完了、連続callbackでも重複なし、failures=0。
  青Rarityで原画の橙を強く乗算すると濁ることを実画面で確認したため、出現/合成だけ75%白寄せTintに修正。
  地面の静止紋章とUI枠/ラベルのレアリティ色はそのまま。
- `pixel_title_vulkan.log`: 通常タイトル起動、exit=0。

Vulkan画像: `artifacts/generated_pixel_vfx_gallery.png`、`artifacts/pixel_world/`の壁、Space/完成技/Hit+Dropのframe1/2/4。
合成中の実画面は`artifacts/forge_pixel_awakening.png`。
通常セーブを変えないephemeral sessionで検証。本編/Developer Labへ検証用フックを追加していない。
テスト専用の固定地形/フレーム停止/カメラ位置はゲーム製品には持ち込まない。

### 検証範囲の限界

自動fixtureによる実Godot実行と描画確認であり、人が通しで遊んだ長時間ランではない。
全職業・全23完成大技・全MAPを自然成長で一巡する検証、物理ゲームパッド、他GPU/解像度は未実施。
画像化でフレームレート低下が根絶したと主張するものではない。過去の性能切り分け方針やdataの戦闘/経済数値は変更しない。

## 今回変更した実装

- `entities/enemies/enemy_basic.gd`: 本体衝突の相互除外。
- `entities/stage_environment/stage_environment.gd`: 専用壁境界PNG/TileSet選択。
- `effects/pixel_sprite_vfx.gd`: 共通画像再生/キャッシュ/予算。
- `effects/active_skill_vfx.gd`, `concept_skill_vfx.gd`, `effect_theme_manager.gd`: 攻撃画像の接続。
- `effects/attack_vfx_manager.gd`: 追加Critical Polygonのみ撤去。
- `effects/vfx_pool_manager.gd`: 6個の画像プール。
- `systems/boss_ai/warning_circle.gd`, `systems/elite_hazard.gd`: 警告/毒床画像。
- `entities/projectiles/projectile.tscn`: Glow画像。
- `entities/pickups/ground_equipment_item.gd`: 画像2枚のDrop。
- `ui/equipment/equipment_screen.gd`: Forge画像/独立1枠。
- 上記のPNG、`tools/import_generated_pixel_vfx.py`、画像manifest/本記録/`game_specification.md`。
- 回帰テスト新規: movement_contact/pixel_sprite_vfx/pixel_world/pixel_hazard/forge_vfx_budget。
  既存map_terrain/loot_visibility/equipment_integration/map_performance/pixel_visual_integration/DeveloperLabの
  旧描画方式期待値を画像へ更新。セーブ保護とheadless描画待ち修正はテスト内のみ。

元々存在する大量の未コミット差分（属性削除等）をリセットしていない。今回の差分をGit HEADとの差分全体と取り違えないこと。
