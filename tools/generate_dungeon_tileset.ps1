# VSGAME ダンジョンタイルセット生成スクリプト
# 「レトロ16bit(SFC・ロマサガ系)×ブライト&アニメ調」— HUD(ui/common/retro_hud_style.gd)と同一パレット。
#
# 出力:
#   assets/tiles/dungeon_tileset_retro.png  … 実タイルセット(16x16タイル / 8列x6行 = 128x96px)
#   assets/tiles/_preview_tileset.png       … 目視確認用の8倍拡大プレビュー(グリッド線付き)
#
# 設計方針(docs/map_design_spec.md 5節):
#   - 床は暗く抑える。上に乗るキャラ・エフェクト・戦利品が埋もれないことを最優先する。
#   - bronze系(明るい金)は縁取りとアクセントに限定し、床の基調には使わない。
#   - 危険地帯だけは例外的に目立たせる(危険が読めない害の方が大きい)。
#   - 光源は左上で統一(HUDパネルのベベルと同じ方向)。
#
# タイル配置(atlas座標 = 列,行):
#   (0,0)-(3,0) 大広間 床 v0-3        (4,0)-(7,0) 危険地帯 床 v0-3
#   (0,1)-(3,1) 柱林 床 v0-3          (4,1)-(7,1) 隘路 床 v0-3
#   (0,2)-(3,2) 壁 v0-3               (4,2)-(7,2) 壁(bronze装飾) v0-3
#   (0,3)-(1,4) 柱A(2x2)              (2,3)-(3,4) 柱B(2x2)
#   (4,3)-(5,4) 危険地帯 噴出口(2x2)  (6,3)-(7,4) 瓦礫(2x2)
#   (0,5)-(7,5) 小物・繋ぎ(瓦礫小/ひび/bronze格子/床端)

Add-Type -AssemblyName System.Drawing

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $ProjectRoot "assets\tiles"
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

$T = 16
$COLS = 8
$ROWS = 6

# ---------------- パレット(retro_hud_style.gd と同一) ----------------
function Hex([string]$h) {
    $h = $h.TrimStart('#')
    $r = [Convert]::ToInt32($h.Substring(0,2),16)
    $g = [Convert]::ToInt32($h.Substring(2,2),16)
    $b = [Convert]::ToInt32($h.Substring(4,2),16)
    return [System.Drawing.Color]::FromArgb(255,$r,$g,$b)
}

# 石材ランプ(void系5段)。床・壁はこの範囲だけで塗る。
$S0 = Hex "1f2835"   # 壁の最暗部
$S1 = Hex "303a48"
$S2 = Hex "394351"
$S3 = Hex "414b59"   # 静かな青灰の床
$S4 = Hex "485260"
$S5 = Hex "606c7a"   # 壁面
$S6 = Hex "808b96"   # 左上の縁

# bronze系(アクセント専用)
$BD = Hex "765937"
$BR = Hex "b38b51"
$BL = Hex "d6b476"

# 危険地帯(boss-purple系 — ここだけ意図的に目立たせる)
$H0 = Hex "1a0726"   # 危険床の地
$H1 = Hex "3a1152"
$H2 = Hex "a63cd6"   # boss-purple
$H3 = Hex "ff8ae8"   # boss-purple-light
$H4 = Hex "ffd6f7"   # 芯の最輝部

# ---------------- 描画ヘルパ ----------------
function Px { param($bmp,[int]$x,[int]$y,$c)
    if ($x -ge 0 -and $y -ge 0 -and $x -lt $bmp.Width -and $y -lt $bmp.Height) { $bmp.SetPixel($x,$y,$c) }
}
function FillTile { param($bmp,[int]$ox,[int]$oy,$c)
    for ($y=0; $y -lt $T; $y++) { for ($x=0; $x -lt $T; $x++) { Px $bmp ($ox+$x) ($oy+$y) $c } }
}
# 上辺と左辺に1pxの継ぎ目を入れる。これで16x16が石板1枚として綺麗にタイリングする。
function SeamTL { param($bmp,[int]$ox,[int]$oy,$c)
    for ($i=0; $i -lt $T; $i++) { Px $bmp ($ox+$i) $oy $c; Px $bmp $ox ($oy+$i) $c }
}

