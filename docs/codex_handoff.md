# Codex Handoff — 2026-08-25

## 現在状態

- 通常Runは3MAP探索。ROOM自動進行は通常経路から外し、Code/Data/Testは復旧用に保持。
- MAPごとに自然湧き、配置宝箱4、Attribute/生命祭壇、Elite、最深部Boss領域を使用する。
- XP Level UpはAttribute 3択。Skillは宝箱/Boss宝箱のみ。Equipment/Inventory/Equip/Merge、COMBO、全10FusionをMAP間で維持。

## 復旧点

- ROOM版Backup commit: `8d41751`
- ROOM版Branch: `codex/room-system-backup-20260825`
- 現作業Branch: `codex/map-exploration-rebuild-20260825`

## 主な接続先

- 進行: `systems/map_run_controller.gd`
- MAP設定: `data/maps/exploration_run.json`
- 通常入口: `scenes/game.gd` / `autoload/game_manager.gd`
- 探索物: `entities/stage_environment/map_landmark.gd` / `entities/pickups/treasure_chest.gd`
- Spawn固定曲線: `systems/wave_spawner.gd` / `data/difficulty/map_exploration.json`

## 確認結果

- `map_entry_input_check`: GAME START→通常ゲーム→Soldier→MAP1をInputMap操作だけで通過 PASS。
- `--map-runtime-check`: MAP1→2→3、Attribute、3Boss、Boss宝箱、Skill、Run Clear PASS。
- `--map-soak-check`: 論理1818.7秒、通常宝箱12、敵上限、3Boss、全遷移 PASS。
- Vulkan RTX 4060 / Forward Mobile: MAP開始、Boss領域、Boss戦 PASS。画像は`artifacts/map_exploration_*.png`。
- 既存Equipment/Merge/Fusion 10種/Concept/ROOM COMBO/ROOM遷移回帰はPASS。

## 次に触る場合

- 実プレイヤー操作で各MAP10〜15分の体感、通常敵8〜15Hit/強敵15〜25Hit、宝箱配置密度を調整する。
- 数値変更は`data/maps/exploration_run.json`と`data/difficulty/map_exploration.json`を優先し、Player Build追従Scalingを追加しない。
- 通常進行へROOM CLEAR/ROOM Reward/RoomSelectを再接続しない。
