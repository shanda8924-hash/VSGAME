# Codex Task: 性能 Phase 3 — 状態異常有効化後の再発を潰す

対象: `C:\Users\USER\Desktop\Claude Code\game7.30\VSGame`（Godot 4.7.1 / GDScript）

---

## 0. 症状（2026-09-04 実プレイ報告）

MAP1 で **救済タイマー残り約12分**（`boss_fallback_seconds` 900 秒に対し経過 **約3分**）の時点で、
再びフレームレートが落ちた。MAP1 の `enemy_cap` は 32。

**重要**: 直前の修正でこの規模の敵数は 1ms/frame 未満まで下がっていたことを実測している（後述 §2）。
つまりこれは同じ原因の再発ではなく、**その後に有効化した状態異常システムが持ち込んだ別の負荷**である
可能性が高い。ただし未計測なので、まず測ってから直すこと。

---

## 1. 今日入れた変更（この作業の前提）

### 1-A. 敵AI経路探索の修正（性能・完了・実測済み）

- `systems/dungeon_map.gd`
  `has_navigation_clearance(cell)` を追加。「自分と周囲8マスがすべて床」を生成完了後に一度だけ
  `PackedByteArray` へ焼き、以降は配列1回参照で答える。従来は1マスにつき `is_floor()` を9回
  呼んでいた（`is_floor()` は実測 1,396 ns/call）。床の書き換えは生成時だけなので実行中の再構築は無い。

- `components/ai/chase_strategy.gd`
  1. 再探索の判断を**経過時間だけ**に一本化。以前は `_path.is_empty()` と `goal != _path_target` でも
     即再探索していたが、どちらも毎フレーム成立しうるため、`PATH_REFRESH_MSEC`(280) の間引きが
     最も高コストな場面でだけ無効になっていた。
  2. `MAX_PATH_BUILDS_PER_FRAME = 4` を導入（全Agent共有の static 予算、物理フレーム単位）。
     予算切れのAgentは再探索期限を進めず、次フレームに順番が回る。

### 1-B. 状態異常の付与を接続（機能・完了・実測済み）

属性システム廃止時に `hurtbox_component.gd` の `apply_element_damage` を撤去した際、
付与経路を作り直し忘れており、**各職業の主力攻撃が一度も状態異常を付与していなかった**。
900秒の実測で `_burning_targets` が全区間 0 だったことから発覚。以下で接続した。

- `components/hitbox_component.gd` — `applied_status_id: String` を追加（空なら何も付与しない）
- `components/hurtbox_component.gd` — `apply_hitbox_damage()` がダメージ適用の**後**に
  `StatusApplySystem.apply_state()` を呼ぶ。`_status_system_cache` で group 検索を1回に抑えている
- `systems/attack_patterns/attack_pattern_base.gd` — `spawn_point_hit`/`spawn_arc_hit`/`spawn_line_hit` で書き込み
- `components/weapon_manager_component.gd` — `_fire_single_projectile()` で書き込み（spread_shot＋装備武器）
- `systems/attack_patterns/homing_bolt_attack.gd` — 自前 instantiate のため個別に書き込み
- `entities/allies/ally_skeleton.gd` — `_ready()` で召喚主の職業から引く（necromancer 用）
- `components/active_skill_component.gd` — Space技の `burning` 固定をやめ職業の状態に揃えた

**この 1-B が入った後、vsync を切ったフレーム時間の再計測をしていない。ここが検証の穴。**

---

## 2. 既に取得済みの実測値（比較の基準に使うこと）

計測条件: `DisplayServer.window_set_vsync_mode(VSYNC_DISABLED)` ＋ `Engine.max_fps = 0`。
これをやらないと 180Hz の vsync に張り付いて 5.56ms 固定になり、何も見えない。

### 1-A 修正の前後（状態異常は付与されていない時期の値）

| シナリオ | 修正前 | 修正後 |
|---|---:|---:|
| 敵20体 | 0.891 ms | 0.86〜1.32 ms |
| 敵40体 | 2.987 ms | 0.63〜0.76 ms |
| 敵60体 | 8.104 ms | 0.80〜1.24 ms |
| 壁越し40体（視界が遮られた敵32〜34） | **1021.6 ms（1 FPS）** | 0.64〜0.92 ms |
| 経路探索1回 | 15.8 ms | 0.02〜0.73 ms |

### 単位コスト

| 項目 | 実測 |
|---|---:|
| `DungeonMap.is_floor()` | 1,396 ns/call |
| `DungeonMap.has_navigation_clearance()` | 1,695 ns/call（前計算後も GDScript の呼び出しコストが支配的） |
| clearance 前計算（100×100、床3,459セル） | 1.4 ms（初回1回のみ） |

