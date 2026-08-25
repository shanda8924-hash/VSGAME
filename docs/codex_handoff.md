# Codex Handoff — 2026-08-25

## 現在状態

- 通常Runは3MAP探索。ROOM自動進行は通常経路から外し、Backup `8d41751` / branch `codex/room-system-backup-20260825`に保持。
- MAP固定値はHP×2.50/3.25/4.00、敵上限32/40/48、Boss解放420/650/900体、救済15/16/17分。
- 完成Skillは既存18条件追撃+5完成大技。雷帝落雷、煉火天柱、氷槍豪雨、光刃陣、虚無断界が独立Cooldownで自動発動する。
- 大技はLv1→3、属性Stack、Element/Fusion Mastery、Character/通常強化/装備Attackへ接続。敵不在はREADYを保持する。
- Test Lab CONCEPTから大技選択、GRANT/Lv.UP、即時発動、Cooldown READY、24体群、全5種Previewが可能。

## 主な接続先

- 実行/Cooldown/補正: `systems/concept_system.gd`
- Data/日本語: `data/skills/completed_skills.json` / `data/localization/ui_ja.json`
- 固有VFX: `effects/concept_skill_vfx.gd`
- MAP候補Weight: `systems/map_run_controller.gd`
- Test Lab: `scenes/developer_test_lab.gd`

## 確認結果

- `signature_skill_runtime_check`: 5種、属性Lv3、装備Attack、Cooldown連続循環、対象削除Echo、敵不在READY PASS。5種同時Peak VFX 13、残留0。
- `concept_build_runtime_check` / `concept_fusion_stress_check` / `equipment_merge_check` / `developer_test_lab_check`: PASS。
- `--map-runtime-check`: 3MAP/Boss/Skill/Run Clear PASS。MAP2/3遷移最大slice 26.825/24.134ms。
- `--map-combat-check`: 雷Lv3+雷帝落雷Lv1で自然撃破420/420、論理370.6秒 PASS。
- `--map-soak-check`: 論理2006.3秒（33.4分）、敵上限、12宝箱、Elite、3Boss、Result PASS。
- Vulkan RTX 4060 / Forward Mobile: Test Lab全5大技個別描画10 screenshots、Debugger gameplay error 0、ブラックアウト0。

## 次に触る場合

- 実プレイヤー操作で各MAP10〜15分の体感と、完成大技Lv2/3の後半画面密度を調整する。
- 通常進行へROOM CLEAR/RoomSelectを再接続せず、新属性追加時は完成大技Data+VFX profileを同じ経路へ追加する。
