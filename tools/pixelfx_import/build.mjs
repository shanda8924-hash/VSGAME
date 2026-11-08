#!/usr/bin/env node
// pixelfx（https://github.com/patch-gg/pixelfx、MIT）の効果を、data/vfx/pixelfx_effects.json の
// 対応表どおりにGodot用シートへ書き出す。ゲームのキー（hit_fire など）ごとに1枚。
//
//   node tools/pixelfx_import/build.mjs --pixelfx ../patch-gg/pixelfx          全部
//   node tools/pixelfx_import/build.mjs --pixelfx ../patch-gg/pixelfx hit_fire 1つだけ
//   node tools/pixelfx_import/build.mjs --pixelfx ../patch-gg/pixelfx --board DIR   確認用の一覧画像も
//
// 書き出し：assets/vfx/pixelfx/<key>.png（コマを格子に並べた透過PNG）と <key>.json
//   { key, fx, fps, loop, count, columns, frame_size:[w,h], pivot:[x,y], scale, fit, speed, z, tail_fade }
// コマは全コマの不透明範囲の和で切り詰める（空白を持たない）。pivot は切り詰め後の座標。

import { readFileSync, writeFileSync, mkdirSync, existsSync, copyFileSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const GAME = resolve(HERE, "..", "..");
const args = process.argv.slice(2), flags = {}, keys = [];
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a.startsWith("--")) flags[a.slice(2)] = args[++i];
  else keys.push(a);
}
const PFX = resolve(flags.pixelfx ?? process.env.PIXELFX_DIR ?? join(GAME, "..", "patch-gg", "pixelfx"));
if (!existsSync(join(PFX, "src", "core", "index.js"))) {
  console.error(`pixelfx not found at ${PFX}. Clone https://github.com/patch-gg/pixelfx and pass --pixelfx DIR`);
  process.exit(1);
}
const lib = await import(pathToFileURL(join(PFX, "tools", "lib", "fxlib.mjs")).href);
const { encodePNG } = await import(pathToFileURL(join(PFX, "tools", "lib", "png.mjs")).href);

const manifest = JSON.parse(readFileSync(join(GAME, "data", "vfx", "pixelfx_effects.json"), "utf8"));
const palettes = manifest.palettes ?? {};
const defaults = manifest.defaults ?? {};
const OUT = join(GAME, "assets", "vfx", "pixelfx");
mkdirSync(OUT, { recursive: true });
copyFileSync(join(PFX, "LICENSE"), join(OUT, "LICENSE_pixelfx.txt"));
copyFileSync(join(PFX, "NOTICE.md"), join(OUT, "NOTICE_pixelfx.md"));