### 蓄積は無いことの確認（論理900秒 × 31サンプル）

Orphan Node 全区間 0 / EventBus シグナル接続数 46 で一定 / Tween 0〜2 /
VRAM 28→44.8MB で頭打ち / Node 増加分はすべて生存中の敵。**リークではない。**

---

## 3. Phase 1: 計測（修正はまだ行わないこと）

### 3-1. まず再現条件を数字で確定する

`scenes/game.gd` の `map_runtime` 分岐へ一時的にフックを足し、`-- --perf3-probe` でだけ動く
計測用 Harness を `tests/` に置く（**調査後に必ず削除し、`scenes/game.gd` を元に戻すこと**）。

起動は `godot --path . scenes/game.tscn -- --perf3-probe`。
`--headless` だと draw call と VRAM が取れないので**ウィンドウありで動かす**。

Harness の要件:

1. `DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)` と `Engine.max_fps = 0`
2. 実プレイに近い状態を作る。**プレイヤーを操作して敵を倒し続けること**
   （状態異常が実際に乗り続ける状況を作らないと今回の再現にならない）。
   `Input.action_press("ui_left")` 等で最寄りの敵へ寄せる方式で良い
3. 論理300秒以上を30秒刻みでサンプリングし、各サンプルで次を出す
   - 実フレーム時間 avg / p95 / max（`Time.get_ticks_usec()` の差分を自前で積む）
   - `Performance.TIME_PROCESS` / `TIME_PHYSICS_PROCESS`
   - `OBJECT_COUNT` / `OBJECT_NODE_COUNT` / `OBJECT_ORPHAN_NODE_COUNT` /
     `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` / `RENDER_VIDEO_MEM_USED`
   - 生存敵数、`status_apply_system` の `_burning_targets.size()`
   - **状態異常が乗っている敵の数**（`StatusEffectComponent.get_states()` が空でない敵の数）
   - 敵→プレイヤーの平均距離、視界が遮られている敵の数

### 3-2. A/B で要因を帰属させる

同じ敵数・同じ場面で、以下を1つずつ止めて 60 フレームずつ測り、baseline との差を出す。
これをやらないと「重い」で終わって原因が特定できない。

| 切り分け | 止め方 |
|---|---|
| 経路探索 | 全敵の `AIComponent.behavior = null`（測定後 `ChaseStrategy.new()` に戻す） |
| 状態異常の時間経過処理 | 全敵の `StatusEffectComponent.process_mode = PROCESS_MODE_DISABLED` |
| 状態異常の付与 | `StatusApplySystem` を `status_apply_system` group から一時的に外す |
| 敵の処理すべて | 全敵の `process_mode = PROCESS_MODE_DISABLED` |
| 敵の描画 | 全敵の `visible = false` |
| プレイヤーの攻撃 | `player.weapon_manager.process_mode = PROCESS_MODE_DISABLED` |

**報告は「差分 ms」と「baseline に占める割合」で出すこと。** 推測は書かないこと。

---

## 4. 仮説（優先順位順・すべてコード上の根拠あり／未計測）

計測の結果と突き合わせること。計測が別の答えを出したらそちらを優先する。

### 仮説1: `StatusEffectComponent._process()` が毎フレーム2回ずつ配列を確保する（最有力）

`components/status_effect_component.gd:63`

```gdscript
func _process(delta: float) -> void:
	if _active_effects.is_empty():
		return                                   # ← 以前はここで必ず抜けていた
	for effect_name in _active_effects.keys().duplicate():   # ← keys() で1本、duplicate() でもう1本
```

状態異常が一度も付与されていなかった間、この関数は `_active_effects` が常に空で
**即 return していた**。1-B で付与を繋いだ結果、**ほぼ全ての敵で毎フレーム
配列2本のアロケーションとループが走るようになった**。MAP1 の32体で毎秒 3,840 本。

`keys()` は既にコピーを返すので `.duplicate()` は**冗長**。さらに、削除対象を集めてから
消す方式にすればコピー自体が不要になる。

### 仮説2: `has_state()` が毎回 `get_states()` を呼んで新規配列を作る

`components/status_effect_component.gd:44`

```gdscript
func has_state(state_id: String) -> bool:
	return state_id in get_states()      # ← 呼ぶたびに Array[String] を確保し 5×6 の二重ループ
```

呼び出し元が多い。特に `components/player_upgrades_component.gd:96`
`resolve_state_condition_damage()` は **敵が被弾するたびに** `metadata.duplicate(true)` 1回と
`has_state()` 5回を実行する（1ヒットあたり配列5本＋150反復）。
燃焼の継続ダメージも `apply_secondary_damage()` 経由でここを通るため、
**燃焼中の敵の数 × 毎秒2tick** ぶんが上乗せされる。これも 1-B 以前はゼロだった。

