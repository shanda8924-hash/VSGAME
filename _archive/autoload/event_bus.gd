extends Node
## グローバルSignalハブ。
## 各System/UIはこのシグナルを購読することで、Entity同士やUI側と疎結合を保つ。
## 新機能(実績・ランキング・デイリーミッション等)を追加する際も、
## 既存コードを一切変更せずここのSignalを購読するだけで実装できる。

signal enemy_died(enemy_data: Resource, death_position: Vector2)
signal enemy_drop_requested(death_position: Vector2, is_elite: bool, is_boss: bool)
signal healing_received(amount: float, position: Vector2)
signal player_damaged(amount: float, current_hp: float, max_hp: float)
signal player_leveled_up(new_level: int)
## 互換用の主属性通知。2属性保持中は最後に取得した属性を通知する。
## ラン中の2属性スロットと各Lv。Fusion用欠片所持数とは独立している。
## 2属性がともにLv3へ到達し、専用Fusion属性が成立した瞬間。1Runにつき一度だけ発火する。
## General / Element / Fusion MasteryのRankが変化した通知。
## Boss属性報酬の確定通知。UIやテストはChoice Dictionaryを読み、攻撃処理とは接続しない。
## ベース攻撃とは別に確定した属性追加ダメージ。chain_index=0は初撃、1以上は雷連鎖。
signal mass_kill_triggered(kill_count: int, trigger_position: Vector2)
signal damage_dealt(amount: float, position: Vector2, is_critical: bool)
## Player由来の物理Damageが敵へ実際に通った通知。COMBO/吸血はPlayer被弾も含む
## damage_dealtではなく、この敵限定Signalを購読する。
signal enemy_physical_damage_dealt(amount: float, position: Vector2, is_critical: bool)
## EnemyのHealthへ実際に通ったDamageだけを、対象とTrigger文脈付きで通知する。
## Concept/COMBOはこのSignalを正とし、Presentation用damage_dealtとは分離する。
signal enemy_damage_confirmed(target: Node, amount: float, is_critical: bool, metadata: Dictionary)
## 戦闘強化・秘技が実際に発動した通知（HUDのビルド表示のピップを光らせる、Phase 2）。
signal upgrade_triggered(upgrade_id: String, position: Vector2)
signal run_started()
signal run_ended(survived_seconds: float, kill_count: int)
signal run_cleared(room_count: int, elapsed_seconds: float, kill_count: int)
## セーブしないラン専用ゴールド。sourceはHUD演出・検証用で、経済計算には使わない。
signal run_gold_changed(current_gold: int, delta: int, source: String)
## 通常RunのMAP探索進行。ROOM進行Signalはテスト／復旧用に残し、通常UIは
## こちらだけを購読する。
signal map_started(map_index: int, total_maps: int, display_name: String)
signal map_progress_changed(map_index: int, elapsed_seconds: float, fallback_seconds: float, kill_count: int, required_kills: int)
signal map_surge_started(map_index: int, surge_index: int, trigger_reason: String, duration_seconds: float)
signal map_surge_ended(map_index: int, surge_index: int, reward_type: String, reward_position: Vector2)
signal map_boss_unlocked(map_index: int)
signal map_completed(map_index: int, elapsed_seconds: float, kill_count: int)
signal treasure_reward_revealed(reward_type: String, rarity: String, position: Vector2)
## 精鋭部屋(Elite Room)にプレイヤーが入室/クリアしたタイミングで発火する。
## room_indexはDungeonMap.roomsの添字。WaveSpawnerはこれを購読して、
## 精鋭部屋の攻略中は通常の雑魚湧きを止める。
signal elite_room_entered(room_index: int)
signal elite_room_cleared(room_index: int)
## ボス戦の開始/終了。WaveSpawnerが購読し、ボス戦中は通常の雑魚湧きを止める。
signal boss_fight_started(boss_display_name: String)
signal boss_fight_ended()
## ボスのHP変化をHUDへ伝える(HUD側は表示専用、状態はBossSpawnerが持つ)。
signal boss_health_changed(current_hp: float, max_hp: float)
## ボス撃破報酬としてアイテムを獲得した際に発火する(HUDのポップアップ演出/一覧表示用)。
signal item_acquired(item_id: String, display_name: String)
signal equipment_dropped(equipment: EquipmentData, position: Vector2)
signal equipment_picked_up(equipment: EquipmentData)
signal equipment_equipped(equipment: EquipmentData)
