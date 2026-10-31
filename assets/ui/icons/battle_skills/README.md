# Battle skill icons

The project owner supplied `physical_sheet.png` and `magic_sheet.png` on 2026-09-09.
Selected 64x64 cells are centered without resampling on transparent 72x72 canvases.

- `upgrades/`: level-up and shop upgrade icons, named after `UpgradeData.id`.
- `completed/`: completed-skill reward icons, named after the completed skill id.
- `talents/`: talent roots that do not have an `UpgradeData` entry.
- `mapping.csv`: exact source sheet row and column for every selected icon.
- `source/`: original user-supplied sheets retained as the candidate library.

All runtime images use nearest-neighbor filtering. State colors are consistent across UI: burning red, charged/marked yellow, frozen blue, cursed purple, and physical techniques cyan/steel.
