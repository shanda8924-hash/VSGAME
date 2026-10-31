# VSGAME 開発ダッシュボード

`dist/`だけで動作する、依存パッケージ不要の静的Webダッシュボードです。

## 構成

- `dist/index.html`: 画面の土台
- `dist/styles.css`: PC / Tablet / Mobileの表示と世界観
- `dist/app.js`: JSON読込、自動集計、検索、Filter、画面切替
- `dist/data/*.json`: 仕様・進捗・Roster・Bug・Decisionの正本
- `dist/data/relations.json`: 体験・世界・戦闘・実装順の相関図と要不要仕分け
- `dist/data/gallery.json`: 実ゲーム画面、説明、関連System、判断区分
- `dist/assets/images/`: Dashboardで参照する実ゲームCapture

ローカル確認は`dashboard/dist`をWeb ServerのRootとして配信してください。`file://`ではBrowserのJSON読込制限により動作しません。

## 進捗計算

- Category進捗 = Category配下Taskの`progress`単純平均
- 全体進捗 = `Category進捗 × weight`の加重平均
- `progress: 100`は実装とTestが完了したTaskだけに設定

表示を更新するときは、該当する`dist/data/*.json`だけを編集します。HTMLへ進捗値を直接書きません。

## 相関図と実画面

- `相関・仕分け`画面は、1 RunのLoop、MAP/敵/Boss階層、戦闘Build、実装依存関係を表示します。
- 判断区分は`keep`（維持）、`redesign`（再設計）、`remove`（削除・非採用）、`hold`（保留）の4種類です。
- 実画面は装飾ではなく、現在の実装状態と判断理由を確認するEvidenceとして登録します。画像を追加するときはCaptionと関連Systemも同時に更新します。
- 画像Cardは拡大Dialogを持ち、Desktop / Tablet / Mobileで同じ情報へ到達できます。

## 公開

`.github/workflows/dashboard-pages.yml`は`dashboard/dist`をGitHub Pagesへ公開します。RepositoryにRemoteを設定し、GitHub PagesのSourceをGitHub Actionsへ切り替えると利用できます。

## キャラクター・敵・Boss図鑑

- `dist/assets/portraits/classes/`: 現行10職の実ゲームSpriteから作成した図鑑画像
- `dist/assets/portraits/enemies/`: 通常敵22種の図鑑画像
- `dist/assets/portraits/bosses/`: 現行Boss10戦と職業転用Boss3戦の図鑑画像。ペア戦は二人を同じ画像へ配置
- `classes.json`、`enemies.json`、`bosses.json`の`image`が公開用画像を参照します。画像は256×256 PNGで、元SpriteのPixelを保ったまま共通の石板背景と区分色を付けています。

## 職業再編の表示

- 職業画面は旧10職を、正式Player6職とBoss転用4職へ分けて表示します。
- Boss画面は現行10戦に、槍兵、死霊術師、聖堂騎士＋司祭の職業転用3戦を加えます。
- 聖堂騎士＋司祭のCardでは、前衛・主攻撃と後衛・支援の役割、強化・回復の関係を個別に表示します。
- `相関・仕分け`では旧10職からPlayer6職とBoss3戦へ分かれる依存関係を管理します。
