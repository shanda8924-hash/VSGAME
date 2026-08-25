# ゲーム仕様書 v3.0(2026年8月15日時点)

> 本ドキュメントは、これまでの開発で決定した仕様を集約した「現時点の正(せい)」です。
> 過去の `design_proposal_v1.md`(初期設計書)から、プラットフォーム変更(スマホ→Steam)、
> ダンジョン構造の追加、職業システム、ボス戦、アイテムシステムなど、多くの点で
> 内容が更新されています。実装との相違が見つかった場合は、仕様書またはコードの片方を
> 推測で正とせず、関連するCode / Scene / Resource / Data / Assetsを確認したうえで、
> 採用する現行仕様へ両者を同じ作業内で同期します。

---

## 1. 概要

| 項目 | 内容 |
|---|---|
| ジャンル | MAP探索型ローグライト・サバイバー |
| プラットフォーム | **Steam(PC)専用**(スマホ版は当面対象外) |
| 画面 | 横長ワイドスクリーン(既定ウィンドウサイズ1600×900、リサイズ可能。UI一部要素は1920×1080基準で設計されているが解像度非依存で動作する) |
| 操作 | キーボード(WASD/矢印キー)で移動。通常攻撃は自動、Spaceで職業固有アクティブスキル。共通InteractionはE、ゲームパッドX。ゲームパッド移動・UI操作対応 |
| 収益モデル | **買い切り**。広告・リワード広告システムは撤去済み(AdManagerはautoloadから除外) |
| エンジン | Godot 4.7系、GDScript |
| 独自要素 | 合体武器(フュージョン)システム |

## 2. アーキテクチャ方針(変更なし)

- SOLID原則、データ駆動設計(数値=JSON、演出/参照=Resourceのハイブリッド)、
  コンポーネント設計、MVCに近い構成
- `autoload/DataLoader` が `data/` 配下のJSONを読み込み、`resources/*.gd` の
  Resourceクラスへ変換する
- 新しい武器・敵・ボス・アイテム・強化オプションは、JSONファイルの追加だけで
  組み込めるようにする(コード変更不要)

## 3. コアループ

```
ホーム画面(職業選択・恒常強化)
  → MAP 1探索(自動攻撃、自然湧き、Elite、配置宝箱/祭壇)
       → 敵撃破XPでLevel Up → Attribute 3択
       → 宝箱をE/Xで開封 → 装備/回復/Skill/Attribute報酬
       → 撃破条件達成後、最深部Boss領域をE/Xで開始（長期探索時だけ救済解放）
       → Boss撃破 → 確定装備+Boss宝箱Skill → MAP 2
  → MAP 2 → MAP 3 Final Boss
  → RUN CLEARリザルト(Retry / Title)
  → 途中死亡 → RUN OVERリザルト
```

現行通常ゲームは上記の3 MAP探索制を使用する。旧36 ROOMのScene/Controller/Data/Testは削除せず、
Developer Test Lab、回帰テスト、`codex/room-system-backup-20260825`からの復旧用に保持する。
通常経路では`RoomRunController.begin_run()`、ROOM CLEAR、ROOM選択、毎ROOM報酬を呼ばない。

## 4. ダンジョン生成

- 通常ゲームは`DungeonGenerator`と既存Dungeon Assetを再利用する中規模手続きMAPを3枚使用する。
  MAP別設定は`data/maps/exploration_run.json`。寸法78/86/94、部屋数10/11/12、Elite部屋1/2/2。
- MAP間だけ`StageEnvironment.build_dungeon_async()`でTile/装飾を行Batch敷設する。全画面黒Fadeは使わず、
  濃紺Pixel遷移表示中に旧MAP Actor/Projectile/VFX/Lootを退役させる。
- ROOM用`RoomTemplateFactory`は通常経路から外し、Test/復旧用に保持する。

- `systems/dungeon_generator.gd` が、ラン開始ごとに固定サイズ(目安100×100マス)の
  マップを手続き生成する。生成結果は「床マス」「壁マス」のグリッド
- 部屋は8×8〜14×14マス程度、通路は最低3〜4マス幅(1マスの細い迷路にしない。
  理由: このゲームの核である「大量の敵に囲まれて薙ぎ払う」爽快感を壁で殺さないため)
- 外周は必ず壁で囲む。壁には実際の当たり判定があり、プレイヤー・敵は通行できない
- 壁の見た目: 目地のはっきりした暗色レンガをベースに、旗・檻・アーチ型の門・松明を
  低頻度で装飾として混ぜる。壁の下端には苔の縁取り、上端には明るい縁取りを入れる
- 出入り口(部屋と通路の接続部)には、柱を左右対称に配置する。柱は壁の直線部分には
  使わない(出入り口専用の装飾とする)
- 床タイルは「石畳・ひび割れ石畳」など、地面として自然に見えるものだけを2〜4種類
  使う(木箱・樽・檻などの物体的な絵柄は床タイル候補から除外する)
- お宝コーナー(樽・木箱を2〜4個まとめた装飾)は、一部の部屋の隅にのみ配置する
- ダンジョン範囲外は完全な黒背景(void)とする
- WaveSpawnerは、生成された床マスの中からのみ、かつプレイヤーから一定の
  最低距離(200〜250px程度)以上離れた位置にのみ敵を出現させる
- Camera2Dの移動範囲は、生成されたマップの外周に制限する(limit設定)

## 5. 精鋭部屋(Elite Room)

- MAPごとに既存`EliteRoomManager`を再設定し、配置Elite部屋と巡回Eliteを通常探索へ統合する。
  MAP経路のElite報酬は経験値+確定地面装備で、旧ROOM用属性Modal/メタ通貨は呼ばない。

- ダンジョン生成時、スタート地点から離れた部屋のうち1〜2部屋を精鋭部屋として指定する
- プレイヤーが入室しても出入り口はふさがれず、通常マップを自由に移動・逃走できる。
  通常の雑魚湧き停止、精鋭の生存管理、全滅判定、報酬処理は従来どおり維持する
- Elite Orc, Werebear, Armored Skeleton, Greatsword Skeletonの中からランダムに
  1〜2体、通常のステータスから1.8〜2.2倍に強化した個体が出現する
- 表示スケールは通常個体よりやや大きく(1.6倍程度)し、視覚的に区別できるようにする
- 各精鋭には進行時間に応じて1〜3個の特殊属性をランダム付与し、頭上へ属性名を表示する
- MAP通常進行では精鋭ごとの高XP+確定地面装備を報酬にし、戦闘を止める属性4択/メタ通貨Modalは出さない。
  旧ROOM/Test互換経路の報酬だけは回帰用に維持する(詳細は23章)。

## 6. レベルアップ(Attribute 3択+小回復)

- MAP通常進行では経験値が一定量たまると、Element/Attribute/Masteryの3択から1つを選ぶ。
  SkillはLevel Upへ混ぜず、宝箱/Boss宝箱だけから取得する。
- 欠片は `data/weapons/*.json` の `required_fragment_ids` と一致すると自動で
  武器に合成される(固定レシピ表。現状15種類以上。詳細は15章)
- MAP Level Up時は最大HPの12%だけ回復する。全回復は旧ROOM/Test互換経路だけに残す。
- レベルアップとボス撃破アイテム選択がほぼ同時に発生した場合、両方のUIを
  同時表示せず、片方が閉じてからもう片方を表示する「キュー」形式にする
  (`active_modal_count` による一時停止管理、詳細は9章)
- Level Up・ボスItem・属性欠片の選択UIは、表示時に先頭の選択肢へKeyboard/
  Gamepad Focusを置く。Focus枠を通常枠より太く明るく表示し、Mouseだけでなく
  `ui_*`移動+`ui_accept`でも選択を開始できる

## 7. ボス

- 現行通常ゲームは各MAPの累計撃破数を満たすと最深部Boss領域を解放し、E/Xで既存Bossを1体生成する。
  MAP1/2/3の固定撃破条件は420/650/900体。固定Timer待ちにはせず、極端に弱いBuildの詰み防止だけ
  15/16/17分で救済解放する。いずれもBoss Areaへの到達+Interactが必要で、Player火力追従は行わない。
  旧ROOM 4の倍数EncounterとDeveloper Test Lab用明示Spawn APIは維持する。
- `data/bosses/` に10体登録済み: Black Knight_A/B/C, Demon_A〜E, Flame Golem, Minotaur
- ROOM 4から順にBlack Knight_A、Minotaur、Black Knight_B、Demon_B、Black Knight_C、
  Demon_D、Demon_A、Demon_C/Eのどちらか、ROOM 36はFlame Golem。同一Runの9戦で重複させない。
- HP / Damage / 通常攻撃間隔 / 固有攻撃間隔 / 状態異常時間 / 召喚敵倍率は
  `data/rooms/room_mvp.json/boss_encounters`のROOM別固定値から設定する。Player火力追従は行わない。
- 表示スケール: 通常敵より明確に大きい(調整を重ねた現在の実装値を正とする)。
  赤いアウトラインで縁取りし、画面上部に日本語の「ボス / 最終ボス」名と専用HPバーを表示する
- 出現時演出: 操作を止めず、既存HUD中央へ「ボス出現 / 最終ボス出現」と名前を短時間表示する。
  Spawn Flashと軽いHit Stopは維持し、全画面暗転やCutsceneは使用しない
- **固有攻撃パターン**(実装済み): `attack_pattern_id` によりボスごとに
  charge(突進)/summon(雑魚召喚)/nova(全方位弾)/slam(範囲攻撃予兆+ダメージ)
  のいずれかの挙動を持たせる。通常の追跡移動に加えて、一定間隔でこの固有攻撃を発動する
  (`systems/boss_ai/`にStrategyパターンで実装)
  - **nova(全方位弾)のダメージ調整**: 弾1発あたりのダメージは、ボスの通常接触
    ダメージ×`damage_multiplier`(既定0.4)。全弾がボス自身の位置から発射される
    ため、プレイヤーがボスに近いと複数発がほぼ同時に命中し得るが、9章の
    HealthComponentダメージ上限キャップと合わせて、1回の弾幕を受けても即死しない
    水準に調整済み
  - novaはPlayerと同じProjectile Sceneを再利用するが、`uses_player_element_vfx=false`・
    `applies_player_elements=false`の敵弾として生成する。PlayerがFire/Lightning等を
    保持中でも現在属性の弾体へ置換せず、紫紅色のArrow+GlowでPlayer弾と区別する
- **近接職の攻撃機会**: 固有攻撃は「追跡停止→床表示または色変化による予兆→攻撃→
  1.25〜1.5秒程度の行動後硬直」を基本とする。プレイヤーは予兆を見て回避し、攻撃後の
  硬直中に接近して近接通常攻撃を差し込める。固有攻撃中と後硬直中、ボスは通常追跡を
  行わない。chargeは予告した直線を突進し、slamは予告円、novaはボス中心の予告円、
  summonは召喚範囲の予告円を表示する
- **攻撃力調整(v1.2)**: ボスごとの`contact_damage`を当時の従来値の約88%へ変更した。
  この値を通常攻撃・charge・slam・novaが共通の基礎ダメージとして使用するため、
  各攻撃固有の`damage_multiplier`差、予兆、方向固定、攻撃後硬直は維持される。ボスHPは変更しない
- **共通基礎倍率**: `data/balance/boss_scaling.json`の共通倍率を
  JSON読込時に全BossDataへ適用する。現在値はHP×1.5、攻撃力×1.25、移動速度×1.10。
  ROOM別Boss倍率はこの読込後の値へ掛ける。ROOM 4=HP×1.15からROOM 36=×20.00まで固定曲線で上げる。
  ROOM Bossの出現距離はPlayerから180〜320pxの床マスへ固定し、極端な至近/遠距離による戦闘時間差を抑える。
- ROOM BossはStatusを完全無効にしない。Slow/Freeze/StunのDurationはROOM進行に応じ45%から18%へ短縮する。
  Burn等のDamage Buildは機能する。通常Hitは既存の小Flash/Squashだけで行動を止めない
- MAP Boss撃破後は確定地面装備+Boss宝箱を生成し、完成済みSkill 3択の確定後に次MAPへ進む。
  MAP3 Boss宝箱完了でRUN CLEAR。旧ROOM報酬順序は回帰経路だけに残す。
  旧メタ通貨+Item選択報酬はROOM Encounter経路では呼ばず、旧明示Spawn互換経路だけに残す
- 死亡時はBoss Nova弾、警告Area、召喚敵、攻撃Componentを退役し、ScreenEffectsのHit Stop / Shake Offsetを
  基準状態へ復元する。遅延Timer/Tweenが残っても破棄済みBossへDamageや画面状態を再適用しない

## 8. アイテムシステム(ボス撃破報酬)

- 各MAPへ通常/希少宝箱を合計4個配置する。Playerが105pxのInteraction Rangeへ入った時だけ
  `【E】宝箱を開く`を表示し、共通`interact` Action（E / gamepad X）で一度だけ開く。
- 通常宝箱の中身はMAP別固定Reward Slotから装備/回復/Skill/Attributeを割り当て、毎回Skillにはしない。
  3MAP+Boss宝箱で完成済みSkill取得機会は合計7回。装備/回復はUI直付与せず実物を床へ生成する。
- 完成済みスキルは内部ID・表示Key・日本語文言を分離し、通常プレイヤーにはTRIGGER/SKILL/MODIFIERを露出しない。
  最大6種類、同一スキル再取得はLv.UP、各スキル最大Lv3。同一Run内だけ維持し、新Runで初期化する。
- 既存`ItemData`/`PlayerUpgradesComponent`報酬と旧Concept Parts/BoardはBoss/Test Lab互換として保持する。

- `data/items/` にステータス系(vitality_ring等)と特別効果系
  (boss_slayer_mark, regenerating_heart, undying_soul, piercing_will,
  twin_fragment, thorns_armor, vampiric_edge, desperate_speed)の両方を用意
- `ItemData`3択はDeveloper Test Lab / 旧明示Boss Spawn互換経路だけで提示する。
  通常ROOM Bossはこの経路を呼ばず、属性3択とBoss宝箱の完成済みSkill 3択を使用する
- 選択肢には、アイテム名+効果の説明文(description)を表示する
- 戦利品選択カードは1920×1080基準で、アイテム名22px、説明文18px、
  カード最小サイズ280×132pxとする。説明文は中央揃え・自動折り返しで読みやすさを優先する
- 獲得したアイテムは、画面上部(または右上)に戦利品トレイとしてアイコン表示する。
  同じアイテムを複数回獲得した場合は「×2」等の重ね取得数を表示し、
  種類数が5〜6個を超えたら省略して「+N」のバッジで表示する

## 9. システム基盤の注意点

- **モーダルの二重オープン対策**: レベルアップ選択・アイテム選択など、
  ゲームを一時停止させるUIが複数同時に開閉しても、`get_tree().paused` が
  正しく維持されるよう、開いているモーダル数を数える仕組み
  (`active_modal_count`、0の時だけpause解除)を用いる
- `GameManager.start_run()`は前RunのResult/Hit Stop/選択UIが途中でも、
  `SceneTree.paused=false`、`Engine.time_scale=1.0`、Modal count/queue初期化から開始する。
  ResultのRetryを含むScene reloadで前Runの停止状態を持ち越さない
- 自動攻撃・Homing・召喚味方・疑似ChainのTargetingは、Nodeが有効でも
  `HealthComponent.current_hp <= 0`の死亡演出中対象を候補から除外する
- ボス・精鋭部屋・通常敵の全データはJSONファイルへの追加だけで増減できる
- **トップダウン物理**: PlayerとEnemyBasicの`CharacterBody2D.motion_mode`は
  `FLOATING`を使用する。Grounded時の床・プラットフォーム追従によって、斜め接触した敵に
  プレイヤーが運ばれる挙動を発生させない。壁・敵本体との通常の衝突判定は維持する
- **被ダメージ上限キャップ(即死防止の安全策)**: `HealthComponent.apply_damage()`は、
  1回の被弾(同一物理フレーム内に複数回命中した場合はその合算)で
  最大HPの40%(`MAX_DAMAGE_PER_HIT_RATIO`)を超えるダメージを与えない。
  ただし、この割合キャップだけを適用すると体力の低い雑魚敵が「一撃で倒せるはず
  の攻撃」でも小刻みにしか減らなくなってしまうため、下限として実ダメージ30
  (`MIN_DAMAGE_CAP_FLOOR`)未満のヒットは常にそのまま通す(=雑魚を一撃で
  薙ぎ払う爽快感には影響しない)。プレイヤー・ボスを含む全HealthComponentに
  共通で適用される、弾幕系の攻撃(nova等)が同時多発ヒットして合算即死する
  事故を防ぐための保険的な安全策

## 10. 演出(VFX)

- 大量撃破時の一掃演出(GPUParticles2Dバースト+画面シェイク+ヒットストップ)
- ダメージ数値のポップアップ表示(クリティカル時は赤・大きめ)、設定でON/OFF可能
- Archer/Wizard等の職業Projectileは`assets/sprites/projectile/Arrow01(32x32).png`を使用し、
  職業・武器本来のThemeによる控えめなGlowを纏う。Element Stackの取得・Lv変更では
  Projectileの生成・置換を行わない。新Element Fusionも専用Projectileを必要とするTrait以外は
  Projectileを使わず、Script描画の専用現象VFXで表現する
- 武器の属性(炎/氷/雷)ごとに着弾エフェクトの色・簡易パーティクルを変える
  (専用の派手な演出は保留、まずは色分けレベルの差別化を安定動作させる)
- **キャラクターの向き**: プレイヤー・敵(ボスを含む全EnemyBasic系)ともに、
  `AnimationComponent`が移動方向の左右成分に応じて`AnimatedSprite2D.flip_h`を
  更新する(左移動でtrue、右移動でfalse)。上下方向のみの移動や停止中は直前の
  左右の向きを維持する。攻撃/被弾アニメーション再生中(ロック中)でも向きの
  更新自体は止めない(攻撃頻度が高いと向きがほぼ更新されなくなる不具合が
  あったため、向きの更新をアニメーションロックの判定より前に行うよう修正済み)
- **全画面フラッシュ演出の禁止(安全面の方針、2026年8月)**: 攻撃ヒット時の
  演出(`EffectThemeManager`)は、画面全体を光らせる`ScreenEffects.flash()`を
  一切呼び出さない。以前は光属性(is_beam)の強化ヒット時に全画面フラッシュを
  発火しており、攻撃速度が上がるほど点滅頻度が上がって不快感・光過敏性発作の
  リスクにつながっていたため廃止した。以降、単体属性・合成属性を問わず、
  武器ヒット時の演出は着弾位置周辺の局所効果(貫通ビームのLine2D・雷の連鎖
  Line2D・パーティクル等)のみに限定する。ボス撃破時のフラッシュ(赤)・
  精鋭部屋撃破時のフラッシュ(金)・武器合成時のフラッシュ(既存演出、通常
  合成は柔らかい金色、超融合は強め+ヒットストップ+カットイン、15.3参照)は、
  攻撃ヒットのたびに連続発火するものではない一度きりの節目演出のため対象外
  (このガイドラインの対象は「攻撃速度に連動して繰り返し光る」演出のみ)
- 節目用のFlash/Cut-inとShake TweenはPauseおよび`Engine.time_scale`を無視して
  実時間で完走する。ボス撃破と同時に報酬ModalがPauseしても、最前面ColorRectを
  停止・残留させず、規定時間後にCanvasLayerごと解放する

## 11. プレイヤー・職業システム

- `data/characters/` に10職業登録: Soldier, Swordsman, Knight, Knight Templar,
  Armored Axeman, Lancer, Archer, Wizard, Priest, Necromancer
- ホーム画面で、解放済みの職業から1つ選んでラン開始する
- Soldierはデフォルトで解放済み。他はメタ通貨で解放(`unlock_cost`)
- 選択した職業に応じて、見た目(AnimatedSprite2D)とステータス(max_hp, move_speed)が
  切り替わる
- 各職業は、欠片合成武器(15章)とは独立した「職業固有の自動攻撃パターン」と
  「固有パッシブ」を持つ(2026年8月追加、詳細は19章)
- 各職業の`preferred_element`は既存Data互換用に保持する。現在のBoss 4択候補は
  2属性Buildの選択自由度を優先して等確率で構成し、この値による重み付けは行わない

## 12. 敵の出現バランス

- `data/enemies/` の各JSONに `min_elapsed_seconds` を設定し、経過時間に応じて
  弱い敵→中堅→強めの敵、と段階的に出現の幅が広がるようにする
- 目安: 0秒〜(Slime, Bat, Skeleton, Orc等)/ 90秒〜(Armored Orc, Skeleton Archer等)/
  180秒〜(Elite Orc, Werebear, Werewolf等)

### 12.1 Heart回復ドロップ

- 通常雑魚死亡時5%、Elite死亡時10%でHeartを地面へ生成する。Bossは対象外
- 確率・回復率・寿命は`data/pickups/heart.json`で調整する
- Heartは接触で自動取得し、最大HPの15%を回復する。最大HPを超えて回復しない
- 取得時は緑色の`+N HP`表示と取得SEを再生し、Heartを消去する
- Heartは赤い簡易ハート描画と控えめな浮遊・明滅を持ち、25秒後に自動消滅する

## 13. フォルダ構成・データ一覧(現状)

```
data/
  characters/   … 10職業
  enemies/      … 通常敵(段階的出現)
  bosses/       … 10体
  weapons/      … 完成武器+固定合成レシピ(15種類以上、詳細は15章)
  fragments/    … 属性の欠片(fire/ice/lightning/light/dark、詳細は15章)
  items/        … ボス撃破報酬アイテム
  upgrades/     … レベルアップ通常強化オプション(16種類、詳細は15章)
  difficulty/   … 難易度カーブ(経過時間ベース)
  pickups/      … フィールド取得物のドロップ率・効果量
  balance/      … ボス共通倍率等のバランス設定
  elite_affixes/ … 精鋭特殊属性の効果・付与数設定
  equipment/    … 装備テンプレート・レアリティ・ドロップテーブル
```

## 14. 今後の未実装/保留事項(参考)

- 実績、デイリーミッション、ランキング、クラウドセーブ(将来拡張予定、EventBus購読で
  既存コードに手を入れず追加できる設計を維持)
- ラン内ショップ、メタ通貨の複数化(検討中、優先度は中)
- ボス候補の温存素材(Blood Monster, Demoness等、通常敵に追加済みのものを除く)

## 15. 合体武器(フュージョン)システム詳細

Steamヒット化レビューを踏まえ、独自要素である合体武器システムを強化した
(2026年8月)。

> 現在の正式なラン内属性成長は29章のElement Fusionである。以下の完成武器Dataは
> 既存Asset/互換用に残すが、属性欠片だけの2属性レシピを`FusionSystem`から自動生成しない。

### 15.1 属性(5種類)

`data/fragments/` に5属性: fire(炎)/ice(氷)/lightning(雷)/light(光)/dark(闇)。
各属性は `effects/themes/*.tres`(fire.tres/ice.tres/lightning.tres/light.tres/
dark.tres)に対応する単体演出テーマを持つ。

### 15.2 合成レシピ(15種類以上)

`data/weapons/` に、5属性から選べる組み合わせのレシピを用意している。

- **2属性(通常合成、10種類)**: 5属性から選べる2属性の組み合わせを全て網羅
  (steam_burst_weapon(fire+ice)・thunder_flame_weapon(fire+lightning)は既存の
  まま変更なし。新規8種: holy_flame(fire+light)・hellfire(fire+dark)・
  frost_thunder(ice+lightning)・holy_frost(ice+light)・shadow_frost(ice+dark)・
  holy_thunder(lightning+light)・shadow_thunder(lightning+dark)・
  purity_corruption「浄化と侵蝕の剣」(light+dark))
- **3属性(超融合、3種類)**: elemental_triad「三大元素の剣」(fire+ice+lightning)・
  trinity_flame「光闇業炎の大剣」(fire+light+dark)・lunar_frost「月光氷刃の剣」
  (ice+light+dark)。通常合成より高威力(base_damage 45〜58程度)
- **4〜5属性(超融合の上位、ボーナス枠、2種類)**: tetra_elemental「四大天啓剣」
  (fire+ice+lightning+light)・pentaelemental「五行天魔剣」(全5属性、最強の
  到達点武器)。base_damage 70〜95程度、crit_chance/crit_multiplierも通常より高い
- 各レシピの`vfx_theme_id`には対応する`combo_ids`付き`EffectThemeData`を用意して
  おり、`EffectThemeManager`が構成属性ぶんの着弾演出をまとめて再生する

### 15.3 合成演出のランク分け

`systems/fusion_system.gd`が、消費した属性数(`required_fragment_ids.size()`)で
演出をランク分けする(`SUPER_FUSION_MIN_FRAGMENT_COUNT = 3`)。

- **通常合成(2属性)**: 既存の柔らかい画面フラッシュのみ(`ScreenEffects.flash()`)
- **超融合(3属性以上)**: 通常より強い画面フラッシュ+0.3秒のヒットストップ
  (`ScreenEffects.hit_stop()`)+武器名を画面中央へ大きくカットイン風に表示する
  専用演出(`ScreenEffects.weapon_cut_in()`)を重ねる

### 15.4 強化オプション(近接/遠距離/共通カテゴリ、トレードオフ対応)

`data/upgrades/`は共通・遠距離向け12種類に近接専用4種類を加えた構成。`resources/upgrade_data.gd`に
`downside_type`/`downside_value`を追加し、`PlayerUpgradesComponent`は
主効果(`effect_type`/`value`)と代償(`downside_type`/`downside_value`)を
同じ汎用ディスパッチャ(`_apply_effect()`)で処理する(代償は主効果と同じ
語彙をマイナス方向に適用するだけ)。

- **純粋な強化(6種類、重ね掛け可能)**: damage_up・multishot_chance_up・
  crit_rate_up・homing_upgrade(既存4種、変更なし)+attack_speed_up・
  vitality_boost(新規2種)
- **トレードオフ付き(6種類、Brotato的な代償あり)**: reckless_power(攻撃力+25%/
  移動速度-5%)・rapid_barrage(攻撃間隔-15%/射程-10%)・glass_cannon(会心率+15%/
  被ダメージ+10%)・long_range_focus(射程+20%/攻撃間隔+8%)・berserker_instinct
  (攻撃力+20%/被ダメージ+15%)・swift_striker(移動速度+15%/攻撃力-10%)
- 射程のトレードオフを実際に機能させるため、`WeaponInstance.tick()`に
  実効射程(`WeaponData.attack_range × attack_range_multiplier`)による
  射程外判定を追加した(従来は`attack_range`フィールドが読み込まれるのみで
  実際の攻撃判定には使われていなかった)
