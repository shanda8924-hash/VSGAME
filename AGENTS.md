# VSGAME Codex 開発ルール

- 開始時は `git status --short`、次に `docs/codex_handoff.md` を確認する。
- 実装前に今回の **Scope** と **Out of Scope** を明示する。
- Task の Keyword で先に検索し、`game_specification.md` の該当箇所と最小限の関連
  File だけを読む。
- Task が明示的に必要としない限り、Repository 全体、仕様書全文、巨大な Log を
  読み込まない。
- 1 Session は1つの主要 Theme に限定し、大きな Task は
  `docs/codex_workflow.md` の Phase に分割する。
- File、Asset、Data、Effect ID が存在するだけでは完成としない。実ゲームの経路へ接続し、
  正常動作を検証して初めて Implemented とする。
- Task 終了時は、実装変更に関係する `game_specification.md` の章と、短い現在状態だけを
  記す `docs/codex_handoff.md` を更新する。
- 無関係な User 変更を保持する。詳細ルールは `docs/codex_workflow.md` を参照する。