`has_state()` は `_active_effects` を直接見れば配列を作らずに答えられる
（`STATE_BY_EFFECT` の逆引きを const で1つ持てば済む）。

### 仮説3: `_has_clear_floor_line()` が毎物理フレーム・全敵・無条件で走る

`components/ai/chase_strategy.gd:59`

視界が通っている敵ではラインを最後まで舐める（早期 return できるのは遮られた時だけ）。
1ステップ = `lerp` + `world_to_grid` + `has_navigation_clearance`(1,695 ns) で概ね 3µs。
`WaveSpawner.spawn_radius = 480` なので湧いた直後は最大約33ステップ ≒ 100µs/体。
32体で 3ms/frame になりうる。刻みは `CELL_WORLD_SIZE * 0.45`（14.4px）と細かすぎる。

対策の方向: 刻みを1セル幅へ粗くする／視界判定も数フレームに1回へ間引く
（敵は毎フレーム進路を変える必要がない）。

### 仮説4: 経路探索の予算 4/frame がまだ重い

BFS 1回が最悪 0.73ms なので `4 × 0.73 = 2.9ms/frame` が上限として残っている。
仮説3と合わせると、それだけで 16.6ms 予算の3分の1を超える。
予算を 2 に下げる、あるいは探索そのものをさらに安くする余地がある。

### 仮説5: 状態変化のたびに `StateIndicator` のテクスチャ差し替えと signal が走る

`_emit_element_states_if_changed()` → `states_changed.emit(current.duplicate())` →
`EnemyBasic._on_states_changed()` → `StateIndicator.set_states()`。
燃焼は命中のたびに再付与され3秒で切れるため、状態の出入りが頻繁に起きる。
Texture 自体は組み合わせ単位の static キャッシュ（上限31件）なので生成は安いが、
**配列確保と signal 発火の頻度**が 1-B 以降に上がっている。

### 仮説6（本命ではないが確認は必要）: 描画側

MAP を進むと draw call が 38 → 183 まで増えるのは実測済み。3分時点では効かないはずだが、
Phase 1 のサンプルに含まれているので数字で否定しておくこと。

---

## 5. Phase 2: 修正（Phase 1 の結果を報告してから着手）

- 計測で支配的と判明したものから順に直す。**仮説の順番どおりに直すのではなく、実測の順番で直す。**
- 1つ直すごとに §3-1 と同じ Harness で測り直し、**前後の数値を並べて報告する**。
- ゲームの挙動を変えないこと。特に、敵が壁を回り込んで接近する挙動は維持する
  （検証方法: 壁越し状態を10秒維持し、敵→プレイヤーの平均距離が縮み、
  視界が遮られた敵の数が減ることを確認する。修正前の実測は 552px → 202px、34体 → 17体）。

---

## 6. 制約

- `data/` の数値（敵HP倍率・`enemy_cap`・`boss_fallback_seconds` 等）は**触らない**。
  難易度調整は性能問題と切り離して後で行う。
- `MAX_PATH_BUILDS_PER_FRAME` や `PATH_REFRESH_MSEC` を変える場合は、
  §5 の挙動確認を必ず通すこと。
- 状態異常の付与経路（§1-B）は**消さない**。重いなら安くする方向で直す。
- 計測用 Harness は作業後に削除し、`scenes/game.gd` を元に戻すこと。

---

## 7. 受け入れ条件

1. Phase 1 の計測結果が、A/B の差分 ms と割合つきで報告されている。
2. 実プレイ相当（MAP1・敵32体・状態異常が乗っている状態）で
   **p95 フレーム時間が 16.6ms を大きく下回る**こと。数値で示すこと。
3. 敵の回り込み挙動が維持されていること（§5 の検証方法で数値を出す）。
4. 既存の回帰がすべて PASS すること。
   - `godot --path . scenes/game.tscn -- --map-runtime-check`
   - `godot --path . scenes/game.tscn -- --map-terrain-rhythm-check`
   - `godot --path . scenes/game.tscn -- --map-performance-check`
5. **全 `.gd` を実際に `load()` して失敗0件**であること。
   `--headless --path . --editor --quit` は**パースエラーを報告しないことが確認済み**なので、
   これだけで済ませないこと（実際にこの見落としで `tests/` 8本が3日間壊れていた）。
   さらに、autoload のプロパティ参照のような実行時解決は `load()` でも検出できないため、
   主要シーン（`title.tscn` / `home.tscn` / `game.tscn`）を実際に起動してエラー0件を確認すること。
6. `game_specification.md` の 38 章を計測結果で更新すること。
