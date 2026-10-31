"""VSGAME UI の石板・古金スキン（9-slice テクスチャ一式）を生成する。

  python3 tools/ui_unified/build.py              # assets/ui/stoneworks/ へ書き出す
  python3 tools/ui_unified/build.py --board DIR  # 2倍のプレビューも DIR へ書く

設計（単位は「ドット」。1ドット＝画面2px。キャラクターと同じ密度で描き、最後に2倍へ拡大する）
- 石板：青灰の切り石。上・左の縁が明るく、下・右が暗い（光は左上）。面には薄い目地と欠け。
- 古金：4段ランプの金具。角の留め金・鋲・飾り紐・槍頭。
- 内側：暗い石の床目。9-slice の中央はタイルとして繰り返す。
- 外周：1ドットの最暗線で輪郭を立てる。
各 PNG の 9-slice マージン（画面px）は MARGINS に書き、ui/common/relic_frame_art.gd が同じ値を使う。
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "ui" / "stoneworks"


def hx(v: str):
    v = v.lstrip("#")
    return np.array([int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16), 255], np.uint8)


EDGE = hx("0b0c13")
STONE = [hx("232734"), hx("353b4c"), hx("4a5266"), hx("646d84"), hx("8a93a8")]  # 暗→明
FLOOR = [hx("12141c"), hx("171a23"), hx("1c2029"), hx("222633")]  # 内側の床
GOLD = [hx("5a3c10"), hx("9a6b22"), hx("cf9a34"), hx("f0cc62"), hx("fff0b8")]
TEAL = [hx("16444a"), hx("2b8086"), hx("4fb3b8"), hx("9ae6e4")]
RED = [hx("5a1418"), hx("a82a30"), hx("e04a44"), hx("ffb0a0")]


class Dots:
    def __init__(self, w: int, h: int):
        self.w, self.h = w, h
        self.px = np.zeros((h, w, 4), np.uint8)
        self.rng = np.random.default_rng(1203)

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y, x] = c

    def rect(self, x0, y0, x1, y1, c):
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, self.w - 1), min(y1, self.h - 1)
        if x1 >= x0 and y1 >= y0:
            self.px[y0 : y1 + 1, x0 : x1 + 1] = c

    def hline(self, x0, x1, y, c):
        self.rect(x0, y, x1, y, c)

    def vline(self, x, y0, y1, c):
        self.rect(x, y0, x, y1, c)

    # ---- 素材 ----
    def stone_slab(self, x0, y0, x1, y1, base=2, seed=0):
        """切り石の面。左上の縁は明、右下は暗、面に薄い目地と欠け。"""
        rng = np.random.default_rng(seed)
        self.rect(x0, y0, x1, y1, STONE[base])
        # 面のむら（2段だけ、まばら）
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                r = rng.random()
                if r < 0.07:
                    self.set(x, y, STONE[base - 1])
                elif r < 0.10:
                    self.set(x, y, STONE[base + 1] if base + 1 < len(STONE) else STONE[base])
        self.hline(x0, x1, y0, STONE[min(base + 2, 4)])
        self.vline(x0, y0, y1, STONE[min(base + 2, 4)])
        self.hline(x0 + 1, x1, y1, STONE[base - 1])
        self.vline(x1, y0 + 1, y1, STONE[base - 1])
        self.set(x0, y1, STONE[base])
        self.set(x1, y0, STONE[base])

    def chisel(self, x0, x1, y, horizontal=True, seed=0):
        """石の目地（暗い線＋その下の明るい線）。所々途切れる。"""
        rng = np.random.default_rng(seed)
        if horizontal:
            for x in range(x0, x1 + 1):
                if rng.random() < 0.85:
                    self.set(x, y, STONE[0])
                    self.set(x, y + 1, STONE[3])
        else:
            for yy in range(x0, x1 + 1):
                if rng.random() < 0.85:
                    self.set(y, yy, STONE[0])
                    self.set(y + 1, yy, STONE[3])

    def floor_tile(self, x0, y0, x1, y1, seed=5):
        """内側の暗い床。乱数は座標から決めるので、同じ座標なら同じ模様＝タイルがつながる。"""
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                h = (x * 73856093 ^ y * 19349663 ^ seed * 83492791) & 0xFFFF
                r = h / 0xFFFF
                c = FLOOR[1]
                if r < 0.06:
                    c = FLOOR[0]
                elif r < 0.12:
                    c = FLOOR[2]
                elif r < 0.135:
                    c = FLOOR[3]
                self.set(x, y, c)

    def gold_bar(self, x0, y0, x1, y1, lit=True):
        self.rect(x0, y0, x1, y1, GOLD[2])
        if x1 - x0 >= 2 or y1 - y0 >= 2:
            self.hline(x0, x1, y0, GOLD[3] if lit else GOLD[1])
            self.vline(x0, y0, y1, GOLD[3] if lit else GOLD[1])
            self.hline(x0, x1, y1, GOLD[1] if lit else GOLD[3])
            self.vline(x1, y0, y1, GOLD[1] if lit else GOLD[3])
            self.set(x0, y0, GOLD[4] if lit else GOLD[0])

    def rivet(self, x, y, big=False):
        if big:
            self.rect(x - 1, y - 1, x + 1, y + 1, GOLD[1])
            self.set(x, y, GOLD[3])
            self.set(x - 1, y - 1, GOLD[4])
            self.set(x + 1, y + 1, GOLD[0])
        else:
            self.set(x, y, GOLD[3])
            self.set(x + 1, y + 1, GOLD[0])
            self.set(x - 1, y - 1, GOLD[4])

    def rosette(self, x, y):
        """3×3 の菱形の飾り鋲。"""
        for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
            self.set(x + dx, y + dy, GOLD[2])
        self.set(x, y, GOLD[3])
        self.set(x, y - 1, GOLD[4])
        self.set(x, y + 1, GOLD[0])
        self.set(x + 1, y, GOLD[1])

    def gem(self, x, y, ramp=TEAL):
        for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
            self.set(x + dx, y + dy, ramp[1])
        self.set(x, y, ramp[2])
        self.set(x, y - 1, ramp[3])
        self.set(x + 1, y, ramp[0])
        self.set(x, y + 1, ramp[0])

    def corner_mount(self, cx, cy, sx, sy, reach=13):
        """角の金具。cx,cy は角のドット、sx,sy は内側へ向かう符号。
        角の金の台座 ＋ 2 ドット幅の L 字の帯 ＋ 帯の内側の渦 ＋ 鋲 ＋ 合わせ目の宝石。"""
        def P(dx, dy, c):
            self.set(cx + sx * dx, cy + sy * dy, c)
        # 台座（6×6）
        for dx in range(6):
            for dy in range(6):
                P(dx, dy, GOLD[2])
        for k in range(6):
            P(k, 0, GOLD[3]); P(0, k, GOLD[3]); P(k, 5, GOLD[0]); P(5, k, GOLD[0])
        P(0, 0, GOLD[4])
        # L 字の帯（2 ドット幅、先へ向かって細くなる）
        for k in range(6, reach):
            P(k, 0, GOLD[3]); P(k, 1, GOLD[2]); P(k, 2, GOLD[1] if k < reach - 3 else GOLD[0])
            P(0, k, GOLD[3]); P(1, k, GOLD[2]); P(2, k, GOLD[1] if k < reach - 3 else GOLD[0])
        P(reach, 0, GOLD[2]); P(reach, 1, GOLD[1]); P(reach + 1, 0, GOLD[1])
        P(0, reach, GOLD[2]); P(1, reach, GOLD[1]); P(0, reach + 1, GOLD[1])
        # 帯の内側の渦（角から斜めに）
        for k in range(3, 9):
            P(k, 3, GOLD[1] if k % 2 else GOLD[2])
            P(3, k, GOLD[1] if k % 2 else GOLD[2])
        for k in range(4, 8):
            P(k, k, GOLD[2])
        P(8, 8, GOLD[3]); P(9, 9, GOLD[1]); P(7, 9, GOLD[1]); P(9, 7, GOLD[1])
        # 鋲と宝石
        self.rivet(cx + sx * 1, cy + sy * 1)
        self.rivet(cx + sx * (reach - 2), cy + sy * 1)
        self.rivet(cx + sx * 1, cy + sy * (reach - 2))
        self.gem(cx + sx * 5, cy + sy * 5)

    def outline(self):
        a = self.px[:, :, 3] > 0
        ring = np.zeros_like(a)
        ring[1:, :] |= a[:-1, :]
        ring[:-1, :] |= a[1:, :]
        ring[:, 1:] |= a[:, :-1]
        ring[:, :-1] |= a[:, 1:]
        self.px[ring & ~a] = EDGE

    def image(self, scale: int = 2) -> Image.Image:
        im = Image.fromarray(self.px, "RGBA")
        return im.resize((self.w * scale, self.h * scale), Image.NEAREST)


# ------------------------------------------------------------------ 部品
def panel_major() -> Dots:
    """大パネル 56×56 ドット（112px）。マージン 16 ドット（32px）。中央 24 ドットがタイル。"""
    d = Dots(56, 56)
    d.floor_tile(0, 0, 55, 55)
    # 外枠の石のレール（1..7）
    d.rect(0, 0, 55, 55, EDGE)
    d.floor_tile(1, 1, 54, 54)
    d.stone_slab(1, 1, 54, 7, base=2, seed=1)
    d.stone_slab(1, 48, 54, 54, base=2, seed=2)
    d.stone_slab(1, 1, 7, 54, base=2, seed=3)
    d.stone_slab(48, 1, 54, 54, base=2, seed=4)
    # レールの目地（中央のタイル区間はまたがないよう端に寄せる）
    for x in (12, 20, 36, 44):
        d.vline(x, 2, 6, STONE[0])
        d.vline(x + 1, 2, 6, STONE[3])
        d.vline(x, 49, 53, STONE[0])
        d.vline(x + 1, 49, 53, STONE[3])
    for y in (12, 20, 36, 44):
        d.hline(2, 6, y, STONE[0])
        d.hline(2, 6, y + 1, STONE[3])
        d.hline(49, 53, y, STONE[0])
        d.hline(49, 53, y + 1, STONE[3])
    # 内側の金の細線と暗い溝
    d.rect(8, 8, 47, 47, EDGE)
    d.rect(9, 9, 46, 46, GOLD[2])
    d.hline(9, 46, 9, GOLD[3])
    d.vline(9, 9, 46, GOLD[3])
    d.hline(9, 46, 46, GOLD[1])
    d.vline(46, 9, 46, GOLD[1])
    d.rect(10, 10, 45, 45, FLOOR[0])
    d.floor_tile(11, 11, 44, 44)
    # 角の金具
    d.corner_mount(1, 1, 1, 1, 13)
    d.corner_mount(54, 1, -1, 1, 13)
    d.corner_mount(1, 54, 1, -1, 13)
    d.corner_mount(54, 54, -1, -1, 13)
    # 辺の中央の小さな留め金
    for (x, y) in ((27, 1), (28, 1), (27, 54), (28, 54)):
        d.rect(x, y if y == 1 else y - 3, x, y + 3 if y == 1 else y, GOLD[2])
    for (x, y) in ((1, 27), (1, 28), (54, 27), (54, 28)):
        d.rect(x if x == 1 else x - 3, y, x + 3 if x == 1 else x, y, GOLD[2])
    d.rivet(27, 4)
    d.rivet(27, 51)
    d.rivet(4, 27)
    d.rivet(51, 27)
    return d


def panel_inset() -> Dots:
    """内側パネル 28×28 ドット（56px）。マージン 8 ドット（16px）。中央 12 ドットがタイル。"""
    d = Dots(28, 28)
    d.rect(0, 0, 27, 27, EDGE)
    d.stone_slab(1, 1, 26, 26, base=1, seed=7)
    d.rect(4, 4, 23, 23, EDGE)
    d.rect(5, 5, 22, 22, GOLD[1])
    d.hline(5, 22, 5, GOLD[2])
    d.vline(5, 5, 22, GOLD[2])
    d.rect(6, 6, 21, 21, FLOOR[0])
    d.floor_tile(7, 7, 20, 20, seed=9)
    for x, y in ((3, 3), (24, 3), (3, 24), (24, 24)):
        d.rosette(x, y)
    return d


def button(state: str) -> Dots:
    """ボタン 28×28 ドット（56px）。マージン 8 ドット。中央はつぶして伸ばす。"""
    d = Dots(28, 28)
    d.rect(0, 0, 27, 27, EDGE)
    if state == "pressed":
        d.rect(1, 1, 26, 26, STONE[0])
        d.rect(2, 2, 25, 25, GOLD[1])
        d.hline(2, 25, 2, GOLD[0])
        d.vline(2, 2, 25, GOLD[0])
        d.hline(2, 25, 25, GOLD[2])
        d.vline(25, 2, 25, GOLD[2])
        d.rect(3, 3, 24, 24, FLOOR[0])
        d.rect(4, 4, 23, 23, FLOOR[1])
        d.hline(4, 23, 4, FLOOR[0])
        d.vline(4, 4, 23, FLOOR[0])
    else:
        hover = state == "hover"
        d.rect(1, 1, 26, 26, GOLD[2] if hover else GOLD[1])
        d.hline(1, 26, 1, GOLD[4] if hover else GOLD[3])
        d.vline(1, 1, 26, GOLD[4] if hover else GOLD[3])
        d.hline(2, 26, 26, GOLD[0])
        d.vline(26, 2, 26, GOLD[0])
        d.rect(3, 3, 24, 24, EDGE)
        d.stone_slab(4, 4, 23, 23, base=2 if hover else 1, seed=11)
        if state == "disabled":
            d.rect(1, 1, 26, 26, STONE[1])
            d.rect(3, 3, 24, 24, EDGE)
            d.rect(4, 4, 23, 23, STONE[0])
            d.hline(4, 23, 4, STONE[1])
            d.vline(4, 4, 23, STONE[1])
        else:
            for x, y in ((2, 2), (25, 2), (2, 25), (25, 25)):
                d.set(x, y, GOLD[4] if hover else GOLD[3])
    return d


def plaque() -> Dots:
    """見出しの板 72×18 ドット（144×36px）。左右マージン 22 ドット、上下 5 ドット。"""
    d = Dots(72, 18)
    cy = 8
    # 槍頭の形
    for y in range(18):
        dy = abs(y - cy)
        reach = max(0, 9 - dy)  # 先端の幅
        for x in range(reach):
            d.set(14 - x - 1, y, GOLD[1])
            d.set(57 + x + 1, y, GOLD[1])
    d.rect(14, 1, 57, 16, STONE[1])
    for x in range(72):
        pass
    # 石の面と上下の縁
    d.stone_slab(14, 1, 57, 16, base=1, seed=13)
    d.rect(16, 3, 55, 14, EDGE)
    d.rect(17, 4, 54, 13, GOLD[1])
    d.hline(17, 54, 4, GOLD[2])
    d.vline(17, 4, 13, GOLD[2])
    d.rect(18, 5, 53, 12, FLOOR[0])
    d.rect(19, 6, 52, 11, FLOOR[1])
    # 槍頭の陰影
    for y in range(18):
        dy = abs(y - cy)
        reach = max(0, 9 - dy)
        for x in range(reach):
            lx, rx = 13 - x, 58 + x
            tone = GOLD[3] if y < cy else GOLD[1]
            if x == reach - 1:
                d.set(lx, y, GOLD[0] if y > cy else GOLD[3])
                d.set(rx, y, GOLD[0] if y > cy else GOLD[3])
            elif x == 0:
                d.set(lx, y, GOLD[2])
                d.set(rx, y, GOLD[2])
            else:
                d.set(lx, y, tone if (x + y) % 3 else GOLD[2])
                d.set(rx, y, tone if (x + y) % 3 else GOLD[2])
    d.gem(8, cy)
    d.gem(63, cy)
    d.rivet(15, 2)
    d.rivet(56, 2)
    d.rivet(15, 15)
    d.rivet(56, 15)
    d.outline()
    return d


def slot() -> Dots:
    """所持品のマス 24×24 ドット（48px）。マージン 6 ドット。"""
    d = Dots(24, 24)
    d.rect(0, 0, 23, 23, EDGE)
    d.stone_slab(1, 1, 22, 22, base=1, seed=19)
    d.rect(3, 3, 20, 20, EDGE)
    d.rect(4, 4, 19, 19, FLOOR[0])
    d.rect(5, 5, 18, 18, FLOOR[1])
    d.hline(5, 18, 5, FLOOR[0])
    d.vline(5, 5, 18, FLOOR[0])
    for x, y in ((2, 2), (21, 2), (2, 21), (21, 21)):
        d.set(x, y, GOLD[2])
    d.set(2, 2, GOLD[3])
    return d


def bar(kind: str) -> Dots:
    """ゲージ 12×8 ドット（24×16px）。マージン 3 ドット。fill は白で描き、ゲーム側で色を掛ける。"""
    d = Dots(12, 8)
    if kind == "track":
        d.rect(0, 0, 11, 7, EDGE)
        d.rect(1, 1, 10, 6, STONE[1])
        d.hline(1, 10, 1, STONE[2])
        d.vline(1, 1, 6, STONE[2])
        d.rect(2, 2, 9, 5, FLOOR[0])
        d.hline(2, 9, 2, EDGE)
    else:
        w = hx("ffffff")
        d.rect(0, 0, 11, 7, hx("b0b0b0"))
        d.rect(1, 1, 10, 6, w)
        d.hline(0, 11, 0, hx("ffffff"))
        d.hline(0, 11, 7, hx("707070"))
        d.hline(1, 10, 3, hx("d8d8d8"))
    return d


def well() -> Dots:
    """区画の窪み 16×16 ドット（32px）。マージン 4 ドット。金具なし、1 ドットの石の縁＋暗い床。"""
    d = Dots(16, 16)
    d.rect(0, 0, 15, 15, EDGE)
    d.rect(1, 1, 14, 14, STONE[1])
    d.hline(1, 14, 1, STONE[2])
    d.vline(1, 1, 14, STONE[2])
    d.rect(2, 2, 13, 13, FLOOR[0])
    d.floor_tile(3, 3, 12, 12, seed=29)
    return d


def backdrop() -> Dots:
    """画面全体の後ろへ敷く暗い石畳 32×32 ドット（64px、タイル）。"""
    d = Dots(32, 32)
    d.floor_tile(0, 0, 31, 31, seed=23)
    for y in (0, 16):
        d.hline(0, 31, y, FLOOR[0])
    for x in (0, 16):
        d.vline(x, 0, 15, FLOOR[0])
        d.vline((x + 8) % 32, 16, 31, FLOOR[0])
    return d


# (ファイル名, 生成関数, 9-slice マージン(px: left, top, right, bottom))
PARTS = [
    ("panel_major.png", panel_major, (32, 32, 32, 32)),
    ("panel_inset.png", panel_inset, (16, 16, 16, 16)),
    ("button_normal.png", lambda: button("normal"), (16, 16, 16, 16)),
    ("button_hover.png", lambda: button("hover"), (16, 16, 16, 16)),
    ("button_pressed.png", lambda: button("pressed"), (16, 16, 16, 16)),
    ("button_disabled.png", lambda: button("disabled"), (16, 16, 16, 16)),
    ("plaque.png", plaque, (44, 10, 44, 10)),
    ("slot.png", slot, (12, 12, 12, 12)),
    ("well.png", well, (8, 8, 8, 8)),
    ("bar_track.png", lambda: bar("track"), (6, 6, 6, 6)),
    ("bar_fill.png", lambda: bar("fill"), (4, 4, 4, 4)),
    ("backdrop_tile.png", backdrop, (0, 0, 0, 0)),
]


def main():
    board_dir = Path(sys.argv[sys.argv.index("--board") + 1]) if "--board" in sys.argv else None
    OUT.mkdir(parents=True, exist_ok=True)
    images = []
    for name, fn, margins in PARTS:
        img = fn().image(2)
        img.save(OUT / name)
        images.append((name, img, margins))
    if board_dir:
        board_dir.mkdir(parents=True, exist_ok=True)
        from PIL import ImageDraw

        W = sum(i.width * 2 + 16 for _, i, _ in images)
        H = max(i.height for _, i, _ in images) * 2 + 40
        b = Image.new("RGBA", (W, H), (40, 38, 46, 255))
        x = 8
        dr = ImageDraw.Draw(b)
        for name, img, _ in images:
            dr.text((x, 4), name, fill=(230, 220, 200, 255))
            b.alpha_composite(img.resize((img.width * 2, img.height * 2), Image.NEAREST), (x, 20))
            x += img.width * 2 + 16
        b.save(board_dir / "parts.png")
        # 9-slice を伸ばした見本
        from PIL import Image as _I

        def nine(img, m, w, h):
            l, t, r, bt = m
            out = _I.new("RGBA", (w, h))
            sw, sh = img.width, img.height
            cw, ch = sw - l - r, sh - t - bt
            for (sx0, sy0, sx1, sy1, dx0, dy0) in [(0, 0, l, t, 0, 0), (sw - r, 0, sw, t, w - r, 0), (0, sh - bt, l, sh, 0, h - bt), (sw - r, sh - bt, sw, sh, w - r, h - bt)]:
                out.paste(img.crop((sx0, sy0, sx1, sy1)), (dx0, dy0))
            top, bottom = img.crop((l, 0, sw - r, t)), img.crop((l, sh - bt, sw - r, sh))
            left, right = img.crop((0, t, l, sh - bt)), img.crop((sw - r, t, sw, sh - bt))
            for xx in range(l, w - r, max(cw, 1)):
                out.paste(top, (xx, 0)); out.paste(bottom, (xx, h - bt))
            for yy in range(t, h - bt, max(ch, 1)):
                out.paste(left, (0, yy)); out.paste(right, (w - r, yy))
            centre = img.crop((l, t, sw - r, sh - bt))
            for yy in range(t, h - bt, max(ch, 1)):
                for xx in range(l, w - r, max(cw, 1)):
                    out.paste(centre, (xx, yy))
            return out.crop((0, 0, w, h))

        demo = _I.new("RGBA", (900, 420), (28, 26, 34, 255))
        demo.alpha_composite(nine(images[0][1], images[0][2], 520, 300), (16, 16))
        demo.alpha_composite(nine(images[1][1], images[1][2], 200, 120), (60, 70))
        demo.alpha_composite(nine(images[2][1], images[2][2], 160, 48), (300, 70))
        demo.alpha_composite(nine(images[3][1], images[3][2], 160, 48), (300, 130))
        demo.alpha_composite(nine(images[4][1], images[4][2], 160, 48), (300, 190))
        demo.alpha_composite(nine(images[6][1], images[6][2], 360, 36), (90, 240))
        demo.alpha_composite(nine(images[7][1], images[7][2], 48, 48), (560, 60))
        demo.alpha_composite(nine(images[8][1], images[8][2], 240, 16), (560, 130))
        demo.alpha_composite(nine(images[9][1], images[9][2], 150, 16), (560, 130))
        demo.alpha_composite(nine(images[10][1], (0, 0, 0, 0), 300, 80), (560, 180))
        demo.save(board_dir / "nine_slice_demo.png")
    print(f"wrote {len(images)} parts to {OUT}")


if __name__ == "__main__":
    main()
