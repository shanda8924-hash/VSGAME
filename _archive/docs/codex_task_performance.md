# Codex Task — 実行時間経過による性能劣化の原因特定 (2026-08-30)

## このTaskの位置づけ

**Phase 1(原因特定)のみを実施する。修正は行わない。**

症状: Runを数分続けると重くなる。生存中の敵数に比例していないため、単純な敵の増加が
原因ではない。時間とともに何かが蓄積している疑いが強い。

事前調査で有力な仮説は得られているが、**仮説のまま修正してはいけない**。実測で
「何が・どれだけ増えているか」を確定させ、数値を持って報告すること。想定と実測が
食い違った場合は、実測を正とする。

```text
Scope: 性能計測harnessの追加、蓄積源の実測・特定、計測結果の報告
Out of Scope: Gameplay Balance、Map、Equipment UI、Forge、HUD、Element/Fusionの数値調整
```

修正(Phase 2)は、この報告を受けてから別Taskとして指示する。

---

## 前提: 既存harnessには2つの死角がある

`tests/map_exploration_runtime_check.gd`の`--map-soak-check`は論理30分・20倍速で全3MAPを
完走する既存テストだが、**そのままでは今回の問題を再現できない**。

1. **性能の経時変化を計測していない** — 撃破数・敵上限・Boss生成といった正しさしか
   見ておらず、ノード数やフレーム時間の推移を記録していない。
2. **プレイヤーの攻撃と移動を無効化して回している** — `map_exploration_runtime_check.gd:143`で
   `player.weapon_manager.process_mode = Node.PROCESS_MODE_DISABLED`、`:144`で
   `set_movement_locked(true)`。つまり**攻撃由来のVFX・撃破・ドロップがほとんど発生しない**。
   蓄積源の候補がちょうどこの死角に入っている。

計測harnessを追加する際は、この2点を必ず解消すること。攻撃を有効にできない技術的理由が
あるなら、代替として「敵を強制撃破し続けてドロップを発生させる」経路で構わないが、
**ドロップ・VFX・撃破が実際に発生している状態で計測する**ことが必須。

計測の書き方は`tests/room_transition_performance_check.gd:80-116`が既に良い手本になっている
(`Performance.get_monitor(Performance.OBJECT_NODE_COUNT)` / `OBJECT_COUNT`、frame slice計測)。
これを流用してよい。

---

## 計測すべき項目

論理20〜30分のRunを通して、**一定間隔(論理30秒ごと程度)でサンプリングし、時系列で
printする**こと。最初と最後だけの2点比較では「増え続けているのか、頭打ちなのか」が
判別できない。

必須:

| 項目 | 取得方法 |
|---|---|
| 経過時間 | `GameManager.elapsed_seconds` |
| 総ノード数 | `Performance.get_monitor(Performance.OBJECT_NODE_COUNT)` |
| 総オブジェクト数 | `Performance.get_monitor(Performance.OBJECT_COUNT)` |
| フレーム処理時間 | `Performance.get_monitor(Performance.TIME_PROCESS)` / `TIME_PHYSICS_PROCESS` |
| 生存中の敵数 | `get_tree().get_nodes_in_group("enemies").size()` |
| 地面の装備数 | `get_tree().get_nodes_in_group("ground_equipment").size()` |
| 累計撃破数 | `GameManager.kill_count` |

「生存中の敵数」を必ず併記すること。**敵数が横ばいなのにノード数とフレーム時間だけが
伸び続けている**なら、蓄積が原因だと確定できる。これが今回の核心。

余力があれば、`CPUParticles2D`の総数など特定ノード型の集計も出すと原因が絞り込める。

---

## 有力仮説(検証対象。事実として扱わないこと)

### 仮説A: 地面に落ちた装備が永久に残る ← 最有力

`entities/pickups/ground_equipment_item.gd`には**消滅処理が存在しない**。
`_process`による寿命カウントもタイマーもなく、`queue_free()`されるのは`collect():222-231`
(プレイヤーが手動で拾う)経路のみ。

対照的に、兄弟である`entities/pickups/heart_pickup.gd:7,22-26`には
`lifetime_seconds = 25.0`と`_process`内の寿命切れ`queue_free()`がある。この非対称は
意図的な仕様か、単なる実装漏れか不明。

さらに悪いことに、残り続けるノードは静的ではない:

- `:138-153` `LootAmbientParticles` — `one_shot`未設定のため**永久に放出し続ける**
  `CPUParticles2D`。レア度に応じて`amount`は2〜9。
- `:91-106` legendary/mythicには**もう1つ**常時放出`CPUParticles2D`が追加される。
- `Area2D`本体が`monitoring = true`(`:21`)のまま常駐する。

発生頻度も高い。`systems/equipment_drop_system.gd:31`により、**MAPモードではElite撃破時の
ドロップ率が1.0に固定**されている(通常敵は2%)。宝箱4個ぶんも同じ経路で床に出る。