# ---------------- 床: 大広間(最も静か。開けていると一目で分かるよう情報量を最小化) ----------------
function Draw-ArenaFloor { param($bmp,[int]$ox,[int]$oy,[int]$seed)
    $rnd = New-Object System.Random $seed
    FillTile $bmp $ox $oy $S3
    # 継ぎ目は最暗色ではっきり入れる。石板1枚の輪郭が読めないと「未完成の床」に見える。
    SeamTL   $bmp $ox $oy $S2
    # 継ぎ目直下に1pxの淡いベベル(左上光源)
    for ($i=1; $i -lt $T; $i++) { Px $bmp ($ox+$i) ($oy+1) $S4 }
    for ($i=2; $i -lt $T; $i++) { Px $bmp ($ox+1) ($oy+$i) $S4 }
    # 右下に落ち影を入れて石板の厚みを出す
    for ($i=1; $i -lt $T; $i++) { Px $bmp ($ox+$i) ($oy+$T-1) $S2 }
    for ($i=1; $i -lt $T; $i++) { Px $bmp ($ox+$T-1) ($oy+$i) $S2 }
    # 石肌のまだら。2pxの塊で置くことで、点ノイズではなく材質として読ませる。
    # 「静か」を保ちつつ、のっぺりした無地に見えないだけの情報量を与える。
    for ($i=0; $i -lt 7; $i++) {
        $x = $rnd.Next(3,13); $y = $rnd.Next(3,13)
        Px $bmp ($ox+$x)   ($oy+$y) $S4
        Px $bmp ($ox+$x+1) ($oy+$y) $S4
    }
    for ($i=0; $i -lt 5; $i++) {
        $x = $rnd.Next(3,14); $y = $rnd.Next(3,14)
        Px $bmp ($ox+$x) ($oy+$y) $S2
    }
    # 角の欠け。大きな石板が並んでいる印象を補強する
    Px $bmp ($ox+$T-2) ($oy+2) $S2
    Px $bmp ($ox+2) ($oy+$T-2) $S2
}

# ---------------- 床: 柱林(8x8の小割り。情報量を上げて「別の場所」と読ませる) ----------------
function Draw-PillarFloor { param($bmp,[int]$ox,[int]$oy,[int]$seed)
    $rnd = New-Object System.Random $seed
    FillTile $bmp $ox $oy $S2
    SeamTL   $bmp $ox $oy $S1
    # 中央十字の継ぎ目 → 2x2の小石板に見せる
    for ($i=0; $i -lt $T; $i++) { Px $bmp ($ox+8) ($oy+$i) $S1; Px $bmp ($ox+$i) ($oy+8) $S1 }
    # 各小石板の左上に淡いベベル
    foreach ($q in @(@(1,1),@(9,1),@(1,9),@(9,9))) {
        for ($i=0; $i -lt 7; $i++) {
            Px $bmp ($ox+$q[0]+$i) ($oy+$q[1]) $S3
            Px $bmp ($ox+$q[0])    ($oy+$q[1]+$i) $S3
        }
    }
    for ($i=0; $i -lt 6; $i++) {
        $x = $rnd.Next(0,16); $y = $rnd.Next(0,16)
        Px $bmp ($ox+$x) ($oy+$y) $S3
    }
}