const MAX_SHEET_WIDTH = 2048;
const wanted = keys.length ? keys : Object.keys(manifest.effects);
const report = [];
let failed = 0;
for (const key of wanted) {
  const entry = { ...defaults, ...manifest.effects[key] };
  if (!manifest.effects[key]) { console.error(`${key}: not in manifest`); failed++; continue; }
  try {
    const fx = await lib.loadEffect(entry.fx, join(PFX, "src", "fx"));
    const options = { ...(entry.options ?? {}) };
    if (entry.palette) options.palette = Array.isArray(entry.palette) ? entry.palette : palettes[entry.palette];
    if (entry.flip) options.flip = true;
    const r = lib.renderFrames(fx, { fps: entry.fps, seed: entry.seed, bg: "none", actor: false, options });
    let frames = r.frames;
    // 長い一発物は max_seconds で打ち切る（減衰の尻尾は実行時に tail_fade で消す）
    if (!fx.meta.loop && entry.max_seconds) frames = frames.slice(0, Math.max(1, Math.round(entry.max_seconds * r.fps) + 1));
    // 全コマの不透明範囲の和
    let x0 = r.w, y0 = r.h, x1 = -1, y1 = -1;
    for (const f of frames) {
      const px = f.clear;
      for (let y = 0; y < r.h; y++) for (let x = 0; x < r.w; x++) {
        if (px[(y * r.w + x) * 4 + 3] > 6) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
      }
    }
    if (x1 < 0) throw new Error("empty effect");
    x0 = Math.max(0, x0 - 1); y0 = Math.max(0, y0 - 1); x1 = Math.min(r.w - 1, x1 + 1); y1 = Math.min(r.h - 1, y1 + 1);
    const w = x1 - x0 + 1, h = y1 - y0 + 1, n = frames.length;
    const columns = Math.max(1, Math.min(n, Math.floor(MAX_SHEET_WIDTH / w)));
    const rows = Math.ceil(n / columns);
    const sheet = new Uint8ClampedArray(columns * w * rows * h * 4);
    frames.forEach((f, i) => {
      const ox = (i % columns) * w, oy = Math.floor(i / columns) * h;
      for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const s = ((y + y0) * r.w + (x + x0)) * 4, d = ((oy + y) * columns * w + (ox + x)) * 4;
        sheet[d] = f.clear[s]; sheet[d + 1] = f.clear[s + 1]; sheet[d + 2] = f.clear[s + 2]; sheet[d + 3] = f.clear[s + 3];
      }
    });
    const [OX, OY] = fx.meta.origin;
    const meta = {
      key, fx: entry.fx, name: fx.meta.name, fps: r.fps, loop: !!fx.meta.loop, count: n, columns,
      frame_size: [w, h], pivot: [OX - x0, OY - y0], scale: entry.scale ?? 2, fit: entry.fit ?? "fixed",
      speed: entry.speed ?? 1, z: entry.z ?? 45, tail_fade: entry.tail_fade ?? 0, flip: !!entry.flip,
      palette: entry.palette ?? null, source: "pixelfx (MIT) https://github.com/patch-gg/pixelfx",
    };
    writeFileSync(join(OUT, `${key}.png`), encodePNG(columns * w, rows * h, sheet));
    writeFileSync(join(OUT, `${key}.json`), JSON.stringify(meta, null, 1));
    const bytes = columns * w * rows * h * 4;
    report.push({ key, fx: entry.fx, n, w, h, mb: +(bytes / 1048576).toFixed(2) });
    console.log(`${key.padEnd(30)} ${entry.fx.padEnd(28)} ${n} frames  ${w}x${h}  ${(bytes / 1048576).toFixed(2)} MB`);
    if (flags.board) {
      const strip = Math.min(n, 8), pick = Array.from({ length: strip }, (_, i) => Math.floor((i * (n - 1)) / Math.max(1, strip - 1)));
      const bw = strip * w, bh = h, board = new Uint8ClampedArray(bw * bh * 4);
      for (let p = 0; p < bw * bh; p++) { board[p * 4] = 20; board[p * 4 + 1] = 22; board[p * 4 + 2] = 30; board[p * 4 + 3] = 255; }
      pick.forEach((fi, i) => {
        const f = frames[fi];
        for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
          const s = ((y + y0) * r.w + (x + x0)) * 4, d = (y * bw + i * w + x) * 4, a = f.clear[s + 3] / 255;
          board[d] = board[d] * (1 - a) + f.clear[s] * a; board[d + 1] = board[d + 1] * (1 - a) + f.clear[s + 1] * a; board[d + 2] = board[d + 2] * (1 - a) + f.clear[s + 2] * a;
        }
      });
      mkdirSync(flags.board, { recursive: true });
      writeFileSync(join(flags.board, `${key}.png`), encodePNG(bw, bh, board));
    }
  } catch (e) {
    failed++;
    console.error(`${key}  FAILED: ${e.stack ?? e}`);
  }
}
const total = report.reduce((s, r) => s + r.mb, 0);
console.log(`\n${report.length} sheets, ${total.toFixed(1)} MB uncompressed`);
if (!keys.length) writeFileSync(join(OUT, "_index.json"), JSON.stringify(report, null, 1));
process.exit(failed ? 1 : 0);