解放されるのはMAP遷移時の一括掃除(`systems/map_run_controller.gd:322-328`、group
`"ground_equipment"`)だけ。1MAPは15〜17分あるため、その間ずっと蓄積する。

**確認してほしいこと**: 実測で`ground_equipment`グループのノード数が時間とともに
単調増加するか。増加するなら、その数がフレーム時間の悪化と相関しているか。
**数が20〜30程度にとどまるなら、これ単独では体感の重さを説明できない可能性がある**。
その場合は「これも一因だが主因は別」と報告し、他の蓄積源を探すこと。

### 仮説B: Fusion markの取りこぼし

`systems/fusion_combat_runtime.gd`の`_solar_marks`(`:206-214`)/`_inferno_marks`(`:235-245`)は、
敵の`died`シグナル経由でしかエントリが削除されない。

しかし`wave_spawner.gd:310`や`map_run_controller.gd:328`など、敵を`HealthComponent.died`を
経由せず直接`queue_free()`する経路が存在する。この経路で消えた敵のmarkは、次の
`run_started`/`run_ended`まで残留する可能性がある。

同ファイル内の`_plasma_cores`や`element_combat_system.gd`の`_burning_targets`は毎tick
`is_instance_valid()`で掃除しているので、**同じ防御をmark側だけが持っていない**という
非対称になっている。

MAP単位で上限があるため仮説Aより影響は小さいはずだが、実測で確認すること。

---

## 調査済み・シロと判断済み(再調査しないこと)

Context節約のため、以下は既に確認済み。時間を使わないこと。

- **ダメージ数値表示** — `effects/damage_number_manager.gd`は36個の固定プールを
  `visible`フラグで使い回すObject Pool実装。蓄積しない。
- **VFXPoolManager** — 同じくプール実装。蓄積しない。
- **AttackVFXManager** — 生成するノードに`animation_finished`→`queue_free`と
  `create_timer(lifetime+0.1)`→`_free_weak_ref`の**二重**の解放経路がある。堅牢。
- **EffectThemeManager** — 全パーティクル/Lineに`create_timer().timeout.connect(queue_free)`あり。
- **敵の死亡処理** — `enemy_basic.gd:242-263`は`death_finished`をCONNECT_ONE_SHOTで
  `queue_free`に繋ぎ、`animation_component`が無い場合は即時`queue_free()`にフォールバックする。
- **WaveSpawner / EliteRoomManager / BossSpawner の内部追跡辞書** — `died`/`tree_exited`の
  one-shotで刈られ、部屋/Elite数で上限が決まる。累計撃破数に比例して伸びない。
- **Autoloadのコレクション** — `GameManager`に無制限に伸びるログ配列等はない。
  `MassKillTracker`は窓付きで毎回再フィルタしている。
- **無限ループTween** — プロジェクト全体で2箇所のみ。`heart_pickup.gd:14`(25秒寿命の
  ノードの子なので一緒に死ぬ)と`ui/common/retro_segment_gauge.gd:112`(常駐UI)。孤児化しない。
- **`.connect()`の重複** — 調べた範囲では`is_connected()`ガードかCONNECT_ONE_SHOT付き。

---

## 既知の環境問題(先に確認すること)

このマシンでは`godot --headless --path . --script res://tests/XXX.gd`が、
**編集していない既存ファイルでも**`Compile Error: Identifier not found: GameManager/EventBus/
DataLoader`で全滅する。切り分け済みの事実は`docs/codex_handoff.md`の該当節を参照。

`--headless --editor --quit`(全スクリプトの構文チェックを含むプロジェクト再スキャン)は
正常に完走するので、構文の検証には使える。

計測を実行するには、この問題を回避する必要がある。**まずこれが自分の環境でも再現するか
確認すること。** 再現するなら、その切り分け・解決自体を最優先タスクとしてよい
(これが解決しないと以降の全機能検証が困難なため)。回避策として`--map-soak-check`のような
`OS.get_cmdline_user_args()`経由でmain sceneから起動する既存方式が動くなら、そちらを使う。

---

## 完了条件

1. 論理20〜30分のRunで、上記項目の時系列サンプリング結果が取れている。
2. **敵数が横ばいの区間でノード数/フレーム時間が伸びているか**が明確に答えられる。
3. 蓄積している対象が特定でき、その増加数と性能悪化の相関が数値で示されている。
4. 仮説A・Bそれぞれについて「主因/一因/無関係」の判定が実測に基づいて出ている。
5. 仮説A・B以外に蓄積源が見つかった場合、それも同じ粒度で報告されている。
6. `docs/codex_handoff.md`が計測結果の要約で更新されている(生ログは貼らない)。

**この段階では修正しない。** 計測harnessの追加は行ってよいが、`ground_equipment_item.gd`や
`fusion_combat_runtime.gd`の挙動は変更しないこと。修正内容は計測結果を見てから決める。

寿命を持たせる修正は「拾えなかった装備が消える」というゲーム性の変更を伴うため、
実装方針(寿命の長さ、上限個数方式との比較、古いものから消すか等)はユーザー判断が必要になる。
Phase 2の指示を待つこと。
