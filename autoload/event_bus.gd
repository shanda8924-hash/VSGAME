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
signal fragment_collected(fragment_id: String)
## 互換用の主属性通知。2属性保持中は最後に取得した属性を通知する。
signal active_element_changed(element_id: String)
## ラン中の2属性スロットと各Lv。Fusion用欠片所持数とは独立している。
signal element_loadout_changed(active_element_ids: Array, element_stacks: Dictionary)
## 2属性がともにLv3へ到達し、専用Fusion属性が成立した瞬間。1Runにつき一度だけ発火する。
signal element_fusion_formed(fusion_id: String, display_name: String, source_element_ids: Array)
## General / Element / Fusion MasteryのRankが変化した通知。
signal element_mastery_changed(scope: String, mastery_id: String, rank: int)
## Boss属性報酬の確定通知。UIやテストはChoice Dictionaryを読み、攻撃処理とは接続しない。
signal element_reward_selected(choice: Dictionary)
## ベース攻撃とは別に確定した属性追加ダメージ。chain_index=0は初撃、1以上は雷連鎖。
signal element_damage_dealt(amount: float, position: Vector2, element_id: String, stack_level: int, chain_index: int)
signal mass_kill_triggered(kill_count: int, trigger_position: Vector2)
signal damage_dealt(amount: float, position: Vector2, is_critical: bool)
## Player由来の物理Damageが敵へ実際に通った通知。COMBO/吸血はPlayer被弾も含む
## damage_dealtではなく、この敵限定Signalを購読する。
signal enemy_physical_damage_dealt(amount: float, position: Vector2, is_critical: bool)
## EnemyのHealthへ実際に通ったDamageだけを、対象とTrigger文脈付きで通知する。
## Concept/COMBOはこのSignalを正とし、Presentation用damage_dealtとは分離する。
signal enemy_damage_confirmed(target: Node, amount: float, is_critical: bool, metadata: Dictionary)
signal run_started()
signal run_ended(survived_seconds: float, kill_count: int)
signal run_cleared(room_count: int, elapsed_seconds: float, kill_count: int)
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
