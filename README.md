# VS Game Prototype v1

Steam(PC)向けのローグライク・サバイバー(ヴァンパイアサバイバーライク)の
初回実装スコープ(横長・キーボード/ゲームパッド操作)です。設計提案書
`design_proposal_v1.md` の「10. 初回実装スコープ」に基づいて実装しています。

## 開き方
1. Godot Engine 4.3以降(最新安定版)をインストール
2. Godotの「プロジェクトをインポート」からこのフォルダの `project.godot` を選択
3. 実行(F5) → タイトル画面 → 「スタート」でプレイ開始(ウィンドウは1600x900の
   横長で起動し、リサイズ可能)
4. 操作: キーボードの矢印キーまたはWASDキー、あるいはゲームパッドの十字キー/
   左スティックで移動。通常攻撃は自動。Spaceキーで職業固有アクティブスキル。

## 実装済みの内容(設計書10.1に対応)
- Entity基盤(HealthComponent / MovementComponent / HurtboxComponent / HitboxComponent / StatusEffectComponent)
- Player(キーボード矢印キー/WASD、またはゲームパッドでの移動のみ操作、WeaponManagerComponent、ExperienceComponent)
  - ラン開始時から`starter_sword`(`data/weapons/starter_sword.json`、欠片不要の基本武器)を
    自動装備した状態にしてあるため、欠片を1つも合成していない序盤から自動攻撃が発生する
    (`WeaponManagerComponent.starting_weapon_id`で指定。空にすれば従来通り無手スタートに戻せる)
- 敵1種類(直進追跡AI: ChaseStrategy)+ WaveSpawnerによる時間経過スポーン
- **独自要素:合体武器(フュージョン)システム**
  - 敵撃破時にランダムで欠片ドロップ
  - レベルアップ時の3択で欠片を選択可能(案②ハイブリッド型)
  - 固定レシピ(`data/weapons/*.json`の`required_fragment_ids`)と一致すると自動合成
- レベルアップ3択UI(欠片選択)
- **大量撃破の一掃演出**(最優先SNS演出): 短時間に規定数を倒すと
  GPUParticles2Dバースト + 画面シェイク + ヒットストップを発火(`MassKillTracker`)
- 簡易リザルト画面(生存時間・撃破数、リトライボタン)
- 設定画面の枠(エフェクト品質/画面揺れ/ダメージ表示トグル。実際の反映は未接続)
- データ駆動設計: `data/enemies/`, `data/weapons/`, `data/fragments/` にJSONを
  追加するだけで、コードを一切変更せずに敵・武器・欠片を追加可能(`DataLoader`が自動読込)
- **難易度カーブ**: `data/difficulty/default.json`に`time_seconds`(経過時間)ごとの
  `spawn_interval`(敵の湧く間隔)をbreakpoint配列として定義。`DataLoader`が
  `data/difficulty/`以下の全JSONを読み込み、ファイル名(拡張子なし)をidとした
  辞書(`difficulty_curves`)で保持する(ステージごとに違うカーブを使いたくなったら
  JSONファイルを追加するだけでよい)。`WaveSpawner`は`GameManager.elapsed_seconds`が
  breakpointのどの区間にあるかを見て前後の値を線形補間するため、時間経過で湧く間隔が
  なめらかに短くなっていく(`difficulty_curve_id`でカーブ切り替え、カーブが無い場合は
  `fallback_spawn_interval`にフォールバック)
- **武器属性ごとのVFXテーマ**(設計書7.2に対応、雷/炎/氷/光/闇):
  `effects/themes/*.tres`(`EffectThemeData`)+`effects/particles/themes/*.tscn`で
  属性ごとに通常ヒット/強化(プレイヤーレベル依存)の見た目を定義。`EffectThemeManager`が
  `WeaponData.vfx_theme_id`または`CharacterData.vfx_theme_id`から引き当てて再生する。
  雷=黄色/紫Particle+レベル3以上の局所Chain、炎=遅延爆発、氷=水色の破砕Particle
  (状態異常なし)、光=局所Beam(全画面Flashなし)、闇=レベル3以上で発射位置へ戻る
  吸収Particle。合成武器は`combo_ids`で構成属性の演出をまとめて再生する。
  属性Theme 20 Effect ID + 実ゲーム通常攻撃/Hit用Pixel 5 Effect ID、装備特殊効果との責務分離、
  追加手順、Performance基準は
  `game_specification.md`25章を正とする
- **プレイヤー/敵の見た目をドット絵アニメーションに差し替え**: `Polygon2D`だった仮図形を
  `AnimatedSprite2D`に置き換え済み。新設の`AnimationComponent`が移動方向(idle/walk切り替え+
  左右反転)・被ダメージ(hurt)・死亡(death)の再生を自動で行う。攻撃モーションはPlayerが
  `WeaponManagerComponent.weapon_fired`を、敵が`ContactHitbox.landed`を購読して
  `animation_component.play_attack()`を呼ぶことでattack1〜3からランダム再生。死亡時は
  アニメーション再生完了(`AnimationComponent.death_finished`)を待ってから
  `GameManager.end_run()`/`queue_free()`するよう変更した(即座に消えると演出が見えないため)。
  スプライトシートの読み込みは`entities/sprite_sheet_builder.gd`(`SpriteSheetBuilder`)に
  一本化(詳細は下記「職業選択システム」参照)
- **背景(StageEnvironment)**: `assets/tilesets/dungeon/Dungeon tileset.png`(384x192px、
  16x16単位のダンジョンタイルセット)を使い、Player/敵より奥(`z_index = -100`、かつ
  シーン上も一番手前=最初の子ノードに配置)へ暗めの床タイルをプレイヤー開始位置周辺
  (既定120x120マス、`half_width_tiles`/`half_height_tiles`で調整可)へ敷き詰めるだけの
  `StageEnvironment`シーンを追加。演出用の飾りのみで、壁や部屋のレイアウトは持たない。
  `TileSet`/`TileSetAtlasSource`は手書きの`.tres`ではなく`stage_environment.gd`の
  `_ready()`内でスクリプトから組み立てている(`TileSetAtlasSource.create_tile()`)。
  最初は無地タイル1種類だけで敷き詰めていたが、見た目が単色にしか見えず反映確認が
  しづらかったため、うっすら模様のある床タイルを4種類(`floor_atlas_coords`)混ぜて
  座標ハッシュで振り分けるようにした
- **ダメージ数値ポップアップ + クリティカル**:
  - `WeaponData`に`crit_chance`(既定0.15)/`crit_multiplier`(既定2.0)を追加し、
    `data/weapons/*.json`からも上書き可能(`DataLoader`)
  - `Projectile.launch()`で発射時に一度だけクリティカル判定を行い、当選時は
    `damage`を`crit_multiplier`倍にして`HitboxComponent.is_critical`を立てる
  - `HurtboxComponent`がダメージを与えた際に`EventBus.damage_dealt(amount, position, is_critical)`
    を発行(敵・プレイヤーどちらへのヒットでも発火する汎用シグナル)
  - `effects/damage_number.tscn`(`DamageNumber`): 被弾位置からふわっと浮かびながら
    0.6秒でフェードアウトするダメージ数値。通常時は白系文字、クリティカル時は赤色・
    文字サイズ1.5倍・より勢いよく飛び出す動き(Tweenのtrans/easeを変更)
  - `effects/damage_number_manager.gd`(`DamageNumberManager`): VFXPoolManager同様の
    プール方式で`EventBus.damage_dealt`を購読し再生。`ScreenEffects.quality_settings`の
    `damage_numbers_enabled`がfalseの間は生成をスキップする
  - `ui/settings/settings_screen.gd`の`damage_numbers_toggle`を`ScreenEffects`
    (グループ"screen_effects"経由で参照)に接続し、トグルでON/OFFを切り替え可能にした。
    ただし`SettingsScreen`自体はまだtitle/game画面から開ける導線になっていないため、
    今回接続したロジックが実際に動作確認できるのは、別途どこかにこの画面を
    表示する導線を用意してから
- **経験値・レベルアップとステータス成長**:
  - これまで`ExperienceComponent.add_exp()`を呼び出す箇所が存在せず、敵を倒しても
    経験値が入らない(=レベルアップも合体武器の3択も実質発生しない)状態だったため、
    `ExperienceComponent`が`EventBus.enemy_died`を自ら購読し、`EnemyData.exp_value`分の
    経験値を加算するようにした
  - 新設`components/stat_modifier_component.gd`(`StatModifierComponent`、設計書2.3で
    言及されている「バフ/デバフによるステータス補正の集約」コンポーネント)をPlayerに追加。
    `EventBus.player_leveled_up`を購読し、レベルに応じた固定攻撃力(1レベルごとに+1)と
    クリティカル率補正(1レベルごとに+1%、上限+50%)を保持する
  - `WeaponManagerComponent`→`Projectile.launch()`にこの補正を渡し、ダメージ計算・
    クリティカル判定へ実際に反映されるようにした(武器そのものの`base_damage`/
    `crit_chance`は変えず、都度の計算に上乗せする方式なので、複数武器を持っても
    それぞれ正しく補正がかかる)
- **背景が表示されない不具合の修正**: `Player.tscn`の`Camera2D`に`current = true`が
  設定されておらず、シーン内でどのカメラも「現在のカメラ」になっていなかった
  (2Dカメラが1台もアクティブでない状態)ため追加。あわせて`stage_environment.gd`に
  タイルセット画像の読込失敗・タイル登録失敗を検知する`push_error`と、実際に
  何マス敷けたかを起動時に`push_warning`で出力する診断ログを追加した。
  タイルセット画像自体は`.import`キャッシュも含めて正常にインポート済みであることを
  確認済み。それでも表示されない場合は、Godotの「出力」パネルに上記の警告/エラーが
  出ていないか教えてほしい
- **StageEnvironmentをTileMapLayerで再構築**: 旧`TileMap`ノードは実データ上は
  正しく子ノードとして存在していたが、`game.tscn`側でインスタンス化した
  `StageEnvironment`シーンの内部ノードはGodotエディタのシーンツリーで既定では
  折りたたまれて何も表示されない(いわゆる「Editable Children」がOFFの状態)ため、
  「空に見える」という報告につながった可能性がある。これに対応するため:
  - `TileMap`(非推奨)から、Godot 4.3以降で推奨されている`TileMapLayer`に置き換え
  - `game.tscn`に`[editable path="StageEnvironment"]`を追加し、エディタのシーンツリーで
    `StageEnvironment`配下の`TileMapLayer`が最初から展開表示されるようにした
  - 敷き詰める範囲も画面(720x1280、カメラzoom1.5)の縦横5倍前後まで拡大
    (`half_width_tiles=80`, `half_height_tiles=120`)
  - 修正後、`game.tscn`→`stage_environment.tscn`→`stage_environment.gd`の3ファイルを
    実際に読み直し、`TileMapLayer`ノードがシーン定義に存在することをこちらで確認済み
  - この`tile_set`代入についてはさらに一歩進めて、手元にあった`Godot_v4.7.1`実行ファイルで
    実際にヘッドレス実行・検証した(推測ではなく実行結果で確認済み)
- **床の見た目のバリエーション追加 + 装飾レイヤー**(2回改訂): `Dungeon tileset.png`を
  改めて確認し直し、以下を実施:
  - `floor_atlas_coords`(床)を8種類・均等重み付けに変更。無地`(9,10)`・ひび割れ2種
    `(0,9)`/`(1,10)`に加え、壁用ブリックを色違いの床として転用した紫`(1,1)`・黒に近い
    暗色`(6,2)`・苔むした緑`(10,3)`・青灰`(5,2)`、床の金属グレーチング`(9,2)`を追加し、
    出現比率を完全に均等化(以前は無地・ひび割れが多めの重み付けだったため、それでも
    「単調」との指摘を受けて差し色を主役級まで引き上げた)
  - 加えて`TileMapLayer`/`DecorationTileMapLayer`を`scale=2`・`texture_filter=NEAREST`で
    2倍表示にし、模様そのものが小さすぎて視認しにくかった問題にも対応(その分マス数は
    半分にして同じ実世界サイズをカバーするよう調整)
  - `DecorationTileMapLayer`(`z_index=-50`、床`-100`とキャラクター`0`の間)に、
    松明(トーチ台)`(11,5)`・樽2種`(7,5)`/`(12,5)`・壺2種`(9,5)`/`(10,5)`・柱2種
    (`(20,0)`+`(20,1)`、`(21,0)`+`(21,1)`を上下2マスで1本)を`decoration_chance=0.0025`で
    低頻度にランダム配置。当たり判定は無い
  - **ゆらめく松明・明滅する結晶の追加**: 新規配置された`torch_a.png`(4コマ、64x128)・
    `torch_b.png`(5コマ、64x128、壁掛けタイプ)・`wall_deco.png`(8コマ、64x64。中身を
    確認したところ静止画バリエーションではなく明滅する結晶/宝石クラスターのループ
    アニメーションだった)から、`SpriteFrames`をスクリプトで組み立てて`AnimatedSprite2D`化。
    新設`SpriteDecorations`コンテナ(`z_index=-50`、当たり判定なし)配下に、松明A/B各10体・
    結晶15体(既定値、`torch_a_count`等でスクリプトから調整可)を最低間隔140pxを空けつつ
    ランダム配置。個体ごとに初期フレームと再生速度(0.85〜1.15倍)をずらし、全員が
    完全同期して明滅しないようにしている
  - Godotをヘッドレス実行して実際に確認(推測ではなく実行結果): 床9600マス(8種類が
    各1200個ずつで完全均等)、タイル装飾31個(7種類すべて出現、柱の上下ペアも欠けなし)、
    松明A10体・松明B10体・結晶15体の合計35体すべてが正しくアニメーション再生中である
    ことを確認済み
- **職業選択システム + 新しい敵10種**:
  - `resources/character_data.gd`(`CharacterData`)+ `data/characters/*.json`
    (soldier/swordsman/knight/knight_templar/armored_axeman/lancer/archer/wizard/priest/
    necromancer)を新設。`id`/`display_name`/`sprite_folder`/`max_hp`/`move_speed`/
    `unlock_cost`を持つ(soldierのみコスト0=最初から解放済み、他は100〜500で段階的)
  - `entities/sprite_sheet_builder.gd`(`SpriteSheetBuilder`)を新設。`assets/sprites/`配下の
    フォルダ名(例: `player/Wizard`、`enemy/Slime`)から実行時に`SpriteFrames`を組み立てる
    共通ユーティリティで、Player/EnemyBasic両方から使う。この素材一式はファイル名の付け方
    (`Walk`/`Walk01`/`Flying`、`Attack01`/`Attack1`、`Death`/`DEATH`)やフォルダ構成
    (直下 or "◯◯ with shadows"/"◯◯"サブフォルダ)がキャラごとにまちまちだったため、
    候補を順番に試して最初に見つかったものを採用する作りにしてあり、コマ数もハードコードせず
    画像の実サイズ(幅÷高さ、1コマ=正方形前提)から自動算出する。プレイヤー10種・敵12種
    すべての素材フォルダに対して実際にヘッドレス実行で解決できることを確認済み(1体だけ
    attack2/attack3が見つからない職業もあるが、`AnimationComponent`は該当アニメーションが
    無ければ黙ってスキップする作りなので問題ない)
  - `SaveManager`に`unlocked_character_ids`(既定`["soldier"]`)と`unlock_character(id, cost)`
    (コスト不足なら何もせずfalseを返す)を追加。将来のセーブデータ互換のため、
    ロード時に無いキーは既定値で補完するようにしてある
  - `GameManager.selected_character_id`(既定`"soldier"`)を新設
  - `ui/home/home.tscn`+`home.gd`を新設。`title.tscn`の「スタート」から
    `home.tscn`へ遷移するように変更(`title.gd`)。解放済みの職業はボタンをタップすると
    即ゲーム開始、未解放の職業はコスト表示付きでグレーアウトし、タップで解放を試みる
    (`SaveManager.unlock_character`、コスト不足時は何もしない)
  - `Player`は`_ready()`で`GameManager.selected_character_id`から`CharacterData`を引き、
    HP・移動速度と`AnimatedSprite2D.sprite_frames`(`SpriteSheetBuilder`経由)を差し替える
  - `EnemyData`に`sprite_folder`を追加(未使用だった`sprite_frames`フィールドを置き換え)。
    `EnemyBasic`も同様に`sprite_folder`から見た目を差し替える。`WaveSpawner`は元々
    `DataLoader.get_all_enemies()`を自動取得する実装だったため、JSON追加だけで新しい敵が
    出現対象に含まれることを確認済み(既存の`basic_enemy`=Orc、`fast_enemy`=Skeletonに加え、
    Armored Orc/Armored Skeleton/Bat/Elite Orc/Greatsword Skeleton/Orc rider/
    Skeleton Archer/Slime/Werebear/Werewolfの10種を追加。Elite Orc・Greatsword Skeleton・
    Werebearは体力・攻撃力高め、Bat・Slime・Skeleton Archerは体力低めで役割に差を付けた)
  - 不要になった手書きの`soldier_sprite_frames.tres`/`orc_sprite_frames.tres`は削除
  - Godotをヘッドレス実行して実際に確認(推測ではなく実行結果): `DataLoader`が職業10種・
    敵12種すべてを正しく読み込み、ホーム画面が10個のボタンを生成し未解放/解放済みの
    表示が仕様通りになっていること、解放フロー(通貨消費→解放)が実際に動作すること、
    Player/EnemyBasicが選択・データに応じてHP/速度/見た目を正しく差し替えること、
    `game.tscn`一式が最後まで起動しWaveSpawnerが12種類すべてを自動取得していることを確認済み
