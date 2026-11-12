# VSGAME 開発ルール（ピボット後）

- 開始時は `git status --short`、次に `game_specification.md` を確認する。現状と新しい方向はそこにだけ書く。
- 実装前に今回の **Scope** と **Out of Scope** を明示する。未定の項目（盤面の中身、攻撃、属性、演出、敵、UI）は勝手に前提にしない。
- `_archive/` はピボット前の退避物。丸ごと戻さない。再利用は必要なファイルだけを元のパスへ戻し、参照を確認する。`_archive/.gdignore` は消さない。
- File、Asset、Data が存在するだけでは完成としない。実ゲームの経路へ接続し、Godotをheadlessで実行して確かめて初めて Implemented とする。
  コードを読んだだけで「確認済み」としない。報告には起動ログのエラー・警告の件数を添える。
- 変更したら `game_specification.md` の該当箇所を更新する。
- 無関係な User 変更を保持する。