# ---------------- 床: 隘路(横方向の溝。進行方向を示唆して「通路」と読ませる) ----------------
function Draw-ChokeFloor { param($bmp,[int]$ox,[int]$oy,[int]$seed)
    $rnd = New-Object System.Random $seed
    FillTile $bmp $ox $oy $S3
    # 「馬目地(running bond)」= 縦の継ぎ目を段ごとに半分ずらしたレンガ敷き。
    # 大広間(1枚板)・柱林(格子)のどちらとも明確に違う組積パターンにすることで、
    # 画面に複数ゾーンが同時に映っても床だけで場所を判別できる。
    # 縦継ぎ目を揃えると柱林と同じ格子に見えてしまうため、必ずずらすこと。
    foreach ($gy in @(0,8)) {
        for ($x=0; $x -lt $T; $x++) {
            Px $bmp ($ox+$x) ($oy+$gy)   $S0
            Px $bmp ($ox+$x) ($oy+$gy+1) $S4
        }
    }
    # 上の段は x=0 に、下の段は x=8 に縦継ぎ目を置いて半個ずらす
    for ($y=0; $y -lt 8; $y++)  { Px $bmp ($ox)   ($oy+$y) $S0 }
    for ($y=8; $y -lt 16; $y++) { Px $bmp ($ox+8) ($oy+$y) $S0 }
    # 縦継ぎ目の右隣に淡いベベル(左上光源)
    for ($y=1; $y -lt 8; $y++)  { Px $bmp ($ox+1) ($oy+$y) $S4 }
    for ($y=9; $y -lt 16; $y++) { Px $bmp ($ox+9) ($oy+$y) $S4 }
    # 踏み減りの筋。通路として使い込まれた印象を出しつつ、進行方向を示唆する
    for ($x=2; $x -lt $T; $x++) { if ($x % 3 -ne 0) { Px $bmp ($ox+$x) ($oy+5) $S2 } }
    for ($x=0; $x -lt $T-2; $x++) { if ($x % 3 -ne 1) { Px $bmp ($ox+$x) ($oy+13) $S2 } }
    for ($i=0; $i -lt 5; $i++) {
        $x = $rnd.Next(2,15); $y = $rnd.Next(2,15)
        Px $bmp ($ox+$x) ($oy+$y) $S2
    }
}

# ---------------- 床: 危険地帯(唯一目立たせてよい床。紫の亀裂が走る) ----------------
function Draw-HazardFloor { param($bmp,[int]$ox,[int]$oy,[int]$seed)
    $rnd = New-Object System.Random $seed
    FillTile $bmp $ox $oy $H0
    SeamTL   $bmp $ox $oy ([System.Drawing.Color]::FromArgb(255,8,3,16))
    # 地の粗さ
    for ($i=0; $i -lt 14; $i++) {
        $x = $rnd.Next(0,16); $y = $rnd.Next(0,16)
        Px $bmp ($ox+$x) ($oy+$y) $H1
    }
    # 亀裂: 上端から下端へランダムウォーク。芯を最輝色にして発光しているように見せる
    $cx = $rnd.Next(4,12)
    for ($y=0; $y -lt $T; $y++) {
        Px $bmp ($ox+$cx) ($oy+$y) $H3
        Px $bmp ($ox+$cx) ($oy+$y) $H3
        if ($y % 3 -eq 1) { Px $bmp ($ox+$cx) ($oy+$y) $H4 }
        # 亀裂の縁を紫で滲ませる
        Px $bmp ($ox+$cx-1) ($oy+$y) $H2
        Px $bmp ($ox+$cx+1) ($oy+$y) $H2
        $cx += $rnd.Next(-1,2)
        if ($cx -lt 2) { $cx = 2 }
        if ($cx -gt 13) { $cx = 13 }
    }
    # 横枝を1本
    $by = $rnd.Next(4,12)
    $len = $rnd.Next(3,6)
    for ($i=0; $i -lt $len; $i++) {
        $bx = $cx + $i
        Px $bmp ($ox+$bx) ($oy+$by) $H2
    }
}