- **精鋭属性+地面装備+ラン内装備システム**:
  - 精鋭部屋の見えない壁を撤廃し、戦うか逃げるかを選べるように変更
  - 火炎/雷撃/氷結/毒/吸血/堅牢を進行時間に応じて1〜3個ランダム付与
  - 精鋭撃破時は必ず装備を1個以上床へドロップし、Eキー/ゲームパッドXで手動取得。
    レアリティの50/30/15/4/1抽選は維持し、追加ドロップはDataで将来有効化できる
  - 5レアリティ、6装備スロット、7種の装備ステータス、Legendary/Mythic特殊効果に対応
  - Cキー/ゲームパッドYでキャラクター中心の装備・比較画面を開く（Iは互換入力）。
    C/ESCで閉じ、装備はラン終了時にリセットされる
  - 詳細・調整ファイル・追加クラスは`game_specification.md` 23章を参照
  - 精鋭部屋入室の`body_entered`中に精鋭sceneを同期生成するとPhysicsServerの
    flush中にCollisionShapeを変更してしまう不具合を修正。生成をdeferred化し、
    見えない壁なしのまま精鋭・属性・撃破・装備ドロップが正常に動作するようにした
  - オリジナル装備アイコン第1弾25点(武器10、頭/胴/腕/脚/アクセサリー各3)を
    64×64透過ピクセルアートで追加。各レアリティ5点を専用の物理デザインに分け、
    抽選後は同レアリティのテンプレートだけを選択する。地面ドロップ・所持装備一覧・
    装備済みスロットでは装備実体が持つ同じアイコンを表示する
  - `data/elite_affixes/spawn_curve.json`の時間帯別絶対時刻と180秒Soft Pityで巡回エリートを
    通常Waveへ混ぜる。Boss/精鋭部屋中は生成だけを保留し、期限は止めない。10分×5回は
    全て4体（平均4.00体）で、追加200 seedも3〜5体。部屋精鋭・ボス・通常敵の処理は維持する
  - 地面装備は不透明画素範囲をプレイヤー高の70〜100%へ正規化。カード枠・浮遊・巨大リングを
    廃止し、硬いPixel Plate + 非AA Outline + レアリティ別の少量Fragmentへ変更。縦Loot Beamと柔らかいGlowは生成しない
  - 通常攻撃開始を`AttackVFXManager`へ接続し、斬撃・投射・Pulse・通常Hit・Critical Hitの
    5種類を各6フレームのPixel Sprite Animationとして実ゲームWorldで再生する
  - 装備Affixは攻撃/防御/最大HP=固定値、Crit/Critダメージ/攻撃速度/移動速度=割合値。
    Legendary/Mythicは命喰らい・守護の残響・窮地の力のいずれか1効果を持つ
  - 火/氷/雷/光/闇の欠片はラン中のElement Loadoutへ最大2属性・各Lv3で蓄積する。同属性はLv上昇、
    異属性は2枠目へ入り、3種類目は取得を拒否してBuildを固定する。Lv3後はMastery候補へ移る。
    合成用`held_fragment_ids`とは独立し、run終了でresetする
  - 通常攻撃は既存Attack Type（Slash/Projectile/Pulse）へ主属性の見た目を合成し、保持する
    各属性の追加Damageを別数値で表示する。火/氷/雷の追加比率とVFXはLv1〜3で強化される
  - 雷Projectileは共有Arrowを隠して6フレームの電撃弾へ置換し、雷Lvに応じ最大1/2/3体へ
    220px内で連鎖（70/50/35%減衰、同じ敵へ戻らない）。居合の半透明扇形は廃止し、
    Dash・残像・細い火/氷/雷Trail・Hitを維持する。HUDは2属性・Lv・主属性を色分け表示する
  - 詳細なElement ID、Effect ID、Asset、Lifetime、拡張手順、実ゲーム検証は
    `game_specification.md` 27〜28章を正とする
- **Pixel Visual System / 36ROOM遷移最適化**:
  - `PixelUIStyle`でTitle/HUD/属性・宝箱・Concept/装備/Pause/Result/Test Labを角なし3px境界、硬い影、明確なFocusへ統一
  - VFXは発生→中心展開→最大→外周崩壊を共通文法とし、主Spriteの横スライドと寿命全体Fadeを使用しない
  - 新規6-frame風刃Pixel Artを`assets/vfx/concepts/wind_blade_6f_v2.png`へ追加し、実Concept攻撃とTest Labへ接続
  - ROOMはMap/Resourceを報酬中に先行準備し、Stage敷設、Enemy生成、AI/Physics解除を分割。36回遷移Stressと36ROOMキーボード通しで確認済み
  - 詳細は`docs/vsgame_pixel_visual_guide.md`と`game_specification.md` 33章を参照
- **背景を「見た目だけ」から「実際に壁にぶつかるダンジョン」に変更**:
  - `systems/dungeon_map.gd`(`DungeonMap`): 床/壁を持つ単純な2値グリッド(中心寄せ座標、
    `PackedByteArray`)。`grid_to_world`/`world_to_grid`変換や`is_wall_adjacent_floor`
    (壁際判定、装飾配置に使用)、`get_floor_cells`を提供する
  - `systems/dungeon_generator.gd`(`DungeonGenerator`): ランダムな矩形の部屋(8x8〜14x14)を
    重なりを避けつつ配置し、部屋の中心同士を幅4マスのL字通路でチェーン状に接続、さらに
    ループ用の追加接続を数本足す方式。**「大量の敵に囲まれて薙ぎ払う爽快感」を損なわないよう
    部屋・通路とも広めに作る**という方針に対応(細い1マス通路の迷路にしない)。外周は
    最終処理として必ず壁で塗り潰す。マップサイズ・部屋数は`GameManager`の
    `DUNGEON_WIDTH`/`DUNGEON_HEIGHT`/`DUNGEON_ROOM_COUNT`(既定100x100・12部屋)で調整可能。
    ラン(`GameManager.start_run()`)ごとに新しく生成し直すため、プレイのたびに配置が変わる
  - **初期化順序の注意**: 子ノードの`_ready()`は親(`Game.gd`)の`_ready()`より先に実行される
    ため、`GameManager.start_run()`(ダンジョン生成)より前に`StageEnvironment`/`Player`の
    `_ready()`が走ってしまい、生成結果を参照できない。そのため`StageEnvironment.build_dungeon()`
    と`Player.setup_camera_limits()`は自動実行にせず、`Game.gd`が`start_run()`の直後に
    明示的に呼び出す構成にした(Controller層が生成順序を保証する)
  - `StageEnvironment`は`DungeonMap`の床マスに従来通りの床タイル(種類・出現比率は変更なし)、
    壁マスには壁タイル(`wall_atlas_coords`、既定で紫レンガ系2種)を敷く。壁タイルには
    `TileSet`の**物理レイヤー機能**でタイル全体(16x16)を覆う矩形の衝突ポリゴンを設定して
    あり(`TileData.add_collision_polygon`)、マスごとに個別の`StaticBody2D`を作らずに
    Player/EnemyBasic(既定`collision_mask=1`のCharacterBody2D)が壁を通れないようにしている。
    装飾(タイル状装飾・松明・結晶)は`is_wall_adjacent_floor`で壁際の床マスだけに絞って
    配置し、通路の真ん中には出さない
  - `WaveSpawner`は`GameManager.dungeon_map`の床マスの中からプレイヤー付近のものを
    ランダムに選んで出現位置にする(壁マス・マップ範囲外には湧かない)。
    近くに床マスが無い場合はマップ全体の床マスから選ぶ。`dungeon_map`が無い異常系では
    従来通りプレイヤー周囲のリング状フォールバックに戻る
  - `Player.tscn`の`Camera2D`に`limit_left`/`limit_right`/`limit_top`/`limit_bottom`を
    生成後のマップ範囲から設定し、マップ外の空白が映らないようにした
  - Godotをヘッドレス実行して実際に確認(推測ではなく実行結果): 生成マップは床2931/壁7069
    マス(約29%が床)、外周が完全に壁であること、スポーン地点が床であること、
    `WaveSpawner`が300回サンプリングした出現位置がすべて床マスだったこと、壁タイル2種
    それぞれに衝突ポリゴンが1つずつ登録されていること、実際に壁マスへ塗られたタイルを
    1240箇所サンプリングしすべて`wall_atlas_coords`のタイルだったこと、`game.tscn`起動後に
    プレイヤーが実際に床マス上へスポーンしカメラのlimitが正しく設定されていることを確認済み
  - **既知の制限**: 敵のAI(`ChaseStrategy`)はプレイヤーへの直線移動のみで、壁を避ける
    経路探索(パスファインディング)は持たない。同じ部屋・通路にいれば通常通り追ってくるが、
    壁越しに直接プレイヤーがいる場合は壁に沿ってスライドするだけで、賢く回り込むことはしない
    (`move_and_slide()`によるスライド運動は行うため完全に固まるわけではない)
- **壁タイルが床タイルと見分けにくかった問題の修正**: 当初の壁タイル`(1,0)`/`(0,1)`は、
  床の色違いアクセントとして使っていた`(1,1)`(紫レンガ)と同じ絵柄の系統だったため、
  床と壁が目で区別しにくくなっていた。目地(モルタル)がくっきり見えるレンガ積みの
  タイル`(7,2)`/`(8,2)`(床タイルと重複しない座標)に選び直し、さらに壁タイルだけ
  `TileData.modulate`で暗めの乗算ティント(既定`Color(0.5, 0.5, 0.56, 1.0)`、
  `wall_tile_modulate`で調整可)をかけて、絵柄が近くても明るさで一目で区別できるようにした。
  ヘッドレス実行で実際に確認: 床タイル・壁タイルの座標が重複していないこと、壁タイルのみ
  ティントと衝突ポリゴンが設定され、床タイルには両方とも設定されていない(既定の白色・
  当たり判定なし)ことを確認済み
- **床タイル選定基準の見直し**: 上記の壁色見直しでも、床タイル候補に木箱・樽・檻(格子)・
  レンガの壁ブロックの絵柄が紛れ込んだままだった(壁用ブリックを「色違いの床」として
  転用していた名残)ため、選定基準を「画像最下部の帯(y=8〜11、グレーの石畳・ひび割れ
  石畳が並ぶ部分)にあるタイルのみ」に絞り直した。木箱・樽・松明・旗・鎖・柱・檻・レンガ
  壁ブロックが描かれたタイルは完全に除外し、候補は1つずつ切り出して個別に画像を目視し、
  実際に「平らな石畳・地面」に見えることを確認したものだけを採用した:
  - `(9, 10)`: 無地の石畳(模様なし、完全に平ら)
  - `(12, 8)`: 無地の石畳(別位置、こちらも模様なし)
  - `(0, 9)`: ひび割れ石畳A(十字状の細いひび)
  - `(1, 10)`: ひび割れ石畳B(枝分かれした太めのひび)
  - `(1, 11)`: ひび割れ石畳C(ひびに加え小さな欠け)
  ヘッドレス実行で実際に確認: 上記5座標がすべてy=8〜11の帯内にあること、壁タイル座標
  `(7,2)`/`(8,2)`と重複しないこと、以前使っていた木箱・レンガ壁系の座標が残っていないこと、
  実際にダンジョンを生成して敷き詰めた結果もこの5種類のみが使われていた(他の座標が
  床に紛れ込んでいない)ことを確認済み
- **壁の見た目を「装飾性のある石壁」に変更**: 前回選んだ`(7,2)`/`(8,2)`が単調な暗色
  レンガだったため、旗・檻・アーチ門・松明が並ぶ装飾帯(y=0〜4)を改めて確認し、以下を実施:
  - ベース壁タイルを、その帯の中で一点物(旗/檻/門/松明)が描かれていない「繰り返し使える
    通常のレンガ部分」`(7,3)`/`(9,3)`に選び直した。目地(モルタル)がくっきり見える、
    明るめの紫がかった石壁の質感。以前入れていた暗色ティント(`TileData.modulate`)は
    撤去し、素材本来の明るさで表示するようにした。候補は隣接タイルの装飾が上下ににじんで
    いないか(実際に(3,3)/(6,3)/(8,3)は旗や松明の一部が上下ににじんでいたため除外)
    1つずつ切り出して確認済み
  - `wall_decoration_variants`として一点物の壁装飾を追加し、壁マス20〜30個に1個程度
    (`wall_decoration_chance=0.04`)の低頻度で、床に面している(プレイヤーから見える)
    壁マスにのみランダムに混ぜるようにした: 旗(赤)`(0,4)`、旗(青)`(5,4)`、
    檻(格子)`(1,4)`、松明(壁掛け)`(8,4)`、アーチ型の門`(13,1)`+真上`(13,0)`
    (縦2マス、真上が床マスの場合は配置しない)。同じ装飾が隣接マスに重ならないよう
    配置時にチェックしている。装飾タイルにもベースと同じ矩形の衝突形状を設定しており、
    通常の壁と同様に通行不可
  - Godotをヘッドレス実行して実際に確認: 生成したダンジョンの全壁マスが期待した
    座標(ベース2種+装飾5種のbase/top)以外を使っていないこと、同じ装飾が隣接して
    配置された箇所が無いこと、ベース・装飾のすべての座標に衝突ポリゴンが設定されている
    ことを確認済み(このテストでは壁装飾38個が実際に配置された)
- **背景・キャラクターのスケール感と敵の出現距離の調整**:
  - タイル(`TileMapLayer`)だけを`TILE_RENDER_SCALE=2`で2倍表示にしていたため、
    キャラクターが相対的に小さく見えていた問題に対応。**案B(キャラクター側にも
    タイルと揃うスケールをかける)** を採用し、`Player.tscn`/`enemy_basic.tscn`の
    `AnimatedSprite2D.scale`をそれぞれ`0.6→1.2`・`0.5→1.0`に倍率を上げ、タイルの
    2倍化前と同じキャラクター/タイル比率(プレイヤー約3.75タイル分・敵約3.13タイル分の
    横幅)に戻した。当たり判定(`CollisionShape2D`)はあえて変更しておらず、見た目のみの
    調整にとどめている(当たり判定を広げると難易度バランスが変わってしまうため)
  - 壁沿いの松明(`torch_a.png`/`torch_b.png`、1コマ64x128px)が無補正だと壁タイル1マス
    (32px)の4倍の高さになり明らかに大きすぎたため、`torch_sprite_scale`(既定0.3)で
    縮小し、タイル1.2マス分の見た目高さに収めた(松明のみが対象。結晶`wall_deco.png`は
    今回のご指摘の対象外のため変更していない)
  - `WaveSpawner`に`min_spawn_distance`(既定220px)を追加。プレイヤーからこの距離より
    近い床マスは出現候補から除外し、それより遠く`spawn_radius`以内の床マスからランダムに
    選ぶようにした(候補が無ければ最低距離の条件だけ保ってマップ全体から探す)
  - Godotをヘッドレス実行して実際に確認: タイル1マス=32px・プレイヤー visual=120x120px
    (3.75タイル分)・敵visual=100x100px(3.13タイル分)であること、松明の見た目高さが
    38.4px(タイル1.2マス分、要求の1.0〜1.5マス範囲内)であること、200回サンプリングした
    敵の出現距離が最短224px・最長480pxで、すべて`min_spawn_distance`(220px)以上に
    なっていることを確認済み

- **ダンジョン装飾を「意図的にデザインされた部屋」に見えるよう配置ルール化**:
  それまでの装飾配置(壁装飾・タイル装飾ともランダムな低頻度散布)を、部屋を意識した
  規則的な配置に作り替えた。`DungeonGenerator`が生成時に各部屋の矩形(`DungeonMap.rooms`)と、
  通路が部屋の境界を横切る「出入り口」の両脇の柱座標(`DungeonMap.pillar_positions`、
  2個1組で対称なペア)を新たに記録するようにし、`StageEnvironment`側でこれを使って
  以下の5つの配置パスを部屋単位で行う:
  1. **柱(出入り口の両脇に必ず対称に1本ずつ)**: `pillar_atlas_base(20,1)`+真上`(20,0)`の
     縦2マス構成。`_place_doorway_pillars`が出入り口ペアを「両方置ける場合のみ」配置し
     (片側だけ置いて非対称になることがないよう常にペア単位で判定)、通路が密集して
     重なり本来の位置が床になっている場合は`pillar_step_directions`(開口部から外側へ
     離れる向き)へ最大3マスずらして再試行する。柱の土台マスだけを必須条件にし、
     真上のマスが塞がっている場合は土台のみの1マス丈の柱として成立させることで、
     通路が密集した箇所でも柱が欠落しにくくした。柱タイルにも壁と同じ矩形の衝突形状を
     設定済み
  2. **松明(torch_a/torch_b)の等間隔配置**: 従来の「マップ全体からランダムに低頻度で
     散布」をやめ、各部屋の四辺(壁沿い)を`torch_wall_spacing`(既定4マス)ごとに歩いて
     配置する方式に変更。出入り口の開口部(床マス)や実際に置かれた柱の1マス以内は
     スキップする。部屋ごとにtorch_a/torch_bを交互に使い単調にならないようにした
  3. **収納コーナー(樽・壺のクラスター)**: 装飾タイル(樽×2種・壺×2種)を1個ずつ
     孤立させて散らす従来方式をやめ、部屋のうち約半数(`storage_cluster_room_ratio=0.5`、
     部屋indexのハッシュで決定)について、1つの隅(部屋indexに応じて4隅のいずれか)に
     2〜4個をまとめて配置する`_place_storage_clusters`に変更した
  4. **檻(格子)の低頻度・部屋壁限定化**: 従来は他の壁装飾(旗・アーチ門)と同じ抽選プールに
     混ぜていたが、専用の`_place_rare_cages`に分離し、(a)`wall_decoration_chance(0.04)`より
     低い`cage_chance(0.012)`、(b)`_is_room_boundary_wall`で判定した「部屋の壁面」のみを対象
     (通路がただ部屋同士を繋ぐだけの区間の壁には出さない)、(c)出入り口の柱から2マス以内は
     除外、の3条件に変更した
  5. 旗・アーチ門(`wall_decoration_variants`、檻と松明はここから分離済み)は従来通り
     低頻度ランダムのままとし、装飾の総数は増やさず「規則性のある配置」を優先する方針に
     した(結晶`wall_deco.png`の低頻度ランダム配置も変更なし)
  - Godotをヘッドレス実行し、乱数シード固定(seed=12345)で100x100・部屋数12の
    ダンジョンを生成して実際の配置を確認済み:
    - 出入り口28組(通路14本×2部屋)のうち18組(64%)で柱が左右対称に配置され、
      衝突ポリゴンも設定されていることを確認(非対称になったケースは0件)。
      残り10組は複数の通路が密集して重なる箇所で床になってしまい、通行を塞がないことを
      優先してスキップした(この生成アルゴリズム自体は変更していないため、部屋数や
      マップサイズを変えれば密集度・成功率も変わる)
    - 松明は部屋の壁沿いに実測で4マス(128px)間隔ちょうどで並んでいること、実際に
      置かれた柱タイルの1マス以内には1件も配置されていないことを確認
    - 檻は全4件が部屋の境界壁上のみに配置され、柱の2マス以内への配置は0件
    - 収納コーナーは12部屋中7部屋(約58%、目標の「約半分」相当)に2〜4個ずつ配置
    - サンプル部屋の実際の配置(room[0]: 位置(-7,-8)・サイズ10x9、room[1]: 位置(21,0)・
      サイズ8x8):
      | 部屋 | 柱(base座標) | 松明(マス座標) | 収納コーナー |
      |---|---|---|---|
      | room[0] | (-8,-9)(3,-9)(-8,1)(3,1) | (-6,-9)(-2,-9)(-6,1)(-2,1) | (-6,-7)=樽, (-5,-7)=樽(別柄) |
      | room[1] | (22,-1)(28,-1)(20,1)(20,7) | (22,8)(26,8)(29,1)(29,5) | なし(この部屋は対象外の約半数側) |

