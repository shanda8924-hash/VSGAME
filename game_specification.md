# ゲーム仕様書 v3.0(2026年8月15日時点)

> 本ドキュメントは、これまでの開発で決定した仕様を集約した「現時点の正(せい)」です。
> 過去の `design_proposal_v1.md`(初期設計書)から、プラットフォーム変更(スマホ→Steam)、
> ダンジョン構造の追加、職業システム、ボス戦、アイテムシステムなど、多くの点で
> 内容が更新されています。実装との相違が見つかった場合は、仕様書またはコードの片方を
> 推測で正とせず、関連するCode / Scene / Resource / Data / Assetsを確認したうえで、
> 採用する現行仕様へ両者を同じ作業内で同期します。

> **現行進行（2026-10-13）:** 床だけの広い戦場で約4分の大群戦、その後に強敵由来のBossを撃破してクリア。約5分が目標。壁・地形障害物なし。最新の数値・終了条件は末尾の2026-10-13節を参照。

---

## 1. 概要

| 項目 | 内容 |
|---|---|
| ジャンル | MAP探索型ローグライト・サバイバー |
| プラットフォーム | PC版とスマートフォン版（横画面）を開発中。スマホ実機・ストア向け書き出しは未検証 |
| 画面 | 横長ワイドスクリーン(既定ウィンドウサイズ1600×900、リサイズ可能。UI一部要素は1920×1080基準で設計されているが解像度非依存で動作する) |
| 操作 | キーボード(WASD/矢印キー)で移動。通常攻撃は自動、Kで回避、Lで職業固有アクティブスキル。共通InteractionはE、ゲームパッドX。ゲームパッド移動・UI操作対応 |
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
       → 敵撃破XPでLevel Up → 属性Lv/属性深化/条件強化/汎用/職業の統合3択
       → 宝箱をE/Xで開封 → 装備/回復/Skill/Attribute報酬
       → 撃破条件達成後、最深部Boss領域をE/Xで開始（長期探索時だけ救済解放）
       → Boss撃破 → 確定装備+Boss宝箱Skill → MAP 2
  → MAP 2 → MAP 3 Final Boss
  → RUN CLEARリザルト(Retry / Title)
  → 途中死亡 → RUN OVERリザルト