# ---------------- 壁(床より明るく、構造として立たせる) ----------------
function Draw-Wall { param($bmp,[int]$ox,[int]$oy,[int]$seed,[bool]$accent)
    $rnd = New-Object System.Random $seed
    FillTile $bmp $ox $oy $S5
    # 上辺ハイライト / 下辺シャドウ(左上光源)
    for ($x=0; $x -lt $T; $x++) {
        Px $bmp ($ox+$x) $oy         $S6
        Px $bmp ($ox+$x) ($oy+$T-1)  $S0
        Px $bmp ($ox+$x) ($oy+$T-2)  $S2
    }
    for ($y=0; $y -lt $T; $y++) {
        Px $bmp $ox        ($oy+$y) $S6
        Px $bmp ($ox+$T-1) ($oy+$y) $S2
    }
    # レンガ目地(段違い)
    for ($x=0; $x -lt $T; $x++) { Px $bmp ($ox+$x) ($oy+7) $S2 }
    for ($y=1; $y -lt 7; $y++)  { Px $bmp ($ox+5) ($oy+$y) $S2 }
    for ($y=8; $y -lt 15; $y++) { Px $bmp ($ox+11) ($oy+$y) $S2 }
    # 石肌
    for ($i=0; $i -lt 6; $i++) {
        $x = $rnd.Next(1,15); $y = $rnd.Next(1,15)
        Px $bmp ($ox+$x) ($oy+$y) $S4
    }
    if ($accent) {
        # bronzeの飾り鋲。壁の一部にだけ使い、金の主張を抑える
        Px $bmp ($ox+8) ($oy+3) $BD; Px $bmp ($ox+9) ($oy+3) $BD
        Px $bmp ($ox+8) ($oy+4) $BR; Px $bmp ($ox+9) ($oy+4) $BL
        Px $bmp ($ox+3) ($oy+11) $BD; Px $bmp ($ox+4) ($oy+11) $BD
        Px $bmp ($ox+3) ($oy+12) $BR; Px $bmp ($ox+4) ($oy+12) $BL
    }
}

# ---------------- 柱(2x2 = 32x32)。障害物として一目で分かる塊感を出す ----------------
function Draw-Pillar { param($bmp,[int]$ox,[int]$oy,[int]$style)
    $W = 32
    # 背景は透過にせず床が見える想定はしない(TileMap上は別レイヤ)。ここでは柱本体のみ描く。
    for ($y=0; $y -lt $W; $y++) { for ($x=0; $x -lt $W; $x++) {
        Px $bmp ($ox+$x) ($oy+$y) ([System.Drawing.Color]::FromArgb(0,0,0,0))
    } }
    # 柱の輪郭: 上部の柱頭(広い) / 中央の軸(細い) / 下部の台座(広い)
    for ($y=0; $y -lt $W; $y++) {
        $halfW = 9
        if ($y -lt 5)        { $halfW = 12 }   # 柱頭
        elseif ($y -lt 8)    { $halfW = 10 }
        elseif ($y -lt 24)   { $halfW = 8 }    # 軸
        elseif ($y -lt 27)   { $halfW = 10 }
        else                 { $halfW = 12 }   # 台座
        for ($x = 16-$halfW; $x -lt 16+$halfW; $x++) {
            $c = $S5
            if ($x -lt 16-$halfW+2) { $c = $S6 }          # 左ハイライト
            elseif ($x -ge 16+$halfW-2) { $c = $S2 }      # 右シャドウ
            Px $bmp ($ox+$x) ($oy+$y) $c
        }
        # 輪郭線
        Px $bmp ($ox+16-$halfW)   ($oy+$y) $S0
        Px $bmp ($ox+16+$halfW-1) ($oy+$y) $S0
    }
    # 上端・下端の輪郭
    for ($x=4; $x -lt 28; $x++) { Px $bmp ($ox+$x) $oy $S0; Px $bmp ($ox+$x) ($oy+$W-1) $S0 }
    # bronzeの帯(柱頭と台座)。ここが唯一の金の主張
    for ($x=5; $x -lt 27; $x++) {
        Px $bmp ($ox+$x) ($oy+5) $BD
        Px $bmp ($ox+$x) ($oy+6) $BR
        Px $bmp ($ox+$x) ($oy+26) $BD
        Px $bmp ($ox+$x) ($oy+27) $BR
    }
    for ($x=6; $x -lt 26; $x+=4) { Px $bmp ($ox+$x) ($oy+6) $BL; Px $bmp ($ox+$x) ($oy+27) $BL }
    if ($style -eq 1) {
        # 変種B: 軸に縦溝を入れる
        for ($y=9; $y -lt 24; $y++) {
            Px $bmp ($ox+13) ($oy+$y) $S4
            Px $bmp ($ox+18) ($oy+$y) $S4
        }
    } else {
        # 変種A: 軸中央に淡い縦ハイライト
        for ($y=9; $y -lt 24; $y++) { Px $bmp ($ox+11) ($oy+$y) $S6 }
    }
}