- **壁の断面構造・出入り口の装飾・床デカールを参考イメージに合わせて再現**:
  Dungeon tileset.pngを実際に切り出して1マスずつ確認した結果、壁の「上端専用」
  「苔むした緑の縁専用」タイルは見当たらなかったため、ユーザー指示の
  「無ければmodulateティントで代用」に従い、既存の壁レンガタイル`(7,3)`/`(9,3)`に
  alternative tile(TileSetの同一座標に複数のTileDataを持たせる仕組み)で明るい
  tint・苔色tintを追加する形で3段構造を再現した(以下の`_fill_floor_and_walls`の
  ロジック):
  - 各壁マスについて、床マスからの最短距離をBFSで計算(`_compute_wall_distances`)
  - 距離1(床に直接面する) → 上端(明るいtint、`wall_top_tint`)
  - どの隣接マスにも「自分よりさらに1つ遠い壁マス」が続いていない(=壁のかたまりの
    末端。マップ外周や孤立した壁の最奥) → 外側・下端(苔色tint、`wall_moss_tint`)
  - それ以外 → 本体(tint無し、従来通りのレンガ)
  - `wall_render_max_distance`(既定4マス)を超えて床から離れた壁マスは、
    「床タイルでも壁タイルでもない何も描画しないマス」のままにした(結果として
    ダンジョン建築から離れた領域は完全な黒背景=voidになる)。あわせて
    `project.godot`に`rendering/environment/defaults/default_clear_color`を
    `(0,0,0,1)`(黒)で明示し、未描画部分が確実に黒くなるようにした
  - alternative tileのどの段(上端/本体/外側・下端)にも通常と同じ矩形の衝突形状を
    設定しており、見た目の段が変わっても通行不可であることは変わらない
  - 出入り口の柱の脇には、既存の旗タイル(赤/青)を柱から2マス外側に添えるように
    した(柱自身の縦2マス分のfootprintと重ならない位置)。また、柱と柱の間の
    開口部(床マス)には、タイルセット内で新たに見つけた階段状の絵柄`(9,1)`を
    段差(階段)タイルとして敷いた(柱が実際に配置できた出入り口のみ)
  - 床全体には、既存のひび割れ床タイルとは別に、低頻度(既定2%)で透過背景の
    小さな瓦礫スプライト`(7,9)`をデカールとして薄く散らした(タイルセット内に
    ひび割れ/シミ/骨片専用の透過デカールは見当たらなかったため、この瓦礫スプライトで
    代用している。収納コーナーや出入り口の段差タイルと重ならないようにしている)
  - Godotをヘッドレス実行し、乱数シード固定(seed=12345)で実際に確認:
    - マップ全体10000マスのうち実際に描画されたのは5257マス(47.4%が完全な
      未描画=void)
    - 壁タイルのalternative tile分布: 本体1004・上端631・外側/下端(苔)565、
      すべての段に矩形衝突ポリゴンが1つずつ設定されていることを確認
    - room[0](位置(-7,-8)・サイズ10x9)の上辺から外側へのサンプル: 1マス目=上端
      (明るいtint)→2〜3マス目=本体→4マス目=外側/下端(苔)→5マス目以降=void、
      という狙い通りの断面が実際に再現されていることを確認
    - 柱36本(18ペア)のうち33本(91.7%)で2マス外側に旗を確認、段差タイルは
      マップ全体で70マス
    - 床デカールは床2931マス中78マス(2.66%、目標2.00%に近い)に配置

- **柱の連続配置・苔tintの弱さ・void外周の黒背景を修正(参考イメージとの差分フィードバック対応)**:
  1. 柱が壁沿いに連続して「柱の列」のように並んでしまう問題を修正。原因は、
     1つの部屋に複数の出入り口が近接している場合(部屋数12に対し通路14本、
     出入り口理論値28に及ぶため、同じ部屋に2〜3個の出入り口が集中することがある)、
     それぞれの出入り口が独立して柱を配置していたため。`_place_doorway_pillars`に
     `DOORWAY_MIN_SEPARATION`(既定6マス)を導入し、既に柱を配置した出入り口から
     6マス以内にある別の出入り口には柱を置かないようにした(通路・段差・松明などの
     配置は影響を受けない、柱の重複だけを間引く)。結果として柱は理論値28出入り口中
     11出入り口(22本)に絞られたが、直線の壁は「レンガ+等間隔の松明」のみの
     単層構成に戻った
  2. 苔むした緑の下端tintが弱すぎて視認できなかった問題を修正。元のレンガタイルが
     紫がかっているため、teal寄りの弱いtintでは紫のまま埋もれてしまっていた。
     `wall_moss_tint`を`(0.55,0.78,0.58)`から`(0.32,0.85,0.4)`(赤・青を大きく削り
     緑を強調)に変更し、はっきり緑と分かる見た目にした
  3. マップ外周が完全な黒背景になっていない可能性への対応として、
     `project.godot`のdefault_clear_color設定だけに頼らず、マップ全体を覆う
     巨大な単色の黒いSprite2D(`_ensure_void_background`、z_index=-200で
     TileMapLayerの背面に配置)を追加した。環境やレンダラーの設定に関わらず、
     床タイル・壁タイルが一切配置されない領域は常に黒く見えるようにしている
  - Godotをヘッドレス実行して実際に確認: room[0]の上辺を柱atlas座標でスキャンした
    結果`P..........P`(両端にのみ柱、間は無地レンガ)になっていること、
    `wall_moss_tint`のTileData.modulateが`(0.32,0.85,0.4,1.0)`で実際に反映されている
    こと、void背景Sprite2Dが3712x3712(マップ実サイズ3200x3200より広い)をカバーし、
    マップ範囲外にタイルが一切配置されていないことを確認済み

- **通路の行き止まりに限定した柱フェンス装飾を追加**:
  参考イメージ下部に見られる「柱が連続して並ぶフェンス状の装飾」について、
  「部屋の壁には使わず、通路の行き止まりだけに限定する」という条件でユーザーに
  確認のうえ追加した。実装は`_place_dead_end_pillar_fence`:
  - 対象は「部屋の境界壁ではない(`_is_room_boundary_wall`が false)」かつ
    「床からの距離がちょうどwall_render_max_distance(=描画範囲の最奥、voidの
    直前)」のマスに限定し、部屋の壁沿いには絶対に置かれないようにした
  - 上記の条件だけだと、近接した部屋同士を隔てる薄い間仕切り壁も含め
    マップ内に対象マスが数多く見つかり、フェンスだらけになってしまったため、
    20x20マス単位のブロックごとに`pillar_fence_block_chance`(既定12%)で
    抽選し、当たったブロックの中だけで`pillar_fence_spacing`(既定3マス)おきに
    柱を並べるようにした(「時々、行き止まりに柵がある」程度の頻度に調整)
  - Godotをヘッドレス実行して実際に確認: room[0]の壁を全周スキャンした結果
    出入り口の柱以外は一切増えていないこと(`P..........P`のまま)、フェンス柱は
    マップ全体で7本(2〜3本のまとまりが2箇所)にとどまり、同じまとまり内では
    実測で3マスおきの等間隔になっていることを確認済み
- **苔の緑tint・void外周の黒背景の追加修正**(前回のフィードバック対応の続き):
  紫がかったレンガに対して緑側へのtintが埋もれていた問題について、
  `wall_moss_tint`を赤・青成分をさらに削った値に強調し直した。また、
  void背景用の黒いSprite2Dのカバー範囲・z_indexを実際にヘッドレス実行で
  再確認し、マップ範囲外にタイルが一切配置されていないことを再検証した。

- **精鋭部屋(Elite Room)を追加**:
  「大量の雑魚が湧いて薙ぎ払う」コアループは維持しつつ、ダンジョン内の一部の部屋を
  「精鋭部屋」として指定し、強化された少数精鋭の敵と戦う特別な部屋を追加した。
  - `DungeonGenerator.generate()`に`elite_room_count`引数を追加(`GameManager.dungeon_elite_room_count`
    でエディタから調整可能、既定1)。生成後、スタート地点(`rooms[0]`)から
    `ELITE_ROOM_MIN_DISTANCE_FROM_START`(既定25マス)以上離れた部屋の中から、
    渡された`rng`によるFisher-Yatesシャッフルでランダムに指定する(`Array.shuffle()`は
    グローバルRNGに依存し再現性が壊れるため使わず、手動シャッフルにした)
  - `DungeonMap`に`elite_room_indices`(精鋭部屋の添字一覧)と`pillar_pair_room_index`
    (各出入り口ペアがどの部屋に属するか)を追加。新規`systems/elite_room_manager.gd`が
    各精鋭部屋にArea2Dを設置し、プレイヤーの入室を検知する
  - 入室すると、その部屋の出入り口(`pillar_pair_room_index`で特定)の開口部に
    通行不可のStaticBody2D(InvisibleWall)を並べて一時的に封鎖し、
    `EventBus.elite_room_entered`を発火。`WaveSpawner`はこれを購読し、精鋭部屋の
    攻略中だけ通常の雑魚湧きを止める(疎結合を保つためWaveSpawnerを直接参照しない)
  - Elite Orc/Werebear/Armored Skeleton/Greatsword Skeletonの中から1〜2体を、
    `EnemyBasic`に追加した`elite_stat_multiplier`(1.8〜2.2倍、実行時にHP・接触ダメージへ
    乗算)と`visual_scale_multiplier`(1.3倍、AnimatedSprite2D.scaleにのみ乗算し
    当たり判定は変えない)を設定して出現させる
  - 全滅させると封鎖を解除し、`EventBus.elite_room_cleared`を発火(WaveSpawner再開)、
    欠片1個確定ドロップ+メタ通貨ボーナス(既定50)を付与し、`VFXPoolManager`の
    既存パーティクルプールと`ScreenEffects`の画面シェイク+金色フラッシュを重ねた
    報酬演出を再生する
  - Godotをヘッドレス実行して実際に確認: `elite_room_count=1/2`それぞれで指定数通りの
    部屋が選ばれ、選ばれた部屋はすべてスタートから閾値(25マス)以上離れていること、
    `elite_stat_multiplier=2.0`適用時にHP55→110・接触ダメージ12→24と正確に倍化される
    こと、実際に精鋭部屋へ入室すると出入り口に10枚のバリアが設置され
    `WaveSpawner._active_elite_rooms`が1になり通常湧きが止まること、出現した
    Greatsword Skeleton(HP2.14倍)を倒すとバリアが解除され`_active_elite_rooms`が0に
    戻り、欠片所持数+1・メタ通貨+50(既定値通り)が加算されること、クリア済みの部屋に
    再入室しても敵が二重に湧かないことを確認済み

- **弾の見た目をArrow画像に差し替え + 武器属性ごとの演出差別化**:
  > 以下は変更当時の履歴であり、途中で導入した氷Slow・雷の毎Hitジグザグ線・強いGlowは、
  > 後続の「矢のグロー縮小・演出の簡略化」で撤去または減光済み。さらに現行は主属性が雷の
  > 場合だけArrow/Glowを電撃弾へ置換する。現行値は仕様書25章・28章を参照。
  1. `entities/projectiles/projectile.tscn`の`Visual`ノードを、仮図形だった
     オレンジのPolygon2Dから`assets/sprites/projectile/Arrow01(32x32).png`を使う
     Sprite2D(scale=0.5)に差し替えた。画像を実際に切り出して確認したところ矢尻
     (羽根)が左、鏃(切っ先)が右にある絵柄だったため、既存の
     `rotation = _velocity.angle()`(0=+X方向)とそのまま向きが一致し、
     回転ロジックの変更は不要だった
  2. 武器属性(炎/氷/雷)の演出差別化について、まず`effects/effect_theme_manager.gd`
     (`EffectThemeData`ベースの既存の属性別VFXディスパッチャ、`Projectile.on_hit`から
     既に`vfx_theme_id`付きで呼び出される仕組み)を調査した結果、要求の大部分は
     既に実装済みだったことが判明した: 炎はオレンジ〜赤系の色+爆発的な円形バースト
     パーティクル(`fire_hit.tscn`、explosiveness=1.0)が既にあり、氷も水色〜白の色+
     被弾時`apply_effect("slow", 1.5)`によるスロウ付与が既に実装されていた。
     一方で**雷だけ`hit_color`が氷とほぼ同じ薄い水色になっているバグ**があり、
     しかもこの2属性(炎+氷=蒸気、炎+雷=雷炎)しか実際の合成武器レシピが
     存在しないため、唯一体験できる2種類の合成武器の見た目がほとんど区別できない
     状態になっていた(これが「差が感じられない」の主因と判断)。そのため
     新規に`play_hit_effect`のような並行システムを追加するのではなく
     (二重にパーティクルが発生する不具合を避けるため)、既存の仕組みの中で
     以下を修正した:
     - `effects/themes/lightning.tres`の`hit_color`を黄色`(1,0.92,0.25)`、
       `enhanced_color`を紫`(0.72,0.35,1)`に変更(`lightning_hit.tscn`/
       `lightning_hit_enhanced.tscn`のパーティクル色も合わせて変更)
     - `EffectThemeData`に`is_zigzag_bolt`フラグを追加し、雷のみtrueに設定。
       `EffectThemeManager`に`_spawn_zigzag_bolt()`を追加し、強化演出(連鎖)の
       有無に関わらず、雷属性のヒット時は毎回、着弾点へジグザグに折れ曲がる
       稲妻のLine2D(5segment、着弾点の少し上から一瞬表示してフェードアウト)を
       表示するようにした
  - Godotをヘッドレス実行して実際に確認: Projectileを右方向・下方向へ発射した際の
    `rotation`がそれぞれ0度・90度になり画像の向きと一致すること、fire/ice/lightning
    各テーマの色が実際に意図した値(炎=オレンジ系、氷=水色系、雷=黄色/紫系)に
    なっていること、雷属性のヒットで実際にLine2D(ジグザグの点列、黄色)が生成される
    こと、氷属性の`apply_effect("slow", 1.5)`で`slow_multiplier`が実際に0.5に
    変化することを確認済み

- **属性演出の実装を実際の物理衝突で再検証 + 矢にグロー(発光)を追加**:
  前回の修正(雷の色変更)だけでは不十分とのご指摘を受け、まず「本当に
  `on_hit()`からの呼び出しが漏れていないか」を、直接メソッドを呼ぶのではなく
  **実際にProjectileと敵のHurtboxComponentをAreaオーバーラップさせ、物理フレームを
  進めて衝突判定を発生させる**形でheadless再検証した。結果、炎(GPUParticles2D生成)・
  氷(StatusEffectComponent.has_effect("slow")=true, slow_multiplier=0.5)・
  雷(Line2Dのジグザグ生成)のいずれも、`HurtboxComponent._on_area_entered`→
  `HitboxComponent.on_hit`→`EffectThemeManager.play_weapon_hit`という実際の
  呼び出し経路で正しく発火していることを確認した。合わせて、以下の点が
  「差が感じられない」の一因になっていたと考えられる:
  - 現状の合成武器レシピが`steam_burst_weapon`(炎+氷)と`thunder_flame_weapon`
    (炎+雷)の2種類のみで、**どちらも「炎」が共通コンポーネントとして必ず
    再生される**ため、目立つ炎の爆発演出が常に主役になり、もう片方の属性
    (氷のスロウ/雷の稲妻)が相対的に見落とされやすくなっていた
  - 雷のジグザグ稲妻(Line2D)は幅3px・表示0.18秒と、炎の爆発パーティクルに
    比べて薄く短命だったため、幅4.5px・表示0.3秒に強調した
  - 矢自体(Polygon2D→Sprite2D化した弾)が薄暗い背景の上で見えにくいという
    別の問題も合わせてご指摘いただいたため、`projectile.tscn`に`GradientTexture2D`
    (中心が白・外側が透明な放射状グラデーション)を使った`Glow`という
    Sprite2Dを矢の絵柄(`Visual`)の背後に追加し、`CanvasItemMaterial`の
    `blend_mode`を加算(ADD)に設定した。`Projectile.launch()`で
    `weapon_data.vfx_theme_id`から`EffectThemeData.hit_color`を引いて
    このグローの`modulate`に適用し(炎=オレンジ、氷=水色、雷=黄色、
    テーマが無い武器は控えめな白)、属性が一目でわかる色付きの光を
    矢に纏わせるようにした
  - Godotをヘッドレス実行して実際の物理衝突で再確認: Glowノードが
    `Visual`より背面(get_index順)にあり`blend_mode=1`(加算)であること、
    炎/氷/雷それぞれの発射直後に`Glow.modulate`が意図した色
    (オレンジ/水色/黄色、アルファ0.6)になっていること、テーマの無い
    武器では控えめな白グロー(アルファ0.35)にフォールバックすること、
    そのうえで炎=パーティクル生成・氷=スロウ付与(slow_multiplier=0.5)・
    雷=Line2D生成(width=4.5)がすべて実際の当たり判定を通じて発生することを
    確認済み

