"""サバイバルの床だけの戦場に敷く「床の飾り（デカール）」と空気感の素材を生成する。

  python3 tools/map_unified/build.py              # assets/visuals/floor_decals/ へ書き出す
  python3 tools/map_unified/build.py --board DIR  # 2倍のプレビューも書く

- 1 ドット＝画面 2px（キャラクター・VFX・UI と同じ密度）。各デカールは 32×32 ドット＝64px（床 2 マス）。
- 1 テーマにつき 16 個（8 列 × 2 行）。列 0〜9 は共通形（ひび・瓦礫・欠け・水たまり・骨・苔・格子・染み）を
  テーマの色で、列 10〜15 はテーマ専用（MAP1 骸と鎖・古い紋、MAP2 紫晶の群生・鉱脈、MAP3 熔岩のひび・鉱滓・歯車）。
- EMISSIVE に印を付けた列は、ゲーム側が光だまりを重ねる（紫晶・熔岩）。
- vignette.png（画面の縁を暗く）と glow.png（光だまり）も同じフォルダへ出す。
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "visuals" / "floor_decals"
D = 32  # デカールの一辺（ドット）
COLS, ROWS = 8, 2


def hx(v: str, a: int = 255):
    v = v.lstrip("#")
    return np.array([int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16), a], np.uint8)


# テーマごとの色：暗い線 / 石の暗 / 石の明 / 差し色（暗→明）
THEMES = {
    1: dict(line="151a26", dark="2e3646", light="7f8ca3", bone=["7a7060", "c0b494", "e6dcc0"], accent=["16444a", "2b8086", "7ae0d8"], water=["141c2c", "243448", "4a6a8a"], moss=["1e3828", "35603a", "5a9458"]),
    2: dict(line="120d20", dark="2a2140", light="7a6aa8", bone=["5a5068", "a090b8", "d8c8e8"], accent=["4a1a7a", "8a3ad0", "ecd0ff"], water=["1a1030", "2e2050", "5a48a0"], moss=["2a2448", "48408a", "7a70c0"]),
    3: dict(line="140c08", dark="3a2c22", light="8a7868", bone=["6a5a48", "a89070", "d8c4a0"], accent=["7a2208", "ff8a2a", "ffd080"], water=["2a1a10", "4a2c18", "7a4a28"], moss=["3a2a14", "6a4a1c", "9a7030"]),
}
EMISSIVE = {1: [12, 13], 2: [10, 11, 12, 13, 14, 15], 3: [10, 11, 12, 13]}


class Dots:
    def __init__(self):
        self.px = np.zeros((D, D, 4), np.uint8)

    def set(self, x, y, c):
        x, y = int(x), int(y)
        if 0 <= x < D and 0 <= y < D:
            self.px[y, x] = c

    def rect(self, x0, y0, x1, y1, c):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.set(x, y, c)

    def line(self, pts, c, rng=None, jitter=0.0):
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
            for i in range(n + 1):
                t = i / max(n, 1)
                x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
                if rng is not None and jitter:
                    x += rng.uniform(-jitter, jitter)
                    y += rng.uniform(-jitter, jitter)
                self.set(round(x), round(y), c)

    def disc(self, cx, cy, r, c, rx=None):
        rx = rx or r
        for y in range(D):
            for x in range(D):
                if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / r) ** 2 <= 1.0:
                    self.set(x, y, c)

    def blob(self, cx, cy, r, c, seed, amp=0.35, n=9, rx=None):
        rng = np.random.default_rng(seed)
        rx = rx or r
        ks = [1 - amp * rng.random() for _ in range(n)]
        for y in range(D):
            for x in range(D):
                dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / r
                a = math.atan2(dy, dx)
                i = int((a + math.pi) / (2 * math.pi) * n) % n
                k = ks[i] * 0.6 + ks[(i + 1) % n] * 0.4
                if dx * dx + dy * dy <= k * k:
                    self.set(x, y, c)

    def outline_dark(self, c):
        a = self.px[:, :, 3] > 0
        ring = np.zeros_like(a)
        ring[1:, :] |= a[:-1, :]
        ring[:-1, :] |= a[1:, :]
        ring[:, 1:] |= a[:, :-1]
        ring[:, :-1] |= a[:, 1:]
        self.px[ring & ~a] = c


def crack(d, P, seed, branches=2, long=True):
    rng = np.random.default_rng(seed)
    line = hx(P["line"])
    light = hx(P["light"])
    x, y = rng.uniform(4, 10), rng.uniform(6, 26)
    pts = [(x, y)]
    for _ in range(5 if long else 3):
        x += rng.uniform(3, 6)
        y += rng.uniform(-4, 4)
        pts.append((x, y))
    d.line(pts, line)
    # ひびの右下側に細い明るい縁（光は左上）
    d.line([(px + 1, py + 1) for px, py in pts], hx(P["light"], 140))
    for _ in range(branches):
        i = rng.integers(1, len(pts) - 1)
        bx, by = pts[i]
        d.line([(bx, by), (bx + rng.uniform(-4, 4), by + rng.uniform(3, 7) * rng.choice([-1, 1]))], line)
    return light


def rubble(d, P, seed, count=5):
    rng = np.random.default_rng(seed)
    for k in range(count):
        cx, cy = rng.uniform(6, 26), rng.uniform(8, 26)
        r = rng.uniform(1.5, 3.5)
        d.disc(cx, cy, r, hx(P["dark"]), rx=r * 1.3)
        d.disc(cx - 0.5, cy - 0.7, r * 0.55, hx(P["light"]), rx=r * 0.8)
    d.outline_dark(hx(P["line"]))


def missing_tile(d, P, seed):
    rng = np.random.default_rng(seed)
    x0, y0 = 6, 8
    d.blob(16, 17, 8, hx(P["line"]), seed, amp=0.25, n=8, rx=10)
    d.blob(15, 16, 6.5, hx("0a0c12"), seed + 1, amp=0.3, n=8, rx=8.5)
    for _ in range(6):
        d.set(rng.integers(8, 24), rng.integers(10, 24), hx(P["dark"]))


def puddle(d, P, seed):
    w = P["water"]
    d.blob(16, 18, 7, hx(w[0], 230), seed, amp=0.3, n=10, rx=11)
    d.blob(15, 17, 5, hx(w[1], 230), seed + 2, amp=0.3, n=9, rx=8)
    d.line([(10, 15), (14, 14)], hx(w[2], 200))
    d.line([(17, 20), (20, 20)], hx(w[2], 150))


def bones(d, P, seed, skull=False):
    b = P["bone"]
    rng = np.random.default_rng(seed)
    for k in range(3):
        x0, y0 = rng.uniform(5, 14), rng.uniform(8, 24)
        ang = rng.uniform(-0.6, 0.6)
        L = rng.uniform(8, 13)
        x1, y1 = x0 + math.cos(ang) * L, y0 + math.sin(ang) * L
        d.line([(x0, y0), (x1, y1)], hx(b[1]))
        d.line([(x0, y0 - 1), (x1, y1 - 1)], hx(b[2]))
        for (x, y) in ((x0, y0), (x1, y1)):
            d.disc(x, y, 1.6, hx(b[1]))
            d.set(x - 1, y - 1, hx(b[2]))
    if skull:
        d.disc(22, 12, 4.5, hx(b[1]), rx=4.2)
        d.rect(19, 14, 25, 16, hx(b[1]))
        d.disc(21, 11, 1.8, hx(b[2]), rx=1.6)
        d.set(20, 11, hx(P["line"]))
        d.set(23, 11, hx(P["line"]))
        d.set(20, 15, hx(P["line"]))
        d.set(22, 15, hx(P["line"]))
        d.set(24, 15, hx(P["line"]))
    d.outline_dark(hx(P["line"]))


def moss(d, P, seed):
    m = P["moss"]
    rng = np.random.default_rng(seed)
    d.blob(16, 16, 8, hx(m[0], 210), seed, amp=0.45, n=11, rx=11)
    d.blob(14, 15, 5, hx(m[1], 210), seed + 3, amp=0.45, n=9, rx=7)
    for _ in range(14):
        d.set(rng.integers(6, 26), rng.integers(8, 24), hx(m[2], 200))


def grate(d, P, seed):
    line = hx(P["line"])
    d.rect(8, 8, 24, 24, hx(P["dark"]))
    for i in range(9, 24, 3):
        d.rect(i, 9, i, 23, hx("07080c"))
    d.rect(8, 8, 24, 8, hx(P["light"]))
    d.rect(8, 8, 8, 24, hx(P["light"]))
    d.outline_dark(line)
    for (x, y) in ((8, 8), (24, 8), (8, 24), (24, 24)):
        d.set(x, y, hx(P["light"]))


def stain(d, P, seed):
    d.blob(16, 16, 9, hx(P["line"], 90), seed, amp=0.5, n=12, rx=12)
    d.blob(16, 16, 5, hx(P["line"], 70), seed + 5, amp=0.5, n=9, rx=7)


# ---- テーマ専用
def chains(d, P, seed):
    rng = np.random.default_rng(seed)
    y = 16
    for i in range(5, 28, 4):
        d.rect(i, y - 1, i + 2, y + 1, hx(P["light"]))
        d.set(i + 1, y, hx(P["dark"]))
    d.disc(26, 12, 3, hx(P["bone"][1]))
    d.outline_dark(hx(P["line"]))


def rune_circle(d, P, seed):
    a = P["accent"]
    for y in range(D):
        for x in range(D):
            r = math.hypot(x + 0.5 - 16, y + 0.5 - 16)
            if 10.5 <= r <= 11.5 or 7.5 <= r <= 8.2:
                d.set(x, y, hx(a[1], 200))
    for k in range(6):
        ang = k * math.pi / 3
        d.set(16 + math.cos(ang) * 9.5, 16 + math.sin(ang) * 9.5, hx(a[2], 230))
    d.line([(12, 16), (16, 12), (20, 16), (16, 20), (12, 16)], hx(a[1], 200))


def crystals(d, P, seed, count=4):
    a = P["accent"]
    rng = np.random.default_rng(seed)
    for k in range(count):
        cx, cy = rng.uniform(9, 23), rng.uniform(16, 26)
        h = rng.uniform(6, 12)
        w = rng.uniform(2, 3.5)
        tip = (cx + rng.uniform(-3, 3), cy - h)
        # 二面の結晶
        pts_l = [(cx - w, cy), (tip[0] - 0.5, tip[1]), (cx, cy)]
        pts_r = [(cx + w, cy), (tip[0] + 0.5, tip[1]), (cx, cy)]
        for y in range(D):
            for x in range(D):
                px, py = x + 0.5, y + 0.5
                if _in_tri(px, py, pts_l):
                    d.set(x, y, hx(a[1]))
                if _in_tri(px, py, pts_r):
                    d.set(x, y, hx(a[0]))
        d.line([(cx - w + 1, cy - 1), tip], hx(a[2]))
    d.blob(16, 25, 3, hx(P["dark"]), seed + 7, amp=0.4, n=8, rx=9)
    d.outline_dark(hx(P["line"]))


def vein(d, P, seed):
    a = P["accent"]
    rng = np.random.default_rng(seed)
    pts = [(3, rng.uniform(10, 22))]
    for i in range(6):
        pts.append((pts[-1][0] + 4.5, pts[-1][1] + rng.uniform(-3, 3)))
    d.line(pts, hx(P["line"]))
    d.line([(x, y) for x, y in pts], hx(a[1], 230))
    for i in range(1, len(pts) - 1, 2):
        d.set(pts[i][0], pts[i][1], hx(a[2]))


def lava_crack(d, P, seed):
    a = P["accent"]
    rng = np.random.default_rng(seed)
    pts = [(2, rng.uniform(10, 22))]
    for i in range(7):
        pts.append((pts[-1][0] + 4, pts[-1][1] + rng.uniform(-4, 4)))
    d.line(pts, hx("2a0c04"))
    d.line([(x, y + 1) for x, y in pts], hx("2a0c04"))
    d.line([(x, y - 1) for x, y in pts], hx(a[0]))
    d.line(pts, hx(a[1]))
    for i in range(0, len(pts), 2):
        d.set(pts[i][0], pts[i][1], hx(a[2]))
    for _ in range(2):
        i = rng.integers(1, len(pts) - 1)
        bx, by = pts[i]
        d.line([(bx, by), (bx + rng.uniform(-3, 3), by + rng.uniform(4, 8) * rng.choice([-1, 1]))], hx(a[1]))


def slag(d, P, seed):
    rng = np.random.default_rng(seed)
    d.blob(16, 20, 5, hx("2a2220"), seed, amp=0.4, n=9, rx=10)
    d.blob(15, 18, 3.5, hx("4a3a34"), seed + 1, amp=0.4, n=8, rx=7)
    for _ in range(5):
        d.set(rng.integers(9, 23), rng.integers(16, 24), hx(P["accent"][1]))
    d.outline_dark(hx(P["line"]))


def gear_plate(d, P, seed):
    for y in range(D):
        for x in range(D):
            r = math.hypot(x + 0.5 - 16, y + 0.5 - 16)
            a = math.atan2(y + 0.5 - 16, x + 0.5 - 16)
            tooth = 9.5 + (2.2 if int((a + math.pi) / (2 * math.pi) * 10) % 2 == 0 else 0)
            if r <= tooth and r >= 3.5:
                d.set(x, y, hx(P["dark"]) if r > 7 else hx(P["light"]))
    d.outline_dark(hx(P["line"]))
    for k in range(4):
        ang = k * math.pi / 2 + math.pi / 4
        d.set(16 + math.cos(ang) * 5.5, 16 + math.sin(ang) * 5.5, hx(P["line"]))


def scorch(d, P, seed):
    d.blob(16, 16, 9, hx("0c0806", 150), seed, amp=0.5, n=12, rx=12)
    d.blob(16, 16, 5, hx("0c0806", 150), seed + 2, amp=0.5, n=9, rx=7)
    for k in range(5):
        ang = k * 2 * math.pi / 5 + 0.4
        d.line([(16 + math.cos(ang) * 6, 16 + math.sin(ang) * 6), (16 + math.cos(ang) * 11, 16 + math.sin(ang) * 11)], hx("0c0806", 150))


def _in_tri(px, py, pts):
    (x1, y1), (x2, y2), (x3, y3) = pts
    d1 = (px - x2) * (y1 - y2) - (x1 - x2) * (py - y2)
    d2 = (px - x3) * (y2 - y3) - (x2 - x3) * (py - y3)
    d3 = (px - x1) * (y3 - y1) - (x3 - x1) * (py - y1)
    neg = d1 < 0 or d2 < 0 or d3 < 0
    pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (neg and pos)


def build_theme(theme: int) -> Image.Image:
    P = THEMES[theme]
    common = [
        lambda d, s: crack(d, P, s, 2, True),
        lambda d, s: crack(d, P, s + 1, 1, False),
        lambda d, s: rubble(d, P, s, 5),
        lambda d, s: rubble(d, P, s + 1, 3),
        lambda d, s: missing_tile(d, P, s),
        lambda d, s: puddle(d, P, s),
        lambda d, s: bones(d, P, s, skull=theme == 1),
        lambda d, s: moss(d, P, s),
        lambda d, s: grate(d, P, s),
        lambda d, s: stain(d, P, s),
    ]
    special = {
        1: [lambda d, s: chains(d, P, s), lambda d, s: bones(d, P, s + 9, skull=True), lambda d, s: rune_circle(d, P, s), lambda d, s: rune_circle(d, P, s + 1), lambda d, s: stain(d, P, s + 3), lambda d, s: crack(d, P, s + 4, 3, True)],
        2: [lambda d, s: crystals(d, P, s, 4), lambda d, s: crystals(d, P, s + 1, 2), lambda d, s: vein(d, P, s), lambda d, s: vein(d, P, s + 1), lambda d, s: crystals(d, P, s + 2, 5), lambda d, s: vein(d, P, s + 2)],
        3: [lambda d, s: lava_crack(d, P, s), lambda d, s: lava_crack(d, P, s + 1), lambda d, s: slag(d, P, s), lambda d, s: lava_crack(d, P, s + 2), lambda d, s: scorch(d, P, s), lambda d, s: gear_plate(d, P, s)],
    }[theme]
    fns = common + special
    sheet = Image.new("RGBA", (COLS * D * 2, ROWS * D * 2), (0, 0, 0, 0))
    for index, fn in enumerate(fns[: COLS * ROWS]):
        d = Dots()
        fn(d, 100 * theme + index)
        im = Image.fromarray(d.px, "RGBA").resize((D * 2, D * 2), Image.NEAREST)
        sheet.alpha_composite(im, ((index % COLS) * D * 2, (index // COLS) * D * 2))
    return sheet


def radial(size: int, inner: float, power: float, invert: bool) -> Image.Image:
    yy, xx = np.mgrid[0:size, 0:size]
    r = np.hypot(xx + 0.5 - size / 2, yy + 0.5 - size / 2) / (size / 2)
    v = np.clip((r - inner) / (1 - inner), 0, 1) ** power
    a = v if invert else 1 - v
    out = np.zeros((size, size, 4), np.uint8)
    out[:, :, :3] = 255
    out[:, :, 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def main():
    board_dir = Path(sys.argv[sys.argv.index("--board") + 1]) if "--board" in sys.argv else None
    OUT.mkdir(parents=True, exist_ok=True)
    sheets = {}
    for theme in (1, 2, 3):
        sheets[theme] = build_theme(theme)
        sheets[theme].save(OUT / f"map{theme}.png")
    # 画面の縁の暗がり（中央は透明）と光だまり
    radial(256, 0.45, 1.6, True).save(OUT / "vignette.png")
    radial(64, 0.0, 1.2, False).save(OUT / "glow.png")
    (OUT / "manifest.json").write_text(json.dumps({"decal_px": D * 2, "cols": COLS, "rows": ROWS, "emissive": EMISSIVE}, indent=2), encoding="utf-8")
    if board_dir:
        board_dir.mkdir(parents=True, exist_ok=True)
        from PIL import ImageDraw

        floor = {t: Image.open(ROOT / "assets" / "visuals" / "ember_v5" / f"map{t}_floor.png").convert("RGBA").resize((256, 256), Image.NEAREST) for t in (1, 2, 3)}
        b = Image.new("RGBA", (COLS * D * 2 * 2 + 16, (ROWS * D * 2 * 2 + 24) * 3), (40, 38, 46, 255))
        for k, theme in enumerate((1, 2, 3)):
            y = k * (ROWS * D * 2 * 2 + 24)
            tile = Image.new("RGBA", (COLS * D * 2, ROWS * D * 2))
            for ty in range(0, tile.height, 256):
                for tx in range(0, tile.width, 256):
                    tile.alpha_composite(floor[theme], (tx, ty))
            tile.alpha_composite(sheets[theme])
            b.alpha_composite(tile.resize((tile.width * 2, tile.height * 2), Image.NEAREST), (8, y + 20))
            ImageDraw.Draw(b).text((8, y + 4), f"map{theme}", fill=(230, 220, 200, 255))
        b.save(board_dir / "decals.png")
    print(f"wrote decals for 3 themes to {OUT}")


if __name__ == "__main__":
    main()
