# VSGAME Codex 開発ワークフロー

今後の Codex Session が Context を節約して作業するための運用規約です。
ゲーム仕様ではなく、開発手順だけを定義します。

## 文書の役割

| 情報源 | 役割 | 更新時期 |
|---|---|---|
| `game_specification.md` | 現在採用されている正式なゲーム仕様と実装上の制約 | 実装を変更した同じ Task 内で、関係する章だけ更新 |
| `docs/codex_handoff.md` | 次の Session が再開するための短い現在状態 | 毎 Task の終了時に内容を置き換え、短く維持 |
| `docs/codex_workflow.md` | 安定した Codex 運用規約 | 開発方式を変える場合だけ更新 |
| Code / Scene / Resource / Data / Asset | 実際の実装 | Task に関係する範囲だけを確認し、仕様と照合 |

Handoff へ仕様全文、Code、大量の Test Log をコピーしません。仕様と実装の差を見つけた
場合は、推測で一方を正とせず、関連する依存経路を確認し、採用する結果へ同じ Task 内で
同期します。

## Session 開始時の確認順序

1. `git status --short` で既存の User 変更を把握する。
2. `docs/codex_handoff.md` を読む。
3. 今回の **Scope** と **Out of Scope** を明示する。
4. Task の Keyword を検索し、候補 File を少数へ絞る。
5. `game_specification.md` の一致する章だけを読む。
6. 現在の依存経路を理解するために必要な候補 File だけを読む。
7. 具体的な参照先や失敗した検証が要求した場合だけ、対象 File を追加する。

Keyword の例:

- Element: `element`、`lightning`、`chain`、`damage`、`vfx`
- Equipment: `equipment`、`inventory`、`forge`、`ui`

Repository の一般知識を得る目的だけで、無関係な Map、Forge、Equipment、Enemy、Boss、
UI まで読み込みません。

## Scope 管理

すべての Task は明示した境界から開始します。

```text
Scope: Fire, Ice, Lightning, Light, Dark, Element Damage, Element VFX, Fusion
Out of Scope: Map, Forge, Equipment UI, Enemy Spawn, Boss
```

Out of Scope の System は、必要な依存関係が確認できた場合だけ変更できます。変更は最小限に
し、理由を Handoff に残します。

1 Session は原則として次のような主要 Theme 1つに限定します。

- Element / VFX
- Equipment / UI / Forge
- Map Redesign
- Enemy Density / Elite / Loot Balance
- Final Regression / Polish

## 実装 Phase

大きな Task は、対象を広げすぎない Checkpoint へ分割します。

1. Investigation
2. Core Implementation
3. Integration
4. Regression Test
5. Specification Update
6. Handoff Update

次の Phase が新しい依存先を必要としない限り、Phase の境界で調査範囲を広げません。

## Implemented の完了条件

適用対象となる次の条件を満たして初めて **Implemented** とします。

- 実ゲームの Runtime Entry Point から機能へ到達できる。
- 必要な Script、Scene、Resource、Data、Asset、ID が接続されている。
- 想定した実ゲーム経路で正常動作する。
- 絞った検証と、Task に適した Regression Check が成功する。
- 関係する `game_specification.md` の章が採用した動作を表している。
- `docs/codex_handoff.md` に次の Task に必要な情報だけが残っている。

孤立した Script、Scene、Asset、Effect ID、Data が存在するだけでは完了ではありません。

## File Reading / Tool Call の節約

- File を開く前に File 名と Keyword で検索する。
- 大きな File は全文ではなく該当する行範囲を読む。
- 同じ Session で、変更されていない巨大 File や Log を繰り返し読まない。
- 確定した事実は短く Handoff に要約し、生の出力は貼らない。
- 先に絞った Test を行い、大量の Test Log は失敗箇所だけを読む。
- 会話や Handoff で、確認済みの仕様を長文で再説明しない。

## Task 終了時と Git の安全性

1. 最終差分と Working Tree の状態を確認する。
2. 無関係な既存 User 変更が保持されていることを確認する。
3. 実装変更があった仕様書の該当章だけを更新する。
4. Handoff を、今回の完了内容、重要な決定、残課題、主要変更 File、既知問題、次の
   Task 1つだけに置き換える。
5. 大規模作業は Phase / Task 境界に安全な Checkpoint を設け、User の作業を上書き・破棄
   しない。

次の Session は Handoff、新しい依頼、仕様書の関連章、関連 Code だけから再開します。
過去の Codex 会話履歴は Project の記録として必要としません。