- 選択UI(`LevelUpSelect`)はトレードオフ付きの選択肢を、アイテム選択画面と
  同様にボタン内へ名前+説明文の2行で表示する(代償の内容が一目で分かるように)

- 各強化は`category`に`melee`/`ranged`/`common`を持つ。近接職(Soldier、Swordsman、
  Knight、Knight Templar、Armored Axeman、Lancer)には`melee`と`common`だけを提示し、
  Projectile数・矢の誘導など`ranged`専用候補は提示しない。その他の職業には
  `ranged`と`common`を提示する
- 近接専用の重ね掛け可能候補は以下の4種:
  - POWER / 剛力: 近接通常攻撃ダメージ+15%
  - RAPID STRIKE / 疾風: 近接通常攻撃速度+12%。クールダウン・攻撃アニメーション・
    HitBox発生タイミングを同じ倍率で同期する
  - WIDE SWING / 旋風: 近接通常攻撃範囲+15%。扇形は半径と角度、槍は長さと幅を拡張する
  - BLOOD THIRST / 吸血: 近接攻撃の与ダメージ1.5%を回復する。1ヒット最大3HPとし、
    回復率と上限は該当JSONの`value`/`effect_params.max_heal_per_hit`から調整可能

### 15.5 属性欠片の入手経路

- 通常敵撃破・通常レベルアップからは欠片を入手しない
- 精鋭部屋クリア時に現在Build対応の属性/研鑽4択を表示し、1個を選択する
- ROOM 4〜32 Boss撃破時は通常ROOMと同じElement Build報酬3択から1つ取得し、その後Boss宝箱へ進む。
  ROOM 36 Final Bossは報酬を挟まずRUN CLEARへ進む。3択へ絞る際は取得可能カードを先頭へ置き、
  MAXカードだけが表示されて進行不能にならないようにする。旧Item 3択→Element 4択はTest Lab互換経路だけに残す
- 通常Runの3択は`ElementRewardSystem`が構成し、属性カードだけを`GameManager.add_fragment()`へ渡す
- `CharacterData.preferred_element`は互換フィールドとして保持するが、現在の抽選では使用しない

## 16. 表示品質(テクスチャフィルタ・キャラクタースケール)

2026年8月、「キャラクターのスプライトが背景タイルに比べて画質が甘く見える」
という指摘を受けて対応した(実際にレンダリングした画面をスクリーンショットで
確認済み)。

### 16.1 テクスチャのにじみ対策(根本原因)

- 原因: プロジェクト全体のデフォルトテクスチャフィルタが未設定のままエンジン既定の
  Linear(線形補間)になっており、拡大表示されるプレイヤー/敵/ボスのドット絵だけが
  にじんで見えていた(TileMapLayerの床・壁は等倍(scale=1.0)で描画されるため、
  Linearでもにじみが目立たなかった)
- 対応: `project.godot` の `[rendering]` セクションに
  `textures/canvas_textures/default_texture_filter=0`(0=Nearest)を追加し、
  プロジェクト全体のデフォルトをNearest(ニアレストネイバー)に変更した。
  個々のシーン/ノードごとの`texture_filter`上書きは不要

### 16.2 キャラクター表示スケールの底上げ(1.25倍基準)

- Player: `entities/player/player.tscn` の `AnimatedSprite2D.scale` を
  1.2→1.5、当たり判定(体の`CircleShape2D.radius`を16→20、
  `HurtboxComponent`の`RectangleShape2D.size`を32×32→40×40)も
  同じ倍率(×1.25)で同期して拡大した
- 通常敵: `entities/enemies/enemy_basic.gd` の `visual_scale_multiplier` の
  既定値を1.0→1.25に変更。この1値の変更だけで、`AnimatedSprite2D.scale`と
  当たり判定3種(本体`CollisionShape2D`・`HurtboxComponent`・`ContactHitbox`)が
  連動して拡大される(既存の`_scale_collision_shapes()`ロジックをそのまま利用)
- 精鋭部屋の敵: `systems/elite_room_manager.gd` の `elite_visual_scale` を
  1.3→1.6に変更(5章参照、通常敵の1.25倍基準よりさらに一回り大きく)
- ボス: `data/bosses/*.json` の `visual_scale` を、各体の相対的な大小関係を
  保ったまま一律×1.25した(Black Knight_A 1.08→1.35、B 1.12→1.40、
  C 1.15→1.44、Demon_A 1.04→1.30、B 1.08→1.35、C 1.12→1.40、
  D 1.15→1.44、E 1.19→1.49、Flame Golem 1.3→1.63、Minotaur 1.12→1.40)。
  `resources/boss_data.gd` の既定値(JSON側で`visual_scale`省略時のみ使用)も
  1.08→1.35に合わせて更新した
- いずれの倍率変更も、見た目のスケールと当たり判定(移動用コリジョン・被弾判定・
  接触ダメージ判定)を必ず同じ倍率で連動させており、見た目と判定のズレは発生しない

## 17. 所持武器の確認UI(HUDトレイ・ポーズメニュー)

2026年8月、Vampire Survivors/Brotato的に現在の武器を常時確認できるUIを追加した。

### 17.1 HUD所持武器トレイ

- `ui/hud/hud.tscn`の`MarginContainer/VBoxContainer`に、HPバーの直下・欠片行
  (`FragmentRow`)/戦利品行(`ItemRow`)とは別行の`WeaponRow`を追加し、画面左上に
  現在`WeaponManagerComponent`が保持する完成武器を常時一覧表示する
- 武器アイコンはテクスチャ未用意のため、既存の欠片/戦利品トレイと同じ方針で
  テキスト略称(表示名の先頭2文字)を暫定表示する
- マウスホバーで武器名・攻撃力・攻撃間隔・属性(`vfx_theme_id`から
  `EffectThemeData.display_name`を解決)・効果説明(`WeaponData.description`)を
  ツールチップ表示する
- 武器合成(`EventBus.weapon_fused`)のたびにトレイを再構築し、新しく合成された
  武器を反映する

### 17.2 ポーズメニュー(所持武器一覧)

- `ui/pause_menu/pause_menu.tscn`を新設。Escキー(`ui_cancel`)で開閉する
  簡易ポーズメニューで、所持武器をアイコンだけでなく、武器名・攻撃力・攻撃間隔・
  属性・効果説明をリスト形式で確認できる
- LevelUpSelect/ItemSelectと同じ`GameManager.active_modal_count`経由の一時停止に
  乗る。ただし他の選択待ちモーダルが既に開いている間はEscを押しても割り込んで
  開かない(選択を横取りしないため)。ラン中(`RunState.PLAYING`)のみ開ける
- `resources/weapon_data.gd`に`description`フィールドを追加し、
  `data/weapons/`全16ファイルに効果説明文を追加した(`ItemData.description`と
  同じ「JSONに用意されている前提、無い場合のみ簡易説明を自動生成」という
  ItemSelectの方針とは異なり、武器は全件に明示的なdescriptionを用意した)

## 18. サウンド(SE/BGM)

2026年8月、`assets/audio/se/`(SE 10種類)・`assets/audio/bgm/`(BGM 3種類、
いずれも仮の.wav)を追加し、`autoload/audio_manager.gd`から再生できるようにした。

### 18.1 読み込み方式

`AudioManager._ready()`が`assets/audio/se/`・`assets/audio/bgm/`をフォルダ走査し、
ファイル名(拡張子なし)をそのままサウンドIDとして`sfx_table`/`bgm_table`に登録する
(`DataLoader`のJSONフォルダ走査と同じ考え方。新しい音声ファイルを置くだけで
コード変更なしに使えるようにするため)。BGMは`AudioStreamPlayer.finished`シグナルを
使って自前でループさせる(素材側のループ設定に依存しない)。

### 18.2 SE一覧とトリガー箇所

| ID | トリガー | 実装箇所 |
|---|---|---|
| ui_click | ボタン全般のpressedシグナル | title.gd/home.gd/result_screen.gd/level_up_select.gd/item_select.gd |
| attack_shoot | 武器発射時 | `WeaponManagerComponent.spawn_projectile()` |
| hit_impact | 敵にダメージが入った瞬間(enemiesグループの被弾のみ) | `HurtboxComponent._on_area_entered()` |
| player_hurt | `EventBus.player_damaged`発火時 | `AudioManager`が購読(発火元は`scenes/game.gd`) |
| item_pickup | 欠片取得・アイテム取得時 | `EventBus.fragment_collected`/`item_acquired`を`AudioManager`が購読 |
| level_up | `EventBus.player_leveled_up`発火時 | `AudioManager`が購読 |
| fusion_success | Element Fusion成立時 | `AttackVFXManager`が`element_fusion_formed`を購読 |
| boss_appear | ボス出現時(`EventBus.boss_fight_started`) | `AudioManager`が購読 |
| enemy_death | `EventBus.enemy_died`発火時 | `AudioManager`が購読 |
| player_death | プレイヤー死亡時(`GameManager.end_run()`内で発火する`EventBus.run_ended`) | `AudioManager`が購読 |

`EventBus.player_damaged`は本機能追加まで宣言のみで未発火だったため、
`scenes/game.gd`の`_on_player_damaged()`(既存のHUD更新箇所)から実際に
発火するよう合わせて修正した。

### 18.3 BGM一覧と状態遷移

- `home_theme`: ホーム画面(`ui/home/home.gd`)表示中にループ再生
- `dungeon_explore`: `EventBus.run_started`(ラン開始)発火時に再生開始し、
  ダンジョン探索中はループ再生
- `boss_battle`: `EventBus.boss_fight_started`発火時に`dungeon_explore`から切替。
  `EventBus.boss_fight_ended`(ボス撃破)発火時に`dungeon_explore`へ復帰
- `AudioManager.play_bgm(id)`は同一IDを再生中の場合は何もしない(頭出しし直して
  音が途切れることがないようにするため)
- `default_bus_layout.tres`はMaster/Music/SFXの3 Busを定義する。Pause MenuのAudio Tabから
  Music/SFXを個別変更でき、`SaveManager`の`music_volume`/`sfx_volume`へ保存して次回起動時に再適用する。
- `EventBus.run_ended`でBGMを停止し、Game Scene終了時はBGM/SEを停止してStream参照を外す。
  停止済みAudioStreamPlayerは空のPlayerへ入れ替え、Dummy audio driverを使うHeadless
  Harnessを含めてPlayback Resourceを次Runへ残さない

## 19. 職業ごとの自動攻撃パターンとパッシブ

2026年8月、職業選択の意味を明確にするため、10職業それぞれに固有の自動攻撃
パターンと固有パッシブを追加した。現在はSoldierを含む全職業が固有の自動攻撃を持ち、
`starter_sword`を自動装備せず、職業固有の攻撃パターンが最初から唯一の見た目の
主力アクションになる(初回実装時、全職業に`starter_sword`を残したまま職業攻撃
パターンを"裏で並行動作"させたところ、矢の発射が常に視覚的に優勢で職業の違いが
実プレイで体感できないという不具合が見つかったため、2026年8月中に修正した。
詳細は19.7参照)。旧欠片合成武器Data/Asset(15章)は互換資料として保持するが、通常ROOM Runでは
旧`FusionSystem`による完成武器の自動生成・自動発射を行わない。正式なラン内成長は29章の
Element Stack→2属性Lv3→Element Fusionであり、職業固有攻撃のHitへGameplay Traitを重ねる。

### 19.1 アーキテクチャ

- `systems/attack_patterns/`に、`systems/boss_ai/`(ボス固有攻撃)・
  `components/ai/`(敵AI)と同じStrategyパターンで実装。基底クラス
  `AttackPatternBase`(`execute()`をサブクラスがオーバーライド)を、
  `WeaponManagerComponent`が`CharacterData.attack_pattern_id`に応じて動的に
  1つ生成し、`character_data.attack_interval`(強化オプション反映済み)ごとに
  `execute()`を呼び出す
- ダメージ計算(会心判定込み)・射程計算・命中判定(円範囲の物理クエリ・扇状の
  角度フィルタ・点ヒット生成)など、複数パターンで共通する処理は
  `AttackPatternBase`にヘルパーとしてまとめてある
- 近接/AoE系(melee_arc/wide_cleave/self_pulse/holy_pulse_heal/piercing_thrust)は
  `entities/melee_hit/`(`MeleeHit`、`HitboxComponent`を継承した移動しない
  瞬間ヒット判定)を使い、既存のHitbox/Hurtbox被弾パイプライン(会心判定込み
  ダメージ・属性VFX・hit_impact SE・`damage_dealt`通知)をそのまま再利用する
- charge_dash(Knight)だけは例外的に、`AttackPatternBase.apply_direct_damage()`で
  対象へその場で直接ダメージを適用する。突進中は攻撃者自身が高速で移動し
  続けるため、MeleeHitの「Area2Dを生成して次の物理ステップの検出を待つ」
  2段階判定だと、その1ステップの間に対象(または突進中のプレイヤー自身)が
  動いてしまい取りこぼす恐れがあったための設計判断
- summon_minion(Necromancer)は`entities/allies/ally_skeleton.gd`(既存の
  `EnemyBasic`/`AIComponent`/`ChaseStrategy`と同じ構成を、追跡対象を
  「プレイヤー」ではなく「最も近い敵」に、被弾・与ダメージの衝突レイヤーを
  敵用ではなく味方用に入れ替えて再利用したもの)を召喚する
- 各パターンの数値(ダメージ・攻撃間隔・射程・扇の角度・貫通数・召喚間隔等)は
  `data/characters/*.json`の`base_damage`/`attack_interval`/`attack_range`/
  `attack_pattern_params`(パターン固有の追加パラメータ、任意のキーをそのまま
  持てる)にあり、JSON編集だけでバランス調整が完結する

### 19.2 職業ごとの攻撃パターン一覧

| 職業 | attack_pattern_id | 概要 |
|---|---|---|
| Soldier | melee_arc | 標準的な前方扇形の近接攻撃 |
| Swordsman | melee_arc | 近接・短射程・扇状範囲攻撃 |
| Knight | charge_dash | 一定間隔で最も近い敵へ自動突進し、通過した敵にダメージ+ノックバック(2026年8月、19.8参照) |
| Knight Templar | self_pulse | 自分を中心とした周期的AoE |
| Armored Axeman | wide_cleave | 近接・広範囲の扇状斬撃(melee_arcと同じクラスを共有し、範囲重視・攻撃間隔長めのパラメータで差別化) |
| Lancer | piercing_thrust | 直線上の敵を貫通する突き、細長い判定 |
| Archer | spread_shot | 同時に3方向へ矢を発射 |
| Wizard | homing_bolt | 緩やかに敵を追尾する魔法弾、射程長め |
| Priest | holy_pulse_heal | 周期的に周囲へダメージ+自分のHPを少量回復(self_pulseを継承) |
| Necromancer | summon_minion | 一定間隔で味方スケルトンを1体召喚(上限あり) |

### 19.3 強化オプションの読み替え

強化オプションは近接/遠距離/共通カテゴリで候補を分離する:

- **damage_up/crit_rate_up**: 全パターン共通でそのまま(`roll_damage()`が
  `PlayerUpgradesComponent`の蓄積値をそのまま参照する)
- **multishot_chance_up/homing_upgrade**: `ranged`専用。近接職の候補には表示しない
- **melee_power/melee_rapid_strike/melee_wide_swing/melee_blood_thirst**:
  `melee`専用。遠距離職の候補には表示しない
- 旧セーブ等ですでに保持している強化値との互換性を保つため、既存の読み取り処理自体は
  残すが、新規ランの候補抽選ではカテゴリを厳守する

### 19.4 職業ごとの特性(HP・移動速度倍率・固有パッシブ)

`max_hp`/`move_speed`は、Soldierの基準値(HP100/移動速度140)に対する倍率で
算出した絶対値を`data/characters/*.json`へ直接設定している(既存フィールドの
数値をそのまま倍率どおりに調整、新規の倍率フィールドは追加していない)。

| 職業 | max_hp | move_speed | 固有パッシブ |
|---|---|---|---|
| Soldier | 100(基準) | 140(基準) | なし |
| Swordsman | 110 | 147 | melee_lifesteal_percent 0.08、1ヒット最大3HP |
| Knight | 100 | 182 | 近距離の標準近接攻撃 |
| Knight Templar | 140 | 119 | damage_reduction 0.15、self_pulseの威力+15%(base_damageに反映済み) |
| Armored Axeman | 150 | 105 | damage_reduction 0.20、近接攻撃力+20%(base_damageに反映済み) |
| Lancer | 105 | 161 | piercing_thrustの貫通数+1(pierce_count=4、既定3+1) |
| Archer | 85 | 168 | crit_rate_bonus 0.10、pickup_range_multiplier 1.2 |
| Wizard | 75 | 140 | exp_gain_multiplier 1.25 |
| Priest | 100 | 140 | damage_reduction 0.05、自己回復量+50%相当(heal_percent 0.15)、pickup_range_multiplier 1.15 |
| Necromancer | 80 | 140 | minion_stat_multiplier 1.3(召喚した味方のステータス+30%)、self_damage_multiplier 0.9(本体攻撃力-10%) |

### 19.5 パッシブの実装先

`CharacterData`に追加した各パッシブ値は、`PlayerUpgradesComponent.
apply_character_passives()`が起動時(`Player._apply_character_data()`の直後)に
「初期値」として蓄積値へ合成する。既存の強化オプション/アイテムの加算・減算
ロジック(`_apply_effect()`)を一切変更せずに、職業パッシブと後から選ぶ強化
オプションが自然に重ね合わさる設計にしている:

- `damage_reduction` → `damage_taken_multiplier`の初期値(以後、強化
  オプション由来の軽減率が加算されていく) → `HealthComponent.
  damage_taken_multiplier`
- `crit_rate_bonus` → `PlayerUpgradesComponent.crit_rate_bonus`の初期値
- `self_damage_multiplier` → `PlayerUpgradesComponent.damage_multiplier`の
  初期値(欠片合成武器・職業攻撃パターンの両方のダメージ計算に反映される)
- `exp_gain_multiplier` → `PlayerUpgradesComponent.exp_gain_multiplier`
  (新設)。`ExperienceComponent`が敵撃破時の獲得経験値に掛ける
- `dash_invincible` → 旧charge_dashとのデータ互換用に保持する
- `minion_stat_multiplier` → summon_minionが召喚時に味方のHP/攻撃力へ直接掛ける
- `melee_lifesteal_percent` → 近接HitBoxの1ヒットごとに掛け、
  `melee_lifesteal_cap_per_hit`で回復量を制限して`HealthComponent.heal()`する
- `pickup_range_multiplier` → Heart取得判定とは別の将来拡張用倍率として保持する。
  Heartは現在、接触時に自動取得する

### 19.6 Swordsman Spaceスキル「居合」

- Space入力後0.16秒の構えを行い、その時点の向きへ最大280px斬り抜ける
- 移動経路上の敵を1体につき1回だけ攻撃し、敵Bodyとの衝突では停止しない
- 壁・障害物との物理衝突は維持し、壁をすり抜けない
- 発動中は移動入力を一時ロックし、終了時に復帰する。敵を自動追尾しない
- 距離・横幅・威力倍率・構え時間・分割数はSwordsmanの`active_skill_params`から調整する
- 移動経路には現在のキャラクターフレームを使った青黒い残像を生成し、約0.28秒で消去する。
  残像の透明度と寿命は`afterimage_alpha`/`afterimage_lifetime`から調整する
- 居合は1体につき1回ヒットし、会心判定は行わない。最終ダメージは次の式とする:
  `base_damage × レベル成長倍率 × 共通damage_multiplier × melee_damage_multiplier × 居合damage_multiplier`
- Swordsmanの初期値では`14 × 4.8 = 67.2`。POWER / 剛力を1回取得すると
  `melee_damage_multiplier`が1.15になり、同条件の居合ダメージは77.28になる
- 共通の攻撃力強化・レベル成長・近接攻撃ダメージ強化は居合にも反映する。
  攻撃速度・近接範囲・吸血強化は居合の威力には影響しない

### 19.7 職業攻撃の表示・実行方針

- Soldierを含む全10職業は、`CharacterData.attack_pattern_id`で指定された固有通常攻撃を自動実行する
- 職業固有攻撃を持つ現在の10職業には、初期矢`starter_sword`を重ねて自動装備しない
- 欠片合成で獲得した武器は例外で、全職業が職業固有攻撃と並行して使用できる
- 職業通常攻撃の開始時は`weapon_fired`を通知し、既存の攻撃アニメーションを再生する
- 近接職は攻撃アニメーション開始後、JSONの`impact_delay`に合わせて短時間HitBoxを発生させる
- 動作確認では攻撃関数の直接呼び出しだけで済ませず、実際のゲームループから自動攻撃が発生することを確認する

### 19.8 職業専用攻撃強化(ability_level、2026年8月追加)

プレイヤーのレベルアップに応じて、職業固有の攻撃パターン(19章、
`systems/attack_patterns/`)自体が段階的に強化される仕組みを追加した。

**実装着手前に判明したデータの食い違いとその修正**: 実装依頼の時点で
「Knightはcharge_dash」という前提が示されたが、当時のdata/characters/knight.json
および本仕様書19.2は「Knightはmelee_arc」になっていた(19.1の`apply_direct_damage()`
の説明文だけが「charge_dash(Knight)」という古い記述のまま残っており、
本仕様書内で矛盾していた)。ユーザーに確認のうえ、`knight.json`の
`attack_pattern_id`を`charge_dash`へ戻し(`systems/attack_patterns/
charge_dash_attack.gd`自体は未使用のまま残存していた)、19.2の表もそれに
合わせて修正した。これにより19.1の記述との矛盾も解消される。

**アーキテクチャ**:

- `AttackPatternBase`(19.1の基底クラス)に`ability_level: int`
  (初期値1、`MAX_ABILITY_LEVEL = 5`が上限)を追加。各サブクラスの
  `execute()`/`get_interval()`等がこの値を見て段階的に挙動を変える
- 新しい選択UIは作らず、既存のレベルアップ「通常強化3択」の抽選プール
  (`ui/level_up_select/level_up_select.gd`)にそのまま混ぜる方針とした
  (9章で扱ったモーダルの二重表示問題を再発させないため)
- `UpgradeData`(`resources/upgrade_data.gd`)に`class_character_id`
  (空文字なら通常の汎用強化)・`class_ability_level`(この強化を選ぶと
  到達する段階、2〜5)を追加。`data/upgrades/class_<character_id>_lv<N>.json`
  として職業ごとに4段階ぶん(10職業×4=40ファイル)用意した
- `LevelUpSelect._get_compatible_upgrades()`は、`class_character_id`が
  空でない候補について「現在選択中のキャラクターのidと一致し、かつ
  現在のability_level+1と一致する」ものだけを候補に加える。これにより
  Lv2→Lv3→Lv4→Lv5の順序が必ず保たれ(飛び級や後戻りが起きない)、
  常に選択肢プールには対象職業の「次の1段階」だけが1件だけ混ざる
- 選択されると`PlayerUpgradesComponent.apply_upgrade()`が通常の
  `_apply_effect()`ディスパッチャ経由で`effect_type: "class_ability_level_up"`
  を処理し、`WeaponManagerComponent.increase_class_ability_level()`が
  `_class_attack.ability_level`を+1する(既存の強化オプション適用経路を
  そのまま流用し、専用の分岐を`apply_upgrade()`自体には追加していない)

**gating単位の設計判断(character_id基準、attack_pattern_id基準ではない)**:
Soldier/Swordsman/Armored Axemanの3職業は`attack_pattern_id`が
`melee_arc`/`wide_cleave`(実装クラスは共通の`MeleeArcAttack`)で重複して
いるため、`attack_pattern_id`だけで出現条件を判定すると3職業が同じ強化
プールを共有してしまい、職業ごとに異なる強化内容を持たせられない。その
ため`class_character_id`は`CharacterData.id`(例: "swordsman")で判定し、
`MeleeArcAttack`・`SelfPulseAttack`(Knight Templar/Priestが共有)は
`character_data.id`で分岐して職業ごとに異なるLv2〜5の効果を出し分けている。

**職業ごとのLv2〜5効果**(`attack_pattern_params`によるJSON側の基礎数値
とは別に、`ability_level`のしきい値で段階的に有効になる。フレーバー文言は
依頼内容を踏襲しつつ、実際の`attack_pattern_id`(19.2参照)に合わせて
近接/範囲攻撃向けに読み替えた項目がある):

| 職業 | Lv2 | Lv3 | Lv4 | Lv5 |
|---|---|---|---|---|
| Soldier | 2連続ヒット | 攻撃間隔-15% | 間合い+15%(貫通1段分の踏み込み) | 20%の確率で3連続ヒット |
| Swordsman | (2026年8月、19.9の「流派分岐」システムに置き換え。以下のLv2〜5表はSwordsmanには適用されない。詳細は19.9参照) ||||
| Knight | 突進距離+50%(dash_duration×1.5) | クールダウン-25% | 着地地点に半径70pxの小爆発 | 0.12秒後にもう1回突進(2連続突進) |
| Knight Templar | 波動範囲+30% | 発動間隔-20% | ヒット時ノックバック+50px | 二重波動(確定でもう1回発生) |
| Armored Axeman | なぎ払い角度+20度 | ダメージ+25% | クールダウン-20% | 返し斬り(逆方向へもう1振り)追加 |
| Lancer | 貫通数+1(間合い+15%) | 射程+30% | クールダウン-20% | 3方向(正面+左右18度)同時の突き |
| Archer | 同時発射+1本 | 拡散角度×0.6(集中射撃) | クールダウン-15% | 15%の確率で全方位8方向発射に切替 |
| Wizard | 誘導性能+0.3 | 弾速×1.2 | 着弾時に半径60px・本体50%ダメージの小爆発 | 2発同時発射(2発目は2番目に近い敵を追尾) |
| Priest | 回復量×1.3 | 発動間隔-20% | ダメージ範囲+25% | 被弾させた敵に被ダメージ+10%の弱体(4秒)を付与 |
| Necromancer | 召喚上限+1 | 味方ステータス×1.2(既存のminion_stat_multiplierに追加で乗算) | 召喚間隔-20% | 味方スケルトン死亡時、その場に半径60pxの爆発ダメージ |

- Priest Lv5の弱体は、敵側で誰も同期していなかった
  `HealthComponent.damage_taken_multiplier`(9章参照)を一時的に掛け増しし、
  時間経過後に同じ倍率で割り戻す形で実装している
- `AttackPatternBase`に`apply_area_damage()`(円範囲の敵へまとめてダメージを
  適用する簡易AoEヘルパー)を追加し、KnightのLv4着地爆発・NecromancerのLv5
  味方死亡爆発で共用している

