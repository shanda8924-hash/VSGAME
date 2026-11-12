# 天賦の魔導書

2026-09-11。ユーザー提供の見開き本を参照し、内蔵 image_gen で生成した実ゲーム用背景。

- 本体素材: `open_book.png`（生成原画を無加工で保存）
- 実装: `ui/pause_menu/talent_grimoire.gd`
- 実ゲーム画像: `artifacts/talent_grimoire/implemented.png`
- 羊皮紙の中身は実行時のノードとテキスト。画像には技・数値・文字を焼き込まない。
- 1600×900基準で等比縮小し、ページと操作位置を一致させる。他の図鑑・記録画面にも背景を転用可能。
- T / ゲームパッドBackで開閉、Escでも閉じる。クリック・矢印・WASDで選択。取得は従来のレベルアップ候補から行う。
- 既存の剣士2流派のみ分岐を表示。他職業の未実装分岐は準備中として表示。

## 生成プロンプト（内蔵ツール）

Use case: stylized-concept. Production game UI background asset, landscape 16:9, 1600x900 composition. Reference image is the user's medieval pixel-art open talent grimoire. Reproduce its ornate physical book and candlelit dark blue ruined gothic library mood very faithfully, but REMOVE ALL gameplay content, text, diagrams, nodes, portraits, bars and maps. A huge open aged parchment book occupies x=175..1425 y=90..810 of a 1600x900 canvas, spine exactly x=800. Left blank usable writing area x=270..740 y=190..730, right blank usable writing area x=865..1330 y=190..730. Page edges with thin brown engraved double rules, small geometric rosettes and decorative corners, layered thick worn paper, deep burgundy leather binding, strong gold triangular corner protectors, tiny gold clasp at top of spine. Slim burgundy ribbon bookmarks near outside top edges only with small gold sword and crown emblems. All page centers blank warm light parchment for runtime Japanese text and talent diagram. Behind book shadowy blue-black pixel stone pillars, old shelves, candles and soft small amber flames at far sides. Straight-on perfectly readable open book, symmetrical flat page planes, extremely close style to reference, lovingly crafted crisp 16bit pixel art, no painterly blur, no modern UI, no letters, no placeholders, no glyph text, no HUD. Full opaque image background. This is an actual composited runtime artwork, not a mockup.

