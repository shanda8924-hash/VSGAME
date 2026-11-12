param(
    [string]$SourcePath = "",
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $projectRoot "assets/tilesets/dungeon/Dungeon tileset.png"
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot "assets/tilesets/dungeon"
}
$retroPath = Join-Path $OutputDirectory "Dungeon tileset_retro.png"
$terrainPath = Join-Path $OutputDirectory "terrain_regions.png"

function New-Color([int]$r, [int]$g, [int]$b, [int]$a = 255) {
    return [System.Drawing.Color]::FromArgb($a, $r, $g, $b)
}

function Mix-Color($from, $to, [double]$amount, [int]$alpha = 255) {
    $t = [Math]::Max(0.0, [Math]::Min(1.0, $amount))
    return New-Color `
        ([int][Math]::Round($from.R + ($to.R - $from.R) * $t)) `
        ([int][Math]::Round($from.G + ($to.G - $from.G) * $t)) `
        ([int][Math]::Round($from.B + ($to.B - $from.B) * $t)) `
        $alpha
}

$voidDeep = New-Color 33 41 53
$void = New-Color 43 52 67
$parchmentDim = New-Color 112 121 133
$bronzeDark = New-Color 104 76 42
$bronze = New-Color 189 146 80
$bronzeLight = New-Color 220 181 111
$hpDark = New-Color 73 22 58
$hpRed = New-Color 224 58 104
$hpRedLight = New-Color 255 138 168
$tealDark = New-Color 20 67 85
$teal = New-Color 30 196 214
$tealLight = New-Color 143 242 247
$purpleLight = New-Color 116 124 139

function Convert-PaletteColor($pixel) {
    if ($pixel.A -eq 0) {
        return [System.Drawing.Color]::Transparent
    }
    $brightness = [double]$pixel.GetBrightness()
    $saturation = [double]$pixel.GetSaturation()
    $hue = [double]$pixel.GetHue()
    $tone = [Math]::Pow($brightness, 0.86)
    if ($saturation -lt 0.13) {
        return Mix-Color $voidDeep $parchmentDim $tone $pixel.A
    }
    if ($hue -ge 22.0 -and $hue -lt 78.0) {
        return Mix-Color $bronzeDark $bronzeLight $tone $pixel.A
    }
    if ($hue -lt 22.0 -or $hue -ge 330.0) {
        return Mix-Color $hpDark $hpRedLight $tone $pixel.A
    }
    if ($hue -ge 78.0 -and $hue -lt 195.0) {
        return Mix-Color $tealDark $tealLight $tone $pixel.A
    }
    return Mix-Color $void $purpleLight $tone $pixel.A
}