# ---------------- 危険地帯の噴出口(2x2)。危険地帯の中心に置く目印 ----------------
function Draw-HazardVent { param($bmp,[int]$ox,[int]$oy,[int]$seed)
    $rnd = New-Object System.Random $seed
    for ($y=0; $y -lt 32; $y++) { for ($x=0; $x -lt 32; $x++) {
        Px $bmp ($ox+$x) ($oy+$y) $H0
    } }
    # 中心から放射する亀裂
    $cx = 16; $cy = 16
    for ($a=0; $a -lt 8; $a++) {
        $ang = [Math]::PI * 2 * $a / 8.0
        $len = 11 + $rnd.Next(0,4)
        for ($t=2; $t -lt $len; $t++) {
            $x = [int][Math]::Round($cx + [Math]::Cos($ang)*$t)
            $y = [int][Math]::Round($cy + [Math]::Sin($ang)*$t)
            $c = if ($t -lt $len*0.55) { $H3 } else { $H2 }
            Px $bmp ($ox+$x) ($oy+$y) $c
        }
    }
    # 中心の孔
    for ($y=-4; $y -le 4; $y++) { for ($x=-4; $x -le 4; $x++) {
        $d = [Math]::Sqrt($x*$x + $y*$y)
        if ($d -le 2.2) { Px $bmp ($ox+$cx+$x) ($oy+$cy+$y) $H4 }
        elseif ($d -le 3.6) { Px $bmp ($ox+$cx+$x) ($oy+$cy+$y) $H3 }
        elseif ($d -le 4.4) { Px $bmp ($ox+$cx+$x) ($oy+$cy+$y) $H2 }
    } }
}

# ---------------- 瓦礫(2x2)。大広間の隅などに置いて単調さを崩す装飾 ----------------
function Draw-Rubble { param($bmp,[int]$ox,[int]$oy,[int]$seed)
    $rnd = New-Object System.Random $seed
    for ($y=0; $y -lt 32; $y++) { for ($x=0; $x -lt 32; $x++) {
        Px $bmp ($ox+$x) ($oy+$y) ([System.Drawing.Color]::FromArgb(0,0,0,0))
    } }
    # 大小の石塊を積む
    $blocks = @(@(6,18,9,7), @(15,20,11,8), @(11,12,8,7), @(19,13,7,6))
    foreach ($b in $blocks) {
        $bx=$b[0]; $by=$b[1]; $bw=$b[2]; $bh=$b[3]
        for ($y=0; $y -lt $bh; $y++) { for ($x=0; $x -lt $bw; $x++) {
            $c = $S4
            if ($y -eq 0 -or $x -eq 0) { $c = $S5 }
            if ($y -eq $bh-1 -or $x -eq $bw-1) { $c = $S1 }
            Px $bmp ($ox+$bx+$x) ($oy+$by+$y) $c
        } }
    }
    # 細かい欠片
    for ($i=0; $i -lt 12; $i++) {
        $x = $rnd.Next(4,28); $y = $rnd.Next(10,30)
        Px $bmp ($ox+$x) ($oy+$y) $S2
    }
}

