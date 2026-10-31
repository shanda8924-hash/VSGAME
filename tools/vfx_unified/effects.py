"""VSGAME 全VFXシートの定義（統一スタイル）。

各エフェクトは draw(f, t, rng) で1コマを描く。f は style.Frame、t は 0..5。
出力パスは res:// からの相対で、旧シートと同じファイル名へ上書きする。
コマ寸法は「表示サイズの約1/2」。読み込み側はコマ寸法＝シート高さ、コマ幅＝シート幅/6 として扱う。
"""
from __future__ import annotations

import math
import zlib

import numpy as np

from style import CAP, FRAMES, Frame, jag, sheet

TAU = math.tau
GROW = [0.35, 0.7, 1.0, 1.08, 1.14, 1.18]


# ------------------------------------------------------------------ 命中（放射）
def hit_steel(f, t, rng, crit=False):
    c, R = f.cx, f.w * 0.46
    n = 8 if crit else 4
    if t == 0:
        f.glow_disc(c, c, R * 0.18, 5)
        f.spark(c, c, 2, 5)
    elif t == 1:
        f.star(c, c, 8 if crit else 4, R * 0.7, R * 0.45, 1.4, 5, rot=math.pi / 4 if not crit else 0)
        f.glow_disc(c, c, R * 0.24, 5)
    elif t == 2:
        f.star(c, c, 8, R * 0.98, R * 0.62, 1.8 if crit else 1.5, 5)
        f.glow_disc(c, c, R * 0.32, 5)
        if crit:
            f.ring(c, c, R * 0.98, 1.2, 4, sectors=8, keep=0.55, rot=0.2)
    elif t == 3:
        f.ring(c, c, R * 0.88, 2.0 if crit else 1.6, 4, sectors=n, keep=0.5, rot=TAU / (n * 4))
        for i in range(n):
            a = i * TAU / n
            f.shard(c + math.cos(a) * R * 0.62, c + math.sin(a) * R * 0.62, R * 0.2, R * 0.09 + 0.6, a, 5)
        f.disc(c, c, R * 0.14, 3)
    elif t == 4:
        for i in range(n):
            a = i * TAU / n + 0.2
            f.shard(c + math.cos(a) * R * 0.82, c + math.sin(a) * R * 0.82, R * 0.16, R * 0.08 + 0.6, a, 4)
    else:
        for i in range(n // 2 + 1):
            a = i * TAU / (n // 2 + 1) + 0.6
            f.spark(c + math.cos(a) * R * 0.92, c + math.sin(a) * R * 0.92, 1, 4)


def hit_fire(f, t, rng):
    c, R = f.cx, f.w * 0.46
    if t == 0:
        f.mass(c, c, R * 0.3, R * 0.3, 5, n=6, seed=1)
    elif t == 1:
        for i in range(5):
            f.flame(c, c, i * TAU / 5 - math.pi / 2, R * 0.7, R * 0.22, 5, bend=0.4)
        f.mass(c, c, R * 0.34, R * 0.34, 5, n=6, seed=2)
    elif t == 2:
        for i in range(6):
            f.flame(c, c, i * TAU / 6 - math.pi / 2, R * (1.0 if i % 2 == 0 else 0.78), R * 0.24, 5, bend=0.45)
        f.mass(c, c, R * 0.4, R * 0.4, 5, n=7, seed=3)
    elif t == 3:
        for i in range(6):
            a = i * TAU / 6 - math.pi / 2 + 0.35
            f.flame(c + math.cos(a) * R * 0.22, c + math.sin(a) * R * 0.22, a, R * 0.78, R * 0.18, 5, bend=0.6)
        f.cut(f.dist(c, c) < R * 0.18)
    elif t == 4:
        for i in range(4):
            a = i * TAU / 4 - math.pi / 2 + 0.7
            x, y = c + math.cos(a) * R * 0.62, c + math.sin(a) * R * 0.62 - R * 0.1
            f.flame(x, y, -math.pi / 2 + 0.4 * math.cos(a), R * 0.4, R * 0.17, 4, bend=0.6)
    else:
        for i in range(3):
            a = i * TAU / 3 - math.pi / 2 + 0.9
            f.diamond(c + math.cos(a) * R * 0.75, c + math.sin(a) * R * 0.75 - R * 0.2, 1.8, 1.1, -math.pi / 2, 4)


def hit_ice(f, t, rng):
    c, R = f.cx, f.w * 0.46
    if t == 0:
        f.diamond(c, c, R * 0.3, R * 0.18, -math.pi / 2, 5)
    elif t == 1:
        for i in range(6):
            a = i * TAU / 6 - math.pi / 2
            f.shard(c + math.cos(a) * R * 0.3, c + math.sin(a) * R * 0.3, R * 0.32, R * 0.12 + 0.5, a, 5)
        f.diamond(c, c, R * 0.24, R * 0.24, 0, 5)
    elif t == 2:
        for i in range(6):
            a = i * TAU / 6 - math.pi / 2
            L = R * (0.5 if i % 2 == 0 else 0.36)
            f.shard(c + math.cos(a) * L, c + math.sin(a) * L, L, R * 0.15 + 0.5, a, 5)
        f.diamond(c, c, R * 0.3, R * 0.3, math.pi / 4, 5)
        f.disc(c, c, R * 0.12, 5)
    elif t == 3:
        for i in range(6):
            a = i * TAU / 6 - math.pi / 2 + 0.12
            f.shard(c + math.cos(a) * R * 0.66, c + math.sin(a) * R * 0.66, R * 0.26, R * 0.12 + 0.5, a, 5)
        f.diamond(c, c, R * 0.16, R * 0.16, math.pi / 4, 3)
    elif t == 4:
        for i in range(5):
            a = i * TAU / 5 - math.pi / 2 + 0.4
            f.shard(c + math.cos(a) * R * 0.84, c + math.sin(a) * R * 0.84, R * 0.17, R * 0.1 + 0.5, a, 4)
    else:
        for i in range(3):
            a = i * TAU / 3 + 0.3
            f.spark(c + math.cos(a) * R * 0.92, c + math.sin(a) * R * 0.92, 1, 4)


def hit_light(f, t, rng):
    c, R = f.cx, f.w * 0.46
    if t == 0:
        f.spark(c, c, 3, 5)
        f.disc(c, c, R * 0.12, 5)
    elif t == 1:
        f.star(c, c, 4, R * 0.85, R * 0.85, 1.3, 5, rot=-math.pi / 2)
        f.glow_disc(c, c, R * 0.24, 5)
    elif t == 2:
        f.star(c, c, 4, R * 1.0, R * 1.0, 1.7, 5, rot=-math.pi / 2)
        f.star(c, c, 4, R * 0.5, R * 0.5, 1.2, 5, rot=math.pi / 4)
        f.glow_disc(c, c, R * 0.3, 5)
    elif t == 3:
        f.star(c, c, 4, R * 0.7, R * 0.7, 1.1, 5, rot=-math.pi / 2)
        for i in range(4):
            a = i * TAU / 4 + math.pi / 4
            f.spark(c + math.cos(a) * R * 0.6, c + math.sin(a) * R * 0.6, 1, 5)
    elif t == 4:
        for i in range(4):
            a = i * TAU / 4 + math.pi / 4 + 0.2
            f.spark(c + math.cos(a) * R * 0.8, c + math.sin(a) * R * 0.8, 1, 4)
        f.spark(c, c, 1, 3)
    else:
        for i in range(2):
            a = i * math.pi + 1.0
            f.spark(c + math.cos(a) * R * 0.9, c + math.sin(a) * R * 0.9, 1, 4)


def hit_lightning(f, t, rng):
    c, R = f.cx, f.w * 0.46
    r = np.random.default_rng(7)
    angles = [i * TAU / 5 + 0.3 for i in range(5)]
    paths = [jag((c, c), (c + math.cos(a) * R, c + math.sin(a) * R), 4, R * 0.25, r) for a in angles]
    if t == 0:
        f.glow_disc(c, c, R * 0.2, 5)
        f.spark(c, c, 2, 5)
    elif t == 1:
        for p in paths[::2]:
            f.bolt(p[:3], 5, 2)
        f.glow_disc(c, c, R * 0.24, 5)
    elif t == 2:
        for p in paths:
            f.bolt(p, 5, 2)
        f.glow_disc(c, c, R * 0.3, 5)
    elif t == 3:
        for p in paths:
            f.bolt(p[2:], 5, 2)
        f.disc(c, c, R * 0.12, 4)
    elif t == 4:
        for p in paths[1::2]:
            f.bolt(p[3:], 4, 1)
        for p in paths[::2]:
            f.spark(*p[-1], 1, 4)
    else:
        f.spark(*paths[1][-1], 1, 4)
        f.spark(*paths[3][-1], 1, 4)


def _spiral(cx, cy, a0, r0, r1, turn, n=8):
    return [(cx + math.cos(a0 + turn * i / n) * (r0 + (r1 - r0) * i / n), cy + math.sin(a0 + turn * i / n) * (r0 + (r1 - r0) * i / n)) for i in range(n + 1)]


def hit_dark(f, t, rng):
    c, R = f.cx, f.w * 0.46
    if t == 0:
        f.disc(c, c, R * 0.24, 4)
        f.disc(c, c, R * 0.12, 2)
    elif t in (1, 2):
        k = 0.7 if t == 1 else 1.0
        for i in range(4):
            sp = _spiral(c, c, i * TAU / 4, R * 0.2, R * 0.95 * k, 1.6)
            f.line(sp, 3, 2)
            f.line(sp[: len(sp) // 2 + 1], 4, 1)
        f.ring(c, c, R * 0.36 * k + 1, 1.5, 5)
        f.disc(c, c, R * 0.36 * k - 0.4, 2)
        f.disc(c, c, R * 0.2 * k, 1)
    elif t == 3:
        for i in range(4):
            sp = _spiral(c, c, i * TAU / 4 + 0.5, R * 0.45, R * 1.0, 1.0)
            f.line(sp, 3, 2)
            f.line(sp[-3:], 4, 1)
        f.ring(c, c, R * 0.3, 1.5, 4, sectors=3, keep=0.6)
    elif t == 4:
        for i in range(4):
            a = i * TAU / 4 + 1.4
            f.shard(c + math.cos(a) * R * 0.8, c + math.sin(a) * R * 0.8, R * 0.16, R * 0.1 + 0.5, a + 1.2, 4)
    else:
        f.spark(c + R * 0.6, c - R * 0.5, 1, 4)
        f.spark(c - R * 0.7, c + R * 0.4, 1, 4)


# ------------------------------------------------------------------ 斬撃・突き（+x が前方）
SWING_REVEAL = [(0.0, 0.35), (0.0, 0.75), (0.0, 1.0), (0.2, 1.0), (0.5, 1.0), (0.78, 1.0)]


def swing(f, t, R, th, span, chunks_late=3, top=5, sy=1.0, twin=False, peak=0.62):
    c = f.cx
    a0, a1 = -span, span
    rev = SWING_REVEAL[t]
    thick = th * (1.0 if t <= 2 else 0.8 if t == 3 else 0.6 if t == 4 else 0.45)
    chunks = 0 if t <= 3 else chunks_late
    f.crescent(c, c, R, thick, a0, a1, top, rev, sy, chunks=chunks, chunk_keep=0.62, peak=peak)
    if twin and t in (1, 2, 3):
        f.crescent(c, c, R * 0.72, thick * 0.5, a0 + 0.25, a1 - 0.1, top - 1, rev, sy, peak=peak)
    if t in (2, 3):
        # 振り終わり側の小さな光点
        a = a1 * 0.92
        f.spark(c + math.cos(a) * (R - 1) , c + math.sin(a) * (R - 1) * sy, 1, 5)


def thrust(f, t, rng, length=0.92, width=0.11):
    s = f.w
    c = f.cx
    half = s * length / 2
    W = s * width
    reach = [0.35, 0.75, 1.0, 1.0, 1.0, 1.0][t]
    x0, x1 = c - half, c - half + 2 * half * reach
    if t <= 3:
        wk = W * (1.0 if t < 3 else 0.7)
        f.poly([(x0, c - wk * 0.5), (x1 - wk * 1.6, c - wk), (x1, c), (x1 - wk * 1.6, c + wk), (x0, c + wk * 0.5)], 3)
        f.poly([(x0 + 2, c - wk * 0.2), (x1 - wk * 1.6, c - wk * 0.45), (x1 - 1, c), (x1 - wk * 1.6, c + wk * 0.45), (x0 + 2, c + wk * 0.2)], 4)
        f.line([(x0 + half * 0.4, c), (x1 - 1, c)], 5, 1)
        for k, oy in enumerate((-2.6, 2.6)):
            y = c + oy * W
            f.line([(x0 + half * (0.2 + 0.3 * k), y), (x0 + half * (0.9 + 0.3 * k) * reach, y)], 3, 1)
    else:
        for k in range(3 if t == 4 else 2):
            x = c + half * (0.2 + 0.35 * k) + (t - 4) * 3
            f.line([(x, c), (x + s * 0.12, c)], 4 if t == 4 else 3, 2)


def projectile(f, t, rng):
    s = f.w
    c = f.cx
    if t == 0:
        f.glow_disc(c - s * 0.25, c, s * 0.1, 5)
    elif t == 1:
        f.poly([(c - s * 0.35, c - 1.5), (c + s * 0.05, c - 2.5), (c + s * 0.15, c), (c + s * 0.05, c + 2.5), (c - s * 0.35, c + 1.5)], 3)
        f.line([(c - s * 0.25, c), (c + s * 0.12, c)], 5, 1)
    elif t in (2, 3):
        tip = c + s * (0.32 if t == 2 else 0.4)
        f.poly([(c - s * 0.45, c - 1.2), (tip - s * 0.16, c - 3.5), (tip, c), (tip - s * 0.16, c + 3.5), (c - s * 0.45, c + 1.2)], 3)
        f.poly([(c - s * 0.3, c - 0.8), (tip - s * 0.14, c - 2), (tip - 1, c), (tip - s * 0.14, c + 2), (c - s * 0.3, c + 0.8)], 4)
        f.line([(c - s * 0.1, c), (tip - 2, c)], 5, 1)
    elif t == 4:
        for k in range(3):
            x = c + s * (0.0 + 0.16 * k)
            f.line([(x, c + (k - 1) * 3), (x + s * 0.1, c + (k - 1) * 3)], 4, 2)
    else:
        f.spark(c + s * 0.3, c - 3, 1, 4)
        f.spark(c + s * 0.12, c + 3, 1, 3)


def pulse(f, t, rng):
    c, R = f.cx, f.w * 0.46
    if t == 0:
        f.glow_disc(c, c, R * 0.18, 5)
    elif t == 1:
        f.ring(c, c, R * 0.4, 1.6, 4)
        f.spark(c, c, 2, 5)
    elif t == 2:
        f.ring(c, c, R * 0.72, 2.2, 5)
        f.ring(c, c, R * 0.72 - 2.2, 1.0, 3)
        for i in range(4):
            a = i * TAU / 4
            f.ray(c + math.cos(a) * R * 0.72, c + math.sin(a) * R * 0.72, a, 0, R * 0.26, 1.2, 4)
    elif t == 3:
        f.ring(c, c, R * 0.92, 2.6, 5)
        f.ring(c, c, R * 0.92 - 2.6, 1.0, 3)
    elif t == 4:
        f.ring(c, c, R * 0.98, 2.0, 4, sectors=8, keep=0.6, rot=0.2)
    else:
        f.ring(c, c, R * 1.0, 1.5, 3, sectors=4, keep=0.35, rot=0.5)


def hammer(f, t, rng):
    c, R = f.cx, f.w * 0.46
    r = np.random.default_rng(11)
    cracks = [jag((c, c), (c + math.cos(a) * R * 0.95, c + math.sin(a) * R * 0.95), 3, R * 0.12, r) for a in [i * TAU / 6 + 0.2 for i in range(6)]]
    if t == 0:
        f.glow_disc(c, c, R * 0.16, 4)
    elif t == 1:
        f.glow_disc(c, c, R * 0.34, 5)
        for p in cracks:
            f.line(p[:2], 4, 2)
    elif t == 2:
        f.glow_disc(c, c, R * 0.42, 5)
        for p in cracks:
            f.line(p, 4, 2)
            f.line(p[:2], 5, 1)
        f.ring(c, c, R * 0.62, 1.6, 3)
    elif t == 3:
        for p in cracks:
            f.line(p[1:], 4, 2)
        f.ring(c, c, R * 0.86, 2.2, 4)
        f.disc(c, c, R * 0.2, 3)
    elif t == 4:
        f.ring(c, c, R * 0.98, 1.6, 3, sectors=6, keep=0.6)
        for i in range(4):
            a = i * TAU / 4 + 0.6
            f.diamond(c + math.cos(a) * R * 0.6, c + math.sin(a) * R * 0.6, 2.2, 1.6, a, 4)
    else:
        for i in range(3):
            a = i * TAU / 3 + 1.0
            f.diamond(c + math.cos(a) * R * 0.85, c + math.sin(a) * R * 0.85, 1.8, 1.2, a, 3)


def muzzle(f, t, rng):
    c, R = f.cx, f.w * 0.46
    size = [0.35, 0.8, 1.0, 0.75, 0.5, 0.3][t]
    f.star(c, c, 4, R * size, R * size * 0.7, 1.4, 5, rot=0)
    f.glow_disc(c, c, R * 0.3 * min(size + 0.3, 1.0), 5)
    if t >= 3:
        f.cut(f.dist(c, c) < R * 0.12 * (t - 2))
        for i in range(4):
            a = i * TAU / 4 + math.pi / 4
            f.spark(c + math.cos(a) * R * 0.7, c + math.sin(a) * R * 0.7, 1, 4)


def orb(f, t, rng, sparks=3):
    """ループする魔弾。全コマ同じ大きさで、周りの光点が回る。"""
    c, R = f.cx, f.w * 0.46
    pulse_r = R * (0.5 + 0.06 * math.sin(t / 6 * TAU))
    f.glow_disc(c, c, pulse_r, 5)
    f.ring(c, c, pulse_r + 1, 1, 2)
    for i in range(sparks):
        a = i * TAU / sparks + t / 6 * TAU
        f.spark(c + math.cos(a) * R * 0.82, c + math.sin(a) * R * 0.82, 1, 4 if i else 5)


def vortex(f, t, rng):
    """魔導士の追尾弾：回り続ける紫の渦（ループ）。"""
    c, R = f.cx, f.w * 0.46
    rot = t * TAU / 6 / 3
    f.disc(c, c, R * 0.82, 2)
    for i in range(3):
        sp = _spiral(c, c, i * TAU / 3 + rot, R * 0.15, R * 0.95, 2.0, n=10)
        f.line(sp, 4, 2)
        f.line(sp[:4], 5, 1)
    f.glow_disc(c, c, R * 0.3, 5)


# ------------------------------------------------------------------ 回避・宝箱
def holy_impact(f, t, rng):
    c, R = f.cx, f.w * 0.46
    if t == 0:
        f.diamond(c, c, R * 0.55, R * 0.55, 0, 5)
        f.diamond(c, c, R * 0.3, R * 0.3, 0, 5)
    elif t == 1:
        f.star(c, c, 4, R * 1.0, R * 1.0, 2.0, 5, rot=0)
        f.glow_disc(c, c, R * 0.3, 5)
    elif t == 2:
        f.star(c, c, 4, R * 0.9, R * 0.9, 1.4, 5, rot=0)
        f.ring(c, c, R * 0.6, 1.5, 4, sectors=4, keep=0.5, rot=TAU / 16)
    elif t == 3:
        for i in range(4):
            a = i * TAU / 4 + math.pi / 4
            f.diamond(c + math.cos(a) * R * 0.6, c + math.sin(a) * R * 0.6, 2.5, 1.6, a, 4)
        f.spark(c, c, 1, 4)
    elif t == 4:
        for i in range(4):
            a = i * TAU / 4 + math.pi / 4 + 0.2
            f.spark(c + math.cos(a) * R * 0.85, c + math.sin(a) * R * 0.85, 1, 4)
    else:
        f.spark(c + R * 0.8, c - R * 0.5, 1, 3)
        f.spark(c - R * 0.7, c + R * 0.6, 1, 3)


def holy_chest(f, t, rng):
    c = f.cx
    base = f.h * 0.82
    if t == 0:
        f.poly([(c - f.w * 0.42, base), (c, base - 2.5), (c + f.w * 0.42, base), (c, base + 2.5)], 4)
        f.line([(c - f.w * 0.3, base), (c + f.w * 0.3, base)], 5, 1)
    elif t in (1, 2, 3):
        top = base - f.h * [0, 0.45, 0.8, 0.8][t]
        w = f.w * [0, 0.2, 0.17, 0.11][t]
        f.poly([(c - w, base), (c - w * 0.8, top + w), (c, top), (c + w * 0.8, top + w), (c + w, base)], 3)
        f.poly([(c - w * 0.55, base), (c - w * 0.4, top + w), (c, top + 2), (c + w * 0.4, top + w), (c + w * 0.55, base)], 4)
        f.line([(c, base - 1), (c, top + 3)], 5, 1 if t == 3 else 2)
        f.ring(c, base, f.w * 0.32, 1.5, 4, sy=0.35)
        if t >= 2:
            for i in range(4):
                x = c + (-1) ** i * f.w * (0.22 + 0.06 * i)
                y = base - f.h * (0.25 + 0.12 * i + 0.1 * (t - 2))
                f.spark(x, y, 1, 5)
    elif t == 4:
        f.line([(c, base - 1), (c, base - f.h * 0.5)], 4, 1)
        for i in range(5):
            x = c + (i - 2) * f.w * 0.14
            y = base - f.h * (0.4 + 0.08 * (i % 3))
            f.spark(x, y, 1, 4)
    else:
        for i in range(3):
            x = c + (i - 1) * f.w * 0.2
            f.spark(x, base - f.h * (0.6 + 0.1 * (i % 2)), 1, 3)


# ------------------------------------------------------------------ 概念スキル（80px）
def concept_thunder(f, t, rng, ground=0.72):
    s, c = f.w, f.cx
    gy = f.h * ground
    r = np.random.default_rng(21)
    main = jag((c + s * 0.08, 0), (c, gy), 7, s * 0.07, r)
    branches = [jag(main[3], (main[3][0] - s * 0.22, main[3][1] + s * 0.16), 3, s * 0.04, r), jag(main[5], (main[5][0] + s * 0.2, main[5][1] + s * 0.1), 3, s * 0.04, r)]
    ground_bolts = [jag((c, gy), (c + math.cos(a) * s * 0.42, gy + math.sin(a) * s * 0.17), 4, s * 0.04, r) for a in [i * TAU / 7 + 0.2 for i in range(7)]]
    if t == 0:
        f.bolt(main[:4], 5, 3, aura=4)
    elif t == 1:
        f.bolt(main, 5, 5, aura=5)
        f.mass(c, gy, s * 0.12, s * 0.06, 5, n=8, seed=4)
    elif t == 2:
        f.mass(c, gy, s * 0.3, s * 0.15, 5, n=11, amp=0.45, seed=5)
        for b in ground_bolts:
            f.bolt(b, 5, 3, aura=2)
        f.bolt(main, 5, 6, aura=6)
        for b in branches:
            f.bolt(b, 5, 3, aura=2)
    elif t == 3:
        f.mass(c, gy, s * 0.2, s * 0.09, 4, n=9, seed=6)
        f.bolt(main[3:], 5, 3, aura=4)
        for b in ground_bolts:
            f.bolt(b[1:], 5, 2, aura=2)
        f.ring(c, gy, s * 0.34, 2, 3, sy=0.42)
    elif t == 4:
        for b in ground_bolts:
            f.bolt(b[2:], 4, 2)
        f.ring(c, gy, s * 0.44, 1.5, 3, sy=0.42, sectors=7, keep=0.5)
        f.spark(c, gy - 2, 1, 4)
    else:
        for b in ground_bolts[::2]:
            f.spark(*b[-1], 1, 4)


def concept_fire(f, t, rng):
    c, R = f.cx, f.w * 0.46
    if t == 0:
        f.mass(c, c, R * 0.28, R * 0.28, 5, n=7, seed=1)
        for i in range(4):
            f.flame(c, c, i * TAU / 4 - math.pi / 2, R * 0.42, R * 0.14, 5, bend=0.8)
        return
    if t <= 3:
        n = 8 if t >= 2 else 6
        for i in range(n):
            a = i * TAU / n - math.pi / 2 + t * 0.2
            ln = R * (1.0 if i % 2 == 0 else 0.76) * [0, 0.65, 1.0, 0.95][t]
            start = R * (0.06 if t < 3 else 0.28)
            f.flame(c + math.cos(a) * start, c + math.sin(a) * start, a, ln, R * 0.19, 5, bend=0.45 + 0.12 * t)
        if t < 3:
            f.mass(c, c, R * (0.28 if t == 1 else 0.34), R * (0.28 if t == 1 else 0.34), 5, n=9, seed=t)
        else:
            f.mass(c, c, R * 0.3, R * 0.3, 4, n=9, seed=7)
            f.cut(f.dist(c, c) < R * 0.13)
        if t >= 2:
            for i in range(5):
                a = i * TAU / 5 + 0.3
                f.diamond(c + math.cos(a) * R * 0.95, c + math.sin(a) * R * 0.95, 2.4, 1.5, a, 5)
    elif t == 4:
        for i in range(6):
            a = i * TAU / 6 - math.pi / 2 + 0.6
            x, y = c + math.cos(a) * R * 0.62, c + math.sin(a) * R * 0.62
            f.flame(x, y, -math.pi / 2 + 0.4 * math.cos(a), R * 0.36, R * 0.14, 4, bend=0.7)
    else:
        for i in range(5):
            a = i * TAU / 5 + 0.2
            f.diamond(c + math.cos(a) * R * 0.8, c + math.sin(a) * R * 0.8 - R * 0.1, 2.5, 1.5, -math.pi / 2, 4)


def concept_ice(f, t, rng):
    c, R = f.cx, f.w * 0.46
    k = min(GROW[t], 1.0)
    if t <= 2:
        for i in range(6):
            a = i * TAU / 6 - math.pi / 2
            L = R * 0.5 * k
            f.shard(c + math.cos(a) * L, c + math.sin(a) * L, L, R * 0.11 + 0.8, a, 5)
            if t >= 1:
                # 枝
                for side in (-1, 1):
                    bx, by = c + math.cos(a) * R * 0.55 * k, c + math.sin(a) * R * 0.55 * k
                    b = a + side * 0.9
                    f.shard(bx + math.cos(b) * R * 0.12 * k, by + math.sin(b) * R * 0.12 * k, R * 0.14 * k, R * 0.05 + 0.6, b, 4)
        f.glow_disc(c, c, R * 0.2 * k + 1, 5)
        f.spark(c, c, 2, 5)
    elif t == 3:
        for i in range(6):
            a = i * TAU / 6 - math.pi / 2 + 0.1
            f.shard(c + math.cos(a) * R * 0.6, c + math.sin(a) * R * 0.6, R * 0.32, R * 0.12 + 0.6, a, 5)
        f.glow_disc(c, c, R * 0.1, 4)
    elif t == 4:
        for i in range(6):
            a = i * TAU / 6 - math.pi / 2 + 0.35
            f.shard(c + math.cos(a) * R * 0.82, c + math.sin(a) * R * 0.82, R * 0.18, R * 0.09 + 0.6, a, 4)
    else:
        for i in range(4):
            a = i * TAU / 4 + 0.6
            f.spark(c + math.cos(a) * R * 0.92, c + math.sin(a) * R * 0.92, 1, 4)


def concept_light(f, t, rng):
    c, R = f.cx, f.w * 0.46
    if t == 0:
        f.star(c, c, 4, R * 0.45, R * 0.45, 1.5, 5, rot=-math.pi / 2)
        f.glow_disc(c, c, R * 0.14, 5)
    elif t in (1, 2):
        k = 0.75 if t == 1 else 1.0
        f.mass(c, c, R * 0.4 * k, R * 0.4 * k, 4, n=8, amp=0.5, seed=t)
        f.star(c, c, 4, R * k, R * k, 2.4, 5, rot=-math.pi / 2)
        f.star(c, c, 4, R * 0.62 * k, R * 0.62 * k, 1.8, 5, rot=math.pi / 4)
        f.star(c, c, 8, R * 0.42 * k, R * 0.42 * k, 1.2, 5, rot=math.pi / 8)
        f.glow_disc(c, c, R * 0.22 * k, 5)
        if t == 2:
            for i in range(8):
                a = i * TAU / 8 + math.pi / 8
                f.spark(c + math.cos(a) * R * 0.78, c + math.sin(a) * R * 0.78, 2 if i % 2 else 1, 5)
    elif t == 3:
        f.star(c, c, 4, R * 0.78, R * 0.78, 1.6, 5, rot=-math.pi / 2)
        f.glow_disc(c, c, R * 0.16, 5)
        for i in range(8):
            a = i * TAU / 8 + math.pi / 8
            f.shard(c + math.cos(a) * R * 0.66, c + math.sin(a) * R * 0.66, R * 0.12, R * 0.05 + 0.6, a, 5)
    elif t == 4:
        for i in range(6):
            a = i * TAU / 6 + 0.4
            f.spark(c + math.cos(a) * R * 0.84, c + math.sin(a) * R * 0.84, 2 if i % 2 else 1, 4)
        f.spark(c, c, 1, 4)
    else:
        for i in range(3):
            a = i * TAU / 3 + 1.0
            f.spark(c + math.cos(a) * R * 0.95, c + math.sin(a) * R * 0.95, 1, 4)


def concept_wind(f, t, rng):
    """前方（+x）へ飛ぶ風の三日月を重ね、渦と速度線を添える。"""
    c, R = f.cx, f.w * 0.46
    shift = [-0.35, -0.15, 0.0, 0.12, 0.24, 0.34][t] * R
    blades = ((0.66, 0.3, 0.0, 5), (0.5, 0.22, -0.26, 4), (0.82, 0.16, -0.14, 4))
    for k, (rr, th, off, top) in enumerate(blades):
        if t == 0 and k > 0:
            continue
        cc = c + shift + off * R - R * 0.25
        rev = SWING_REVEAL[min(t + 1, 5)] if t <= 1 else (0.0, 1.0) if t <= 3 else SWING_REVEAL[t]
        thick = th * R * (1.0 if t <= 2 else 0.75 if t == 3 else 0.55)
        f.crescent(cc, c, R * rr, thick, -1.2, 1.2, top, rev, chunks=0 if t < 4 else 3, chunk_keep=0.65, peak=0.5)
    if 1 <= t <= 4:
        for i, y in enumerate((-0.5, -0.26, 0.26, 0.5)):
            x0 = c - R * 0.98 + shift * 0.5 + i * 2
            f.line([(x0, c + y * R), (x0 + R * (0.5 - 0.08 * i), c + y * R)], 3 if t < 4 else 2, 2 if i in (1, 2) else 1)
        for i in range(3):
            a = 0.8 + i * 1.9
            f.diamond(c + shift + math.cos(a) * R * 0.75, c + math.sin(a) * R * 0.7, 2.5, 1.2, a, 4)


def _rift(f, cx, cy, half, open_, ang, seed, s, depth_lv=1):
    """斜めの裂け目。縁は明るく、中は虚無（上書き）。"""
    r = np.random.default_rng(seed)
    ux, uy = math.cos(ang), math.sin(ang)
    nx, ny = -uy, ux
    n = 11
    jt = [r.uniform(0.55, 1.0) for _ in range(n)]
    jb = [r.uniform(0.55, 1.0) for _ in range(n)]
    top, bot, mid = [], [], []
    for i in range(n):
        u = -1 + 2 * i / (n - 1)
        env = (1 - abs(u)) ** 0.8
        h1 = s * 0.12 * open_ * env * jt[i]
        h2 = s * 0.12 * open_ * env * jb[i]
        x, y = cx + ux * half * u, cy + uy * half * u
        mid.append((x, y))
        top.append((x + nx * h1, y + ny * h1))
        bot.append((x - nx * h2, y - ny * h2))
    f.poly([(x + nx * 3, y + ny * 3) for x, y in top] + [(x - nx * 3, y - ny * 3) for x, y in bot[::-1]], 3)
    f.poly([(x + nx * 1.5, y + ny * 1.5) for x, y in top] + [(x - nx * 1.5, y - ny * 1.5) for x, y in bot[::-1]], 5)
    f.poly(top + bot[::-1], 2, over=True)
    inner_t = [(m[0] + (p[0] - m[0]) * 0.55, m[1] + (p[1] - m[1]) * 0.55) for m, p in zip(mid, top)]
    inner_b = [(m[0] + (p[0] - m[0]) * 0.55, m[1] + (p[1] - m[1]) * 0.55) for m, p in zip(mid, bot)]
    f.poly(inner_t + inner_b[::-1], depth_lv, over=True)
    return ux, uy, nx, ny


def concept_dark(f, t, rng, wide=1.0):
    """横に開く裂け目。中が暗く、縁が明るい。"""
    c, R = f.cx, f.w * 0.46
    s = f.w
    open_ = [0.15, 0.5, 0.85, 0.6, 0.3, 0.0][t]
    length = R * [0.55, 0.85, 1.0, 1.0, 0.8, 0.5][t] * wide
    if t in (1, 2, 3):
        f.blob(c, c, length * 0.9, R * 0.3 * open_ + 2, 10, 0.5, 2, seed=t)
        for i in range(4):
            sp = _spiral(c, c, i * TAU / 4 + t * 0.4, R * 0.25, R * 0.7, 1.4, n=8)
            f.line(sp, 3, 2)
    if open_ > 0:
        f.line([(c - length * 1.25, c), (c + length * 1.25, c)], 4, 1)
        _rift(f, c, c, length, open_, 0.0, 31, s * 1.9)
    else:
        f.line([(c - length, c), (c + length, c)], 3, 1)
    if t >= 2:
        for i in range(6):
            a = i * TAU / 6 + 0.5
            d = R * (0.5 + 0.14 * (t - 2))
            f.shard(c + math.cos(a) * d * 1.2, c + math.sin(a) * d * 0.85, R * 0.14, R * 0.07 + 0.6, a, 5 if t < 4 else 4)


# ------------------------------------------------------------------ 秘技（96px、着地点は高さ0.72）
GROUND = 0.72


def sig_thunderlord(f, t, rng):
    """雷の大剣が落ち、着地で地を這う雷が放射する。"""
    s, c = f.w, f.cx
    gy = f.h * GROUND
    r = np.random.default_rng(41)
    blade_len = s * 0.5
    tip_y = [gy - s * 0.34, gy - s * 0.04, gy + 2, gy + 2, gy + 2, gy + 2][t]

    def sword(tip, w, aura=True, bolts=6):
        hilt_y = tip - blade_len
        mid = tip - blade_len * 0.5
        if aura:
            f.blob(c, mid, w * 3.6, blade_len * 0.64, 10, 0.5, 2, seed=t + 3)
            f.blob(c, mid, w * 2.2, blade_len * 0.56, 9, 0.4, 3, seed=t + 9)
        f.poly([(c, tip), (c - w, tip - w * 2.4), (c - w, hilt_y), (c + w, hilt_y), (c + w, tip - w * 2.4)], 3)
        f.poly([(c, tip - 2), (c - w * 0.5, tip - w * 2.4), (c - w * 0.5, hilt_y + 1), (c + w * 0.5, hilt_y + 1), (c + w * 0.5, tip - w * 2.4)], 4)
        f.line([(c, tip - 3), (c, hilt_y + 1)], 5, 1)
        f.poly([(c - w * 3.4, hilt_y - 1.5), (c + w * 3.4, hilt_y - 1.5), (c + w * 2.4, hilt_y + 2.5), (c - w * 2.4, hilt_y + 2.5)], 4)
        f.line([(c - w * 3, hilt_y), (c + w * 3, hilt_y)], 5, 1)
        f.line([(c, hilt_y - 1), (c, hilt_y - s * 0.12)], 3, 3)
        f.disc(c, hilt_y - s * 0.13, 2.4, 5)
        for k in range(bolts):
            y = hilt_y + blade_len * (0.1 + 0.8 * k / max(bolts - 1, 1))
            side = -1 if k % 2 else 1
            p = jag((c + side * w, y), (c + side * (w + s * (0.1 + 0.04 * (k % 3))), y + s * 0.05), 3, s * 0.025, r)
            f.bolt(p, 5, 1)

    if t == 0:
        f.bolt(jag((c, 0), (c, tip_y - blade_len - s * 0.12), 4, s * 0.03, r), 5, 2, aura=3)
        sword(tip_y, s * 0.045, bolts=4)
    elif t == 1:
        f.bolt(jag((c - 2, 0), (c, tip_y - blade_len - s * 0.12), 4, s * 0.04, r), 5, 3, aura=4)
        f.mass(c, gy, s * 0.14, s * 0.06, 5, n=8, seed=4)
        sword(tip_y, s * 0.055)
    elif t == 2:
        f.mass(c, gy, s * 0.42, s * 0.19, 5, n=13, amp=0.5, seed=5)
        f.poly([(c - s * 0.07, 0), (c + s * 0.07, 0), (c + s * 0.1, gy), (c - s * 0.1, gy)], 2)
        for i in range(8):
            a = i * TAU / 8 + 0.2
            p = jag((c, gy), (c + math.cos(a) * s * 0.48, gy + math.sin(a) * s * 0.21), 5, s * 0.035, r)
            f.bolt(p, 5, 3 if i % 2 == 0 else 2, aura=2)
        f.bolt(jag((c, 0), (c, tip_y - blade_len - s * 0.12), 4, s * 0.05, r), 5, 4, aura=4)
        sword(tip_y, s * 0.06, bolts=8)
    elif t == 3:
        f.mass(c, gy, s * 0.3, s * 0.12, 4, n=11, amp=0.5, seed=8)
        for i in range(8):
            a = i * TAU / 8 + 0.35
            p = jag((c + math.cos(a) * s * 0.12, gy + math.sin(a) * s * 0.05), (c + math.cos(a) * s * 0.49, gy + math.sin(a) * s * 0.22), 4, s * 0.035, r)
            f.bolt(p, 5, 2, aura=2)
        f.ring(c, gy, s * 0.4, 2.5, 4, sy=0.44)
        sword(tip_y, s * 0.05, aura=True, bolts=4)
    elif t == 4:
        hilt_y = tip_y - blade_len
        f.poly([(c, tip_y), (c - 3, tip_y - 6), (c - 3, hilt_y), (c + 3, hilt_y), (c + 3, tip_y - 6)], 3)
        f.line([(c, tip_y - 2), (c, hilt_y)], 4, 1)
        for i in range(8):
            a = i * TAU / 8 + 0.5
            p = jag((c + math.cos(a) * s * 0.3, gy + math.sin(a) * s * 0.13), (c + math.cos(a) * s * 0.5, gy + math.sin(a) * s * 0.22), 2, s * 0.03, r)
            f.bolt(p, 4, 2)
        f.ring(c, gy, s * 0.47, 2, 3, sy=0.44, sectors=8, keep=0.5)
    else:
        f.line([(c, gy), (c, gy - blade_len * 0.6)], 3, 2)
        for i in range(6):
            a = i * TAU / 6 + 0.7
            f.spark(c + math.cos(a) * s * 0.44, gy + math.sin(a) * s * 0.19, 1, 4)


def sig_inferno(f, t, rng):
    """地面から天へ伸びる火柱。縁は炎の舌、芯は白熱、巻きつく火の帯。"""
    s, c = f.w, f.cx
    gy = f.h * GROUND + s * 0.06
    if t == 0:
        f.mass(c, gy, s * 0.2, s * 0.07, 5, n=9, seed=1)
        for i in range(5):
            a = -math.pi / 2 + (i - 2) * 0.5
            f.flame(c + (i - 2) * s * 0.06, gy, a, s * 0.16, s * 0.05, 5, bend=-0.4 * (i - 2))
        return
    height = s * [0, 0.48, 0.7, 0.72, 0.6, 0.3][t]
    width = s * [0, 0.13, 0.16, 0.14, 0.1, 0.07][t]
    top = gy - height
    if t <= 4:
        n = 12
        for layer, (sc, lv) in enumerate(((1.0, 2), (0.78, 3), (0.5, 4), (0.22, 5))):
            left, right = [], []
            for i in range(n + 1):
                y = gy - height * i / n
                wob = math.sin(i * 1.4 + t * 1.3 + layer) * width * 0.2
                ww = width * sc * (1 - 0.45 * (i / n) ** 1.5) + (1 if i % 2 else 0)
                left.append((c - ww + wob, y))
                right.append((c + ww + wob, y))
            tip = (c + math.sin(t + layer) * 2, top - width * (1.4 - 0.3 * layer))
            f.poly(left + [tip] + right[::-1], lv)
        for i in range(7):
            y = gy - height * (0.12 + 0.13 * i)
            side = -1 if i % 2 else 1
            f.flame(c + side * width * 0.75, y, -math.pi / 2 + side * 0.9, s * (0.17 - 0.012 * i), s * 0.05, 5 if t < 4 else 4, bend=-side * 0.9)
        # 巻きつく火の帯（前側半分だけ明るい）
        for k in range(2 if t >= 2 else 1):
            yy = gy - height * (0.35 + 0.3 * k) + (t % 2) * 2
            f.ring(c, yy, width * 1.5, 2, 5, sy=0.32, sectors=1, keep=0.5, rot=0.0)
            f.ring(c, yy, width * 1.5, 1.5, 3, sy=0.32)
        f.mass(c, gy, s * (0.22 + 0.03 * t), s * 0.075, 5, n=10, seed=t + 2)
        f.ring(c, gy, s * (0.28 + 0.04 * t), 2, 3, sy=0.32)
    if t >= 3:
        for i in range(6):
            y = gy - s * (0.15 + 0.11 * i) - (t - 3) * s * 0.07
            x = c + math.sin(i * 2.1 + t) * s * (0.2 + 0.03 * i)
            f.diamond(x, y, 3, 1.8, -math.pi / 2, 5 if t < 5 else 4)
    if t == 5:
        f.mass(c, gy, s * 0.1, s * 0.05, 4, n=7, seed=9)
        f.flame(c, gy, -math.pi / 2, s * 0.14, s * 0.05, 4)


def sig_glacial(f, t, rng):
    """太い氷槍が両側から降り注ぎ、着地で結晶が咲いて大きく砕ける。"""
    s, c = f.w, f.cx
    gy = f.h * GROUND
    spears = [(-0.3, -0.35, 0.0), (0.28, 0.3, 0.12), (-0.12, -0.15, 0.22), (0.1, 0.12, 0.3), (-0.4, -0.5, 0.42), (0.38, 0.45, 0.5), (0.0, 0.03, 0.6)]

    def spear(tx, ty, tilt, length, w):
        ang = math.pi / 2 + tilt  # 下向き
        dx, dy = math.cos(ang), math.sin(ang)
        px_, py_ = -dy, dx
        bx, by = tx - dx * length, ty - dy * length
        sx, sy_ = tx - dx * length * 0.3, ty - dy * length * 0.3
        f.line([(bx - dx * 3, by - dy * 3), (bx - dx * length * 0.35, by - dy * length * 0.35)], 2, 2)
        f.poly([(tx, ty), (sx + px_ * w, sy_ + py_ * w), (bx + px_ * w * 0.6, by + py_ * w * 0.6), (bx - px_ * w * 0.6, by - py_ * w * 0.6), (sx - px_ * w, sy_ - py_ * w)], 3)
        f.poly([(tx, ty), (sx + px_ * w * 0.95, sy_ + py_ * w * 0.95), (bx + px_ * w * 0.55, by + py_ * w * 0.55), (bx, by), (sx, sy_)], 4)
        f.poly([(tx, ty), (sx - px_ * w, sy_ - py_ * w), (sx - px_ * w * 0.4, sy_ - py_ * w * 0.4)], 2, over=True)
        f.line([(tx - dx * 1.5, ty - dy * 1.5), (sx + px_ * w * 0.5, sy_ + py_ * w * 0.5), (bx + px_ * w * 0.3, by + py_ * w * 0.3)], 5, 1)

    def cluster(scale, top_lv):
        for i in range(9):
            a = -math.pi / 2 + (i - 4) * 0.3
            ln = s * (0.3 if i == 4 else 0.22 if i % 2 == 0 else 0.15) * scale
            x, y = c + math.cos(a) * ln * 0.5, gy + math.sin(a) * ln * 0.5
            f.shard(x, y, ln * 0.55, s * 0.045 * scale + 0.8, a, top_lv)

    L, W = s * 0.34, s * 0.06
    if t <= 1:
        k = [0.42, 0.82][t]
        for i, (ox, tilt, lag) in enumerate(spears[: 4 if t == 0 else 7]):
            ty = gy * k - lag * s * 0.35
            fall = gy - ty
            spear(c + ox * s * 0.6 - math.sin(tilt) * fall * 0.0 + ox * s * 0.4 * (1 - k), ty, -tilt * 0.45, L, W)
        if t == 1:
            f.ring(c, gy, s * 0.22, 2, 2, sy=0.35)
    elif t == 2:
        f.mass(c, gy, s * 0.34, s * 0.12, 5, n=12, amp=0.4, seed=12)
        for i, (ox, tilt, lag) in enumerate(spears):
            spear(c + ox * s * 0.62, gy - lag * s * 0.08, -tilt * 0.45, L * (0.8 - lag * 0.3), W)
        cluster(0.8, 5)
        f.ring(c, gy, s * 0.4, 2.5, 4, sy=0.35)
    elif t == 3:
        f.mass(c, gy, s * 0.24, s * 0.08, 4, n=10, seed=13)
        cluster(1.15, 5)
        f.ring(c, gy, s * 0.46, 2.5, 4, sy=0.35)
        for i in range(4):
            a = -math.pi / 2 + (i - 1.5) * 0.9
            f.shard(c + math.cos(a) * s * 0.36, gy + math.sin(a) * s * 0.3, s * 0.09, s * 0.04, a, 5)
    elif t == 4:
        cluster(0.45, 4)
        for i in range(7):
            a = -math.pi / 2 + (i - 3) * 0.48
            d = s * 0.36
            f.shard(c + math.cos(a) * d, gy + math.sin(a) * d * 0.85, s * 0.09, s * 0.045, a, 5)
        f.ring(c, gy, s * 0.49, 2, 3, sy=0.35, sectors=8, keep=0.5)
    else:
        for i in range(5):
            a = -math.pi / 2 + (i - 2) * 0.62
            d = s * 0.44
            f.shard(c + math.cos(a) * d, gy + math.sin(a) * d * 0.85, s * 0.06, s * 0.03, a, 4)


def sig_radiant(f, t, rng):
    """光の刃が扇状に立ち上がる。"""
    s, c = f.w, f.cx
    gy = f.h * GROUND
    count = [3, 5, 7, 7, 7, 0][t]
    reach = [0.3, 0.5, 0.62, 0.62, 0.54, 0][t] * s
    for i in range(count):
        k = i - (count - 1) / 2
        if t == 4 and i % 2:
            continue
        a = -math.pi / 2 + k * 0.32
        L = reach * (1 - abs(k) * 0.08)
        bx, by = c + math.cos(a) * s * 0.05, gy + math.sin(a) * s * 0.05
        tx, ty = bx + math.cos(a) * L, by + math.sin(a) * L
        px_, py_ = -math.sin(a), math.cos(a)
        w = s * 0.036
        sh = (bx + math.cos(a) * L * 0.75, by + math.sin(a) * L * 0.75)
        f.poly([(tx, ty), (sh[0] + px_ * w, sh[1] + py_ * w), (bx + px_ * w * 0.8, by + py_ * w * 0.8), (bx - px_ * w * 0.8, by - py_ * w * 0.8), (sh[0] - px_ * w, sh[1] - py_ * w)], 3)
        f.poly([(tx, ty), (sh[0] + px_ * w, sh[1] + py_ * w), (bx + px_ * w * 0.8, by + py_ * w * 0.8), (bx, by)], 4)
        f.line([(bx, by), (tx - math.cos(a) * 2, ty - math.sin(a) * 2)], 5, 1)
        gx, gy2 = bx + math.cos(a) * L * 0.14, by + math.sin(a) * L * 0.14
        f.line([(gx + px_ * w * 2.4, gy2 + py_ * w * 2.4), (gx - px_ * w * 2.4, gy2 - py_ * w * 2.4)], 4, 2)
    if t <= 4:
        f.mass(c, gy, s * [0.08, 0.12, 0.17, 0.13, 0.08, 0][t], s * [0.04, 0.06, 0.08, 0.06, 0.04, 0][t], 5, n=8, seed=t)
    if t >= 2:
        f.ring(c, gy, s * (0.26 + 0.08 * (t - 2)), 2, 4 if t < 4 else 3, sy=0.35, sectors=0 if t < 4 else 8, keep=0.5)
    if t >= 2:
        for i in range(6):
            a = -math.pi / 2 + (i - 2.5) * 0.42
            d = s * (0.5 + 0.06 * (t - 2))
            f.spark(c + math.cos(a) * d, gy + math.sin(a) * d * 0.9, 2 if i % 2 else 1, 5 if t < 5 else 4)


def sig_void(f, t, rng):
    """空間を斜めに断つ裂け目。中は虚無、縁は白紫、ひびと破片が飛ぶ。"""
    s, c = f.w, f.cx
    cy = f.h * 0.56
    r = np.random.default_rng(51)
    ang = math.radians(-28)
    half = s * [0.22, 0.44, 0.48, 0.48, 0.4, 0.25][t]
    open_ = [0.0, 0.55, 1.0, 0.75, 0.3, 0.0][t]
    ux, uy = math.cos(ang), math.sin(ang)
    nx, ny = -uy, ux
    if 1 <= t <= 3:
        f.blob(c, cy, half * 1.05, s * 0.2 * open_ + 3, 12, 0.55, 2, seed=t, tilt=ang)
        for i in range(4):
            sp = _spiral(c, cy, i * TAU / 4 + t * 0.5, s * 0.18, s * 0.42, 1.2, n=8)
            f.line(sp, 3, 2)
            f.line(sp[-3:], 4, 1)
    if t >= 2 and t <= 4:
        for i in range(6):
            u = -0.6 + 0.24 * i
            side = 1 if i % 2 else -1
            x, y = c + ux * half * u, cy + uy * half * u
            ln = s * (0.16 + 0.06 * (i % 3)) * (1.0 if t < 4 else 0.6)
            p = jag((x, y), (x + nx * side * ln + ux * ln * 0.3, y + ny * side * ln + uy * ln * 0.3), 3, s * 0.03, r)
            f.line(p, 4 if t < 4 else 3, 2 if t == 2 else 1)
    if open_ > 0:
        flare = half * (1.35 if t == 2 else 1.2)
        f.line([(c - ux * flare, cy - uy * flare), (c + ux * flare, cy + uy * flare)], 4, 1)
        _rift(f, c, cy, half, open_, ang, 52, s)
    else:
        f.line([(c - ux * half, cy - uy * half), (c + ux * half, cy + uy * half)], 5 if t == 0 else 3, 2 if t == 0 else 1)
        if t == 0:
            f.line([(c - ux * half * 1.3, cy - uy * half * 1.3), (c + ux * half * 1.3, cy + uy * half * 1.3)], 3, 1)
            f.spark(c, cy, 2, 5)
    if t >= 2:
        d = s * [0, 0, 0.2, 0.3, 0.38, 0.44][t]
        for i in range(8):
            u = -0.8 + 0.23 * i
            side = 1 if i % 2 else -1
            x = c + ux * half * u * 0.9 + nx * side * d * (0.8 + 0.25 * (i % 3))
            y = cy + uy * half * u * 0.9 + ny * side * d * (0.8 + 0.25 * (i % 3))
            a = math.atan2(ny * side, nx * side) + (i - 4) * 0.12
            size = s * (0.075 if t < 4 else 0.055 if t == 4 else 0.04)
            pts = [(x + math.cos(a) * size, y + math.sin(a) * size), (x + math.cos(a + 2.2) * size * 0.75, y + math.sin(a + 2.2) * size * 0.75), (x + math.cos(a - 2.0) * size * 0.65, y + math.sin(a - 2.0) * size * 0.65)]
            f.poly(pts, 2 if t < 5 else 1)
            f.line(pts[:2], 4 if t < 5 else 3, 1)
    if t == 2:
        f.ring(c, cy, s * 0.47, 1.5, 3, sy=0.6, sectors=10, keep=0.4, rot=0.3)


# ------------------------------------------------------------------ 戦技（88px）
def active_aura(f, t, rng):
    c, R = f.cx, f.w * 0.46
    k = min(GROW[t], 1.0)
    rot = t * 0.5
    if t <= 3:
        f.blob(c, c, R * 0.85 * k, R * 0.85 * k, 12, 0.2, 2, seed=t)
    for i in range(3):
        sp = _spiral(c, c, i * TAU / 3 + rot, R * 0.15 * k, R * 0.92 * k, 2.2, n=14)
        f.line(sp, 3, 5 if t < 4 else 3)
        f.line(sp[:10], 4, 2 if t < 4 else 1)
        f.line(sp[:5], 5, 1)
    if t <= 3:
        f.mass(c, c, R * 0.26 * k, R * 0.26 * k, 5, n=7, seed=t + 3)
    for i in range(4):
        a = i * TAU / 4 + rot * 1.5
        f.spark(c + math.cos(a) * R * 0.75 * k, c + math.sin(a) * R * 0.75 * k, 1, 5 if t < 4 else 4)
    if t >= 4:
        f.cut(f.dist(c, c) < R * 0.3)


def active_burst(f, t, rng):
    c, R = f.cx, f.w * 0.46
    if t == 0:
        f.star(c, c, 4, R * 0.35, R * 0.25, 1.6, 5)
        f.glow_disc(c, c, R * 0.14, 5)
    elif t <= 2:
        k = 0.7 if t == 1 else 1.0
        f.mass(c, c, R * 0.55 * k, R * 0.55 * k, 4, n=12, amp=0.5, seed=t)
        f.star(c, c, 12, R * k, R * 0.6 * k, 3.0, 5)
        f.glow_disc(c, c, R * 0.28 * k, 5)
    elif t == 3:
        f.mass(c, c, R * 0.3, R * 0.3, 3, n=10, amp=0.5, seed=4)
        for i in range(12):
            a = i * TAU / 12
            f.shard(c + math.cos(a) * R * 0.62, c + math.sin(a) * R * 0.62, R * (0.3 if i % 2 == 0 else 0.2), R * 0.07 + 1, a, 5)
        f.glow_disc(c, c, R * 0.14, 4)
    elif t == 4:
        for i in range(8):
            a = i * TAU / 8 + 0.2
            f.shard(c + math.cos(a) * R * 0.82, c + math.sin(a) * R * 0.82, R * 0.16, R * 0.06 + 1, a, 4)
    else:
        for i in range(5):
            a = i * TAU / 5 + 0.5
            f.spark(c + math.cos(a) * R * 0.92, c + math.sin(a) * R * 0.92, 1, 4)


def active_chains(f, t, rng):
    c, R = f.cx, f.w * 0.46
    k = [0.45, 0.8, 1.0, 1.0, 0.9, 0.75][t]
    for j, a in enumerate((math.pi / 4, -math.pi / 4, 0.1)):
        if j == 2 and t < 1:
            continue
        L = R * k
        dx, dy = math.cos(a), math.sin(a)
        links = 7
        for i in range(-links, links + 1):
            if t >= 4 and (i % 3 == 0):
                continue
            u = i / links
            x, y = c + dx * L * u, c + dy * L * u
            if i % 2 == 0:
                f.ring(x, y, R * 0.08, 1.6, 4, sy=0.6)
            else:
                f.diamond(x, y, R * 0.07, R * 0.035 + 0.6, a, 3)
    if t in (2, 3):
        f.glow_disc(c, c, R * 0.2, 5)
        for i in range(4):
            a = i * TAU / 4 + math.pi / 8
            f.spark(c + math.cos(a) * R * 0.3, c + math.sin(a) * R * 0.3, 1, 5)


def active_charge(f, t, rng):
    s, c = f.w, f.cx
    reach = [0.3, 0.65, 0.95, 0.95, 0.8, 0.6][t]
    x0 = c - s * 0.45
    x1 = x0 + s * 0.9 * reach
    if t <= 3:
        f.blob((x0 + x1) / 2, c, (x1 - x0) * 0.55, s * 0.12, 10, 0.4, 2, seed=t)
        for i, oy in enumerate((-0.14, -0.07, 0.07, 0.14)):
            f.flame(x1 - s * (0.12 + 0.05 * i), c + oy * s, math.pi + (0.2 if oy > 0 else -0.2), s * (0.3 - 0.03 * i) * reach, s * 0.04, 5, bend=(0.3 if oy > 0 else -0.3))
        w = s * 0.08
        f.poly([(x0 + s * 0.1, c), (x1 - w * 2, c - w), (x1, c), (x1 - w * 2, c + w)], 3)
        f.poly([(x0 + s * 0.2, c), (x1 - w * 2, c - w * 0.5), (x1 - 1, c), (x1 - w * 2, c + w * 0.5)], 4)
        f.line([(x0 + s * 0.3, c), (x1 - 2, c)], 5, 1)
    else:
        for i in range(4):
            y = c + (i - 1.5) * s * 0.08
            x = x1 - s * (0.1 + 0.12 * i)
            f.flame(x, y, math.pi, s * 0.16, s * 0.03, 4 if t == 4 else 3)
        f.spark(x1, c, 1, 4)


def active_execution(f, t, rng):
    s, c = f.w, f.cx
    L = s * [0.2, 0.44, 0.5, 0.5, 0.42, 0.26][t]
    W = s * [0.025, 0.06, 0.09, 0.06, 0.035, 0.02][t]
    if 1 <= t <= 3:
        f.blob(c, c, L * 0.8, W * 2.6 + 2, 10, 0.5, 2, seed=t)
    f.poly([(c - L, c), (c, c - W), (c + L, c), (c, c + W)], 3)
    f.poly([(c - L * 0.8, c), (c, c - W * 0.6), (c + L * 0.8, c), (c, c + W * 0.6)], 4)
    f.line([(c - L * 0.7, c), (c + L * 0.7, c)], 5, 1)
    if t in (1, 2, 3):
        k = [0, 0.6, 1.0, 0.7][t]
        f.ray(c, c, -math.pi / 2, 0, s * 0.3 * k, 2.5, 5, tones=3)
        f.ray(c, c, math.pi / 2, 0, s * 0.3 * k, 2.5, 5, tones=3)
        f.glow_disc(c, c, s * 0.06 * k + 1, 5)
        for i in range(4):
            a = i * TAU / 4 + math.pi / 4
            f.ray(c, c, a, s * 0.04, s * 0.17 * k, 1.5, 4, tones=2)
    if t >= 3:
        for i in range(5):
            x = c + (i - 2) * s * 0.17
            f.shard(x, c + (-1) ** i * s * 0.08 * (t - 2), s * 0.05, s * 0.025 + 0.6, (-1) ** i * math.pi / 2, 5 if t < 5 else 4)


def active_holy_burst(f, t, rng):
    concept_light(f, t, rng)
    c, R = f.cx, f.w * 0.46
    if t in (2, 3):
        f.ring(c, c, R * (0.9 + 0.06 * (t - 2)), 2.5, 4, sectors=0 if t == 2 else 8, keep=0.6)


def active_impact(f, t, rng):
    s, c = f.w, f.cx
    gy = f.h * 0.66
    if t == 0:
        f.mass(c, gy, s * 0.1, s * 0.05, 5, n=7, seed=1)
        return
    k = [0, 0.65, 1.0, 1.0, 0.8, 0.5][t]
    if t <= 3:
        f.mass(c, gy - s * 0.12 * k, s * 0.3 * k, s * 0.24 * k, 5 if t < 3 else 4, n=11, amp=0.45, seed=t)
        for i in range(7):
            a = -math.pi / 2 + (i - 3) * 0.36
            f.flame(c, gy, a, s * 0.44 * k * (1 - abs(i - 3) * 0.1), s * 0.06, 5, bend=(i - 3) * 0.12)
    else:
        f.mass(c, gy - s * 0.2, s * 0.16 * k, s * 0.12 * k, 3, n=9, amp=0.5, seed=t, depth=3)
    f.ring(c, gy, s * (0.2 + 0.07 * t), 2.5, 4 if t < 4 else 3, sy=0.35, sectors=0 if t < 4 else 8, keep=0.55)
    if t >= 2:
        for i in range(6):
            a = -math.pi / 2 + (i - 2.5) * 0.5
            d = s * (0.32 + 0.06 * (t - 2))
            f.diamond(c + math.cos(a) * d, gy - s * 0.05 + math.sin(a) * d * 0.8, 3, 2, a, 4 if t < 5 else 3)


def active_rain(f, t, rng):
    s, c = f.w, f.cx
    gy = f.h * 0.76
    xs = [-0.26, 0.04, 0.28, -0.1, 0.16, -0.34, 0.36, -0.02]
    lag = [0.0, 0.1, 0.25, 0.4, 0.55, 0.7, 0.85, 1.0]
    for i, (ox, lg) in enumerate(zip(xs, lag)):
        prog = (t + 1) / 2.4 - lg
        if prog < 0:
            continue
        x = c + ox * s
        if prog < 1:
            y = gy * (0.25 + 0.75 * prog)
            L, w = s * 0.24, s * 0.035
            f.line([(x, y - L * 1.6), (x, y - L)], 2, 1)
            f.poly([(x, y), (x - w, y - L * 0.35), (x - w * 0.6, y - L), (x + w * 0.6, y - L), (x + w, y - L * 0.35)], 3)
            f.poly([(x, y), (x - w, y - L * 0.35), (x - w * 0.6, y - L), (x, y - L)], 4)
            f.line([(x, y - 1), (x, y - L * 0.8)], 5, 1)
        elif prog < 2:
            kk = prog - 1
            f.mass(x, gy, s * 0.08 * (1 + kk * 0.5), s * 0.035, 4 if kk < 0.5 else 3, n=6, seed=i, depth=3)
            for j in range(3):
                a = -math.pi / 2 + (j - 1) * 0.6
                f.shard(x + math.cos(a) * s * 0.04, gy + math.sin(a) * s * 0.04, s * 0.06 * (1 - kk * 0.4), s * 0.02 + 0.6, a, 5 if kk < 0.5 else 4)


def active_sanctuary(f, t, rng):
    c, R = f.cx, f.w * 0.46
    k = [0.3, 0.7, 1.0, 1.0, 0.95, 0.9][t]
    top = 5 if t < 4 else 4
    f.ring(c, c, R * 0.95 * k, 2, top - 1)
    f.ring(c, c, R * 0.72 * k, 1.5, top - 2, sectors=12, keep=0.6, rot=t * 0.2)
    if t >= 1:
        # 外周のルーン（小さな菱形）
        for i in range(8):
            a = i * TAU / 8 + t * 0.15
            f.diamond(c + math.cos(a) * R * 0.84 * k, c + math.sin(a) * R * 0.84 * k, 2.6, 1.6, a, top)
        # 内の三角
        tri = [(c + math.cos(-math.pi / 2 + j * TAU / 3) * R * 0.6 * k, c + math.sin(-math.pi / 2 + j * TAU / 3) * R * 0.6 * k) for j in range(3)]
        f.line(tri + [tri[0]], top - 1, 1)
    if t <= 3:
        f.glow_disc(c, c, R * 0.18 * k, 5)
        f.star(c, c, 4, R * 0.35 * k, R * 0.35 * k, 1.2, 5, rot=-math.pi / 2)
    if t >= 4:
        f.cut(np.mod(f.angle(c, c) / TAU * 8 + 0.1 * t, 1.0) < 0.25)


def active_shield(f, t, rng):
    c, R = f.cx, f.w * 0.46
    k = [0.4, 0.8, 1.0, 1.0, 1.05, 1.1][t]
    hexp = [(c + math.cos(i * TAU / 6 - math.pi / 2) * R * 0.88 * k, c + math.sin(i * TAU / 6 - math.pi / 2) * R * 0.88 * k) for i in range(6)]
    if t <= 3:
        for i in range(6):
            a, b = hexp[i], hexp[(i + 1) % 6]
            f.poly([(c, c), a, b], 2 if i % 2 else 3)
        f.poly([hexp[5], hexp[0], (c, c)], 4 if t == 2 else 3)
        f.glow_disc(c, c, R * 0.3 * k, 5)
        f.line(hexp + [hexp[0]], 4, 3)
        f.line(hexp + [hexp[0]], 5, 1)
        inner = [(c + (x - c) * 0.55, c + (y - c) * 0.55) for x, y in hexp]
        f.line(inner + [inner[0]], 4, 1)
        for (x, y) in hexp:
            f.spark(x, y, 2, 5)
    else:
        for i in range(6):
            if (i + t) % 2:
                continue
            a, b = hexp[i], hexp[(i + 1) % 6]
            f.line([a, b], 4 if t == 4 else 3, 3)
        for i in range(6):
            a = i * TAU / 6
            f.shard(c + math.cos(a) * R * 0.95 * k, c + math.sin(a) * R * 0.95 * k, R * 0.1, R * 0.05 + 0.6, a, 5 if t == 4 else 4)


def active_summon(f, t, rng):
    s, c = f.w, f.cx
    gy = f.h * 0.82
    k = [0.35, 0.7, 1.0, 1.0, 0.85, 0.6][t]
    f.ring(c, gy, s * 0.36 * min(k + 0.2, 1.0), 2, 4 if t < 4 else 3, sy=0.3)
    if t <= 3:
        f.mass(c, gy, s * 0.3 * min(k + 0.2, 1.0), s * 0.07, 4, n=10, seed=t, depth=3)
    ghosts = [(-0.22, 0.32, 0.65), (0.22, 0.3, 0.65), (0.0, 0.42, 1.0)]
    for gi, (ox, hgt, sc) in enumerate(ghosts):
        if t == 0 and gi < 2:
            continue
        rise = s * hgt * k + (s * 0.05 * (t - 3) if t >= 4 else 0)
        x, y = c + ox * s, gy - rise
        hr = s * 0.11 * sc * min(k + 0.3, 1.0)
        top = 5 if t < 4 else 4
        # 尾（揺らぐ炎）
        f.flame(x, y + hr * 0.4, math.pi / 2 + 0.2 * math.sin(t + gi), hr * 3.0, hr * 0.9, top - 1, bend=0.6 * math.sin(t * 1.3 + gi))
        f.disc(x, y, hr, top - 2)
        f.disc(x - hr * 0.15, y - hr * 0.15, hr * 0.7, top - 1)
        f.disc(x - hr * 0.3, y - hr * 0.35, hr * 0.3, top)
        for ex in (-0.38, 0.32):
            f.poly([(x + hr * ex - 1, y - 0.5), (x + hr * ex + 1, y - 0.5), (x + hr * ex + 1, y + 1.5), (x + hr * ex - 1, y + 1.5)], 1, over=True)
    if t >= 2:
        for i in range(4):
            f.spark(c + (i - 1.5) * s * 0.2, gy - s * (0.1 + 0.14 * ((i + t) % 3)), 1, 5 if t < 5 else 4)


def active_time(f, t, rng):
    c, R = f.cx, f.w * 0.46
    k = [0.4, 0.8, 1.0, 1.0, 1.0, 1.0][t]
    top = 5 if t < 4 else 4
    if t <= 3:
        f.disc(c, c, R * 0.9 * k, 1)
        for j in range(2):
            f.crescent(c, c, R * 0.85 * k, R * 0.26, -math.pi + j * math.pi + t * 0.6, j * math.pi + t * 0.6, 3, (0, 1), peak=0.8)
    f.ring(c, c, R * 0.92 * k, 2, top - 1, sectors=0 if t < 4 else 12, keep=0.6)
    for i in range(12):
        a = i * TAU / 12
        r0 = R * (0.72 if i % 3 == 0 else 0.8) * k
        f.line([(c + math.cos(a) * r0, c + math.sin(a) * r0), (c + math.cos(a) * R * 0.88 * k, c + math.sin(a) * R * 0.88 * k)], top - 1 if i % 3 else top, 2 if i % 3 == 0 else 1)
    ha = -math.pi / 2 - t * 0.9
    ma = -math.pi / 2 + t * 0.5
    if t <= 4:
        f.line([(c, c), (c + math.cos(ha) * R * 0.64 * k, c + math.sin(ha) * R * 0.64 * k)], top, 3)
        f.line([(c, c), (c + math.cos(ma) * R * 0.44 * k, c + math.sin(ma) * R * 0.44 * k)], top - 1, 3)
        f.glow_disc(c, c, 3.5, top)


# ------------------------------------------------------------------ 線・その他
def chain_line(f, t, rng):
    w, h = f.w, f.h
    cy = h / 2
    r = np.random.default_rng(61 + (t % 2))
    reach = [0.5, 1.0, 1.0, 1.0, 1.0, 1.0][t]
    pts = jag((0, cy), (w * reach, cy), 8, h * 0.6, r)
    if t <= 3:
        f.bolt(pts, 5, 3 if t in (1, 2) else 2)
        if t == 2:
            f.bolt(jag(pts[3], (pts[3][0] + w * 0.2, cy + h * 0.35), 3, h * 0.2, r), 4, 1)
    elif t == 4:
        for i in range(0, len(pts) - 1, 2):
            f.bolt(pts[i : i + 2], 4, 2)
    else:
        for i in range(1, len(pts) - 1, 3):
            f.spark(*pts[i], 1, 4)


def beam_line(f, t, rng):
    w, h = f.w, f.h
    cy = h / 2
    th = [1.5, 3.5, 5, 4, 2.5, 1.5][t]
    f.poly([(0, cy - th * 0.6), (w * 0.08, cy - th), (w * 0.92, cy - th), (w, cy - th * 0.6), (w, cy + th * 0.6), (w * 0.92, cy + th), (w * 0.08, cy + th), (0, cy + th * 0.6)], 3)
    f.poly([(0, cy - th * 0.3), (w, cy - th * 0.3), (w, cy + th * 0.3), (0, cy + th * 0.3)], 4)
    f.line([(1, cy), (w - 1, cy)], 5 if t < 4 else 4, 1)
    if t in (1, 2, 3):
        for i in range(4):
            x = w * (0.15 + 0.23 * i) + t * 2
            f.spark(x, cy + (-1) ** i * (th + 1), 1, 5)


def mass_kill(f, t, rng):
    c, R = f.cx, f.w * 0.46
    if t == 0:
        f.spark(c, c, 3, 5)
        f.glow_disc(c, c, R * 0.12, 5)
    elif t <= 2:
        k = 0.7 if t == 1 else 1.0
        f.mass(c, c, R * 0.5 * k, R * 0.5 * k, 4, n=10, amp=0.5, seed=t)
        f.star(c, c, 8, R * k, R * 0.55 * k, 2.6, 5)
        f.glow_disc(c, c, R * 0.24 * k, 5)
        for i in range(6):
            a = i * TAU / 6 + 0.3
            f.diamond(c + math.cos(a) * R * 0.62 * k, c + math.sin(a) * R * 0.62 * k, 3.5, 2.5, -math.pi / 2, 4)
            f.px(c + math.cos(a) * R * 0.62 * k - 1, c + math.sin(a) * R * 0.62 * k - 1, 5)
    elif t <= 4:
        d = R * (0.75 if t == 3 else 0.9)
        for i in range(9):
            a = i * TAU / 9 + 0.15 * t
            x, y = c + math.cos(a) * d, c + math.sin(a) * d
            f.diamond(x, y, 3.5 if t == 3 else 3, 2.5 if t == 3 else 2, -math.pi / 2, 4)
            f.px(x - 1, y - 1, 5)
        if t == 3:
            f.ring(c, c, R * 0.5, 2, 3, sectors=8, keep=0.5)
            f.glow_disc(c, c, R * 0.12, 4)
    else:
        for i in range(5):
            a = i * TAU / 5 + 0.8
            f.spark(c + math.cos(a) * R * 0.94, c + math.sin(a) * R * 0.94, 1, 4)


def forge_awaken(f, t, rng):
    c, R = f.cx, f.w * 0.46
    k = [0.4, 0.75, 1.0, 1.0, 1.0, 1.0][t]
    if t <= 3:
        tri = [(c + math.cos(-math.pi / 2 + j * TAU / 3) * R * 0.7 * k, c + math.sin(-math.pi / 2 + j * TAU / 3) * R * 0.7 * k) for j in range(3)]
        f.line(tri + [tri[0]], 4, 2)
        f.ring(c, c, R * 0.85 * k, 2, 4)
        f.ring(c, c, R * 0.55 * k, 1.2, 3, sectors=6, keep=0.6, rot=t * 0.3)
        for (x, y) in tri:
            f.glow_disc(x, y, R * 0.1, 5)
        f.glow_disc(c, c, R * (0.12 + 0.12 * (t >= 2)) * k, 5)
    if t >= 2:
        n = 8
        d = R * [0, 0, 0.5, 0.7, 0.85, 0.95][t]
        for i in range(n):
            a = i * TAU / n + 0.2
            if t <= 3:
                f.flame(c + math.cos(a) * d * 0.6, c + math.sin(a) * d * 0.6, a, R * 0.3, R * 0.07, 5)
            else:
                f.diamond(c + math.cos(a) * d, c + math.sin(a) * d, 3 if t == 4 else 2, 2 if t == 4 else 1.4, a, 4)


def loot_awaken(f, t, rng):
    s, c = f.w, f.cx
    gy = f.h * 0.8
    k = [0.35, 0.75, 1.0, 1.0, 0.8, 0.5][t]
    f.ring(c, gy, s * 0.4 * min(k + 0.2, 1.0), 2, 4 if t < 4 else 3, sy=0.35)
    if t <= 4:
        for i in range(5):
            a = -math.pi / 2 + (i - 2) * 0.42
            ln = s * (0.62 if i == 2 else 0.46 if i in (1, 3) else 0.34) * k
            f.ray(c, gy, a, 0, ln, s * 0.07, 5 if t < 4 else 4, tones=3)
        f.mass(c, gy, s * 0.14 * k, s * 0.06 * k, 5, n=6, seed=t, depth=3)
    if t >= 2:
        for i in range(3):
            x = c + (i - 1) * s * 0.3
            y = gy - s * (0.4 + 0.12 * (i % 2)) - (t - 2) * s * 0.05
            f.spark(x, y, 1, 5 if t < 5 else 4)


def poison_loop(f, t, rng):
    """6コマでひと回りする毒沼。底は最暗、渦と泡が明るい。"""
    c, R = f.cx, f.w * 0.46
    rot = t * TAU / 6 / 3
    f.blob(c, c, R * 0.86, R * 0.86, 14, 0.18, 1, seed=t % 2)
    f.blob(c, c, R * 0.6, R * 0.6, 10, 0.3, 2, seed=5 + t % 2, rot=rot)
    for i in range(3):
        sp = _spiral(c, c, i * TAU / 3 + rot, R * 0.12, R * 0.84, 2.4, n=14)
        f.line(sp, 3, 3)
        f.line(sp[3:10], 4, 1)
    for i in range(6):
        a = i * TAU / 6 + rot * 2 + 0.3
        d = R * (0.3 + 0.12 * ((i + t) % 4))
        size = [1.0, 1.6, 2.2, 1.6][(i + t) % 4]
        f.disc(c + math.cos(a) * d, c + math.sin(a) * d, size, 4)
        f.px(c + math.cos(a) * d - size * 0.4, c + math.sin(a) * d - size * 0.4, 5)


# ------------------------------------------------------------------ 静止画
def loot_seal(f):
    c = f.cx
    R = f.w * 0.36
    octa = [(c + math.cos(i * TAU / 8 + TAU / 16) * R, c + math.sin(i * TAU / 8 + TAU / 16) * R) for i in range(8)]
    f.poly(octa, 3)
    inner = [(c + (x - c) * 0.72, c + (y - c) * 0.72) for x, y in octa]
    f.poly(inner, 4)
    f.line(inner + [inner[0]], 2, 1)
    f.diamond(c, c, R * 0.3, R * 0.3, 0, 5)
    f.diamond(c, c, R * 0.14, R * 0.14, 0, 3)
    for side in (-1, 1):
        x = c + side * f.w * 0.46
        f.line([(x - side * 3, c - R * 0.9), (x, c - R * 0.6), (x, c + R * 0.6), (x - side * 3, c + R * 0.9)], 4, 1)


def projectile_core(f):
    c, R = f.cx, f.w * 0.46
    f.glow_disc(c, c, R * 0.7, 5)
    f.spark(c, c, 3, 5)


WARNING_RING_RADIUS = 50  # 見える円周の外端（px）。warning_circle.gd の RING_PIXEL_RADIUS と一致させる


def warning_ring(f):
    c = f.cx
    f.ring(c, c, WARNING_RING_RADIUS, 2, 5)
    f.ring(c, c, WARNING_RING_RADIUS - 2, 1, 3)
    for i in range(4):
        a = i * TAU / 4
        f.line([(c + math.cos(a) * (WARNING_RING_RADIUS - 1), c + math.sin(a) * (WARNING_RING_RADIUS - 1)), (c + math.cos(a) * (WARNING_RING_RADIUS + 5), c + math.sin(a) * (WARNING_RING_RADIUS + 5))], 5, 2)
    for i in range(4):
        a = i * TAU / 4 + math.pi / 4
        f.diamond(c + math.cos(a) * (WARNING_RING_RADIUS - 5), c + math.sin(a) * (WARNING_RING_RADIUS - 5), 2, 1.2, a, 4)


# ------------------------------------------------------------------ 一覧
# (出力パス, コマ幅, コマ高さ, ランプ, 描画関数, 表示サイズ(比較ボード用))
def _sw(R, th, span, chunks=3, twin=False, peak=0.62):
    return lambda f, t, rng: swing(f, t, f.w * R, f.w * th, span, chunks, twin=twin, peak=peak)


ANIMATED = [
    # 職業通常攻撃（AttackVFXManager。高さは不透明部から自動換算）
    ("attack/attack_slash_6f.png", 32, 32, "steel", _sw(0.44, 0.2, 1.25), 40),
    ("attack/attack_pulse_6f.png", 32, 32, "steel", pulse, 40),
    ("attack/attack_projectile_6f.png", 32, 32, "steel", projectile, 40),
    ("attack/hit_normal_6f.png", 32, 32, "steel", hit_steel, 36),
    ("attack/hit_critical_6f.png", 32, 32, "gold", lambda f, t, r: hit_steel(f, t, r, crit=True), 44),
    # 装備武器（floating_weapons.gd。表示＝64*cut/26）
    ("equipment_comfy/light_6f.png", 48, 48, "steel", _sw(0.4, 0.12, 1.1, twin=True), 62),
    ("equipment_comfy/slash_6f.png", 48, 48, "steel", _sw(0.44, 0.19, 1.25), 88),
    ("equipment_comfy/heavy_6f.png", 48, 48, "steel", _sw(0.46, 0.3, 1.4, chunks=4), 128),
    ("equipment_comfy/thrust_6f.png", 48, 48, "steel", thrust, 108),
    ("equipment_comfy/axe_6f.png", 48, 48, "steel", _sw(0.42, 0.26, 0.85, peak=0.75), 94),
    ("equipment_comfy/hammer_6f.png", 48, 48, "steel", hammer, 78),
    ("equipment_comfy/scythe_6f.png", 48, 48, "steel", _sw(0.46, 0.12, 1.9, chunks=5), 142),
    ("equipment_comfy/shot_6f.png", 24, 24, "gold", muzzle, 42),
    ("equipment_comfy/magic_6f.png", 20, 20, "arcane", orb, 35),
    # 回避・宝箱（imported_burst_vfx.gd）
    ("dodge/holy_impact.png", 32, 32, "gold", holy_impact, 26),
    ("dodge/holy_chest.png", 48, 48, "gold", holy_chest, 60),
    # 魔導士の追尾弾（projectile.gd）
    ("imported/pixel_magic_effects_animations.png", 20, 20, "arcane", vortex, 41),
    # 属性命中（effect_theme_manager.gd。表示36〜54）
    ("pixel/hit_fire.png", 24, 24, "fire", hit_fire, 44),
    ("pixel/hit_ice.png", 24, 24, "ice", hit_ice, 44),
    ("pixel/hit_lightning.png", 24, 24, "lightning", hit_lightning, 44),
    ("pixel/hit_light.png", 24, 24, "gold", hit_light, 44),
    ("pixel/hit_dark.png", 24, 24, "void", hit_dark, 44),
    # 概念スキル（表示〜160）
    ("pixel/concept_thunder_strike.png", 80, 80, "lightning", concept_thunder, 160),
    ("pixel/concept_fire_burst.png", 80, 80, "fire", concept_fire, 160),
    ("pixel/concept_ice_nova.png", 80, 80, "ice", concept_ice, 160),
    ("pixel/concept_light_burst.png", 80, 80, "gold", concept_light, 160),
    ("pixel/concept_wind_blade.png", 80, 80, "wind", concept_wind, 160),
    ("pixel/concept_dark_rift.png", 80, 80, "void", concept_dark, 160),
    ("concepts/wind_blade_6f_v2.png", 48, 48, "wind", concept_wind, 96),
    # 秘技（表示〜192）
    ("pixel/signature_thunderlord_descent.png", 96, 96, "lightning", sig_thunderlord, 192),
    ("pixel/signature_inferno_pillar.png", 96, 96, "fire", sig_inferno, 192),
    ("pixel/signature_glacial_spear_rain.png", 96, 96, "ice", sig_glacial, 192),
    ("pixel/signature_radiant_blade_array.png", 96, 96, "gold", sig_radiant, 192),
    ("pixel/signature_void_severance.png", 96, 96, "void", sig_void, 192),
    # 戦技（表示〜176）
    ("pixel/active_aura.png", 88, 88, "spirit", active_aura, 176),
    ("pixel/active_burst.png", 88, 88, "white", active_burst, 176),
    ("pixel/active_chains.png", 88, 88, "danger", active_chains, 176),
    ("pixel/active_charge.png", 88, 88, "fire", active_charge, 176),
    ("pixel/active_execution.png", 88, 88, "void", active_execution, 176),
    ("pixel/active_holy_burst.png", 88, 88, "gold", active_holy_burst, 176),
    ("pixel/active_impact.png", 88, 88, "fire", active_impact, 176),
    ("pixel/active_rain.png", 88, 88, "ice", active_rain, 176),
    ("pixel/active_sanctuary.png", 88, 88, "gold", active_sanctuary, 176),
    ("pixel/active_shield.png", 88, 88, "shield", active_shield, 176),
    ("pixel/active_summon.png", 88, 88, "spirit", active_summon, 176),
    ("pixel/active_time.png", 88, 88, "time", active_time, 176),
    # 線（幅は長さへ伸縮、高さ12表示）
    ("pixel/chain.png", 48, 12, "lightning", chain_line, (120, 12)),
    ("pixel/beam.png", 48, 12, "gold", beam_line, (120, 12)),
    # その他
    ("pixel/mass_kill.png", 72, 72, "gold", mass_kill, 144),
    ("pixel/forge_awaken.png", 64, 64, "forge", forge_awaken, 128),
    ("pixel/loot_awaken.png", 32, 32, "gold", loot_awaken, 64),
    ("pixel/poison.png", 64, 64, "poison", poison_loop, 140),
]

# ループ素材は消えずに回るので後半の減光をしない
NO_FADE = {"pixel/poison.png", "equipment_comfy/magic_6f.png", "imported/pixel_magic_effects_animations.png"}

STATIC = [
    ("pixel/loot_seal.png", 32, 32, "stone", loot_seal, (52, 26)),
    ("pixel/projectile_core.png", 12, 12, "white", projectile_core, 12),
    ("pixel/warning_ring.png", 128, 128, "white", warning_ring, 200),
]


def build_animated(entry):
    path, w, h, ramp, fn, _ = entry
    rng = np.random.default_rng(zlib.crc32(path.encode()))
    frames = []
    for t in range(FRAMES):
        f = Frame(w, h)
        fn(f, t, rng)
        cap = 5 if path in NO_FADE else CAP[t]
        frames.append(f.finish(cap=cap).render(ramp))
    return sheet(frames)


def build_static(entry):
    path, w, h, ramp, fn, _ = entry
    f = Frame(w, h)
    fn(f)
    return f.finish(cap=5).render(ramp)