$source = [System.Drawing.Bitmap]::new([string](Resolve-Path -LiteralPath $SourcePath))
$retro = [System.Drawing.Bitmap]::new($source.Width, $source.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
for ($y = 0; $y -lt $source.Height; $y++) {
    for ($x = 0; $x -lt $source.Width; $x++) {
        $retro.SetPixel($x, $y, (Convert-PaletteColor $source.GetPixel($x, $y)))
    }
}
$retro.Save($retroPath, [System.Drawing.Imaging.ImageFormat]::Png)
$retro.Dispose()
$source.Dispose()

Write-Output "Generated: $retroPath"
# CombatTerrainはtools/generate_dungeon_tileset.ps1の8x6 Atlasへ一本化した。
# 以下の旧terrain_regions.png生成部は再生成互換の参照用に残すが、実行しない。
return

$terrain = [System.Drawing.Bitmap]::new(128, 16, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

function Fill-Tile([int]$tileX, $color) {
    $left = $tileX * 16
    for ($y = 0; $y -lt 16; $y++) {
        for ($x = 0; $x -lt 16; $x++) {
            $terrain.SetPixel($left + $x, $y, $color)
        }
    }
}

function Pixel([int]$tileX, [int]$x, [int]$y, $color) {
    if ($x -ge 0 -and $x -lt 16 -and $y -ge 0 -and $y -lt 16) {
        $terrain.SetPixel($tileX * 16 + $x, $y, $color)
    }
}

function Rect([int]$tileX, [int]$x, [int]$y, [int]$width, [int]$height, $color) {
    for ($py = $y; $py -lt $y + $height; $py++) {
        for ($px = $x; $px -lt $x + $width; $px++) {
            Pixel $tileX $px $py $color
        }
    }
}

# 0-1: Arena。広い床を示すbronzeの角印と中央の控えめな星。
for ($tile = 0; $tile -le 1; $tile++) {
    Fill-Tile $tile (New-Color 45 39 82)
    foreach ($p in @(@(1,1),@(2,1),@(1,2),@(13,1),@(14,1),@(14,2),@(1,13),@(1,14),@(2,14),@(14,13),@(13,14),@(14,14))) {
        Pixel $tile $p[0] $p[1] $bronzeDark
    }
}
Pixel 0 7 7 $bronze
Pixel 0 8 7 $bronzeLight
Pixel 0 7 8 $bronzeLight
Pixel 0 8 8 $bronze
foreach ($p in @(@(4,4),@(11,4),@(4,11),@(11,11))) { Pixel 1 $p[0] $p[1] (New-Color 75 62 112) }

# 2: Pillar field床、3: 衝突柱。床は低彩度、柱だけ高い縦コントラスト。
Fill-Tile 2 (New-Color 38 34 70)
foreach ($p in @(@(3,3),@(12,3),@(3,12),@(12,12))) { Pixel 2 $p[0] $p[1] (New-Color 38 91 105) }
Fill-Tile 3 (New-Color 27 21 55)
Rect 3 4 2 8 12 (New-Color 72 56 105)
Rect 3 3 1 10 3 $bronzeDark
Rect 3 5 4 2 8 (New-Color 128 104 158)
Rect 3 9 4 2 8 (New-Color 47 35 79)
Rect 3 3 13 10 2 $bronze
Pixel 3 4 1 $bronzeLight
Pixel 3 11 1 $bronzeLight

# 4: Chokepoint床、5: 閉塞壁。平行線が進行方向を一目で示す。
Fill-Tile 4 (New-Color 42 34 69)
for ($x = 1; $x -lt 15; $x++) {
    Pixel 4 $x 5 $bronzeDark
    Pixel 4 $x 10 $bronzeDark
}
for ($x = 5; $x -le 10; $x++) {
    Pixel 4 $x 7 (New-Color 180 124 28)
    Pixel 4 $x 8 (New-Color 92 65 26)
}
Fill-Tile 5 (New-Color 24 18 49)
for ($y = 1; $y -lt 15; $y += 4) {
    Rect 5 1 $y 14 2 (New-Color 101 64 130)
    Pixel 5 ((($y * 3) % 11) + 2) ($y + 1) $bronzeDark
}
Rect 5 0 0 2 16 $bronzeDark
Rect 5 14 0 2 16 $bronzeDark

# 6-7: Hazard。暗い床に赤橙の割れ目を置き、背景より明確だがVFXより暗くする。
for ($tile = 6; $tile -le 7; $tile++) { Fill-Tile $tile (New-Color 49 24 60) }
foreach ($p in @(@(2,2),@(3,3),@(4,4),@(5,5),@(5,6),@(6,7),@(7,8),@(8,8),@(9,9),@(10,10),@(11,11),@(12,12),@(13,13),@(8,7),@(9,6))) {
    Pixel 6 $p[0] $p[1] $hpRed
}
foreach ($p in @(@(13,2),@(12,3),@(11,4),@(10,5),@(10,6),@(9,7),@(8,8),@(7,9),@(6,10),@(5,11),@(4,12),@(3,13),@(7,7),@(6,6))) {
    Pixel 7 $p[0] $p[1] $hpRedLight
}
Pixel 6 7 8 $bronze
Pixel 7 8 8 $bronzeLight

$terrain.Save($terrainPath, [System.Drawing.Imaging.ImageFormat]::Png)
$terrain.Dispose()

Write-Output "Generated: $retroPath"
Write-Output "Generated: $terrainPath"
