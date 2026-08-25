# Codex Handoff — 2026-08-16

## 現在状態

- 通常Runは36ROOM。4の倍数がBoss、ROOM 36がFinal。既存の属性5種/Fusion 10種/COMBO/ラン内装備を維持。
- 装備合成は「同一装備3個」から「名称・部位を問わない同一Rarity 3個」へ変更済み。
- 装備画面は「装備 / 合成」の2モード。合成側は3素材Slot、Rarity数、3→1 Preview、局所Pixel演出、完成品比較/即時装備を持つ。

## 今回の主要変更

- 3素材の実体参照・Inventory所属・装備中・Lock・Rarity・出力Poolを取引直前に再検証。完成品生成後だけ3→1を一括置換し、失敗時は無消費。
- 完成品は次Rarityの既存Template Poolから選択。素材に含まれる部位を優先し、Stats品質は既存Rarity範囲へ正規化。
- 所持一覧の旧`1 / 3`表示を削除。合成中の連打を遮断し、初回後はMouse/E/決定で演出Skip可能。
- Test Labへアンコモン/レア/エピック各3素材生成と、実合成画面を開くButtonを追加。

## 確認結果

- `equipment_merge_check`: failures=0。異名Uncommon→Rare、Rare→Epic、混在/装備中/Lock/候補なし無消費、二重実行、3Slot、演出/Skip、即時装備。
- `equipment_integration_check`: failures=0。既存Drop/Inventory/Equipを維持。
- `character_screen_layout_check`: failures=0（1600×900、6装備Slot）。
- Vulkan RTX 4060 / Forward Mobile: `equipment_merge_check` failures=0、3Slot/収束中/完成Cardを実描画確認。`developer_test_lab_check` failures=0。
- Visual evidence: `artifacts/equipment_merge_overhaul/`。

## 参照

- Specification: `game_specification.md` 23.5〜23.7
- Visual rule: `docs/vsgame_pixel_visual_guide.md`
