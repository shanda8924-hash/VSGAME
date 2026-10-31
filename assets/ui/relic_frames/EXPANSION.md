# UI展開用追加素材 — 2026-09-11

内蔵 image_gen で生成。CLI/APIは使用していない。生成原画をこのフォルダへコピーして実UIから参照。

- `equipment_parts.png`: 武器・頭・胴・腕・脚・装飾の6部位。3列×2段の領域参照と描画時の白黒Shaderで使用。装備品の図柄をフィルタへ使い回さない。
- `skull_crest.png`: ボス戦利品の髑髏紋章。黒マットは描画時に除去。
- 既存`ornament_atlas.png`: 太い石枠・細い石枠・見出し札。共通PixelUIStyleとFrameArtへ接続。
- `artifacts/crafted_ui/`: 実画面の報告画像6種。画像生成によるモックではない。

## 部位アイコンの生成プロンプト

Production pixel-art UI icon sprite sheet. Exactly six simple monochrome white/light gray equipment CATEGORY silhouettes on pure solid black background, no text, no labels, no border, no color. Layout exact 3 columns x 2 rows evenly spaced square cells, equal icon scale with large padding. Top row: generic straight sword (weapon category), simple helmet (head), plain torso tunic armor (body). Bottom row: one gauntlet/glove (arms), pair of boots (legs), plain ring with tiny round gem (accessory). Flat bold readable silhouettes with a few black cutouts, no realistic lighting, no ornate gear, no item rarity, clean crisp pixel art intended 32x32 game UI. Each icon completely isolated within its own grid cell, six cells identical size. Deliver square 1024x1024. Background pure RGB black, foreground white and light gray only. User explicitly wants new generated symbols for equipment filters.

## 髑髏紋章の生成プロンプト

Generate production game UI decoration asset, matching dark navy blue stone and finely engraved antique gold 16-bit pixel art fantasy UI. On pure solid BLACK background, one centered horizontal ornamental crest: small golden human SKULL with deep black eye sockets and tiny ruby forehead gem, symmetrical curled acanthus scrolls to each side, delicate pointed ends, engraved gold edging. Crest silhouette like a low wide crown, width 5 times height. Not a banner or panel, just skull crest ornament for placing above a title bar. Skull at center clearly readable at 40 pixels tall. No words, no text, no checkerboard, no white background. Pixel art crisp, warm bronze shadows gold highlights. Ornament occupies central 80% width, central 40% height of wide canvas. User wants skull replacing fleur-de-lis emblem over existing royal navy/gold plaque.

