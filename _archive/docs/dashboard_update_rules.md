# VSGAME Dashboard 更新ルール

VSGAMEの外部記憶として、実装状態とDashboard表示を一致させる。

## 実装・修正後に行うこと

1. `dashboard/dist/data/roadmap.json`で該当Taskの`status`と`progress`を更新する。
2. 仕様の対象がMAP、Enemy、Boss、Class、Systemなら、対応するJSONも更新する。
3. 新しいBugを確認したら`bugs.json`へ登録する。修正時は原因、修正内容、次の確認を残す。
4. 大きな仕様変更では`decisions.json`へ`date`、`title`、`decision`、`reason`、`impact`を追加する。
5. `project.json`の`updatedAt`を更新する。
6. 全JSONの構文、JavaScript構文、PC / Mobile表示を確認する。

## Progress基準

- 0%: 未着手
- 1〜20%: 方針・設計を整理中
- 40〜70%: 実装中
- 80〜99%: 実装済みでTest中、または一部の実経路が未確認
- 100%: 実ゲーム経路へ接続し、必要なTestが完了

Code、Data、Assetが存在するだけでは100%にしない。

## 公開情報の制限

API Key、Password、Token、Secret、個人情報、PC固有の絶対PathをDataへ入れない。公開して問題ないゲーム仕様、数値、進捗、判断理由だけを記録する。

## Dataの役割

- `project.json`: 表示名、更新日、Status/Priority定義
- `roadmap.json`: Category、Weight、Task、Roadmap
- `maps.json`: MAPごとのTheme、進行、敵、Boss、背景、BGM
- `enemies.json`: 6階級と通常敵Roster
- `bosses.json`: Bossの数値、登場MAP、演出、報酬
- `classes.json`: 現行10職と再編判断
- `systems.json`: 状態異常、Fusion再定義、Skill、Equipment、UI/VFX/Audio、Performance
- `bugs.json`: Known Bugs
- `decisions.json`: 仕様変更と理由
- `relations.json`: System同士の依存関係、要不要の判断区分、影響範囲
- `gallery.json`: 実画面Capture、判断Memo、関連System

実画面を追加・差し替える場合は`dashboard/dist/assets/images/`へ公開用Copyを置き、個人情報やPC固有Pathを含めない。画像だけを置かず、`gallery.json`へ「何が確認できるか」「どの判断に関係するか」を記録する。

## 図鑑画像の更新

- 職業、通常敵、Bossを追加・差し替えた場合は、対応するDataの`image`と`dashboard/dist/assets/portraits/`を同時に更新する。
- 画像は実ゲームが参照するSpriteの代表Frameを使い、元Assetを上書きしない。職業・通常敵・Bossの額縁色と256×256の寸法を維持する。
- 公開前に全`image`参照の存在、画像読込、PC/Mobileの横Scroll、Browser Consoleを確認する。

## 職業再編とBoss転用

- Player職を追加・削減した場合は、`classes.json`の`disposition`、職業画面の集計、Roadmap、Decision Log、相関図を同時に更新する。
- 職業をBossへ転用する場合は、`bossEncounter`で職業とBoss戦を結び、`bosses.json`へ実装状態と未確定値を明記する。未実装のHP・Damage・配置を推測値で確定しない。
- ペアBossは構成員ごとの役割、相互作用、撃破順の意味を記録し、2体で1戦として集計する。