- **レベルアップの選択肢を「通常強化オプション」中心に作り替え + 矢のグロー縮小・演出の簡略化**:
  1. `data/upgrades/`を新設し、`resources/upgrade_data.gd`(id/display_name/
     effect_type/value)経由でDataLoaderが読み込む形で4種類の強化オプションを追加した:
     `damage_up`(攻撃力+15%、重ね掛け可)・`multishot_chance_up`(追加の矢+10%、
     重ね掛け可、上限50%)・`crit_rate_up`(会心率+8%、重ね掛け可)・
     `homing_upgrade`(ホーミング強度+0.2、重ね掛け可、上限1.0)
  2. 新規`components/player_upgrades_component.gd`(`PlayerUpgradesComponent`)を
     `Player`の子コンポーネントとして追加し、選択した強化の蓄積値
     (damage_multiplier/multishot_chance/crit_rate_bonus/homing_strength)を保持する。
     `WeaponManagerComponent.spawn_projectile()`がこれを`Projectile.launch()`へ渡し、
     ダメージ計算(`StatModifierComponent`によるレベル成長とは独立に乗算)・
     クリティカル判定(crit_chanceへ加算)に反映されるようにした。`multishot_chance`は
     発射のたびに抽選し、当たった場合は角度を18度ずらしたもう1本を追加発射する
     (完全に重なって見えないように)。`homing_strength`はProjectileの新規
     `_apply_homing()`で毎フレーム`Vector2.slerp`により速度ベクトルを最も近い敵の
     方向へ滑らかに旋回させる形で実装した
  3. `level_up_select.gd`を書き換え、レベルアップ回数をカウントするようにした。
     通常は`DataLoader.get_all_upgrades()`から3つをランダム提示し、選択すると
     `PlayerUpgradesComponent.apply_upgrade()`が呼ばれる。4回に1回
     (`FRAGMENT_OFFER_INTERVAL`)だけ、3枠のうち1枠を属性の欠片の選択肢に
     置き換える(従来通り`GameManager.add_fragment`を呼ぶ)。欠片の枠がどの位置に
     出るかは毎回シャッフルしている
  4. 前回追加した矢のグローが目立ちすぎるとのご指摘を受け、`GradientTexture2D`の
     サイズを48x48→24x24に、不透明度を属性テーマ有り0.6→0.3・テーマ無し
     (中立色)0.35→0.18に、それぞれ縮小・減光した
  5. 炎/氷/雷の着弾演出のうち、表示の確認が難しかった実装(氷の`slow`状態異常付与、
     雷のジグザグLine2D)を、ユーザー指示に従い無理に追わず撤去した。
     `EffectThemeData`側の状態異常・強化条件の仕組み自体(`status_effect`/
     `enhanced_requires_status`)は将来の再利用のため残し、`ice.tres`の該当値だけを
     空に戻した。雷は`is_zigzag_bolt`フラグと`_spawn_zigzag_bolt()`を丸ごと削除し、
     以前から安定していた色付きパーティクル(fire_hit/ice_hit/lightning_hit)による
     着弾表現に一本化した(強化演出時の連鎖稲妻`is_chain`は元々安定していたため維持)
  - Godotをヘッドレス実行して実際に確認: 4種の強化オプションがJSONから正しく
    読み込まれること、`apply_upgrade`を重ね掛けした際に`damage_multiplier`=1.30・
    `multishot_chance`が上限0.50でクリップ・`crit_rate_bonus`=0.08・
    `homing_strength`が上限1.00でクリップされること、`_build_choices()`が
    レベルアップ1〜3回目は欠片0枚・4回目と8回目は欠片1枚を含む3択になること、
    欠片選択で実際に`held_fragment_ids`が増えること、`damage_multiplier`/
    `crit_rate_bonus`を設定したProjectileの`launch()`実行結果が期待値通り
    (10×1.3×crit2.0=26.0)になること、`multishot_chance=1.0`で実際に
    `WeaponManagerComponent.spawn_projectile()`を呼ぶと2本のProjectileが
    生成されること、`homing_strength=1.0`で発射直後は敵方向と90度ずれていた
    軌道が物理フレーム10回後には25度まで縮まること、Glowのテクスチャサイズが
    実際に24x24・既定アルファ0.25になっていること、簡略化後も炎/氷/雷それぞれの
    実際の物理衝突でGPUParticles2Dが1個ずつ生成される一方、氷のslow付与と
    雷のLine2Dはどちらも発生しなくなっていることを確認済み

