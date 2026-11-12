# _archive — ピボット前の退避物（2026-11-12）

ゲームのピボットで外したものを、元のフォルダ構成のまま置いてある。削除ではなく退避で、あとで再利用するものを選ぶ。

- `.gdignore` があるので Godot はこのフォルダを読み込まない（`class_name` の衝突やエラーを避けるため）。
- 再利用するときは、必要なファイルだけを元の場所（`res://` 直下の同じパス）へ戻し、参照を確認する。フォルダごと戻さない。
- ピボット直前の完全な状態は git タグ `pre-pivot`（コミット f9ccd55）。そこでは全部が動く。
- 土台側で書き換えたファイルの「元の版」もここに同じパスで入っている：
  `entities/player/player.gd`・`player.tscn`、`entities/entity_base/entity.gd`、`components/{animation,movement,health}_component.gd`、
  `resources/character_data.gd`、`autoload/{data_loader,game_manager}.gd`、`data/characters/*.json`（攻撃パターン・職業技などの項目つき）。
- `.github/workflows/dashboard-pages.yml`（ダッシュボード公開）も退避した。`dashboard/dist` を戻すなら一緒に戻す。
