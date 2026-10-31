"""VSGAME 統一VFXスタイルの共通規則。

規則（全シート共通）
- 1コマは level(0..5) の整数マップで描き、level → 色ランプの5段で塗る。中間色・アンチエイリアスは使わない。
- 0=透明、1=ランプ最暗（縁取り）、2=暗、3=本体、4=明、5=芯（ほぼ白）。
- 明るい本体（level>=2）の外周へ 1px の最暗縁（level 1）を付け、暗い床でも輪郭が読めるようにする。
- 孤立した暗い1ドットは消す（市松ノイズ防止）。砕け片は 3px 以上の塊で描く。
- 6コマの時間配分：0 予兆 / 1 立ち上がり / 2 最大 / 3 持続・崩れ始め / 4 散る / 5 余韻。
  後半コマは level の上限（CAP）を下げ、色が暗いランプへ落ちることで消える。
- ドット密度：コマ寸法は「ゲーム内表示サイズの約1/2」（1ドット≒ワールド2px、キャラクターと同等）。
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw

FRAMES = 6
CAP = [5, 5, 5, 5, 4, 3]


def _hex(value: str) -> tuple[int, int, int, int]:
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), 255)


# 暗 → 明 の5段。ゲームコードで線を描く色（雷光連鎖 #ffdf64、残影 #90ddff など）は
# 対応するランプの4段目と一致させている。
RAMPS_HEX = {
    "steel": ["1b2a4a", "2f5d8a", "4f9ccc", "90ddff", "f4fdff"],
    "gold": ["4a2410", "9a5512", "e0a020", "ffd860", "fff8d8"],
    "fire": ["3a0c0c", "8c1c10", "e04a10", "ff9a2a", "fff0a0"],
    "ice": ["0e2048", "1d5aa8", "3fa6e8", "9ee8ff", "f0ffff"],
    "lightning": ["1c1a5c", "3f4fd0", "7fb0ff", "ffdf64", "fffbe8"],
    "void": ["1a0a2e", "4a1a7a", "8a3ad0", "c88aff", "f6e8ff"],
    "wind": ["0c2a24", "1a6a50", "3cb884", "8ff5c0", "effff6"],
    "poison": ["16220e", "2f5a14", "62a020", "a8e040", "eaffb0"],
    "arcane": ["241048", "4a2898", "7a5ae0", "b8a0ff", "f4eeff"],
    "danger": ["3a0808", "8a1410", "e83a22", "ff7a4a", "ffe0c8"],
    "spirit": ["0a2a2a", "145a54", "2aa890", "7af0d0", "e8fff8"],
    "time": ["1a1440", "3a2f8a", "5a7ad0", "a0e8f8", "f8ffff"],
    "shield": ["0a1850", "1a40b0", "3a7cff", "9ac8ff", "f0f8ff"],
    "forge": ["3a1408", "8a3a10", "e07a18", "ffc040", "fff4c0"],
    "stone": ["1c1e26", "3a3e4a", "6a7080", "a0a8b8", "e0e6f0"],
    "white": ["5a5a66", "9a9aa8", "c8c8d4", "e8e8f0", "ffffff"],
}
RAMPS = {k: [_hex(c) for c in v] for k, v in RAMPS_HEX.items()}


class Frame:
    def __init__(self, w: int, h: int | None = None):
        self.w = w
        self.h = h if h is not None else w
        self.L = np.zeros((self.h, self.w), np.int16)
        yy, xx = np.mgrid[0 : self.h, 0 : self.w]
        self.X = xx + 0.5
        self.Y = yy + 0.5
        self.cx = self.w / 2
        self.cy = self.h / 2

    # ---- 基本 ----
    def put(self, mask, lv: int):
        self.L = np.where(mask, np.maximum(self.L, lv), self.L)

    def cut(self, mask):
        self.L = np.where(mask, 0, self.L)

    def _pil(self, draw_fn) -> np.ndarray:
        im = Image.new("L", (self.w, self.h), 0)
        draw_fn(ImageDraw.Draw(im))
        return np.asarray(im) > 0

    def poly(self, pts, lv: int, over: bool = False):
        """over=True は下の明るさを上書きする（裂け目の暗い内側など）。"""
        pts = [(float(x), float(y)) for x, y in pts]
        if len(pts) >= 3:
            m = self._pil(lambda d: d.polygon(pts, fill=255))
            if over:
                self.L = np.where(m, lv, self.L)
            else:
                self.put(m, lv)

    def line(self, pts, lv: int, width: int = 1):
        pts = [(float(x), float(y)) for x, y in pts]
        if len(pts) >= 2:
            self.put(self._pil(lambda d: d.line(pts, fill=255, width=max(1, int(width)), joint="curve")), lv)

    def px(self, x, y, lv: int):
        x, y = int(math.floor(x)), int(math.floor(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.L[y, x] = max(self.L[y, x], lv)

    # ---- 形 ----
    def dist(self, cx, cy, sy: float = 1.0):
        return np.hypot(self.X - cx, (self.Y - cy) / sy)

    def angle(self, cx, cy, sy: float = 1.0):
        return np.arctan2((self.Y - cy) / sy, self.X - cx)

    def disc(self, cx, cy, r, lv, sy: float = 1.0):
        if r > 0:
            self.put(self.dist(cx, cy, sy) <= r, lv)

    def ring(self, cx, cy, r, th, lv, sy: float = 1.0, sectors: int = 0, keep: float = 1.0, rot: float = 0.0):
        d = self.dist(cx, cy, sy)
        m = (d <= r) & (d > r - th)
        if sectors:
            a = (self.angle(cx, cy, sy) + rot) / (2 * math.pi) * sectors
            m &= np.mod(a, 1.0) < keep
        self.put(m, lv)

    def glow_disc(self, cx, cy, r, top: int = 5, sy: float = 1.0):
        """中心ほど明るい円（段は同心円で、ぼかしは使わない）。"""
        for i, f in enumerate((1.0, 0.72, 0.45, 0.22)):
            lv = top - 3 + i
            if lv >= 1 and r * f >= 0.6:
                self.disc(cx, cy, r * f, lv, sy)

    def diamond(self, cx, cy, length, width, ang, lv):
        c, s = math.cos(ang), math.sin(ang)
        pts = [
            (cx + c * length, cy + s * length),
            (cx - s * width, cy + c * width),
            (cx - c * length, cy - s * length),
            (cx + s * width, cy - c * width),
        ]
        self.poly(pts, lv)

    def shard(self, cx, cy, length, width, ang, lv):
        """外向きの砕け片。尖端が明るく、尾が暗い。"""
        c, s = math.cos(ang), math.sin(ang)
        self.diamond(cx, cy, length, width, ang, max(lv - 2, 1))
        self.diamond(cx + c * length * 0.15, cy + s * length * 0.15, length * 0.8, max(width * 0.55, 0.5), ang, max(lv - 1, 1))
        self.line([(cx - c * length * 0.2, cy - s * length * 0.2), (cx + c * length * 0.85, cy + s * length * 0.85)], lv, 1)

    def spark(self, cx, cy, size: int, lv: int):
        """4方向の光点。size 1=十字5px、2以上=腕が伸びる。"""
        x, y = int(math.floor(cx)), int(math.floor(cy))
        self.px(x, y, lv)
        for k in range(1, size + 1):
            klv = lv if k == 1 else max(lv - k + 1, 2)
            for dx, dy in ((k, 0), (-k, 0), (0, k), (0, -k)):
                self.px(x + dx, y + dy, klv)

    def ray(self, cx, cy, ang, r0, r1, w0, lv, tones: int = 1):
        """中心から外へ細くなる光条。tones=3 で 暗い外側→明→芯 の3段。"""
        c, s = math.cos(ang), math.sin(ang)
        px_, py_ = -s, c
        for k in range(tones):
            w = w0 * (1.0, 0.55, 0.2)[k] if tones > 1 else w0
            rr = r1 * (1.0, 0.85, 0.65)[k] if tones > 1 else r1
            l = lv - (tones - 1) + k
            if w < 0.35 and k > 0:
                self.line([(cx + c * r0, cy + s * r0), (cx + c * rr, cy + s * rr)], l, 1)
                continue
            pts = [
                (cx + c * r0 + px_ * w, cy + s * r0 + py_ * w),
                (cx + c * rr, cy + s * rr),
                (cx + c * r0 - px_ * w, cy + s * r0 - py_ * w),
            ]
            self.poly(pts, max(l, 1))

    def star(self, cx, cy, n, r_long, r_short, w, top, rot=0.0, sy: float = 1.0):
        """n本の長短交互の光条（3段）。"""
        for i in range(n):
            a = rot + i * 2 * math.pi / n
            r = r_long if i % 2 == 0 else r_short
            self.ray(cx, cy, a, 0, r, w * 1.6, top, tones=3)

    def crescent(self, cx, cy, R, th, a0, a1, top=5, reveal=(0.0, 1.0), sy=1.0, chunks=0, chunk_keep=0.7, peak=0.6):
        """刃の軌跡。外縁が最も明るく、内側へ暗くなる。u=0→1 が振りの進行方向。"""
        d = self.dist(cx, cy, sy)
        a = self.angle(cx, cy, sy)
        u = (a - a0) / (a1 - a0)
        inside = (u >= reveal[0]) & (u <= reveal[1])
        uc = np.clip(u, 0, 1)
        # 進行方向寄りが最も太い
        k = math.log(0.5) / math.log(peak)
        taper = np.sin(np.pi * uc**k) ** 0.7
        thick = th * taper
        depth = R - d
        m = inside & (depth >= 0) & (depth <= thick) & (thick >= 0.6)
        if chunks:
            m &= np.mod(u * chunks, 1.0) < chunk_keep
        rel = depth / np.maximum(thick, 1e-3)
        lv = np.where(rel < 0.3, top, np.where(rel < 0.62, top - 1, np.where(rel < 0.88, top - 2, top - 3)))
        lv = np.maximum(lv, 2)
        self.L = np.where(m, np.maximum(self.L, lv), self.L)

    def bolt(self, pts, top=5, width=3, aura=0):
        """稲妻。太い本体の中へ1px の芯。aura>0 で外側に暗い放電の帯。"""
        if aura:
            self.line(pts, max(top - 3, 1), width + aura)
        self.line(pts, top - 2, width)
        if width >= 3:
            self.line(pts, top - 1, max(width - 2, 1))
        self.line(pts, top, 1)

    def flame(self, cx, cy, ang, length, width, top, bend: float = 0.0):
        """外向きの炎の舌。bend で先端が渦を巻くように曲がる（ラジアン）。3段。"""
        def outline(scale_w, scale_l):
            steps = 12
            center = []
            for i in range(steps + 1):
                t = i / steps
                a = ang + bend * t * t
                r = length * scale_l * t
                center.append((cx + math.cos(ang) * r * (1 - t) + math.cos(a) * r * t, cy + math.sin(ang) * r * (1 - t) + math.sin(a) * r * t, a, t))
            left, right = [], []
            for x, y, a, t in center:
                w = width * scale_w * math.sin(math.pi * (0.2 + 0.8 * t))
                w = max(w, 0.0)
                nx, ny = -math.sin(a), math.cos(a)
                left.append((x + nx * w, y + ny * w))
                right.append((x - nx * w, y - ny * w))
            return left + right[::-1]
        self.poly(outline(1.0, 1.0), max(top - 2, 1))
        self.poly(outline(0.55, 0.78), max(top - 1, 1))
        self.poly(outline(0.22, 0.5), top)

    def blob(self, cx, cy, rx, ry, n, amp, lv, seed=0, rot=0.0, over=False, tilt=0.0):
        """ぎざぎざの塊（エネルギー・爆炎・煙）。tilt で楕円ごと回す。"""
        r = np.random.default_rng(seed)
        ct, st = math.cos(tilt), math.sin(tilt)
        pts = []
        for i in range(n * 2):
            a = rot + i * math.pi / n
            k = 1.0 if i % 2 == 0 else 1.0 - amp * r.uniform(0.5, 1.0)
            k *= r.uniform(0.9, 1.05)
            x, y = math.cos(a) * rx * k, math.sin(a) * ry * k
            pts.append((cx + x * ct - y * st, cy + x * st + y * ct))
        self.poly(pts, lv, over)

    def mass(self, cx, cy, rx, ry, top, n=9, amp=0.35, seed=0, rot=0.0, depth=4, tilt=0.0):
        """入れ子の塊。外ほど暗い（top-3 → top）。"""
        for k, sc in enumerate((1.0, 0.74, 0.5, 0.27)[:depth]):
            lv = top - (depth - 1) + k
            if lv >= 1:
                self.blob(cx, cy, rx * sc, ry * sc, n, amp, lv, seed + k, rot + k * 0.3, tilt=tilt)

    # ---- 仕上げ ----
    def finish(self, cap: int = 5, rim: bool = True, despeckle: bool = True):
        L = np.minimum(self.L, cap)
        L = np.where(self.L > 0, np.maximum(L, 1), 0)
        if despeckle:
            lit = L > 0
            n = np.zeros_like(L)
            n[1:, :] += lit[:-1, :]
            n[:-1, :] += lit[1:, :]
            n[:, 1:] += lit[:, :-1]
            n[:, :-1] += lit[:, 1:]
            L = np.where(lit & (n == 0) & (L < 4), 0, L)
        if rim:
            body = L >= 2
            near = np.zeros_like(body)
            near[1:, :] |= body[:-1, :]
            near[:-1, :] |= body[1:, :]
            near[:, 1:] |= body[:, :-1]
            near[:, :-1] |= body[:, 1:]
            L = np.where((L == 0) & near, 1, L)
        self.L = L
        return self

    def render(self, ramp: str) -> Image.Image:
        pal = np.array([(0, 0, 0, 0)] + RAMPS[ramp], np.uint8)
        return Image.fromarray(pal[np.clip(self.L, 0, 5)], "RGBA")


def sheet(frames: list[Image.Image]) -> Image.Image:
    w, h = frames[0].size
    out = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        out.alpha_composite(f, (i * w, 0))
    return out


def jag(p0, p1, n, amp, rng, lock_end=True):
    """p0→p1 を n 区間の稲妻線に。"""
    (x0, y0), (x1, y1) = p0, p1
    dx, dy = x1 - x0, y1 - y0
    length = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / length, dx / length
    pts = [(x0, y0)]
    for i in range(1, n):
        t = i / n
        o = rng.uniform(-amp, amp) * (1 if i % 2 else -1) * 0.5 + rng.uniform(-amp, amp) * 0.5
        pts.append((x0 + dx * t + nx * o, y0 + dy * t + ny * o))
    pts.append((x1, y1) if lock_end else (x1 + nx * rng.uniform(-amp, amp), y1 + ny * rng.uniform(-amp, amp)))
    return pts