- **レベルアップの選択肢を「強化3つ+属性3つ=常に6択」へ変更**:
  前回実装した「4回に1回だけ欠片が混ざる」ロジックを撤廃し、`level_up_select.gd`を
  毎回「通常強化オプション3つ+属性(欠片)オプション3つ」の6択を同時に提示する
  形に書き換えた。
  - 強化オプション3つは従来通り`DataLoader.get_all_upgrades()`からランダムに選ぶ
  - 属性オプション3つは、`AVAILABLE_FRAGMENT_IDS`のようなハードコードした配列では
    なく`DataLoader.fragments`(data/fragments/*.jsonから動的読込)からランダムに
    選ぶよう実装した。現状は3属性(fire/ice/lightning)しか無いため実質毎回
    全属性が出る形になるが、`mini(FRAGMENT_SLOT_COUNT, fragment_ids.size())`で
    件数を絞っているため、将来4属性目以降を追加してもそのまま「ランダムに3つ」に
    切り替わる(コード変更不要)
  - UIは`level_up_select.tscn`の`VBoxContainer`を`GridContainer`(columns=2)に
    差し替え、強化(偶数列)と属性(奇数列)が交互に並ぶことで列単位でも
    視覚的にグルーピングされるようにした
  - 種類の区別は、`StyleBoxFlat`をボタンの`normal`/`hover`/`pressed`/`focus`
    テーマへ上書きする形で実装: 強化オプションは青系の枠色固定、属性オプションは
    `DataLoader.effect_themes[fragment.element].hit_color`(炎=オレンジ、
    氷=水色、雷=黄色)をそのまま枠色に使うことで、既存の属性演出の色と統一した
    (対応するテーマが無い属性が将来追加された場合は既定のグレー枠にフォールバック)
  - Godotをヘッドレス実行して実際に確認: `_build_choices()`が毎回必ず
    合計6件(強化3・属性3)を返すこと、属性側の枠色が実際の`EffectThemeData.hit_color`
    と一致すること、`EventBus.player_leveled_up`発火で実際に`GridContainer`へ
    6個のボタンが生成され、それぞれ意図した枠色を持つこと、強化を選ぶと
    `PlayerUpgradesComponent`の該当値が実際に増えること(例: homing_upgradeで
    0.00→0.20)、属性を選ぶと`GameManager.held_fragment_ids`に選んだ欠片IDが
    実際に追加されることを確認済み

- **レベルアップを2段階選択に変更 + ボスキャラクターを実装**:
  1. `level_up_select.gd`を「6択から1つ」から「ステップ1(強化3択→1つ)→
     ステップ2(属性3択→1つ)」の2段階選択に書き換えた。ステップ1を選ぶと
     `PlayerUpgradesComponent`に即時反映されつつ、ゲームは一時停止したままステップ2
     (属性/欠片3択)に自動で進み、選び終えて初めて`get_tree().paused = false`で
     ゲームに戻る。UIには「(1/2)」「(2/2)」の見出しラベルを追加した
  2. ボスキャラクターを追加した。ただし**`assets/sprites/boss/`フォルダは
     プロジェクト内に存在せず**(`enemy/`・`player/`フォルダのみ確認できた)、
     指定されたBlack Knight/Demon/Flame Golem/Minotaurのスプライトも見つからな
     かった。データ・ロジック層は指定されたsprite_folderパス(例:
     `boss/Black Knight_A`)のままで完成させてあり、実際に画像ファイルを
     配置していただければ即座に表示されるようになっている(`SpriteSheetBuilder`は
     フォルダが見つからない場合nullを返すだけで安全に動作するため、現状は
     見た目だけプレースホルダのままボスの当たり判定・戦闘自体は機能する)
     - `resources/boss_data.gd`(`BossData`)は`EnemyData`を継承する設計にし、
       既存の`EnemyBasic`(移動・ダメージ計算・SpriteSheetBuilder読込ロジック)を
       改修せずにそのまま流用できるようにした
     - `data/bosses/`に10体分のJSON(黒騎士A/B/C・デーモンA〜E・
       フレイムゴーレム・ミノタウロス)を作成。HPは通常雑魚(`basic_enemy`
       max_hp=20)の15〜25倍(300〜500)、接触ダメージは42〜55、移動速度は
       ボスごとに変化を付けた(フレイムゴーレムが最も遅く最もHPが高い、
       ミノタウロスが最速、等)。表示スケール(`visual_scale`)も2.0〜2.5倍と
       通常個体よりはっきり大きくした
     - 新規`systems/boss_spawner.gd`: `GameManager.elapsed_seconds`を監視し、
       `min_interval_seconds`〜`max_interval_seconds`(既定180〜300秒=3〜5分)の
       ランダムな間隔でボスを1体抽選・出現させる。出現位置は`WaveSpawner`と同じ
       「`DungeonMap`の床マスから選ぶ」方式を踏襲し、壁の中に出現しないようにした
     - **ユーザーからの回答が無かった3点は以下の既定値で実装した(いつでも
       変更可能です)**: (a) 撃破報酬は精鋭部屋(EliteRoomManager)と同じ形
       (欠片1つ確定+メタ通貨ボーナス、既定150)にし、演出だけ赤みがかった
       フラッシュにして精鋭部屋の金色フラッシュと区別、(b) ボス出現中は
       `EventBus.boss_fight_started/ended`経由で`WaveSpawner`の通常湧きを停止
       (精鋭部屋と同じ仕組みを流用)、(c) HUDに専用のボスHPバー(画面上部中央、
       名前+HPゲージ)を追加した
  - Godotをヘッドレス実行して実際に確認: 2段階選択UIで実際にステップ1選択後も
    `visible`/`paused`がtrueのまま維持されステップ2へ自動遷移すること、両方選び
    終えて初めて`visible=false`・`paused=false`になること、ボスデータ10体すべてが
    `EnemyData`型として読み込め(継承確認)HP倍率が15.0〜25.0倍の範囲に収まって
    いること、実際に`BossSpawner._spawn_boss()`を呼ぶとHUDのボスHPバーが表示され
    `WaveSpawner._boss_fight_active`がtrueになること、表示スケールが実際に
    通常の1.0倍より大きく適用されること、ボスを撃破すると`WaveSpawner`の湧きが
    再開しHPバーが非表示になり、欠片とメタ通貨(差分150、既定値通り)が実際に
    付与され、次回出現時刻が再抽選されることを確認済み

- **ボス撃破報酬に「常時ステータス上昇アイテム」を追加**:
  `data/items/`を新設し、`resources/item_data.gd`(id/display_name/effect_type/value)
  経由でDataLoaderが読み込む形で6種類のアイテムを追加した: `vitality_ring`
  (最大HP+20)・`swift_boots`(移動速度+15%)・`power_gauntlet`(攻撃力+20%、
  data/upgrades/のdamage_upと同じeffect_typeを再利用)・`quick_hands`(攻撃間隔
  -10%短縮)・`lucky_charm`(会心率+10%、crit_rate_upを再利用)・`sturdy_shield`
  (被ダメージ-15%)。
  - `PlayerUpgradesComponent`に`move_speed_multiplier`・`max_hp_bonus`・
    `attack_interval_multiplier`・`damage_taken_multiplier`を追加し、新規
    `apply_item(ItemData)`で反映する。反映方法は2通り: (a) `damage_up`/
    `crit_rate_up`は既存のレベルアップ強化と同じ蓄積値にそのまま合算、
    (b) `max_hp_bonus`は取得した瞬間に`HealthComponent.max_hp`/`current_hp`へ
    差分加算(増えた分だけその場で回復もする一般的なローグライク仕様)、
    `move_speed_multiplier`は`MovementComponent`に新設した
    `bonus_speed_multiplier`フィールドへ、`damage_taken_multiplier`は
    `HealthComponent`に新設した同名フィールドへ、それぞれ「現在の蓄積合計」を
    都度セット(べき等)する形で同期する
  - `MovementComponent.get_velocity()`は`direction * base_speed * speed_multiplier
    * bonus_speed_multiplier`(状態異常由来の一時倍率とアイテム由来の永続倍率を
    別フィールドで分離し、掛け合わせる)に変更
  - `HealthComponent.apply_damage()`は`amount * damage_taken_multiplier`を実際の
    減少量として使うように変更(Enemy側は誰も同期しないため既定の1.0のままで影響なし)
  - `WeaponManagerComponent`に`get_attack_interval_multiplier()`を追加し、
    `WeaponInstance.tick()`のクールダウン再設定時に`data.attack_interval`へ
    掛けるようにした
  - `BossSpawner._grant_rewards()`にアイテム抽選処理を追加。ボスを倒すたびに
    `data/items/`からランダムに1つ選び、プレイヤーの`PlayerUpgradesComponent`へ
    即座に適用し、新規`EventBus.item_acquired`シグナルを発火する。同じアイテムを
    再取得した場合はそのまま重ね掛けされる
  - `EventBus.item_acquired`をHUDが購読し、(a) 欠片表示(`fragment_row`)とは別の
    `item_row`に獲得済みアイテムの一覧をテキストラベルで積み上げ表示、(b) 画面上部に
    「アイテム獲得: ○○」という文字がフェードイン→約1.8秒表示→フェードアウトする
    ポップアップ演出(Tween制御、アイコンは今回もテキストラベルで代用)を追加した
  - Godotをヘッドレス実行して実際に確認: 6種のアイテムがすべて意図した
    effect_type/valueで読み込まれること、実際のPlayerシーンに対して
    `vitality_ring`を2回適用するとmax_hp/current_hpが実際に100→140へ変化する
    こと(重ね掛け確認)、`swift_boots`適用後の実際の移動速度が140→161に
    なること、`quick_hands`適用後に`WeaponManagerComponent.get_attack_interval_multiplier()`
    が0.90を返し`WeaponInstance.tick()`の実際のクールダウンも0.90秒になること、
    `sturdy_shield`適用後に実際に100ダメージを与えると85しか減らないこと、
    ボスを実際に撃破すると`item_acquired`シグナルが発火してHUDの`item_row`に
    要素が1つ増え、メタ通貨も既定通り+150されることを確認済み

- **ボスをもっと目立たせる + ボス撃破後の戦利品を3択選択式に変更**:
  1. `data/bosses/*.json`の`visual_scale`を全体的に引き上げ(2.0〜2.5倍→
     2.2〜3.0倍、フレイムゴーレムが最大の3.0倍)、全ボスが「通常敵の2倍以上」を
     満たすようにした
  2. 新規`effects/shaders/sprite_outline.gdshader`(透明ピクセルの周囲8方向を
     サンプリングし、隣接する不透明ピクセルがあれば指定色で塗る一般的な
     スプライト用アウトラインシェーダー)を作成し、`EnemyBasic._ready()`で
     `enemy_data is BossData`の場合だけ`AnimatedSprite2D.material`へ赤色
     (`Color(0.9,0.05,0.05)`)で適用するようにした。通常個体・精鋭個体には
     適用されない
  3. `BossSpawner._spawn_boss()`に出現演出を追加: HPバー表示に加え、不穏な
     暗い赤のフラッシュ(撃破時の明るい赤フラッシュとは色を分けている)と
     `ScreenEffects.hit_stop(0.3)`(実時間ベースなのでtime_scaleが下がって
     いてもきちんと0.3秒分止まる)を発火するようにした
  4. ボスHPバーの表示/非表示自体は前回実装済みのものを再検証(出現時に表示・
     撃破時に非表示になることを実際に確認)
  5. ボス撃破時の戦利品を「ランダム自動付与」から「3択選択式」に変更した。
     `resources/item_data.gd`に`is_special`フラグを追加し(現状の6種はすべて
     false、将来の「特別アイテム」追加に備えた優先枠)、新規
     `ui/item_select/`(`level_up_select`と同じ構成・スタイルの3択UI、
     金色系の枠で強化オプション(青)・属性(各色)とは別の「戦利品」だと
     分かるようにした)を作成。`BossSpawner._build_item_candidates()`が
     `is_special`アイテムを優先しつつdata/items/から3件の候補を組み立て、
     `ItemSelect.show_choices()`へ渡す。選ぶまでゲームは一時停止したままで、
     選択後の適用(`PlayerUpgradesComponent.apply_item`)と
     `EventBus.item_acquired`発火は`ItemSelect`側で行う(HUDのポップアップ/
     一覧表示は変更なしでそのまま動作する)
  - Godotをヘッドレス実行して実際に確認: 全10体のボスが`visual_scale>=2.2`を
    満たすこと、通常敵の`animated_sprite.material`は`null`のままボスだけ
    `ShaderMaterial`(outline_color=赤)が設定されること、**シェーダーの
    `fragment()`内で`return`を使っていたために実際にコンパイルエラーが
    発生するバグを検証中に発見し、if/else構造に書き直して修正**したこと、
    ボス出現直後に`Engine.time_scale`が実際に0.05まで下がりヒットストップが
    かかること、時間経過後に1.0へ戻ること、ボスHPバーが出現時に表示され撃破時に
    非表示へ戻ること、ボスを実際に撃破すると`ItemSelect`が正確に3択
    (このテストでは「頑丈な盾」「幸運のお守り」「早業の手袋」)を提示して
    ゲームが一時停止すること、1つ選ぶとその項目に対応するステータス(例:
    `sturdy_shield`選択で`HealthComponent.damage_taken_multiplier`だけが
    1.00→0.85に変化し、他のステータスは一切変化しないこと)だけが正確に
    反映されてUIが閉じ一時停止が解除されることを確認済み

- **敵出現の時間帯制限(序盤の理不尽即死対策)**: 開始直後からElite Orc/Werebear/
  Greatsword Skeletonのような強敵が雑魚と同確率で出現し、1〜2分で倒されてしまう
  問題への対応。
  1. `resources/enemy_data.gd`に`min_elapsed_seconds: float`(既定0.0)を追加し、
     `autoload/data_loader.gd`の`_load_enemies()`がJSONから読み込むようにした
  2. `data/enemies/`配下の12体全JSONを3段階に設定: 0秒〜(`basic_enemy`/
     `fast_enemy`/`bat`/`slime`)、90秒〜(`armored_orc`/`armored_skeleton`/
     `skeleton_archer`)、180秒〜(`elite_orc`/`werebear`/`greatsword_skeleton`/
     `orc_rider`/`werewolf`)。ユーザー指定例のうちHellbat/Lava Slime/Hellhound/
     Demoness系はこのプロジェクトに実際のスプライト素材が存在しないため、
     架空の敵を新設せず対象から除外した
  3. `systems/wave_spawner.gd`に`_get_eligible_enemy_data()`を追加し、
     `GameManager.elapsed_seconds >= min_elapsed_seconds`を満たす敵だけを
     スポーン候補にした。経過時間はラン中ずっと増え続けるため、`_ready()`時に
     一度だけ絞り込むのではなく毎回のスポーン試行時に都度フィルタし直す
     (該当が1体もない場合はその回のスポーンをスキップする)
  4. `data/characters/`のうち100未満だった4職業(`wizard`70→100、
     `necromancer`75→100、`archer`80→100、`priest`90→100)の`max_hp`を
     引き上げ、全10職業が100以上になるようにした(他6職業は元々100以上のため
     変更なし)
  5. 精鋭部屋(Elite Room)のスタート地点除外ロジック(`dungeon_generator.gd`の
     `ELITE_ROOM_MIN_DISTANCE_FROM_START`=25マス)を再確認したところ既に実装・
     機能済みだったため、コード変更は行わず動作の再検証のみ実施した
  - Godotをヘッドレス実行して実際に確認: 12体全敵の`min_elapsed_seconds`が
    意図通りの値で読み込まれること、実際の`WaveSpawner._get_eligible_enemy_data()`
    呼び出しが`GameManager.elapsed_seconds`を0秒/89秒/90秒/179秒/180秒に
    切り替えるたびに候補数が4→4→7→7→12体と段階的に増えていくこと(90秒到達で
    中堅3体、180秒到達で強敵5体が追加され、それ以前は候補に含まれないこと)、
    序盤(t=0)でも候補が空にならずスポーンが止まらないこと、10職業全ての
    `max_hp`が100以上であること、実際に`DungeonGenerator.generate()`を
    シード固定で実行し選ばれた精鋭部屋がすべてスタート地点(部屋インデックス0)
    から25マス以上離れていること(実測27.1マス/30.4マス)を確認済み

- **ボスをさらに大きく + 当たり判定ズレの修正、ボス撃破後アイテム選択の再検証**:
  1. `data/bosses/*.json`の`visual_scale`を全10体とも2.9〜3.6(通常敵比おおよそ3倍)に
     引き上げた(従来は2.2〜3.0)
  2. **重大なバグを発見・修正**: `EnemyBasic._ready()`は`visual_scale_multiplier`を
     `AnimatedSprite2D.scale`にしか乗算しておらず、`HurtboxComponent`(被弾判定)・
     `ContactHitbox`(接触与ダメージ判定)・本体の移動用`CollisionShape2D`の
     当たり判定サイズは常に通常敵と同じ28x28/半径14のまま据え置きだった
     (`boss_data.gd`/`elite_room_manager.gd`のコード上のコメントにもその旨が
     明記されていた)。見た目だけ3倍近く大きいのに当たり判定は変わらないため、
     「見た目通りに攻撃が当たらない/外れる」ズレが実際に発生する状態だった。
     `EnemyBasic`に`_scale_collision_shapes()`を追加し、`visual_scale_multiplier`が
     1.0でない場合に本体・被弾・接触ダメージの3つの`CollisionShape2D`すべてへ
     同じ倍率を適用するようにした(`.tscn`内の`[sub_resource]`は
     `instantiate()`ごとに複製される仕様だが、念のため`duplicate()`してから
     書き換え、他個体への影響を確実に防いでいる)。これはボスだけでなく
     精鋭部屋(Elite Room, `elite_visual_scale=1.3`)の敵にも同じコード経路で
     適用されるため、両方とも見た目と判定が一致するようになった
  3. 「ボス撃破後にアイテム選択UIが出ない」という報告を受け、`BossSpawner`の
     `HealthComponent.died`接続・`game.tscn`への`ItemSelect`ノード実装・
     `ItemSelect.show_choices()`呼び出し経路をすべて再確認したところ、
     コード上の配線自体に欠陥は見つからなかった。実際にGodotを
     ヘッドレス実行し、`_spawn_boss()`をタイマー経由の自然な発火(直接呼び出し
     ではなく`_process()`の通常経路)で待たせ、実際のボスに対して本物の
     `HitboxComponent`(プレイヤーの攻撃と同じ`collision_layer=32`)を
     繰り返し重ねてArea2D物理衝突を実際に発生させて撃破するところまで
     シミュレートしたところ、ボスは実際に(9発の命中で)撃破され、
     `ItemSelect`が実際に表示され3択(このテストでは「頑丈な盾」「剛力の籠手」
     「俊足のブーツ」)が正しく提示され、ゲームが一時停止することを確認できた
     (=配線自体は正しく機能している)。ボスの見た目とほぼ同時に修正した
     当たり判定ズレ(2番目の項目)が、体感的に「攻撃が当たらず倒せない」原因
     だった可能性が高いため、根本原因はそちらで解消したと考えられる
  - Godotをヘッドレス実行して実際に確認: 全10体のボスの`visual_scale`が
    2.8以上であること、`visual_scale_multiplier=3.0`を実際に適用した
    `EnemyBasic`インスタンスで本体の当たり判定半径が14→42、被弾/接触判定の
    サイズが28x28→84x84へ正確に3倍スケールされること、別インスタンス
    (`visual_scale_multiplier=1.0`)の当たり判定サイズがそのスケーリングの
    影響を一切受けず14のまま変化しないこと(共有リソース汚染が無いことの
    確認)、実際の`game.tscn`をタイマーの自然な経過で待たせて出現した
    ボス(デーモンC、当たり判定サイズが実測28x28→86.8x86.8に拡大済み)に
    対して実際のHitboxComponentを使った物理衝突を9回重ねて実際に撃破し、
    `ItemSelect`が正確に3択を提示してゲームが一時停止することを確認済み

- **レベルアップの選択肢を「強化3つ+属性3つ=6択同時提示」に変更**(2段階選択・
  4回に1回だけ欠片が混ざる方式は廃止):
  1. `ui/level_up_select/level_up_select.gd`から`Step`(UPGRADE/FRAGMENT)による
     2段階選択ロジックを撤廃し、レベルアップの度に`data/upgrades/`からランダム3つ
     (通常強化)と`DataLoader.fragments`からランダム3つ(属性欠片。現状fire/ice/
     lightningの3属性しか無いため実質毎回全属性が出るが、ハードコードした配列に
     依存しない実装のため、将来4属性目以降が追加されても常に3つへ絞られる)を
     同時に組み立てて1画面に並べ、いずれか1つを選んだ時点で即座にその効果
     (強化適用 or 欠片獲得)が反映されて画面が閉じ、一時停止が解除されるように
     変更した
  2. `level_up_select.tscn`の`GridContainer`を`columns=3`(横一列)から
     `columns=2`(2列×3行)に変更。強化3件・属性3件を1件ずつ交互(強化→属性→
     強化→属性→強化→属性)に追加することで、左列=強化・右列=属性という
     視覚的なグループ分けになるようにした。枠色による区別(強化=青系固定色、
     属性=対応する`EffectThemeData.hit_color`)は既存のスタイルをそのまま流用
  - Godotをヘッドレス実行して実際に確認: 実際の`game.tscn`に対して
    `EventBus.player_leveled_up`を実際に発火させると、毎回必ず6択
    (強化3件+属性3件、列数2)が同時に表示されること、強化の選択肢を実際に
    タップすると該当する`PlayerUpgradesComponent`の数値だけが正しく変化し
    (`damage_up`選択で`damage_multiplier`が1.0→1.15)UIが閉じ一時停止が
    解除されること、属性の選択肢を実際にタップすると`GameManager.add_fragment()`
    経由で選んだ属性IDだけが実際に`held_fragment_ids`へ加わりUIが閉じ
    一時停止が解除されること、`DataLoader.fragments`に実際にテスト用の
    架空属性2件を追加して合計5属性にした状態でもう一度レベルアップを
    発火させても、属性の選択肢は常にちょうど3件に絞られること
    (4種類以上でも壊れずスケールすることの実証)を確認済み

- **ボス出現ロジックの見直し(固定間隔化)+レベルアップの2段階選択への差し戻し+
  レベルアップ時HP全回復**:
  1. `systems/boss_spawner.gd`のボス出現を「3〜5分のランダム間隔」から
     「ラン開始と同時に1体目、以降は`boss_interval_seconds`(既定90秒)ごとに
     1体ずつ」という固定スケジュールに変更した。`_boss_spawn_count`(出現済み数)
     と`elapsed_seconds >= _boss_spawn_count * boss_interval_seconds`の比較で
     毎フレーム次回のしきい値を再計算する方式にし、乱数のロールし忘れによる
     ズレが起こらないようにした
  2. 「ボスが全く出現しない」という報告を受けてGodotを実際にヘッドレス起動し、
     `--fixed-fps 60`(実時間に依存せず1フレーム=1/60秒を保証)で実際の
     `game.tscn`を約100秒分、`_process(delta)`を毎フレーム本物に呼ばせて
     進行させたところ、**修正前のコード自体に欠陥は無かった**(旧: 3〜5分の
     ランダム待ちなので単に「まだ出現していないだけ」だった可能性が高い)。
     新しい固定間隔ロジックでも同じ方法で再検証している
  3. 前回「強化3択→属性3択」の2段階選択から「6択同時提示」へ変更していたが、
     今回の指示で2段階選択に差し戻した。`ui/level_up_select/level_up_select.gd`に
     `Step`(UPGRADE→FRAGMENT)ロジックを復元し、`level_up_select.tscn`の
     `GridContainer`も`columns=2`→`columns=3`に戻した
  4. `entities/player/player.gd`が`EventBus.player_leveled_up`を購読し、
     レベルアップの瞬間に`HealthComponent.current_hp`を`max_hp`まで即座に
     全回復するようにした(`HealthComponent.damaged`シグナルも合わせて発火させ、
     HUDのHPバー表示もその場で満タンに更新されるようにしている)
  - Godotを`--fixed-fps 60`でヘッドレス実行し、実際の`game.tscn`に対して
    `_process(delta)`を本物のフレーム経過で約90秒分進行させて確認: ラン開始
    直後(elapsed_seconds=0.02)に1体目のボスが実際にシーンツリーへ追加される
    こと、実際の`HitboxComponent`物理衝突で撃破しボス撃破後のアイテム選択も
    実際にクリックして進めた上で、そのままさらにフレームを進めるとちょうど
    elapsed_seconds=90.01で2体目のボスが実際に出現すること、レベルアップを
    実際に発火させると強化3択(1/2)→選択→属性3択(2/2)の順で正しく2段階
    表示され、1段階目を選んだだけではUIも一時停止も解除されず、2段階目を
    選んで初めて閉じて選んだ属性の欠片が実際に1つだけ加わること、プレイヤーの
    HPを意図的に20/100まで減らした状態でレベルアップを発火させると即座に
    100/100へ全回復することを確認済み

- **ボス用スプライト素材(`assets/sprites/boss/`)を実際に配置してもらい、表示を再検証**:
  Black Knight_A/B/C、Demon_A〜E、Flame Golem、Minotaurの計10体分の画像フォルダが
  追加されたのを受けて、`data/bosses/*.json`の`sprite_folder`値(例:
  `"boss/Black Knight_A"`、`"boss/Flame Golem"`)と実際のフォルダ名を全10体分
  突き合わせたところ、**綴り・スペース・アンダースコアともすべて一致しており、
  パス修正は不要だった**(以前ボスが見えなかったのは、今回判明した通り単純に
  画像ファイル自体が存在していなかったことが原因だったと考えられる)。
  Godotを実際にヘッドレス実行し、`SpriteSheetBuilder.build_sprite_frames()`が
  全10体ともidle/walk/attack1〜3/hurt/deathの各アニメーションを実際の
  100x100テクスチャ付きで読み込めることを確認した上で、実際に`EnemyBasic`へ
  各ボスの`enemy_data`/`visual_scale_multiplier`を設定してシーンツリーに
  追加し、`AnimatedSprite2D.sprite_frames`が実際に設定されていること、
  現在再生中のアニメーション("idle")が実在のテクスチャを指していること、
  ボス用の赤い縁取り`ShaderMaterial`も正しく適用されていること、
  `visual_scale_multiplier`(2.9〜3.6倍)が`AnimatedSprite2D.scale`へ
  正確に反映されていることを全10体ぶん確認済み

- **ボスの表示スケールを現状の30%に縮小**: 実際に画像が表示されるようになったところ
  大きすぎたため、`data/bosses/*.json`全10体の`visual_scale`に0.3を掛けた値
  (例: `black_knight_a` 3.0→0.9、`flame_golem` 3.6→1.08。全10体2.9〜3.6→0.87〜1.08)
  に差し替えた。`resources/boss_data.gd`の既定値も3.0→0.9に合わせて更新。
  当たり判定(`HurtboxComponent`/`ContactHitbox`/本体の移動用`CollisionShape2D`)は
  既存の`EnemyBasic._scale_collision_shapes()`が`visual_scale_multiplier`と
  連動して自動でスケールする実装のため、コード変更は不要でJSONの数値変更だけで
  見た目と判定のズレは発生しない。HPバー(`HUD.BossHealthContainer`)は元々
  ボスのワールド座標に追従しない画面固定UI(`anchor_left/right=0.5`の中央上部
  CanvasLayer要素)のため、ボスの表示スケール変更による位置ズレは元々発生しない
  ことを確認した
  - Godotをヘッドレス実行して実際に確認: 全10体の`visual_scale`が0.87〜1.08の
    範囲に収まっていること、`visual_scale_multiplier=0.9`を実際に適用した
    `EnemyBasic`インスタンスで本体の当たり判定半径が14→12.6、被弾/接触判定の
    サイズが28x28→25.2x25.2へ正確に0.9倍スケールされること、実際の`game.tscn`で
    ボスを実際に出現させると`visual_scale_multiplier`(このテストでは
    デーモンAの0.87)が`AnimatedSprite2D.scale`へそのまま反映されること、
    `HUD.BossHealthContainer`が出現時に表示され、`anchor_left/right=0.5`の
    画面固定位置のまま変化していないことを確認済み

- **ボスをもう少し大きく+アイテム選択に効果説明文を表示+
  同時発生モーダルの一時停止バグ修正**:
  1. `data/bosses/*.json`全10体の`visual_scale`に1.2を掛けた値
     (例: `black_knight_a` 0.9→1.08、`flame_golem` 1.08→1.3。全体では
     0.87〜1.08→1.04〜1.3)に更新。当たり判定は既存の
     `_scale_collision_shapes()`が連動するため変更不要。HPバー
     (`HUD.BossHealthContainer`)は前回確認済みの通り画面固定UIのため
     今回も調整不要だった
  2. `resources/item_data.gd`に`description`フィールドを追加し、
     `data/items/`全6種のJSONに効果説明文(例:
     `sturdy_shield`→「被ダメージが15%軽減される」)を追加。
     `ui/item_select/item_select.gd`のボタン生成をBoxContainer+2つの
     Labelによる2行表示(上段=アイテム名、下段=やや小さく薄い色の説明文)に
     変更し、`description`が空のアイテムは`effect_type`/`value`から
     自動的に説明文を生成して補うようにした(該当ラベルは
     `mouse_filter=IGNORE`にしてボタン自体のクリックを妨げないようにしている)
  3. **一時停止の二重解除バグを修正**: `LevelUpSelect`と`ItemSelect`が
     それぞれ個別に`get_tree().paused=true/false`を直接操作していたため、
     ボス撃破のアイテム選択とレベルアップ選択がほぼ同時に発生すると、
     片方が閉じた際にもう片方がまだ開いているのを考慮せず一時停止を
     解除してしまう危険な状態になっていた。`GameManager`に
     `active_modal_count`(開いているモーダルの数)と
     `open_modal()`/`close_modal()`/`request_modal()`を追加し、
     一時停止の設定/解除を必ずこのカウンタ経由に一本化した。
     既に何か開いている間に別のモーダルを表示しようとした場合は
     即座には表示せずキューに積み、先に開いていた方が
     `close_modal()`で閉じてカウントが0に戻った瞬間、キューの先頭を
     取り出して自動的に表示する(2つのモーダルが同時に画面へ
     表示されることは無い)。`LevelUpSelect`/`ItemSelect`とも
     表示開始時に`GameManager.request_modal()`経由で開き、選択完了時に
     `GameManager.close_modal()`を呼ぶように変更した
  - Godotをヘッドレス実行して実際に確認: 全10体のボスの`visual_scale`が
    1.04〜1.3であること、`visual_scale_multiplier=1.08`を実際に適用した
    `EnemyBasic`で当たり判定半径が14→15.12へ正確にスケールされること、
    実際の`ItemSelect`にJSONの`description`を持つアイテムと
    (テスト用に)`description`を空にしたアイテムを同時に渡すと、前者は
    JSON通りの説明文、後者は`effect_type`/`value`から自動生成した
    説明文(「移動速度が25%上昇する」)がそれぞれボタンに正しく
    表示されること、そして本命の検証として、`ItemSelect.show_choices()`と
    `EventBus.player_leveled_up`をほぼ同時(間にawaitを挟まず)に発火させると
    **常にどちらか一方だけが表示され**(このテストでは先に呼んだ
    `ItemSelect`が先に表示)、ゲームが一時停止したままItemSelectの選択を
    完了すると自動的にキューから`LevelUpSelect`(ステップ1)が表示され
    一時停止も維持されたまま、ステップ1を選んでもまだステップ2待ちで
    表示/一時停止とも維持され、ステップ2を選んで初めて両方のUIが
    非表示になり一時停止が解除されて`active_modal_count`が0に戻ることを
    確認済み

- **スマホ向けからSteam(PC)向けへの切り替え**:
  1. `project.godot`の`[display]`を1920x1080(横長)・`window/size/resizable=true`に
     変更し、`window/handheld/orientation`(縦持ち固定設定)を削除。
     `config/features`からも"Mobile"タグを外した
  2. `entities/player/player.gd`の`_input()`からタッチ(`InputEventScreenTouch`/
     `InputEventScreenDrag`)によるドラッグ移動コードを完全に削除し、
     `Input.get_vector("ui_left","ui_right","ui_up","ui_down")`のみに一本化した。
     Godot既定の`ui_*`アクションは矢印キー+ゲームパッド(十字キー/左スティック)は
     最初から登録済みだが、WASDは含まれていなかったため、`GameManager._ready()`に
     `InputMap.action_add_event()`でWASDの物理キーコードを追加登録するようにした
     (project.godotの`[input]`セクションを手書きすると`InputEvent`の
     シリアライズ形式を誤りやすいため、起動時にコードから安全に追加する方式にした)
  3. 広告システムを撤去: `ui/result_screen/`から「広告視聴で報酬2倍」ボタンと
     `AdManager.show_rewarded()`呼び出しを削除し、`project.godot`の`[autoload]`
     から`AdManager`を外した(スクリプトファイル自体は将来の参考用に残置)。
     `SaveManager.add_meta_currency()`自体は元々広告専用ロジックを持たない
     汎用メソッドだったため、変更は不要だった
  4. HUD/ホーム画面を横長向けに調整: `HUD`の情報パネルが画面全幅(1920px)まで
     間延びして表示されていた問題を、左上に固定幅(416px)で収める`MarginContainer`
     配置に変更(ボスHPバーの幅も320→480pxに拡大)。ホーム画面(`HomeScreen`)は
     職業選択ボタンの一覧が画面全幅まで間延びしていたのを、`CenterContainer`+
     固定幅(600px)の`VBoxContainer`で中央寄せに変更した(`ui/home/home.gd`の
     ノードパス参照も追従して更新)。`LevelUpSelect`/`ItemSelect`/`ResultScreen`は
     元々`CenterContainer`ベースでボタンサイズも固定だったため変更不要だった
  - Godotをヘッドレス実行して実際に確認: `ProjectSettings`のビューポートサイズが
    1920x1080でresizable=trueであること、`project.godot`に
    `window/handheld/orientation`の行が実際に残っていないこと、`AdManager`が
    実際に`root.has_node("AdManager")`でfalseになる(autoloadから外れている)こと、
    実際の`game.tscn`に対して本物の`InputEventKey`(WASDのWキー・矢印キーの→キー)を
    `Input.parse_input_event()`で発生させ、`Input.get_vector()`だけでなく
    実際の`Player.movement_component.direction`(プレイヤーの実際の移動方向)が
    正しく更新されることを確認済み。**この検証中、プレイヤーが実際に移動できる
    ようになったことで初めて発覚した既存の不具合**(精鋭部屋(Elite Room)の
    トリガーAreaへプレイヤーが物理的に進入した際、`EliteRoomManager._on_body_entered`
    という物理シグナルコールバックの中で敵を`add_child`し、その`_ready()`内の
    `EnemyBasic._scale_collision_shapes()`が`CollisionShape2D.shape`を同期的に
    書き換えようとして"Can't change this state while flushing queries"という
    物理エンジンのエラーが発生する)を発見した。このエラーはゲームを即座には
    止めないため今回のPC移行の完了を妨げるものではないが、精鋭部屋の敵の当たり判定
    サイズが正しく反映されない可能性があるため、別タスクとして修正が必要

- **ボス固有攻撃パターンの追加(「体力が高いだけの雑魚」から本格的なボス戦へ)**:
  1. `resources/boss_data.gd`に`attack_pattern_id: String`を追加し、
     `data/bosses/`全10体へ見た目・名前から判断して割り当てた:
     `charge`=黒騎士A/デーモンC/ミノタウロス(突進が似合う機動力寄りのボス)、
     `slam`=黒騎士B/デーモンD/フレイムゴーレム(重量級・鈍足のボスに地面叩きつけ)、
     `nova`=黒騎士C/デーモンB(既存アセットにビーム/矢の演出フォルダがあり遠隔攻撃と
     相性が良い)、`summon`=デーモンA/デーモンE(下級デーモンを従える上位デーモン)
  2. 新規`systems/boss_ai/`に、移動用の`EnemyBehaviorStrategy`と対になる「攻撃用」
     Strategy基底クラス`boss_attack_strategy.gd`と、`charge_attack_strategy.gd`/
     `summon_strategy.gd`/`nova_strategy.gd`/`slam_strategy.gd`の4つの具象クラスを
     作成。移動ロジック(AIComponent)とは完全に独立した「攻撃ロジック」として、
     新規`components/boss_attack_component.gd`が一定間隔(interval)ごとに
     `execute()`をawaitで呼び出す構成にした(EnemyBasicがBossData.attack_pattern_id
     を検出した場合のみ動的に生成・アタッチするため、大量に湧く雑魚敵には
     一切オーバーヘッドを追加しない)
  3. 各攻撃の実装: `charge`は`EnemyBasic.set_movement_locked()`を新設して溜め中
     (スプライトを赤く明滅させて予告、既定1.0秒)は通常のプレイヤー追跡移動を
     一時停止し、突進中(0.4秒)はプレイヤー方向への直線移動+接触ダメージ1.8倍
     (`ContactHitbox.damage`を一時的に引き上げ、終了後に必ず元へ戻す)。
     `summon`はWaveSpawnerと同じ`DataLoader.enemies`から雑魚IDをランダムに選び
     周囲へ2〜3体`add_child`。`nova`は既存の`entities/projectiles/projectile.tscn`
     (プレイヤーの武器と同じ弾)をそのまま流用し、`collision_layer`だけ
     プレイヤーの`HurtboxComponent.collision_mask`(16、`ContactHitbox`と同じ)に
     差し替えることで既存の被弾パイプラインをそのまま利用しつつ、円状に12発
     発射(既定0.5秒の予告後)。`slam`は新規`warning_circle.gd`(床に警告円を
     描画するだけの単純なNode2D)をプレイヤーの現在地に既定0.9秒表示した後、
     その時点のプレイヤー座標との距離判定でAoEダメージ(接触ダメージの2.2倍)を
     与える(警告円の外へ逃げていれば無傷)
  - Godotをヘッドレス実行して実際に確認: 全10体の`attack_pattern_id`が意図通り
    読み込まれること、実際に`charge`(黒騎士A)を発動させると溜め中に本当に
    移動がロックされ攻撃状態フラグが立つこと、突進中に実際の
    `ContactHitbox.damage`が45.0→81.0(1.8倍)へ変化し突進後に45.0へ正確に
    戻ること、`summon`(デーモンA)を発動させると実際に`enemies`グループの
    ノード数が2体増えること、`nova`(黒騎士C)を発動させると実際に12発の
    `Projectile`インスタンスが生成され、実際の`collision_layer`が16
    (プレイヤーが被弾する層)になっていること、`slam`(黒騎士B)を発動させると
    実際に警告円が生成され、予告時間経過後に消え、警告円の範囲内にいた
    プレイヤーの実際の`HealthComponent.current_hp`が105.6(接触ダメージ48×2.2倍)
    だけ正確に減っていることを確認済み

- **`game_specification.md` との突き合わせ監査(2026年8月)**: 新設された仕様書
  (`game_specification.md`、これまでの決定事項を集約した「現時点の正」)と
  実際のコード・データを1項目ずつ突き合わせ、以下の4点の相違を修正した
  (ボスの表示スケール・難易度カーブ等、実プレイで調整済みの数値はいずれも
  仕様書側が「現在の実装値を正とする」と明記しているため変更していない):
  1. **ボスの同一ラン内重複出現**: `systems/boss_spawner.gd`が単純な完全ランダム
     抽選で、同じボスが同一ラン中に何度も出現し得る状態だった(仕様書7章は
     「同一ランでの重複出現なし」と明記)。`_spawned_boss_ids`で出現済みidを
     記録し、未出現のボスから優先的に選ぶよう修正。全10体を出現させ切った
     場合は記録をリセットして以降も出現自体は止まらないようにした
  2. **精鋭部屋(Elite Room)の部屋数**: `GameManager.dungeon_elite_room_count`が
     常に固定値1で、仕様書5章の「1〜2部屋」という範囲が実現できていなかった。
     `dungeon_elite_room_count_min/max`(1/2)を追加し、`start_run()`のたびに
     `randi_range()`で決めるよう修正
  3. **ボス撃破時の欠片ドロップ数**: `boss_fragment_reward_count`が常に固定値1で、
     仕様書7章の「欠片1〜2個確定ドロップ」を満たしていなかった(精鋭部屋の
     「欠片1個」は元々仕様通りで変更なし)。`boss_fragment_reward_count_min/max`
     (1/2)を追加し、撃破のたびにランダムに決めるよう修正
  4. **戦利品トレイの重ね取得表示**: `ui/hud/hud.gd`がアイテム獲得のたびに
     単純にラベルを追加するだけで、仕様書8章が求める「同じアイテムを複数回
     獲得した場合は×2等の重ね数表示」「種類数が5〜6個を超えたら+Nバッジで
     まとめる」が未実装だった。`_item_rows`辞書でアイテム種別ごとの獲得数を
     追跡し、`<アイテム名> ×N`表示と、6種類を超えた分をまとめる`+N`バッジを
     実装した
  - **相違点として確認したが、あえて修正しなかった/保留とした事項**(詳細は
    ユーザーへの報告を参照): (a) 仕様書8章が名指しする8種の特別効果アイテム
    (`boss_slayer_mark`等)が`data/items/`に1つも存在せず、既存6種はすべて
    ステータス系のみだった。それぞれ新しいゲームメカニクス(被撃破時復活、
    生命奪取、被ダメージ反射等)の実装が必要な規模のため、ユーザーに実装要否を
    確認してから着手する方針とした。(b) `ui/settings/settings_screen.tscn`
    (ダメージ数値表示のON/OFF等を持つ設定画面)が、`title.tscn`/`home.tscn`/
    `game.tscn`のどこからも参照されておらず、実際には到達不能な状態で残置
    されていることを発見した。仕様書にも記載が無いため、削除するか導線を
    追加するかはユーザーの判断が必要と考え、コードは変更していない
  - Godotをヘッドレス実行して実際に確認(推測ではなく実行結果ベース):
    `AdManager`が実際に`root.has_node()`でfalseであること、実際に
    `_pick_unspawned_boss_id()`を10回連続で呼ぶと本当に10体すべて異なる
    idが返ること・11回目で正しくリセットされ出現が止まらないこと、
    実際に`start_run()`を20回呼ぶと精鋭部屋数が実際に1と2の両方で
    観測されること、実際にボス撃破報酬を30回発生させると欠片ドロップ数が
    実際に1と2の両方で観測されること、実際の`game.tscn`で
    Player/WaveSpawner/EliteRoomManager/BossSpawner/HUD/LevelUpSelect/
    ItemSelect/ResultScreen/FusionSystem/ScreenEffects/VFXPoolManager/
    MassKillTracker/EffectThemeManager/DamageNumberManagerの全14ノードが
    実際にシーンツリー上に存在すること(「コードは書いたがシーンに追加し
    忘れていた」事故が無いことの確認)、同じアイテムを実際に2回獲得させると
    本当に1行に集約され`×2`と表示されること、7種類目のアイテムを実際に
    獲得させると本当に`+1`バッジとしてまとめられること、レベルアップが
    実際に強化3択→属性3択の2段階のままであることを確認済み

- **キャラクターの向き反転修正+ボスnova攻撃の即死対策**:
  1. `components/animation_component.gd`の`flip_h`更新が、攻撃/被弾アニメの
     ロック判定(`_locked_until_msec`)より後ろにあったため、攻撃間隔が短く
     ほぼ常にロック中になる戦闘中は左右反転がほとんど発生しない不具合を修正。
     向きの更新(`_update_facing()`)をロック判定より前に移動し、アニメ
     ロック中でも常に左右移動方向を反映するようにした(上下移動のみ・停止中は
     直前の向きを維持、という既存仕様はそのまま)。`AnimationComponent`は
     Player/EnemyBasic(通常敵・精鋭・ボスすべて)で共通利用されているため、
     この1ファイルの修正で全キャラクターに適用される
  2. ボスの`nova`(全方位弾)攻撃を受けるとプレイヤーが即死する事故を修正。
     原因は、全12発の弾がボス自身の位置から発射されるため、プレイヤーが
     ボスに近いと複数発がほぼ同時に命中し合算で数百ダメージになり得たこと。
     `systems/boss_ai/nova_strategy.gd`の`damage_multiplier`を1.0→0.4に
     引き下げるとともに、`components/health_component.gd`に恒久的な安全策として
     被ダメージ上限キャップを追加した: 1回の被弾(同一物理フレーム内の複数命中は
     合算)で最大HPの40%(`MAX_DAMAGE_PER_HIT_RATIO`)を超えるダメージを
     与えない。ただし雑魚敵の「一撃で倒せるはずの攻撃」まで弱体化させないよう、
     実ダメージ30(`MIN_DAMAGE_CAP_FLOOR`)未満のヒットはキャップの対象外とした
     (このキャップはnova専用ではなくHealthComponent全体に適用される汎用の
     安全策)
  3. `game_specification.md`の該当箇所(7章ボスのnova説明・9章システム基盤・
     10章演出)を今回の修正内容に合わせて更新した
  - Godotをヘッドレス実行して実際に確認: `HealthComponent`に実際に600ダメージの
    一撃を与えると本当に40ダメージ(max_hp100の40%)に切り詰められること、
    体力10の雑魚敵相当に実際に25ダメージを与えると閾値未満のためキャップされず
    そのまま一撃で倒れること、同一フレーム内に実際に20ダメージを4連続で
    与えると合計40ダメージ止まりで打ち止めになること、実際の`game.tscn`で
    プレイヤーをボスの真上に配置した最悪ケースでnova攻撃を実際に発動させても
    HP100→60で生存すること(以前の実装なら即死していた状況)、実際に矢印キーを
    押して左右移動させると`AnimatedSprite2D.flip_h`が正しく反転すること、
    さらに攻撃アニメーションをロックした状態で実際に左右キーを押しても
    flip_hが正しく更新され続けること、上下移動のみでは直前の向きが維持される
    ことを確認済み

- **Fusion Weaponシステムの大幅強化(Steamヒット化レビュー対応)**:
  1. `data/fragments/`に`light`(光)・`dark`(闇)を追加し3属性→5属性に拡張。
     対応する`effects/themes/light.tres`/`dark.tres`は既存資産として既に
     存在していたため、新規作成は不要だった
  2. `data/weapons/`に13種類の新規レシピを追加(既存の`steam_burst_weapon`/
     `thunder_flame_weapon`は変更なし)。5属性から選べる2属性の組み合わせを
     全10種類網羅、3属性の「超融合」を3種類、4〜5属性のボーナス上位ティアを
     2種類の計15種類以上。各レシピに対応する`combo_ids`付き
     `EffectThemeData`(`effects/themes/*.tres`)も新設し、
     `EffectThemeManager`の既存の合成着弾演出ロジックをそのまま流用できる
     ようにした
  3. `resources/upgrade_data.gd`に`downside_type`/`downside_value`を追加し、
     `PlayerUpgradesComponent`を「主効果+代償を同じ語彙(effect_type)で
     マイナス方向に適用する」汎用ディスパッチャ(`_apply_effect()`)に
     再設計した。`data/upgrades/`を4種類→12種類(純粋な強化6種+Brotato的
     トレードオフ6種)に拡張。射程のトレードオフを実際に機能させるため、
     従来使われていなかった`WeaponData.attack_range`を`WeaponInstance.tick()`
     で実際に判定するようにした(射程外の敵には発射しない)
  4. `systems/fusion_system.gd`に合成演出のランク分けを追加: 通常合成(2属性)は
     既存の光る演出(画面フラッシュ)のみ、超融合(3属性以上)は画面フラッシュ+
     0.3秒のヒットストップ+武器名カットイン(新設`ScreenEffects.weapon_cut_in()`)
     を重ねる専用演出にした
  5. `CharacterData.preferred_element`を追加し全10職業に割り当て、
     `LevelUpSelect`の属性抽選を「重み付き非復元抽出」に変更。選択中の職業の
     `preferred_element`と一致する属性は通常の1.5倍選ばれやすくなる
  - Godotをヘッドレス実行して実際に確認: 5属性・15種類(2属性10+3属性3+
    4〜5属性2)のレシピが実際に正しく読み込まれること、既存の
    `steam_burst_weapon`が変更されていないこと、トレードオフ強化
    (`reckless_power`)を実際に適用すると`damage_multiplier`が+0.25、
    `MovementComponent.bonus_speed_multiplier`が実際に0.95(-5%)になること、
    `rapid_barrage`適用後に`WeaponManagerComponent.get_attack_range_multiplier()`
    が実際に0.9を返すこと、実際に2属性(fire+ice)を合成しても
    `Engine.time_scale`が1.0のまま変化しないこと、実際に3属性
    (fire+ice+lightning)を合成すると`Engine.time_scale`が実際に0.05まで
    下がり(ヒットストップ発動)、武器名「三大元素の剣」のカットインラベルが
    実際にシーンツリーへ生成されること、`wizard`(preferred_element=dark)を
    選択中に属性抽選を400回実際に試行すると`dark`の出現率が70.0%
    (職業未選択時の61.3%より明確に高い)になることを確認済み

- **キャラクター表示品質の改善(テクスチャにじみ対策+スケール拡大、2026年8月)**:
  1. `project.godot`の`[rendering]`に
     `textures/canvas_textures/default_texture_filter=0`(Nearest)を追加。
     原因は、プロジェクト全体のデフォルトフィルタが未設定でエンジン既定の
     Linear(線形補間)になっており、拡大表示されるプレイヤー/敵/ボスの
     ドット絵だけがにじんで見えていたこと(TileMapLayerの床・壁は等倍
     描画のためLinearでも目立たなかった)。この1設定の変更だけで
     プロジェクト全体のキャラクター描画がNearestになる
  2. Player/通常敵/精鋭敵/ボスの表示スケールを、当たり判定込みで一律×1.25
     拡大した: `player.tscn`の`AnimatedSprite2D.scale`(1.2→1.5)・
     体の`CollisionShape2D`(radius 16→20)・`HurtboxComponent`の
     `CollisionShape2D`(32×32→40×40)を同期して変更。`enemy_basic.gd`の
     `visual_scale_multiplier`既定値を1.0→1.25にしたことで、通常敵全体に
     見た目と当たり判定(本体・被弾・接触ダメージの3コリジョン)が連動して
     反映されるようにした。`elite_room_manager.gd`の`elite_visual_scale`を
     1.3→1.6、`data/bosses/*.json`10体分の`visual_scale`を相対的な大小関係を
     保ったまま一律×1.25(詳細は`game_specification.md`16章)
  - Godotを実際にウィンドウ描画ありで実行し、`get_viewport().get_texture()`で
    実機と同じレンダリング結果をスクリーンショットとして保存して目視確認: Player・
    通常敵・精鋭敵・ボス(黒騎士A)それぞれの`AnimatedSprite2D.scale`と3種の
    `CollisionShape2D`(本体/被弾/接触ダメージ)が期待値どおり(1.25倍/1.6倍/
    1.35倍)同期して拡大されていること、実際にゲームを起動してプレイヤーと
    ボス(ミノタウロス)が画面に表示された状態のスクリーンショットで、
    キャラクターの輪郭が背景タイルと同程度にくっきりして見える(にじみが
    解消されている)ことを確認済み

- **雷属性の全画面フラッシュ廃止+所持武器確認UI追加(2026年8月)**:
  1. `effects/effect_theme_manager.gd`の`_play_element()`から、光属性(is_beam)の
     強化ヒット時に`ScreenEffects.flash()`で画面全体を光らせていた処理を削除した。
     原因調査の結果、雷(lightning)属性テーマ自体には元々全画面フラッシュは無く
     (`is_chain`による着弾位置周辺の局所的な連鎖稲妻のみ)、光(light)属性テーマの
     `is_beam`分岐が全画面フラッシュの実体だった。雷+光の合成武器(聖雷/holy_thunder
     等)を使うと雷属性と体感的に結びついて見えていたと考えられる。攻撃速度が
     上がるほど点滅頻度が増して不快感・光過敏性発作のリスクにつながるため、
     属性を問わず「攻撃ヒットのたびに全画面が光る」演出を完全に廃止し、着弾位置
     周辺の局所効果(貫通ビームのLine2D等)のみに限定した。合わせて未使用になった
     `screen_effects_path`/`_screen_effects`を`EffectThemeManager`と`game.tscn`から
     削除した
  2. `resources/weapon_data.gd`に`description`(効果説明文)を追加し、
     `data/weapons/`全16ファイルに説明文を追加した
  3. `components/weapon_manager_component.gd`に`get_weapon_instances()`を追加し、
     所持武器一覧をHUD/ポーズメニューから読み取れるようにした
  4. `ui/hud/hud.gd`/`hud.tscn`に、HPバー直下・欠片行/戦利品行とは別の
     `WeaponRow`を追加し、現在所持する完成武器をテキスト略称アイコンで常時表示。
     ホバー時に武器名・攻撃力・攻撃間隔・属性・効果説明をツールチップ表示する
  5. `ui/pause_menu/`を新設。Escキー(`ui_cancel`)で開閉する簡易ポーズメニューに
     所持武器一覧(アイコン+名前+攻撃力+攻撃間隔+属性+効果説明)を表示する。
     既存のLevelUpSelect/ItemSelectと同じ`GameManager.active_modal_count`経由の
     一時停止に乗り、他モーダルが開いている間は割り込んで開かない
  - Godotをヘッドレス実行して実際に確認: `EffectThemeManager`から
    `screen_effects_path`プロパティが完全に削除されていること、`holy_thunder`
    (雷+光)・`lightning`単体それぞれのヒット演出を実際に発火させてもエラーなく
    実行でき局所的なビーム線(Line2D)は実際に生成されること、`lightning`テーマの
    `is_beam`が`false`・`is_chain`が`true`のままであること(局所効果は維持)を
    確認済み。さらに実際に`game.tscn`を起動してHUDの所持武器トレイに初期装備
    `starter_sword`が表示され、そのツールチップに武器名・攻撃力・攻撃間隔・
    属性が含まれること、実際に武器を1つ合成して`weapon_fused`を発火させると
    トレイが2件に更新されること、ポーズメニューを実際に開くと
    `GameManager.active_modal_count`が1に増え`get_tree().paused`が`true`になり、
    武器一覧に2件(名前・攻撃力・攻撃間隔・属性・効果説明)が表示されること、
    閉じると`active_modal_count`が0に戻り一時停止が解除されることを確認済み

- **SE/BGMシステムの実装(2026年8月)**:
  1. `assets/audio/se/`(SE10種類)・`assets/audio/bgm/`(BGM3種類、いずれも仮の.wav)を
     配置し、`autoload/audio_manager.gd`にフォルダ走査による読み込みを実装した
     (`DataLoader`のJSONフォルダ走査と同じ方針。ファイル名がそのままサウンドIDになる)
  2. BGMは`AudioStreamPlayer.finished`を使い、素材側のループ設定に依存せず
     `AudioManager`側で明示的にループさせるようにした
  3. `EventBus`経由で発火する各種イベント(enemy_died/player_damaged/
     player_leveled_up/weapon_fused/fragment_collected/item_acquired/
     boss_fight_started/boss_fight_ended/run_started/run_ended)をAudioManager自身が
     購読し、対応するSE再生・BGM切替を一元的に行うようにした(HUD等の既存Systemと
     同じくEventBus購読による疎結合)。`EventBus.player_damaged`はこれまで宣言のみで
     未発火だったため、`scenes/game.gd`の既存HUD更新箇所から実際に発火するよう
     合わせて修正した
  4. EventBus化されていない発生源(武器発射・被弾・ボタンクリック・ホームBGM)は、
     それぞれの発生源スクリプト(`WeaponManagerComponent.spawn_projectile()`、
     `HurtboxComponent._on_area_entered()`(被弾側がenemiesグループの時のみ)、
     title.gd/home.gd/result_screen.gd/level_up_select.gd/item_select.gdの各ボタン
     ハンドラ、home.gdの`_ready()`)から直接`AudioManager.play_sfx()`/`play_bgm()`を
     呼ぶようにした
  - Godotをヘッドレス実行して実際に確認: `sfx_table`/`bgm_table`に全13ファイルが
    IDとして読み込まれていること、`EventBus`の各シグナルを実際に発火させると
    それぞれ対応するSE(enemy_death/player_hurt/level_up/fusion_success/
    item_pickup×2/boss_appear/player_death)が実際に空いている
    `AudioStreamPlayer`で再生開始すること、`run_started`→`dungeon_explore`・
    `boss_fight_started`→`boss_battle`・`boss_fight_ended`→`dungeon_explore`と
    BGMが正しく切り替わること、実際に`WeaponManagerComponent.spawn_projectile()`を
    呼ぶと`attack_shoot`が、敵の`HurtboxComponent`へ実際に被弾処理を発火させると
    `hit_impact`が鳴ること、実際に`title.tscn`のStartButtonの`pressed`シグナルを
    発火させると`ui_click`が鳴ることを確認済み

- **職業ごとの自動攻撃パターン+固有パッシブ(2026年8月)**:
  1. `systems/attack_patterns/`を新設し、`systems/boss_ai/`(ボス固有攻撃)と
     同じStrategyパターンで9種類の攻撃パターンクラス(`AttackPatternBase`を
     継承)を実装した: `MeleeArcAttack`(melee_arc/wide_cleave共有)、
     `ChargeDashAttack`、`SelfPulseAttack`、`HolyPulseHealAttack`
     (SelfPulseAttackを継承)、`PiercingThrustAttack`、`SpreadShotAttack`、
     `HomingBoltAttack`、`SummonMinionAttack`。`WeaponManagerComponent`が
     `CharacterData.attack_pattern_id`に応じて動的に生成し、既存の欠片合成
     武器システム(WeaponInstance)とは独立して並行発動させる
     (Soldierの`single_shot`だけは既存の単発射撃のまま変更なし)
  2. 近接/AoE系は`entities/melee_hit/`(`MeleeHit`、移動しない瞬間ヒット判定)で
     既存のHitbox/Hurtbox被弾パイプラインを再利用。summon_minionは
     `entities/allies/ally_skeleton.gd`(既存のEnemyBasic/AIComponent/
     ChaseStrategyの構成を、追跡対象と衝突レイヤーを味方用に入れ替えて再利用)
  3. `resources/character_data.gd`に`attack_pattern_id`・`base_damage`・
     `attack_interval`・`attack_range`・`vfx_theme_id`・`crit_chance`・
     `crit_multiplier`・`attack_pattern_params`(パターン固有パラメータの
     任意辞書)・職業パッシブ8種(`damage_reduction`/`exp_gain_multiplier`/
     `pickup_range_multiplier`/`crit_rate_bonus`/`melee_lifesteal_percent`/
     `minion_stat_multiplier`/`self_damage_multiplier`/`dash_invincible`)を
     追加し、`data/characters/`全10ファイルに値を設定した
  4. `max_hp`/`move_speed`をSoldier基準(HP100/移動速度140)への倍率どおりに
     全職業ぶん調整した(倍率フィールドの新設はせず、既存の絶対値フィールドを
     直接書き換え)
  5. `PlayerUpgradesComponent.apply_character_passives()`を新設し、職業パッシブを
     既存の強化オプション/アイテムの蓄積値(damage_multiplier/crit_rate_bonus/
     damage_taken_multiplier)へ「初期値」として合成することで、`_apply_effect()`
     を一切変更せずに職業パッシブと強化オプションが自然に重なるようにした。
     `exp_gain_multiplier`(新設、ExperienceComponentが参照)、
     `HealthComponent.invincible`(新設、charge_dash中の無敵に使用)も追加
  6. 既存の強化オプション(multishot_chance_up/homing_upgrade)を、パターンごとに
     読み替えるロジックを実装(近接/AoE系はmultishotを「もう一振り」、
     homingを「射程/AoE半径+」に読み替える。詳細は`game_specification.md`19.3)
  - Godotをヘッドレス実行して実際に確認: 10職業すべてで実際にHP・移動速度・
    `attack_pattern_id`に対応するクラスが正しく反映されること、職業パッシブが
    `PlayerUpgradesComponent`/`HealthComponent`へ正しく合成されていること、
    そして各職業の攻撃パターンを実際に`execute()`発動させて、swordsman/
    armored_axemanの扇状攻撃が前方の敵に、knightの突進が通過した敵に実際に
    ダメージを与え突進中は無敵になり終了後に解除されること、knight_templar/
    priestの周囲AoEが実際に敵にダメージを与え(priestは自己回復も)、lancerの
    貫通突きが直線上の2体に実際にダメージを与えること、archerが実際に3方向の
    矢を発射すること、wizardの魔法弾が強化未取得でも実際に最低限の誘導性能を
    持つこと、necromancerが実際に味方スケルトンを召喚しそのステータスが
    `minion_stat_multiplier`ぶん正しく増幅され、上限(既定3体)を超えて
    召喚されないことを確認済み。検証の過程で、charge_dashのように攻撃者自身が
    高速移動し続けるパターンでは、Area2D同士の2段階物理判定(次の物理ステップの
    検出待ち)だと対象を取りこぼす実際の不具合を発見し、`apply_direct_damage()`
    (クエリ結果へその場で直接ダメージを適用)に切り替えて修正した
  - **前回ラウンドの不具合修正**: SE/BGM追加時に`EventBus.player_damaged`が
    実は`entities/player/player.gd`の`_on_damaged()`から既に発火されていたのを
    見落とし、`scenes/game.gd`にも重複して発火処理を追加してしまっていた
    (被弾のたびにplayer_hurt SEが二重再生される状態だった)。今回`scenes/game.gd`
    側の重複発火を削除して修正した

- **職業攻撃パターンの実結線バグ修正+敵接触ダメージの見直し(2026年8月)**:
  1. **不具合の発見経緯**: 前回ラウンドで「10職業すべて検証済み」と報告したが、
     実プレイでは全職業が矢の単発射撃のままに見えるとの指摘を受け、
     `execute()`を手動で直接呼ばず実際の`_process()`ループだけを走らせて
     再検証したところ、`MeleeHit`等の職業攻撃パターン自体は実際に発生して
     いたが、全職業が`starter_sword`(初期装備の矢)も同時に自動発射し
     続けており、矢の発射だけが視覚的に優勢でパターンの違いが埋もれて
     見えていたことが判明した(前回の検証がexecute()の手動呼び出しに
     依存していたため、この「結線はされているが体感できない」問題を
     見落としていた)
  2. `components/weapon_manager_component.gd`を修正し、`single_shot`
     (Soldier)以外の職業には`starter_sword`を自動装備しないようにした。
     欠片合成(FusionSystem)は`starting_weapon_id`の有無に関係なく動作する
     ため、フラグメントを集めて武器を合成すれば引き続きどの職業でも
     自動発射される
  3. 職業攻撃パターンの発動ごとに`weapon_fired`シグナルを発火し、矢の発射時と
     同様にプレイヤーの攻撃アニメーションが実際に再生されるようにした。
     近接系(Swordsman/Armored Axeman)・突進系(Knight)の`vfx_theme_id`を
     未登録の`"default"`から各職業の`preferred_element`に合わせた実在テーマ
     (lightning/light)へ変更し、命中時に実際に属性VFXが出るようにした
  4. `entities/enemies/enemy_basic.gd`の接触ダメージ(ContactHitbox)を、
     常時有効から「攻撃モーション(attack1/attack2等)を実際に再生している間
     だけ有効」に変更した。`components/hitbox_component.gd`に`damage_enabled`
     を新設し、`components/hurtbox_component.gd`はこれがtrueの時だけ実際に
     ダメージを適用する(falseの間も接触自体は敵側へ伝わり、攻撃モーション
     開始のきっかけにできる)。プレイヤーと敵が接触したまま動かないケースが
     多いため、`area_entered`(重なり始めた瞬間)だけに頼らず、
     `ContactHitbox.get_overlapping_areas()`を毎フレーム確認して能動的に
     ダメージを適用する経路も追加した。攻撃モーションを持たない敵
     (Slime等)向けに`EnemyData.attack_interval`(新設)を追加し、周期的に
     ダメージ有効窓を開くフォールバックを実装した
  5. `components/health_component.gd`に被弾後0.5秒の無敵時間(iframe)を追加し、
     複数の敵に囲まれた際の連続ヒット事故を防ぐ安全策とした(Player/Enemy
     共通のコンポーネントのため両方に適用される)
  - Godotをヘッドレス実行して実際に確認: `execute()`を手動で呼ばず実際の
    `_process()`ループだけで4秒間走らせ、Soldierは矢(Projectile)のみ、
    Swordsman/Knight Templarは`weapon_instances`が0件(矢を撃たない)で
    `MeleeHit`のみが実際に生成されることをノードの発生ログで確認した。
    接触ダメージについては、攻撃モーションを持つ敵に実際に密着させた状態で
    実ゲームループを3秒間走らせ、接触した瞬間のフレームでは即座にダメージが
    発生しないこと、被弾回数が「毎フレーム」ではなく攻撃モーション+iframeで
    間引かれた妥当な回数に収まること、`HealthComponent.apply_damage()`を
    連続で呼ぶと2回目がiframeでブロックされ0.5秒経過後は再び通ること、
    攻撃モーションを持たない敵(疑似的に無効化して検証)が
    `attack_interval`相当の周期でのみ被弾させることを確認した。最後に
    WaveSpawner有効の通常プレイに近い状態で6秒間走らせ、スクリプトエラーが
    出ずプレイヤーが即死しないことも確認済み

- **ホーム画面の職業選択UIをグリッドレイアウトへ刷新(2026年8月)**:
  1. `ui/home/home.tscn`のボタン縦一覧を、`GridContainer`(5列×2行、10職業ぶん)
     を使ったレイアウトへ変更。ドラゴンクエストの記念画像のような「複数
     キャラクターのポートレートを整列させる」レイアウトの考え方を参考にした
     (特定作品のデザインの模倣ではなく、グリッド整列という構成のみを踏襲)
  2. `entities/sprite_sheet_builder.gd`に`build_portrait_texture()`を新設し、
     各職業の`_Idle.png`スプライトシートから`AtlasTexture`で1コマ目だけを
     切り出してポートレートに使うようにした(多コマのシートをそのまま表示すると
     複数キャラクターが横に並んで見えてしまうため)
  3. `ui/home/home.gd`で各セルをButtonとして動的生成し、未解放セルは
     ポートレートをmodulateでグレーがかった色に落とし鍵アイコン(🔒)を重ね、
     解放コストを表示。通常/ホバー/選択中(フォーカス)でスタイルボックスの
     枠線色を切り替え、マウスカーソルを合わせたセル・選択中のセルを視覚的に
     区別できるようにした
  4. 解放済みセルのクリックで職業選択+ゲーム開始、未解放セルのクリックで
     解放試行(コスト不足なら何もしない)という既存の選択/解放ロジックは
     そのまま流用した
  - Godotを実際にウィンドウ描画ありで実行し、実際にレンダリングした
    スクリーンショットで目視確認: グリッドが実際に5列×2行(10セル)で
    表示されること、10職業すべてのポートレートが実際に1コマぶんの正方形
    (スプライトシート全体の幅より明確に小さい領域)として切り出されていること、
    未解放セルでは実際にポートレートが暗く鍵アイコン付きで表示され、解放済み
    セル(Soldier)とは実際に見た目が区別できることを確認済み

- **ホーム画面グリッドのサイズ調整(2026年8月)**: 上記グリッド刷新の直後、
  画面サイズに対してカード・ポートレート・文字が全体的に小さく見える
  問題を修正した。
  1. `home.gd`の`CELL_SIZE`を`Vector2(340, 420)`に拡大し、`home.tscn`の
     `GridContainer`の`h_separation`/`v_separation`も`28`に拡大(10職業=
     5列×2行で`grid total size`が概ね`(1812, 868)`前後になり、横長画面の
     幅の大部分を使う)
  2. ポートレートを`PORTRAIT_SCALE = 3`(整数倍)で`300x300`表示に拡大し、
     `TextureRect.expand_mode`を`EXPAND_IGNORE_SIZE`に変更(既定の
     `EXPAND_KEEP_SIZE`だと拡大が反映されなかったため)。鍵アイコンの
     フォントサイズも`150`に拡大してポートレートと存在感を揃えた
  3. 職業名(`26`)・補助テキスト(`18`)・所持メタ通貨(`24`)の
     フォントサイズを拡大
  4. `home.tscn`で`CharacterGrid`を`size_flags_vertical = 3`の
     `CenterContainer`配下に置き、カードを大きくしても上下に間延びした
     余白が出ないよう画面の中央〜上寄りにバランス良く収める構成に変更
  - **副次的に発見・修正したバグ**: 上記のサイズ調整だけでは、実際の
    レンダリング結果を見るとポートレートのキャラクターが300x300の枠に
    対して極端に小さいままだった。`Image.get_used_rect()`で調査した結果、
    素材のスプライトシート(1コマ=100x100)は実際に描かれたキャラクター
    部分がごく一部(例: Soldierは17x21ピクセル程度)しかなく、残りは
    アニメーションのコマ位置を揃えるための透明な余白だと判明。
    `entities/sprite_sheet_builder.gd`の`build_portrait_texture()`を、
    コマ全体ではなく不透明ピクセルの外接矩形だけを`AtlasTexture.region`
    として使うように修正し、キャラクターが枠のほとんどを占めるサイズで
    表示されるようにした
  - Godotを実際にウィンドウ描画ありで実行し、実際にレンダリングした
    スクリーンショットで目視確認: カードが画面幅の大部分を使うサイズに
    なっていること、ポートレートの外接矩形切り出し修正によりキャラクターが
    はっきり視認できる大きさで表示されること、鍵アイコン・職業名・
    解放コスト・所持メタ通貨のいずれも明確に大きくなっていること、
    グリッド全体が画面上下に間延びせず中央〜上寄りにバランス良く
    収まっていることを確認済み

- **ホーム画面グリッドの再拡大(2026年8月、縮小デグレの修正)**: 上記の
  サイズ調整後、`home.gd`にポートレートの最終描画だけを70%
  (`TextureRect.scale`)に縮小する処理が誤って混入し、外接矩形切り出し
  修正の効果を打ち消してグリッドが再び小さく見える状態になっていたことが
  判明。この70%縮小(および中間ラッパー`portrait_holder`/`pivot_offset`)を
  撤去し、`TextureRect`を表示枠いっぱいに直接描画するシンプルな構成に戻した
  上で、さらにサイズを拡大した。
  1. `CELL_SIZE`を`Vector2(352, 460)`に拡大(`h_separation`/`v_separation`
     は`26`)。実測`grid total size`は`(1864, 946)`前後(1920×1080画面の
     マージン内でほぼ幅いっぱい)
  2. 職業名`32`・補助テキスト`22`・鍵アイコン`170`・所持メタ通貨`28`と、
     文字サイズをさらに拡大
  - Godotを実際にウィンドウ描画ありで実行し、実際にレンダリングした
    スクリーンショットで目視確認: 70%縮小デグレが解消され10職業すべての
    ポートレートが表示枠の大部分を占めるサイズで表示されること、カード・
    文字が前回よりさらに明確に大きくなっていること、画面上下のバランスは
    崩れていないことを確認済み

- **ホーム画面ポートレートの表示スケール縮小(2026年8月、ドット絵の粗さ対策)**:
  上記の再拡大でポートレートが配置枠(300×300)いっぱいまで拡大された結果、
  ドット1つ1つが引き伸ばされすぎて粗さが目立つようになったため、カード・
  配置枠のサイズは変えずポートレートの表示スケールだけを2/3に縮小した。
  `home.gd`の配置枠(`PORTRAIT_FRAME_SIZE`、300×300、`CenterContainer`)は
  そのまま維持し、実際に描画する`TextureRect`の`custom_minimum_size`だけを
  `PORTRAIT_DISPLAY_SCALE = 2.0/3.0`倍(`Vector2(200, 200)`)に縮小、
  `CenterContainer`の自動中央配置に任せる方式(`scale`/`pivot_offset`は
  使わない)。Godotを実際にウィンドウ描画ありで実行し、実際にレンダリングした
  スクリーンショットでカードサイズが不変のままポートレートが約200×200に
  縮小され、ドット絵のジャギーが軽減されたことを確認済み

- **職業選択カードのホバー攻撃アニメーション(2026年8月)**: 解放済みの
  職業カードにマウスカーソルを合わせている間、そのキャラクターの攻撃
  アニメーションをループ再生するようにした。新設した
  `ui/home/hover_attack_portrait.gd`(`HoverAttackPortrait`、`TextureRect`
  継承)が、通常はIdle静止画を表示し、カード(`Button`)の`mouse_entered`/
  `mouse_exited`から呼ばれる`start_attack()`/`stop_attack()`で攻撃コマの
  ループ再生⇔Idle静止画を切り替える。攻撃コマの取得は、Player側の職業攻撃
  パターン実装で使っている`SpriteSheetBuilder.build_sprite_frames()`を
  再利用する新設`build_hover_attack_frames()`が、対象職業に存在する
  attack1/attack2/attack3からランダムに1つを選んで返す(アニメーション内の
  拡大率がコマごとにガクガクしないよう、選んだアニメーションの全コマに
  共通する外接矩形で切り抜く)。未解放カードは`mouse_entered`/
  `mouse_exited`のシグナル接続自体を行わず、対象外(従来通り鍵アイコン表示
  のまま)。ヘッドレス実行で、解放済みカードのシグナル接続・実際の
  `_process()`ループによる複数コマ切り替え・ホバー解除時のIdle復帰・
  未解放カードの非対象化(接続数0)を確認し、さらに実レンダリングの
  スクリーンショットでホバー中のカードだけが攻撃ポーズになることを
  目視確認済み

- **職業専用攻撃強化(ability_level、2026年8月)**: プレイヤーのレベルアップに
  応じて、職業固有の攻撃パターン(`systems/attack_patterns/`)自体が
  段階的に強化される仕組みを追加した。新しい選択UIは作らず、既存の
  レベルアップ「通常強化3択」の抽選プールに職業専用強化を混ぜる形で実装
  (モーダルの二重表示問題を再発させないため)。
  - **実装前に判明したデータの食い違い**: 依頼時点の「Knightはcharge_dash」
    という前提が、当時のdata/characters/knight.json・本仕様書19.2の
    「Knightはmelee_arc」と食い違っていた(19.1の説明文だけ古い記述が
    残っており、仕様書内でも矛盾していた)。ユーザーに確認のうえ、
    `knight.json`を`charge_dash`へ戻し、19.2の表も合わせて修正した
  - `AttackPatternBase`に`ability_level`(初期値1、最大5)を追加。
    `UpgradeData`に`class_character_id`/`class_ability_level`を追加し、
    `data/upgrades/class_<character_id>_lv<N>.json`を10職業×4段階=40件
    新設。`LevelUpSelect._get_compatible_upgrades()`が「現在のキャラクター
    のidと一致し、現在のability_level+1と一致する」候補だけを追加し、
    Lv2→Lv3→Lv4→Lv5の順序を保証する
  - Soldier/Swordsman/Armored Axemanは`attack_pattern_id`(melee_arc/
    wide_cleave)を共有しているため、gatingは`attack_pattern_id`ではなく
    `character_data.id`基準にした(3職業がそれぞれ別々の強化ツリーを
    持てるようにするため)。`MeleeArcAttack`/`SelfPulseAttack`(Knight
    Templar/Priestが共有)は`character_data.id`で分岐して職業ごとに
    異なるLv2〜5の効果を出し分ける(詳細は game_specification.md 19.8)
  - ヘッドレス実行で、(1)Swordsmanのability_levelを1→5まで実際に上げながら
    候補プールを確認し、各段階でLv2〜5が正しい順序で1件ずつだけ出現し
    Lv5到達後は候補が0件になること、(2)実際のゲームループでSwordsmanの
    ability_level1と2を比較し、同じ3秒間に発生する近接ヒット数が実際に
    1周期1発→2発に増えること、(3)Knightが実際にcharge_dashのインスタンスを
    使い、実際のゲームループで突進移動が発生し、ability_level2で移動距離が
    実際に伸びることを確認済み

- **職業スキルの流派分岐(school、2026年8月、試験実装)**: 職業専用攻撃強化
  (ability_level)に「流派分岐」を追加した。**現時点ではSwordsman
  (melee_arc)のみの試験実装**で、うまく機能すれば他の9職業へ展開する予定
  (未着手)。強化は引き続きプレイヤーのキャラクターレベルに紐づき、既存の
  レベルアップ3択プールに統合する方針を維持している(新しい選択UIは
  追加していない)。
  - `AttackPatternBase`に`school: String`(既定"none")、`UpgradeData`に
    `class_school`を追加。Lv1→2到達時は通常の数値強化ではなく「乱撃派」
    「一閃派」の2択を提示し、選ぶとschoolが確定、以降は選んだ流派の強化
    だけが出現する(もう一方は二度と出現しない)。流派選択の2択は
    `LevelUpSelect._open()`で他の候補と分離して必ず出現を保証している
    (乱数で埋もれて出現しない事故を防ぐため)
  - **乱撃派**: Lv2連続斬り数2/Lv3で3/Lv4攻撃間隔-20%/Lv5で連続斬り数4+
    最後の一撃は確定クリティカル。**一閃派**: Lv2単発ダメージ+40%/
    Lv3間合い+30%/Lv4クリティカル率+25%/Lv5でHP30%以下の敵に約5倍の
    大ダメージ(完全な即死ではなく大ダメージとして実装)
  - 既存のポーズメニュー(`ui/pause_menu/`)に「所持武器」/「天賦図」の
    切り替えタブを新設。天賦図は上部中央に起点ノード「居合」、その下に
    2列(左: 乱撃派、右: 一閃派)でLv.2〜Lv.5のノードを矢印で接続して
    表示し、習得済み(金色ではっきり)/未到達(薄暗い+🔒)/選択不可
    (流派確定後、選ばなかった側は永続的にグレーアウト)の3状態を視覚化
    する。Swordsman以外を選んでいる場合は「準備中」の案内を表示する
  - ヘッドレス実行で、流派選択2択の出現保証(10試行すべてで両方出現)、
    乱撃派選択後にLv3→4→5が正しい順序でのみ出現し一閃派が一度も混ざらない
    こと、実際のゲームループでLv2選択直後に近接ヒット数が実際に増えること、
    天賦図パネルが実際に組み立てたノードの色/ロックアイコンがschool/
    ability_levelの現在値と一致することを確認し、さらに実レンダリングの
    スクリーンショットで3状態(未確定/乱撃派選択直後/乱撃派Lv4)の見た目を
    目視確認済み

- **能動発動スキルシステム(2026年8月、試験実装)+ EXPゲージ + ウィンドウ
  サイズ変更**:
  - **既存実装の調査**: 実装前に調査した結果、`active_skill`という入力
    アクションが既にSpaceキーへ割り当て済み(`autoload/game_manager.gd`が
    起動時にコードから動的登録)で、`ActiveSkillComponent`により全10職業の
    アクティブスキルが既に実装済みだった(Swordsmanは`swordsman_iai`=
    居合ダッシュ斬り、クールダウン6秒)。**新規アクションは追加せず、この
    既存の`active_skill`を拡張・流用**し、ゲームパッド未割り当てだった
    南ボタン(Xbox配置のAボタン)を追加登録した
  - Swordsmanの`active_skill_id`経路だけをschool(乱撃派/一閃派)で
    出し分けるよう`ActiveSkillComponent`を拡張。school未確定(Lv1)の間は
    従来通りの居合がそのまま発動し、school確定後(Lv2以降)は乱撃派/一閃派
    専用の挙動に切り替わる(=school確定後は居合本来の演出は発動しなくなる、
    仕様変更として明記)
  - 乱撃派: 単押しで居合1回、0.4秒以内の2回目押下でability_levelに応じた
    連続斬り(2〜4連続)。専用クールダウン`@export rengeki_cooldown`
    (既定2秒)。一閃派: 単押しで確定クリティカルの一撃(通常の近接攻撃の
    2.5倍、`@export issen_damage_multiplier`)。専用クールダウン
    `@export issen_cooldown`(既定3秒)
  - **検証中に発見・修正したバグ**: 各段でノックバックを適用すると、
    同一フレーム内で連続実行される後続の斬撃が対象を判定範囲外へ弾き
    出してしまい、4連続のはずが2発しか命中しない不具合が見つかった。
    最後の一撃だけノックバックを適用する形に修正し、実際に4発すべて
    命中することを再検証した
  - HUD(`ui/hud/`)にHPバー直下の経験値ゲージ+レベル表示を追加
    (`ExperienceComponent.exp_changed`シグナル新設)。ポーズメニューの
    天賦図パネルにも、次の段階解放までの同じ経験値を使った小ゲージを追加
  - `project.godot`の既定ウィンドウサイズを1920×1080→1600×900に変更
    (リサイズ可能設定は元々未指定=エンジン既定のため変更なし)
  - ヘッドレス実行で、乱撃派の単押し(1発)/2回押し(4発、修正後)、
    一閃派の確定クリティカル(実測ダメージが基礎値×2.5と一致)、HUDの
    経験値ゲージが`set_experience()`後に正しい値を示すこと、
    `ProjectSettings`上のウィンドウサイズが1600×900になっていることを
    確認し、さらに実ウィンドウ描画ありの実行で`DisplayServer.
    window_get_size()`が実際に(1600, 900)を返すことも確認済み

- **乱撃派のチャージ制への作り直し + EXPゲージとスキル熟練度表示の完全分離
  (2026年8月、上記2点の修正)**:
  - **チャージ制**: 前回の実装は乱撃派選択時に居合の技自体
    (`_swordsman_iai()`)を`_cone_attack()`という別形状の攻撃(連続斬り
    モーション)に差し替えてしまっていたが、これは誤りだった。居合の技
    (モーション・当たり判定・ダメージ計算)はschoolに関わらず常に
    `_swordsman_iai()`のまま共通にし、schoolが変えるのは「1回のクール
    ダウンサイクルで何回連続発動できるか」というチャージ数だけにした:
    school未確定(Lv1)/一閃派=`max_charges 1`、乱撃派=`max_charges 2`
    (1回目発動直後にもう一度押せば、間を置かず同じ居合が2回目発動し、
    2回使い切った時点でクールダウン開始)。0.4秒の入力バッファ方式は
    撤去し、押下ごとにチャージを即座に消費する単純なカウンタ方式に
    作り直した。`_swordsman_iai()`は非同期(ダッシュ演出)のため、2発目が
    1発目の演出中に押されても同時に動いて移動ロック/無敵状態を奪い合わ
    ないよう、順番に実行するキュー(`_queue_swordsman_iai()`)にしている
  - **EXPゲージとスキル熟練度表示の分離**: 前回、天賦図の進捗ゲージを
    キャラクターの経験値バーと連動させてしまっていたが、これも誤りだった。
    新設した`ui/common/ability_stage_dots.gd`(`AbilityStageDots`)が、
    `WeaponManagerComponent.get_class_ability_level()`(ExperienceComponent
    とは別のデータ)だけを参照して「5つの丸印」(基本形態+Lv.2〜Lv.5、
    到達済みは金色の塗りつぶし、未到達は暗い輪郭)を組み立てる。
    `WeaponManagerComponent`に`class_ability_level_changed`シグナルを新設し
    これで駆動する。HUDのスキルアイコン付近(画面下部中央)と天賦図パネルの
    両方に同じ丸印を配置し、EXPバー(画面左上、水色)とは配色・配置ともに
    完全に切り離した(前回追加した「次の段階までのEXP連動ゲージ」は撤去)
  - ヘッドレス実行で、(1)school未確定時に1回押下すると即座にクールダウン
    (6秒)が始まり2回目押下が拒否されること、その間プレイヤーが実際に
    280px移動する(居合のダッシュ技自体が発動している)ことを確認、
    (2)乱撃派選択後、1回目押下ではクールダウンが始まらず、間を置かず
    2回目を押下すると2回目の居合(同じダッシュ技)が発動し、2回目でのみ
    クールダウンが開始、直後の3回目が拒否され、クールダウン終了後に
    チャージが回復して4回目が受理されることを確認、(3)HUDの`ExpBar`と
    `StageDotsWrap`(丸印)がそれぞれ独立したノードとして正しい値を示し、
    画面上の座標も明確に異なる(左上 vs 下部中央)ことを確認済み

- **乱撃派のコンボキャンセル(2026年8月追加)**: 1回目の居合が完全に終わる
  のを待たずに2回目を繋げられるよう、`_swordsman_iai()`のダッシュモーション
  内に「キャンセル可能ポイント」(全体の60〜70%、ダメージ判定発生直後)を
  追加した。対象は乱撃派のチャージ連携のみ(school未確定/一閃派は元々
  max_charges=1のためこの判定自体が発生しない)。このポイントに達した時点で
  次のチャージが控えていれば、1回目の残りの硬直モーションを打ち切って
  即座に2回目の居合を開始する(ダメージ自体はキャンセル前の各ステップで
  既に適用済みのため失われない)。キャンセル時は移動ロック/無敵の解除も
  行わず次の居合へそのまま引き継ぐため、2回の居合の間に一瞬だけ無敵が
  切れる隙間もできない。ヘッドレス実行で、school未確定でのフル居合1回の
  所要時間(実測435ms)を基準に、乱撃派で即2連打した場合の合計所要時間
  (実測796ms)が単純な2回フル再生の想定値(870ms)より明確に短い
  (74ms短縮)こと、その間`health_component.invincible`が2回の居合を
  またいで一度もfalseに戻らず連続していること、プレイヤーの移動距離
  (実測476px)が「約70%でキャンセルされた1回目(≈196px)+フルの2回目
  (280px)」の合計とほぼ一致し、キャンセル位置が意図した60〜70%地点で
  発生していることを確認済み

## あえて含めていないもの(設計書10.2に対応、今後追加)
- 相棒/メタ進行、ホーム画面の恒常強化
- ボス戦、複数ステージ
- 実績/デイリーミッション/ランキング/クラウドセーブ
- 多言語対応
- 武器レベル自体の育成(`WeaponInstance.level`は現状常に1。VFXの「強化」演出は
  プレイヤーのキャラクターレベルで代用している。武器個別のレベルアップテーブル実装は次フェーズ)

## 既知の制限・注意点
Godot 4.7.1のヘッドレス回帰テストと実レンダラーによる1600×900 UI確認を行っています。
環境差で表示や入力に問題が出た場合は、Godotの出力ログを確認してください。

- シーンファイル(.tscn)やSpriteFrames(.tres)のプロパティ名は手書きのため、
  Godotのバージョンによっては微修正が必要な場合があります
- パーティクルの見た目(色・形状)は仮のプレースホルダーです
- `SpriteSheetBuilder`は「1コマ=正方形、横一列に並んだスプライトシート」という前提で
  画像サイズから自動的にコマ数を割り出しています。実際に開いてコマ送りがズレている・
  原点(足元)がずれている場合はAnimatedSprite2Dの`offset`を調整するか、
  `entities/sprite_sheet_builder.gd`のフォルダ探索候補・アニメーション名候補を見直してください
- `ScreenEffects.hit_stop()` は複数回同時発火した場合に競合する可能性があります(既知の簡易実装)
- 背景の床タイル(`stage_environment.gd`の`floor_atlas_coords`)・装飾
  (`wall_decoration_variants`/`storage_cluster_variants`等)は画像を目視で確認して座標を
  選んだものです。実際に開いて見た目が想定と違う場合は、この配列のVector2i
  (`Dungeon tileset.png`は16x16単位・24列x12行)を差し替えてください

## フォルダ構成
設計提案書「3. フォルダ構成」と対応しています。詳細はそちらを参照してください。

## 次にやること(ご相談したい内容)
1. まずはGodotエディタで開いて実際に触ってみていただき、動作確認・フィードバックをお願いします
2. 動作確認後、以下を優先順位をつけて次のフェーズとして着手します:
   - 敵AIのパスファインディング対応(壁を避けて回り込む。現状は直線移動のみ)
   - 遠距離型・ボス型のStrategy追加(現状は全敵が直進追跡のChaseStrategyのみ)
   - 設定画面の実際の反映(ScreenEffects/VFXPoolManagerへの接続)、SettingsScreenを開く導線の追加
   - 相棒(メタ進行)システムの追加
   - 職業ごとの攻撃モーション/専用武器等の差別化(現状はHP・移動速度と見た目のみが職業差)