**検証方法**(19.9のSwordsman流派分岐システム導入前、直線的な段階構成だった
当時の検証。Swordsmanの検証内容は19.9で再実施済み): ヘッドレス実行で、
(1)Swordsmanを選択した状態でability_levelを1→5まで実際に上げながら
`LevelUpSelect._get_compatible_upgrades()`を都度呼び出し、各段階で対応する
`class_swordsman_lv{2,3,4,5}`だけが1件ずつ候補に出現し、Lv5到達後は候補が
0件になる(Lv6が存在しないため)ことを確認、(2)実際のゲームループ(手動での
`execute()`呼び出しではなく、`WeaponManagerComponent._process()`による
自動発動)でSwordsmanのability_level1と2を比較し、同じ3秒間で発生する
`MeleeHit`ノード数が1周期1発から1周期2発に実際に増えることを確認、
(3)Knightについては
`_class_attack`が実際に`charge_dash_attack.gd`のインスタンスになっている
こと、実際のゲームループで突進による移動が発生すること、ability_level2で
移動距離が実際に伸びることを確認した。

### 19.9 職業スキルの流派分岐(school、2026年8月、試験実装)

19.8のability_levelシステムに「流派分岐」を組み込んだ。**現時点では
Swordsman(melee_arc)のみの試験実装**であり、うまく機能することを
確認したうえで他の9職業へ同じ仕組みを展開する予定(未着手)。

**設計**:

- 職業スキルの強化は(使用回数ではなく)引き続き「プレイヤーの
  キャラクターレベル」に紐づく。19.8までと同じく、既存のレベルアップ
  「通常強化3択」の選択肢プールに統合する形を維持し、専用の選択UIは
  作っていない
- `AttackPatternBase`(基底クラス)に`school: String`(既定値`"none"`)を
  追加した。school分岐を持たないパターン(Soldier/Armored Axeman等)では
  常に`"none"`のまま無視される
- `UpgradeData`に`class_school: String`を追加。意味は`effect_type`で変わる:
  - `effect_type == "class_school_select"`の場合: この強化を選ぶと確定する
    school(例: `"rengeki"`)。`class_ability_level`は常に2(=流派選択が
    Lv2到達を兼ねる)
  - それ以外(`"class_ability_level_up"`)の場合: この強化が出現するために
    必要な「既に確定しているschool」。空文字ならschool分岐を持たない
    (19.8の他職業と同じ扱い)
- `LevelUpSelect._get_compatible_upgrades()`のschool判定:
  - `class_school_select`系の候補は、school未確定(`"none"`)の間だけ出現する
  - 通常の`class_ability_level_up`系候補は、`class_school`が現在確定している
    schoolと一致する場合だけ出現する(選ばなかった流派は二度と出現しない)
- **出現の保証**: 流派選択(school未確定でLv2に到達するタイミング)は
  一度きりの重要な分岐のため、`LevelUpSelect._open()`で
  `class_school_select`系の候補を通常の抽選(シャッフル→先頭3件)から
  分離し、必ず選択肢に含めるようにしている(残り枠は通常の候補から
  ランダムに補充する)。これにより、レベルアップの通常オプションに
  「混ぜる」という依頼の方針を保ちながら、流派選択の回だけ乱数で
  埋もれて出現しない事故を防いでいる
- 選択されると`PlayerUpgradesComponent.apply_upgrade()`が
  `effect_type == "class_school_select"`を判定し、通常の`_apply_effect()`
  ディスパッチャ(float専用)を経由せず`WeaponManagerComponent.
  select_class_school(class_school)`を直接呼ぶ(schoolは文字列のため)。
  `select_class_school()`は`school`を確定させると同時に
  `increase_class_ability_level()`でability_levelも2へ進める

**Swordsman: 乱撃派(rengeki) / 一閃派(issen)**

| 流派 | Lv2 | Lv3 | Lv4 | Lv5 |
|---|---|---|---|---|
| 乱撃派 | 連続斬り数2 | 連続斬り数3 | 攻撃間隔-20% | 連続斬り数4+最後の一撃は確定クリティカル |
| 一閃派 | 単発ダメージ+40% | 間合い+30% | クリティカル率+25% | HP30%以下の敵に約5倍の大ダメージ(完全な即死ではなく大ダメージとして実装) |

- `roll_damage()`/`spawn_arc_hit()`に`bonus_crit_chance`(一閃派Lv4の
  クリティカル率加算)・`force_critical`(乱撃派Lv5の最後の一撃を確定
  クリティカルにする)を追加した(既定値ありの追加引数のため既存呼び出し元に
  影響しない)
- 一閃派Lv5の大ダメージは、通常のなぎ払い判定(全員に1回ずつ命中)とは別に、
  `AttackPatternBase.query_enemy_hurtboxes()` + `is_within_arc()`で
  同じ扇範囲内のHP30%以下の敵を再度探索し、`apply_direct_damage()`で
  追加ダメージ(通常の1撃相当×4、合計で約5倍相当)を上乗せする形で実装した
  (MeleeHit自体を「対象ごとに異なるダメージ」を出せる作りに拡張するのは
  過剰と判断し、既存のダメージ適用パイプラインを2回に分けて呼ぶ形にした)

**天賦図(TalentTree)UI**:

- 既存のポーズメニュー(`ui/pause_menu/`、所持武器一覧画面)に「所持武器」/
  「天賦図」の切り替えタブを追加した(`ui/pause_menu/pause_menu.tscn`の
  `TabBar`、`pause_menu.gd`の`_show_tab()`)
- レイアウト: 上部中央に起点ノード「居合」、その下に2列(左: 乱撃派、
  右: 一閃派)でLv.2〜Lv.5のノードを縦に並べ、`↓`のテキスト矢印で接続する
  (`pause_menu.gd`の`_refresh_talent_tree()`/`_build_school_column()`/
  `_build_talent_node()`が`WeaponManagerComponent.get_class_school()`/
  `get_class_ability_level()`の現在値からその場で組み立てる)