# ---------------- 小物列(行5) ----------------
function Draw-SmallProp { param($bmp,[int]$ox,[int]$oy,[int]$kind,[int]$seed)
    $rnd = New-Object System.Random $seed
    FillTile $bmp $ox $oy ([System.Drawing.Color]::FromArgb(0,0,0,0))
    switch ($kind) {
        0 { # 小瓦礫
            for ($i=0; $i -lt 9; $i++) {
                $x = $rnd.Next(3,13); $y = $rnd.Next(6,14)
                Px $bmp ($ox+$x) ($oy+$y) $S4
                Px $bmp ($ox+$x) ($oy+$y+1) $S1
            }
        }
        1 { # 床のひび
            $x = 3
            for ($y=3; $y -lt 14; $y++) {
                Px $bmp ($ox+$x) ($oy+$y) $S1
                $x += $rnd.Next(0,2)
                if ($x -gt 13) { $x = 13 }
            }
        }
        2 { # bronze格子(排水溝)
            for ($y=4; $y -lt 13; $y++) { for ($x=4; $x -lt 13; $x++) {
                Px $bmp ($ox+$x) ($oy+$y) $S0
            } }
            for ($x=5; $x -lt 12; $x+=2) { for ($y=5; $y -lt 12; $y++) {
                Px $bmp ($ox+$x) ($oy+$y) $BD
            } }
            for ($x=5; $x -lt 12; $x+=2) { Px $bmp ($ox+$x) ($oy+5) $BR }
        }
        3 { # 苔/汚れ(大広間の隅用)
            for ($i=0; $i -lt 16; $i++) {
                $x = $rnd.Next(2,14); $y = $rnd.Next(2,14)
                Px $bmp ($ox+$x) ($oy+$y) $S2
            }
        }
        4 { # 危険地帯の縁(通常床→危険床の境界)
            for ($y=0; $y -lt $T; $y++) { for ($x=0; $x -lt $T; $x++) {
                $c = if ($x -lt 8) { $S3 } else { $H0 }
                Px $bmp ($ox+$x) ($oy+$y) $c
            } }
            for ($y=0; $y -lt $T; $y++) {
                Px $bmp ($ox+7) ($oy+$y) $S1
                Px $bmp ($ox+8) ($oy+$y) $H1
            }
            for ($i=0; $i -lt 4; $i++) {
                $y = $rnd.Next(0,16)
                Px $bmp ($ox+9) ($oy+$y) $H2
            }
        }
        5 { # bronzeの床標(枝の先=報酬地点の目印)
            for ($y=5; $y -lt 12; $y++) { for ($x=5; $x -lt 12; $x++) {
                Px $bmp ($ox+$x) ($oy+$y) $S2
            } }
            for ($x=5; $x -lt 12; $x++) { Px $bmp ($ox+$x) ($oy+5) $BD; Px $bmp ($ox+$x) ($oy+11) $BD }
            for ($y=5; $y -lt 12; $y++) { Px $bmp ($ox+5) ($oy+$y) $BD; Px $bmp ($ox+11) ($oy+$y) $BD }
            Px $bmp ($ox+8) ($oy+7) $BR; Px $bmp ($ox+8) ($oy+8) $BL; Px $bmp ($ox+8) ($oy+9) $BR
            Px $bmp ($ox+7) ($oy+8) $BR; Px $bmp ($ox+9) ($oy+8) $BR
        }
        6 { # 骨(装飾)
            for ($x=5; $x -lt 12; $x++) { Px $bmp ($ox+$x) ($oy+9) $S6 }
            Px $bmp ($ox+4) ($oy+8) $S6; Px $bmp ($ox+4) ($oy+10) $S6
            Px $bmp ($ox+12) ($oy+8) $S6; Px $bmp ($ox+12) ($oy+10) $S6
            for ($x=5; $x -lt 12; $x++) { Px $bmp ($ox+$x) ($oy+10) $S4 }
        }
        7 { # 隘路の壁際の傷(方向感を補強)
            for ($x=2; $x -lt 14; $x++) {
                Px $bmp ($ox+$x) ($oy+6) $S1
                Px $bmp ($ox+$x) ($oy+7) $S4
            }
            for ($x=4; $x -lt 12; $x++) {
                Px $bmp ($ox+$x) ($oy+10) $S1
                Px $bmp ($ox+$x) ($oy+11) $S4
            }
        }
    }
}

# ================= 生成 =================
$bmp = New-Object System.Drawing.Bitmap ($COLS*$T), ($ROWS*$T)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Transparent)
$g.Dispose()