```

現行通常ゲームは3テーマを各20層、計60層として探索する。上の旧3MAPフローは初期仕様の記録。旧36 ROOMのScene/Controller/Data/Testは削除せず、
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
- 壁の見た目: 目地のはっきりした暗色レンガをベースに、旗・格子・松明を
  床がすぐ下にある正面壁だけへ低頻度で配置する。壁天面・側面には付けない。
- 出入り口(部屋と通路の接続部)は床の敷居と正面壁の旗で示す。
  壁奥の柱・void境界の柱列・柱画像のアーチ代用は使わない。通行を遮る実体柱はPillar Fieldのみ。
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

## 6. レベルアップ(統合成長3択+小回復)

- MAP通常進行では経験値が一定量たまると、属性Lv上げ・所持属性の
  属性深化カード・状態条件カード・既存汎用強化・既存職業強化を単一プールから3枚提示する。
  SkillはLevel Upへ混ぜず、宝箱/Boss宝箱だけから取得する。
- 必要XPは`28 + round((level - 1) * 1.7)`を基本とし、Lv5〜8は+5、Lv15〜18は+3で
  敵Roster解禁直後の連続Level Upを抑える。論25分の3 MAP実測モデルで各Level間隔を30〜42秒に収める。
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
- 戦利品選択カードは1600×900基準で、72×72pxのPixel icon、アイテム名24px、説明文20px、
  カード最小サイズ340×244pxとする。説明文は中央揃え・自動折り返しとする。
- `ItemData.icon_path`と`data/items/*.json`で旧互換報酬8種のiconを指定する。
  通常MAPのBoss宝箱で表示する完成済みSkill 23種も`data/skills/completed_skills.json`の
  `icon_path`から個別iconを表示し、画像がない定義だけ従来の文字iconへ戻す。
- iconはShikashi's Fantasy Icons Pack v2の透明版から32×32で切り出し、Nearestで72×72表示する。
  実使用31枚に加えて、全284候補の透明sheet、影付きsheet、原ライセンス／順序catalogを
  `assets/ui/icons/shikashi/`へ保持する。製品CreditにはShikashiとgame-icons.net（CC BY 3.0）を記載する。
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
- 武器Theme(炎/氷/雷等)ごとに生成Pixel PNGの着弾アニメーションを変える（§35.6）。属性成長システムは廃止済み。
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

#### 2026-09-07追補: 所有済み・未登録の通常敵10種

- `Desktop/111`のFull版42キャラクターは既存素材と一致。主人公10種・既存敵/ボスの
  重複取り込みは行わず、ユーザー承認により既存画像だけ存在していた次の10種を登録する。
  通常敵Catalogは12→22種。ボス10体、主人公10職業の登録・元画像は変更しない。

| 通常MAPの出現解禁 | 追加した敵ID |
|---|---|
| 0秒 | blood_monster_a / eyeball_monster / hellbat / lava_slime |
| 90秒 | blood_monster_b / demoness_a / ghostfire |
| 180秒 | demoness_b / hellhound / warlock |

- `data/enemies/*.json`→DataLoader→WaveSpawnerの既存経路へ接続。出現数/間隔/上限、
  既存12種の能力値は変えず、既存の弱〜中堅敵を基準に新規10種の初期値を設定する。
- 今回は共通の追跡AI・停止予備動作→近距離攻撃→クールダウンを使用する。
  付属の待機/歩行または飛行/攻撃1・2/被弾/死亡を再生し、既存の被弾/撃破/XP/Dropへ接続。
  固有の遠距離弾・召喚・状態付与・ボス化は未実装であり、素材の炎や魔法の見た目だけで付与しない。
- 元PNGの編集・複製は不要。`enemy/<名前>/<名前>`の既存影なしフォルダを直接参照する。
  GhostfireとLava SlimeのAttack02は同梱の`No beam effects`/`No spike effects`版を優先し、
  実判定に存在しない長距離ビーム/地面の棘を表示しない。この接尾辞は既存主人公/ボス/12種にはない。

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

### 16.2 キャラクター表示スケールの底上げ（現行Phase 2）

- Player: `entities/player/player.tscn` の `AnimatedSprite2D.scale` を
  1.2→1.5→**1.65**、当たり判定(体の`CircleShape2D.radius`を16→20、
  `HurtboxComponent`の`RectangleShape2D.size`を32×32→40×40)も
  キャラクター本体を包む現行40pxのまま維持した
- 通常敵: `entities/enemies/enemy_basic.gd` の `visual_scale_multiplier` の
  既定値を1.0→1.25→**1.40**に変更。この1値の変更だけで、`AnimatedSprite2D.scale`と
  当たり判定3種(本体`CollisionShape2D`・`HurtboxComponent`・`ContactHitbox`)が
  連動して拡大される(既存の`_scale_collision_shapes()`ロジックをそのまま利用)
- 精鋭部屋の敵: `systems/elite_room_manager.gd` の `elite_visual_scale` を
  1.3→1.6→**1.78**に変更(通常敵の1.40倍基準よりさらに一回り大きく)
- ボス: 旧倍率の相対差は廃止。Idle全コマの不透明範囲を素材ごとに実測し、全10体が
  **約65px高**になる個別倍率へ変更した。標準2D剣士（22px×1.65）に対して約1.79倍で、
  HD-2D試作のMinotaurと同じ体格差を通常2Dへ移している（詳細は§39）。
- 通常敵・精鋭・ボスは、見た目と3種の当たり判定を同じ倍率で連動させる。
  Playerは40px判定が1.65倍表示後の標準本体約36pxを引き続き包む。

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

- 武器名24px、数値18px、説明20pxを使用する。天賦図は278×112pxのノードへ拡大し、
  高さ520pxのScrollContainer内で表示する。Tab/矢印のフォーカスにスクロールが追従し、下段も読める。
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

**天賦図(TalentTree)UI — 見開き魔導書（2026-09-11更新）**:

- 同日配置調整: 起点中心Y270、分岐線Y326、流派見出しY338〜368、各段階中心Y410／486／562／638。文字の背後に接続線を通さず、最下段の外枠をページ下端の装飾から離す。

- `T`で直接開閉。ゲームパッドはBack。Escでも閉じられる。ポーズメニューの「天賦図 [T]」からも同じ本を開く。他の選択モーダルが開いている間は割り込まず、GameManagerのモーダル数を通じて停止・再開する。
- `ui/pause_menu/talent_grimoire.gd`が、生成背景`assets/ui/talent_grimoire/open_book.png`上へ操作できるノードと文字を描画する。羊皮紙、赤革、金の角金具、栞、書庫背景を参考画像に合わせ、1600×900基準で等比スケールする。
- 左ページは起点「居合」から乱撃派／一閃派の段階2〜5を金の円形印章と接続線で表示。習得済み・未習得（錠前）・別流派の選択不可を区別し、選択中は青緑の外周で示す。クリック・矢印・WASD・Tabで閲覧できる。
- 右ページは実Playerの肖像、職業名、現在の流派、職業熟練5段階、選択ノード名・実データの効果・習得状態・取得条件を表示。熟練は`get_class_ability_level()`を参照し、キャラクターEXPとは分離する。
- 天賦図は閲覧画面。取得・流派確定は既存のレベルアップ候補選択で行う。条件達成だけで取得できる表示にはしない。段階2の「双連斬／剛剣」等は天賦図内の短い表示名で、既存Upgrade IDと効果に接続する。
- 現行の分岐は剣士2流派のみ。他職業は「分岐は準備中」と実際の職業・熟練情報を表示し、架空の分岐や取得操作を追加しない。
- 「居合」は従来の起点名を維持。Spaceの能動スキルとは別の通常攻撃強化ツリーの表示。
- 生成プロンプトと再利用方法は`assets/ui/talent_grimoire/README.md`。報告用実画面は`artifacts/talent_grimoire/implemented.png`。

**戦闘・魔法Pixel iconの接続(2026-09-10)**:

- `UpgradeData.icon_path`を追加し、全85件の通常/条件/Shop/職業強化へ72×72の
  個別iconを割り当てた。`LevelUpSelect`と`ShopScreen`は同じdata pathを読むため、
  同じ強化が画面ごとに違う図柄にならない。path未設定・読込失敗時は従来のcategory
  iconへfallbackする。
- 物理技はsteel/cyan系の剣・斧・弓、burningは赤、charged/markedは黄、frozenは青、
  cursedは紫で統一した。×2/×3は攻撃回数、扇状の刃は範囲/多段、光点は会心、
  円環はfield/barrierという意味を優先して選定した。
- Swordsman天賦図の起点と8ノードは、LevelUpと同じ職業強化iconを表示する。
  習得済みは原色、未到達は55%、選択不可側は28%のopacityで、既存の枠色・lock表示と
  同じ進行状態を示す。
- Boss報酬の完成大技23件も魔法系sheetの図柄へ更新した。元のShikashi iconは削除せず、
  旧Boss ItemData 8件と将来候補として保持する。原sheetと全割り当て座標は
  `assets/ui/icons/battle_skills/source/`と`mapping.csv`へ保存する。
- 全191 GDScript load、実GameのLevel Up/天賦図/完成大技UI、Shop購入・補充、
  通常3MAPのBoss報酬→遷移→RUN CLEARを再実行してPASS。実描画は
  `artifacts/secondary_readability_level_up_icons.png`、`secondary_readability_talent_top.png`、
  `secondary_readability_completed_skill_select.png`、`shop_screen.png`へ保存した。

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

**2026-09-11 現行仕様**: 正式Playerはソルジャー・剣士・弓兵・騎士・重装斧兵・魔導士の6職。`GameManager.PLAYABLE_CHARACTER_IDS`を基準に選択画面を3列×2段、350×280pxの石枠カードへ変更した。槍兵・聖堂騎士・司祭・死霊術師のデータはボス転用に備えて保持し、Player選択には出さない。旧IDが選択状態に残っている場合は開始時にソルジャーへ戻す。解放済み記録・通貨は削除しない。未解放職業の肖像も見えるようにし、解放条件は文字で表示する。以下の10職業／5列の記述は旧版の履歴であり、現行仕様は本段落を優先する。


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
- `GroundEquipmentItem`を地面へ実体として生成する。通常の時間寿命は持たないが、
  Uncommon / Rare / Epicの未取得品は維持上限を24個とし、上限を超えた場合は生成時刻が
  最も古い品を1.2秒点滅させてから消滅させる。点滅中だけ実Node数は一時的に上限を超える。
  点滅中も取得可能で、削除予約中の品も上限判定へ含めて同じ品の二重予約を防ぐ。
  Legendary / Mythicはこの自動整理の対象外とする。
  上限値と点滅時間は`data/equipment/drop_table.json`の
  `ground_item_low_rarity_cap` / `ground_item_expiration_warning_seconds`で管理する
- 取得範囲72pxへ入ると、レアリティ色のアイテム名・レアリティ名・
  「E / X：拾う」を表示する。EキーまたはゲームパッドXで最寄りの1個を取得する
- 地面表示は64×64pxの画像全体ではなく、生成時に保存した`EquipmentIconMetrics.BOUNDS`の
  不透明画素範囲をVisual Sizeとして扱う。Drop時のGPU `texture.get_image()`は行わない。現在のプレイヤーフレームの不透明画素高と
  `AnimatedSprite2D.global_scale`から見た目の高さを求め、装備本体をその82%（最小24px、最大42px）へ
  正規化する。全10職業で結果がプレイヤー本体の70〜100%に収まることを回帰テストする
- カード背景、上下浮遊、バウンド、大きな装備Sprite、円形・楕円形のレアリティリング、縦方向Loot Beamは
  使用しない。アイコン真下の`PixelLootPlate`/非AA Outlineへ、古金の角飾りと1〜5個のレアリティ刻印を加える
- レアリティはPlate/Outline色、刻印数、常駐Pixel粒子数（Uncommon 2 / Rare 3 / Epic 4 / Legendary 5 / Mythic 6）で区別する。
  Drop瞬間は0.7秒の局所展開→崩壊と6〜14粒の短いBurst。長いBeam・柔らかいGlow・全画面Flashは生成しない
- Drop瞬間のBurst Nodeは再生完了時に解放し、常駐粒子は画面外で停止・画面内で再開する。
  アイテム名と取得Promptはプレイヤーが取得範囲へ初めて入った時点で生成する
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
Legendary/Mythicは橙/赤の生成Pixel紋章と短い6コマ出現画像で強調する。
地面演出は静止`loot_seal.png`1枚＋0.7秒の`loot_awaken.png`1枚。常駐粒子・線・Polygon台座は使わない。
紋章の色と寸法をレアリティで変え、巨大リング・縦Beam・柔らかい足元Glowは生成しない。一方、装備本体は
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

- 2026-09-11: 中央タブ、レア度／並び順、鍛造切替、装備・解除を青石と古金の画像枠へ統一。左下はアイコン・能力名・数値の3列、HP／攻撃力／防御力／移動速度／会心率／会心ダメージの6行を18pxで表示。202pxの専用枠に収め、折り返しを無効化する。
- ALLの下の部位フィルタは、新規生成の白黒シルエット6種（剣・兜・胴・手袋・靴・指輪）。実在装備のアイコンはフィルタで使用しない。生成原画`assets/ui/relic_frames/equipment_parts.png`を領域参照し、黒マット除去は描画Shaderで行う。


- 2026-09-11装飾更新: `assets/ui/relic_frames/ornament_atlas.png`の生成石枠・彫金・紋章・尖形見出しを実UIに使用。
  `ui/common/relic_frame_art.gd`の伸縮描画で四隅金具を保ち、比較枠・所持金枠にも再利用する。詳細は白い名前、Rarity色、錠前、能力画像と数値列、現装備画像付き比較を表示する。

- `ui/equipment/equipment_screen.tscn`をCキーまたはゲームパッドYで開閉する。
  Iキーは旧装備画面からの互換エイリアスとして同じ画面を開く。ESCでも閉じられる。
  既存モーダルが開いている間は割り込まず、`GameManager.active_modal_count`を使って
  安全に一時停止する
- 1600×900で「装備／所持品／右操作」の3列を常時表示する。左はキャラクターと周囲6装備スロット・現在ステータス、
  中央は5列の実アイコングリッド、右は既定の装備詳細と遺物鍛造を上部タブで切り替える。
  右タブだけを切り替え、装備欄と所持品は常に残す。所持品の選択は鍛造中も同じ一覧から行う。
- 所持品には部位タブ（全て／武器／頭／胴／腕／脚／装飾）、レア度Filter、整理順を置く。
  選択品はレア度枠の内側へ古金、外周の四隅へ青緑の選択標を表示する。装備中は`E`、保護中は`◆`、
  お気に入りは`★`、鍛造候補は`鍛`で示す。所持上限は50枠とし、`所持数 / 50`を表示する。
  満杯時は拾得を成立させず、地面の装備を残して消失を防ぐ。
- 比較は同じスロットの現在装備を基準に、各値を「現在→選択中」と表示する。
  上昇=緑の↑、低下=赤の↓、同値=灰色の=を用いる
- 地面取得後は所持一覧へ即時追加する。通常ROOM RunではCLEAR/REWARD/次ROOM準備中だけC/I画面を開け、
  COMBAT中は開かない。装備画面を閉じると準備済みの次ROOMへ自動遷移する
- 地面ドロップ、所持装備一覧、中央の装備済みスロットは、同じ`icon_path`の画像を表示する。
  取得や装備で別画像へ置き換えず、装備実体の同一性を視覚的に維持する
- 宝物庫に「レア度順／部位順／新規入手順」とレア度Filterを設ける。表示用コピーだけを整理し、Inventoryの内容・取得順データは変えない。
- 右側の遺物鍛造タブに素材3個、`現Rarity ×3 → 次Rarity ×1`プレビュー、合成Button、完成品を表示する。
  一覧クリックは比較対象の選択だけ。「素材に追加」で空きSlotへ置き、素材Slotの選択で取り外す。
  所持カード単位の`1 / 3`表示は行わない。素材を置いても他Rarityや装備品を自動で隠さない。
  「同レア3点セット」は未装備・未Lockの完全な3点を候補へ並べるだけで、消費は合成確定時のみ。
  整理/任意Filter/素材全解除は同時に操作できる。最上位Mythicは合成候補にしない。
  装備中・Lock中も比較・装備操作は可能だが、素材追加は拒否する。「装備を外す」は選択品自身が装備中の時だけ有効。
  装備枠の選択でも比較対象を指定でき、素材に置いた品を装備すると素材候補から自動で外れる。
  完成品はFilterを解除して中央で選択し、右側を装備詳細へ戻して比較と即時装備を可能にする。
  比較/完成品/装備枠のRarity文字は基準色から28%明るくし、枠とDataの色は変更しない。
  比較対象が変わった時だけ説明のスクロールを先頭へ戻す。同じ対象の更新では読んでいる位置を保つ。
- 合成演出は約1.64秒。右欄へ収まる古代炉・金属刻印・八角紋章台へ3つの実Iconが収束し、局所Pixel FragmentとImpactを経て完成Iconを開示する。
  炉内部の132px原寸描画を欄の寸法へ合わせて縮小し、所持品・装備枠を覆わない。
  Impact/Fragmentは新規`forge_awaken.png`の6コマで再生し、Rarityで表示寸法と弱い色味を変える。
  出現/合成画像のTintは75%白へ寄せ、青・紫Rarityでも原画の金/白い芯を濁らせない。静止紋章はRarity色そのまま。
  合成用画像1枚は戦闘VFX予算とは独立させ、Pause中の戦闘VFX飽和でも演出を欠落させない。
  巨大Bloom・Gradient・全画面Flashは使用しない。
  初回は全再生し、2回目以降はMouse / E(`interact`) / 決定(`ui_accept`)で表示だけをSkipできる。
  合成中Flagにより連打しても取引は1回だけ実行する。SkipはGUIより先に入力を捕捉し、全子Tweenを停止してから演出Nodeを解放する
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
- 2026-09-05のRoyal版は`tools/source_art/royal_equipment_atlas.png`の新規25画像を`import-royal-atlas`で切り出し、
  2px論理ドット・64x64へ正規化する。`validate-catalog`で25種・画像重複なし・二値透過・offline Bounds一致を検査する。
  同時生成する`resources/equipment_icon_metrics.gd`も素材と一緒に更新する。
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

- 2026-09-05: 下記25種を新規Royal Pixel Artへ差し替え。`icon_path`は維持し、地面/宝物庫/装備/合成を同じ画像へ接続。
  原画・生成指示は`tools/source_art/royal_equipment_*`、目視一覧は`artifacts/royal_equipment_contact_sheet.png`。
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

Godot側の地面レアリティ演出は§23.4の生成画像2枚方式とする。
リング・縦方向Loot Beam・柔らかいGlowは生成しない。Legendary/Mythicほど紋章を大きく明確にする。
装備アイコン本体には演出を焼き込まず、地面・インベントリ・装備済みスロットで同じ画像を再利用する。

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
  周囲へ武器・頭・胴・腕・脚・アクセサリーの6スロットを配置する。中央は部位Filter付き5列所持品、
  右は選択品の大Icon・Rarity・能力差・現在装備との比較を表示し、右上タブから遺物鍛造へ切り替える
- 下部にHP、攻撃力、防御力、攻撃速度、移動速度、Crit率、Critダメージを表示する。
  総合戦闘力は導入しない
- 既存ラン内Inventoryを再利用し、所持上限は50。満杯時の拾得品は地面へ残す。
  比較欄は現在→候補、↑/↓/=、固定値と%を区別して表示し、「装備する」「外す」で即時再集計・再描画する。
  お気に入り`★`と鍛造保護`◆`はラン中の装備実体へ保持する
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
- CONCEPT: 旧Parts/Boardに加え、完成大技5種の選択、GRANT/Lv.UP、即時発動、Cooldown READY、
  24体固定Target、全大技連続Previewを提供する。状態欄で各大技のLvと残Cooldownを確認できる
- RESET STATEは生成物、Boss、Enemy、Projectile、Transient VFX、装備、属性/Fusion、Player、
  Damage Meterを初期化し、実Game Sceneは保持する。RELOAD GAMEは実Game Scene自体を再生成する

### 30.3 検証

- `tests/developer_test_lab_check.tscn`: 実Game接続、LevelUp、5属性、全10 Fusion、自然Fusion、
  4択報酬、Enemy/Boss、Equipment/Merge/Loot、Projectile、Resetを自動検証する
- `tests/developer_test_lab_visual_check.tscn`: Vulkan 1600×900でPanel、実Game Field、Fusion VFX、
  全Rarity Loot、生成済み風刃、完成大技5種の固有シルエットを描画し、`artifacts/developer_test_lab/`へ保存する
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

- 既存18種の条件追撃に加え、独立Cooldownで敵群を自動捕捉する完成大技を5種追加する。

| 属性 | 完成大技 | Lv1→Lv3基礎Cooldown | 主シルエット / 補助 |
|---|---|---|---|
| 雷 | 雷帝落雷 | 7.5→5.5秒 | 巨大縦雷剣 / 連鎖 |
| 火 | 煉火天柱 | 9.0→7.0秒 | 中心火柱+二重衝撃輪 / 範囲 |
| 氷 | 氷槍豪雨 | 10.0→8.0秒 | 放射氷槍 / 遅延Echo |
| 光 | 光刃陣 | 8.5→6.5秒 | 放射光刃+中核 / 範囲 |
| 闇 | 虚無断界 | 11.0→8.0秒 | 水平の虚無裂界 / 範囲 |

- 初取得は1.1秒のWarm-up後、敵が自動捕捉範囲へ入った時だけ発動する。敵不在ではCooldownを消費せずREADYを保持する。
  属性Stack Lv2/Lv3は1段階ごとDamage +16%、Reach +8%、Cooldown -7%。既存Element/Fusion Masteryも重ねる。
  基礎Damageは選択Character、固定強化、装備Attack、低HP条件倍率を使用し、完成大技だけ固定14 Damageへ置き去りにしない。
- 固有VFXは主Spriteの移動/全体Fadeや全画面Flashを使わず、発生点で硬い非AA形状を展開し、短い保持後にY圧縮・破片化して退役する。
  雷/火/氷/光/闇は大技定義色を優先し、敵攻撃・背景と区別できる。

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
- ECHOのawait中に対象が死亡/queue_freeされた場合は、終了時に参照を再検証する。解放済みNodeを型付き引数へ渡さず、
  Echoだけは元着弾地点で成立させ、Focusは生存対象が無ければ中止する。
- `tests/concept_build_runtime_check.tscn`で旧Concept Parts、完成済みSkillの6種上限/Lv.UP/日本語Key、
  雷鳴連鎖、導電炎、Cross候補、Trigger再帰防止、Metadata、Developer Board modalを検証する。
- `tests/signature_skill_runtime_check.tscn`は5種Data/Profile、Lv/属性/装備Damage、Cooldown自動復帰、敵不在READY、
  対象削除中Echo、5種同時Cooldown Stressを検証する。2026-08-25実測の定常PeakはTransient VFX 13、終了後残留0。

### 32.5 全体監査・安定化（2026年8月14日）

- Soldierの初期DamageはReferenceと同じ14。近接攻撃は0.18秒の予備動作開始時の向きを保持し、
  命中判定直前の移動入力で逆方向へ反転して至近距離の敵を永久に外さない。
- `ChaseStrategy`は直接床Lineが通る間は従来の直進を使い、障害物で遮られた場合だけ280ms間隔の軽量Grid経路へ切り替える。
  中間Cellは周囲1 Cellの床余白を要求し、柱角へPlayer/EnemyのCollisionが食い込んで停止する経路を選ばない。
  この「周囲1 Cellの床余白」判定と再探索の間引きは2026年9月に性能上の理由で作り直した（38章参照）。
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

**現行追記（2026-09-23）:** 大群・自動攻撃・広いランダム部屋へ復帰。現行仕様は本書末尾の2026-09-23節を参照。以下は2026-09-15時点の履歴：3つの作画テーマを各20層、計60層へ拡張。各層は`ExplorationLayout`で再生成し、部屋別の有限遭遇、番人の鍵、各層のボス、別位置の階段を使う。旧撃破数・大量自然湧き・3MAP終了の数値は履歴として以下に残す。現在値は本章末の2026-09-15節を参照。

### 34.1 通常経路と互換境界

- `scenes/game.gd`は通常Main Scene時だけ`GameManager.start_run(false, true)`から`MapRunController.begin_run()`を呼ぶ。
  明示Debug ROOM requestは`RoomRunController`、Test Labへ埋め込んだGameは自動進行なしのSandboxとして分離する。
- ROOM 1/36、ROOM CLEAR、次ROOM選択、毎ROOM Cleanup/Rewardは通常MAP経路へ接続しない。
  ROOM Code/Data/Testは削除せず、事前Backup commit `8d41751` / branch `codex/room-system-backup-20260825`に固定した。
- 通常Runの可変状態はPlayer/Element/Skill/Equipment/COMBOをMAP間で維持し、Stage Actor/Loot/VFXだけをMAP遷移時に退役する。

### 34.2 MAP固定曲線

| MAP | 寸法 / 部屋 | 目安 / Boss解放（救済） | 通常敵HP / Damage | 同時上限 | Boss HP / Damage |
|---|---|---|---|---|---|
| 1 忘却の地下回廊 | 78×78 / 10 | 約10分 / 420体（15分） | ×2.80 / ×1.00 | 96 | ×3.0 / ×0.62 |
| 2 紫晶の深層 | 86×86 / 11 | 約11分 / 650体（16分） | ×3.60 / ×1.10 | 144 | ×4.6 / ×0.72 |
| 3 終焉の炉心 | 94×94 / 12 | 約12分 / 900体（17分） | ×4.50 / ×1.20 | 192 | ×6.8 / ×0.82 |

- 難易度はMAP番号・MAP内時間だけで決まり、Player火力、Attribute/Fusion/装備所持数から逆算しない。
- Boss領域は固定Timer待ちでは解放しない。通常は各MAPの累計撃破数で封印を解き、さらに最遠部のBoss Areaへ到達してE/Xを押す。
  拡散力のない極端なBuildでもRunが詰まらないよう15/16/17分だけ救済解放とし、HUDには撃破進捗と救済までの残り時間を表示する。
- MAP1開始Poolの平均HPは初期Soldier通常攻撃換算で約8.0Hit。後続MAPは想定Build成長を受けても
  通常敵8〜15Hit、強敵15〜25Hitを基準にする固定倍率であり、RuntimeのPlayer能力追従補正は行わない。
- `WaveSpawner`はPlayerから220〜480pxの床に自然生成する。MAP開始時は2.80秒ごとに1体、
  90/210/360/540/720秒のBreakpointを経て、出現間隔は従来のまま、同時数だけ
  1→1〜2→2〜3→3〜5→5〜8→8〜12体へ段階上昇する。生存敵上限はMAP1/2/3で96/144/192体。
  Boss/Elite Encounter中は停止する。MAP切替で床Cache、Elite/Boss停止Counter、進行Offsetを必ずリセットする。
- 各MAPはBoss必要撃破数の25% / 50% / 75%で侵攻（Surge）を開始する。未到達時はMAP 1=
  180/360/540秒、MAP 2=195/390/585秒、MAP 3=210/420/630秒で同じ侵攻へ入る。
  侵攻は45秒、Spawn間隔×0.5、同時Spawn batch×1.5。整数化後も生存敵上限96/144/192を共用し、
  敵HP・敵1発Damage・`MAX_DAMAGE_PER_HIT_RATIO`は通常時から変更しない。
- 侵攻中はHUDへ回数/残り秒/敵密度上昇を常時表示し、Stageを短い紫系Toneへ変える。開始/終了SFXを鳴らし、
  終了ごとにRecovery→Equipment→Recoveryの順で確定DropをPlayer付近の到達可能床へ生成する。
- `game.tscn`で旧ROOM/Test Lab用にDisabled配置された`WaveSpawner`/`EliteRoomManager`は、
  `MapRunController.begin_run()`時だけInheritへ戻す。通常MAPで自然SpawnとElite Areaが停止したままにならないこと。
- COMBO猶予は3.5秒。Triggered hitは数値へ加算するが猶予を更新せず、戦闘が途切れれば自然に切れる。

### 34.3 戦闘地形と生成タイル

- 各通常生成MAPは専用Boss Arenaを先に予約し、他の部屋へArena / Pillar Field / Chokepointを割り当てる。
  Arenaは四方からの大群処理、Pillar Fieldは直線追跡を切る回避を担う。
  2026-09-05追加修正で、橙の格子が並ぶHazard領域と床Damageの生成を廃止した。
  Chokepointは横長部屋内の縦短壁と中央3セルの開口だけ維持し、縦長部屋へ並ぶ横短壁は生成しない。
- Pillar/Chokepoint障害物は通常壁と同じTileSet Physics layer 1を使用する。Pillarは2x2セルの一体画像で、
  A/B 2種を決定的に混在させる。柱本体2セル+通行間隔3セルの5セルpitchと中央十字レーンを維持し、
  4セルすべてをPlayer/敵が通過しない。下地は同じ石床にCollision alternative 3を付け、柱の透過画像を別Layerへ重ねる。
  旧Hazard型/画像/設定値は互換用に残るが、通常MAPの割当とArea生成からは切り離す。敵の毒床など攻撃Hazardは対象外。
- 敵の出現位置は`DungeonMap.get_spawn_cells()`を使い、既存の3×3通行余裕がある床に限定する。
  噴水はPillar FieldのB画像であり、4セルの障害物登録/Collisionは正しかったが、旧精鋭部屋の矩形乱数には
  床検査がなく内部へ生成できた。床だけを見る通常/巡回精鋭/Bossも、本体半径ぶんの余白を取っていなかった。
  室内精鋭は同じ部屋内の安全床、通常/サージ/巡回精鋭/Bossは従来の距離条件と安全床を併用する。
  Boss召喚の円周候補も`find_spawn_position_near()`で安全セルへ寄せる。地形/本体Collision/敵数値は変えない。
  安全床一覧は既存clearance cacheと同時に構築し、地形変更まで再利用する。毎Spawnで全床の通行判定をやり直さない。
  候補なしは`Vector2.INF`を返し生成を中止する（地形内へのfallback/無限再抽選なし）。
  全員生成できない精鋭部屋は既存の空部屋解放処理、巡回精鋭は既存の再試行に従う。
  `tests/fountain_spawn_check.tscn`で実噴水Collision・各出現経路・実精鋭移動・実Boss召喚・空候補を検証する。
- 生成後はSpawn床から全床への4近傍BFSを行う。`tests/map_terrain_rhythm_check.gd`は3サイズ×12 seed=
  36生成MAPについて到達不能床0、現行3地形、Hazard不存在、壁下地と透過装飾、障害物を自動検証する。
- 床・収納装飾は`assets/tiles/royal/dungeon_atlas.png`（352x192）を使用する。
  普通壁は元の暗い上面/明るい正面を保持し、加工した接合部とともに`wall_relief.png`へ集約する（§35.8）。
  `CombatTerrainTileMapLayer`は`assets/tiles/royal/combat_atlas.png`（128x96、16px単位8x6）を使用し、
  Arena=row 0 col 0〜3、Hazard=row 0 col 4〜7、Pillar床=row 1 col 0〜3、Chokepoint床=row 1 col 4〜7、
  旧Chokepoint壁/Pillar合成済みタイルは現行描画に使わない。短壁は主壁材、柱は`wall_overlays.png`を使う。
- `tools/build_royal_dungeon.py`が生成原画`tools/source_art/royal_dungeon_source.png`から再生成する。
  床は地形タイプをまたいで同じ青灰色石材。通常MAPには危険噴出口を描かない。
  壁正面/天面は方向で選び、緑/紫のランダムな色帯は使用しない。樽/木箱は1タイル内に全体を収め、
  壁奥へ退避する入口柱、void境界の柱列、柱に見えるアーチ装飾は廃止する。
  入口は元の床開口に敷居を置き、旗・格子・松明は直下に床がある正面壁だけに配置する。
  正面壁の旗/格子/壁付柱は透過Overlayとして重ね、下地の壁や笠木を置換しない。
  2x2柱・噴水の通行不可範囲は維持。Boss部屋予約と撤回したHazard/横短壁以外の地形構造は維持する。
  松明16x24は6コマ8fps、結晶24x24は静止画を整数2倍表示。開始床に透過の金象嵌を配置する。
  2x2障害物のA/Bは柱/噴水。`artifacts/royal_dungeon_asset_preview.png`はオフライン素材組立見本であり、Runtimeの証拠ではない。
- MAP2「紫晶の深層」とMAP3「終焉の炉心」は、MAP1と同じ部屋生成・通路・Boss予約・安全床・衝突規則を使い、
  景観素材だけを専用化する。MAP2は暗紫の連続石床、青緑の鉱脈、紫晶群・封印碑・採掘台車。MAP3は煤けた炉床、
  赤熱亀裂、溶鉱炉・金床・歯車・排気塔で構成する。voidもMAP2は濃紺、MAP3は暗い焦茶へ分離する。
- MAP2/3の床は256x256の連続Macro Atlasを16px単位で参照し、部屋ごとに32pxの亀裂・鉱脈・格子・残滓を
  決定的に配置する。16px単位で同じ印が並ぶCombat Overlayは透明化し、壁の色線も反復させない。
  大型小物は各MAP4種、MAP2は18個、MAP3は16個を置く。全て足元Collision付きでPlayer/敵が通過しない。
- MAP2/3の壁Atlasは1024x256。床8近傍256形状ごとに4種の石組みを持ち、座標Hashで欠け・継ぎ目を変える。
  結晶埋没／鉄帯／炉刻印の強い装飾は約2%だけに置き、長い壁で同じ記号を反復させない。
  透過壁装飾もMAP別に生成し、入口旗、Boss旗、壁柱、檻、Pillar Fieldを紫晶建築／炉心建築へ分離する。
  MAP2/3だけ壁掛け・檻をやや増やし、MAP1の密度と素材は変更しない。
- `tools/build_map_themes.py`が両MAPのRuntime素材を再生成する。`tests/map_theme_check.tscn`は専用床、Detail、
  4種小物、壁・小物Collisionを3MAP同条件で検証し、`tools/capture_map_themes.tscn`は
  `artifacts/map_themes/map1.png`〜`map3.png`を比較用に保存する。

### 34.4 探索配置・報酬・回復

- 各通常MAPに通常/希少宝箱4、生命祭壇1、最遠部Boss領域1を配置する（Attribute祭壇は§36の廃止に伴い生成しない）。
  Boss部屋indexはGenerator/描画/Controllerで共有し、探索宝箱・生命祭壇・Elite部屋を同じ部屋へ割り当てない。
  宝箱/祭壇/Boss領域はPlayerの共通Interact登録を使い、範囲外E/X、二重Open、二重Rewardを拒否する。
- XP Level Upは6章/36章の統合成長3択。Skillは通常宝箱の割当と各MAP Boss宝箱だけ。Fusionは
  属性Lv選択で両属性がLv3へ到達した時点で成立する。旧Concept Parts/Boardは通常UIへ出さない。
- Skill候補は現在の1〜2属性だけから選び、完成大技へ+1.65の初回Weightを与える。取得済みSkillのLv.UP優先は従来どおり維持する。
- 通常敵装備率2%、MAP Eliteは1体ごと確定、Bossは最低1個確定。宝箱Equipmentも実物Ground Itemとして生成する。
  Recoveryは通常/EliteのHeart Drop、宝箱Heart、生命祭壇40%、MAP間25%、Level Up12%を使用する。
- C/I Character ScreenはMAP戦闘中もModal pauseで安全に開け、Inventory/Equip/Mergeは通常Run進行と同じラン状態を参照する。

### 34.5 遷移・表示・検証

- 遷移はMAP間だけ。濃紺Pixel Overlayを表示し、`StageEnvironment.build_dungeon_async()`で敷設する。
  壁装飾/檻/結晶候補は全矩形走査ではなく床近傍/Room外周/床Cacheから列挙する。
- MAP HUDは2行進捗と案内文を別領域へ置く。Boss戦中はMAP進捗を一時非表示にしてBoss名/HPを優先し、終了後に復帰する。
- `--map-runtime-check`は実Game SceneでAttribute、3MAP、各Boss、Boss宝箱、Skill、Run Clearを短縮完走する。
  MAP2/3遷移の2026-08-25 headless最終実測は最大slice 21.842/24.338ms（最適化前53.698/71.546ms）。
- 同Checkは3MAPすべてで撃破率/時間の両入口、侵攻3回の終了、確定報酬、Spawn間隔/Batch、敵上限、
  Damage倍率不変も検証する。`--map-terrain-rhythm-check`は実Tile描画、Physics layer 1、通常MAPのHazard不存在、
  柱越しの敵追跡をVulkan Runtimeで検証する。
- `--map-combat-check`は4倍速・雷Lv3+雷帝落雷Lv1のMAP1中盤代表Build、通常移動Input/実近接Hitboxで、
  Phase 1調整後の自然撃破424/420を論理432.3秒で確認する。序盤78秒25体、中盤308秒207体、
  終盤432秒424体と増加率が明確に上がる。4倍速・検証用高HP条件のため実プレイヤー中央値ではない。
- `--map-soak-check`は20倍速で論理1998.5秒、自然Spawn、時間側侵攻3回/各MAP、通常宝箱、Elite完了経路、
  3Boss、全遷移、敵上限32/40/48、Run Clearを確認する。
- `--map-gui-capture`はRTX 4060 / Vulkan Forward Mobileで4地形を`artifacts/map_region_*.png`、
  侵攻中画面を`artifacts/map_surge.png`へ保存する。Combat地形差し替え後も4地形、2x2 Pillar、Player/敵/宝箱の
  可読性を確認し、Debugger gameplay error、暗転残留、HUD重なりは0件。
- 31〜33章のROOM数値・検証結果は旧方式の回帰資料であり、現行通常Runの進行仕様は本34章を優先する。

## 35. 古王国Pixel UI（2026年9月5日ブラッシュアップ）

既存のHUD・Shop・LevelUp・宝物庫・鍛造を「朽ちた王国の地下遺跡」で統一する。
今回の変更は表示と所持品の操作補助。戦闘数値・抽選・価格・セーブ・成長条件は変えない。

### 35.1 色と文字

`PixelUIStyle` / `RetroHUDStyle`は濃紺 `#151b29`、青紺石板、古金
`#9d7138 / #d6a957`、象牙文字 `#f2e6cd`、緑玉 `#70d5cc`を基準にする。
HPは赤、職業スキルは青緑。本文20px、補助18px以上、見出し24〜32pxを基準にする。
文字は可読性を優先し`assets/fonts/MPLUS1p-Medium.ttf`（Google Fonts公式/OFL同梱）を使用する。
FontFileはgrayscale AA有効・subpixel配置無効。通常Labelに加えRichTextLabelのnormal/bold等も同じ書体へ揃える。
小さい日本語のドット書体・太い縁取り・影重ねを廃止する。枠/装備画像/マップのPixel Artと最近傍表示は維持する。
既存Sceneは同じテーマを使い、欠落時だけGodotフォントへフォールバックする。

### 35.2 枠・装飾

`RetroPanel.content`はそのまま使い、48x48の金属9-slice（patch 10px）と濃紺中央へ変更する。
旧グラデーション/ガラス光沢/複数Glow矩形は描かない。古金の角鎹・緑玉の印章・翼付き紋章は
`PixelUIStyle.RelicOrnament`の非AAドット描画で加える。Containerの本文レイアウトから装飾を分離する。
静止パネルは毎frame更新せず、サイズ・フォーカス変更時だけ再描画する。

### 35.3 HUD配置

1600x900基準で、左上に職業/LV/HP/細いXP、上中央にMAP名・封印解除進捗・時間救済の案内、
右上に所持金と探索情報、下中央に職業スキルとSPACE/残り秒数・5段階ピップ、右下にComboを置く。
実Boss戦中は既存Boss名/HP表示を優先する。旧属性/Fusion欄は復活させない。
HP枠は370×132px、技枠は560×96px。MAP本文20pxには濃紺の静的背景を付け、背景タイルから分離する。
HP/技の本文20px、Gold22px。取得時の動的通知も同じ日本語書体を使う。
LVバッジは濃紺背景と金文字にする。右上トレイは幅276px内で132px×2列へ折り返す。
武器/アイテム/完成技は18pxの固定幅Labelで名前だけ省略し、個数/Lvは残す。全文はTooltipへ表示する。
`RetroSegmentGauge`と`RetroPipRow`は既存値を描画するのみで、成長・ダメージ計算は持たない。

### 35.4 選択画面

- LevelUpは「魂の刻印」。3枚の石板に種類・アイコン・名前・説明・取得段階を分離し、
  現職固有/状態反応/基礎能力を見分ける。候補生成や付与効果は既存のまま。
- Shopは「灯火の遺物商」。ランタン/木箱と古金の紋章、4枚の商品カード、所持金/不足額、
  購入後残高の案内を表示する。購入/リロール結果は自動focus復帰で消さない。
- Keyboard/Gamepadでカードを選び決定する。Mouse必須にはしない。
- Shopカードは420×250px以上、LevelUpは360×322px。種類18px・名前26px・本文/価格20px。
  Shop4枚/LevelUp3枚を1600×900へ収める。
- タイトルの説明は幅640pxの枠で折り返し、文字拡大で枠外に出ないようにする。
- 宝物庫と鍛造の整理・候補補助・演出は§23.6。部品再利用を優先する制約より世界観の一貫性を優先する。
- アイテムボックスは左に装備紙人形、中央に5列所持品、右に大きな選択Icon・Rarity・部位・現在装備との差分を置く。
  濃紺石板、古金の装備枠、青緑の操作焦点、Rarity色の外枠を同時に使い、画像モックと実画面で同じ情報階層にする。
  Complete UI Book Styles Pack FreeのCoin／Starを所持金とお気に入りへ最近傍表示で使う。青緑の選択角は
  伸縮によるPixel崩れを避けるため整数座標で描き、Creditと変更内容は`assets/ui/complete_ui_pack/README.md`と各Licenseへ記録する。

### 35.4b 生成石枠の全画面展開（2026-09-11）

**同日更新・タイトルの例外**: タイトルは専用キービジュアル`title_sealed_kingdom.png`を採用。共通石枠・見出し札はタイトルから撤去し、銀のVS GAMEロゴと封印門の一枚絵に、左下の文字メニューを重ねる。通常探索・演出確認室の選択は維持。下記のタイトル石枠適用は旧版の記録。素材生成指示は`assets/ui/backgrounds/TITLE_KEYART.md`。


- 共通`PixelUIStyle`のボタン・パネル・三択カード・主要枠を`relic_frame_art.gd`の生成画像へ統合。石の二重枠、古金の彫金、四隅金具を共有し、細枠と厚枠を用途で分ける。アイテムのレア度枠は従来の識別色を保持。
- レベルアップ三択は王家の紋章と青緑、ボス戦利品三択は新規生成の髑髏紋章と赤銅。タイトルと6職選択には尖形の見出し札を配置。共通スタイルを使用するショップ・探索記録などにも石枠が反映される。
- HUDのHP／EXP、MAP状況、武装・戦利品欄、金貨、能動技、コンボを同じ素材へ変更。ゲージ・数値・戦闘判定は既存のまま。
- 三択UIの画像変更は既存ItemSelectへ接続。停止済みの旧属性宝箱や完成大技報酬の通常MAP経路を復活させる変更ではない。
- 生成原画・プロンプトは`assets/ui/relic_frames/`。報告用実画面6枚は`artifacts/crafted_ui/`。今回はユーザーの希望に沿って全体テストを行わず、実画面を撮影した。

### 35.5 今回の検証境界

`tests/pixel_visual_check.tscn`は本編Sceneを使い、MAP/LevelUp/Shopを採取し、
3択・4枠・キーボード決定・購入後focus・Modal解放・画面内収容を検査する。
2026-09-05追検証: 新Royal版の2箇所の未型付け配列ループが座標`x := ...`の型推論を失敗させ、
起動を阻害した。Dropは`for side: float`、鍛造は`for side: int`と明記し、描画内容を変えずに修正した。
装備以外のControlがfocusを持つ際の`inventory_item`参照も`has_meta`確認後だけ行う。
`tests/script_load_check.gd`による全147 Script実loadは失敗0。Title/Home/Game/Test Lab起動、
VulkanのPixel Visual / Equipment Merge / Equipment IntegrationもPASS、最終ログのERRORは0件。
同日追加依頼（壁内の柱/可読性/装備と鍛造の統合）では、VulkanのPixel Visual/Equipment Mergeと
本編Map Terrainを再実行しPASS。36seed実描画で廃止柱0・正面壁装飾・到達性・床/障害物不変、
本編のHazard tick/柱Collisionを検査。最新画像は`artifacts/readability_after_*.png`と`artifacts/equipment_merge_overhaul/`。
装備50点/長文能力/別装備選択時の先頭復帰、Pause/天賦図最下段までのキーボード操作、
実ItemData3択/Title/モード選択も最終VulkanでPASS。全148 Script実load失敗0。
全MAP移動・長時間・物理Gamepad検証などの残りは`docs/royal_visual_implementation.md`を参照する。

### 35.6 移動接触・壁の背面・画像VFX統一（2026年9月5日）

- Player/Enemy本体は押し合わず通過する。壁と同じlayer=1を使うPlayerを、Enemy生成時に
  本体衝突だけ相互除外する。壁・Hurtbox/Hitbox・拾得Areaは除外しない。
  予備動作後の通常敵攻撃、Boss攻撃、武器のKnockbackは維持する。新しい接触ダメージは加えない。
- 壁の元の正面/天面の立体表現を保持し、§35.8の接合加工済みAtlasを使う。
  旧`wall_edges.png`は縁だけを素材として使用し、別色の中央部分は使わない。建築配置の整理は§35.7を参照。
- 生成VFXは`assets/vfx/pixel/`へ保存。34種の64×64×6コマPNGと、警告輪/弾Core/Drop紋章の静止PNG3枚。
  Space12種、Concept6種、完成大技5外観、武器Theme Hit5種、Beam/Chain/大量撃破/Drop/Forge/毒床へ接続する。
  元属性/Fusionシステムは復活させない。既存の画像Projectile/Pulse/通常Hit/Critical Hitと本人の残像は保持する。
  不要な通常攻撃の黄色い三日月は引き続き出さない。
- `PixelSpriteVFX`で6コマの形成→成長→外周崩壊→残滓を再生する。本体Position/AlphaをTweenしない。
  透過画素は0/255、Nearest。SpriteFrames/Textureを共有し、実行時のImage読み戻しは行わない。
  Space/Conceptの描画だけ最大192world pxに抑え、広い攻撃半径で原画を巨大化しない。実ダメージ範囲は不変。
  敵の警告輪はこの表示上限の対象外とし、実攻撃半径へ合わせる（64px原画の円周本体外端25px、目盛りは別）。
- 戦闘画像の生成は最大96個・1frame32個。大量撃破は6個を再利用する。
  VFX予算からダメージ/状態付与へ分岐しない。合成用はトランザクションにつき独立した最大1枚。
- カメラシェイク/Hit-stop、短い画面フラッシュ、Bossの本体縁取り、頭上の状態情報UI、静的な宝箱/炉/ランドマークは
  今回の攻撃画像化とは別。全ての描画コードやShaderを機械的に削除するものではない。

調査の根拠・全画像の接続先・実測ログ・検証範囲は`docs/pixel_vfx_and_contact.md`。
生成は組み込みimage_genを使用。全採用プロンプト/元画像は`assets/vfx/pixel/source_manifest.json`と`sources/`、
再整形スクリプトは`tools/import_generated_pixel_vfx.py`。元画像は`.gdignore`で実行時import対象外とする。

### 35.7 壁装飾の透過分離・不要地形撤去・Boss広間（2026年9月5日）

- 撤去対象は橙の格子状Hazardエリア（床Damageも廃止）と横方向の短壁。縦の小壁、正面の金縁、上/側面の壁厚は残す。
- `wall_overlays.png`（128×64）は元画像の旗・壁付柱・格子・浮彫・床柱・噴水の透過部分を保持する。
  `WallOverlayTileMapLayer`/Source 3で描き、下地の壁材や床材を消さない。床柱は2×2セルの同じ矩形Collisionを維持する。
- `DungeonMap.boss_room_index`は開始位置から部屋中心への距離二乗が最大の部屋。同距離では後index。
  通常MAPは配置候補の段階で14×14マスの広さと隣室からの余白を確保し、配置後の拡幅は行わない。
  Boss部屋の196セルは全て通行可能。柱・短壁・Hazard・Elite・探索報酬を置かない。
- Boss広間は既存の青灰色の石床を継続し、内周に古金の象嵌、中央に256world pxの薄い床紋章（2026-09-22以降：待機中のみ・不透明度28%、戦闘中／撃破後は非表示）、
  実在する正面壁へ左右一対の王旗・壁付柱・松明を置く。入口を塞がず、片側しか置けない壁装飾は無理に配置しない。
  無作為な樽/瓦礫/結晶を広間へ散布しない。Bossゲートの旧紫色矩形描画は撤去し、紋章下に読みやすい操作案内を置く。
- Boss解放の撃破/救済条件、E/X操作、出現位置、攻撃/報酬/ショップ導線は変更しない。
  画像は静的TileMapとSpriteとして描画し、常時処理/Particle/Shaderを新設しない。
- 新規画像`boss_floor_seal.png`（128×128）と`boss_floor_border.png`（48×48/9-slice）は組み込みimage_genで制作。
  保存先は`assets/tiles/royal/`。承認済みPython整形は`tools/build_royal_dungeon.py`、
  原画/全プロンプトは`tools/source_art/map_architecture_manifest.json`（原画は`.gdignore`でimport対象外）。

### 35.8 元の立体壁・明るい縦壁とL字の統一・松明/結晶（2026年9月5日）

- 2026-09-11: 水晶に可視外接矩形の下側55%・幅80%の足元衝突を追加。Sprite再利用時に衝突も無効化／再設定する。樽・壺は16pxタイル座標の(-6,-2)〜(6,7)を衝突矩形とし、装飾レイヤーの実拡大率へ追従する。双方とも壁と同じcollision layer 1を使用。床模様・松明は非衝突。
- 同日: MAPの「生命の祭壇」（赤い台座）は生成停止。宝箱との重複表示を解消する。宝箱、Bossゲート、回復ドロップの処理は維持。


- ユーザーの実機評価により平面的な`wall_material.png`案を撤回。元のRoyal壁へ戻し、
  `dungeon_atlas.png`の暗い上面(7,3)・明るい正面/金笠木(9,3)の石積みと立体陰影を保持する。
  正面の高さ16pxと側面の横幅は別の表現であり、同幅/同輝度に平坦化しない。
  縦壁はユーザー画像の紫枠内にある既存の明るい壁が基準（石を紫色へ変更する意味ではない）。
  `wall_edges.png`のセル2・左3px（明るい石2列＋接触目地1列）を使い、右側は同じ画素の水平反転。
  暗い右側セル4や角用の別色材を混ぜない。壁本体は元の上面へ揃え、距離0.7 Tintを復活させない。
- `assets/tiles/royal/wall_relief.png`（256×256）は16px×256タイル。Source 5の通常壁専用Atlas。
  `StageEnvironment._wall_neighbor_mask`は床の8近傍N1/E2/S4/W8/NW16/NE32/SE64/SW128を使用し、
  `(mask & 15, mask >> 4)`を選ぶ。Sが床なら元の正面、それ以外は元の暗い上面と同一材の明るい縁を使う。
  SW/SEの内L・正面外角も幅3pxへ統一し、4〜15行は直線縦壁の画素をそのまま連続させる。
  内Lの0〜3行だけ隣接する正面端3pxを水平反転して笠木を接続し、外角の上4行は元正面のまま。
  NW/NE内角も同じ縦材の3×3pxを使う。暖灰色4pxの旧生成Lと正面端列を全高へ貼る方式は使わない。
  全256タイルの中央8×8pxは元の上面または正面そのまま。元画像を別の石模様で置き換えない。
- 同期・非同期とも`_set_wall_cell`へ接続。床柱の下地alt 3を優先し、元の16px矩形Collisionを保持する。
  床/壁の地形、BFS描画範囲、出入口、Boss領域、松明の配置座標、data/数値は変更しない。
  壁画像はオフライン合成・静的TileMap。毎フレームの画像生成や追加Shader/Particleはない。
- 松明の1コマ画像を`torch_6f.png`（96×24、16×24×6コマ）へ変更し、8fpsのループを再生する。
  上12行の炎は6種類の異なる形、下12行の金具は全コマ同一。Position/AlphaをTweenしない。
  全コマ共通の下端透明余白を除き、炎の根元（11行目）を金具（12行目）へ接続して浮きを防ぐ。
  Shared SpriteFrames＋既存poolを継続。開始frame/速度に差を付け、未使用poolはhide＋stop、再利用時にplay。
  静止画の結晶は再生停止。金具を含むSpriteの配置/大きさを変えず、炎のコマだけ動かす。
- 現行接合画像は承認済みPythonの`tools/build_wall_relief.py`で既存画素の切出し・水平反転・合成から再現する。
  前回のimage_gen角原画は保持するが現行builderでは参照しない。履歴/採用画素は`tools/source_art/wall_relief_manifest.json`。
  好評だった炎画像/再生は変更しない。炎の原画/全プロンプトは`tools/source_art/wall_material_manifest.json`、
  再整形は`tools/build_wall_material.py --torch`。旧平面壁の生成コマンドは現行壁へ接続しない。
  壁は完全不透明、炎の背景は透過。PNGは`assets/tiles/royal/`、原画は`.gdignore`でimport対象外。
- 検証は`tests/wall_junction_check.tscn`と`tests/wall_material_animation_check.tscn`。
  256近傍/元画像保持/全側面の明るい3px一致/笠木と角の接続/Collision、実移動6ケース、3MAP同期非同期、実本編の同位置4時点で炎だけ変化、
  同seed6回rebuildでpool増殖なし/非表示停止を確認する。描画は`artifacts/wall_material_animation/`。
- 結晶は`StageEnvironment._scatter_crystal_decorations`から、実TileMapの描画セル中心を使って配置する。
  24×24画像の不透明外接範囲（2倍表示で36×40px）を初回のみ取得/cacheし、矩形全体＋3px余白を検査する。
  壁/void/柱/Boss広間/収納/壁Overlay/既存Spriteと重なる候補は使わない。壁際の候補を有限回だけ調べ、
  セル中心から最大各軸8pxの内寄せを試す。安全な場所がなければ省略し、危険位置へfallbackしない。
  画像・表示倍率・静止表示・既存poolは保持。全オブジェクトへ一律16px補正する変更は行わない。
  `tests/crystal_placement_check.tscn`で36生成MAPの全不透明画素/3px隙間/他prop、同期非同期/座標変換/狭い床/poolを検証する。
- 通路掘削後の薄い横壁、および松明の配置原点による一部はみ出しは別件として未修正。

### 35.9 剣士の2.5D小規模試作（正式移行とは独立）

- 入口はタイトル→ゲームスタート→「2.5D試作 / 剣士」。通常ゲーム／既存Test Labの入口は維持する。
  `prototypes/hd2d/hd2d_arena.tscn`の単独1部屋（床25×17セル・柱4本）で120秒の生存戦を試す。
  職業は剣士のみ、初期10体・通常上限24体。スライム/オーク/コウモリの既存データを使い、JSONの数値は変更しない。
  自動通常攻撃、Space/Aの居合、撃破XP→既存3択強化、回復拾得を含む。
  長いMAP進行・Boss・ショップ・装備合成・天賦図はこの試作へ持ち込まない。
- 表示はGodotの実3D空間＋約30度の固定斜め上Camera3D。2026-09-06、箱を組み合わせた剣士モデルは撤去。
  元SwordsmanのPNG/AnimatedSprite2Dを変更せず、待機/歩行/攻撃3種/被弾/死亡の選択中フレームを
  QuadMeshへ同期する。専用Shaderでドット内だけの弱い面の丸み・銀鎧の反射・実照明を加え、輪郭は拡張しない。
  Idle全コマの不透明範囲から高さ1.68単位と足元を固定。影も同じフレームのアルファを地面へ投影する。
  Vは同じ画像・大きさ・足位置による「光加工あり／原画色のunshaded」比較。敵は既存Sprite3Dを維持する。
- 舞台は「薄明の森」。新規生成した`assets/prototypes/hd2d/forest_props.png`（木2種/シダ/根と苔石）と
  `forest_ground.png`を使用。木は前/中/遠の3層、草木は共有MultiMeshの計66個、石の境界と4障害物は
  共有の面取りMesh。地面の十字ブロック舗装は使わず、外側の土面も連続させる。
  草木は画像の根元baseline184/192で接地し、遠景だけに深度霧を使用。画面端の弱い陰影はUIより後ろに配置する。
  松明は既存6コマ/8fps＋暖色2灯、主光源は寒色＋影。全敵への動的影、被写界深度、ボリューム霧は使わない。
  生成原画・全プロンプト・整形手順は`tools/source_art/hd2d_forest_manifest.json`と`tools/prepare_hd2d_forest.py`。
- 戦闘/敵AI/HP/衝突/XPは既存の2Dゲーム側を唯一の正として継続し、3D側は表示のみ。
  `game.tscn`の試作インスタンスだけ起動スクリプトを外し、小MAPを与える。`scenes/game.gd`は変更しない。
  試作インスタンスのStageだけ(-16,-16)補正し、32px=1単位でセル中心と3D壁/柱を一致させる。
  居合の移動軌跡には固定位置の斬線を短時間残す。Phase 1でBoxMeshから滑らかな発光Quad/Shaderへ変更。
  中心から展開し、端と幅を削って消す。火花は個別に散り、画像全体の横滑り/Alphaフェードは使わない。
  `combat_effect_3d.gd` / `combat_energy.gdshader`が表示専用。居合最大24区間・寿命0.26秒。
  AttackVFXManagerのhit_normal/criticalとEffectThemeManagerのhit_*を3D命中表示へ接続。
  前者は元AnimatedSprite2Dの進行、後者は元PixelSpriteVFXのelapsed/durationに同期し、元Node終了で解放。
  Nodeを挟むEffectThemeManager配下もvisibility_layer=0として、2Dの命中画像が画面へ重ならないようにする。
  黄色い大量撃破演出mass_killは本試作で非表示（2D visibility_layer=0、3D proxy生成なし）。
  撃破判定/報酬/元Poolの寿命は維持。他の既存Pixel VFXは従来どおり。生成PNGは削除・上書きしない。
  ダメージ数字はCamera3Dの投影位置へ表示する。
- Phase 1の敵縮尺: Idle全コマの不透明範囲を初回だけ測定し、剣士1.68に対しオーク1.50、
  スライム1.05、コウモリ1.10の表示高を基準にする。透明余白を除外し、足元/アニメ中の伸縮を維持。
  変更は3D表示のみ。敵のHP・接触判定・攻撃範囲や通常ゲームの敵サイズは変更しない。
  この森を今後も実験室として保持する。自動攻撃方式は現状維持、攻撃が変化する装備の仕様/実装は保留。
  旧VFX全体の整理・元剣士PNG内の描き込み斬撃の分離・Boss/ウェーブ/天賦は後続の別作業。
- 操作: WASD/矢印/左スティック移動、Space/A居合、Esc/Bメニュー、R再試行、N敵追加（上限内）、
  Lで点光源＋主光源の影を比較、Vで剣士の光加工／原画色を比較。UI決定はEnter/A。
  UIのA/BはTitleと試作の滞在中だけ不足分を登録し、退出時は自身が追加したEventだけを除去する。
  既存強化3択中は試作HUD/数字を隠し、Rで選択を飛ばせない。試作中の装備/天賦UIは無効化する。
  死亡/120秒生存で再試行・タイトル帰還のメニューを出す。
- SaveManagerのephemeral sessionを使用し、通常Saveファイルへ書き込まない。再試行で試作内の成長を破棄し、
  退出で元職業・Dungeon参照・停止状態・独自Actionを復元/解除する。通常ゲームの2D描画を置き換える決定ではない。
  回帰は`tests/hd2d_arena_check.tscn`、全57フレームの同期と接写は`tests/hd2d_character_visual_check.tscn`、
  短時間の人工負荷比較は`tests/hd2d_performance_check.tscn`。
  Phase 1の縮尺/新命中/2D重複防止/寿命/個数上限は`tests/hd2d_phase1_check.tscn`。
  24体/48体・高HPの負荷チェックは本編の過去の性能問題を再現/解決した証拠として扱わない。

### 35.10 HD-2D Phase 2 — 森の闘技場（独立試作）

- 入口: GAME START→「2.5D Phase 2 / ウェーブとボス」。旧25×17の小実験室/通常ゲームは別に維持。
- `hd2d_expedition.tscn/.gd`、床45×31（旧面積約3.28倍）、障害物4個、追従Camera。
- 準備2秒、3ウェーブ総数18/24/30、2.5秒ごと最大6体・同時24体。全滅で4秒休憩。
  出現はPlayerから170px超480px以内の安全候補床。自動通常攻撃/Space・A居合/既存XP選択を維持。
- 最後に既存Minotaur AIのボス1体。3D表示高3.0（剣士比約1.79）。インスタンスHP倍率3.0に
  既存難易度倍率が適用される。敵/職業JSONは変更しない。自然な撃破時間は未実測。
- 撃破1.2秒後に新しい3D宝箱。`chest_view_3d.gd`の丸い蓋/木板/金属帯/鋲/錠/内部コイン。
  normal木＋銀、rare青＋銀、legendary赤紫＋金。蓋はヒンジ回転0.6秒。
  試作ボスの外観はrare80%/legendary20%、報酬性能との段階連動は後続作業。
- 既存TreasureChestの一度だけ開封/InputMap経路を使い、試作範囲58px。E/Pad Xで開封。
  0.8秒後に既存ItemSelectの最大3候補から1件取得、クリアメニューで再試行/帰還。
  中のコインは視覚装飾。新装備効果/大量装備Drop/ショップ/天賦/次周は未追加。
- 通常ゲームの2D宝箱/Save/攻撃方式は変更しない。SaveManager ephemeralで試作成長を破棄。
  旧小実験室と同様に黄色mass_killは非表示。詳細は`docs/hd2d_phase2.md`。
- 検証: `tests/hd2d_phase2_check.tscn`。撃破/HP早送りfixtureを含む進行検証であり、自然な1周の
  時間/難易度・長時間性能・物理Pad手動プレイの完了証拠とはしない。

### 35.11 HD-2D Phase 3 — 剣士のみの再配分天賦

- §35.10の森の闘技場のみ更新。入口はGAME START→「2.5D Phase 3 / 剣士の天賦」。
  通常ゲームと旧小実験室のレベルアップ選択は従来のまま。
- XPレベルアップ1回につき1P。ラン獲得量は現在Lv−1、残量は獲得量−配分済み。
  この試作ではランダム3択を開かない。乱撃派／一閃派の既存Lv2〜5カードを読み、
  一方に順番に1Pずつ配分（最大4P）。余剰は保持。専属スキルの新設計ではない。
- 最初と各ウェーブ終了後は自動で天賦図を開き、プレイヤーが「次の戦闘へ」を選ぶまで待つ。
  準備中／ボス後の宝箱待ちで1P返却・無料全リセット可能。戦闘中T/Pad Yは閲覧のみ。
  Esc/Pad Bで閉じる。準備画面を閉じると戦闘開始。加点操作はボタン／方向キー＋決定。
- 返却は最終段階から。全返却後に他方の流派へ変更可能。既存攻撃Strategyのschoolと
  ability_levelへ反映する。攻撃処理中は変更不可。HP・装備ボーナス・既存cooldownは変更しない。
  使いかけの連続使用回数は変更前の技の再充填時間へ変換し、切替による無料補充を防ぐ。
- 他職業、新規専属スキル、装備効果、大量ドロップ、周回は今回対象外。
  SaveManagerの試作セッション内に閉じ、再試行／終了で天賦ポイントを持ち越さない。
- 実装: `prototypes/hd2d/swordsman_talents.gd` と `hd2d_expedition.gd`。
  検証: `tests/hd2d_phase3_check.tscn`（XP加算fixture）、既存Phase 2進行検証。
  自然プレイの成長速度・強さ比較・物理Controller操作は別途評価が必要。

### 35.12 HD-2D Phase 4 — ボス装備散布・回収・装備画面

- 剣士の森の闘技場のみ。入口「2.5D Phase 4 / ボスの戦利品」。通常ゲーム／旧小部屋は維持。
- ボス死亡後に既存EquipmentDropSystemの生成処理で5品（試作配分Rare 3／Epic 2）。
  既存テンプレート・能力値範囲・特殊効果をそのまま使い、装備内容や職業スキルを追加しない。
- loot_view_3d.gd: 既存アイコンの3D表示、0.75秒の放物線飛散、着地リング・音。
  レアリティ色の細い光柱は上位ほど長い。全画面フラッシュや常設PointLightは使わない。
  安全床へ配置し宝箱から112px以上、装備同士80px以上を確保。
- 着地後38px以内で最寄りの1品をE/Pad Xで回収。近距離のみ名前とガイドを表示。
  取得フラグを先に立てて既存EquipmentComponentへ1回だけ追加。自動装着はしない。
- Iまたは天賦図の「装備・比較・合成」から既存統合EquipmentScreenを開く。
  準備／宝箱待ち／回収中のみ使用可能。整列・比較・装着解除・同レアリティ素材補助・合成は既存仕様。
  天賦と装備の入力を分離し、Pad Yは天賦入口として維持。
- 宝箱の既存報酬選択後は即終了せず回収状態へ戻す。Fで明示終了。未回収品を残して終了可能。
  時間制限なし。終了・再試行で装備を持ち越さない。周回／次の戦闘追加はPhase 5以降。
- 検証はtests/hd2d_phase2_check.tscnを拡張。XP/撃破早送りfixtureを含むため自然なバランス測定とはしない。

### 35.13 HD-2D Phase 5 — 剣士の3周チャレンジ

- 入口「2.5D Phase 5 / 剣士の3周チャレンジ」。既存試作アリーナを3周まで連続プレイ。
  各周は3ウェーブ→Minotaur→装備散布5個＋宝箱→回収・組み替えの流れ。
- 宝箱報酬選択後、F/Pad STARTで「次の周へ／回収へ戻る／終了」を選ぶ。
  3周目は次周ボタンを無効にし制覇終了できる。途中終了・未回収品破棄も明示する。
- 続行では同じPlayerを保持し、所持装備・装着・経験値・天賦・取得強化を維持。
  HP自動回復・技待ち時間リセットは行わない。次周の準備天賦画面で戦闘開始を待つ。
  再試行は新ラン、タイトル帰還は試作セッション破棄。通常Saveに持ち越さない。
- 暫定難易度: 各ウェーブ総数18/24/30に周ごと+6体、同時上限24は維持。
  通常敵とボスHPは1周目比1.00/1.35/1.70。攻撃力・速度・装備性能・XP量のJSONは変更しない。
  ボスの基礎倍率3.0および既存難易度倍率に追加適用。自然プレイの難易度は未調整。
- 周回遷移時は未回収装備・回復・宝箱・ボス攻撃を清掃し、前周の参照を解除。
  ボス通知の周番号を検証。周回選択の状態チェックで多重遷移を防止。
- 通常ゲーム／旧小部屋・他職業は変更しない。無限周回、新マップ、新スキル、
  新しい装備効果は今回対象外。`tests/hd2d_phase5_check.tscn`で3周経路を確認する。

### 35.14 試作ボスの攻撃追加・剣士の後退攻撃

- 3周闘技場のMinotaurに専用Strategy `minotaur_patterns.gd` を接続した。当初は試作限定だったが、
  2026-09-08の通常2D Phase 2で同じ4攻撃を`minotaur_combo_strategy.gd`へ移植した（§39）。
- 突進→前方薙ぎ払い→環状衝撃波→3連地割れの順に繰り返す。
  突進は横回避、薙ぎ払いは側面/後方、衝撃波は内側75px以内または外側180px超、
  地割れは狙われた地点（半径62px）から継続移動して回避する。攻撃方向/地点は各予告開始時に固定。
- 予告1.05秒（地割れは各0.85秒）、発動後硬直1.5秒、次技待ち2.2秒。
  突進は700px/sで0.4秒。技ダメージは既存contact_hitbox.damage相当、既存防御/無敵/被弾上限を経由。
  HPはPhase 5のままで追加増加なし。硬直終了直後に古い通常攻撃が出ないようWindupを解除する。
- `boss_attack_zone.gd`の地面Meshと当たり判定で半径・角度・幅を共用する。床予告→局所発光→終了。
  同時生成は1予告。Pause中は予告/突進/硬直が進まない。ボス死亡時に予告を除去し遅延ダメージを拒否。
- ボス本体の演技は `boss_attack_performance.gd` が試作内だけで制御する。
  環状波は既存Attack03、突進/地割れはAttack01を使用。Attack02は前方への突きなので薙ぎ払いには使わない。
  薙ぎ払いは元の`Minotaur.aseprite`のAttack01 body層を複製した`hd2d/source_edit/`の3枚×8コマを使用。
  元の顔・角・鎧・配色に加え、握り手・前腕・肩・胴・武器が一体で動く原画モーションを保持する。
  元の白いfx層だけを除外し、構え3コマ→全身で振る3コマ→振り抜き2コマとして接続する。
  `tools/export_minotaur_source_layers.py`は28コマのbody+fxが既存PNGとRGBA完全一致することを検証。
  `tools/build_minotaur_source_motion.py`は生成8コマが元Attack01 body層とRGBA完全一致し、上半身が6ポーズ以上あることを検証。
  2026-09-08、武器内縁の切り抜き漏れ3px（元座標x57〜59/y55）が本体の足元に残る不具合を修正。
  マスクの内縁を延長し、該当3pxを本体から回転する武器へ移す。全3枚×8コマを再出力。
  原画の顔/角/鎧は不変。本体への武器残留なし・武器の元画素保持・本体の連結性を生成時に検証する。
  2026-09-08、武器だけが回転して握り手・腕・胴が静止する不整合を廃止。
  第一形態の薙ぎ払い3枚×8コマは、元AsepriteのAttack01 body層8コマをRGBAそのままで使用する。
  元の白いfx層だけを除き、構えから振り抜きまで握り手・前腕・肩・胴・武器を原画どおり一体で動かす。
  side/back/frontは床の三日月方向を選ぶ名称とし、キャラクターは存在しない正面/背面を新造しない。
  左向きだけ全身を反転し、剣撃の掃引方向も反転する。攻撃半径・半角・威力・0.18秒の命中進行は変更しない。
  元Aseprite/PNGは不変。前段のAI再生成版は第一形態には使わず、第二形態候補として削除せず保管する。
  第二形態の変身条件/専用攻撃は未確定・未実装。現在のゲームには未接続。
  side/back/frontは床の三日月方向（横/奥/手前）の区別。元データにない正面/背面の顔は新造せず、
  元の斜め向き全身モーションを維持する。左向きだけ全身と剣撃進行を同時に反転する。
- 薙ぎ払いの姿勢・`boss_cleave_slash.gd`・`boss_attack_zone.gd.contains_sweep`は0.18秒の共通進行度で同期。
  予告終了と同時に扇全体へ瞬間命中させず、刃が通った角度だけが有効（1回の攻撃で最大1回命中）。
  これは従来の0.18秒の局所発光期間を使い、1.05秒の予告と1.5秒の硬直、既存威力は維持する。
  刃と予告は同じ床高さ0.065・原点・方向・半径145px・半角70度。高い空中の弧による画面上のズレを避ける。
  剣撃の形はユーザー参照画像の「白い外縁・青白い内側、中央が厚く両端が尖った三日月」に固定する。
  細い直線への置換、一定幅のリング、扇全体の青い塗りは不可。最大厚は半径の16%、
  sin(角度内の割合×PI)^1.4で両端の幅を0にし、内側には細い弧状の残像を1本添える。
  掃引済みの角度だけを順に描き、0.18秒の振り抜き完了で三日月全体が完成する。
  終了直後0.04秒は完成形を保持し、後端から削れつつ厚みを縮め、0.24秒で除去する。
  画像の横移動/全体フェード/黄色い星/全画面フラッシュは使わない。白い芯は消失直前まで発色を保持する。
  薙ぎ払い予告/実行中にボスが2px超の強制移動を受けた場合は中断し、古い予告位置からの攻撃を防ぐ。
  演出側はダメージを与えず、既存Strategyのみが命中を処理する。
- 演技の所有者は常に1つ。3連地割れの次予告へ移る際は前の演技を解放。
  Pause中はポーズ/刃軌跡も停止し、死亡/Scene終了で除去してDeathアニメを上書きしない。
  演技終了時に既存Idle/Walk制御を復帰する。通常2D/旧小ルーム/他職業には適用しない。
- 承認済みの自動照準は `swordsman_aim.gd` で剣士の試作アリーナだけに適用。
  元の通常攻撃にも自動照準はあったが、移動がSpriteの向きを上書きし、溜め中に照準が古くなる。
  1振りの対象を保持して命中時に現在方向へ補正し、近距離の敵へ見た目を向けたまま後退可能にする。
  射程外への攻撃、射程/威力/速度の強化はしない。居合を敵への自動追尾には変更しない。
- 2026-09-08、保持中の敵が死亡して`queue_free()`された次フレームに、解放済み参照を
  型付き`_alive(Node2D)`へ渡した時点で関数内の有効性検査より先に型エラーになる不具合を修正。
  `_alive(Variant)`でインスタンス有効性→Node2D復元→削除予約→HPの順に検査し、無効な対象は
  既存の最寄り敵再検索へ流す。攻撃対象の選び方、射程、威力、速度、VFXは変更しない。
  検証は解放済み対象fixtureを含む照準16項目と、通常Spawnerで72体を死亡させる敵Lifecycle 452項目を
  Vulkan実描画で実行し、失敗0・ERROR/WARNINGなし。

### 35.15 所有済みの敵10種を森の闘技場へ追加（2026-09-07）

- §12追補の10種を3周チャレンジ`hd2d_expedition`へ接続する。最初の1周で全種に遭遇可能。
  旧小実験室`hd2d_arena`はスライム/オーク/コウモリの比較用構成を維持する。
- ウェーブごとの固定巡回候補（重複は出現比率の重み）。通常MAPの秒数解禁とは別に設定する。

| Wave | 巡回候補 |
|---|---|
| 1 | Slime / Blood Monster_A / Orc / Hellbat / Slime / Eyeball Monster / Bat / Lava Slime |
| 2 | Orc / Blood Monster_B / Slime / Hellhound / Bat / Ghostfire / Hellbat / Demoness_A |
| 3 | Blood Monster_A / Demoness_B / Orc / Warlock / Lava Slime / Blood Monster_B / Hellhound / Demoness_A |

- 各Wave18/24/30体、次周+6体、同時上限24体、既存の周回HP倍率・ボス・報酬は不変。
  新素材はプレイ開始前に1フレーム1種ずつSpriteFramesキャッシュへ読み込み、戦闘中にまとめてロードしない。
- 3D表示高はBlood A1.40/B1.35、Demoness A1.75/B1.80、Eyeball1.05、Ghostfire1.30、
  Hellbat1.10、Hellhound1.15、Lava Slime1.05、Warlock1.70。剣士1.68/ボス3.0との体格差を維持する。
  待機の不透明範囲を基準に表示し、余白を含めた一律拡大はしない。影なし原画＋既存の床影を使用する。
  戦闘・衝突・死亡の正は共通EnemyBasic、3D側は元アニメーションの表示だけを担当する。
- 個別の敵専用AI/攻撃技の作成や自然プレイの難易度調整は今回の範囲外。
- 検証: `tests/hd2d_enemy_roster_check.tscn`で通常Spawner経由の10種生成、元画像全行動、
  移動/攻撃命中・回避/剣士の攻撃/死亡/XP・Drop一度だけ、実Wave72体→Boss、通常Save不変を確認。
  実描画452確認・失敗0（`artifacts/enemy_roster_runtime.log`）。並列表示は`artifacts/enemy_roster/lineup.png`。
  3周進行と旧小ルームの既存回帰も失敗0。位置/高HP/死亡早送りを使った統合検証であり、
  自然1ランの難易度・長時間性能・個別技の完成を保証するものではない。

## 36. 状態異常システム（2026年9月・属性/フュージョン廃止に伴う再定義）

### 36.1 廃止したもの

属性システム（火・氷・雷・光・闇）とフュージョンシステムを**全廃**した。廃止理由:

- 属性オプションの入手経路がボス/エリート報酬とレベルアップ候補プールに二重化していた
- フュージョン成立条件（2属性が両方LvMAX）が重く、ほとんどのランで発生せず成長動機として機能しなかった
- 職業10種 × 属性5種 × 天賦図分岐の組み合わせが、個人開発で調整可能な規模を超えていた

削除対象: 属性レベル/スロット/熟練度倍率、fragment、フュージョン一式（スクリプト・VFX・アセット・
テーマ3種）、`ElementRewardSystem`、`FragmentSelect`、ボス/エリート撃破時の属性報酬、
レベルアップの属性Lv候補生成。

### 36.2 存続する「状態異常」レイヤー

`StatusEffectComponent`が扱う状態異常を、属性体系から切り離して`slow`/`stun`と同列に扱う。

| 状態ID | 内部effect名 | 効果 |
|---|---|---|
| `burning` | `element_burning` | 継続ダメージ（0.5秒間隔）。既定3.0秒 |
| `frozen` | `slow` / `stun` | 移動速度低下または停止。既定2.0秒・速度55% |
| `charged` | `element_charged` | 状態のみ（条件付き強化の参照先）。既定3.0秒 |
| `marked` | `element_marked` | 状態のみ。既定3.5秒 |
| `cursed` | `element_cursed` | 被ダメージ+25%。既定3.5秒 |

内部effect名からは`element_`接頭辞を撤去済み（`burning` / `charged` / `marked` / `cursed`）。
`frozen`だけは`slow`と`stun`の2つのeffectから立つ（`STATE_BY_EFFECT`参照）。
API名も`has_state()` / `get_states()` / `states_changed` / `STATE_BY_EFFECT` / `STATE_ORDER`へ統一した。

### 36.3 付与の責務: `systems/status_apply_system.gd`

旧`ElementCombatSystem`から**状態異常の付与処理だけ**を救出した`StatusApplySystem`
（`game.tscn`のノード、group `status_apply_system`）が担当する。属性ダメージ計算・
属性Lv・熟練度倍率・属性ID体系は引き継いでいない。

付与する状態は各攻撃Strategyの`applied_status_id()`が決める。サブクラスで
overrideすることで職業ごとに変えられる。

#### 付与経路（2026年9月4日に接続）

`applied_status_id()`が返す状態IDは、攻撃判定の生成時に`HitboxComponent.applied_status_id`
へ書き込まれ、`HurtboxComponent.apply_hitbox_damage()`がダメージ適用の**後**に
`StatusApplySystem.apply_state()`を呼ぶ。ダメージより先に付与すると、その状態を条件に
するダメージ強化が「状態を付けた当のHit」にも乗ってしまうため、順序は
`AttackPatternBase.apply_direct_damage()`と揃えてある。空文字のHitboxは何も付与しない
（EnemyBasicのContactHitbox、Boss弾はここに該当する）。

書き込み箇所は5つ。

| 経路 | 書き込み位置 | 対象職業 |
|---|---|---|
| 近接・点/扇/線Hit | `attack_pattern_base.gd`の`spawn_point_hit`/`spawn_arc_hit`/`spawn_line_hit` | melee_arc, wide_cleave, self_pulse, holy_pulse_heal, piercing_thrust |
| Player由来Projectile | `weapon_manager_component.gd`の`_fire_single_projectile()` | spread_shot ＋ 装備武器すべて |
| homing_bolt | `homing_bolt_attack.gd`（weapon_managerを経由せず自前でinstantiateするため個別） | wizard |
| 召喚した味方の接触ダメージ | `ally_skeleton.gd`の`_ready()`で召喚主の職業から引く | necromancer |
| Hurtboxを経由しない直撃 | `attack_pattern_base.gd`の`apply_direct_damage()`（従来どおり） | charge_dash, 一閃派の処刑, homing_bolt Lv4爆発 |

Space技（`active_skill_component.gd`の`_damage_enemy()`）も職業の状態に揃えてある。
以前はここだけ`burning`固定で、cursed職のPlayerが自分では使えないburning系カードの
条件を満たしてしまう状態だった。

【経緯】属性システム廃止時に`hurtbox_component.gd`の`apply_element_damage`ブロックを
撤去した際、この接続を作り直し忘れていた。結果として各職業の**主力攻撃が一度も状態異常を
付与しない**状態が続いており、状態カード9枚と天賦図の状態トリガー23件がすべて空振りしていた
（900秒の実測で`_burning_targets`が全区間0だったことから発覚）。

#### 職業ごとの割り当て

`WeaponManagerComponent.ATTACK_PATTERN_SCRIPTS`が示す通り、`melee_arc`と`wide_cleave`は
同じStrategyを共有するため、そこだけ`GameManager.selected_character_id`で分岐させている。

| Strategy | 職業 | 付与する状態 |
|---|---|---|
| `melee_arc_attack` | soldier | `burning` |
| `melee_arc_attack` | swordsman | `cursed` |
| `melee_arc_attack` | armored_axeman（wide_cleave） | `frozen` |
| `charge_dash_attack` | knight | `frozen` |
| `piercing_thrust_attack` | lancer | `frozen` |
| `spread_shot_attack` | archer | `charged` |
| `homing_bolt_attack` | wizard | `charged` |
| `self_pulse_attack` | knight_templar | `marked` |
| `holy_pulse_heal_attack` | priest | `marked` |
| `summon_minion_attack` | necromancer | `cursed` |

5状態すべてが最低1職業でカバーされており、23件の完成大技すべてを自然発動で検証できる。

#### 実測（2026年9月4日、10職業を順に起動して確認）

10職業すべてで、期待どおりの状態だけが敵に立つことを確認済み（他状態の混入なし）。

| 職業 | 期待 | 観測 | | 職業 | 期待 | 観測 |
|---|---|---|---|---|---|---|
| soldier | burning | burning | | knight_templar | marked | marked |
| swordsman | cursed | cursed | | priest | marked | marked |
| armored_axeman | frozen | frozen | | necromancer | cursed | cursed |
| knight | frozen | frozen | | archer | charged | charged |
| lancer | frozen | frozen | | wizard | charged | charged |

**TODO: 天賦図による付与状態の追加・変更は後日設計する。**

### 36.9 付与を有効化したことによる難易度影響（2026年9月4日実測）

同一の的（HP固定）へ60秒間攻撃し続けた与ダメージ合計を、`StatusApplySystem`を
groupから外して付与を止めた状態と比較した（強化カードは未取得＝Lv1相当）。

| 職業 | 状態 | 付与なし | 付与あり | 差 |
|---|---|---:|---:|---:|
| soldier | burning | 854 | 1012 | **+18.5%** |
| swordsman | cursed | 1022 | 1292 | **+26.4%** |
| priest | marked | 348 | 348 | ±0% |
| archer | charged | 1305 | 1296 | ±0%（-0.7%は計測誤差） |

素の与ダメージが増えるのは**burning（継続ダメージ）とcursed（被ダメージ+25%）だけ**で、
frozen / charged / markedは対応する強化カードを取るまで数値上の差を生まない。
ただしfrozenは敵の移動速度を2秒間-45%にするため、与ダメージには表れない形で
実際の難易度を下げる。

敵HP倍率（Phase 1後はMAP1で2.8倍〜MAP3で4.5倍）は「状態異常が一切効いていない状態」で
調整された数字なので、実プレイの手応えを見たうえで再調整すること。この表の数値は
カード未取得時の下限であり、状態カードを取るほど差は開く。

### 36.4 完成大技（天賦図）との接続

`concept_system.gd`の完成大技は**維持**した。属性依存を以下へ置き換えている。

- `required_elements`による解放条件 → **撤廃**。`is_completed_skill_available_for_build()`は
  常に`true`を返す。TODO: 将来、天賦図の取得状況で絞り込む
- `trigger_element`（与ダメージの属性で判定）→ **`trigger_state`**（対象に該当の状態異常が
  乗っているかで判定）。`completed_skills.json`の23件を
  fire→burning / ice→frozen / lightning→charged / light→marked / dark→cursed へ置換済み
- 属性Lv/熟練度による威力・範囲・クールダウン補正 → **全廃**。基礎値のみで決まる

### 36.5 属性報酬廃止後の報酬経路（ラン内経済 Phase 1）

| 経路 | 現状 |
|---|---|
| MAP1/2ボス撃破 | ラン内ゴールド＋完成スキル宝箱。ショップUI接続までは宝箱開封後に次MAPへ進む |
| MAP3ボス撃破 | 完成スキル宝箱。ラン内ゴールド追加なし |
| 精鋭部屋クリア | ラン内ゴールド。精鋭本体の確定装備・経験値も従来どおり |
| サージ完了 | ラン内ゴールド＋既存の回復／装備報酬 |
| 属性祭壇 | **生成を停止**（触れても何も起きないオブジェクトを残さないため） |
| 宝箱の`attribute`枠 | 抽選テーブルから除外。equipment / recovery / skill の3種のみ |
| ROOM属性報酬 | 選択UIを挟まず直接宝箱報酬へ進む |

ラン内ゴールドは`SaveManager.meta_currency`とは別で、セーブせずRun開始／終了時に0へ戻す。
ショップ画面と商品抽選は次Phaseで接続する。

### 36.6 融合武器15種（未着手）

`required_fragment_ids`を持つ武器15種は**入手経路が存在しない**まま残置している
（`add_weapon()`の呼び出しは開始武器のみ。`fusion_system.gd`は本作業以前に削除済み）。
`required_fragment_ids`は現在「融合武器か否か」のフラグとして`projectile.gd`のVFX分岐に
使われているだけ。TODO: 将来ショップの商品に転用する。

### 36.7 レベルアップ候補からの旧属性カード除外

`data/upgrades/`のA1カード25枚のうち、**状態異常を参照する9枚だけ**を抽選候補に残し、
旧属性メカニクス（燃焼範囲・連鎖数・聖光回数など、実装が`ElementCombatSystem`にあった）に
依存する**16枚は抽選から除外**した。取っても効果がないカードを引かせないため。

- 候補に残す9枚: `ACTIVE_STATE_UPGRADE_EFFECTS`（`player_upgrades_component.gd`）
- 除外する16枚: `DISABLED_LEGACY_UPGRADE_EFFECTS`。**JSONは削除せず残置**しており、
  将来ショップの商品や天賦図の素材へ転用する可能性がある

`category`は`element_fire`等のまま残っているが、これは旧データの識別子であり、
属性システムとしての意味は持たない。

#### 職業が付与しない状態のカードは候補に出さない

状態異常カード9枚をそのまま候補にすると、**その職業が付与しない状態のカードが出てしまい、
取っても効果が永久にゼロ**になる（例: swordsmanは`cursed`を付与するのに「聖印追撃」＝
`marked`参照のカードが候補に出る）。

そのため`LevelUpSelect`は`WeaponManagerComponent.get_applied_status_id()`
（＝現在の職業の`applied_status_id()`）を参照し、
`PlayerUpgradesComponent.UPGRADE_EFFECTS_BY_STATE`で対応するカードだけを候補に入れる。

| 状態 | 対応カード |
|---|---|
| `burning` | 灼熱追撃 / 火葬の知恵 |
| `frozen` | 氷砕追撃 / 氷点看破 |
| `charged` | 感電追撃 |
| `marked` | 聖印追撃 / 殉光の護り |
| `cursed` | 呪殺追撃 / 伝染呪 |

`charged`だけ1枚なのは、`charged_chain`（導電路）が雷連鎖依存で無効化されたため。

#### 候補総数（実測）

絞り込みにより状態異常カードは1〜2枚に減るため、重みは2.8→**1.5**へ引き下げた
（枚数が少ないのに重みが高いと、同じカードばかり出て他の候補を圧迫するため）。

| 職業 | 付与状態 | 状態カード | common | 近接/遠隔 | 職業 | 合計 |
|---|---|---:|---:|---:|---:|---:|
| soldier | burning | 2 | 8 | 4 | 1 | **15** |
| swordsman | cursed | 2 | 8 | 4 | 2 | **16** |
| armored_axeman | frozen | 2 | 8 | 4 | 1 | **15** |
| knight | frozen | 2 | 8 | 4 | 1 | **15** |
| knight_templar | marked | 2 | 8 | 4 | 1 | **15** |
| lancer | frozen | 2 | 8 | 4 | 1 | **15** |
| priest | marked | 2 | 8 | 4 | 1 | **15** |
| necromancer | cursed | 2 | 8 | 4 | 1 | **15** |
| archer | charged | 1 | 8 | 4 | 1 | **14** |
| wizard | charged | 1 | 8 | 4 | 1 | **14** |

swordsmanの職業カードが2枚なのは流派選択（`class_school_select`）が
Lv2到達時に追加で候補へ入るため。重みは状態カード1.5 / common・近接遠隔1.0 / 職業2.0。

### 36.10 検証Testの復旧（2026年9月4日）

属性/フュージョン削除の際、`tests/`配下の8本が削除済みAPIを参照したまま残り、
**2026年9月1日以降まったく実行できない状態**になっていた。全8本を復旧し、いずれも
failures=0で通ることを確認した。

| Test | 残っていたもの | 対応 |
|---|---|---|
| `developer_test_lab_check` | Fusion Gallery/属性Lv/属性攻撃のLab API、`lab.element_combat` | Fusion系検証を削除。属性LvはSTATUSボタン経由の5状態付与検証へ置換。Damage Meterは`trigger_projectile()`の実WeaponManager経路で確認 |
| `final_polish_soak_check` | 空の欠片取得ループ、`combat.apply_element_damage` | 燃焼の追跡解放検証を`StatusApplySystem.apply_state()`へ移植（検証の意図は保持） |
| `global_audit_check` | `element._fusion_runtime`のtag検証 | 削除 |
| `iai_and_mode_check` | 属性IAIのtrail VFX計測 | 削除 |
| `pixel_visual_integration_check` | Fusion VFX Resource 10種の存在検証 | 削除 |
| `room_combo_mvp_check` | 属性報酬選択Helperのbody（関数の外に残存） | 削除 |
| `room_mvp_visual_check` | 属性報酬のCaptureとその分岐残骸 | 削除 |
| `vfx_spawn_stall_check` | 属性Lv構築の空if/else | 削除 |

`final_polish_soak_check`はあわせて、VFX残留判定が「Line2Dは全部VFX」という粗い
ヒューリスティックだったために、後から入った床装備の枠線（生存中のドロップ品）を
誤検出していた点も直した。床装備の寿命は上限・期限切れ検証が別途担当する。

#### `--editor --quit`ではパースエラーを拾えない

この8本は`--headless --path . --editor --quit`を通してもエラーとして出てこなかった。
全スクリプトを実際に`load()`する掃き出しを行って初めて発覚している（145本中8本が失敗）。
36.8の教訓に加えて、**削除作業の後は「全.gdをload()して0件失敗」まで確認すること**。
さらに`lab.element_combat`のような自動読み込み/プロパティ参照は`load()`でも
検出できず、実際にTestを起動して初めて出る。

### 36.8 削除作業の検証方法（重要な教訓）

属性/フュージョン削除の過程で、**`--headless --editor --quit`（構文チェック）を通過しても
実行時に落ちる**不具合が発生した。原因は`EventBus.fragment_collected.connect(...)`のような
**Autoloadのプロパティアクセス**で、GDScriptはこれを実行時解決するためパース時には検出されない。

HUDの`_ready()`がこの1行で停止し、キャラクター選択後に画面が真っ暗になった。

**シンボル削除を伴う変更では、構文チェックだけを根拠にしないこと。** 以下の2段構えで検証する。

1. **削除したAPI名の文字列全走査**: 削除したシグナル名・関数名・定数名・クラス名を列挙し、
   `.gd`と`.tscn`の両方をgrepする。`.tscn`の`@export`/NodePath参照も対象に含める
2. **実シーンの起動確認**: `godot --headless --path . <scene>.tscn` を
   `title` / `home`(キャラクター選択) / `game` / `developer_test_lab` の4つで実行し、
   `SCRIPT ERROR` / `Invalid access` / `Invalid call` / `null instance` が0件であることを確認する

削除済みAPIの一覧は本章36.1と、`docs/codex_handoff.md`の該当節に残す。

## 37. ラン内ゴールド／ボス後ショップ（2026年9月確定仕様）

**現行追記（2026-09-15）:** 少数の有限遭遇と60層進行に合わせ、ショップは各層のボス宝箱を開けた後、階段を調べると開く。60層目はクリアへ。旧2回来店・旧価格は履歴。現在値は本章末の2026-09-15節を参照。

### 37.1 役割と進行

ショップはラン中のゴールドを「今の戦力」へ変換する任意購入層であり、永続アンロックには
使わない。初期実装では探索MAP中に店を配置せず、**MAP1とMAP2のボス撃破後だけ**開く。
来店回数は1Runにつき2回。MAP3最終ボス後は使う戦闘が残らないためショップを開かない。

進行順は`ボス撃破 → ラン内ゴールド獲得 → 完成スキル宝箱 → ショップ → 次MAP`。
完成スキルを確定した後のBuildを見て購入判断できる順序にする。

### 37.2 ラン内ゴールド

- 正本は`GameManager.run_gold`。加算は`add_run_gold()`、購入／リロールは
  `try_spend_run_gold()`だけを通す
- `SaveManager.meta_currency`とは分離し、保存・持越し・キャラクター解放への変換を行わない
- Run開始／死亡終了／クリア終了で0へ戻す
- 敵ごとのコインNodeは生成せず、既存の撃破イベントから直接加算する
- HUDは`EventBus.run_gold_changed`を購読し、MAP Run中だけ現在値を表示する

初期収入値:

| 経路 | ゴールド |
|---|---:|
| 敵撃破 | 1G |
| 精鋭個体撃破 | 通常1Gに加えて10G |
| 精鋭部屋クリア | 50G |
| サージ完了 | 20G |
| MAP1ボス撃破 | 100G |
| MAP2ボス撃破 | 150G |
| MAP3ボス撃破 | 0G |

ここでいうサージは新規機能ではない。各MAPの撃破進行25%／50%／75%付近（または救済時刻）で
発生する、約45秒間の既存の敵密度上昇イベントを指す。既存の回復／装備報酬を残したまま、
完了報酬へ20Gを追加する。

### 37.3 商品枠と購入後の補充

1店舗は常に次の**4枠**を表示する。

1. 遺物武器 1枠
2. 汎用強化 1枠
3. 現在の職業が付与する状態異常に対応した強化 1枠
4. 回復 1枠

購入後に`SOLD OUT`枠は残さず、**購入したカテゴリの商品を1つ再抽選して同じ枠へ補充**する。
同一来店中に購入済みの商品は再抽選候補から外す。候補を使い切ったカテゴリだけ枠を詰める。

### 37.4 価格と購入量

1来店でおおむね2商品を買える収支を基準とする。

| 商品 | 初期価格 |
|---|---:|
| 回復 | 160G（35%）／200G（60%） |
| 汎用強化 | 240G前後 |
| 状態異常強化 | 240G前後 |
| 1回目・低～中Tier遺物武器 | 450～550G |
| 2回目・高Tier遺物武器 | 600～800G |

高Tier武器と汎用強化の価格差は約3倍以内にする。1回目は100Gリロール後も武器枠が死なない
よう上限550G、2回目だけ600～800Gを出す。価格・収入は`exploration_run.json`と商品Catalogへ
置き、実測で調整する。

#### 実測値と評価上の注意

Godot本編Runtimeを自然Spawn・Player自動攻撃・全精鋭部屋クリアでMAP2 Bossまで通した結果、
MAP1 Boss直後666G、MAP2 Boss直後累計1687Gだった。ただし計測は**4倍速・検証用高HP**で、
被弾回避による攻撃停止や死亡リスクがない。666Gは上振れの可能性があり、実プレイヤーの
中央値はこれより低い前提で1回目価格を安全側の450～550Gにする。

MAP1実測666Gのうち通常敵撃破は422G（63.4%）、MAP2累計1687Gのうち通常敵撃破は
1066G（63.2%）であり、収入の6割以上が通常敵撃破に由来する。したがって現状のゴールドは
実質的に**撃破数の関数**である。ボス領域の時間救済を待って撃破数を減らす判断と、敵を倒して
ショップ購買力を増やす判断のトレードオフが実際に機能するかは、ショップ画面完成後の
実プレイで再検証する。

### 37.5 リロール

ショップにはゴールド消費のリロールを設ける。初回100G、同じ店舗内では実行ごとに+50G。
リロールは未購入を含む4カテゴリすべてを再抽選し、同一来店中に既に購入した商品は候補へ
戻さない。購入前に所持金不足を判定し、失敗時は商品も所持金も変更しない。

### 37.6 商品化の制約

- 旧融合武器15種は「遺物武器」として再定義する。`required_fragment_ids`を取得条件・描画判定に
  使わず、`is_relic`で矢画像を隠して発光弾体と現存Hit Themeへ接続する
- 除外済み旧属性カード16枚は状態異常または汎用効果へ再実装する。レベルアップ候補には戻さず、
  現在の職業が付与できる状態で絞り込んだショップ専用商品にする
- 購入・リロール・回復はすべてラン内だけに作用し、通常セーブを変更しない

旧カード16枚の再定義と出現条件:

| 職業が付与する状態 | ショップ専用カード | 再定義した効果 |
|---|---|---|
| burning | 熱波／焦熱／灰燼 | 攻撃範囲／燃焼Damage／燃焼時間 |
| frozen | 永久凍土／絶対零度／深凍 | 凍結時間／対凍結Crit／対凍結Damage |
| charged | 雷速／過負荷／電界／導電路 | 攻撃間隔／対帯電Damage／攻撃範囲／死亡時帯電伝播 |
| marked | 連撃聖光／裁き／加護 | 対Marked Crit／対Marked Damage／死亡時Shield |
| cursed | 深淵／呪縛／侵蝕 | 呪い脆弱率／呪い時間／対呪いDamage |

商品正本は`data/shop/shop_catalog.json`（全41商品）。`ShopSystem`が来店回数、現在の職業状態、
所持武器、購入済みIDで抽選し、`ShopScreen`はそのStockだけを4枠で表示する。遺物武器15種は
1回目10種／2回目5種、旧カードは上記16枚。高位3武器を含め、削除済みElement Theme IDを
参照せず現存Hit Themeへ接続する。

### 37.7 実装Phase

- Phase 1（完了）: ラン内ゴールドの加算・消費API、報酬経路、HUD表示、Runリセット
- Phase 2（完了）: 遺物武器15種／旧カード16枚の有効化とData-driven商品Catalog
- Phase 3（完了）: 4枠ショップUI、購入後補充、有料リロール、ボス宝箱後のMAP進行接続

実装済み進行は`MAP1/2 Boss宝箱 → 完成スキル選択 → ShopScreen → 次MAP`。MAP3はShopを
開かずRun Clearへ進む。ショップはGameManagerの共通Modalへ接続し、キーボード／ゲームパッドの
既存UIフォーカス操作で購入・リロール・退出まで完結する。

### 37.8 ショップPixel Art素材

`tools/generate_shop_pixel_ui.py`を正本とし、実行時に`assets/ui/shop/`へ次を再生成する。

- 16x16カテゴリIcon: `weapon_icon.png` / `upgrade_icon.png` / `status_icon.png` /
  `recovery_icon.png`
- 48x48 9-slice枠: `shop_frame.png`（Patch Margin 10px、中央はalpha 220の濃紺）
- 8x8選択Cursor: `cursor.png`
- 店内背景Object: `crate.png`（32x32）/ `lantern.png`（16x24）

各Assetは最終解像度へ直接描画し、アンチエイリアスを使わない。可視色は画像ごとに8色以下、
Frame以外のalphaは0/255、Frameだけ透過Cornerと半透明中央を許可する。PaletteはScript上部の
定数へ集約する。2026-09-05に`ShopScreen`へ全種を接続した。画面は「灯火の遺物商」、古金/緑玉紋章と
ランタン/木箱、画像・商品名・説明・価格帯を持つ4カードで構成。所持金不足の商品もフォーカスして不足額を確認できる。
購入/補充後は同じ枠へフォーカスを戻す。抽選/価格/購入ロジックは変更しない。最終Royal版GUI検証状況は§35.5を参照。

---

## 38. 敵AI経路探索の性能設計（2026年9月4日）

MAP刷新後に「敵が出現し始めると重くなり、時間経過で悪化し、最終的に静止画同然になって
二度と戻らない」症状が出た。計測の結果、原因は敵AIの経路探索`components/ai/chase_strategy.gd`
だった。属性/フュージョン廃止・状態異常システム・ラン内ゴールドとは無関係である。

### 38.1 症状の機構

`ChaseStrategy.compute_direction()`はプレイヤーへの直線視界が壁で遮られた敵に対して
幅優先探索を実行する。ここに3つの問題があった。

1. 通行可否判定`_has_navigation_clearance()`が、1マスにつき`DungeonMap.is_floor()`を
   3x3＝9回呼んでいた。`is_floor()`は1回あたり実測1,396ns（GDScriptのメソッド呼び出しが
   コストの支配項）なので、1マスの判定に約12.6µsかかる。平均336セルを探索する
   1回の経路探索は約12,100回の呼び出し＝**実測15.8ms**に達した。
2. 再探索の間引き条件が`_path.is_empty() or goal != _path_target or now >= 期限`で、
   前2つはどちらも毎フレーム成立しうる（探索が失敗すると`_path`は空のまま、
   プレイヤーが1マス動くだけで`goal`は変わる）。**最も高コストな場面でだけ
   280msの間引きが無効**になっていた。
3. 1フレームあたりの実行数に上限が無かった。フレーム時間が280msを超えると
   全敵の再探索期限が毎フレーム切れる状態に入り、**フレーム時間が自分自身を
   維持する正のフィードバック**が成立する。これが「一度重くなると回復しない」の正体。

MAP刷新で柱・チョークポイント・地形障害物を導入したこと、およびMAPサイズ78²→86²→94²・
敵上限32→40→48がラン中単調増加することが、この高コスト経路の発火率を押し上げていた。

### 38.2 対策

**通行可否の前計算（`systems/dungeon_map.gd`）**
`DungeonMap.has_navigation_clearance(cell)`を追加した。「自分と周囲8マスがすべて床」を
生成完了後に1度だけ`PackedByteArray`へ焼き、以降は配列1回参照で答える。初回構築は実測1.4ms。
床の書き換え（`set_floor`/`mark_terrain_obstacle`）は`DungeonGenerator`と
`RoomTemplateFactory`の生成時にしか起きないため、実行中に作り直しは走らない。
書き換え時は`_clearance_cache_valid`を落として次回問い合わせで作り直す。

**再探索条件の修正（`components/ai/chase_strategy.gd`）**
再探索の判断を経過時間だけに一本化した。`_path.is_empty()`と`goal`変化による
即時再探索を廃止し、探索失敗時も次の期限まで待つ。使われなくなった`_path_target`は削除。

**1フレームあたりの探索予算**
`MAX_PATH_BUILDS_PER_FRAME = 4`を導入し、全Agent共有のstatic予算として
物理フレーム単位で配る。予算切れのAgentは再探索期限を進めないので次フレームに順番が回り、
前回の経路（無ければ直進）で動き続ける。敵が何体いても経路探索がフレーム時間へ与える
負荷が頭打ちになるため、38.1の正のフィードバックが構造的に成立しなくなる。

### 38.3 実測（vsyncを切って計測、同一手順で修正前後を比較）

| シナリオ | 修正前 | 修正後 |
|---|---:|---:|
| 敵20体 | 0.891 ms | 0.86〜1.32 ms |
| 敵40体 | 2.987 ms | 0.63〜0.76 ms |
| 敵60体 | 8.104 ms | 0.80〜1.24 ms |
| 壁越し40体（視界が遮られた敵32〜34） | **1021.6 ms（1 FPS）** | **0.64〜0.92 ms** |
| フレーム時間に占めるAIの割合（60体） | 68% | 18〜34% |
| 経路探索1回 | 15.8 ms | 0.02〜0.73 ms |

壁越し状態を10秒維持しても平均0.70〜0.95ms／最悪19msで悪化しない。同区間で敵→プレイヤーの
平均距離は552px→202px、視界が遮られた敵は34→17へ減っており、**敵は従来どおり壁を回り込んで
接近している**（挙動の退行なし）。敵20体の帯が広いのは、この速度域（約1,000fps）では
レベルアップModalやGCの単発スパイクが平均へ乗るための計測ばらつきで、修正前後で有意差はない。

### 38.7 経路探索コストの上限化（2026年9月5日・38.2の追加修正）

38.2で`MAX_PATH_BUILDS_PER_FRAME = 4`を入れたが、**回数だけを抑えて1回あたりのコストを
抑えていなかった**。幅優先探索は展開セル数が距離とともに増えるため、遠くの敵ほど1回が高くなる。
予算を4に決めたときの実測値「1回0.73ms」は、プレイヤーを最も遠い敵の位置へ瞬間移動させた
直後に測っており、敵とプレイヤーが密集して経路が極端に短いサンプルだった。

#### 対策

1. **通行可否を配列直読みへ**（`DungeonMap.get_navigation_clearance_data()`を追加）。
   幅優先探索は1セルにつき4回の通行可否判定を行うので、1回1.4usのメソッド呼び出しが
   支配項になっていた。前計算済み`PackedByteArray`を1回だけ取得し、内側ループでは
   添字参照だけにする。`_has_clear_floor_line()`も同じ理由で同じ扱いにした。
2. **`MAX_PATH_SEARCH_CELLS = 900`** を新設。展開セル数が上限に達した探索は経路を諦めて
   空を返し、その敵は直進する（壁には`move_and_slide()`が沿う）。距離が伸びても
   1回あたりのコストが頭打ちになる。
3. **`MAX_PATH_BUILDS_PER_FRAME` を 4 → 2**。
4. `goal`の算出を予算分岐の内側へ移動（予算切れのフレームで計算して捨てていた）。

#### 実測（同一Harness・修正前後）

床かつ3x3の余裕があるマスの組をgrid距離帯ごとに選び、`_build_floor_path()`を24回ずつ計測。

| grid距離 | 修正前 1回 | 修正後 1回 | 予算込み最悪 前 → 後 |
|---:|---:|---:|---:|
| 10 | 610 us | 177 us | 2.44 ms → **0.35 ms** |
| 20 | 1,040 us | 367 us | 4.16 ms → **0.73 ms** |
| 30 | 2,142 us | 606 us | 8.57 ms → **1.21 ms** |
| 45 | 2,739 us | 710 us | 10.96 ms → **1.42 ms** |

1セルあたりのコストは2.5〜2.7us → 0.5〜0.8us。**経路探索がフレーム時間へ与えうる最大の負荷は
10.96ms → 1.42ms**（60fps予算16.6msの66% → 8.5%）。

挙動は維持されている。壁越し800pxへ敵30体を置いて10秒放置すると、
敵→プレイヤーの平均距離は800px → 243px、視界が遮られた敵は31体 → 14体へ減る。

#### 計測上の注意（重要）

この検証の途中、敵をリング状に強制配置するHarnessが**敵を壁の中へ埋めてしまい**、
物理のめり込み解決がフレーム時間を支配して「距離が遠いほど重い」という誤った表を出した
（610pxで15.5ms等）。配置先を「床かつ`has_navigation_clearance()`が真のマス」に限定し、
壁の中に入った敵の数を毎回報告するようにして初めて正しい値が出た。
**敵を強制配置する計測を書くときは、必ず配置先が有効な床かを検証し、報告に含めること。**

#### 残っている課題

この修正は「多数の敵が同時に再探索を要求したときの上限」を下げたものであり、
**実プレイで報告された「常時カクカク」を再現・解消したことの証明にはなっていない**。
敵30体を適正配置した状態のフレーム時間は修正前で1.06〜1.53ms、修正後で0.88〜1.41msと
差が小さい。実症状の再現は未達のまま。

### 38.4 蓄積が原因ではないことの確認

論理900秒を30秒刻みで31点採取した結果、**Orphan Node数は全区間0**、EventBusのシグナル接続数は
46で一定、Tween数は0〜2、Video Memoryは28→44.8MBで頭打ち。Node増加分（528→1067）は
クラス別差分集計の結果すべて生存中の敵39体そのもので、リークは存在しない。
`StatusApplySystem`の`_burning_targets`はinstance_idをキーにしたDictionaryで構造的に
重複不可、Timer/Tweenの生成も無い。`StateIndicator`のTextureは状態組み合わせ単位の
staticキャッシュ（上限31件）で、Sprite2D数は敵数と完全一致する。

### 38.5 対象数に比例する毎フレーム処理（既知の残コスト）

38.2の対策後、次に大きいのは以下。現状のフレーム時間では表面化していない。

- `entities/projectiles/projectile.gd`の追尾処理: 弾ごとに全敵走査でO(弾数×敵数)
- `entities/allies/ally_skeleton.gd`: 味方ごとに全敵走査＋`ChaseStrategy`を共用
- `components/player_upgrades_component.gd`の`resolve_state_condition_damage()`:
  被弾1回ごとに`metadata.duplicate(true)`1回と`has_state()`5回。`has_state()`は毎回
  `get_states()`で新規Arrayを確保して5x6の二重ループを回す
- `effects/effect_theme_manager.gd`の`_spawn_chain()`: ヒットごとに全敵を`sort_custom`

### 38.6 状態付与接続後の再計測（2026年9月5日・Phase 1のみ）

Godot 4.7.1/Vulkan Mobile、vsync無効・max_fps=0、等速MAP1 300秒の自然戦闘で470撃破。
180秒では敵29体/燃焼13体、直近30秒平均1.300ms・p95 2.345ms。全区間p95は1.893〜2.814ms。
持続低下は未再現だが最大123.020msの単発スパイクあり、原因未特定。
6項目の各60frame A/Bでは180秒の敵全処理OFFが0.631ms（28.39%）、300秒の敵描画OFFが
0.231ms（18.14%）減と順位が変わり、支配原因は未確定。性能修正は行っていない。
全計測値・条件・短区間比較の限界は`docs/performance_phase3_measurement.md`に記録。
一時Harnessは削除し、game.gdは開始時とbyte単位で一致する内容へ復帰。

### 38.7 併せて修正した既知不具合（性能とは別件）

**状態異常が実プレイで一度も付与されていなかった（2026年9月4日に修正済み、詳細は36.3）。**
900秒の計測中`_burning_targets`は全区間0だった。
`StatusApplySystem.apply_state()`の呼び出し元は`attack_pattern_base.gd`の
`apply_direct_damage()`だけだが、各職業の主力攻撃はそこを通らない
（近接は`spawn_arc_hit`/`spawn_line_hit`→`MeleeHit.on_hit()`、遠隔は`Projectile`→
`HurtboxComponent`。どちらも付与しない）。`apply_direct_damage()`を通るのは一閃派の処刑や
homing_bolt Lv4の爆発などの派生効果だけである。属性廃止時に`hurtbox_component.gd`の
`apply_element_damage`ブロックを撤去した際の取りこぼしで、36章の状態異常・状態カード9枚・
天賦図の状態トリガーはすべて空振りしていた。`HitboxComponent`に状態IDを持たせ、
`HurtboxComponent.apply_hitbox_damage()`から付与する形で接続した（36.3参照）。

---

## 39. 通常2D戦闘 Phase 1〜2（2026年9月8日）

HD-2D試作との比較結果を受け、探索性とPixel背景は通常2Dのまま維持し、戦闘の立ち上がり、
キャラクター体格、ボス戦の読み合いだけを段階移植した。2026年9月11日に正式方針を2Dへ固定し、
2.5D試作／3周チャレンジはタイトル画面と通常実行経路から撤去した。

### 39.1 Phase 1 — 逃走安全性・敵密度・成長速度

- 全職業の`CharacterData.move_speed`へ共通0.90倍を掛ける。職業間の速度差と装備／状態倍率は維持する。
- 通常敵の序盤XPは1。初回必要EXPを10にして約10体で最初の成長へ到達させる。
  Lv10までは10→12→…→28と軽快に増やし、Lv11以降は線形項と緩い二次項で徐々に重くする。
- 通常敵HP倍率はMAP1/2/3で2.80/3.60/4.50、Boss HP倍率は3.0/4.6/6.8。
- Spawnは2.80秒・1体から開始し、2.30→1.65→1.05→0.68→0.55秒へ連続的に加速する。
  同時数はBreakpointで1→1〜2→2〜3→3〜5→5〜8→8〜12へ段階上昇し、
  MAP1/2/3の生存上限96/144/192体を越えない。
  既存の侵攻は同時数と間隔へさらに倍率を掛けるため、平常の呼吸と明確なピークを両立する。
- 代表Buildの実経路は78秒25体、308秒207体、432.3秒424体でMAP1条件420体へ到達した。
  この値は4倍速・検証用高HPであり、最終的な中央値／難易度は実プレイで再調整する。

### 39.2 Phase 2 — 2D体格とボス戦

- Player表示は1.50→1.65、通常敵は1.25→1.40、Eliteは1.60→1.78。
- 全Bossは倍率を揃えるのではなく、SpriteSheetBuilderが実際に採用する影付きIdle全コマの
  不透明範囲を基準に個別補正し、画面上の基準高を約65pxへ統一する。

| Boss | 元の不透明高 | visual_scale | 実表示高 |
|---|---:|---:|---:|
| Black Knight A / B / C | 33 / 24 / 31 | 1.97 / 2.71 / 2.10 | 65.01 / 65.04 / 65.10 |
| Demon A / B / C / D / E | 22 / 21 / 28 / 27 / 25 | 2.95 / 3.10 / 2.32 / 2.41 / 2.60 | 64.90〜65.10 |
| Flame Golem / Minotaur | 31 / 22 | 2.10 / 2.95 | 65.10 / 64.90 |

  標準剣士の不透明高は22×1.65=36.3pxのため、Bossは約1.79倍。試作Minotaurの
  3D表示高3.0÷剣士1.68と同じ比率差である。見た目・移動Collision・Hurtbox・攻撃接触判定は
  同じ個別倍率で拡大する。赤Outlineは拡大後も画面上約2pxに保つ。
- 通常2D Minotaurへ、試作の「突進→薙ぎ払い→環状衝撃波→3連地割れ」を移植した。
  予兆寸法と命中判定は同じNode2D値を共有する。薙ぎ払いは半径145px・半角70度・0.18秒で、
  元画像加工8コマの全身動作、白外縁／氷青の三日月、掃引判定を同じ進行率で同期する。
  予兆・演技・剣撃はBoss死亡／MAP清掃／攻撃終了時に残さない。他9Bossの既存固有技は維持する。

### 39.3 検証

- `--map-phase2-check`: 移動90%、初回EXP10・Lv10前後の曲線、Spawn序中終盤、通常敵表示／判定、全10Boss実表示高、
  Minotaur 4攻撃順・全身薙ぎ払い・Transient消去を確認してPASS。
- `--map-runtime-check`: 侵攻3回×3MAP、Boss、宝箱、MAP遷移、Run ClearまでPASS。
  MAP2/3遷移最大Frame sliceは19.160/24.183ms。
- `--map-mass-density-check`: MAP3終盤条件で最大192体を実生成し、192体を180frame維持してPASS。
  Headless実測は平均7.238ms、p95 21.746ms、最大28.108ms。
- `--map-combat-check`: 424/420体、論理432.3秒でPASS。
- 全191 GDScriptの実loadはfailure 0。Windows Sandboxでsystem CA storeを読めない環境警告は
  ゲームコードとは無関係。長時間実プレイ中央値、全職業の体感、全Bossの自然戦闘時間は未確認。

## 40. UI世界観刷新（2026-09-10）

### 40.1 表現方針

- UIの統一テーマは「朽ちた王国の地下を踏破する、鮮やかな16bit遺跡ファンタジー」。
- 濃紺／青灰の石材、古金の金具、青緑の封印石を共通語彙とする。危険・鍛造だけ朱赤／橙を使う。
- 装飾は主画面の紋章枠、区画の石板、選択カードの三段階に分け、同じ菱形を全要素へ反復しない。
- Level Up、Shop、Boss報酬、完成大技のカードはIcon背面の菱形を廃止する。Icon本体の輪郭を見せ、名称は日本語だけを優先して一行に収める。

### 40.2 画面構成

- TitleとCharacter選択は地下王宮の封印門を背景にする。
- 戦闘HUDの武装・戦利品・完成大技は、実Icon付きの小型石板を2列で表示する。従来の上限、重複数、Tooltipは維持する。
- Level Up、Boss報酬、完成大技、Room選択は共通祭壇枠を使う。Shopは金貨色、Talentは青緑、鍛造は橙で役割を区別する。
- Pause、コンセプト構築、Equipment、Resultを同じ書体・石板・古金枠へ揃える。コンセプト構築は起点／スキル／補助を金／青緑／紫で区別する。

### 40.3 変更しない仕様

- 戦闘方式、敵AI、数値Balance、Upgrade／Item／Roomの抽選、購入価格、Save形式、入力Actionは変更しない。
- UI変更の詳細、参照作品、生成素材の再現手順は`docs/ui_world_refresh.md`へ記録する。

## 41. 開発ダッシュボード（2026-09-11）

- `dashboard/dist/`を公開可能な静的Webとして保持する。HTML/CSS/JavaScriptだけで構成し、画面内容は`dashboard/dist/data/*.json`から生成する。
- 全体進捗は、CategoryごとのTask平均に`weight`を掛けた加重平均。Taskの100%は実装完了とTest完了の両方を満たす場合だけ設定する。
- DashboardはRoadmapだけでなく、3MAP、敵6階級、通常敵22種、Boss10種、職業再編、状態異常、旧Fusionの再定義、完成大技23種、Equipment、UI/VFX/Audio、Performance、Known Bugs、Decision Logを一元表示する。
- 現行正本では旧属性Lv/欠片/Element Fusionを廃止済みのため、火・氷・雷・光・闇は状態異常/完成大技の語彙として表示し、旧Fusion武器はShopの遺物武器として表示する。廃止前の仕様を現行機能として表示しない。
- Desktopは左SidebarとTable、Tabletは縮小Sidebar、MobileはHamburger Menu＋Bottom NavigationとCardへ切り替える。Dashboard全体の横Scrollは発生させず、操作Targetは44px以上を基準とする。
- 主要な機能追加、仕様変更、Bug修正後は`docs/dashboard_update_rules.md`に従い、Task Status、Progress、Bug、Decision Log、更新日を同時に更新する。
- 公開DataへSecret、Credential、個人情報、PC固有の絶対Pathを含めない。
- 実装状態を文字だけで誤認しないため、入口、探索、Boss、報酬、完成大技、Shop、天賦、装備、Resultの実画面CaptureをDashboardへ掲載する。画像には判断区分、確認点、関連Systemを必ず付ける。
- `相関・仕分け`では、1 Runの体験Loop、MAP/敵/Boss階層、職業/攻撃/状態/完成大技、Phase実装順の4図を管理する。
- 要不要の判断区分は、`維持`、`再設計`、`削除・非採用`、`保留`の4種類。手動攻撃、共通回避、全職天賦は依存先が決まるまで`保留`とする。HD-2D正式移行は2D方針確定により`削除・非採用`とする。

### 41.1 キャラクター・敵・Boss図鑑

- 職業再編台帳10種（正式Player6職・Boss転用4職）、通常敵22種、Boss戦13件は、ゲームが実際に参照するSpriteから代表Frameを切り出し、Dashboardの図鑑カードへ掲載する。
- 図鑑用画像は`dashboard/dist/assets/portraits/`へ公開用Copyとして置き、ゲーム本体のSpriteや戦闘Dataは変更しない。
- 職業は青緑、通常敵は古金、Bossは朱赤の額縁で区別し、カード内では名称、ID、登場MAP、状態、主要数値、通常攻撃、役割・報酬を同じ順序で表示する。
- PCとスマートフォンで同じ42体へ到達でき、横Scrollを発生させない。画像追加・差し替え時はDataの`image`参照と実Fileの両方を検証する。

## 42. 職業再編 — Player6職と職業転用Boss3戦（2026年9月11日）

### 42.1 正式Player職

- 正式Playerはソルジャー、剣士、弓兵、騎士、重装斧兵、魔導士の6職とする。
- 6職は近接基準、技量、射撃、機動防御、重量、魔法制御の役割へ分け、天賦・Upgrade・能動Skillの重複を減らして個性を強める。
- 槍兵、聖堂騎士、司祭、死霊術師はPlayer選択とPlayer向け拡張対象から外す。既存Dataは移行完了まで削除せず、Boss転用元として保持する。

### 42.2 職業転用Boss

- 槍兵は単独Bossとし、長距離突進、貫通突き、反転突撃を核に射線と位置取りを問う。
- 死霊術師は単独Bossとし、Skeleton召喚、死者蘇生、呪い領域を核に召喚数と本体接近の判断を問う。
- 聖堂騎士と司祭は2体で1つのペアBoss戦にする。聖堂騎士が前衛と主攻撃を担当し、司祭は直接攻撃を抑えて聖堂騎士の強化、回復、聖域展開を優先する。
- 司祭の支援は予兆、対象、効果時間、再使用間隔を明示し、回復だけで戦闘が膠着しない上限を設ける。撃破順によるPhase変化と数値はPrototype後に確定する。

### 42.3 実装順

1. 職業選択、解放、Save互換を正式6職へ移行する。
2. 転用4職のPlayer専用Upgrade・天賦・能動Skill参照を整理し、Boss用Dataを独立させる。
3. 槍兵と死霊術師を単独Boss Prototypeへ接続し、予兆と攻撃間隔を検証する。
4. 聖堂騎士＋司祭を2体同時戦へ接続し、支援対象、回復上限、撃破順、死亡時の残存挙動を検証する。
5. 3MAP内の配置、HP・Damage、報酬、登場演出を決め、通常2D回帰と長時間実Playを行う。

現時点で確定したのはRosterとBoss役割であり、ゲーム本体の職業選択、戦闘AI、数値、MAP配置は未実装。Dashboardでは設計中として扱う。

## 43. 2D正式採用と旧属性系宝箱報酬の停止（2026年9月11日）

- 正式な画面表現は通常2Dとする。タイトル画面の「2.5D試作：剣士」「2.5D遠征：剣士三周」を撤去し、通常探索と2D演出確認室だけを残す。
- 光・闇・火・氷・雷を前提にした旧完成大技は、属性システムを再設計するまで通常Runの獲得候補へ出さない。
- 通常MAPの`skill`宝箱枠は装備へ置換する。旧`attribute`／`skill`が残る互換Dataを読み込んだ場合も、通常Runでは装備報酬として処理する。
- Boss宝箱は旧完成大技3択を開かず、Rare／Legendary装備を出した後にShopまたはRun Clearへ進む。
- `completed_skills.json`と完成大技Runtimeは将来の非属性版再設計と演出確認用に保持するが、通常MAP進行からは接続しない。


## 強敵固有技の初回実装 — 2026-09-12

- 重装オークだけにorc_step_slashを接続。既存Attack01の7フレームを使用し、全体の回転・伸縮による攻撃表現は行わない。
- 開始0.12秒だけ目元を赤く発光。構え0.55秒、刃が走る部分0.12秒、0.61秒時点に前方120度・58pxの単発判定。命中ダメージは通常の1.35倍。1.10秒で終了し、再使用6秒。
- 狙いは開始時に固定。22pxの踏み込みはmove_and_collideで壁・水晶を尊重。射線が塞がる場合は発動／命中しない。スタン・死亡・部屋停止で中断する。
- 見せ方確認用の実エンジン等速GIFはartifacts/strong_enemy/orc-step-slash.gif。撮影は専用シーンで拡大表示。通常出現のEnemyDataにも接続済み。
- 他の強敵、階級順の出現制御、同時発動数制限は今回未実装。全体の自然プレイ調整も今後。


## 強敵6体の固有技 — 2026-09-12

- 重装スケルトン=迎撃突き、大剣スケルトン=大薙ぎ払い、ブラッドモンスターB=血槍、エリートオーク=二連斬り、ワーベア=跳びかかり叩きつけを通常EnemyDataへ接続。重装オークと合わせて6体。精鋭化でも同じ技を継承する。
- systems/strong_enemy_special.gdに実フレームと秒数を指定。赤い合図0.12秒、構え約0.55〜0.79秒、斬る部分約0.12秒。二連斬りは0.56秒と1.17秒に命中窓。既存0.5秒無敵時間を尊重する。
- 身体全体の回転・伸縮による攻撃表現を追加しない。クマは6pxだけ浮いて34px前進、着地を円で予告。壁を越えず、スタン・死亡・部屋停止で浮き姿勢とロックを解除。血の敵は目のない素材なので口元に赤い合図。
- 近傍280px以内で同時に固有技を実行できる敵を2体までに制限。密着後も発動可能。向きは開始時に固定。
- tools/preview_strong_roster.tscnで実エンジンの6体を等速撮影。スマホ用H.264/yuv420p/faststart MP4をダッシュボードstrong-enemies.htmlへ掲載。各動画後半は横回避。全体の自然プレイ検証は未実施、出現順変更は未着手。

## 精鋭能力の視認演出刷新 — 2026-09-12

- 火炎・雷撃・氷結・毒・吸血・堅牢の効果と数値は維持し、戦闘中の視認演出を刷新する。
- 精鋭本体の足元に、能力ごとに形と色が異なる紋章を常時周回させる。複数能力では全紋章を同時表示する。
- 火炎・雷撃・毒は床予兆が収束してから発動し、予兆中にはダメージを与えない。火炎は橙の爆炎、雷撃は黄青の雷柱、毒は紫緑の持続渦で区別する。
- 氷結と吸血は攻撃命中時に対象へ専用VFXを表示する。吸血は精鋭側にも吸収光を表示する。堅牢は展開時の盾VFXに加え、シールド残量がある間は六角障壁を常時表示する。
- 表示は敵側の特殊能力であり、廃止済みのPlayer属性Lv・欠片・Element Fusionを復活させない。
- tools/preview_elite_affixes.tscnで、6能力の常時紋章、予兆中無傷、発動後ダメージ、氷結Slow、吸血回復、堅牢Shieldを確認する。スマホ用MP4はdashboard/dist/elite-affixes.htmlへ掲載する。


### MAP2・MAP3 建築ランドマーク（2026-09-12）

MAP2: 紫晶採掘場／結晶神殿。MAP3: 古代溶鉱炉／冷却水車。各最大2箇所を通常部屋の北寄りに配置する。開始地点とBoss・精鋭部屋を避け、6x2セルの台座と周囲の通行幅を確保する。床全体の到達性を維持できない場合は配置を省略。台座はTile衝突・経路探索・敵出現候補で共通して通行不可とする。Mapに配置情報を保持しStage再構築時に増殖させない。専用透過Atlasを使用し、MAP1や報酬・戦闘能力は変更しない。


### ランドマーク配置改訂（2026-09-13）
独立した部屋中央の台座配置を廃止。北壁と接する位置のうち、背面4行が壁、前面3行と左右に通行余地がある場所に配置。形状ごとの乱数で点在させ、基本1か所、35%で最大2か所。2つ目は22セル以上離す。安全な候補がなければ省略。鉱山には景観用の採掘作業員を配置し、2.8秒周期で構え・素早い打撃・戻し・休止を行う。戦闘、報酬、会話は追加しない。


### MAP2・MAP3 作画統一（2026-09-13）
ランドマーク基準の石肌・欠け・目地・錆・木材表現へ壁床小物を統一。高密度の素材を32pxの世界セルに直接描き、床・壁正面・岩盤の明暗を分ける。旧記号状装飾は表示を外し、収納・地形柱には新しい小物画像を当てる。物理Tile、経路探索、配置、採掘作業員を保持。MAP1は従来の描画を維持。

## 装備200種 — 2026-09-13

- templates.jsonを25→200種類へ拡充。既存25 ID/名前/能力候補を保持、新規175。武器52、頭31、胴31、腕24、脚24、装飾38。各レア度40。
- painted_200/に生成8シートと200 AtlasTexture。既存ドロップと合成が同じカタログを読み込み、新規品も取得可能。抽選確率と所持品50枠は維持。系統はアート上の出自で、セット効果/新属性ではない。
- equipment_catalog_200.tscn: 200生成、全画像書出、6部位装備 PASS。equipment_merge_check PASS。旧テストの25件前提と旧希少度ラベル参照を更新。
- artifacts/equipment_200/implemented.png は実装画面。Dashboardに全200種の画像と能力候補を掲載。

## MAP2壁・連続鍛造 — 2026-09-13
- MAP2壁専用masonry_wall.pngを新規生成。全solid描画に石積みを適用、左右側面/天端/下端の陰影で床と区別。既存collision維持、MAP1/3変更なし。
- 合成完了・演出スキップ後とも鍛造タブ維持。素材枠を空にし、利用可能なら同レア3点セットへfocus。
- 実描画map2.png更新、equipment_merge_check failures=0（連続2回とskip確認）。Dashboard記録更新、今回の記録は未公開。
## 成長バランス初回調整 — 2026-09-13

- 実装済み。緑→青3個95%、青→紫5個90%、紫→橙7個85%、橙→赤10個80%。失敗時は選択順の先頭から1/1/2/2個のみ消費し、残りは個体・能力・お気に入り状態を保持。成功時は全素材を消費。最高段階は合成不可。未装備・未ロックの同レア素材のみ。鍛造は最大10枠/2行、確率と損失表示、完了後タブ維持。
- 装備の新規生成レンジは従来比で攻撃50%、防御30%、最大HP40%、攻撃速度70%、会心率70%、会心ダメージ65%、移動速度85%（整数能力は丸め）。職業の基礎値と経験値曲線は維持。既に所持している個体の数値は書き換えず、新RUNで評価する。
- 防御の固定減算による軽減は最大60%。他のスキル軽減は別乗算。命喰らい回復を橙2/赤4、無効化を橙4%/赤7%へ。
- 通常装備抽選の重みは緑70/青25/紫4.5/橙0.5/赤0。Bossはearly65/30/5/0/0、mid30/50/18/2/0、late10/45/35/10/0、final0/25/50/23/2。装備そのものの落下率は維持。
- ランダム回復ハート通常1.5%、精鋭4%、回復最大HP6%、寿命15秒、地面上限5個。確定回復報酬は別扱い。
- forge_balance_check: 4段階、強制成功/失敗、部分返却、重複/ロック/消費済み素材拒否、画面維持、ハート上限、防御上限を確認。3MAP通しの体感バランスは未評価。
- 未完了: 敵の重なりと間合い、局所ヒットストップ、MAP2/3敵構成、200装備の属性/固有役割/レア度の全面再設計。


## 打撃感・攻撃間合い — 2026-09-13
- 確定したPlayer直接HitからEnemyBasic.receive_hit_impactへ接続。通常50ms、会心/ActiveSkill80msの敵個別停止。精鋭0.65倍、Boss0.4倍。再発動間隔220ms/Boss400ms。継続・二次ダメージは停止対象外。通常Hitの全体14ms停止を削除し、Player操作を維持。
- 既存の被弾姿勢/明滅/命中音を維持して停止に合わせる。停止解除後3/5pxの小さな押し戻し。既存Weapon Knockbackも停止中は予約、解除後に壁Collisionを使って適用。固有攻撃を持つ敵の自動微小押し戻しは抑制。
- 通常追跡はattack_rangeの70%（上限24px）で停止。中心重なりは敵だけを壁判定付きで外へ戻す。敵同士の大群分離・Boss突進中の重なりは引き続き別調整。
- impact_check PASS: 実Health経路、停止解除、Player/全体時刻維持、連打制限、DOT除外、間合い、完全重なり、吹き飛ばし待機、停止中死亡解除。大群での長時間体感は未評価。
- ユーザー方針: 一つの変更に関連するUI・操作・既存機能との接続も合わせて更新する。

## 2026-09-13 コンパクトUI・今後の戦闘方針
- HUDを左下HP・右下職業技・最下端EXPへ再配置。武装／戦利品は開閉式。C所持品・T天賦図・Space職業技を維持。
- 所持品画面を中央へ縮小（1600×900時、基準1360×790）。装備比較・フィルタ・ステータス名・最大10素材枠・連続鍛造を維持。開いている間はHUDを隠し、閉じると元の表示状態に復元。
- 実描画でHUD・50アイテム・10素材鍛造を確認。forge_balance_check成功。Embervilleの配置と情報密度を参考に既存素材を調整した実装。
- 次回相談：少数の敵を倒し徐々に成長する戦闘へ再設計。従来の大量湧き路線に優先する新方針。今回は敵数、XP、戦闘ロジック、操作を変更していない。
- 装備の属性と強度の再設計は引き続き未完了タスク。公開サイトは今回未更新。

## 2026-09-13 小型所持品・ホバー詳細
- 常設の3列目を撤去し装備＋所持品の2列へ。アイテム48px・7列。装備スロット52px。装備絵のアルファ輪郭をシェーダーでレア色に描画し、セル枠は中立色。
- ホバー詳細はアイコンに隣接し画面内へ補正。クリック固定、矢印選択でも比較。カーソルを詳細へ移動して装備・お気に入り・保護を操作可能。
- 鍛造は独立した浮動パネル。10素材、失敗返却、連続鍛造を維持。閉じるとHUD復元。
- capture_compact_hover、forge_balance_check PASS。通常50アイテムとホバー実画像はartifacts/compact_hover。戦闘ロジック変更なし。

## 2026-09-14 打撃感の第一調整
- Emberville方向への近接命中表現。公開映像の内部数値を複製したものではない。
- 既存50/80msの敵局所停止を維持、反応後の基本後退3/5→5/9px、潰れ幅8%→2.5%、弾性戻りを滑らかな減速へ。
- 扇形／刺突命中時に130msの細い白い接触線。1攻撃最大3個、範囲パルスには追加しない。既存命中音は維持。攻撃速度・判定時刻・敵数・成長値は未変更。
- impact_check PASS。終了時に既存のObjectDB/resource残存警告あり。
- 未完：単純な小物と宝箱の再生成・配置、装備ドラッグ＆ドロップ。前回は詳細素材生成までで、ユーザーから簡素化指示あり。武器2系統制限は相談中。


## 2026-09-14 手動戦闘と少数敵バランス（初期値）
- WASD移動、J通常攻撃（長押し可）、K回避、L職業技。SpaceからLへ移行。C/T/E維持。I未使用。
- 近接は移動方向へ振る。対象への自動旋回・踏み込みを撤去し空振り可能。遠距離の標的選択は既存補助を維持。回避／攻撃の同時開始を抑制。
- 回避80px/0.20秒、再使用0.85秒、最初0.12秒無敵。壁衝突あり、メニュー中停止。攻撃中の回避キャンセルは不可。
- MAP通常敵上限8/10/12、1体ずつ3.5〜4.5秒。サージによる数倍増を撤去。ボス撃破条件60/80/100（旧420/650/900）。敵HP倍率3.2/4.0/4.8、攻撃倍率1.3/1.6/1.9。ボスHP倍率2.2/3.2/4.2、攻撃0.9/1.05/1.2。
- EXP初回15、Lv10まで+5/段階、その後増加。剣士初期吸血を撤去。装備・合成ルールは維持。
- manual_combat_check PASS（自動攻撃なし、J空振り、K再使用制限・無敵終了・メニュー停止、L割当）。impact_check PASS（終了時リソース残存警告あり）。HUD実描画確認。
- Emberville内部値の複製ではなくVSGAMEの初期調整。3MAP通しの体感バランスは未評価、連携コンボ・武器別アニメーション・装備武器制限は未実装。

## 2026-09-14 探索配置戦闘・低い初期ダメージ
- 前回の時間湧き／高耐久・高火力調整に優先。MAP通常敵は24/30/36体を生成後に一度だけ配置。開始地点300px内、精鋭部屋・Boss部屋を除外し、通行余裕のある床へ180px以上離して配置。倒しても補充しない。
- 通常配置敵は200px以内かつ壁越しでない視認、または被弾で反応。380pxを超えて離れると追跡終了。精鋭部屋とBoss専用行動は従来方式を維持。
- 職業基礎攻撃を半減（剣士14→7）。職業技の基礎ダメージ最低10制約を撤去し、通常攻撃と同じ低い基礎値に追従。装備由来の上乗せは今回は維持（全面再設計は残作業）。
- 通常敵HP倍率0.9/1.2/1.6、攻撃0.6/0.8/1.0。BossHP0.8/1.2/1.7、攻撃0.5/0.65/0.8。HPも下げ、低火力化による硬すぎる敵を避ける。
- Boss撃破条件12/16/20へ変更、時間解放は維持。通常襲撃サージと自動報酬を停止。敵種は配置地点の遠さで段階選定し、その場で待っても強い種類が追加されない。
- exploration_encounter_checkで実MAP配置、床余裕、開始距離、待機、近接発見、追跡解除、非補充、剣士基礎値を確認。3MAP通しの成長・装備込みの体感バランスは未評価。公開Dashboard未反映。

## 2026-09-14 本体衝突・命中反動・ドラッグ装備
- Player mask=9、Enemy layer=8/mask=9。本体の相互除外を撤去し、敵同士も衝突。死亡時は本体判定を無効化。通常の間合いは両者の実Circle半径合計+2px、攻撃射程はそこから最低6pxを確保。壁越しの通常攻撃／扇・直線近接判定を遮断。
- 既存50/80ms局所Hitstopを維持。通常敵の微小反動7/12px、復帰待ち80/120ms。押し戻しが終わるまで追跡移動を再開しない。武器ノックバックを瞬間移動から壁衝突付き短時間移動へ。強敵固有姿勢／Bossの無差別な追加反動は抑制。
- 所持品と装備ButtonにGodot native drag forwarding。アイコンpreviewと対応部位の青緑highlight。正しい部位にdropして装備交換、装備枠から所持品のitem/余白へdropして解除。間違った部位／画面外は変更なし。元itemをdrag開始時に消費しない。drop完了後deferredで再描画。鍛造中は操作拒否。
- ホバーの装備／解除Buttonを非表示。drag中は詳細popupを隠しdrop先を塞がない。部位フィルタ・50枠・鍛造経路を維持。装備輪郭shaderのbuiltin sampler引数によるコンパイラエラーも修正。
- impact_check / manual_combat_check成功。contact_drag_checkは実マウスeventで空き装備・不正部位拒否・交換・解除・個数維持を確認、OpenGL実描画でもPASS（stderrなし）。artifacts/contact_drag/drag.png。
- Emberville開発者実演を再参照。通常攻撃と押し戻し／stun技、武器別comboの役割差を確認。停止時間等の内部数値は公開根拠がなくVSGAME用調整。新combo・新武器アニメ全体の移植を完了したものではない。docs/emberville_contact_research.md参照。

## 2026-09-14 宝箱差替・モーション別命中・歩行押し出し修正
- TreasureChestの矩形仮描画をchest_simple_v2.pngの透過した閉／開2状態へ接続。通常幅40、Boss幅48。足元StaticBody34×12、E範囲64。開封済み表示と報酬一回制御を保持。artifacts/chest_ingame.pngは実ゲーム描画。
- 剣士attack1はframe3に1回、attack2はframe3/6/12に3回、attack3はframe5/7/9/11に4回の命中。frame_changedに同期し、モーション全体の旧ダメージ予算を各打へ分配。短い敵iframeで後続打が欠けない専用経路、各Hitbox内の重複防止を保持。一閃派は単発attack1を選択。通常速度1.65倍に攻撃速度補正。J一回でそのモーション一連を再生。
- 敵が接近距離を維持するため後退する補正を撤去。静止敵に不要なmove_and_slideを呼ばず、接触の復元処理による押し出しも止める。Hitstopでprocess停止してもCollisionObjectはKEEP_ACTIVE、被弾中も本体・Hurtboxを維持。攻撃ノックバックは残す。
- sword motion中は壁時計のアニメロックを使用せず、実際の再生終了を待つ。モーダル休止後も残る攻撃Frameが再生される。
- chest_strikes_check: 実ダメージ1/3/4、180physics ticks前進で敵位置不変、本体遮断、開封一回、alpha確認。60fps・20fps・途中menu休止でPASS。manual_combat_checkとimpact_checkもPASS。OpenGL宝箱描画stderrなし。テスト終了時に既存ObjectDB/resource解放警告が残るが、実行中のScript/Physicsエラーなし。
- Emberville動画25:30付近を再参照。剣112コンボは確認したが、歩行で敵を押せるかの内部仕様は断定できない。今回の「歩行は遮断、押し戻しは攻撃時」はVSGAME側の設計判断。


## 2026-09-14 探索型MAP構造・番人の鍵・探索図
- 公開開発ログと指定動画の26:47/28:01/46:48/47:40を参照。内部アルゴリズム・タイル数は非公開。VSGAME向けの再構成。docs/emberville_map_research.mdに根拠・設計・優先課題を整理。
- 通常3MAPはExplorationLayoutへ。13/15/17区画、116×94 / 120×97 / 124×100、3〜4タイル通路。役割を決めてから変形部屋と短い接続を生成。seedで寸法、形状、反転、迂回路再接続が変わる。旧ROOM/Test Lab生成は保持。
- 部屋別15/16/19体（ボス除外、精鋭1体込み）。弱敵／標準敵／固有技強敵を1〜2体ずつ配置。追加湧きと時間巡回精鋭なし。配置精鋭は能力1/1/2個。長すぎる追跡は持ち場へ戻る。
- 進行は番人を倒す→鍵箱をEで開く→ボス領域で開始。時間・撃破数だけで解放されない。実死亡通知で箱を解放。ボス開始で他室の敵を消さない。M探索図は発見済み範囲のみ、M/Escで閉じる。
- 移動経路3タイルと目的物周辺を装飾禁止にし、壁面ランドマーク／水晶／収納の衝突を維持。120seedで全床と3×3経路、実3MAPで半径20の実衝突経路・鍵箱・帰還・ボス開始・MAP切替を確認。OpenGL実描画はScriptエラーなし。確認終了時の既存ObjectDB/resource警告は残る。
- artifacts/exploration_map1〜3.png、exploration_guardian1〜3.png、exploration_discovery.pngは実描画。exploration_routes.pngはseed=913000の実地形から作図。ローカルDashboard同期、公開デプロイなし。
- 次は敵編成の役割差→装備の属性/強度と武器制限→有限遭遇のEXP/報酬→NPCなどの発見→帰還後の使い道→別の接続テンプレート。装備200種の全面再設計は未実装。


## 2026-09-15 60層探索・経済・回避・景観（現行値）

- MAP1/2/3のテーマを各20層、通算60層にする。各層の役割付き地形、部屋の形、反転、分岐は乱数で再生成。部屋数はテーマ基準13/15/17から最大17へ段階拡張。最深部の鍵の番人を倒して鍵箱を開き、各層のボスを解放する。最終ボスは60層目だけ。
- 通常敵は部屋別の有限遭遇。通算深度で広い戦闘部屋に最大2体ずつ増援を追加し、狭い宝箱部屋では増やさない。敵HPはテーマ基準0.9/1.2/1.6に`1+0.028×(深度-1)`、攻撃は基準0.6/0.8/1.0に`1+0.02×(深度-1)`を掛ける。ボスHPは基準0.8/1.2/1.7に`1+0.035×(深度-1)`、攻撃は基準0.5/0.65/0.8に`1+0.02×(深度-1)`を掛ける。テーマ境界でも難度が低下しない。
- ボス死亡地点の宝箱と確定床装備を離して配置。宝箱を開けても移動しない。別位置の階段は宝箱開封後に使える。装備を拾い、階段をE/Xで調べるとショップ、閉店後に次の層を生成する。60層では階段からRUN CLEARへ。
- 少数撃破に合わせ通常敵は初期2G、層ごとに段階加算。精鋭部屋18G、ボスはテーマごと50/65/80Gに層番号ぶん+2G。ショップ初期は回復40/55G、強化60G、武器165G前後から。価格とリロール初期25Gは通算深度で+3.5%/層。強化・武器は同じ商品を1Runで一度だけ購入でき、回復は再購入可。旧3MAP移動時の自動25%回復は60層の階段移動ごとに8%へ抑え、宝箱/ショップ回復の価値を維持する。60層の自然プレイ収支は今後評価する。
- 合成は緑→青→紫→橙→赤の全段階で同レア装備3個。成功率95/90/85/80%、失敗時の素材損失1/1/2/2個は維持。鍛造画面の素材数・表示も同期。
- J斬撃中・騎士のJ突進中・L居合中でもK回避へ移れる。中断したモーションの後続命中・非同期移動・騎士の2段目を止める。MAP切替等の攻撃以外の移動ロックは解除しない。敵通常攻撃または強敵固有技の実着弾フレーム直前0.12秒以内、射程内でKを押すと世界を0.65秒の実時間だけ0.35倍速にし、Jの次の一撃を1.35倍にする。反撃受付はスロー後も1秒続く。死亡・新Runでは時刻を1倍へ戻す。剣士L居合は倍率4.8→2.0、距離280→190、幅38→26、クールダウン6→9秒。乱撃/一閃派の連射間隔も延長。
- 装備は既存ドラッグに加え、所持品ダブルクリックで装着／解除。鍛造中は拒否。炉の炎、冷却水車の落水と水面は原画の切り出し領域だけを時間変化させ、壁面配置と足元Collisionを保持する。
- `floor_run_check`は45シードの地形到達性、1→2/20→21/40→41/60→クリアの実経路、境界での敵数・HP非低下、宝箱・階段・ショップを確認。`dodge_counter_inventory_check`は遅延命中なし・ヒットストップとの重畳・強敵技の予告窓と実命中・時刻復帰・反撃・装備ダブルクリック、`contact_drag_check`は既存ドラッグ実入力を確認。炉と水はOpenGLで2フレームを撮り、変化領域を原画位置へ合わせた。全60層の長時間通しプレイと購買体感は未評価。

## 2026-09-21 敵階級とMAP別Roster

- 敵の階級は`雑魚 → 標準 → 強敵 → 精鋭 → 中ボス → ボス`の6段階とする。通常敵23種は雑魚・標準・強敵のいずれかを基礎階級とする。精鋭は強敵を基礎個体にAffixを付与したもの、中ボスとボスはBossSpawnerの専用BossDataとする。
- MAP1（王国・不死）は、雑魚=`slime / bat / fast_enemy`、標準=`basic_enemy / shield_guard / skeleton_archer`、強敵=`armored_skeleton / greatsword_skeleton`。
- MAP2（血晶・魔性）は、雑魚=`eyeball_monster`、標準=`blood_monster_a / ghostfire / demoness_a / werewolf`、強敵=`blood_monster_b / werebear`。
- MAP3（溶鉱炉・オーク）は、雑魚=`lava_slime / hellbat`、標準=`demoness_b / hellhound / orc_rider / warlock`、強敵=`armored_orc / elite_orc`。
- 部屋役割は入口・宝箱=`雑魚`、通常警備=`雑魚+標準`、前室=`標準+強敵`、鍵番=`強敵+標準`、精鋭部屋=`強敵+Affix`。同階級内は部屋番号と各MAP内の層番号で循環し、20層内に担当する全種を出現可能にする。有限遭遇数と深度増援数は従来値を維持する。
- 現状で実挙動が重複する組は、`slime/lava_slime`、`bat/hellbat`、`fast_enemy/eyeball_monster`、`basic_enemy/blood_monster_a`、`werewolf/hellhound`。今回は削除せずMAP別の外見差として残す。弓兵・魔法系を含む専用行動が未実装の敵は、見た目だけで役割を完了扱いにしない。
- `tests/enemy_assignment_check.tscn`で23種の重複なし配属、各MAPの基礎3階級、EnemyData実在、20層内の全種到達、6階級順を検証する。

### 2026-09-16 宝箱・盾兵・短い発光素材

- 通常/ボス宝箱は新規入手した5列×6行の32px素材を使用する。通常は上段、ボスは下段の閉/開ペアを選び、レアリティで列を切り替える。E/X操作、足元Collision、報酬の一回限りの付与は変更しない。
- 盾兵(`shield_guard`)はMAP1・2の一部警備部屋の標準敵。HP86、移動48、接触ではなく予備動作後の近接攻撃5、EXP2。被ダメージを20%軽減し、被弾時に盾防御アニメを見せる。既存の敵1体との置換なので有限遭遇の総数は増やさない。
- Holy VFX 01/02は属性システムへ接続せず、ジャスト回避成功とボス宝箱の開封に使う短い装飾演出。現在のジャスト回避の時間制御や反撃倍率は変更しない。
- 新地形セットはMAP2・3の石材と色味だけでなく陰影と描線の密度が異なり、色替えだけでは自然に混ざらないため導入を保留する。既存の地形、当たり判定、生成ルールを維持する。

### 2026-09-16 ジャスト回避J反撃と剣士の表示
- 攻撃予兆の命中直前0.12秒にKを押すとジャスト回避。成功時に1.5秒のJ受付窓を設ける。成功だけでは自動復帰せず、最初のJで敵の左右側面の近い方へ最大0.14秒・壁/敵衝突を守って移動し、影を残してJ攻撃を開始する。敵が死亡・遠方なら移動せずJを開始する。
- J開始後1秒間の近接攻撃間隔は0.82倍、最初の命中は既存の1.35倍。Lのクールダウンは変更しない。ジャスト回避の全体スローは撤去し、通常の命中ヒットストップだけ既存経路で維持する。
- 剣士の上下向き専用素材は作画の違和感により撤回。待機・歩行・斬撃は元の横向き原画を使用し、J反撃時の位置復帰と命中判定は維持する。
- MAP1の柱フィールドの青い球体と細い台座は撤去。2×2の通行不能な障害物は、同じ石壁材のタイルとして描画する。


## 2026-09-22 予兆と反撃機会の統一・旧モード撤去
- JEV推奨実装順2。強敵6種の赤い目（血の敵は口元）を0.12秒→0.40秒、寸法1.6倍へ。最初の0.28秒は明るさを維持。二連斬り二発目にも予告を表示。構え・振り抜き・既存命中時刻は維持。
- 強敵の床予兆は実判定と同じ射線幅／扇角／半径、攻撃方向は構え開始時に固定。精鋭の周期能力は一度に1つ、最低0.75秒の予告＋発動＋0.45秒の回復待ち。強敵固有技と重複させない。未発見・帰還中・死亡後の能力を止める。
- 既存中Boss/Bossの突進は1秒の直線、叩きつけは0.9秒の円、Novaは0.85秒の放射、召喚は0.75秒の紫の円で予告。攻撃後の硬直1.25〜1.5秒を維持し、通常攻撃を差し込ませない。死亡時は予告と遅延命中を破棄。Minotaur専用4攻撃の予兆同期は維持。
- 旧ROOMのController／Select／Factory／データ／専用テスト、LabのROOMタブ・操作、HD-2D専用Scene／Script／Shader／素材／生成ツール／テストを削除。共有Minotaur斬撃素材は通常2D本編に必要なため保持。過去章のROOM／HD-2D記述は履歴であり現行機能ではない。
- 検証：強敵6種の実描画・命中回数・回避・中断・死亡取消、精鋭直列化、Boss警告と反撃猶予を確認。通常タイトル→MAP1、Lab（保存無効）、45seedと階段1→2／20→21／40→41／60→Clear、Kキャンセル・J反撃・装備操作を確認。
- Dashboardの図鑑・判断・進捗と強敵6種のMP4をローカル更新。公開デプロイは未実施。次の大項目は装備属性・強度の再設計で、今回数値変更はしていない。


## 2026-09-22 ボス領域：紋章・壁内装備・地下4層の進行停止
- BossSpawnerの候補3体の一巡後に空文字を返していた箇所を修正。候補プールだけ履歴をリセットし、候補が複数なら直前の連続出現も避ける。空候補／候補1体にも対応。鍵条件は維持。生成に失敗した場合は同じ場所でEを押し直せるようMapLandmarkを再登録する。
- ボス床紋章を暗い青灰寄りの乗算色・不透明度28%へ。待機中だけ表示し、戦闘中と撃破後は消す。生成失敗時は再表示、次層生成時は待機表示へ戻す。
- ボス死亡時の装備に使っていた右160px固定オフセットと壁座標へのfallbackを撤去。宝箱／階段生成後に配置を決める。部屋内の3×3床余裕＋半径20pxの実衝突を確認し、ボス宝箱／階段から112px、他の装備から原則56px離す。通常の開封済み宝箱は48px、未開封は96px離す。安全な床が一杯の場合だけ装備同士は同じ床を共有する。
- Boss宝箱を壁から余裕のある床へ寄せる。宝箱の装備報酬は遠い部屋角ではなく、箱に近い分離位置を選ぶ。抽選率・レアリティ・装備数・合成・敵能力値は変更していない。
- boss_room_regression_check：3テーマ各20回の実Boss生成、地下4層で通常敵を死亡させ鍵を開封→領域で開始、生成失敗→その場再試行、壁際での死亡ドロップの実E回収、宝箱報酬の衝突・間隔を確認。floor_run_check：45seed／1→2、20→21、40→41、60→Clearが成功。script_load_check：185件成功。
- 実描画はartifacts/boss_room_fixed_before.png／fight.png／loot.png。DashboardのBug・進捗・仕様・判断・実画面をローカル同期、公開デプロイ未実施。描画キャッシュの保存権限／証明書ストア警告は環境由来で、実行中のScript/Physicsエラーなし。

## 2026-09-23 大群・自動攻撃と広いダンジョンへの復帰（現行）

この節は過去の少数有限遭遇・J必須・番人の鍵の記述に優先する。

- 通常攻撃は全6職業で自動。射程内かつ壁で遮られない敵へ攻撃開始時に旋回し、命中コマごとの判定を維持する。攻撃中も移動できる（騎士の固有突進などを除く）。WASD/矢印で移動、Kで回避・攻撃キャンセル、Lで職業技、ジャスト回避後のJ反撃、C/T/Eは維持。Jで任意の空振りも可能だが通常攻撃に押下は不要。
- 旧DungeonGeneratorのランダム矩形・連結通路・追加接続を本編へ再接続。テーマ別100/108/116四方、部屋候補8/9/10、部屋18〜26セル・ボス部屋26セル。通路幅パラメータ8（実際に彫る幅は9セル）。柱密集・中央狭窄を本編で使わず、通路・部屋の中央5セルの十字レーンを固体装飾から予約。壁面素材・ランドマーク・装飾の衝突は維持。3テーマ各20層、各層再生成・各層ボス・階段・ショップを維持。
- 有限の部屋別配置・視認開始・持ち場帰還・鍵箱の導線を本編から外す。通常波はプレイヤーへ常時追跡。最初から3〜5体/1.15秒、45秒で4〜6体/0.95秒、90秒で5〜8体/0.8秒、150秒で7〜10体/0.65秒へ。間隔は線形補間。各テーマ基準cap64/80/96に通算深度の0.7倍を加算、上限128。遠方1200px超の通常波だけを無報酬で整理し補充する。
- 0〜20秒は雑魚のみ、20秒以降は標準敵を30%混ぜ、60秒以降は雑魚70%/標準22%/強敵8%。各MAP専属Rosterを使用。巡回精鋭は90〜105秒後から、以降60〜90秒。各MAP専属強敵へAffix1/1/2個と深度HP/攻撃補正を付与。通常capに従う。敵同士・主人公との本体衝突、ノックバック、局所Hitstop、強敵予告・精鋭直列化は維持。
- 出現は220〜480pxの近傍に限定。3×3床余裕に加え半径26pxの実物理判定で壁・固体装飾・既存Enemy本体を検査。安全地点がなければ次の波で再試行する。壁内や遠い別室へ無理に生成しない。
- ボス解放はテーマ基準120/160/200体＋テーマ内の層ごとに3体。240/270/300秒の時間救済も有効。鍵と全滅は不要。40%/80%の撃破、または75/150秒で40秒の侵攻を開始し、間隔0.8倍・同時数1.25倍、報酬は回復→装備。ボス開始時は通常波を整理して追加湧きを停止。撃破後〜宝箱・装備回収〜階段でも停止し、次層で再開。
- 通常敵HP基準倍率0.38/0.50/0.65、攻撃0.70/0.85/1.0。従来の通算深度HP+2.8%/攻撃+2.0%を乗算。Player基礎火力、装備個体の能力、Boss能力・深度補正は維持。
- EXP必要量は従来曲線の2倍（初回30、Lv10まで段階+10）。通常敵4体で1G。Elite加算10G、侵攻完了20G、Boss基準50/65/80G＋テーマ内層ごと2Gを維持。ショップ初回強化60G、回復40/55G、リロール25Gと段階価格・同一商品一回制限を維持。通常装備抽選0.6%、Eliteは確定。高レア抽選と3個合成を維持。通常ハート0.8%、Elite4%、回復6%、寿命15秒、地面上限3個。
- 普通の敵のHPバーは被弾後のみ、幅24px。強敵・精鋭は幅32pxで常時表示、Bossは専用HUD。M地図は全体の通路・現在地・ボス位置・現時点の目的を表示。操作説明とBoss戦/報酬回収中の目的HUDを同期。
- 自動検証: 実game.tscnの起動経路、6職の実Sprite/自動命中、自然増援・cap・安全出現・K取消・メニュー停止、敵4体1G、EXP/回復設定、時間/撃破解放、Boss戦と回収時の停止、テーマ境界。30seedの幅・全床/3×3経路、別途45seedと階段1→2/20→21/40→41/60→clear、Boss60回抽選と壁際報酬を確認。全60層の人による遊び心地と職業ごとの難度比較は未完了。

## 2026-09-24 区画選択とスマホ横画面（旧仕様：行き先選択を撤去）

この節は2026-09-23の「常時追跡・継続湧き・撃破数/時間でボス解放」に優先する。広いランダム広間、3テーマ×20層、各層のボス・宝箱・階段・ショップと職業の自動攻撃は維持する。

- 各層を4戦闘区画の有限Waveに分ける。1区画目は雑魚編成、制圧後は2.5秒の安全時間を置き、回復区画（HP25%）、装備区画（装備箱と戦技）、強敵区画（増量・高火力の敵と希少装備）から次を選ぶ。4区画目制圧後、ボス領域を選択してボスに進む。区画中は自然増援と時間巡回精鋭を止め、区画の制圧判定に残敵を含める。
- 1区画目11体を基準に深度と区画番号で敵数を増やす。敵HP/攻撃の既存深度倍率を継承し、強敵区画は追加倍率1.18。スマホの同時敵数上限は28、PCは42。出現地点は選択した部屋の歩行可能な床・実衝突・主人公との距離を確認する。
- 自動攻撃を実行する既存職業武器と、装備中の武器アイコンを主人公の近くに浮遊表示する。射撃は浮遊位置から発射し、攻撃時に武器が短く動く。この時点では装備武器は能力値と表示のみ。2026-10-01に後述の独立した装備自動攻撃へ更新。
- 装備区画で得る戦技は近接の斬幅/追撃、遠隔の貫通/連鎖/追撃を段階強化する。5層ごとにゴールドとHP回復を与え、最深踏破層を保存する。階段前のボス報酬とショップは従来の進行を維持する。
- スマホは横画面で、左に仮想スティック、右に回避・技・反撃・拾う・装備、上に地図・停止を置く。分岐は画面中央の大きなタッチ選択肢で危険度と報酬を示す。装備詳細/鍛造はタッチ時に画面中央へ置き、閉じる・装備/解除の直接ボタンを表示する。メニュー中は戦闘ボタンを隠す。Android/iOS実機の安全領域・発熱・長時間操作は正式リリース前に検証する。

## 2026-09-24 部屋ごとの殲滅と宝箱を確認して進む方式（MAP2/3・共通進行）

- 2026-09-27：MAP1の地形生成と読み込みは後述の個別部屋方式へ変更。以下の面積・連結通路はMAP2/3に適用。殲滅・宝箱・手動退出・ボス後の回収は共通仕様として維持する。

- 3テーマ×各20層、職業の自動攻撃、各層ボス・階段・ショップを維持。生成面積はMAP1/2/3それぞれ92×92、96×96、104×104セル。各階の部屋生成目標は5。通常広間16〜23セル、ボス部屋26セル、通路実幅7セル。全室を生成できない場合も実在する部屋から進行数を決め、少なくとも3戦闘室の後にボス室へ進む。
- 各室の敵は有限Wave。生存敵と未出現の残数がともに0になるまで出口を封鎖する。部屋の通路開口には見える封印と実衝突を置き、横道から次室へ抜けられない。全滅後も自動選択画面や時間制限は出ない。E/Xで出口を調べて初めて次室へ移る。
- 戦闘室の約半数には宝箱をランダム配置し、残りは宝箱なし。同じ階に両方の部屋を含める。宝箱は全滅後に開封可能で、宝箱のある部屋の出口は開封まで開かない。通常宝箱の装備と戦技は開封時に付与。ボス撃破後は宝箱を開けても階層移動せず、装備を回収して別位置の階段をE/Xで調べた時だけ次層へ進む。
- スマホ横画面の仮想スティックと操作ボタン、装備詳細/鍛造の画面内配置は維持。中央の行き先選択画面は削除。敵HP/攻撃や武器の能力値は今回変更しない。Android/iOS実機の安全領域・発熱・長時間操作は今後確認する。

## 2026-09-25 NEW素材の戦闘・音・小物（現行追記）

- 魔導士の自動追尾弾は`Pixel_Magic_Effects_Animations.png`の紫渦5コマを12fpsで繰り返し、汎用の矢絵を隠す。追尾・判定・状態異常の処理はそのまま使う。
- `AudioManager`の既存SE読み込みへ魔導士詠唱、近接素振り、敵への命中、宝箱開封、装備取得、ハート取得、部屋扉の7音を追加。命中音は80msの重複制限で密集戦中の過剰再生を防ぐ。
- `Objects.png`と同梱の個別画像から岩・骨・廃墟の6種類を選び、通常室の端寄りに最大2個ずつ配置する。MAPごとの床色に合わせて調色し、岩・廃墟は足元に物理衝突を持つ。戦闘通路・予約地点・既存装飾の重なりを避ける。ボス室には配置しない。
- 実ゲームで3MAPの配置・衝突・部屋進行、魔導士弾表示、音声IDを確認。OpenGL 1280×720の描画も確認した。端末実機での音量と長時間性能は今後確認する。

## 2026-09-27 MAP1の個別部屋読み込みと従来石床（現行）

- MAP1の20層は、入口の広間・崩れた回廊・石柱の広間・強敵の前室・ボスの祭室の5室構成。通常室22/24×16、ボス室24×18セルで、同時に存在する地形は1室だけ。室幅と障害物の左右をseedで変え、敵・小物・宝箱位置も抽選する。中央5セルの導線と、3×3移動余裕のある床の連結を確保する。MAP2/3は既存の連結広間を継続する。
- ユーザー指定でMAP1の床は従来のRoyal石床へ復元。既存の立体壁・松明と岩/骨/廃墟を合わせる。新地形セットは新MAP専用の候補素材として保管し、既存3MAPの床へ適用しない。壁・柱・固体小物の衝突、入口・出口・中央レーンの予約は維持。
- 全滅と宝箱開封が退出条件。4戦闘室中2室に宝箱を抽選配置。時間で選択画面を出さず、E/Xまたはスマホの操作ボタンで扉を調べると次室を読み込む。未回収の装備は次室の入口付近の通行余裕と実衝突を確認した床へ引き継ぎ、切替で消さない。主人公の装備・HP・成長は室間で継続し、室移動だけで回復しない。
- MAP1の同時敵数は16まで。室番号・深度によるWave総数と敵能力倍率、全職自動攻撃、浮遊武器、回避/反撃を継承。4室後にボス室を読み込み、領域の操作で戦闘開始。ボス宝箱・装備・階段・ショップ・次層の既存順序は維持する。
- 個別部屋はカメラ1.15倍。HUDはMAP1/3と地下層・室番号/役割・未出現を含む残敵を表示し、M地図も現在の部屋を表示。生成範囲と残敵処理は室切替時に更新する。
- 公式GunzTowerの公開説明と画像から戦闘/回収の区切りと空間の役割を学び、独自の室テンプレートに落とし込んだ。相手の正確な生成コードや寸法の複製とは扱わない。調査・判断・未実施項目はdocs/gunztower_room_design.md。300生成室、実ゲームの退出/装備引継ぎ/ボス/テーマ切替と60層境界を検証。Android/iOS実機と自然プレイの難度は未評価。


## 2026-09-27 現行キャラクターに合わせたMAP2/3床・壁の再生成

- MAP1のRoyal石床は現行キャラと整合するため維持。MAP2/3は写真状の石肌と線形補間がキャラのドット密度と異なったため、ローカルComfyUI（SDXL + pixel-art-xl）で床・壁正面・岩盤を個別に再生成。
- `pixel_materials_v2.png`は272×272、各象限136×136の内側128×128を8×8セルへ分割。16pxの素材を32pxセルへNearestで2倍表示。MAP2の`pixel_masonry_wall_v2.png`は128×128。各生成面は20色以内。
- `detailed_map_surfaces.gd`が新素材を参照。旧原画は保持。紫灰の鉱山と茶灰の炉心のテーマ、部屋生成・当たり判定・敵配置は維持。
- Soldier/Swordsman/Wizardの現行Idleを1.65倍で並べる`tools/map_style_capture.tscn`で比較。これは製品のStageEnvironmentを使う作画比較用Sceneで、実プレイの操作確認とは区別する。
- MAP_THEME_CHECKで3MAPの素材参照・到達性・壁と障害物の衝突、新PNG寸法とNearestを検証。ランドマークや小物の全面再作画は今回の変更に含めない。

## 2026-09-27 3MAPオブジェクトとゲームUIの精査・修正

- MAP2/3の小物4種ずつ、景観4種、作業員4姿勢、岩・骨・廃墟6種、封鎖/開放扉と階段を2倍Nearestへ統一。配置は全小物の外形、衝突は表示フレームの外形を使う。松明のアニメーションを復元。
- 装備200点の24px版は後続の可読性修正で48px版へ置き換え。共通枠を整数倍率へ更新。HUD・装備・天賦図の小文字、装備数値の切れ、地図の古い目的表示、操作案内、タッチの「調べる」とモーダル後のスティック状態を修正。
- 炉・水車はAtlasの解像度依存を撤去し、色の二重乗算も修正。時間による画素変化と静止部分の原色保持を実描画で検査。
- 3テーマの描画/到達性/衝突、景観60seed、実ゲームの宝箱/手動退出/ボス/MAP2・3/タッチ入力、1600×900装備画面、天賦/報酬/タイトルの文字とキーボード操作、炉/水車の色・アニメーションを確認。
- 旧secondary UI検査は廃止済みのスクロール天賦タブを参照していたため現行の天賦図へ更新。タイトルの説明は実画面範囲で検査する。
- 旧shop_runtime_checkは改定前の武器450〜550G/リロール100G等を要求し失敗。forge_balance_checkは鍛造全段階の検査後、現行ハート上限3個に対する旧5個固定assertで失敗。chest_strikes_checkは従来の「歩行で敵を押さない」のassertで失敗。これら全体を成功扱いせず、宝箱・UI・進行は専用実経路で確認。敵やショップの能力/価格は今回変更しない。
- 元素材と変更前バックアップを保持。Dashboardはローカル同期。Android/iOS実機、長時間の自然プレイ、公開デプロイは未実施。

## 2026-09-27 壁内の門・入場動作・装備アイコン再生成（現行）
- 3MAPの部屋出口を北壁の開口へ接続。中央へ歩く→門の内側へ入る→次室へ遷移。枠を主人公の手前へ描き、封鎖・宝箱条件を維持。MAP1カメラは上側に64pxの余白を確保。
- 装備200点を48px・透過ドット絵へ再生成。剣・弓・鎌・斧槍・兜・冠・鎧・手袋・ブーツ・装飾の輪郭を優先し、所持品・詳細・鍛冶・床Drop・浮遊装備へ接続。無料ローカルComfyUIで既存の明瞭な形を参照して再描画。 種類別の形を共有する色違いを含む。生成参照とAPI Workflowはtools/source_art/readable_iconsへ保存。
- 3MAPの門・入場・遷移後の操作復帰、200実画像の読み込み、1600×900装備配置、部屋進行/タッチ操作を確認。Android/iOS実機は未確認。 通常敵/ボス/報酬/装備の能力値は変更しない。

### 同日追修正：門の壁面統合（現行）
- 3MAP共通の青緑ポータルと台座を撤去。既存の壁面と石積みを保持し、各MAPの石材・床素材で掘り込み、敷居、暗い奥行き、閉じた鉄格子を描画。門だけ別の石板に見える外周をなくした。中央入場と遷移条件は維持。
- 壁のTextureを消す方式を廃止。入口セルは非衝突Alternativeへ切り替え、MAP2/3の壁面上書き描画も保持。描画は既存素材を使うGodot Canvas。前景の狭い石縁が主人公を覆い、入場後に遷移。操作Promptは入口の下。
- gate_entry_checkで3MAPの非衝突壁面、中央入場、前景/遷移/操作復帰を確認。sector-mobile-checkの既存進行回帰成功。

## 2026-10-01 浮遊装備武器の実攻撃（現行）

- 装備52武器の`attack_kind`を明記。軽刃・斬撃・重斬・刺突・弓・魔法の6系統を`equipment_auto_attack.gd`から実行する。職業の通常攻撃とL技は維持する。
- 主人公中心の円内を全方向に索敵。最寄りの生存敵で壁越しでないものを選ぶ。半径は軽刃96/斬撃112/重斬124/刺突140/弓232/魔法216px。既存の射程強化を反映し、同じ半径を薄い円で表示する。
- 剣はSprite本体が敵へ飛び、接触時に局所の斬撃判定を出し、元の位置へ戻る。弾は発射しない。短剣は素早く狭い斬撃、大剣は長めの飛行・広い斬り幅、槍・刺剣は突き。主人公の位置は動かさない。飛行中に対象が射程外へ出る・死ぬ・壁に隠れると攻撃を中止する。
- 弓/杖は浮遊位置から矢/魔法弾を発射。弾も主人公中心の範囲外と壁で消え、壁越しや範囲外の敵へ命中しない。職業固有の魔法や矢は装備剣を発射元に使わない。
- 基本間隔は軽刃0.72/斬撃0.95/重斬1.25/刺突1.05/弓1.00/魔法1.15秒。装備攻撃速度・射程・会心など既存強化を反映。基礎ダメージ3＋既存の加算/倍率計算。装備交換で残りクールダウンを消さない。解除・回避・メニュー・死亡時の発動を停止する。
- ComfyUI（SDXL＋pixel-art-xl）で軽刃/斬撃/重斬/刺突/発射/魔法の6種を生成。ガイドでフレーム位置を固定し、64px×6コマの透過素材へ整形。原画像・API Workflow・入力ガイド・生成履歴は`tools/source_art/equipment_attacks`、採用素材は`assets/vfx/equipment_comfy`。
- レアリティは緑→青→紫→橙→赤の斬撃色。高レアほど残光が長く火花が多い。火花は装飾で、追加ヒットや無料の火力倍率は付けない。
- `tests/equipment_auto_attack_check.tscn`で実ゲーム経由の装備/攻撃、6系統のHP減少、剣の接近と非射撃、射程、壁、回避/メニュー、射程離脱、飛行中解除、360度、5レア度、解除後の職業攻撃を検査。既存sector-mobile-checkもPASS。実機と深層での長時間難度評価は未実施。

## 2026-10-04 ComfyUI武器素材24種（生成候補）

- 現行の48pxドット密度に合わせ、曲刀・細剣・波刃剣・三叉槍・大鎌・斧槍・双刃斧・戦棍・弓/弩・杖/王笏/魔導書・鉤爪など24種をローカルComfyUI（SDXL＋pixel-art-xl）で生成。形状ガイドには既存Shikashi素材と新たに作った輪郭を用いた。
- `assets/items/comfy_variety_24`に48×48透過PNGと候補manifest、`tools/source_art/weapon_variety_20261004`に768px原画、96px切り抜き、参照、API、seed、prompt_idを保存。24画像の重複・透過・外縁余白を検証し、濃色/淡色の背景で作画を確認する。
- 緑5/青5/紫5/橙5/赤4と9攻撃系統は採用候補。現行templatesは200種、武器は52種のまま。新素材はドロップ・合成・自動攻撃へ未追加。素材の完成とゲームへの実装を区別する。
- Dashboardのアイテム画面へ素材一覧を追加。次の段階は素材選定と能力予算を決めて実装する。

## 2026-10-04 武器ごとの自動攻撃の特色（現行）

52武器を9系統に分類。大剣は広い斬撃、細剣・槍は速く細い突き、弓は矢、斧は1.8秒間隔の重い一撃。鎚・棍と大鎌も専用モーション・ComfyUI素材へ接続。威力倍率は装備・成長を含む命中値へ適用。装備詳細へ特色・基準間隔・一撃倍率を表示。実ゲームの同能力比較、横の巻き込み、9系統の命中、壁・射程・解除・回避/メニュー、スマホ操作・4室進行を検証。

| 系統 | 基準間隔 | 一撃倍率 | 特色 |
|---|---:|---:|---|
| 短剣・爪 | 0.62秒 | ×0.72 | 小さく素早い連撃 |
| 片手剣 | 0.95秒 | ×1.00 | 扱いやすい斬撃 |
| 大剣 | 1.25秒 | ×1.20 | 幅広く敵を薙ぎ払う |
| 細剣・槍 | 0.78秒 | ×0.85 | 細い直線を素早く貫く |
| 斧 | 1.80秒 | ×2.00 | 間隔は長く、一撃が重い |
| 鎚・棍 | 2.10秒 | ×2.25 | 溜めて叩き、強く押し返す |
| 大鎌 | 1.38秒 | ×1.05 | 長い弧で広く刈り取る |
| 弓・弩 | 1.00秒 | ×0.90 | 遠くへ速い矢を放つ |
| 杖・魔導書 | 1.15秒 | ×1.10 | 魔法弾で遠距離を攻撃 |

- 52武器の内訳は片手剣9、短剣/爪3、大剣2、細剣/槍8、斧3、鎚/棍8、大鎌1、弓/弩9、魔法9。既存アイコンとレア度は維持。新規24種の生成候補はドロップへ未追加。
- 倍率は既存の装備・成長・会心を含むダメージ計算の結果へ適用。攻撃速度を反映した間隔にも動作全体の時間を下限として設け、空中の武器が動作途中で次の攻撃へ飛ばない。
- 斧・鎚/棍・大鎌の6コマ素材をComfyUIで生成して装備の接触へ同期。細剣は半幅7pxの直線、大剣は半角82度・接触半径52px。主人公の索敵円と壁で全ての命中を制限。弓は390px/sの矢、魔法は280px/sの魔法弾。
- 装備詳細は武器の特色・基準間隔・一撃倍率を先頭表示。Projectileの装備用Sceneは発射時に読み込み、通常起動時の循環preloadを解消。
- equipment_auto_attack_checkは9系統の実命中・解除・壁・円・回避/メニューと、同能力での威力/間隔比較、横の敵を巻く大剣と巻かない細剣をPASS。実測は細剣11.05/47F、大剣15.6/75F、斧26/109F、鎚29.25/127F（60Hz、装備攻撃力10、会心なし）。sector_mobile_runtime_checkもタッチ操作、4室、宝箱待ち、手動退出、ボス、MAP2/3をPASS。9種の実ゲームGIFと詳細画面を保存。深層の長時間難度・実機評価は未実施。


## 2026-10-04：Embervilleを参考にした全体ビジュアル刷新

本節の見た目が旧48px装備・紺金の厚い枠・常設の本背景・旧床画像を置き換える。今回のユーザー指示はゲーム全体の刷新であり、Ponytailは使用しない。既存キャラクターの元絵、200装備の能力値、9武器の自動攻撃系統、3テーマ×20層、部屋・Wave・手動退出の進行は維持する。

- ローカルComfyUI（SDXL base＋pixel-art-xl、img2img）で241生成を完了。平坦な床の試作3枚は採用せずv2へ、部位が分かりづらい帽子・胸当て等18点は再生成。238出力を素材元として採用し、実装中の装備画像は200点。API JSON、guide、seed、prompt_id、原画を`tools/source_art/ember_v5/`へ保管。
- 実装画像は`assets/visuals/ember_v5/`。装備200点は64×64、Nearest、二値Alpha、余白と表示Boundsを検証。所持品・詳細・地面Drop・浮遊武器へ同一画像を接続。レア度は緑/青/紫/橙/赤の1px輪郭。GPUからの毎回画像読取は避け、全画像のBoundsを`EquipmentIconMetrics`へ登録。
- UIは暗いプラム/石灰色、抑えた金属色、青緑の選択色。ComfyUI製96×64の枠を3px nine-sliceで全メニューへ共有。大きな金の紋章を撤去。HPは連続ProgressBar。深度表示は60層で統一。装備取得通知は短い一つのToastにまとめ、Room目的に重ねない。
- 装備は2パネル・小型7列/50枠。PCホバーは薄い半透明の比較カード、タッチでは中央の詳細カード。ドラッグとダブルクリックの着脱を維持。鍛造はScrollContainerで合成ボタンまで収め、完了後も鍛造に留まる。
- 天賦図の本は2026-10-05のユーザー指示に従い、大きな見開きを保持する仕様へ更新（下節）。演出後に本を消して別の2パネルへ切り替える方式を撤回。
- 3テーマの床/壁は128×128・低色数のComfyUI素材を実描画へ接続。床セル・壁衝突・通行導線は変更しない。景観4種のAtlas位置とAlphaは従来の位置を維持して炎/水/作業員の動きを継承。MAP2/3の4種小物は既存24pxフレームの外形へ合わせ、サイズ拡張で配置がすべて拒否されることを防ぐ。岩・骨・廃墟とキャラは元の素材を継承。
- タイトル・職業選択背景、HUD、レベルアップ三択、ショップ、装備/比較/鍛造、天賦図に実ゲームの画面を保存。Dashboardも同じ細い枠・最新200画像・本の実動画へ同期。

検証：`ember_visual_polish_check`はPC1600×900／横画面1280×720タッチプレビューの両方でfailures=0、200実画像、ダブルクリック着脱、2回の実鍛造、Popup範囲、天賦図の順序/中断/再開、Modal解除、MAP2/3遷移を確認。`equipment_auto_attack_check`は9系統/52武器/壁/射程/解除/回避でfailures=0。`map_theme_check`は3テーマの到達性・衝突と小物生成、`landmark_check`は60seed、`landmark_flow_capture`は炎と水の実描画変化がPASS。部屋進行とタッチ入力は`sector_mobile_runtime_check`がPASS。

全Godot検証に`--audio-driver Dummy`と`-- --mute-audio`を付ける。保存音量は変えない。PC/スマホ幅Dashboardは画像と横はみ出しを確認。Android/iOS実機、深層の長時間難度は未評価。Windowsのルート証明書・Shader cache書込み警告は検証環境由来。既知の旧固定値Test不一致は別件として維持。


## 2026-10-05：本の見開きと天賦図の統合

「本を大きくし、開いた2ページへ天賦図と刻印の記録を載せる」という指示を現行仕様とする。
旧「本を消して背景なし天賦図へ」は履歴。今回は天賦図の表示と操作、その関連記録のみを変更し、戦闘・装備・MAP・天賦取得の効果は変更しない。

- `BookArt`を基準1600×900の画面内に1200×720で配置。紙面の合計幅は1155px、高さ675px。画面幅の約72%を使い、Viewportに合わせて一様に縮尺を合わせる。
- 背表紙を固定し、表紙と3枚の紙を右から左へ連続描画。ComfyUI製`book_motion_v2/cover.png`と`paper.png`を継続使用。紙の持ち上がりを大判に合わせ、途中の紙も画面内へ収める。
- 登場0.16秒、表紙/紙めくり1.48秒。表紙0.62秒、紙は0.64／0.79／0.94秒から0.28／0.28／0.44秒でめくる。最後の紙の裏に天賦図、下の右ページに記録を描画し、紙が動くことで内容が見える。後出しの文字フェードと静止待ちを撤去。開いた本は残す。
- 左ページに起点・2流派・各4段階の天賦、右ページに職業肖像、流派、熟練、選択した天賦の効果・習得条件。旧2枚の暗い大枠を撤去し、紙に合う濃いインク、茶色の接続線、青緑の選択を使用。
- 本の絵は入力を通す層に置き、天賦のボタンはその上で操作する。全9ノードのクリック、矢印Focus、途中閉じる/再開、閉じた後のPause解除を維持。
- `talent_book_pages_check`は実ゲームでPC1600×900／横画面1280×720の両方がfailures=0。左右の内容と表紙の軌道が画面内に収まることを検査。`ember_visual_polish_check`の装備200点・着脱・2回鍛造・MAP遷移も新しい本と合わせてPASS。すべてDummy audio＋mute。スマホ実機は未検証。
- 最新CaptureとGIFは`artifacts/talent_book_pages_v3/`。Dashboardの天賦画面、進捗、Bug、Decisionを同じ見開きへ更新。


## 2026-10-05：文字も紙と一緒にめくる

- Scope：天賦図の紙めくり・内容の投影・操作への接続と関連Dashboard。Out of Scope：天賦取得／効果、戦闘、装備、MAP。
- `talent_grimoire.gd`は同じ実操作Controlを開く間だけ1600×900の透明SubViewportへ移す。紙面の領域を使って右記録と左天賦図を描画。複製や固定スクリーンショットではなく、選択状態・職業・熟練・条件がそのまま反映される。
- `book_opening_art.gd`の最後の紙の裏面へ36分割の同じ曲面座標で文字を投影。背表紙が左ページの右端になるUVを使い、文字を鏡像にしない。右の記録は最後の紙に覆われ、めくりに沿って見える。
- 着地したら同じControlを元の親へ戻す。Alphaは常時1。紙面はPC／横画面プレビューとも切替前後のキャプチャでピクセル差0。操作開始後のSubViewport更新を停止し、毎フレームのGPU画像読み戻しも行わない。
- `talent_book_ink_check`はPC1600×900と横画面1280×720でfailures=0。文字を載せたままの裏面が13フレーム描画されること、9ノードの入力・右ページBounds・中断3時点・再開・Pause解除を確認。`ember_visual_polish_check`も200画像・着脱・2回鍛造・本・MAP遷移がPASS。すべて無音。実機は別途。
- 最新実画面・GIF・ピクセル比較は`artifacts/talent_book_ink_v4/`、コード控えと手順は`tools/source_art/talent_book_ink_v4/`。Dashboard1.6.15の天賦へ同期。


## 2026-10-09：見えない壁と浮遊武器の仕上げ

- Scope：地形描画と当たり判定の一致、浮遊武器のサイズ・輪郭・オーラ・透過、その入力/攻撃経路と関連記録。Out of Scope：攻撃性能、進行、装備数値、保存データ、新規生成素材。
- `detailed_map_surfaces.gd`は通常の通行可能床と、目に見えるランドマークが覆う足元だけを床として扱う。石柱・短壁のterrain_obstacleセルを普通の床へ塗り潰さない。同じ関数を小部屋・同期生成・分割生成で使う。地形の衝突は削除しない。
- `floating_weapons.gd`は装備IDの現行Emberアイコンを優先し、既存Boundsで絵の長辺を48pxへ。画像全体の透明余白で武器が縮まらない。副武器がある場合は36px。待機中心は±38px、y=-9、帰還先と残像の中心を同じ位置へ合わせる。
- `weapon_aura.gdshader`は0.5未満のAlphaを描かず、シルエットへ1pxのレア度輪郭、輪郭の外へ揺らぐ炎を付ける。アンコモン→ミシックで強度0.30/0.42/0.54/0.66/0.78。緑・青・紫・橙・赤、ミシックの輪郭は#ff4659。周囲の四角や画像全体を光らせず、武器本来の色を保持する。形状の余白は頂点で10px拡張。追加ParticleやCPU画像再生成なし。
- `weapon_aura_walls_check`は実ゲームでPC1600×900/OpenGLと横画面1280×720/Vulkan Mobileがfailures=0。3テーマ12地形、11,237壁/21,535床の表示分類と衝突、実主人公の中央通行/石柱遮断、52武器の48px・二値Alpha、5レア度、旧参照、Alpha0.08の背景除去、原色保持、揺らぎと透明な四隅を確認。
- `equipment_auto_attack_check`で9攻撃系統・命中/間隔/射程/壁/装備解除/回避/モーダルの回帰がPASS。`map_theme_check`の3テーマ・小物衝突・ランドマークもPASS。音はすべてDummy+mute。Android/iOS実機と多数武器時の負荷は未検証。
- Capture/比較GIF/レポートは`artifacts/weapon_aura_walls/`。Dashboard1.6.16の戦闘・アイテム・MAP・進捗/Bug/Decisionへ同期。既存ComfyUIの絵を再利用。


## 2026-10-12 5分サバイバル（旧タイムクリア仕様）

3テーマから出撃先を選び、36×28セルの1アリーナで5分間生き残る。敵は時間帯で密度と階級が増え、浮遊武器が自動攻撃。120秒・240秒にボス（前のボスが生存中なら延期）。300秒で敵を退去させ、経験値は付与しない。終了後は時間制限なく宝箱・装備を回収し、階段を手動で調べて結果へ。

途中のボス宝箱を自分で開けると装備・戦技と補給ショップ。ショップと強化選択中は時間停止。残金は1G=1欠片、回収装備は1点=5欠片として、撃破数に加えて継承報酬へ反映。装備自体は従来どおりRun内専用。

- 36×28セル、外周込み44×36。PC80体／タッチ48体。ボス召喚も上限を確認。出現間隔・Batchはdata/difficulty/five_minute_survival.json。通常敵は最大HP+60%、攻撃+25%。
- Boss死亡からの宝箱生成は物理通知後に行う。待機中にBossが退去しても解放済み参照へアクセスしない。
- 回収中は時計が05:00で停止。残敵を消す際のEXP・ドロップなし。宝箱・装備・階段を離し、自動選択画面は表示しない。手動帰還後に結果。旧下降ショップは使わない。
- 保存済み解放・音量・最高記録を削除しない。Run装備を永続装備へ変更する範囲ではない。所持品・鍛造・天賦の既存導線は保持。
- 調査・適用・検査と限界：docs/crazy_gunner_survival.md。Android/iOS実機、無敵を使わない全職の難度比較、最終的な成長・価格調整は未検証。相手の内部数値を複製したとは扱わない。


## 2026-10-13 床のみの広い戦場と終盤Boss（現行進行）

3テーマ共通で、壁・柱・地形小物のない広い床へ。床とカメラが現在地へ追従し、表示基準96×96セルの外でも歩行・出現・回収が続く。約4分の大群戦の後、従来の強敵から1体を終盤ボスとして出す。撃破してクリア、5分を過ぎても生存ボスを消さない。

序盤3〜4体/1.0秒→終盤8〜10体/0.45秒。45秒から標準敵を混ぜ、150秒から45%。PC128体・タッチ96体。通常敵は序盤比で、終盤にHP約+72%、攻撃約+32%、EXP必要量は2.1倍。画面外の周囲から出現する。

75秒に60%の装備箱、150秒に確定の補給箱。補給箱を自分で開けるとショップ、閉じると戦闘へ。ボス撃破後は装備・討伐宝箱・帰還階段を離して配置し、開封しても自動帰還しない。残金・回収装備は従来どおり継承報酬へ。

- 96×96はデータの表示基準。床は現在地のカメラへ追従して描画。遠方でも歩行、AI、出現、装備回収が継続する。元の床素材・作画は維持。
- 通常4分＋Boss約1分を目指す。240秒後は増援停止、元の強敵6種をテーマごと2候補から1体生成。300秒の自動撤退・生存だけでの成功を撤去。時計とBoss HPを保ち、実撃破後にのみ回収へ。
- 6BossはData Loaderの特技IDを通常敵と共用し、元絵/アニメーション/予兆を保持。通常データは変更しない。実HP11700〜17550、倍率1.7。
- 無敵の検査キャラ・自動強化の通し例：全体約4分51秒、Boss約51秒。実機と全職の難度は別評価。調査・数値・検査の範囲はdocs/crazy_gunner_survival.md。


## 2026-10-13 成長と視覚的な強化（現行）

敵の歩行を35%減速し、主人公の通常歩行速度の75%以内へ。経験値倍率を2.1から0.6へ、初回必要EXPは32→9。5分の中で強化を試しやすくした。

大きなアイコン・現在→強化後の動く比較・選択チェック・独立した取得ボタン。タップだけでは取得せず、選択中は戦闘時間を止める。上限に達した強化と、使えない遠距離強化は候補に出さない。

広域攻撃・高速攻撃・残影追撃・雷光連鎖・再生結界・強撃・多重射撃・貫通射撃。旧数値/状態カードを現行レベルアップから外し、職業技と流派は維持。通常攻撃と浮遊装備の実命中・弾数・貫通へ接続。

PC/OpenGLとタッチ操作を含む横画面/Vulkanプレビューで6職を確認。連鎖/追撃の再帰防止、上限、連続レベルアップ、実シールド、装備の追加弾と実貫通も検査。スマホ実機と無敵なしの全職難度は未確認。

無敵・自動選択の通し例：初回17.4秒、Lv5は32.9秒、Lv10は68.6秒、終盤Lv25。全体293.0秒、Boss52.9秒。勝率の証明ではない。

- 共通6系統と、矢/魔法を使う職業か装備がある時の2系統。強撃を除き最大3段階（多重/貫通は2）。既存の職業強化と剣士の流派条件を保持。旧カードはShop/Labのためデータを保持。
- 追撃は0.18秒後・0.6秒に1回・元命中の30/35/40%。連鎖は近傍120px・0.7秒に1回・35%。副次イベントはis_direct=falseで再帰させず、射程と壁も確認。結界は8秒ごとに8×段階。
- 既存effect_paramsとPlayerUpgradesへ接続。ComfyUI slash_6fと既存アイコン・キャラクター/敵を再利用。攻撃の固有テンポと終盤Boss HPは維持。
- 公開資料は公式Google Play（https://play.google.com/store/apps/details?id=com.leguas.gunstorm&hl=ja）の「Choose Your Evolution」画像と説明。実アプリの全スキル値は確認できず、倍率と能力はVSGAME用に設計。
- artifacts/survival_growth/check.json・mobile/check.json・soak.json、tests/survival_growth_checkが実入力/実攻撃の根拠。tests/runtime_exit_cleanupは高速終了時も音声停止をMixerに渡してから終了。


## 2026-10-25 レベルアップ画面のブラッシュアップ（現行）

本節の見た目が、2026-10-13節のレベルアップ画面の表示部分と§35.4のLevelUpカード寸法を置き換える。2段階の取得（カードを選ぶ→取得ボタン）、選択中は戦闘時間を止めること、候補の抽選・重み・上限・付与効果は変えていない（`_open`〜`_get_current_school`は元と同一）。

### 画面の枠と配色を共通部品へ統一

- レベルアップだけが独自の平板な枠（1pxの`StyleBoxFlat`）だったため、ショップと同じ構成へ揃えた。外枠は`PixelUIStyle.apply_major_panel`、上部の装飾線は`add_ornament(…, "emblem")`、カードの地は`FrameArt.box`の石枠。
- 見出しは古金の「レベルアップ」（34px）。その上に「Lv.N に到達・戦闘時間は停止中」（18px）、下に「強化を1つ選び、下のボタンで取得する」（20px）。旧黄緑の`LEVEL UP!`と、タッチ前提だった「タップして選択」は撤去した。
- 色は強化の**種類だけ**を表す（ショップの分類色と同じ）。戦闘強化＝青`#79d7e8`、職業技／流派の選択＝金`#f2c14e`。この色は種類名・段階ピップ・説明文中の数値にだけ使い、カードの枠には使わない。
- 選択中のカードだけを青緑`#8fe0d6`の2px枠と光で示す。以前は説明文の単語から色を機械的に決めていたため、選んでいないカードの黄色い枠が選択中のカードと同じくらい目立っていた。
- キーボード操作中のカードにはショップと同じ`▶`カーソルを出す。

### カードの情報整理

- 上から、アイコン（64px）・種類名・名前（26px、1行）／段階ピップと段階表記／比較プレビュー／説明文。カードは362×450px。
- 段階ピップは最大段階までの枠を並べ、取得済みは灰、今回増える1段だけ種類の色、未到達は空枠。表記は「新規 Lv.1 / 3」「Lv.1 → Lv.2 / 3」、職業技は「段階 1 → 2 / 5」（`AttackPatternBase.MAX_ABILITY_LEVEL`）。上限のない強撃はピップを出さない。
- 3枚とも同じだった「NEW / 戦闘強化」と、意味が重複していた「未取得 → Lv.1」をこの段階表記へまとめた。
- 説明文はRichTextLabelにし、数値（18%・0.18秒・1体など）だけを種類の色で強調する。
- 全Labelは18px以上（旧タグは16pxで可読性検査の基準を割っていた）。

### 比較プレビューを実際の効果に合わせて作り直し

旧プレビューは各強化の実処理と食い違っていた（雷光連鎖の「現在」で攻撃自体が描かれない、広域攻撃の扇の角度が変わらない、貫通が飛距離の延長として描かれる、等）。職業技カードは説明文の単語から描画を推測していたため、内容と無関係な動きが出ていた。

新しいプレビュー（`ui/level_up_select/upgrade_preview.gd`、190px）は次の原則で描く。

- 左右は**同じ敵配置**で、変わるのは強化段階だけ。命中した敵だけが白く光ってHPが減るので、何体に当たるか・何が増えるかをそのまま数えられる。
- 上段の見出しは実数値（段階ごとの加算はゲーム側と同じ式）。
- 追撃・連鎖・結界・火花はゲーム内描画と同じ色（`survival_upgrade_effects.gd`の`#90ddff`／`#ffdf64`／シールド色）。
- 職業の通常攻撃の形（扇／突き／全周／弾）に合わせて「現在」の攻撃を描く。
- キャラは整数倍に丸めて拡大し、横長の敵は長辺基準で揃える。

| 強化 | 描く内容（実処理） | 見出し |
|---|---|---|
| 広域攻撃 | 射程×(1+0.18×段)・扇の半角+12°/段。現在の範囲のすぐ外（横と奥）の敵を強化後だけ巻き込む。範囲の境界線を常時うっすら表示 | 範囲（弾職は射程）100%→118% |
| 高速攻撃 | 攻撃間隔×(1−0.1×段)。現在の間隔4回分の時間軸に攻撃を刻む（現在4回→強化後5回） | 間隔 100%→90% |
| 残影追撃 | 直撃の0.18秒後、同じ敵へ影の斬撃（25%+5%×段） | 追撃なし→追撃30% |
| 雷光連鎖 | 命中点から近い敵へ段数ぶん雷が渡る（35%） | 連鎖なし→連鎖1体 |
| 再生結界 | 敵の一撃を、現在は主人公が受けてHPが減り、強化後は結界が受けてシールドだけが減る | シールドなし→シールド8 |
| 多重射撃 | 一度の発射が+1本/段。縦に並んだ敵へ1本ずつ当たる | 弾数 |
| 貫通射撃 | 弾は「段+1」体に当たってから消える（`pierce_remaining`） | 命中 1体→2体 |
| 強撃 | 攻撃力+8%/段、命中の火花の半径10+2.5×段（段0では火花なし） | 攻撃力 100%→108% |

職業技・流派の選択は段階ごとの効果が職業で異なるため、動く場面を作らず、職業と技の図柄を段階付きで並べる（実際と異なる動きを見せないため）。

### 検証

- `survival_growth_check`：PC（OpenGL）・タッチ横画面プレビューの両方でPASS（6職、選択と確定の2段階、画面内と文字収まり、プレビュー高さ、範囲の実効果）。
- `tests/script_load_check.gd`：全210 Scriptの実loadで失敗0。
- 一時Harnessで全8強化＋職業技カードを近接（soldier）・遠隔（archer）・2段目で撮影し、時刻を固定して各効果の決定的瞬間を確認。可読性検査と同じ基準（18px以上・カード内・切れなし・画面内）で全5パターン問題0件。
- `pixel_visual_check`はFAIL（HUDの「label outside flow」17件）、`secondary_ui_readability_check`は天賦図の検査（114行目）で停止する。**どちらも元のレベルアップ画面に戻して実行しても同一の結果**で、今回の変更とは無関係の既存の失敗。レベルアップ部分の検査はいずれも通過または上記の代替検査で確認した。
- 報告用の実画面は`artifacts/level_up_brushup/`（`before_after.png`、`previews_all.png`、`class_card.png`、`rank2.png`）。

### 未対応

- カードの登場演出と、入力機器（キーボード／タッチ）に応じた操作案内の切り替えは今回の範囲外。
- 職業技カードの比較は静止表示。職業ごとの段階効果を正確に動かすには、各職業の強化内容の個別設計が必要。