- ノードの状態は3通り: **習得済み**(選んだ流派の到達済み段階、金色系の
  枠・背景ではっきり表示)/**未到達**(流派未確定、またはこれから来る
  段階、薄暗い枠+🔒アイコン)/**選択不可**(流派確定後、選ばなかった側は
  ヘッダーごとさらに沈んだグレーで永続的に表示し続ける)
- Swordsman以外の職業を選んでいる場合は「この職業の天賦図は現在準備中です」
  という案内文を表示する(19.9がSwordsmanのみの試験実装であるため)
- 「居合」という名称は、Swordsmanの既存Spaceアクティブスキル(19.6)と
  同じ名前を天賦図の起点ラベルとして流用している(依頼内容の指定通り)。
  両者は別の仕組み(19.6は即時発動のアクティブスキル、19.9は通常攻撃の
  強化ツリーの起点表示)である点に注意

**検証方法**: ヘッドレス実行で、(1)`LevelUpSelect._open()`と同じ抽選ロジック
(school_select系を強制採用+残りをシャッフル)を10回試行し、毎回
乱撃派/一閃派の両方の選択肢が候補に含まれることを確認、(2)乱撃派を選択後、
`_get_compatible_upgrades()`がLv3→Lv4→Lv5の順に乱撃派の強化だけを1件ずつ
返し、一閃派の候補が一度も混ざらないこと、Lv5到達後は候補が0件になる
ことを確認、(3)実際のゲームループ(`WeaponManagerComponent._process()`
による自動発動)で、school未確定時とLv2(乱撃派)選択直後を比較し、同じ
3秒間に発生する`MeleeHit`ノード数が実際に増える(1周期1発→2発)ことを
確認、(4)`PauseMenu._refresh_talent_tree()`が組み立てたノードの文字色/
ロックアイコンの有無を実際に読み取り、school未確定時は全8ノードが
未到達、乱撃派選択後は乱撃派側だけが順に習得済みへ切り替わり一閃派側は
全ノードが選択不可になることを確認したうえで、実レンダリングの
スクリーンショットでも天賦図の見た目(色分け・矢印接続・ロックアイコン)を
目視確認した。

### 19.10 能動発動スキルシステム(2026年8月、試験実装)+ EXPゲージ + ウィンドウサイズ

**実装前の調査結果(既存のSpaceキー実装)**: 依頼を受けて調査した結果、
`active_skill`という入力アクションが**既に**存在し、Space(キーボード)に
割り当てられていた(`autoload/game_manager.gd`の`_register_active_skill_action()`
が起動時にコードから動的登録している。`project.godot`に`[input]`セクションは
無く、WASD移動と同じ「コードから安全に登録する」方式)。このアクションは
`entities/player/player.gd`の`_process()`から`ActiveSkillComponent.
try_activate()`を呼ぶ形で**全10職業ぶん実装済み**であり、Swordsmanには
`active_skill_id = "swordsman_iai"`(居合)が割り当てられていた:
Space押下でダッシュしながら直線上の敵を斬る(`dash_distance` 280px、
`damage_multiplier` 4.8倍、`windup` 0.16秒、クールダウン6秒、専用の
残像VFX付き)、既に作り込まれた機能。**新規に`ability_activate`アクションを
追加するのではなく、この既存の`active_skill`アクションをそのまま拡張・
流用する方針で実装した**(ゲームパッド未割り当てだったため、南ボタン
(Xbox配置のAボタン、`JOY_BUTTON_A`)を追加登録した)。

**Swordsmanの既存实装(swordsman_iai)との関係**: 「根本的な競合」では
ないと判断した。理由: (1) 依頼内容はSwordsmanの`active_skill_id`経路の
**発動可能回数(チャージ)**をschool(19.9)に応じて出し分けたいという
主旨であり、Spaceキー自体の役割(「職業固有の重い一撃を撃つ」)は変わらない、
(2) `ActiveSkillComponent`は元々`_execute_skill(skill_id)`で職業ごとに
分岐する設計になっており、将来Lv.5奥義をここに展開する土台としてそのまま
使える。**「居合」の技自体(モーション・当たり判定・ダメージ計算、
`_swordsman_iai()`)はschoolに関わらず常に同じものを使う**(下記の
チャージ制修正で確定)。

**設計(`components/active_skill_component.gd`)、チャージ制(2026年8月、
初版の「連続斬りモーション」実装が誤りだったため作り直し)**:

- 居合の技自体(`_swordsman_iai()`: ダッシュしながら直線上の敵を斬る、
  `dash_distance` 280px・`damage_multiplier` 4.8倍・`windup` 0.16秒・
  残像VFX)は、school未確定(Lv1)/乱撃派/一閃派のいずれでも**共通の
  同じ関数**を呼ぶ(初版で乱撃派だけ`_cone_attack()`という別形状の
  攻撃に差し替えてしまっていたのは誤りで、撤去した)
- schoolが変えるのは「1回のクールダウンサイクルで何回連続して発動
  できるか」というチャージ数だけ:
  - school未確定(Lv1)/一閃派: `max_charges = 1`(1回発動したら即
    クールダウンへ)
  - 乱撃派: `max_charges = 2`(1回目発動直後にもう一度押せば、間を
    置かず同じ居合が2回目発動する。2回使い切った時点でクールダウン開始)
  - 一閃派だけは技そのものが異なる(確定クリティカルの一撃、
    `_swordsman_issen_strike()`、`@export var issen_damage_multiplier:
    float = 2.5`)。chargeは常に1のため「今まで通り単発のまま」
- 実装は`_swordsman_charges_used`(今のサイクルで使ったチャージ数)を
  押下のたびに+1し、`max_charges`に達した瞬間だけクールダウンを
  開始する単純なカウンタ方式(0.4秒の入力バッファ等のタイマーは
  一切使わない。「間を置かず」という要件を、押下ごとに即座に判定する
  ことでそのまま満たす)
- `_swordsman_iai()`は複数フレームにまたがる非同期処理(ダッシュ演出)
  のため、乱撃派の2チャージ目が1チャージ目の演出中に押された場合でも、
  2つの居合が同時に動いて移動ロック/無敵状態を奪い合わないよう、
  `_queue_swordsman_iai()`で順番に実行するキューにしている(同時実行
  ではなく、1つ目が終わり次第すぐ2つ目、という順次実行)
- クールダウン終了時にチャージは`max_charges`まで自動的に回復する
  (`cooldown_remaining<=0`になれば、次の押下で`_swordsman_charges_used`が
  0から数え直される)

**乱撃派のコンボキャンセル(2026年8月追加)**: 1回目の居合が完全に終わるのを
待たずに2回目を繋げられるよう、`_swordsman_iai()`のダッシュモーション
(`dash_steps`のステップループ)内に「キャンセル可能ポイント」を設けている。
**対象は乱撃派のチャージ連携のみ**(school未確定/一閃派は元々max_charges=1
のため、このキャンセル判定自体が発生しない)。

- キャンセル可能ポイントは、モーション全体のうちダメージ判定が発生した
  直後・60〜70%が再生されたあたり(`IAI_CANCEL_POINT_RATIO = 0.65`、
  既定`dash_steps=10`に対し`ceil(10*0.65)=7`→0始まりでstep index 6、
  すなわち10ステップ中7ステップ目=70%完了時点からキャンセル可能になる)
- ダッシュのステップループが各ステップで(1)移動、(2)そのステップぶんの
  ダメージ判定、を行った**直後**にキャンセル可能ポイントの判定を行う。
  この時点で次のチャージが既に控えていれば(`_swordsman_iai_pending > 0`)、
  1回目の残りの硬直モーション(キャンセル可能ポイント以降のステップ)を
  打ち切ってその場で`return`する
- 呼び出し元の`_run_swordsman_iai_queue()`は`await _swordsman_iai()`から
  即座に復帰し、間を置かず次の`_swordsman_iai()`(2回目の居合)を開始する。
  1回目のダメージ判定は、打ち切られる前の各ステップで既に適用済みのため、
  ダメージが出ないまま次に切り替わることはない
- キャンセルされた場合は移動ロック(`set_movement_locked`)・無敵
  (`health_component.invincible`)の解除も行わない(次の居合へそのまま
  引き継ぎ、2回の居合の間に一瞬だけ無敵が切れる隙間を作らないため)。
  最終的な解除は、キャンセルされなかった(=そのチャージ連携で最後になる)
  居合だけが行う
- 2回目のチャージが無い場合(通常/一閃派、または既にチャージを使い切って
  いる場合)は`_swordsman_iai_pending`が0のままキャンセル判定を通過しない
  ため、これまで通り最後まで通常再生される
- **検証方法**: ヘッドレス実行で、(1)school未確定でのフル居合1回の
  所要時間を基準値として実測(435ms)、(2)乱撃派選択後に即座に2連打した
  場合の合計所要時間を実測(796ms)し、単純に2回フル再生した場合の想定値
  (基準値×2=870ms)より明確に短い(74ms短縮)ことを確認、(3)この間
  `health_component.invincible`が2回の居合をまたいで一度もfalseに戻らず
  連続していること(=移動ロック/無敵の解除が正しくスキップされ、隙間なく
  繋がっていること)、(4)プレイヤーの移動距離(実測476px)が
  「キャンセルされた1回目(約70%×280px≈196px)+フルの2回目(280px)」の
  合計とほぼ一致すること(=キャンセル位置が意図した60〜70%地点で発生して
  いること)を確認した。

**将来の展開方針**: 「characterごとに`_try_activate_*()`を用意して
`try_activate()`から分岐する」「`_cooldown()`もcharacter/schoolで分岐できる」
という構造にしてあるため、他職業のLv.5奥義をここに追加する際もこの
ファイル内だけで完結できる(現時点では未着手、Swordsmanのみ)。

**EXPゲージとスキル熟練度表示の分離(2026年8月、完全に別概念として実装
し直し)**: 初版では天賦図の進捗ゲージをキャラクターの経験値バーと連動
させてしまっていたが、これは誤りだったため、見た目・データの両方を
完全に分離した。

- キャラクターEXPゲージ(現状維持): `components/experience_component.gd`の
  `exp_changed(current_exp, exp_to_next_level)`シグナルを`add_exp()`の
  たびに発火し、`ui/hud/hud.tscn`のHPBar直下の`LevelLabel`+`ExpBar`
  (水色のなめらかなバー)がこれを表示する
- 職業スキルの熟練度表示(新規、EXPとは別物): `ui/common/
  ability_stage_dots.gd`(`AbilityStageDots`)が、`WeaponManagerComponent.
  get_class_ability_level()`(19.8のability_level、1〜5)だけを参照して
  「5つの丸印」(基本形態+Lv.2〜Lv.5)を組み立てる。到達済みは金色の
  塗りつぶし、未到達は暗い輪郭のみ。`WeaponManagerComponent`に新設した
  `class_ability_level_changed(new_level)`シグナルで駆動する
  (ExperienceComponentの値は一切参照しない)
- この丸印表示を、HUDのスキルアイコン付近(`SkillPanel`内、画面下部中央)と
  天賦図パネル(ポーズメニュー、19.9参照)の両方に配置した。EXPバー
  (画面左上)とは配色(金色 vs 水色)・配置(画面下部中央 vs 左上)の
  両方で明確に区別し、同じバーに重ねたり色を似せたりしていない

**ウィンドウサイズ**: `project.godot`の既定ウィンドウサイズを1920×1080から
1600×900へ変更した。リサイズ可能設定(`window/size/resizable`)は元々
明示指定されておらずエンジン既定(可能)のままのため、変更していない。

**検証方法**: ヘッドレス実行で、(1)school未確定(Lv1)状態で1回押下すると
即座にクールダウン(6秒)が始まり、直後の2回目押下が拒否されること、
その間にプレイヤーが実際に280px(dash_distanceの既定値と一致)移動する
=居合のダッシュ技自体が発動していることを確認、(2)乱撃派選択後、
1回目の押下ではクールダウンが0のまま(まだチャージが残っている)、
1回目の演出中に間を置かず2回目を押下しても正しく2回目の居合(同じ
ダッシュ技、プレイヤーがさらに移動)が発動し、2回目でクールダウン
(既定2秒)が開始されること、直後の3回目押下が拒否されること、
クールダウン終了後にチャージが回復し4回目が再び受理されることを確認、
(3)HUDの`ExpBar`(`set_experience()`後の値)と`StageDotsWrap`
(`set_ability_stage()`後の塗りつぶし数)がそれぞれ独立したノードとして
正しい値を示し、画面上の座標も明確に異なる(EXPバーは左上、丸印は下部
中央)ことを確認した。

## 20. 敵の通常攻撃(接触ダメージ廃止・無敵時間)

2026年8月、近接職業(Swordsman/Armored Axeman等)が敵に隣接して戦う際、
接触ダメージが実質「触れている間ずっと」入り続け体力が急減する問題を修正した。

### 20.1 通常攻撃の発生条件

- `ContactHitbox.damage_enabled`は常時falseとし、敵へ触れただけではダメージを受けない
- `EnemyBasic`はREADY→WINDUP→COOLDOWNの状態を持つ
  1. プレイヤーが`EnemyData.attack_range`へ入る
  2. 敵が停止して攻撃アニメーションを開始する
  3. `attack_windup`(既定0.45秒)の予備時間を待つ
  4. 攻撃時点で距離を再判定し、まだ範囲内の場合だけ`HurtboxComponent`へダメージを適用する
  5. `attack_interval`ぶんクールダウンする
- 精鋭・ボスの通常攻撃は予備時間中に床の危険円を表示する
- ボスchargeは接触判定に依存せず、突進中に明示的な距離判定を1回だけ行う

### 20.2 被弾無敵時間(iframe)

- `components/health_component.gd`に、被弾のたびに0.5秒(`IFRAME_DURATION`)の
  無敵時間を付与する仕組みを追加した。この間に発生した`apply_damage()`は
  すべて無視される
- Player/Enemy共通のコンポーネントのため、敵が被弾した際にも同様に適用される
  (複数の攻撃が短時間に集中して連続ヒットする事故を防ぐという趣旨自体は
  どちらにも当てはまるため)。既存の同一物理フレーム内ダメージ合算キャップ
  (9章)とは別の安全策で、両方とも有効なまま重ね合わさる

## 21. ホーム画面の職業選択UI(グリッドレイアウト)

2026年8月、ホーム画面(`ui/home/`)の職業選択を、縦一列のボタン一覧から
5列×2行のグリッド(10職業ぶん)へ作り替えた。ドラゴンクエストの記念画像の
ような「複数キャラクターのポートレートを整列させる」レイアウトの考え方を
参考にしたもので、特定作品のデザインを模倣したものではない。

### 21.1 レイアウト構成

- `ui/home/home.tscn`に`GridContainer`(`columns = 5`)を配置。各セルは
  `home.gd`が`Button`を動的に生成し(item_select.gd等と同じ、子に
  VBoxContainerを重ねてクリックをボタン自体に通す構成)、`GridContainer`へ
  追加する
- 各セルの構成: ポートレート(`TextureRect`)・職業名ラベル・下段の補助テキスト
  (解放済みは「選択してスタート」、未解放は「解放コスト: N」)
- ポートレートは、`entities/sprite_sheet_builder.gd`に新設した
  `build_portrait_texture(sprite_folder)`が、各職業の
  `assets/sprites/player/[職業名]/[職業名]_Idle.png`から`AtlasTexture`で
  1コマ目だけを切り出して返す。複数コマのスプライトシートをそのまま
  表示すると複数キャラクターが横に並んで見えてしまうため、必ず1コマぶんだけ
  を使う
- 未解放セルは、ポートレートに`modulate`でグレーがかった色(`Color(0.45,
  0.45, 0.45, 1.0)`)を掛けて彩度を落とし、ポートレートの上に鍵アイコン
  (テキストの🔒)を重ねて表示する
- 各セルの`Button`は、通常/ホバー/選択中(フォーカス)でスタイルボックスの
  枠線色を切り替える(通常は暗いグレー、ホバー・フォーカス中は金色寄りの
  ハイライト)ことで、マウスカーソルを合わせたセル・選択中のセルが視覚的に
  分かるようにしている

### 21.2 操作フロー(既存ロジックの流用)

- 解放済みのセルをクリック: `GameManager.selected_character_id`に記録して
  `game.tscn`へ遷移する(以前と同じ処理をそのまま流用)
- 未解放のセルをクリック: `SaveManager.unlock_character()`で解放を試みる。
  メタ通貨が足りていれば解放してグリッドを再描画し、足りなければ
  何も起きない(以前と同じ処理をそのまま流用)

### 21.3 サイズ調整(2026年8月、グリッドが画面に対して小さすぎた不具合の修正)

21.1節のグリッドを実装した直後、画面サイズに対してカード・ポートレート・
文字が全体的に小さく見える問題があったため、サイズ調整を行った。

**根本原因(ポートレートが原寸のわりに小さく見えた理由)**: 素材の
スプライトシート(例: `Soldier_Idle.png`)は1コマ=100x100のキャンバスに
対し、実際に描かれたキャラクター部分はごく一部(Soldierの場合17x21
ピクセル程度)しかなく、残りはアニメーションのコマ位置を揃えるための
透明な余白であることが判明した。そのため、1コマをそのまま切り出して
表示すると余白ごと拡大されるだけでキャラクター自体は相対的に小さいままだった。

**修正**: `entities/sprite_sheet_builder.gd`の`build_portrait_texture()`で、
1コマ目の画像を`Image.get_used_rect()`(不透明ピクセルの外接矩形を返す)で
走査し、取得できた場合はその矩形だけを`AtlasTexture.region`として使うように
変更した(取得できない場合は従来通りコマ全体を使うフォールバックを残す)。
これにより`TextureRect`の`STRETCH_KEEP_ASPECT_CENTERED`と組み合わさって、
キャラクターが表示枠のほとんどを占めるサイズで表示されるようになる。

**検証方法**: ヘッドレスではなく実レンダリングを伴うスクリプト実行
(`--path "." --script ...`、`--headless`なし)でホーム画面を実際に
インスタンス化し、`get_viewport().get_texture().get_image().save_png(...)`
で実際の画面をPNG保存した上で目視確認する(数値上のサイズが正しくても
実際に画像として小さく見える不具合はこの方法でしか発見できない)。

### 21.4 再拡大(2026年8月、縮小デグレの修正+さらなるサイズアップ)

21.3の修正後、`home.gd`に「カードの配置枠は300×300のまま維持しつつ、
`TextureRect.scale`で最終描画だけを70%(`PORTRAIT_RENDER_SCALE = 0.7`)に
縮小する」処理が誤って加わり、21.3のクロップ修正の効果を打ち消して
グリッドが再び小さく見える状態になっていた。以下の内容で修正・再調整した。

- **縮小デグレの除去**: `portrait.scale`による70%縮小、および`pivot_offset`・
  中間ラッパー`portrait_holder`(`SIZE_SHRINK_CENTER`)を撤去し、
  `TextureRect`を`PORTRAIT_SIZE`(`Vector2(300, 300)`)いっぱいに
  `STRETCH_KEEP_ASPECT_CENTERED`で直接描画する、21.1時点のシンプルな構成に戻した
- **カードサイズ**: `home.gd`の`CELL_SIZE`を`Vector2(352, 460)`に拡大
  (`home.tscn`の`GridContainer.theme_override_constants/h_separation`・
  `v_separation`は`26`)。10職業(5列×2行)で実測`grid total size`は
  `(1864, 946)`前後(1920×1080画面のマージン内でほぼ幅いっぱい、縦方向にも
  余裕を残したまま拡大)
- **文字サイズ**: 職業名`NAME_FONT_SIZE = 32`、解放コスト等の補助テキスト
  `SUB_FONT_SIZE = 22`、鍵アイコン`LOCK_ICON_FONT_SIZE = 170`、
  画面上部の「所持メタ通貨」ラベルは`home.tscn`側で
  `theme_override_font_sizes/font_size = 28`に拡大
- 画面全体のバランス(`CenterContainer`+`VBoxContainer`によるレイアウト、
  21.1・21.3から変更なし)は維持し、拡大後も画面上下に間延びした余白は
  発生しない
- 検証は21.3と同じ方式(実レンダリングのスクリーンショット目視確認)で、
  10職業すべてのポートレートが表示枠の大部分を占めるサイズで表示され、
  カード・文字が明確に大きくなったことを確認した

### 21.5 ポートレート表示スケールの縮小(2026年8月、ドット絵の粗さ対策)

21.4でポートレートを配置枠(300×300)いっぱいまで拡大した結果、ドット絵の
1ピクセルが大きく引き伸ばされすぎて粗さが目立つようになったため、
表示スケールのみを縮小した(カード・配置枠のサイズやレイアウトは変更しない)。

- `home.gd`に配置枠のサイズを`PORTRAIT_FRAME_SIZE`(`Vector2(300, 300)`、
  従来の`PORTRAIT_SIZE`)として分離し、`portrait_wrap`(`CenterContainer`)は
  このサイズのまま維持する(カードの縦幅・名前ラベルとの間隔を変えないため)
- 実際に描画する`TextureRect`のサイズだけを`PORTRAIT_DISPLAY_SCALE = 2.0/3.0`
  倍した`PORTRAIT_SIZE`(`Vector2(200, 200)`)に縮小する。`CenterContainer`が
  子(TextureRect)を自身の最小サイズのまま中央配置する性質を利用しており、
  21.4より前に混入していた`TextureRect.scale`+`pivot_offset`によるレイアウト
  外縮小(21.4で撤去済み)とは異なり、`custom_minimum_size`を直接縮小する
  シンプルな方式のため再発しにくい
- 鍵アイコン(`LOCK_ICON_FONT_SIZE = 170`)・文字サイズ・カードサイズ
  (`CELL_SIZE`)は今回変更していない
- 実レンダリングのスクリーンショットで、カードサイズが不変のまま
  ポートレートが約200×200で表示され、ドット絵のジャギーが軽減されたことを
  目視確認した

### 21.6 カードホバー時の攻撃アニメーション再生(2026年8月)

解放済みの職業カードにマウスカーソルを合わせている間、そのキャラクターの
攻撃アニメーションをループ再生するようにした。

- `ui/home/hover_attack_portrait.gd`(`HoverAttackPortrait`、`TextureRect`
  を継承)が、通常時はIdleの1コマ静止画を表示し、`start_attack()`が
  呼ばれている間だけ攻撃コマ配列を`_process()`でループ再生する
  (`stop_attack()`でIdle静止画に戻る)。カード(`home.gd`が生成する
  `Button`)の`mouse_entered`/`mouse_exited`シグナルへ、それぞれ
  `start_attack`/`stop_attack`を直接接続する
- 攻撃コマの取得には、Player側の職業攻撃パターン実装で使っている
  `SpriteSheetBuilder.build_sprite_frames()`(idle/walk/attack1/attack2/
  attack3等のSpriteFramesを組み立てる既存ロジック)をそのまま再利用する。
  新設した`SpriteSheetBuilder.build_hover_attack_frames(sprite_folder)`が、
  対象職業に存在する攻撃アニメーション(attack1/attack2/attack3のうち
  存在するもの)からランダムに1つを選び、そのコマ配列を返す
- 表示上は、選んだ攻撃アニメーションの全コマに共通の外接矩形(コマごとに
  `Image.get_used_rect()`を取り`Rect2.merge()`で合成した範囲)を切り抜きに
  使う。コマごとに個別の外接矩形を使うと、コマによってキャラクターの
  写る面積が変わり`STRETCH_KEEP_ASPECT_CENTERED`の拡大率がコマごとに
  変動してガクガクして見えるため、アニメーション内では拡大率を固定する
  (21.3のIdle単体クロップとは独立して、攻撃アニメーション側だけで
  一貫性を持たせる。IdleとAttack間で見た目のサイズがやや異なるのは
  想定内の挙動とする)
- 未解放カードは、`portrait.configure()`に空の攻撃コマ配列を渡し、
  `mouse_entered`/`mouse_exited`のシグナル接続自体を行わない。ホバーしても
  常にIdle静止画のまま(鍵アイコン表示)で、攻撃アニメーション再生の対象外
- 攻撃アニメーションが1つも見つからない職業(現状は存在しないが将来の
  素材差異に備えたフォールバック)は、ホバーしても静止画のままになる
  (`build_hover_attack_frames()`が空のDictionaryを返し、`configure()`に
  空配列が渡るため`start_attack()`が何もしない)
- 検証は、ヘッドレス実行で(a)解放済みカードの`mouse_entered`/
  `mouse_exited`が`HoverAttackPortrait`の`start_attack`/`stop_attack`へ
  実際に1件ずつ接続されていること、(b)`mouse_entered`シグナルを発火させた
  後、実際に`_process()`を複数フレーム進めてtextureが複数のコマ間で
  切り替わること(手動で`execute()`相当を1回呼ぶだけでなく、実際のループ
  再生を確認)、(c)`mouse_exited`発火後にIdle静止画へ戻ること、
  (d)未解放カードは`mouse_entered`/`mouse_exited`の接続数が0であることを
  それぞれ確認し、さらに実レンダリングのスクリーンショットでホバー中の
  カードだけが攻撃ポーズになっていることを目視確認した

### 21.7 1600×900基準の1画面フィット(2026年8月)

既定ウィンドウを1920×1080から1600×900へ変更した後も、21.4時点の
1920×1080向けグリッド寸法(約1864×946)が残っていたため、右端と下段が
表示領域から見切れていた。職業選択・解放処理やカードデザインは変更せず、
次のレイアウト値へ調整する。

- 基準解像度は1600×900。10職業を`GridContainer(columns = 5)`の5列×2段で
  表示し、横・縦スクロールなしで全カードを1画面内に収める
- 外周は`MarginContainer`で上下左右24pxを確保し、タイトル・通貨・グリッドは
  `VBoxContainer`と`CenterContainer`で中央揃えを維持する。グリッド自体は
  288×340pxのカード10枚、横間隔20px、縦間隔18pxで、合計1520×698pxとする
- ポートレートの配置枠は230×230px、実表示は200×200pxとし、従来と同じ
  `STRETCH_KEEP_ASPECT_CENTERED`、Nearestフィルタ、中央配置を維持する
- 職業名28px、補助テキスト20px、鍵120px、タイトル36px、所持通貨26pxとし、
  カード内間隔8px、カード内余白12pxで可読性と余白を両立する
- `ScrollContainer`は使用しない。1600×900より大きい解像度では、アンカーで
  全画面へ追従する外側ControlとCenterContainerによりグリッドを中央配置する
- 黒背景、ダークグレーのカード、4px枠線、角丸、ホバー/フォーカス色、
  ポートレート、選択・解放・画面遷移ロジックは変更しない

## 22. 自動通常攻撃・Spaceアクティブスキル・特別報酬(2026年8月改訂)

- 職業固有通常攻撃と合成武器は従来どおり自動発動し、プレイヤーは移動と位置取りへ集中する
- Spaceは通常攻撃ではなく、8〜15秒程度のCDを持つ職業固有アクティブスキルに使用する
- スキル数値は`data/characters/*.json`の`active_skill_*`で職業別に調整する
- HUD下部にスキル名・アイコン・SPACE表示・残り秒数・CD暗転を表示し、再使用可能時に発光する
- スキルVFXは局所的な扇/円の衝撃波、画面シェイク、短いヒットストップ、ノックバックを用い、
  通常攻撃との差を出しつつ全画面の視認性を損なわない

| 職業 | Spaceスキル | CD |
|---|---|---:|
| Soldier | 制圧薙ぎ払い(前方広範囲+ノックバック) | 10秒 |
| Swordsman | 迅雷連斬(前方への高速3連斬演出) | 9秒 |
| Knight | 不落の盾撃(周囲攻撃+4秒軽減) | 12秒 |
| Knight Templar | 聖域の審判(聖属性AoE+4.5秒軽減) | 13秒 |
| Armored Axeman | 大旋風(360度高威力+大ノックバック) | 11秒 |
| Lancer | 竜槍突破(長距離直線貫通+前進) | 10秒 |
| Archer | 九連矢嵐(前方9方向の扇状射撃) | 10秒 |
| Wizard | 深淵大魔法(大型周囲魔法) | 14秒 |
| Priest | 聖者の祈り(35%回復+聖属性AoE) | 12秒 |
| Necromancer | 死者の軍勢(強化召喚体2体) | 15秒 |

敵通常攻撃は接触ダメージではなく、攻撃範囲侵入→予備動作→命中時の距離再判定→
クールダウンの状態遷移で処理する。接触しているだけではダメージを受けない。
精鋭・ボスの通常攻撃では床の危険円を表示し、ボス固有攻撃もchargeの明滅、
slam/novaの床予兆など、回避可能な事前表示を持つ。

## 23. 精鋭属性・地面装備・ラン内装備システム(2026年8月)

### 23.1 ボス共通倍率

- `data/balance/boss_scaling.json`で全ボスの読込時倍率を一括管理する
- `hp_multiplier = 1.5`、`damage_multiplier = 1.25`、
  `move_speed_multiplier = 1.10`
- `DataLoader._load_bosses()`が各`data/bosses/*.json`の基礎値へ倍率を掛けて
  `BossData`を生成する。個別JSONは基礎値として維持し、AI・攻撃パターンは変更しない

### 23.2 精鋭戦と特殊属性

- `EliteRoomManager`は入室時に`StaticBody2D`等の一時障害物を生成しない。
  マップ外周・壁タイル等、本来のCollisionのみを維持する
- 入室イベント、精鋭生成、生存数、通常Wave停止、全滅報酬は従来の処理を維持する。
  プレイヤーは精鋭を倒さず部屋から離れられる
- 属性設定は`data/elite_affixes/default.json`、実行は
  `systems/elite_affix_component.gd`へ分離する。敵本体へ属性別分岐を追加しない
- 付与数は経過時間0〜119秒=1個、120〜299秒=1〜2個、300秒以降=2〜3個。
  候補から重複なしでランダム選択し、将来JSONへ属性を追加できる構造とする
- 頭上に「精鋭 [ 属性名 / 属性名 ]」を表示し、複数属性を確認可能にする

| 属性 | 効果 |
|---|---|
| 火炎 | 4秒間隔で半径105pxへ12ダメージ |
| 雷撃 | 5秒間隔でプレイヤー現在位置に0.8秒予兆後、半径58pxへ16ダメージ |
| 氷結 | 通常攻撃命中時、2秒間プレイヤーの移動速度を50%へ低下 |
| 毒 | 6秒間隔でプレイヤー付近に半径72px・5秒持続・毎秒5ダメージの毒床を生成 |
| 吸血 | 通常攻撃命中時、基礎与ダメージの30%を自身のHPとして回復 |
| 堅牢 | 8秒間隔で最大HPの15%ぶんのシールドを5秒間展開 |

火炎・雷撃・毒は局所的な円表示のみを使い、全画面フラッシュは発生させない。
シールドは`HealthComponent.shield_amount`がHPより先にダメージを吸収する。

### 23.3 装備ドロップと地面アイテム

- 全Enemy死亡時の`EventBus.enemy_drop_requested`を`EquipmentDropSystem`が購読する。
  通常敵は2%、強敵/Eliteは4%、Bossは最低1個確定で地面装備を生成する。
- Boss RarityはROOM Phase別Tableを使い、ROOM 4/8はUncommon〜Rare中心、ROOM 12以降はRare以上を増やし、
  ROOM 36はUncommon 0%、Legendary+Mythic合計62%とする。撃破と同時に自動取得はしない
- 死亡位置から最大52pxのランダムオフセットを付け、`DungeonMap.is_floor()`で
  床マスであることを確認する。候補が壁・範囲外なら死亡位置または近傍床へ戻す
- `GroundEquipmentItem`を地面へ実体として生成し、ラン中は時間で自動消滅させない
- 取得範囲72pxへ入ると、レアリティ色のアイテム名・レアリティ名・
  「E / X：拾う」を表示する。EキーまたはゲームパッドXで最寄りの1個を取得する
- 地面表示は64×64pxの画像全体ではなく、アルファ付き画像の不透明画素範囲
  （`Image.get_used_rect()`）をVisual Sizeとして扱う。現在のプレイヤーフレームの不透明画素高と
  `AnimatedSprite2D.global_scale`から見た目の高さを求め、装備本体をその82%（最小24px、最大42px）へ
  正規化する。全10職業で結果がプレイヤー本体の70〜100%に収まることを回帰テストする
- カード背景、上下浮遊、バウンド、大きな装備Sprite、円形・楕円形のレアリティリング、縦方向Loot Beamは
  使用しない。アイコン真下に6頂点の`PixelLootPlate`と非AAの`PixelLootOutline`だけを置く
- レアリティはPlate/Outline色、常駐Pixel粒子数（Uncommon 2 / Rare 3 / Epic 4 / Legendary 6 / Mythic 9）、
  粒子Contrastで区別する。Drop瞬間は3〜9粒の短いBurstだけを再生し、長いBeam・柔らかいGlow・全画面Flashは生成しない
- 同時に複数の対象がある場合は、プレイヤーから最も近い装備を取得する
- ROOM遷移時は未取得の`ground_equipment`を退役させ、旧ROOMのDropを後半まで蓄積しない。
  取得成功時はHUDへ小さく「○○を入手」と表示し、戦闘を停止する大型UIは出さない
- Drop成立時は`equipment_drop` SE IDを呼ぶ。現在は専用WAV未配置のため無音で安全にno-opし、
  `assets/audio/se/equipment_drop.wav`追加後はAudioManagerの既存フォルダ走査だけで再生可能になる
- アイコンは`data/equipment/templates.json`の`icon_path`から読み込む。
  未配置時はカテゴリ仮バッジを表示し、素材追加後はJSONのパスだけで差し替える

### 23.4 レアリティ

| レアリティ | 色 | 抽選重み | ステータス数 |
|---|---|---:|---:|
| Uncommon / アンコモン | 緑 | 50% | 1 |
| Rare / レア | 青 | 30% | 2 |
| Epic / エピック | 紫 | 15% | 3 |
| Legendary / レジェンダリー | 橙 | 4% | 3+特殊効果 |
| Mythic / ミシック | 赤 | 1% | 4+強力な特殊効果 |

上記はドロップ成立後の相対確率で、色だけでなく英語・日本語のレアリティ名も表示する。
Legendary/Mythicは橙/赤の硬いPixel Plateと多めの局所パーティクルで強調する。
巨大リング・縦Beam・柔らかい足元Glowは全レアリティで生成しない。Plate・Outline・パーティクルはGodot側で
画像と分離して重ねる。一方、装備本体は
レアリティ専用テンプレートと専用アイコンを使い、同じ物理デザインの単純な色替えにはしない。
Uncommonは実用品、Rareは青鋼と宝石、Epicはルーン魔装、Legendaryは王級の黄金装飾、
Mythicは黒赤の異形装備というように、シルエット・装飾密度・素材感も段階的に変える。

### 23.5 装備データ・スロット・効果

- 装備実体は`EquipmentData`。`instance_id`、テンプレート、名称、slot、rarity、
  icon_path、stats(Dictionary)、special_effects(Array)、合成素材保護用`is_locked`を持つ
- スロットは武器・頭・胴・腕・脚・アクセサリーの6種類。各1個を装着可能
- ステータス語彙は攻撃力、防御力、最大HP、移動速度、攻撃速度、
  クリティカル率、クリティカルダメージ
- 攻撃力・防御力・最大HPは固定値、移動速度・攻撃速度・クリティカル率・
  クリティカルダメージは割合値として扱う。レアリティ別範囲・個数・特殊効果は
  `data/equipment/drop_table.json`で調整する
- 特殊効果は`kill_heal`（撃破時固定HP回復）、`negate_hit`（確率で被弾無効）、
  `low_hp_power`（低HP時に最終攻撃倍率上昇）の3種類
- `EquipmentComponent`が装備交換時に全スロットを再集計する。既存レベルアップ強化・
  ボス3択アイテムの累積値とは分離し、交換時の二重加算を防ぐ
- 装備と所持一覧はPlayer scene内だけに存在し、SaveManagerへ保存しない。
  `run_ended`で一覧・全スロット・装備補正を明示的にリセットする
- 既存メタ通貨、解放済み職業、ベスト生存時間等のセーブキーは変更しない
- `EquipmentMergeSystem`は名称・部位・`template_id`を問わず、同一rarityの未装備・未ロック品を3個消費する。
  完成品は既存Rarity順の次段階に属する`templates.json`候補から1個生成し、素材に含まれる部位を優先、
  候補がなければそのRarityの全候補へフォールバックする。順序は
  Uncommon→Rare→Epic→Legendary→Mythicで、Mythicは上限。Element `FusionSystem`とは別責務である
- 合成前に3実体参照の重複、Inventory所属、装備中、Lock、Rarity、次Rarity候補を再検証する。
  完成品を構築できた場合だけ`EquipmentComponent.replace_merge_materials()`で3個削除・1個追加を一括実行し、
  失敗時は素材を消費しない。合成Statsは3素材の良いロール品質を次Rarityの既存`stat_ranges`へ正規化し、
  Affix数とLegendary/Mythicの特殊効果値も既存`drop_table.json`定義を使用する。新Rarityや新Save Dataは追加しない

### 23.6 装備UI・比較UI

- `ui/equipment/equipment_screen.tscn`をCキーまたはゲームパッドYで開閉する。
  Iキーは旧装備画面からの互換エイリアスとして同じ画面を開く。ESCでも閉じられる。
  既存モーダルが開いている間は割り込まず、`GameManager.active_modal_count`を使って
  安全に一時停止する
- 左: 既存キャラクタースプライトを中央に置き、その周囲へ6装備スロットと現在ステータス。
  右は「装備」「合成」の2モードを明確に分け、装備モードでは所持一覧・固定比較・装備/解除を表示する
- 比較は同じスロットの現在装備を基準に、各値を「現在→選択中」と表示する。
  上昇=緑の↑、低下=赤の↓、同値=灰色の=を用いる
- 地面取得後は所持一覧へ即時追加する。通常ROOM RunではCLEAR/REWARD/次ROOM準備中だけC/I画面を開け、
  COMBAT中は開かない。装備画面を閉じると準備済みの次ROOMへ自動遷移する
- 地面ドロップ、所持装備一覧、中央の装備済みスロットは、同じ`icon_path`の画像を表示する。
  取得や装備で別画像へ置き換えず、装備実体の同一性を視覚的に維持する
- 合成モードは独立した素材スロット3個、Rarity別素材候補数、素材用所持一覧、
  `現Rarity ×3 → 次Rarity ×1`プレビュー、合成Button、完成品Cardを表示する。
  所持カード単位の`1 / 3`表示は行わない。一覧選択で左から空きSlotへ入り、Slot選択で取り外す。
  最初の素材と同Rarityを強調し、他Rarityを暗くするが選択時は日本語の不成立理由を表示する。
  装備中・Lock中は状態を明記して選択不可とする。完成品の種類・部位・Statsは合成後に開示し、
  現在装備との比較と即時装備を可能にする
- 合成演出は約1.2秒。3つの実Iconが中央へ収束し、局所Pixel FragmentとImpactを経て完成Iconを開示する。
  Rarityが高いほどFragment数と展開距離を増やすが、巨大Bloom・Gradient・全画面Flashは使用しない。
  初回は全再生し、2回目以降はMouse / E(`interact`) / 決定(`ui_accept`)で表示だけをSkipできる。
  合成中Flagにより連打しても取引は1回だけ実行する
- Developer Test LabのEQUIPMENT / LOOTへ「アンコモン素材×3」「レア素材×3」
  「エピック素材×3」「合成画面を開く」を置き、異なる既存Templateを即投入できる
- `tests/equipment_merge_check.tscn`で異名Uncommon→Rare、Rare→Epic、混在/装備中/Lock/出力候補なしの
  無消費失敗、二重実行防止、3Slot UI、演出完了/Skip、結果即時装備、Run resetを確認する

### 23.7 開発構造とアイコン配置

- 新規Resource: `resources/equipment_data.gd`
- 新規Component/System: `components/equipment_component.gd`、
  `systems/equipment_drop_system.gd`、`systems/elite_affix_component.gd`、
  `systems/elite_hazard.gd`
- 新規scene: `entities/pickups/ground_equipment_item.tscn`、
  `ui/equipment/equipment_screen.tscn`
- アイコン配置先: `assets/items/weapons/`、`head/`、`body/`、`arms/`、
  `legs/`、`accessories/`。完成素材は64×64px、透過PNG、二値アルファ、最近傍表示とする
- 命名規則は`<slot>_<type>_<rarity>_<連番3桁>.png`。例:
  `weapon_sword_uncommon_001.png`、`accessory_relic_mythic_001.png`
- オリジナル生成素材はクロマキー除去後、`tools/equipment_icon_pipeline.py`で外接矩形を切り出し、
  54px以内へアスペクト比を保って最近傍縮小し、64×64px中央へ配置する。同スクリプトで
  サイズ・透明四隅・二値アルファを検証する
- 属性追加は属性JSON+必要なら再利用可能な発動Strategy、装備追加はtemplates.json、
  レアリティ調整はdrop_table.jsonを優先し、EnemyBasicやPlayerへ個別条件を増やさない

### 23.8 精鋭スポーンのPhysicsServer flush回避(2026年8月、不具合修正)

- 精鋭部屋の`Area2D.body_entered`シグナルはPhysicsServerが接触クエリを処理中に発火する。
  このコールバックから同期的にEnemyBasicを`add_child()`すると、EnemyBasicの`_ready()`で
  精鋭用にCollisionShapeを拡大・差し替える処理が実行され、Godotから
  `Can't change this state while flushing queries`として拒否される
- 症状は精鋭入室時だけ発生し、環境によって精鋭が表示されない、または物理形状の初期化が
  不完全になる。DataLoaderの精鋭Resource、精鋭部屋の割当、トリガー生成自体は正常だった
- `EliteRoomManager._on_body_entered()`では多重起動防止用のactive状態だけを即時記録し、
  `call_deferred()`で`_begin_elite_event()`へイベント通知と精鋭scene生成を送る。
  これにより次の安全なアイドル処理でCollisionShapeを初期化する
- 見えない壁は引き続き生成しない。精鋭出現条件、1〜2体の生成、属性付与、生存数管理、
  全滅報酬、装備ドロップ、通常Wave停止は変更しない
- 回帰テスト`tests/elite_spawn_regression_check.tscn`で、実Game sceneのArea2Dへ物理入室し、
  通常敵1体、属性付き精鋭2体、ボス1体の生成、見えない壁0個、部屋外への移動、
  精鋭死亡追跡と地面装備ドロップを確認する

### 23.9 オリジナル装備アイコン第1弾(25種、2026年8月)

- 第1弾は武器10種、頭3種、胴3種、腕3種、脚3種、アクセサリー3種の計25種
- `EquipmentDropSystem`は従来どおり`drop_table.json`でレアリティを先に抽選し、続いて
  `templates.json`から同じ`rarity`を持つ5つの専用デザインだけを候補にして1つ選ぶ。
  精鋭1体につき最低1個を保証し、50/30/15/4/1の抽選重みは維持する。Affix数・値域・特殊効果は
  23.4〜23.5および24章のハイブリッド仕様を適用する
- 各レアリティに5つの専用デザインを用意するため、レアリティと外見が食い違うフォールバックは
  行わない。該当テンプレートが0件なら警告を出して生成を中止し、誤った画像を表示しない

| レアリティ | 武器 | 防具・アクセサリー |
|---|---|---|
| Uncommon | 旅鉄の剣、旅人の短弓 | 革のスカウト帽、旅人の革服、斥候の手袋 |
| Rare | 月青の短剣、霜青の槍 | 蒼鋼の騎士兜、波紋の鎖帷子、風走りのブーツ |
| Epic | ルーン大剣、星術の杖 | 秘術師のローブ、魔紋の篭手、紫晶の指輪 |
| Legendary | 太陽炎の戦斧、不死鳥の弩 | 獅子王の兜、竜爪の篭手、陽輪の護符 |
| Mythic | 虚無の双爪、終焉の魔導書 | 虚空歩きの靴、星堕ちの脚甲、深淵の心核 |

Godot側の地面レアリティ演出は硬いPixel Plate + 非AA Outline + 少量Fragment方式とする。
リング・縦方向Loot Beam・柔らかいGlowは生成しない。Legendary/MythicほどFragment数とContrastを増やし、
素材画像にはGlow・Beam・パーティクルを焼き込まず、地面・インベントリ・装備済みスロットで
同じ画像を再利用する。

## 24. エリート・装備ハクスラ改善（2026年8月9日）

### 24.1 時間進行型の巡回エリート

- 専用部屋の精鋭生成、属性付与、撃破追跡、部屋報酬、装備ドロップは維持する
- `EliteRoomManager`は追加で`data/elite_affixes/spawn_curve.json`を読み、通常Waveと並行して
  1体の巡回エリートを床マスへ生成する。巡回個体は`elite_room_entered`を発火しないため、
  通常敵スポーンを停止せず、見えない壁や閉鎖イベントも生成しない
- 初回は90〜120秒。次回までの間隔は序盤0〜179秒=150〜180秒、
  中盤180〜419秒=120〜150秒、終盤420秒以降=90〜120秒
- 巡回予定時刻は経過秒の絶対時刻として保持する。ボス戦中または専用精鋭部屋の攻略中は生成だけを
  保留し、予定時刻そのものは停止しない。競合状態が解消した時点で期限超過分を再判定するため、
  ボス出現が多い実ゲームでも巡回エリート頻度が失われない
- 最終巡回生成から180秒をSoft Pity上限とする。Boss alive / Elite Room active / Elite alive中は
  同時生成しないが、解除後の次の安全な生成機会を優先する。スポーン失敗時は5秒後に再試行する
- 巡回個体はプレイヤーから200〜380pxの床マスへ生成し、通常Wave、Boss、Enemy Capとは
  独立して管理する。見えない壁、部屋封鎖、プレイヤー拘束は生成しない
- 既存の属性数カーブ（序盤1、中盤1〜2、終盤2〜3）を巡回個体にも共用する。
  将来は同JSONの時間帯を追加して出現頻度を調整できる
- `tests/elite_frequency_check.tscn`は実Managerと同じ絶対時刻/Soft Pityロジックで10分を検証する。
  5回の実測（seed 20260809〜20260813）は全て4体、平均4.00体/10分。生成時刻は順に
  `[96.70,265.00,387.91,519.52]`、`[111.49,270.52,405.85,533.79]`、
  `[91.81,265.22,395.07,525.95]`、`[92.24,265.00,385.64,510.63]`、
  `[95.32,265.00,407.36,565.00]`。加えて通常100 seedと25秒Boss競合窓付き100 seedの
  全ケースが3〜5体に収まることを確認する

### 24.2 Affixの型とレアリティ別範囲

固定値Affixは攻撃力、防御力、最大HP。割合Affixは移動速度、攻撃速度、
クリティカル率、クリティカルダメージとする。値域はすべて`drop_table.json`で管理する。

| レアリティ | 攻撃力 | 防御力 | 最大HP | 移動速度 | 攻撃速度 | Crit率 | Critダメージ |
|---|---:|---:|---:|---:|---:|---:|---:|
| Uncommon | +5〜10 | +3〜6 | +25〜45 | +2〜4% | +2〜4% | +1〜2.5% | +6〜10% |
| Rare | +10〜20 | +6〜12 | +45〜80 | +3.5〜6% | +3.5〜6% | +2〜4% | +10〜16% |
| Epic | +20〜35 | +12〜20 | +70〜120 | +5〜8% | +5〜8% | +3.5〜6% | +15〜24% |
| Legendary | +30〜50 | +18〜30 | +110〜170 | +7〜11% | +7〜11% | +5〜8% | +22〜34% |
| Mythic | +45〜70 | +28〜45 | +160〜240 | +9〜14% | +9〜14% | +7〜11% | +30〜45% |

Affix数はUncommon=1、Rare=2、Epic=3、Legendary=3+特殊効果1、
Mythic=4+強力な特殊効果1で固定する。テンプレートの`stats`候補から重複なしで選ぶ。

### 24.3 ステータス計算順序

- 攻撃力: `（職業基礎攻撃力 + レベル固定攻撃力 + 装備固定攻撃力）× 既存強化倍率 × 条件付き特殊倍率`
- レベル成長は旧+8%/Lvから固定`+1/Lv`へ移し、`StatModifierComponent`で保持する
- 防御力: `max(受ける生ダメージ - 装備固定防御力, 1) × 既存割合軽減 × アクティブスキル軽減`
- 最大HP: 職業基礎値・既存固定成長へ装備固定HPを差分加算する。装備解除時は差分を戻し、
  現在HPが新最大値を超えた場合だけクランプする
- Crit率・Critダメージ・攻撃速度・移動速度は既存割合層へ加算する
- 装備変更のたびに6スロットをゼロから再集計し、同じ値を重複加算しない

### 24.4 Legendary / Mythic特殊効果

`EquipmentData.special_effect_values`へドロップ時のレアリティ別実数値を保持する。
同じ効果を複数装備した場合は最も強い値だけを採用する。

| 効果 | Legendary | Mythic |
|---|---|---|
| 命喰らい `kill_heal` | 敵撃破時HP+8 | 敵撃破時HP+15 |
| 守護の残響 `negate_hit` | 10%で被弾無効 | 16%で被弾無効 |
| 窮地の力 `low_hp_power` | HP30%以下で攻撃+20% | HP35%以下で攻撃+35% |

### 24.5 キャラクター・装備画面

- InputMap actionは`character_screen`。初期入力C / gamepad Y。Iは互換入力
- C/Yで開くと`GameManager.open_modal()`でワールドを停止し、UIはPROCESS_MODE_ALWAYSで動く。
  C/YまたはESCで閉じ、`close_modal()`で他モーダルがなければゲームを再開する
- 1600×900基準。左パネル中央へ現在キャラクターの既存SpriteFramesの現在frameを表示し、
  周囲へ武器・頭・胴・腕・脚・アクセサリーの6スロットを配置する
- 下部にHP、攻撃力、防御力、攻撃速度、移動速度、Crit率、Critダメージを表示する。
  総合戦闘力は導入しない
- 右側は既存ラン内Inventoryを再利用し、下側の固定比較パネルに現在→候補、↑/↓/=、
  固定値と%を区別して表示する。「装備する」「装備を外す」で即時再集計・再描画する
- `tests/character_screen_layout_check.tscn`で1600×900、6スロット、キャラクター、
  ステータス、Inventory、比較パネルがViewport内に収まることを検証する

## 25. Equipment System / Attack VFX System 正式仕様（2026年8月9日）

本章は23〜24章の装備仕様をデータ構造・計算・拡張手順まで含めて正式化し、現行の
Attack VFX実装を一つのシステムとして定義する。ここでいう`EquipmentData`（精鋭から
落ちるラン内装備）と`WeaponData`（欠片合成で得る完成武器）は別システムである。

### 25.1 用語と責務の境界

| 用語 | 識別子 | 責務 |
|---|---|---|
| Equipment | `EquipmentData.template_id` / `instance_id` | ラン内Inventory、6スロット、Affix、特殊効果を保持する |
| Special Effect | `EquipmentData.special_effects`内のID | 「何が、いつ起こるか」を決めるGameplay識別子 |
| Fusion Weapon | `WeaponData.id` | 欠片合成武器の攻撃値・攻撃間隔・`vfx_theme_id`を持つ |
| VFX Effect ID | `EffectThemeData.id` | 「攻撃・命中をどう見せるか」を決めるVisual識別子 |
| Element Modifier | `GameManager.active_element_ids` / `element_stacks` | ラン中にAttack Typeへ重ねる最大2属性・各Lv3のLoadout。`active_element_id`は主属性互換値。Fusion用欠片とは別状態 |
| Active Skill style | `ActiveSkillVFX.style` | Spaceスキルの局所図形を選ぶ内部Visual識別子。Effect IDとは別 |

`Special Effect ID`と`VFX Effect ID`は同じ文字列へ統合しない。Gameplay側はVFXが
存在しなくても成立し、VFX側はダメージ値・ドロップ抽選・撃破判定を変更しない。

### 25.2 Equipment基本仕様

1. 全Enemy死亡時に`EventBus.enemy_drop_requested(position, is_elite, is_boss)`を発行する。
2. `EquipmentDropSystem`は通常敵2%、強敵/Elite 4%で抽選し、Bossは最低1個を確定する。
   BossはROOM 1〜11 / 12〜23 / 24〜35 / 36のPhase別Rarity Tableを使う。
3. `drop_table.json`でレアリティを抽選し、同レアリティの`templates.json`候補から
   テンプレートを1つ選び、Affixと特殊効果の値をロールして`EquipmentData`へ保存する。
4. `GroundEquipmentItem`を安全な床マスへ生成する。自動取得・時間消滅は行わない。
5. プレイヤーが72px以内でE / gamepad Xを押すと最寄りの1個をInventoryへ加える。
6. 戦闘外のCLEAR/REWARD/次ROOM準備中にC / gamepad Y（Iは互換入力）でCharacter Screenを開き、同スロットの現装備と比較し、
   装備・交換・解除する。取得だけではステータスへ反映しない。
7. Inventory、装備中アイテム、装備補正はラン中だけ有効で、`run_ended`時に全て消去する。
   `SaveManager`へ保存せず、恒久解放・メタ通貨のセーブ形式も変更しない。

装備スロットは`weapon`、`head`、`body`、`arms`、`legs`、`accessory`の6種類で、
各スロットへ1個だけ装着できる。交換前の装備もInventoryには残る。

#### レアリティ仕様

| Rarity | 色 | Weight | 基本Affix | 特殊効果 | Range | 地面表示 / Rarity VFX | Attack VFXとの関係 |
|---|---|---:|---:|---|---|---|---|
| Uncommon | 緑 | 50 | 1 | なし | 24.2表 | Pixel Plate + 2粒 | なし |
| Rare | 青 | 30 | 2 | なし | 24.2表 | Pixel Plate + 3粒 | なし |
| Epic | 紫 | 15 | 3 | なし | 24.2表 | Pixel Plate + 4粒 | なし |
| Legendary | 橙 | 4 | 3 | 1個 | 24.2表 | Pixel Plate + 6粒 | 現行特殊効果はVFX IDを持たない |
| Mythic | 赤 | 1 | 4 | 1個（高い値） | 24.2表 | Pixel Plate + 9粒 | 現行特殊効果はVFX IDを持たない |

Weightはドロップ成立後の相対重みで合計100。64px元画像の不透明画素範囲を、プレイヤー本体の
70〜100%（目標82%、24〜42px）へ正規化する。巨大リング、Loot Beam、柔らかいGlowは生成しない。
Ground EquipmentのPixel PlateはAttack VFX Effect IDではない。カード、浮遊、全画面フラッシュ、
Trailは使用しない。

### 25.3 Affix SystemとEquipment Stats

Affixは装備インスタンスへ付くステータス補正1件を指す。候補語彙はテンプレートごとの
`stats`、レアリティ別値域は`data/equipment/drop_table.json`の`stat_ranges`で定義する。

| 型 | Affix ID | 単位 / 保存方式 |
|---|---|---|
| 固定値 | `attack_power`、`defense`、`max_hp` | 実数をロール後に整数へ丸めて`EquipmentData.stats`へ保存 |
| 割合 | `crit_rate`、`crit_damage`、`attack_speed`、`move_speed` | 0.001刻みの小数（0.10 = 10%）で同Dictionaryへ保存 |

生成時はテンプレートの`stats`配列を複製してshuffleし、先頭からレアリティのAffix数だけ
採用する。このため同一アイテム内で同じAffixは重複しない。候補数が必要数より少ない場合は
候補数が上限となる。装備間の同種Affixは6スロット分を加算する。Special Effectだけは
同じIDを複数装備しても加算せず、各パラメーターの最も強い値を採用する。

標準の自動攻撃・Projectile経路の攻撃値は次の順序で計算する。

```text
Flat Attack = Character / Weapon Base Damage
            + StatModifierComponent Level Flat Bonus（1Lvごとに+1、Lv1は+0）
            + Equipment Flat Attack

Damage = Flat Attack
       × Upgrade / Character Percentage Multiplier
       × low_hp_power Conditional Multiplier
       × Melee-only Multiplier（該当時）
       × Critical Multiplier（Critical時のみ）
```

- Crit率は基礎率 + レベル補正 + 通常強化補正 + Equipment `crit_rate`。Crit倍率は
  基礎Crit倍率 + Equipment `crit_damage`。VFXはこの計算へ関与しない。
- 攻撃速度は攻撃間隔へ反映し、基本形は
  `base_interval × max(0.2, 1 - upgrade短縮率 - equipment_attack_speed) × 一時倍率`
  とする。装備由来の集計値は0.7でclampする。
- 移動速度は`base_speed × 状態異常倍率 × 既存強化倍率 × (1 + equipment_move_speed)`。
- 防御は`max(生ダメージ - equipment_defense, 1) × 既存割合軽減 × Active Skill軽減`。
- 最大HPは装備合計の前回値との差分だけを`HealthComponent`へ加減する。増加分は現在HPにも
  加算し、減少時は新しい最大HP以下へclampする。
- 多くのSpaceスキルは`Base + Level Flat + Equipment Flat`へスキル固有倍率を掛ける。
  既存スキルごとの通常強化倍率の扱いは19.10を優先し、全スキルが同じ乗算層を通るとは
  仮定しない。

`EquipmentComponent._recalculate_bonuses()`は装備、交換、解除のたびに6スロットをゼロから
再集計する。`run_ended`ではInventoryと全スロットを空にした後に同じ再計算を行う。
Inventoryへ拾っただけの時点では再計算しない。

#### 新しいAffixの追加手順

1. 固定値か割合か、IDと表示単位を決める。
2. 全レアリティの値域を`data/equipment/drop_table.json/stat_ranges`へ追加する。
3. 付与可能なテンプレートの`data/equipment/templates.json/stats`へIDを追加する。
4. `EquipmentComponent`で集計先のComponentへ反映し、解除・交換・ラン終了時も戻るようにする。
5. `ui/equipment/equipment_screen.gd`の表示名、固定値/割合表示、比較表示へ追加する。
6. 生成値域、重複なし抽選、再計算、UI比較のテストと本仕様書を同じ作業で更新する。

### 25.4 Equipment Special Effect

| Special Effect ID | 発動条件 | Legendary | Mythic | Gameplay実装 | 現行VFX Effect ID |
|---|---|---:|---:|---|---|
| `kill_heal` | `enemy_died`受信時 | HP+8 | HP+15 | `EquipmentComponent._on_enemy_died()` | なし |
| `negate_hit` | 被弾前の確率抽選 | 10%無効 | 16%無効 | `HealthComponent.apply_damage()` | なし |
| `low_hp_power` | 攻撃計算時に現在HP比を判定 | HP30%以下で+20% | HP35%以下で+35% | `PlayerUpgradesComponent.get_equipment_conditional_damage_multiplier()` | なし |

特殊効果候補とレアリティ別実数値は`drop_table.json/special_effects`、付与されたIDは
`EquipmentData.special_effects`、その装備固有の値スナップショットは
`EquipmentData.special_effect_values`へ保存する。現在はLegendary / Mythic生成時に
グローバル候補から1つランダム選択し、特定テンプレートへ固定する仕組みはない。

正式な拡張フローは次のとおりとする。

```text
EquipmentData
  -> Special Effect ID
  -> Gameplay側の発動条件判定
  -> Gameplay Effect（回復、無効化、攻撃Object生成など）
  + 省略可能なVFX Request（別のVFX Effect ID）
  -> EffectThemeManager等のVisual実行役
```

将来、特殊効果へVFXを加える場合も、Special Effect ID自体をVFX Managerへ渡さない。
発動処理が明示的にVFX Effect IDを要求し、VFX失敗・非表示設定でもGameplay結果を維持する。

### 25.5 Attack VFX Systemの目的とアーキテクチャ

Attack VFX Systemは、攻撃開始・命中・属性・Spaceスキル・Critical数値・画面演出を、
ダメージ計算や当たり判定から分離して表示する合成システムである。通常攻撃のPixel Sprite
Animationは`AttackVFXManager`へ集約し、既存の属性ThemeやSpaceスキル演出と組み合わせる。

| 実行役 | 役割 |
|---|---|
| `AttackVFXManager` | Attack Typeと現在Elementを合成し、攻撃開始・確定Hit・居合軌跡の6フレームSpriteを実ゲームWorldへ生成 |
| `EffectThemeManager` | `EffectThemeData.id`を解決し、通常/強化Particle、Line2Dを再生 |
| `ElementCombatSystem` | 確定したベースDamageから属性別の独立追加Damageと雷の敵間連鎖を計算。Visual Resourceとは分離 |
| `ActiveSkillVFX` | Spaceスキルの局所図形をscript drawingで一時描画 |
| `DamageNumberManager` | 通常・Critical・回復・属性別数値を36個のPoolから再生 |
| `ScreenEffects` | Shake、Hit Stop、Slow Motion、限定的な全画面Flash / Cut-in |
| `VFXPoolManager` | 大量撃破Burstを6個のPoolから再生 |

```text
Player / Enemy / Equipment / WeaponData
                  |
              Attack Logic
          +-------+------------------+
          |                          |
  Damage / Hitbox / Hurtbox      attack_vfx_requested / Hit VFX Request
          |                          |
  HealthComponent / Event       Visual実行役
                                     |
                          Effect ID / style / API
                                     |
                       Effect Scene / Draw / Tween
                                     |
                              Visual Effect
```

ダメージ、Critical抽選、撃破、報酬、Equipment Special EffectはGameplay側で先に確定する。
VFXは確定結果を受けて表示するだけで、Damageを直接計算・適用しない。現行
`EffectThemeData`には旧拡張用の`status_effect` / `status_duration`がありManagerにも
状態付与処理が残るが、現行20テーマは全て未設定である。新規Gameplay効果はこのVisual用
hookへ追加せず、Gameplay Componentへ実装する。将来整理する際は互換性を確認して分離する。

#### 呼び出し経路

- `DataLoader._load_effect_themes()`が`effects/themes/*.tres`を走査し、`id`をkeyに保持する。
- `DataLoader._load_attack_vfx_effects()`が`effects/attack_vfx/*.tres`を走査し、Pixel Effect IDを保持する。
- 攻撃開始: `WeaponManagerComponent`が実際の職業攻撃開始時に
  `attack_vfx_requested(character_data, origin, direction)`を1回発火し、常設
  `AttackVFXManager`が`attack_pattern_id`をPixel Effect IDへ解決する。色は現在Elementではなく
  `CharacterData.vfx_theme_id`を使い、Player周囲へ属性取得/Lv/Fusion演出を混入させない。
- Projectile: `Projectile.on_hit()` → `play_weapon_hit(WeaponData.vfx_theme_id, ...)`。
- 近接Hit: `MeleeHit.on_hit()` → `play_weapon_hit(CharacterData.vfx_theme_id, ...)`。
- 即時AoE: `AttackPatternBase.apply_direct_damage()`がDamage適用・Event発行後に同APIを呼ぶ。
- Spaceスキル: `ActiveSkillComponent._damage_enemy()`がDamage適用後にキャラクターテーマを要求し、
  発動範囲の予告・余韻には別途`ActiveSkillVFX`を使う。
- 全命中経路はCritical確定値も`play_weapon_hit()`へ渡す。同APIは属性Theme解決前に
  `AttackVFXManager.play_hit()`を呼ぶため、Themeが欠けても中立Pixel Hitは表示される。

### 25.6 Effect Data / Scene / Asset / Lifetime

`AttackVFXData`は`id`、Sprite Sheet、フレーム数、FPS、Lifetime、プレイヤー比のVisual Size、
方向追従、発生位置比を持つ。`AttackVFXManager`が`SpriteFrames`を生成・キャッシュし、
`AnimatedSprite2D`で実ゲームWorldへ再生する。

`EffectThemeData`は従来どおり`id`、表示名、`combo_ids`、通常/強化Particle Scene、色、遅延、
beam / chain / absorbのVisual flagを持つ。属性ThemeはPixel Attack/Hitの補助層である。

`ElementVFXData`は`element_id`、表示名、attack tint、居合Trail/Hit、居合残像alpha倍率と
省略可能なProjectile/ChainそれぞれのEffect ID、Sprite Sheet、FPS、Lifetime、Visual Ratioを持つ。
Damage、Critical、状態異常、追加Drop等のGameplay値は持たない。`DataLoader._load_element_vfx_effects()`が
`effects/element_vfx/*.tres`を走査し、`element_id`で登録する。

- Pixel Sprite Sheetは各384×64px、64×64pxを横6フレーム。透明PNG、Nearest filter、非Loop
- `attack_slash`: 16fps / 0.45s / プレイヤー高1.10倍 / 方向追従。Resource互換用に保持するが、
  通常近接攻撃の実Runtimeでは生成しない
- `attack_projectile`: 18fps / 0.40s / 0.95倍 / 方向追従
- `attack_pulse`: 14fps / 0.50s / 1.20倍 / 非方向
- `hit_normal`: 20fps / 0.36s / 0.48倍 / 非方向
- `hit_critical`: 18fps / 0.42s / 0.90倍 / 非方向 + 0.10秒の局所Flash
- Animation完了時に`queue_free()`し、WeakRefを用いたLifetime保険タイマーでも残存を防ぐ

- Theme Particleは全て`GPUParticles2D`、`one_shot=true`、embedded
  `ParticleProcessMaterial`で描画し、外部Particle Texture / Sprite Sheetは使わない。
- 通常/強化はキャラクターレベル3未満/3以上で切り替える。
- Particle nodeは`particles.lifetime + 0.3秒`後に`queue_free()`する。
- Beam / Chainの`Line2D`はTween完了時、Active Skill図形とAfterimageはTween完了時、
  Flash / Cut-inのCanvasLayerもTween完了時に`queue_free()`する。
- Projectile本体は3.0秒または命中で破棄する。職業Projectileは24×24の`GradientTexture2D`を
  加算Glowとして共通矢画像の背面に置き、職業・武器本来のThemeを使う。Fusion武器
  （`required_fragment_ids`あり）は共通矢を隠し、武器Theme Glowだけを表示する。
  現在ElementやElement Lv変更で職業Projectileを別Spriteへ置換しない
- Boss Novaは同Sceneの3.0秒Lifetime/Collisionを再利用するがPlayer Element Modifierを
  適用せず、敵弾用のcollision layer・紫紅色Visualとして扱う
- Attack Hit用Shaderは現在ない。`effects/shaders/sprite_outline.gdshader`は主にBoss輪郭用で、
  Attack Effect IDへ紐付かない。
- 現在Poolするのは大量撃破Particle 6個とDamage Number 36個。Theme Hit Particle、
  Active Skill図形、Line2D、Flashは都度生成・自動破棄する。

### 25.7 VFX Effect ID一覧（属性Theme 20件 + Pixel Attack/Hit 5件 + Element Modifier 12件）

`EquipmentData`は現時点でどのIDも直接参照しない。属性Theme IDとPixel Attack/Hit IDは
別Registryだが、どちらもVisual専用でGameplay値を変更しない。

#### Pixel Attack / Hit ID

| Effect ID | 6-frame Sprite Sheet | 接続元 / 対象 |
|---|---|---|
| `attack_slash` | `assets/vfx/attack/attack_slash_6f.png` | Resource互換/単体Preview用。通常近接の実Runtime生成は抑止 |
| `attack_projectile` | `assets/vfx/attack/attack_projectile_6f.png` | `piercing_thrust`、`spread_shot`、`homing_bolt` |
| `attack_pulse` | `assets/vfx/attack/attack_pulse_6f.png` | `self_pulse`、`holy_pulse_heal`、`summon_minion` |
| `hit_normal` | `assets/vfx/attack/hit_normal_6f.png` | Projectile / Melee / direct AoEの通常命中。ただしLightning Themeの通常近接では黄色表示を避けるため生成しない |
| `hit_critical` | `assets/vfx/attack/hit_critical_6f.png` | 同じ確定命中のCritical。通常より大きい局所Flash付き。Lightning Themeの通常近接では生成しない |

#### 現在属性Element Modifier ID

| Element ID | Iai Trail Effect / Asset | Hit Effect / Asset | Projectile / Chain |
|---|---|---|---|
| `element_fire` | `vfx_iai_fire_trail` / `assets/vfx/elements/iai_fire_trail_6f.png` | `vfx_fire_hit` / `assets/vfx/elements/fire_hit_6f.png` | なし |
| `element_ice` | `vfx_iai_ice_trail` / `assets/vfx/elements/iai_ice_trail_6f.png` | `vfx_ice_hit` / `assets/vfx/elements/ice_hit_6f.png` | なし |
| `element_lightning` | `vfx_iai_lightning_trail` / `assets/vfx/elements/iai_lightning_trail_6f.png` | `vfx_lightning_hit` / `assets/vfx/elements/lightning_hit_6f.png` | `vfx_lightning_projectile` / `lightning_projectile_6f.png`、`vfx_lightning_chain` / `lightning_chain_6f.png` |
| `element_light` | `vfx_iai_light_trail` / `assets/vfx/elements/iai_light_trail_6f.png` | `vfx_light_hit` / `assets/vfx/elements/light_hit_6f.png` | なし |
| `element_dark` | `vfx_iai_dark_trail` / `assets/vfx/elements/iai_dark_trail_6f.png` | `vfx_dark_hit` / `assets/vfx/elements/dark_hit_6f.png` | なし |

上記12 Effect IDは`EffectThemeData.id`ではなく`ElementVFXData`内のVisual IDである。
全Sprite Sheetは384×64px、64px×6フレーム、透明PNG、Nearest。ProjectileだけLoopし、
Trail/Hit/Chainは非Loopで自動破棄する。

| Character | attack_pattern_id | 攻撃開始Effect ID | 命中Effect ID |
|---|---|---|---|
| Soldier | `melee_arc` | なし（`attack_slash`生成抑止） | `hit_normal` / `hit_critical` |
| Swordsman | `melee_arc` | なし（`attack_slash`生成抑止） | 黄色Pixel Hitなし。Lightning属性Hit/強化演出は維持 |
| Armored Axeman | `wide_cleave` | なし（`attack_slash`生成抑止） | 黄色Pixel Hitなし。Lightning属性Hit/強化演出は維持 |
| Knight | `charge_dash` | なし（`attack_slash`生成抑止） | `hit_normal` / `hit_critical` |
| Lancer | `piercing_thrust` | `attack_projectile` | `hit_normal` / `hit_critical` |
| Archer | `spread_shot` | `attack_projectile` | `hit_normal` / `hit_critical` |
| Wizard | `homing_bolt` | `attack_projectile` | `hit_normal` / `hit_critical` |
| Knight Templar | `self_pulse` | `attack_pulse` | `hit_normal` / `hit_critical` |
| Priest | `holy_pulse_heal` | `attack_pulse` | `hit_normal` / `hit_critical` |
| Necromancer | `summon_minion` | `attack_pulse` | Minion固有処理。現時点で直接Hit IDなし |

#### 単属性ID

| Effect ID | 用途 / 使用キャラクター・攻撃 | 使用WeaponData / Equipment | Scene / Asset | Animation / Lifetime | Particle / Trail |
|---|---|---|---|---|---|
| `fire` | 炎Hit。Soldierの`melee_arc`および同キャラのDamage Hit | 単体完成武器なし / Equipmentなし | `fire_hit.tscn`、`fire_hit_enhanced.tscn`。embedded material | 通常0.5s。Lv3+は通常0.5s後、0.4s遅延して強化0.6s | 有 / 無 |
| `ice` | 氷Hit。Lancer `piercing_thrust`、Archer `spread_shot`および両キャラのDamage Hit | 単体完成武器なし / Equipmentなし | `ice_hit.tscn`、`ice_hit_enhanced.tscn`。embedded material | 通常0.6s、Lv3+ 0.4s | 有 / 無 |
| `lightning` | 雷Hit。Swordsman `melee_arc`、Armored Axeman `wide_cleave`および両キャラのDamage Hit | 単体完成武器なし / Equipmentなし | `lightning_hit.tscn`、`lightning_hit_enhanced.tscn`。embedded material | 通常0.25s、Lv3+ 0.35s。Lv3+ Chain Lineは0.25s、最大5本 | 有 / 無 |
| `light` | 聖/光Hit。Knight `charge_dash`、Priest `holy_pulse_heal`、Knight Templar `self_pulse`および各Damage Hit | 単体完成武器なし / Equipmentなし | `light_hit.tscn`、`light_hit_enhanced.tscn` + Line2D | 通常0.3s、Lv3+ 0.35s。Beam Lineは0.2s、幅3/6 | 有 / 無 |
| `dark` | 闇Hit。Wizard `homing_bolt`。Necromancerでは`summon` Active Skill図形の色参照（Minion HitはThemeを要求しない） | 単体完成武器なし / Equipmentなし | `dark_hit.tscn`、`dark_hit_enhanced.tscn`。embedded material | 通常0.8s、Lv3+ 0.7s。Lv3+は0.15s後に発射元へ追加Particle | 有 / 無 |

Particle数は順に、fire 20/48、ice 18/40、lightning 20/48、light 16/32、dark 24/36
（通常/強化）。上表のLifetimeはParticleの設定値で、node破棄は各値+0.3秒後。

#### 複合ID

複合IDは専用Scene / Asset / Animationを持たず、表の構成IDのSceneを全て再生する。
Lifetimeは構成要素依存（最長はdark通常0.8s、fire強化は0.4s遅延後0.6s）。全てParticle有、
Trail無、使用キャラクターの直接割当無、`EquipmentData`からの参照無である。

| Effect ID | 用途 / 構成 | 使用WeaponData | Scene / Asset / Animation |
|---|---|---|---|
| `steam` | 蒸気Hit（fire + ice） | `steam_burst_weapon` | 構成2テーマを同時再生 |
| `thunder_flame` | 雷炎Hit（lightning + fire） | `thunder_flame_weapon` | 構成2テーマを同時再生 |
| `holy_flame` | 聖炎Hit（fire + light） | `holy_flame_weapon` | 構成2テーマを同時再生 |
| `hellfire` | 業炎Hit（fire + dark） | `hellfire_weapon` | 構成2テーマを同時再生 |
| `frost_thunder` | 凍雷Hit（ice + lightning） | `frost_thunder_weapon` | 構成2テーマを同時再生 |
| `holy_frost` | 聖氷Hit（ice + light） | `holy_frost_weapon` | 構成2テーマを同時再生 |
| `shadow_frost` | 冥氷Hit（ice + dark） | `shadow_frost_weapon` | 構成2テーマを同時再生 |
| `holy_thunder` | 聖雷Hit（lightning + light） | `holy_thunder_weapon` | 構成2テーマを同時再生 |
| `shadow_thunder` | 冥雷Hit（lightning + dark） | `shadow_thunder_weapon` | 構成2テーマを同時再生 |
| `purity_corruption` | 浄化と侵蝕Hit（light + dark） | `purity_corruption_weapon` | 構成2テーマを同時再生 |
| `elemental_triad` | 三大元素Hit（fire + ice + lightning） | `elemental_triad_weapon` | 構成3テーマを同時再生 |
| `trinity_flame` | 光闇業炎Hit（fire + light + dark） | `trinity_flame_weapon` | 構成3テーマを同時再生 |
| `lunar_frost` | 月光氷刃Hit（ice + light + dark） | `lunar_frost_weapon` | 構成3テーマを同時再生 |
| `tetra_elemental` | 四大天啓Hit（fire + ice + lightning + light） | `tetra_elemental_weapon` | 構成4テーマを同時再生 |
| `pentaelemental` | 五行天魔Hit（fire + ice + lightning + light + dark） | `pentaelemental_weapon` | 構成5テーマを同時再生 |

#### Effect IDではないVisual識別子

`ActiveSkillVFX.style`の実装済み値は`aura`、`slash`、`rain`、`charge`、`impact`、
`shield`、`counter`、`execution`、`sanctuary`、`chains`、`holy_burst`、`time`、
`summon`、`burst`。全てscript drawingで、scale 0.35→1.15を0.28秒、alphaを0.36秒で
fadeして破棄する。これらを`EffectThemeData.id`としてDataLoaderへ登録してはならない。

### 25.8 VFX Visual LanguageとVisual Priority

| 種別 | デザイン規約 |
|---|---|
| 斬撃 | 高速、sharp、短い残像。進行方向と攻撃arcを即座に読めること |
| 炎 | 揺れ、外向きに広がり、火の粉が散る。橙〜赤を基調にする |
| 氷 | 鋭く直線的で、白〜水色の破片が砕ける。現行はSlowを付与しない |
| 雷 | 黄色/紫、高速・不規則・瞬間的。連鎖線は局所表示に限定する |
| 闇 | 紫〜黒、吸収、残像、煙状の消滅。発射元へ戻る動きを許容する |
| 聖/光 | 白/金、直線的、短い局所発光。通常Hitで全画面Flashを使わない |
| 物理 | 短く重く、接触点のImpactを優先。長時間画面を覆わない |

Visual Priorityは「通常攻撃 < 強攻撃 < Skill < Legendary Special < Mythic Special」。
Priorityを上げる方法は局所的なScale、粒子数、余韻、補助線、色コントラストを段階的に
増やすことであり、無条件の全画面Flashや長時間Shakeではない。どのPriorityでも敵本体、
Enemy Projectile、Elite属性表示、Boss、Boss Telegraph、Ground EquipmentのPixel Plateを隠さない。
現行Equipment SpecialにはAttack VFXがないため、Legendary / Mythic Attack Priorityは
将来実装枠である。Ground表示だけは25.2の差を用いる。

### 25.9 Hit Effect / Critical / Hit Stop / Screen Shake

| Hit種別 | Effect ID / Scale | Lifetime | Flash | Particle | Hit Stop |
|---|---|---|---|---|---|
| Normal Hit | `hit_normal`、プレイヤー見た目高0.48倍 + 攻撃元Theme。Lightning通常近接は黄色Sprite/基底Particleを抑止 | 0.36s + Theme値 | なし | 6-frame Sprite + Theme（Lightning通常近接を除く） | なし |
| Critical Hit | `hit_critical`、プレイヤー見た目高0.90倍。Damage Numberも拡大。Lightning通常近接は黄色Sprite/基底Particleを抑止 | 0.42s + 数値0.6s | 0.10s局所Flash | 6-frame Sprite + Theme（Lightning通常近接を除く） | なし |
| Element Hit | 現在属性は`vfx_fire_hit` / `vfx_ice_hit` / `vfx_lightning_hit` + 対応Theme。Fusion武器は従来Theme | 27章 | なし | 6-frame Sprite + Theme | なし |
| Heavy Hit | 汎用専用IDは未実装。Space Skill style + 命中Themeを使用 | style 0.36s + Theme値 | なし | Theme分のみ | Space共通0.08s |

Critical DamageはGameplay側で計算し、`EventBus.damage_dealt(amount, position, is_critical)`の
確定値をDamage Numberと`EffectThemeManager.play_weapon_hit(..., is_critical)`へ渡す。
Critical Visualはダメージを再計算しない。`hit_critical`はParticleだけではなく形状が変化する
6フレームSprite Animationであり、通常Hitより大きく、命中地点だけを短く発光させる。
物理の通常/会心数値は従来どおり白/赤大文字を維持する。属性追加Damageは別の小型数値として
火=赤橙、氷=白水色、雷=黄〜青紫で表示し、属性側へ会心拡大は適用しない（詳細は28章）。

Hit Stopは通常攻撃・通常Critical・単純な属性Hitでは採用しない。現行採用箇所は以下。

| 対象 | 時間 | 条件 |
|---|---:|---|
| Spaceスキル共通発動 | 0.08s | 有効スキルが発動しCooldownを開始した時 |
| 15体/2秒のMass Kill | 0.08s | MassKillTracker成立時 |
| Super Fusion | 0.30s | 3属性以上の完成時 |
| Boss出現 | 0.30s | Boss生成演出時 |

`ScreenEffects.hit_stop()`は`Engine.time_scale=0.05`と実時間Timerを使う。現在は重複要求の
統合・Cooldownがなく、同時呼び出しが競合し得るため、高頻度Hitへ追加しない。大量Hitでは
攻撃ごとに呼ばず、Mass Kill等の集約イベント1回だけにする。

Screen Shakeは通常攻撃では使用しない。Spaceスキル=強度7/0.22s、Mass Kill=8/0.30s、
精鋭部屋報酬=10/0.40s、Boss死亡=14/0.50s。`screen_shake_enabled=false`で無効化可能。
Boss出現はShakeではなく暗赤の全画面Flash（0.35s）+ Hit Stop、Boss TelegraphはBoss spriteの
赤/白明滅で、どちらもAttack VFX Effect IDではない。将来OFF設定では現在のquality設定を
UI導線から使う。

### 25.10 Legendary / MythicとVFXの連携規約

現行3特殊効果には専用VFX Effect IDがなく、Gameplayだけが発動する。これは欠落ではなく
現在の実装状態である。将来VFXを付ける場合の正規フローは次とする。

```text
Legendary / Mythic Equipment
  -> Special Effect ID
  -> 発動条件判定（Gameplay）
  -> Gameplay結果を確定
       + 回復 / 無効化 / 補正
       + 必要なGameplay Object / Hitbox
  -> 別フィールドまたは発動定義からVFX Effect IDを要求
  -> Visual Effect
  -> Hitした場合はHitbox / HealthがDamage処理
  -> 確定Hit情報を受けてHit Effectを表示
```

VFX SceneへDamage値、発動確率、撃破判定を持たせない。VFX IDが不正、Particle品質OFF、Poolが
満杯でもGameplay Effectは失敗させない。Legendaryは通常Skillを超える局所強調、Mythicは
Legendaryより一段強い局所強調を許可するが、Boss Telegraph等の可読性を優先する。

### 25.11 Elite撃破からEquipment / VFXまでの完全フロー

```text
Elite撃破
  -> EventBus.enemy_drop_requested
  -> EquipmentDropSystem（100%成立、最低1個。Rarity/Affix/Specialを生成）
  -> GroundEquipmentItem
  -> Visual Bounds正規化Icon / 硬いPixel Plate / 非AA Outline / 上位local Particle
  -> E / gamepad Xで取得
  -> EquipmentComponent.inventory
  -> C / gamepad Y（I互換）のCharacter Screen
  -> 同slot比較
  -> Equip / Replace
  -> 6slotを再集計しEquipment Stats反映
  -> Legendary / MythicならSpecial Effect IDを有効化
  -> AttackまたはEvent
  -> Special Effect条件判定
  -> Gameplay Effect
  -> （現行はなし。将来は独立したVFX Effect IDをrequest）
  -> Attack LogicのDamage / Hitbox
  -> CharacterData.attack_pattern_id + GameManager.active_element_ids / element_stacks
  -> WeaponManager.attack_vfx_requested -> AttackVFXManager -> 職業本来のAttack Type / Theme
  -> 確定Hit -> HealthComponent（物理）+ ElementCombatSystem（属性別追加Damage / 雷連鎖）
  -> EffectThemeManager / AttackVFXManager -> Pixel Hit + Element Hit Sprite + 対応Theme
  -> DamageNumberManager -> 物理/Critical数値 + 属性別の独立数値
```

Equipmentを装備しても`CharacterData.vfx_theme_id`や`WeaponData.vfx_theme_id`は上書きしない。
現行装備は攻撃Themeを変更せず、ステータスと3特殊効果だけを提供する。

### 25.12 ファイル構成

#### Equipment関連

| 種別 | Path / 役割 |
|---|---|
| Resource | `resources/equipment_data.gd`（ラン内装備instance） |
| Data | `data/equipment/templates.json`（名称、slot、rarity、icon、Affix候補） |
| Data | `data/equipment/drop_table.json`（Drop率、Weight、Affix数/Range、Special） |
| Component | `components/equipment_component.gd`（Inventory、6slot、再計算、Special集計） |
| System | `systems/equipment_drop_system.gd`（精鋭Drop、生成、床位置） |
| Ground Scene | `entities/pickups/ground_equipment_item.tscn` / `.gd` |
| UI Scene | `ui/equipment/equipment_screen.tscn` / `.gd` |
| Assets | `assets/items/{weapons,head,body,arms,legs,accessories}/`（64×64透過PNG） |
| Tests | `tests/equipment_integration_check.tscn`、`character_screen_layout_check.tscn`、`elite_spawn_regression_check.tscn` |

#### VFX関連

| 種別 | Path / 役割 |
|---|---|
| Resource class | `resources/effect_theme_data.gd` |
| Pixel Resource class | `resources/attack_vfx_data.gd` |
| Element Resource class | `resources/element_vfx_data.gd` |
| Effect Data | `effects/themes/*.tres`（Effect ID、Scene参照、色、combo、Visual flag） |
| Pixel Effect Data | `effects/attack_vfx/*.tres`（5 Effect ID、Sprite Sheet、FPS、Lifetime、Size） |
| Element Combat Data | `data/elements/element_combat.json`（2スロット、Lv上限、追加Damage、VFX倍率、雷連鎖） |
| Element Effect Data | `effects/element_vfx/*.tres`（5 Element ID、居合Trail/Hit、雷Chain、Lv2/3 Accent設定） |
| Manager | `effects/effect_theme_manager.gd` |
| Pixel Manager | `effects/attack_vfx_manager.gd`（攻撃開始/Hit、AnimatedSprite2D生成、frame cache） |
| Gameplay System | `systems/element_combat_system.gd`（属性追加Damage、雷の対象探索・減衰・重複防止） |
| Effect Scene | `effects/particles/themes/*.tscn`（10個の通常/強化Particle scene） |
| Active Skill | `effects/active_skill_vfx.gd`、`effects/character_afterimage.gd` |
| Critical/Number | `effects/damage_number.tscn` / `.gd`、`damage_number_manager.gd` |
| Screen/Pool | `effects/screen_effects.gd`、`effects/vfx_pool_manager.gd`、`effects/particles/mass_kill_burst.tscn` |
| Projectile Asset | 職業Projectileは`assets/sprites/projectile/Arrow01(32x32).png`+武器Theme Glow。Fusion武器はArrowなし+武器Theme Glow。Element取得/Lv変更では生成・置換しない |
| Shader | `effects/shaders/sprite_outline.gdshader`（Boss輪郭。Attack IDには未使用） |
| Composition root | `scenes/game.tscn`（各Managerを常設） |
| Pixel Assets | `assets/vfx/attack/*_6f.png`（384×64、透明、64px×6フレーム） |
| Element Assets | `assets/vfx/elements/*_6f.png`（居合Trail 5枚 + Hit 5枚 + 雷Projectile/Chain 2枚、同形式） |
| Runtime test | `tests/gameplay_vfx_capture.tscn` / `.gd`（実game.tscn、2職業、攻撃/Hit/PNG） |
| Element Runtime test | `tests/element_stack_combat_check.tscn`（Stack/Damage/Chain/Projectile/HUD/reset）、`element_level_vfx_check.tscn`（5属性Lv1〜3/攻撃非生成）、`element_shard_vfx_check.tscn`（実描画、5属性×Lv1〜3） |
| Visual evidence | `artifacts/equipment_element_polish/`と`artifacts/developer_test_lab/`（5属性×Lv1〜3、雷Chain/Projectile、装備合成画面、戦闘中Pixel Loot Plate） |

通常攻撃と物理Hitの主表示は上記Sprite Sheetと職業/武器Themeを維持する。
Element Modifier Spriteは実際に属性追加Damageが成立したHitと居合経路だけへ合成し、取得/Lv変更や通常攻撃開始からは生成しない。
新規Assetを追加した場合は、実パス、import設定、使用Effect IDをこの表と25.7へ同時追記する。

### 25.13 新しいLegendary Equipmentの追加手順

1. 64×64透過PNGを該当`assets/items/<slot>/`へ配置し、最近傍表示を確認する。
2. `templates.json`へ一意なtemplate ID、名称、slot、`rarity:"legendary"`、icon path、
   重複のないAffix候補を追加する。追加後は同Rarity抽選候補へ自動で入る。
3. 既存Specialをランダム付与するだけなら追加設定は不要。特定templateへSpecialを固定する
   仕様は現行にないため、必要なら勝手に固定せずData schemaの変更として設計・実装する。
4. 新しいSpecial Effectを追加する場合は`drop_table.json/special_effects`へIDと
   Legendary / Mythic値を追加し、発動条件を適切なGameplay Componentへ実装する。
5. VFXが必要ならSpecial IDとは別のVFX Effect IDを決め、25.14の手順でVisualを追加し、
   Gameplay発動箇所から省略可能なVFX requestとして呼ぶ。
6. Drop候補、Affix数/Range、icon path、地面Icon/Pixel Plate/Particle、Pickup、Inventory、比較、装備、解除、
   run reset、Special Gameplay、VFX非依存性をテストする。
7. Effect ID一覧、Special表、ファイル表を含む本仕様書を同じ作業で更新する。

### 25.14 新しいVFXの追加手順

属性Hitまたは複合Themeを追加する場合:

1. 既存IDと衝突しないlower_snake_caseのEffect IDとVisual Priorityを決める。
2. Visual Languageに沿って通常/必要なら強化Sceneを作成し、Particle数、Lifetime、Glow、
   Trail、Shaderの有無を決める。高頻度ならPool化を検討する。
3. `EffectThemeData`の`.tres`を`effects/themes/`へ置く。単属性はScene参照、複合は
   実在するIDだけを`combo_ids`へ設定する。DataLoaderが自動登録するため通常はManagerへの
   switch追加は不要。
4. `CharacterData.vfx_theme_id`または`WeaponData` JSONの`vfx_theme_id`へ設定する。
   Equipment SpecialならSpecial IDとは別のVisual参照として発動側から要求する。
5. 通常/強化、Projectile / Melee / direct AoE、Critical、同時Hit、欠損IDfallback、
   `queue_free` / Pool再利用、1600×900での可読性を確認する。
6. VFXは`scenes/developer_test_lab.tscn`のVFX Galleryで、実`game.tscn`を描画した状態の
   単属性Attack/Hit/Status、Lv1/2/3比較、全10 Fusionを確認する。
7. 25.7の全項目（用途、キャラ、攻撃、装備/武器、Scene、Asset、Animation、Lifetime、
   Particle、Trail）とPerformance基準を同じ作業で更新する。

汎用斬撃など属性Theme以外のEffect IDを追加する場合、現行には汎用Registryがない。
既存`EffectThemeData`へ意味の異なるIDを無理に混ぜず、専用Effect Data / Managerが必要かを
設計し、Scene / Data / 呼び出し元 / Gallery / テスト / 本章を一体で追加する。

### 25.15 VFX Gallery

VFX GalleryはDeveloper Test Lab内に実装する。Sceneは`scenes/developer_test_lab.tscn`で、
EditorからF6で直接起動できるほか、Debug BuildではGAME START後のモード選択からTEST MODEへ入れる。
通常Saveを停止する一時Sessionで、RETURN TITLEから通常タイトルへ戻る。

- VFX GALLERY Tab: Fire/Ice/Lightning/Light/DarkのAttack、Hit、StatusとLv1/2/3比較、生成済み風刃Concept VFX
- FUSION Tab: 全10 FusionのAttack、Hit、Intro、Bonus Trait、連続Preview、Esc停止
- 右Field: `scenes/game.tscn`をSubViewportへ実体化した本編Map/Player/Enemy/VFX表示
- ROOM Tab: 任意ROOM、ROOM 4/12/24/36 Boss、12回遷移Stressを即実行する
- Effect追加時はDataLoaderへ登録されたElement/Fusion IDと実Manager経路を用い、Gallery専用の
  Gameplay複製を作らない。1600×900のVulkan描画確認は
  `tests/developer_test_lab_visual_check.tscn`で実施する

### 25.16 Performance方針

- 大量敵・大量Projectile時もEnemy / Enemy Projectile / Telegraphを最優先で読めること。
- Theme Particleは現在都度生成するため、profileでinstantiate / GCが問題になったEffectは
  再生頻度と最大同時数を測定し、専用Poolへ移す。Pool枯渇時はVisualを省略しGameplayを続行する。
- `VFXPoolManager`のMass Killは6個、Damage Numberは36個を上限として再利用する。
- Gameplay Lightning ChainはStackに応じ1/2/3本、距離220px。旧ThemeのVisual-only Chainは
  active lightning中は抑止し、同じ対象間へ二重表示しない。Projectileは3.0秒で自動破棄する。
- Compositeは最大5属性を同時再生するため、Penta系の同時Hit数を重点測定する。通常攻撃の
  全画面Flash / Hit Stop / Shakeは禁止し、画面効果の連打を避ける。
- Glowは24×24の小さなGradient、alpha 0.30以下を基準とする。Additive GlowやShaderを
  Projectileごとに増やす場合はoverdrawを測定する。
- `particle_quality`設定は現在Dictionaryに存在するがTheme Particle数へは未接続。
  Web対応時はlow / medium / highごとのamount、同時数、Glow、Trail、Shaderの実設定を接続する。
- Web ExportではGPU Particle / Shader互換性、VRAM、draw call、GC、低性能端末を実測する。
  見た目を簡略化してもHitbox、Damage、Special Effect、Drop結果は変えない。
- 現在、Theme Hit VFXの包括的な同時数上限はない。新規高頻度Effectを追加する前に、
  VFX Galleryまたは負荷テストsceneと上限/劣化方針を用意する。
- ROOM遷移はMapを報酬中に先行生成し、TileMap敷設を複数Frameへ分割する。EnemyのSpriteFramesは
  `sprite_folder`単位でCacheし、Spawn位置候補は1ROOMにつき1回だけshuffleする。Enemyは1体/Frameで
  非表示準備し、Spriteは全員同時表示、AI/Physics解除だけを2体/Frameで分散する。旧ROOM解放と新ROOM生成を
  同一Frameへ集中させない。
- 居合Trailはdash stepごとに最大1 Sprite（既定10 step）を生成し、非Loop 6フレーム完了時に
  自動破棄する。Element VFX欠損時はTrail/Hitを省略し、移動・Damage・当たり判定を続行する。

### 25.17 仕様書同期の恒久ルールと完了前チェック

「実装が最新、仕様書が古い」状態を禁止する。Equipment、Affix、Special Effect、Effect ID、
VFX、Attack、UI、Input、Balance、Scene、Resource、Data、Assetを追加・変更・削除した場合は、
必ず同じ作業内で`game_specification.md`を更新する。READMEに現行概要を記載している項目は
READMEも同期する。コードだけ、または仕様書だけを更新した状態を完了としない。

完了報告前に最低限、次を機械確認または目視照合する。

- `effects/themes/*.tres`の全IDが25.7に1回ずつ存在し、存在しないIDを記載していない。
- `effects/attack_vfx/*.tres`の5 ID、Sprite Sheet、6フレーム、FPS、Lifetime、Character接続が
  25.6〜25.7と一致し、実ゲーム通常攻撃からAnimatedSprite2Dへ到達する。
- 全`combo_ids`、`CharacterData.vfx_theme_id`、`WeaponData.vfx_theme_id`が実在Themeまたは
  明記した`default` fallbackである。
- Affix ID、Range、Affix数、Weight、Special Effect ID / 値が`drop_table.json`と一致する。
- Template、icon path、slot、Resource / Scene / Script pathが実在する。
- E/X、C/Y、I互換、ESCのInput仕様と実装が一致する。
- Particle amount / Lifetime、Line duration / width、Glow alpha、Pool数、Hit Stop、Shake値が一致する。
- VFXを無効化・欠損させてもDamage、撃破、Drop、Special Gameplayが維持される。

### 25.18 Final polish耐久回帰（2026年8月9日）

- `tests/final_polish_soak_check.tscn`は実`scenes/game.tscn`を使い、600秒地点のSpawn条件で
  480体の通常Spawn/死亡、連続Level Up、Fire Lv3 Burn 30体、Projectile 240発、
  Pixel/Theme VFX各120回、居合10回を圧縮実行する
- Charge/Slam/Summon/Nova全Boss Strategy、Boss撃破後のItem→Fragment Modal、Pause、
  Player死亡→Result→Retry Button reload、追加2回のGame再生成まで同じRuntimeで通す
- 完了条件はProjectile/VFX/Burn残留0、Orphan Node増加0、主要EventBus接続数のRestart間一致、
  Runtime error 0。HeadlessとVulkan GUIの双方で実行し、GUI画像は
  `artifacts/final_polish/`へ保存する

## 26. 前回実装の実機不具合修正と検証（2026年8月9日）

### 26.1 原因

- Ground Equipmentは全アイコンへ固定`scale=0.82`を適用しており、元画像の透明余白や物理形状差、
  職業ごとの実表示高を考慮していなかった。さらに半径35px級のリングが装備本体より大きかった
- 巡回EliteはBoss/精鋭部屋中に相対カウントダウン全体を停止していたため、60秒周期Bossがある
  実ゲームではGallery/単体simulationより出現期限が大幅に後ろへずれていた
- 旧Attack VFXはTheme Particle ResourceとEffect IDが存在しても、通常攻撃開始イベントから
  Sprite Animationを生成する接続がなく、素材も形状変化するフレームアニメーションではなかった

### 26.2 実装確認

- `tests/equipment_integration_check.tscn`: 全10職業×全25アイコン（250組）で不透明画素高70〜100%、
  巨大Ring/縦Beamなし、硬いPixel Plate/Outline、カード/浮遊なし、Drop/Pickup/装備Gameplay維持
- `tests/elite_frequency_check.tscn`: 10分×5回=`[4,4,4,4,4]`、平均4.00。
  通常100 seed + Boss競合100 seedも全て3〜5体、Soft Pityあり、見えない壁なし
- `tests/gameplay_vfx_capture.tscn`: 実`scenes/game.tscn`へSwordsman/Archerを選択して敵を置き、
  通常攻撃開始、6フレーム進行、通常Hit、Critical Hit、既存Damage減少を全て確認
- GUI描画で`artifacts/equipment_element_polish/mass_combat_loot_visibility.png`、
  `swordsman_attack.png`、`swordsman_normal_hit.png`、`archer_attack.png`、
  `archer_critical_hit.png`を保存し、実ゲーム背景上で目視確認する
- `scenes/game.tscn`単体もヘッドレス起動し、通常Wave/Boss/Elite/装備/既存入力を含む構成の
  parse・instantiateでScript Errorがないことを確認する

## 27. Elite 100% Drop / Element Shard / Attack Type + Element Modifier（2026年8月9日）

### 27.1 Elite装備ドロップ保証

- `enemy_drop_requested`が「精鋭=true、ボス=false」で届いた場合、装備を最低1個必ず生成する。
  見えない壁、精鋭生成条件、属性Affix、撃破追跡、通常Wave、Bossには変更を加えない
- `drop_table.json`は`elite_minimum_drop_count=1`、`elite_extra_drop_chance=0.0`、
  `elite_extra_drop_count=1`を持つ。現在は1撃破=1個。将来、追加確率だけを上げれば2個目を
  生成でき、最低保証を失わない
- 旧`elite_drop_chance`と「落ちない」抽選は廃止する。レアリティ抽選は従来の
  Uncommon/Rare/Epic/Legendary/Mythic = 50/30/15/4/1を各Dropで独立して行う
- テンプレート、Affix数/値域、Legendary/Mythic特殊効果、床位置補正、取得、Inventoryは維持する

### 27.2 Element Shardの状態管理

| Element ID | 対応欠片 | Theme ID | HUD例 |
|---|---|---|---|
| `element_none` | なし | なし | 属性：なし |
| `element_fire` | `fire` / 炎の欠片 | `fire` | 属性：主 火 Lv3 |
| `element_ice` | `ice` / 氷の欠片 | `ice` | 属性：氷 Lv2 |
| `element_lightning` | `lightning` / 雷の欠片 | `lightning` | 属性：主 雷 Lv1 |
| `element_light` | `light` / 光の欠片 | `light` | 属性：光 Lv2 |
| `element_dark` | `dark` / 闇の欠片 | `dark` | 属性：主 闇 Lv1 |

- 正式な保存先は`GameManager.active_element_ids`（古い→新しい取得順、末尾が主属性）と
  `element_stacks`。最大2属性・各Lv3。`active_element_id`は既存呼び出し互換の主属性値である
- 同属性はLvを1上げて主属性へ移動する。Lv3以後は通常属性カードを候補から外し、
  属性固有Masteryへ置き換える。直接再取得を要求してもStack/欠片を増やさない
- 異なる属性は空きスロットへLv1で入る。2属性取得後はBuildを正式にLockし、
  3種類目の取得要求を拒否する。既存2属性を置換せず、そのRunの報酬候補にも出さない
- `held_fragment_ids`とは独立したラン内一時状態で、`SaveManager`へ保存しない。ゲーム開始時と
  `run_ended`時に全スロット・全Lvを0へ戻す。Fusion消費ではLoadoutを消さない
- 火/氷/雷/光/闇の5属性をElement Modifierとして扱う
- 互換通知`active_element_changed(primary_id)`に加え、正式通知
  `element_loadout_changed(active_ids, stacks)`をHUD等へ送る

### 27.3 Attack Type + Element Modifier

```text
Character attack_pattern_id（Attack Type）
  + GameManager.active_element_ids / element_stacks（最大2 Element Modifier）
  = 職業・武器本来のAttack開始Sprite / Projectile
    + 主属性による居合Trail
    + ElementCombatSystemで追加Damageが成立した属性の確定Hit Sprite
    + ElementCombatSystemによる各属性の独立追加Damage
    + 雷なら敵から敵へのGameplay Chain
```

- 通常近接の攻撃開始時はPresentation専用`attack_slash`を生成しない。`attack_projectile` / `attack_pulse`、
  Character Animation、攻撃範囲、速度、Damage、Critical、Hitboxは変更しない。
  通常攻撃の物理HitはCharacter/Weaponの`vfx_theme_id`を使うが、Lightning Themeの通常近接だけは
  黄色い三日月/星を残さないため汎用`hit_normal` / `hit_critical`と黄色の基底Lightning Particleを生成しない。
  紫の強化Lightning、ElementCombatSystemによる属性Hit、Chain、Damage、SEは維持する
- 職業通常攻撃へ現在属性・Fusion由来の追加Flash/Aura/Trail/Projectile置換を自動付与しない。
  属性Hit Spriteは`ElementCombatSystem`で実際の属性追加Damageが成立した地点だけに生成する。
  Element Fusion成立後は継承Gameplayを維持しつつ、画面上では通常属性Hitを抑止して専用Fusion VFXだけを出す
- `AttackPatternBase`の近接/直線/AoE HitとArcher/Wizardの一時`WeaponData`も
  `CharacterData.vfx_theme_id`を使う。現在Elementを通常攻撃Themeへ流用しないため、光のBeamや
  闇の吸収Particleが属性取得/Lv変更直後の通常攻撃へ逆流しない。Active Skillの属性Themeは維持する
- 職業Projectileは共通Arrowと職業・武器Theme Glowを維持する。Element/Fusion取得・Lv変更は
  職業Projectileを生成・置換せず、Fusion固有処理も意図しないArrowを生成しない
- `ElementVFXData`と`AttackVFXManager`はVisual専用。追加Damage・Chainは
  `data/elements/element_combat.json`と`ElementCombatSystem`が担当し、VFX欠損でもGameplayを続行する

### 27.4 居合Trailと属性Hit

| Element | Iai Visual Language | 実再生時間 / Safety | Hit Visual |
|---|---|---|---|
| 火 | 橙〜赤の細い燃焼帯、揺れる炎、火の粉。実通過区間へ連続配置 | 6f/12fps=0.50s、Safety 0.95s | 外向きに咲いて散る小型火花 |
| 氷 | 白〜水色の冷気、直線的な氷晶、砕ける残像 | 6f/13fps≈0.46s、Safety 0.78s | 氷晶の放射破砕+冷気 |
| 雷 | 青〜紫の鋭い不規則分岐、途切れた瞬間発光 | 6f/22fps≈0.27s、Safety 0.36s | 短い分岐電撃+残留Spark |
| 光 | 白〜金の細い直線斬光、Lv2で小星粒、Lv3で二層細線。高輝度の面を作らない | 6f/16fps=0.38s、Safety 0.50s | 小型星Burst、Lv3だけ細い神聖星Core |
| 闇 | 紫黒の細い裂け目、Lv2で残滓、Lv3で黒芯+紫縁の二層亀裂。画面暗転を使わない | 6f/14fps≈0.43s、Safety 0.50s | 小型裂傷Burst+局所的な虚無Rift |

- `ActiveSkillComponent._swordsman_iai()`の各実移動segment完了後に
  `AttackVFXManager.play_iai_trail(start,end)`を呼ぶ。壁衝突時は実際に通った距離だけ表示する
- Trail/HitはParticleだけで済ませず、各6フレームの`AnimatedSprite2D`を主表示とする。
  afterimageも現在属性色へ寄せるが、既存モーション、チャージ、キャンセル、無敵、Damageは維持する
- 旧`ActiveSkillVFX(style="slash")`の半透明扇形/三角形は居合から外す。Dash、残像、実移動Trail、
  各stepのHitは残し、細く鋭い斬線を主役にする
- VFXはStackごとにScale 1.00/1.16/1.32とSecondary detailを段階強化する。主Spriteの
  OpacityはLv1から1.00を維持し、最初から薄い面として出さない。画面を覆う面積やLifetimeを
  増やす方式にはしない
- Lv2/Lv3はScaleだけでなく、Elementごとの局所Secondaryを追加する。火=`embers`、氷=`crystals`、
  雷=`arcs`、光=`rays`、闇=`rifts`。Lv3はLv2よりParticle/Shard/Arc/Ray数とCore detailを増やす
- Lv2/Lv3到達時はPlayer周辺だけに0.74秒のRing、Burst、`LEVEL 2` / `LEVEL MAX`を表示する。
  このSignal経路はAttack、Damage、Weapon生成、Fusion判定、Projectile生成を呼ばない
- 光・闇の到達Burstは最大17px/sの短い局所Particleに制限し、遠くへ飛ぶ弾や斬撃に見える
  指向性移動を使わない。光は細い縦Core、闇は細い不規則Riftで属性差を表現する
- 5属性は別々に調整したSprite Sheetを使い、単純な色替えを禁止する。画面全体を覆う大きさ、
  通常Hit Stop、通常Shake、無条件の全画面Flashは追加しない

### 27.5 UI・データ・追加手順

- HUD左上のHP/EXP直下に`ActiveElementLabel`を置き、0属性は`属性：なし SLOT 0 / 2`、1〜2属性は
  `火 Lv3 | 主 雷 Lv1 SLOT 2 / 2 LOCKED`の形式で各色表示する。Fusion後はFusion名とSignature Rankを表示する。
  既存HUD、Skill Panel、Boss HP、Character Screen、InputMapへ新しい操作は追加しない
- `resources/element_vfx_data.gd`がVisual schema、`effects/element_vfx/*.tres`が5属性Data、
  `assets/vfx/elements/`が最終Sprite、`AttackVFXManager`が合成・自動破棄を担当する。
  Gameplay値は`data/elements/element_combat.json`へ分離する
- 新属性追加は、(1)Trail/Hit 6-frame PNG作成、(2)`ElementVFXData`の`.tres`追加、
  (3)一意な`element_*` / `vfx_*` ID設定、(4)`GameManager.ACTIVE_ELEMENT_BY_FRAGMENT`と
  Theme mapping追加、(5)追加Damage表・必要な固有GameplayをCombat Data/Systemへ追加、
  (6)HUD/Stack/2-slot lock/reset/全Attack Type/Hit/expiryテスト、(7)本章とAsset README更新

### 27.6 属性現象の共通Lifecycle

- 新属性/Fusionの主Spriteを始点から終点へ平行移動させない。Attack/Trailは実攻撃区間の中央へ
  固定し、6 frame内で中心から横へ形状が展開→最大発光→外周/両端が欠けて粒子化する
- Sprite Sheet生成で全体Alphaを段階的に下げない。可視Pixelは全frameで強い発色を保ち、
  最後のごく短い残光以外は、Alphaではなく可視形状の減少と欠片で消滅を表現する
- Lv2/Lv3のTrail/Hit補助もRoot全体の`modulate.a` Fadeを使わず、線分を両端から短くするか
  外周形状を中心へ畳んで解放する。このLifecycleを今後の新属性VFXにも適用する
- 居合は攻撃区間へ固定した属性/Fusion Trailで空間を斬る。命中敵を追従する横線、傷Overlay、
  属性別Slash Mark Resourceは生成・保持しない。居合Damage、属性追加Damage、Trail/Hit Spriteは維持する

### 27.7 実ゲーム検証

- `tests/equipment_integration_check.tscn`: 旧No-drop keyが存在しないこと、最低1個、追加率0%、
  精鋭撃破通知3回から地面装備が正確に3個増え、全て既存5レアリティ・床マス・iconを使うこと
- `tests/element_stack_combat_check.tscn`: 実`scenes/game.tscn`でLv1〜3、Lv4上限、2スロット、
  3属性目の拒否、2属性の追加Damage増加、色付き数値、実Space Hit、職業Projectile維持、
  雷Lv3の4連鎖・310px・重複なし・撃破打起点、HUD、Fusion成立、run resetを確認
- `tests/element_shard_vfx_check.tscn`: 5属性それぞれLv1〜3の実居合・Hit・Scale増加、
  職業ProjectileのArrow維持、雷連鎖、Fire 4択取得UIのpause解除と
  blackout用CanvasLayer残留なしを実Game sceneで確認
- 実レンダラー1600×900で`artifacts/equipment_element_polish/iai_{fire,ice,lightning,light,dark}_lv{1,2,3}.png`、
  `lightning_projectile_lv3.png`、`lightning_chain_lv3.png`を保存し、扇形なし、電撃形状、
  床・敵・HUDの可読性を目視確認する。両テストは`failures=0`
- `tests/loot_visibility_check.tscn`でElite実Drop、全5RarityのPlate色・Fragment数/Contrast、到着Burstから常駐表示への移行、
  取得後の残留なしを確認し、`mass_combat_loot_visibility.png`で敵・弾・Damage Number混在時の可読性を確認する
- `tests/element_level_no_attack_check.tscn`で光/闇Lv1〜3の各取得単体がProjectile、Weapon、
  Attack Event、Damage Event、Hitboxを一切生成せず、Lv2/3の局所Feedbackだけを出すことを確認する
- `tests/auto_attack_vfx_regression_check.tscn`で敵接近から実通常攻撃を発生させ、職業Attack/Hit、
  Element Damageは維持しつつ、現在光/闇Theme、Lv/Fusion VFX、謎Projectileが混入しないことを確認する
- `tests/light_dark_vfx_visual_check.tscn`をVulkan Forward Mobile 1600×900で実行し、
  `artifacts/light_dark_vfx_polish/`へ光闇Lv1〜3、Lv feedback、Hit、全属性比較を保存する
- 既存`elite_spawn_regression_check.tscn`と`gameplay_vfx_capture.tscn`も再実行し、通常敵、
  部屋/巡回Elite、Affix、壁0、逃走、Boss、既存Attack/Hit、Damageがエラーなしであることを確認。
  回帰テスト内では巡回Elite 1体＋部屋Elite 2体を実際に撃破し、本番の死亡通知経路から
  地面装備が正確に3個増えることも確認する

## 28. Element Stack / Element Damage / Lightning Chain 正式仕様（2026年8月9日）

### 28.1 採用方針と調査結果

同属性はStackして投資価値を上げ、異属性は最大2種類を同時保持する。2属性を両方Lv3にした瞬間、
順序に依存しない10種類のElement Fusionへ一度だけ進化する。旧完成武器レシピとは責務を分け、
Element ModifierのGameplay/VFX/Masteryは`ElementCombatSystem`と`FusionCombatRuntime`が担当する。
色だけに依存せず、属性名・Lv・Slot Lock・Fusion名・Signature RankをUIへ併記する。

### 28.2 Stack・追加Damage・Lv4

| Lv | VFX Scale | Opacity | 火追加 | 氷追加 | 雷追加 | 光追加 | 闇追加 |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 1.00 | 0.78 | 10% | 8% | 12% | 9% | 11% |
| 2 | 1.16 | 0.90 | 17.5% | 14% | 21% | 15.75% | 19.25% |
| 3 | 1.32 | 1.00 | 30% | 24% | 36% | 27% | 33% |

- 上限はLv3。Lv4相当の通常属性カードは抽選から除外し、属性固有Masteryへ移行する。
  直接再取得も拒否し、二重成立や不要な旧Fusion素材を発生させない
- 各確定Hitで、実際に通った物理ベースDamage × 上表比率を各保持属性ごとに要求する。
  `HealthComponent.apply_secondary_damage()`が既存iframeだけを無視し、防御、Shield、1Hit上限、
  死亡判定は通常Damageと同じ規則で処理する。追加Damageは新しいiframeを開始しない
- 物理Criticalは従来のCritical倍率・赤30px数値を維持する。属性比率はCritical適用後の
  実ベースDamageを参照するが、属性数値自体はCritical扱いにせず17〜19pxの属性色で別表示する
- 2属性保持時は両方の追加Damageを独立適用する。主属性だけが居合Trailを決め、
  Hit Spriteと追加Damageは両属性を表示・適用する。通常攻撃開始色と職業Projectileは職業・武器本来のThemeを維持する

### 28.3 雷Gameplay Chain

| 雷Lv | 最大Jump | Jumpの初期雷追加Damage比 | 1Link距離 |
|---:|---:|---|---:|
| 1 | 1 | 78% | 200px |
| 2 | 2 | 78% / 62% | 250px |
| 3 | 4 | 78% / 62% / 50% / 42% | 310px |

- 雷属性取得・Lv変更はProjectileを生成せず、職業Projectileも`vfx_lightning_projectile`へ置換しない。
  当該Resource/Assetは将来の専用攻撃用に登録状態を維持するが、Element Stackイベントからは未接続とする
- 雷追加Damageが成立したHit（ベース攻撃が起点を倒した撃破打を含む）から、現在地点の
  Lv別Range以内にいる最寄りの生存敵を順に選ぶ。訪問済みinstance IDを保持し、同一敵へ戻らない
- Chain Damageは最初の雷追加Damage実適用値へ上表を掛ける。対象不足、距離超過、死亡時はその場で終了する
- Damage/対象選択は`ElementCombatSystem`、表示は`vfx_lightning_chain`が担当する。
  旧`EffectThemeManager`のVisual-only疑似Chainはactive lightning中だけ抑止し、二重線を出さない
- 通常敵/Elite/Bossの既存Spawn、Affix、撃破、報酬、装備Dropは変更しない。Chainで死亡した敵も
  `HealthComponent.died`から従来の撃破・Drop経路へ入る

### 28.4 Damage Number・HUD・Save境界

- 物理通常=`#F2F2F2`/20px、物理Critical=`#FF4033`/30px、火=`#FF611A`、
  氷=`#9EEBFF`、雷=`#B899FF`。属性はLv1/2/3で17/18/19px、Chainは2px小さくする
- 同時表示増加に合わせDamage Number Poolを20→36へ拡張する。OFF設定時は物理・属性とも表示しない
- HUDはRichTextで2属性の名称・Lv・主属性・Slot Lockを常時表示する。Fusion成立後は
  専用Fusion名とSignature Rankを表示し、旧完成武器を追加表示しない
- Element Loadout / Stack / Chain履歴はラン内状態で、Save schemaを変更しない。ラン開始/終了で
  全消去し、メタ通貨、解放、装備、職業データへ永続化しない

## 29. 2属性Build / Boss 4択 / 全10 Element Fusion（2026年8月10日）

### 29.1 Boss報酬と2属性Lock

- Element報酬は常に2×2の4枠。0属性時は異なる通常属性3枚+General Element Mastery 1枚、
  1属性時は所持属性Lv Up+未取得属性2枚+General 1枚とする
- 2属性取得後は`SLOT 2 / 2 LOCKED`となり、未取得3属性を候補から完全除外する。
  所持属性のLv Up、Lv3属性Mastery、General Masteryだけを候補にする
- Lv3属性の通常カードは出さない。2属性ともLv3になった瞬間に順序非依存でFusionを一度だけ成立させる
- Fusion後は通常5属性カードを一切出さず、Fusion Power / Echo / Haste / Signatureの固定4枠に移行する。
  各Rank上限は3。全4系統が上限の場合だけ、報酬Modalを閉じられる`FUSION COMPLETE`を1枠目に出す
- Bossの既存Item 3択は変更せず、モーダルキューでItem 3択の後にElement/Fusion 4択を表示する

### 29.2 属性成長・Mastery・Echo

| 属性 | Lvで成長する固有Mechanic |
|---|---|
| Fire | Burn tick/継続/範囲が増え、Lv3でBurn対象死亡Explosion |
| Ice | Slow時間/強度とFreeze率が増え、Lv3で完成形のFreeze/Shatter条件 |
| Lightning | Chainが1→2→4 Jump、Rangeが200→250→310pxへ増える |
| Light | Holy Strike必要Hitが5→4→3、Bonus Damageと一時Shieldが増える |
| Dark | Curse時間と被Damage増加が15%→28%→45%へ増える |

- Fire Burnは対象更新中の死亡Explosion/AoEで別Burn対象が同期削除されることを前提に、Dictionaryを
  `get()`で安全取得する。死亡・期限切れ・無効Target・Runtime ResetではBurn本体と死亡Signalを同時に
  退役し、Callback削除後のEntryを書き戻して復活させない

- General MasteryはPower（属性Damage +15%/Rank）、Echo（+15%/Rank、最大45%）、
  Haste（Interval -10%/Rank）、Reach（AoE/Range +12%/Rank）の4系統、各Rank 3
- Lv3属性MasteryはPower（+25%/Rank）、Echo（+15%/Rank）、Reach（+20%/Rank）、
  Signature（固有Mechanic強化）の4系統、各Rank 3
- Element Echoは元Hitごと・属性ごとに最大1回だけ二次発動する。Echo Damage/Chain/Statusは維持するが、
  二次発動からEcho抽選やFusion Signature抽選へ戻さず、再帰を禁止する

### 29.3 全10 Fusion Gameplay

| Fusion | 組合せ | 継承Trait | 第3Trait |
|---|---|---|---|
| THERMAL SHOCK / 熱衝撃 | Fire+Ice | Burn + Freeze | Thermal Collapse: 両状態から小型Steam圧AoE |
| PLASMA / プラズマ | Fire+Lightning | Burn + Chain | Overcharge: 遅延/死亡時Plasma Core爆発 |
| SOLAR FLARE / 太陽炎 | Fire+Light | Burn + Holy | Corona: Burn対象死亡時Solar Flare |
| INFERNO / 煉獄 | Fire+Dark | Burn + Curse | Soul Devour: 死亡Soul蓄積から黒炎強化 |
| SUPERCONDUCTOR / 超伝導 | Ice+Lightning | Freeze + Chain | Resonance Shatter: 凍結Networkの連鎖破砕 |
| AURORA / 極光 | Ice+Light | Freeze + Holy | Refraction: Prismから別Targetへ分裂 |
| BLACK ICE / 黒氷 | Ice+Dark | Freeze + Curse | Gravity Collapse: 凍結地点へ吸引+Collapse |
| RADIANT ARC / 聖雷 | Lightning+Light | Chain + Holy | Afterglow Circuit: Chain軌道へ短時間の追加判定 |
| VOIDSTORM / 虚雷 | Lightning+Dark | Chain + Curse | Space Jump: Portal間を跳ぶEnergy |
| ECLIPSE / 日蝕 | Light+Dark | Holy + Curse | Total Eclipse: Gaugeから時限State+専用AoE |

- Fusion Signatureの追加Damageは`apply_secondary_damage()`だけを使い、Element Combat入口へ再投入しない。
  Death/AoE/Spread/ChainからFusion→Element→Fusionの再帰を起こさない
- Fusion Powerは継承属性Payloadと専用Traitを強化し、Fusion Echoは元Hitごとに最大1回、
  Fusion HasteはInterval/Cooldownを短縮する。Signature Rank 1〜3は各固有Mechanicの対象数、範囲、
  Gauge、蓄積、Spread等を段階的に進化させる
- PlasmaはLightning Chain先ごとにFireのBurn/AoEを適用し、各到達敵へOvercharge Coreを残す。
  Core更新中は爆発させず、更新/無効ID収集とDetonationを別Phaseにする。Coreごとの死亡Signalは
  時間爆発、無効Target、Runtime Resetで解除し、死亡時はOne-shot Callbackから1回だけ爆発する。
  Dictionary参照は`get()`を使い、AoE死亡による再入削除や`queue_free`済みHealthを直接参照しない
  Radiant ArcはChain先ごとにLight Hit/Holy進行を適用し、細い軌道を0.16秒だけ残して
  `apply_secondary_damage()`による追加判定を1回行う。内部IDは既存Save/Test互換のため`judgment`を維持する
- 旧2属性完成武器は同時生成しない。職業Weapon数、職業Projectile、通常Auto AttackのThemeを変えない

### 29.4 Fusion Presentation / 成立演出

- Fusion中は内部で2属性Traitを適用しても通常属性Hit Spriteを重ねず、専用Fusion VFXだけを表示する。
  居合Trailも現在Fusionの現象表現へ切り替える
- VFXは既存属性Spriteの合成・色替えではない。組み込みImageGenで全10 Fusionを別々の新規Pixel Artとして生成し、
  `assets/vfx/fusions/<fusion_id>/fx_fusion_<fusion_id>_<mode>_6f.png`へ保存する。
  各FusionはAttack / Trail / Hit / Burst / Introの5枚、各画像は64px×6 frameの透過Sprite Sheetとする
- 現象設計はThermal Shock=小さな蒸気圧破砕、Plasma=細いChain+各着弾Fire Burst、
  Solar Flare=火炎帯+短い光線、Inferno=小型黒炎+Soul Ember、Superconductor=細い放電+結晶破砕、
  Aurora=氷片+短い屈折光、Black Ice=黒い亀裂+氷片、Radiant Arc=白金の細いChain+小Holy Burst、
  Voidstorm=欠けた紫電、Eclipse=光Burstを横切る闇亀裂とする。巨大紋章、柱、Portal Ring、
  Event Horizon、画面を占有するCoronaを主役にせず、元属性と同じ小VFXを反応回数で豪華にする
- `FusionVFXData` Resourceが5画像を保持し、`DataLoader.fusion_vfx_effects`からRuntimeへ供給する。
  `FusionVFXEffect`は対応する6 frame `AnimatedSprite2D`を主描画として再生し、旧Canvas形状とParticleは
  低Alphaの補助Layerだけに制限する。Formation/StateはIntro、Signature/Pillar/PortalはBurst、SoulはTrailを使う
- 画像は18fps。Attack/Trail/Hit/Burst/Introの表示寿命は概ね0.42/0.32/0.38/0.50/0.72秒、
  主Sprite倍率は0.74〜1.12とし、現行Element Hit/Chainと同じ占有率へ収める。
  Gameplayを止めずPresentationだけを間引く同時Fusion VFX上限192を設ける。通常Attack/Hit等は176枠までとし、
  Fusion成立Introが高密度Hitの末尾で欠落しないようFormation用16枠を予約する
- VFXはCollision/Hitboxを持たないVisual-only Nodeで、実時間Lifetimeにより自己解放する。
  瞬間的な多層Burst/Glow/Shake/Hit Stopは許可するが、長時間の白画面・暗転・Player/予兆の不可視化は禁止する
- 各FusionはAttack=区間中央で横展開するPixel Sprite、Trail=区間中央固定の方向追従Sprite、Hit=着弾Sprite、Burst/Signature=拡張Sprite、
  Formation=Intro/Awakening Spriteの用途別画像を持つ。全10種×5用途は同じVisual-only APIで生成し、
  Element SpriteやGameplay Collisionを再利用しない
- `tools/build_fusion_pixel_vfx.py`は全50 Sprite Sheetへ共通Lifecycleを適用する。frame 0〜3は
  中央から可視形状を増やし、frame 4〜5は外周を不規則に欠かせて短い破片へ分解する。
  全体Opacity倍率やGodot側のAttack Sprite座標Tweenは使用しない
- 成立時は元2色のShardがPlayerへ収束→消失→新Fusion Core/衝撃波→
  `ELEMENT A × ELEMENT B → FUSION NAME`を約1〜2秒表示する。最後の通常Lv3演出は重ねない

### 29.5 Runtime State / 検証基準

- `GameManager`が2属性Stack、General/属性/Fusion Mastery、`active_fusion_id`をラン内管理する。
  Run開始/終了/Retryで、Fusion Gauge、Mark、Soul、Portal、Plasma Core、Timer接続を含め全てResetする
- `ElementCombatSystem`は継承Trait、`FusionCombatRuntime`は第3Trait、`AttackVFXManager`と
  `FusionVFXEffect`はPresentationだけを担当する。GameplayとVFX欠損を相互依存させない
- 必須回帰は`element_reward_pool_check`、`element_fusion_matrix_check`、
  `element_damage_scaling_check`、`fusion_trait_check`、`fusion_proc_safety_check`、
  `fusion_chain_grammar_check`、
  `fusion_runtime_integration_check`、`fusion_pixel_art_asset_check`、`developer_test_lab_check`、
  `fusion_pixel_art_lab_visual_check`、`plasma_core_lifecycle_check`、`burn_lifecycle_check`、`element_system_2_visual_check`、
  `element_system_2_soak_check`
- Vulkan GUI成果物は`artifacts/element_system_2/`へ保存し、報酬5状態、成立瞬間、
  全10FusionのAttack/Hit・大量戦・Boss戦、10種一覧、各Fusionの5用途比較、Soakピークを
  比較できる状態にする。現行実Game GUIテストは47画像を生成する。
  さらに`artifacts/fusion_pixel_vfx_gui/`へDeveloper Test Lab内の全10種×5用途10画像、
  全10 Intro一覧1画像、Lightning/Plasma/Lightning、Fire/Plasma/Fire、
  Lightning/Radiant Arc/Lightningの3比較画像を保存する

## 30. Developer Test Lab（2026年8月10日）

### 30.1 起動と安全境界

- 開発Sceneは`scenes/developer_test_lab.tscn`。Godot EditorからF6で直接起動できるほか、Debug Buildでは
  Titleの`GAME START`→Mode Select→`TEST MODE`からPlayer自身が入れる
- Rootで`OS.is_debug_build()`を確認し、Release Buildでは操作UIと本編Runtimeを生成しない
- Mode Selectの`NORMAL GAME`は従来どおりHomeへ進み、Release BuildではTest Modeボタンを無効化する
- Test Lab開始時に`SaveManager.begin_ephemeral_session()`でSave書込を停止し、退出時に開始前の
  in-memory Save snapshotを復元する。Boss/Elite/Resultの実経路を試しても`user://save_data.json`へ永続化しない
- 画面右上へ`テストモード — セーブ無効`を常時表示し、`RETURN TITLE`でTitleへ戻れる
- 左側をDeveloper Control Panel、右側を実`scenes/game.tscn`のSubViewportとする
- 本編中のSpawn先は`game_runtime_world` Groupから解決し、通常GameとSubViewportの双方で
  同じ実Game rootへEnemy/Projectile/VFX/Dropを接続する

### 30.2 操作範囲

- PLAYER: HP、回復、無敵、移動、攻撃倍率、攻撃速度、Critical、Level、EXP、死亡、Reset
- ELEMENT: 5属性のNone/Lv1/Lv2/Lv3、通常取得/Force、Lv遷移、Attack/Hit/Status、実居合Hit
- FUSION: 全10種のCREATE/NATURAL/TRIGGER ATTACK/TRIGGER HIT/TRIGGER BONUS TRAIT/
  TRIGGER INTRO/RESET。`PREVIEW ALL FUSIONS`は各Fusionの新規Attack/Trail/Hit/Burst/Introを連続再生する。
  Lightning→Plasma→Lightning、Fire→Plasma→Fire、Lightning→Radiant Arc→Lightningの比較を1操作で実行できる
- VFX GALLERY: 5属性のAttack/Hit/Status、Lv1/2/3比較、Preview停止、属性/Fusionの居合・Attack表示、
  新規6-frame風刃Pixel VFXの実ゲーム再生
- COMBAT: 敵1/10/50/100、種類/配置/Elite、Dummy、Damage Meter、Projectile/Clear
- BOSS / REWARD: Boss生成、HP 50%/1、撃破/Clear、Charge/Slam/Summon/Nova直接実行、
  現在Build別の4択Element報酬
- EQUIPMENT / LOOT: Template/Rarity指定のDrop/Add/Equip/Unequip/Remove、3個Merge、
  1/10/全Rarity Drop、Loot Clean/Combat/Stress
- RESET STATEは生成物、Boss、Enemy、Projectile、Transient VFX、装備、属性/Fusion、Player、
  Damage Meterを初期化し、実Game Sceneは保持する。RELOAD GAMEは実Game Scene自体を再生成する

### 30.3 検証

- `tests/developer_test_lab_check.tscn`: 実Game接続、LevelUp、5属性、全10 Fusion、自然Fusion、
  4択報酬、Enemy/Boss、Equipment/Merge/Loot、Projectile、Resetを自動検証する
- `tests/developer_test_lab_visual_check.tscn`: Vulkan 1600×900でPanel、実Game Field、Fusion VFX、
  全Rarity Loot、生成済み風刃を描画し、`artifacts/developer_test_lab/`へ保存する
- `tests/fusion_pixel_art_asset_check.tscn`: 全50 PNGの固有Path、384×64 RGBA、透明角、6 frame、
  Resource接続、Runtime AnimatedSprite、Collisionなしに加え、全frame高発色、発生→最大→形状崩壊、
  Attack/Trail Sprite座標固定をHeadlessで検証する
- `tests/fusion_pixel_art_lab_visual_check.tscn`: Vulkan Forward MobileでDeveloper Test Labを起動し、
  全10 FusionのAttack/Trail/Hit/Burst/Intro、全Intro一覧、指定3比較の計14画像を
  `artifacts/fusion_pixel_vfx_gui/`へ保存する
- `tests/iai_and_mode_check.tscn`: 複数敵の実居合Damage、属性Trail維持、敵追従横線が生成されないこと、
  Save snapshot復元、Title Mode SelectをHeadless/Vulkanで検証する
- `tests/plasma_core_lifecycle_check.tscn`: 同時期限切れ、AoE中死亡、時間爆発、連続再付与、1体、複数体、
  `queue_free`、Reset時のCore/死亡Signal退役と非Blackout画面をHeadless/Vulkanで検証する
- `tests/burn_lifecycle_check.tscn`: Lv3 Burn死亡Explosionによる同時削除、期限切れ、連続再付与、
  `queue_free`、Reset時のBurn/死亡Signal退役を検証する

## 31. ROOM制ローグライト / COMBO MVP（2026年8月13日）

### 31.1 ROOM進行

- 1 Runは`data/rooms/room_mvp.json`の`total_rooms`で管理し、現行値は36。各ROOMは
  `RoomRunController`がENTERING→COMBAT→CLEAR→REWARD/CHOOSINGを管理する。
- 4の倍数以外は有限通常Wave、ROOM 4 / 8 / 12 / 16 / 20 / 24 / 28 / 32はBoss Encounter、ROOM 36はFinal Boss Encounter。
  Boss ROOMでは通常Waveを開始せず、既存Bossを明示的に1体だけ生成する。
- `WaveSpawner`のROOM modeは敵を開始時に有限数だけ生成し、ROOM所有Dictionaryで生存個体を追跡する。
  死亡またはTree退出で0体になった時だけ全滅を通知する。通常の時間経過Spawn modeはTest Lab互換として維持する。
- 通常敵数はROOM別10〜15体。HP/攻撃倍率、高進行敵の抽選率、
  Boss候補/倍率、Clear待機、COMBO猶予、Treasure Rarityは同JSONから調整できる。
  通常ROOM敵へElite group/drop/affixは混入させない。
- ROOM遷移では敵、ROOM所有Projectile、未取得宝箱/装備を退役させてからStageを非同期再構築し、同じPlayerを新Spawnへ移す。
  HP、通常Level Up、Element Stack、Fusion、完成済みスキルとそのLvはRun内で維持する。

### 31.2 報酬と分岐

- 全ての非FINAL ROOMは、Clear演出の終了後に属性3択→宝箱→完成済みスキル3択を同じROOM内で順に処理する。
  ATTRIBUTE/TREASURE分岐とレイアウト2択は通常Runから廃止し、報酬完了後は次ROOMへ自動遷移する。
- 属性報酬は既存`FragmentSelect`/`ElementRewardSystem`を使用する。初回は火/氷/雷の3択、1属性所持後は
  所持属性の成長とCore補完属性を含む3択を提示する。2属性Slot、Lv1〜3、Lv3後Mastery、全10 Fusionは29章どおり。
- 属性選択後にNORMAL/RARE/LEGENDARY宝箱を必ず実フィールドへ生成する。範囲外では操作Guideを表示せず、
  Playerが105px以内へ入った時だけ`【E】宝箱を開く`を表示する。宝箱は`is_opened`をSignal発火前に確定し、
  連打でもOPEN、報酬付与、報酬UI生成を一度だけにする。
- 宝箱候補は現在の所持属性を全て満たす完成済みスキルだけから3件を重み付き抽選する。所持済みSkillはLv.UP候補として
  Weightを上げ、2属性対応SkillもWeightを加算する。6種類所持後は未所持Skillを除外するため、無制限に種類が増えない。
- CLEAR/REWARD中もPlayer Inputは有効。戦闘由来の一時移動ロックはROOM CLEAR時とTreasure生成時に解除する。
  ROOM/属性/Skill/Resultの各Buttonは初期Focusを持ち、方向キー＋決定操作だけで進行できる。
- 次Templateは`large`をBoss専用とし、通常ROOMでは直近2Templateを候補から除外して自動抽選する。
  `RoomSelect`基盤は将来の危険/SHOP/Event分岐用に保持するが通常Runから呼ばない。ROOM 36 Final Boss撃破では
  報酬を挟まず`RUN CLEAR`を表示し、RetryまたはTitleへ戻れる。

### 31.3 COMBO

- `ComboSystem`は通常ROOM modeだけで有効。`HealthComponent`を実際に通った敵Damageの
  `enemy_damage_confirmed`を1イベント=1 COMBOとして数える。表示用の旧Signal直送では増えない。
- Direct Hitは1加算して2.5秒Timerを更新する。Element Chain、Fusion AoE、Concept Skill等の派生Hitは
  `is_triggered=true`かつ元Direct Hitの`chain_id`を継承し、敵ごとに加算するが同一起点では最大12までとしTimerを更新しない。
  Burn等のDoTは`combo_eligible=false`で加算しない。汎用Presentation用
  `damage_dealt`、0以下Damage、Player被弾、VFXだけの発生では加算しない。
- 最後の有効Hitから既定2.5秒で0へ戻す。右中央に数字+COMBOを表示し、10/30/50/100以降の節目は
  表示Tweenのみを強調する。現段階ではDamage/Speed/Drop等のBonusを一切持たない。

### 31.4 安全境界と検証

- 通常Game rootだけがROOM modeを開始する。Developer Test LabのSubViewport内Gameは従来Spawnを保ち、
  Test Lab側からBoss/Elite/Fusion/Equipmentを即時生成できる。
- Heart DropはPhysics query処理中にArea2Dを追加しないようDeferredでRuntime worldへ接続し、ROOM全滅時の
  同時死亡でもDebugger errorを出さない。
- `tests/room_combo_mvp_check.tscn`は実Game SceneでROOM 1→36、通常有限Wave、4ROOMごとの9非重複Boss、
  非Finalの属性→通常/Boss宝箱→Skill、Lv3×2、自然Fusion、Cross Skill、6 Skill上限、Boss死亡Cleanup、
  COMBO Reset、RUN CLEARを自動検証する。
- `tests/boss_room_visual_check.tscn`はVulkan GUIで短いBoss出現表示、日本語HP Bar、Status短縮、
  撃破後のProjectile/Warning/Summon/Screen状態復元と非Blackout画面を確認する。
- `tests/room_transition_performance_check.tscn`は同期Component基準と、事前準備後のROOM 2/4/12/13/24/25/36、
  36回連続遷移のStage slice、Node/Object数を計測する。
- `tests/room_mvp_visual_check.tscn`はVulkan Forward Mobile 1600×900で戦闘+COMBO、自動ROOM進行、
  宝箱、Concept 3択、装備済みBoard、Concept Skill VFXを`artifacts/room_mvp/`へ保存する。

## 32. 戦闘耐久 / Concept Build System（2026年8月13日）

### 32.1 固定成長曲線とHit Reaction

- Player火力へ自動追従するDynamic Scalingは使用しない。敵Data基礎HPへROOM 1倍率1.35を掛け、14 Damage基準で
  小型平均4.33Hit、標準平均9.33Hit、大型平均16.33Hitとする。
- 固定HP倍率はROOM 1=`1.35`からROOM 35=`15.00`、固定Damage倍率は`0.24〜0.58`へ緩やかに増やす。
  敵数は最大15体で、極端な同時出現数や一撃死Damageではなく耐久・敵構成で難しくする。
  14 Damage固定Referenceで標準敵はROOM 1/5/9/11=`9/13/19/23 Hit`だが、実Runでは属性・Skill・Fusion成長により必要Hit数が下がる。
- ROOM CLEARごとに最大HPの7.5%を回復する。割合は同JSONの`room_clear_heal_ratio`で調整する。
- Enemy被弾時は白いHit Flash、短いSquash、14ms Hit Stopを再生する。Hit Stopは全敵共通120ms Cooldownを持ち、
  移動停止や大Knockbackを伴わないためFreeze/Stunと競合せず永久怯みを作らない。

### 32.2 完成済みスキル / 旧Concept Board

- 通常プレイは`data/skills/completed_skills.json`の完成済みスキルを1能力として取得する。表示名・Lv別説明は
  `data/localization/ui_ja.json`のKey参照で、英語の内部IDやConcept Parts名を表示しない。
- 最大6種類、同一IDの再取得はLv1→Lv2→Lv3へ強化する。LvでDamage/範囲が上がり、CHAINは対象数、蓄積型は
  必要Hit数も変化する。HUD左上に所持SkillとLvを最大6件表示する。
- 初期Skillは火/氷/雷の各3種、火+雷/火+氷/雷+氷のCross 3種。光・闇を2属性目に選んでもPoolが枯れないよう、
  光/闇にも各3種を用意する。条件外属性Skillは候補へ入れない。

| 対応属性 | 完成済みスキル |
|---|---|
| 雷 | 雷鳴連鎖 / 蓄電 / 過負荷 |
| 火 | 炎上爆発 / 延焼 / 灼熱追撃 |
| 氷 | 氷砕 / 冷気蓄積 / 凍結追撃 |
| 火+雷 | 導電炎 |
| 火+氷 | 熱衝撃 |
| 雷+氷 | 超伝導 |
| 光 | 光輪追撃 / 閃光蓄積 / 天啓 |
| 闇 | 虚無裂き / 闇蝕 / 魂喰らい |

- 旧`data/concepts/`と2 Chain Concept BoardはDeveloper Test Labと既存回帰テスト用に保持するが、通常プレイの
  Treasure取得後や次ROOM選択画面には表示しない。Boardを開いた場合の起点/スキル/補助名、説明、操作ラベルは日本語表示とする。

### 32.3 初期Concept

| Type | ID | 動作 |
|---|---|---|
| 起点 | 会心起動 | 非派生の直接攻撃が会心になった時 |
| 起点 | 五撃起動 | 同一敵への直接命中5回ごと |
| 起点 | 撃破起動 | プレイヤーの有効ダメージで敵HPが0になった時 |
| 起点 | 連撃起動 | 20/40/60…コンボ到達時 |
| スキル | 雷撃 | 対象中心の高密度雷ダメージ |
| スキル | 炎上爆発 | 対象周囲の炎範囲攻撃 |
| スキル | 氷結新星 | 冷気範囲攻撃+短時間鈍足 |
| スキル | 風刃 | 対象周囲の風斬撃 |
| 補助 | 連鎖 | 近い別対象へ最大2回追加発動 |
| 補助 | 反響 | 0.22秒後に1回だけ再発動 |
| 補助 | 範囲拡張 | 効果半径×1.55 |
| 補助 | 集中 | 同じ生存対象へ0.18秒後に再命中 |

- 現行Element Stackは実コードどおりFire/Ice/Lightning/Light/Darkの5属性と全10 Fusionを維持する。
  風刃は初期Concept Skillであり、新しいWind Element Stack/Fusionを暗黙追加しない。主VFXは
  `assets/vfx/concepts/wind_blade_6f_v2.png`（64×64×6 frame、透過、Nearest）を`ConceptSkillVFX`が実攻撃とTest Labで再生する。

### 32.4 Trigger安全境界

- `HealthComponent.apply_damage/apply_secondary_damage`は既存戻り値/APIを保ち、任意の`CombatEventMeta`だけを追加受領する。
  確定イベントはevent_id、source_kind、chain_id、generation_depth、element_tags、is_direct、is_triggered、
  combo_eligible、is_critical、killed、impact_positionを持つ。
- 既定`max_trigger_depth=2`。発動済みChain indexをlineageに保存し、同一Chainの自己再入を禁止する。
  Triggered Skillは直接攻撃ではなく、Critical再抽選もしないためON CRITICALへ戻らない。
- ECHO/FOCUSは再発動時にModifierを再適用しない。Run Resetは遅延Timer epochを無効化し、古いCallbackを次Runへ持ち越さない。
- `tests/concept_build_runtime_check.tscn`で旧Concept Parts、完成済みSkillの6種上限/Lv.UP/日本語Key、
  雷鳴連鎖、導電炎、Cross候補、Trigger再帰防止、Metadata、Developer Board modalを検証する。

### 32.5 全体監査・安定化（2026年8月14日）

- Soldierの初期DamageはReferenceと同じ14。近接攻撃は0.18秒の予備動作開始時の向きを保持し、
  命中判定直前の移動入力で逆方向へ反転して至近距離の敵を永久に外さない。
- `ChaseStrategy`は直接床Lineが通る間は従来の直進を使い、障害物で遮られた場合だけ280ms間隔の軽量Grid経路へ切り替える。
  中間Cellは周囲1 Cellの床余白を要求し、柱角へPlayer/EnemyのCollisionが食い込んで停止する経路を選ばない。
- 敗北Entityは死亡Animation終了までTreeへ残るが、HP 0への遅延Healを拒否し、`EnemyBasic._on_died()`も一度だけ処理する。
  Aura/Elite Affix等の遅延Heal後に2回目の`died`を発火し、`death_finished`を二重接続する競合を防ぐ。
- Plasma/Burn/FusionのDictionaryは参照前に`get()`/型/Instance有効性を確認し、死亡・Timer・ROOM ResetのCleanupを冪等化する。
  Plasma Core、Solar Mark、Judgment残光は元Damage metadataを保存し、遅延解決後も同じCOMBO chainへ属する。
- `ScreenEffects`は重複Hit Stopを個別期限で管理し、最短Time Scaleを採用する。Flash/Cutin TweenはPause中も進み、
  Scene退出時にTime Scaleと一時Canvasを必ず復元するため、演出例外が全画面暗転として残らない。
- `tests/normal_run_player_input_check.tscn`はTitle→Mode→Home→36 ROOM→属性→Treasure E→完成Skill→
  Fusion→FINAL→RUN CLEAR→TitleをInputMap Actionだけで通す。`concept_fusion_stress_check.tscn`は24体、Plasma Chain、
  Echo、Areaを同時負荷し、Trigger Depth、COMBO上限、Node/VFX/Projectile/Dictionary退役を検証する。

## 33. Pixel Visual System / ROOM Transition最終統一（2026年8月15日）

### 33.1 共通Visual Language

- 詳細な制作基準は`docs/vsgame_pixel_visual_guide.md`を正とする。VFXは64×64を1 frameの基準とし、
  6 frame素材は384×64、Nearest、硬い2〜4px主形状と1〜2px Fragmentを用いる。
- UIは中立暗色面、3px角なし境界、Focus 4px、3〜4pxの硬い影を基本とする。
  `PixelUIStyle`をTitle/Home/HUD/属性・宝箱・Concept/装備/Pause/Result/Test Labへ適用し、
  Normal/Hover/Pressed/Focus/Disabledを色と境界で判別できるようにする。
- 既定FilterはNearestを維持する。Player/Enemy移動を損なうGlobal Pixel Snapは強制せず、VFXのLine/点/座標を
  整数化して非AA描画する。画面占有率・情報量の優先順位はPlayer/Enemy/Boss予兆→攻撃主形状→Hit→残光→UI装飾とする。

### 33.2 VFX Lifecycle

- 主Sprite一枚の横スライドや寿命全体のAlpha Fadeは使用しない。発生地点で高発色→中心から展開→最大形状→
  端/外周からFragment化またはY/横圧縮→最後の短い残光だけFade、の順に統一する。
- 通常近接の追加黄色三日月は生成しない。通常攻撃の判定・Damage・速度・Character Animationは変更しない。
- 画面Flashは同時1枚、最大Alpha 0.16とし、Tween callbackはNodeを直接captureせずInstance IDで解決する。
  Scene resetが先に走っても遅延callbackから解放済みNodeへ触れず、CanvasLayerを残さない。
- Damage Numberは通常19px、Critical 26px、属性16px、暗色2〜3px Outline。中心は寿命82%まで濃く保ち、
  最後18%だけ短く消す。Afterimageも寿命後半だけFadeし、全て`transient_vfx`として自己解放する。
- Element用Pixel Resourceがある時は旧Theme GPUParticlesを重ねない。Line系補助は短い整数Step・非AA・0.16秒以内とする。
- Fusionは29.4の全50画像を維持し、同時上限192（Formation予約16）でPresentationだけを間引く。
  Damage/Status/ProcはVFX入口より前に確定し、VFX省略がGameplayへ影響しない。

### 33.3 ROOM / Loot / 検証

- 報酬中に次Map、Enemy/Boss SpriteFrames、装備Resourceを先行準備する。Stage敷設は複数Frame、Enemy生成は1体/Frame、
  戦闘開始時は全Spriteを同時表示しつつAI/Physics解除を2体/Frameに分散する。
- 2026-08-15 Windows headless計測ではROOM 2/4/12/13/24/25/36の同期入口0.048〜0.086ms、
  最大Frame 14.815〜17.578ms、ROOM 13 combat first 6.898ms、36回遷移Stress最大Stage slice 14.086ms、Node数増加0。
- 地面装備は縦Beamを廃止し、33.1の硬いPixel Plate/Outlineと少量FragmentでRarityを示す。
- `tests/pixel_visual_integration_check.tscn`は共通UI、風刃6 frame、全10 Fusion×5用途、Loot Plateを検証する。
  `tests/developer_test_lab_visual_check.tscn`、`tests/fusion_pixel_art_lab_visual_check.tscn`、
  `tests/light_dark_vfx_visual_check.tscn`、`tests/room_mvp_visual_check.tscn`はVulkan Forward Mobileで実描画を保存する。
- 36ROOMキーボード通しはHeadlessとVulkan実描画の双方で9 Boss、35属性報酬、18宝箱、Fusion成立、
  完成スキル6種を完走する。2026-08-15 Vulkan Runは434撃破、wall 431.48秒、RUN CLEAR後Title復帰、
  Debugger gameplay error 0、ブラックアウトなしを確認した。

## 34. 3MAP探索Run（2026年8月25日）

### 34.1 通常経路と互換境界

- `scenes/game.gd`は通常Main Scene時だけ`GameManager.start_run(false, true)`から`MapRunController.begin_run()`を呼ぶ。
  明示Debug ROOM requestは`RoomRunController`、Test Labへ埋め込んだGameは自動進行なしのSandboxとして分離する。
- ROOM 1/36、ROOM CLEAR、次ROOM選択、毎ROOM Cleanup/Rewardは通常MAP経路へ接続しない。
  ROOM Code/Data/Testは削除せず、事前Backup commit `8d41751` / branch `codex/room-system-backup-20260825`に固定した。
- 通常Runの可変状態はPlayer/Element/Skill/Equipment/COMBOをMAP間で維持し、Stage Actor/Loot/VFXだけをMAP遷移時に退役する。

### 34.2 MAP固定曲線

| MAP | 寸法 / 部屋 | 目安 / Boss解放（救済） | 通常敵HP / Damage | 同時上限 | Boss HP / Damage |
|---|---|---|---|---|---|
| 1 忘却の地下回廊 | 78×78 / 10 | 約10分 / 420体（15分） | ×2.50 / ×1.00 | 32 | ×2.2 / ×0.62 |
| 2 紫晶の深層 | 86×86 / 11 | 約11分 / 650体（16分） | ×3.25 / ×1.10 | 40 | ×3.8 / ×0.72 |
| 3 終焉の炉心 | 94×94 / 12 | 約12分 / 900体（17分） | ×4.00 / ×1.20 | 48 | ×5.8 / ×0.82 |

- 難易度はMAP番号・MAP内時間だけで決まり、Player火力、Attribute/Fusion/装備所持数から逆算しない。
- Boss領域は固定Timer待ちでは解放しない。通常は各MAPの累計撃破数で封印を解き、さらに最遠部のBoss Areaへ到達してE/Xを押す。
  拡散力のない極端なBuildでもRunが詰まらないよう15/16/17分だけ救済解放とし、HUDには撃破進捗と救済までの残り時間を表示する。
- MAP1開始Poolの平均HPは初期Soldier通常攻撃換算で約8.0Hit。後続MAPは想定Build成長を受けても
  通常敵8〜15Hit、強敵15〜25Hitを基準にする固定倍率であり、RuntimeのPlayer能力追従補正は行わない。
- `WaveSpawner`はPlayerから220〜480pxの床に1〜3体ずつ自然生成する。MAP内間隔は1.35→0.62秒へ変化し、
  Boss/Elite Encounter中は停止する。MAP切替で床Cache、Elite/Boss停止Counter、進行Offsetを必ずリセットする。
- `game.tscn`で旧ROOM/Test Lab用にDisabled配置された`WaveSpawner`/`EliteRoomManager`は、
  `MapRunController.begin_run()`時だけInheritへ戻す。通常MAPで自然SpawnとElite Areaが停止したままにならないこと。
- COMBO猶予は3.5秒。Triggered hitは数値へ加算するが猶予を更新せず、戦闘が途切れれば自然に切れる。

### 34.3 探索配置・報酬・回復

- 各MAPに通常/希少宝箱4、Attribute祭壇1、生命祭壇1、最遠部Boss領域1を配置する。
  宝箱/祭壇/Boss領域はPlayerの共通Interact登録を使い、範囲外E/X、二重Open、二重Rewardを拒否する。
- XP Level UpはAttribute 3択。Skillは通常宝箱の割当と各MAP Boss宝箱だけ。Fusionは6回目のAttribute取得を目安に
  MAP1後半〜MAP2で成立する。旧Concept Parts/Boardは通常UIへ出さない。
- 通常敵装備率2%、MAP Eliteは1体ごと確定、Bossは最低1個確定。宝箱Equipmentも実物Ground Itemとして生成する。
  Recoveryは通常/EliteのHeart Drop、宝箱Heart、生命祭壇40%、MAP間25%、Level Up12%を使用する。
- C/I Character ScreenはMAP戦闘中もModal pauseで安全に開け、Inventory/Equip/Mergeは通常Run進行と同じラン状態を参照する。

### 34.4 遷移・表示・検証

- 遷移はMAP間だけ。濃紺Pixel Overlayを表示し、`StageEnvironment.build_dungeon_async()`で敷設する。
  壁装飾/檻/結晶候補は全矩形走査ではなく床近傍/Room外周/床Cacheから列挙する。
- MAP HUDは2行進捗と案内文を別領域へ置く。Boss戦中はMAP進捗を一時非表示にしてBoss名/HPを優先し、終了後に復帰する。
- `--map-runtime-check`は実Game SceneでAttribute、3MAP、各Boss、Boss宝箱、Skill、Run Clearを短縮完走する。
  MAP2/3遷移の2026-08-25 headless最終実測は最大slice 21.842/24.338ms（最適化前53.698/71.546ms）。
- `--map-combat-check`は4倍速・無成長Soldierの通常移動Input/実近接Hitboxで、MAP1の自然撃破421/420を
  論理612.2秒で確認する。固定待機ではなく通常戦闘だけで約10分の解放条件へ届く。
- `--map-soak-check`は20倍速で論理2001.5秒、自然Spawn、通常宝箱12、Elite完了経路、3Boss、
  全遷移、敵上限32/40/48、Run Clearを確認する。
- `--map-gui-capture`はRTX 4060 / Vulkan Forward MobileでMAP開始、Boss領域、Boss戦を
  `artifacts/map_exploration_*.png`へ保存する。Debugger gameplay error、暗転残留、HUD重なりは0件。
- 31〜33章のROOM数値・検証結果は旧方式の回帰資料であり、現行通常Runの進行仕様は本34章を優先する。

---

**本仕様書の使い方**: この内容と実際のコード・データの間に相違がある場合、
仕様書または実装の片方を推測で上書きせず、関連Code / Scene / Resource / Data / Assetsと
直近の変更意図を確認してください。確認後に採用した現行仕様へ両者を同期し、同じ作業内で
整合性確認まで行います。プレイ調整済みの数値は明確な根拠なしに変更しません。