# 行0: 大広間床 x4 / 危険地帯床 x4
for ($i=0; $i -lt 4; $i++) { Draw-ArenaFloor  $bmp ($i*$T)        0 (100+$i) }
for ($i=0; $i -lt 4; $i++) { Draw-HazardFloor $bmp (($i+4)*$T)    0 (200+$i) }
# 行1: 柱林床 x4 / 隘路床 x4
for ($i=0; $i -lt 4; $i++) { Draw-PillarFloor $bmp ($i*$T)       $T (300+$i) }
for ($i=0; $i -lt 4; $i++) { Draw-ChokeFloor  $bmp (($i+4)*$T)   $T (400+$i) }
# 行2: 壁 x4 / 壁(bronze装飾) x4
for ($i=0; $i -lt 4; $i++) { Draw-Wall $bmp ($i*$T)     ($T*2) (500+$i) $false }
for ($i=0; $i -lt 4; $i++) { Draw-Wall $bmp (($i+4)*$T) ($T*2) (600+$i) $true }
# 行3-4: 柱A / 柱B / 噴出口 / 瓦礫 (各2x2)
Draw-Pillar     $bmp 0        ($T*3) 0
Draw-Pillar     $bmp ($T*2)   ($T*3) 1
Draw-HazardVent $bmp ($T*4)   ($T*3) 700
Draw-Rubble     $bmp ($T*6)   ($T*3) 800
# 行5: 小物 x8
for ($i=0; $i -lt 8; $i++) { Draw-SmallProp $bmp ($i*$T) ($T*5) $i (900+$i) }

$tilesetPath = Join-Path $OutDir "dungeon_tileset_retro.png"
$bmp.Save($tilesetPath, [System.Drawing.Imaging.ImageFormat]::Png)

# 歩ける王家の紋章床。半透明/AAを使わず、欠けた八角形と剣の彫刻を48pxで描く。
$crest = New-Object System.Drawing.Bitmap 48,48
for ($y=0; $y -lt 48; $y++) {
    for ($x=0; $x -lt 48; $x++) {
        $dx=[Math]::Abs($x-23.5); $dy=[Math]::Abs($y-23.5)
        if ($dx -le 22 -and $dy -le 22 -and ($dx+$dy) -le 36) {
            $color=$S2
            if ($dx -ge 20 -or $dy -ge 20 -or ($dx+$dy) -ge 33) { $color=$S5 }
            if ($y -gt 36) { $color=$S1 }
            Px $crest $x $y $color
        }
        if ($x -ge 22 -and $x -le 25 -and $y -ge 10 -and $y -le 34) { Px $crest $x $y $BR }
        if ($x -ge 15 -and $x -le 32 -and $y -ge 28 -and $y -le 30) { Px $crest $x $y $BD }
        if ($y -ge 8 -and $y -le 12 -and $dx -le ($y-8)) { Px $crest $x $y $BL }
    }
}
$crest.Save((Join-Path $OutDir 'royal_crest.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$crest.Dispose()

# ---------------- 目視確認用プレビュー(8倍 + グリッド線 + 座標) ----------------
$SCALE = 8
$pw = $bmp.Width * $SCALE
$ph = $bmp.Height * $SCALE
$pv = New-Object System.Drawing.Bitmap $pw, $ph
$pg = [System.Drawing.Graphics]::FromImage($pv)
$pg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$pg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
$pg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
# 背景を暗くして透過部分が分かるようにする
$pg.Clear((Hex "0a0714"))
$pg.DrawImage($bmp, (New-Object System.Drawing.Rectangle 0,0,$pw,$ph))
# タイル境界のグリッド線
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(90,255,226,122)), 1
for ($c=0; $c -le $COLS; $c++) { $pg.DrawLine($pen, $c*$T*$SCALE, 0, $c*$T*$SCALE, $ph) }
for ($r=0; $r -le $ROWS; $r++) { $pg.DrawLine($pen, 0, $r*$T*$SCALE, $pw, $r*$T*$SCALE) }
$pen.Dispose()
$pg.Dispose()
$previewPath = Join-Path $OutDir "_preview_tileset.png"
$pv.Save($previewPath, [System.Drawing.Imaging.ImageFormat]::Png)

$bmp.Dispose()
$pv.Dispose()

Write-Output "tileset: $tilesetPath"
Write-Output "preview: $previewPath"



