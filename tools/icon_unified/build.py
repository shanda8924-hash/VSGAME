"""装備アイコン200点を、原画（assets/items/painted_200/sheet_*.png）から同じ手順でドット化する。

  python3 tools/icon_unified/build.py                 # 200点とタブ用6点を上書きし、metrics も更新
  python3 tools/icon_unified/build.py --board DIR     # 旧(HEAD)と新の比較ボードも書く
  python3 tools/icon_unified/build.py --dry --board DIR

手順（全点共通）
1. templates.json の art_sheet / art_region で原画を切り出し、不透明部の外接矩形で詰める。
2. 長辺が SUBJECT px になるよう面積平均で縮小（半透明は事前乗算してから）。
3. 明暗差を少し強め、アイコンごとに COLORS 色へ減色（ディザなし）。アルファは二値化。
4. 外周に 1px の共通の明るい縁（OUTLINE）。48×48 の中央に置く。
"""
from __future__ import annotations

import io
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance

ROOT = Path(__file__).resolve().parents[2]
SHEETS = ROOT / "assets" / "items" / "painted_200"
OUT = ROOT / "assets" / "ui" / "equipment_readable_v4"
METRICS = ROOT / "resources" / "equipment_icon_metrics.gd"
RES_PREFIX = "res://assets/ui/equipment_readable_v4/"

SIZE = 48
SUBJECT = 44  # 本体の長辺
COLORS = 14  # アイコンごとの色数
OUTLINE = (236, 232, 222, 255)  # 旧アイコンと同じ明るい縁。暗い床でも輪郭が立つ
ALPHA_CUT = 110

_sheet_cache: dict[int, Image.Image] = {}


def sheet(index: int) -> Image.Image:
    if index not in _sheet_cache:
        _sheet_cache[index] = Image.open(SHEETS / f"sheet_{index}.png").convert("RGBA")
    return _sheet_cache[index]


def load_templates() -> list[dict]:
    return json.loads((ROOT / "data" / "equipment" / "templates.json").read_text(encoding="utf-8"))


# 所持品画面のスロット絞り込みタブ用。同じ原画から 64px（本体 54px）で作る。
TAB_ICONS = {
    "assets/items/weapons/weapon_sword_uncommon_001.png": "wanderer_iron_sword",
    "assets/items/head/head_cap_uncommon_001.png": "leather_scout_cap",
    "assets/items/body/body_coat_uncommon_001.png": "traveler_leather_coat",
    "assets/items/arms/arms_gloves_uncommon_001.png": "scout_gloves",
    "assets/items/legs/legs_boots_rare_001.png": "windrunner_boots",
    "assets/items/accessories/accessory_ring_epic_001.png": "amethyst_ring",
}


def pixelize(item: dict, size: int = SIZE, subject: int = SUBJECT) -> Image.Image:
    x, y, w, h = item["art_region"]
    src = sheet(item["art_sheet"]).crop((x, y, x + w, y + h))
    a = np.asarray(src)[:, :, 3]
    ys, xs = np.where(a > 40)
    src = src.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    # 事前乗算して縮小（縁の暗い滲みを防ぐ）
    arr = np.asarray(src).astype(np.float32)
    alpha = arr[:, :, 3:4] / 255.0
    pre = np.concatenate([arr[:, :, :3] * alpha, arr[:, :, 3:4]], axis=2)
    scale = subject / max(src.width, src.height)
    tw, th = max(1, round(src.width * scale)), max(1, round(src.height * scale))
    small = Image.fromarray(pre.astype(np.uint8), "RGBA").resize((tw, th), Image.BOX)
    sarr = np.asarray(small).astype(np.float32)
    sa = sarr[:, :, 3:4]
    rgb = np.where(sa > 0, sarr[:, :, :3] / np.maximum(sa / 255.0, 1e-3), 0)
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    mask = _despeckle(sarr[:, :, 3] >= ALPHA_CUT)
    color = Image.fromarray(rgb, "RGB")
    # 原画は全体に暗いので、旧アイコンと同じ明るさ・鮮やかさまで持ち上げる
    color = ImageEnhance.Brightness(color).enhance(1.22)
    color = ImageEnhance.Contrast(color).enhance(1.30)
    color = ImageEnhance.Color(color).enhance(1.35)
    # 不透明画素だけで減色パレットを作り、全画素を最近傍の色へ
    pix = np.asarray(color)
    opaque = pix[mask]
    strip = Image.fromarray(opaque.reshape(-1, 1, 3), "RGB")
    pal_img = strip.quantize(colors=min(COLORS, len(opaque)), method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = np.array(pal_img.getpalette()[: 3 * len(pal_img.getcolors())], np.int32).reshape(-1, 3)
    d = ((pix.reshape(-1, 1, 3).astype(np.int32) - pal[None, :, :]) ** 2).sum(axis=2)
    quant = pal[d.argmin(axis=1)].reshape(pix.shape).astype(np.uint8)
    # 48 の中央へ置き、外周アウトライン
    canvas = np.zeros((size, size, 4), np.uint8)
    ox, oy = (size - tw) // 2, (size - th) // 2
    full_mask = np.zeros((size, size), bool)
    full_mask[oy : oy + th, ox : ox + tw] = mask
    canvas[oy : oy + th, ox : ox + tw, :3] = quant
    canvas[full_mask, 3] = 255
    ring = _dilate(full_mask) & ~full_mask
    canvas[ring] = OUTLINE
    return Image.fromarray(canvas, "RGBA")


def _despeckle(mask: np.ndarray, min_pixels: int = 6) -> np.ndarray:
    """本体から離れた小さな飛び（半透明の縁の残り）を消す。4近傍の連結成分で判定。"""
    h, w = mask.shape
    seen = np.zeros_like(mask)
    keep = np.zeros_like(mask)
    for sy in range(h):
        for sx in range(w):
            if not mask[sy, sx] or seen[sy, sx]:
                continue
            stack = [(sy, sx)]
            seen[sy, sx] = True
            comp = []
            while stack:
                y, x = stack.pop()
                comp.append((y, x))
                for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            if len(comp) >= min_pixels:
                for y, x in comp:
                    keep[y, x] = True
    return keep


def _dilate(m: np.ndarray) -> np.ndarray:
    d = m.copy()
    d[1:, :] |= m[:-1, :]
    d[:-1, :] |= m[1:, :]
    d[:, 1:] |= m[:, :-1]
    d[:, :-1] |= m[:, 1:]
    return d


def old_image(item_id: str) -> Image.Image | None:
    try:
        data = subprocess.run(["git", "-C", str(ROOT), "show", f"HEAD:assets/ui/equipment_readable_v4/{item_id}.png"], capture_output=True, check=True).stdout
        return Image.open(io.BytesIO(data)).convert("RGBA")
    except Exception:
        return None


def board(out_dir: Path, results: list[tuple[dict, Image.Image]]):
    """系統ごとに、旧（上）と新（下）を 2 倍で並べる。"""
    out_dir.mkdir(parents=True, exist_ok=True)
    groups: dict[str, list] = {}
    for item, img in results:
        groups.setdefault(item.get("collection", "?"), []).append((item, img))
    scale = 2
    cell = SIZE * scale + 6
    names = {"継承装備": "heritage", "王国軍": "royal_guard", "紫晶鉱山": "amethyst_mine", "終焉の炉心": "ruin_forge", "辺境の狩人": "wild_hunt", "封印修道院": "sealed_abbey", "深淵の監視者": "abyss_watch", "失われた王家": "fallen_dynasty"}
    for name, items in groups.items():
        cols = 13
        rows = (len(items) + cols - 1) // cols
        b = Image.new("RGBA", (cols * cell + 8, rows * (cell * 2 + 24) + 8), (40, 38, 46, 255))
        d = ImageDraw.Draw(b)
        for k, (item, new) in enumerate(items):
            x = 4 + (k % cols) * cell
            y = 4 + (k // cols) * (cell * 2 + 24)
            d.text((x, y), f"{item['id']} {item['rarity'][:2]}", fill=(230, 220, 200, 255))
            old = old_image(item["id"])
            if old is not None:
                b.alpha_composite(old.resize((SIZE * scale, SIZE * scale), Image.NEAREST), (x, y + 12))
            b.alpha_composite(new.resize((SIZE * scale, SIZE * scale), Image.NEAREST), (x, y + 12 + cell))
        b.save(out_dir / f"icons_{names.get(name, 'other')}.png")
    cols = 25
    rows = (len(results) + cols - 1) // cols
    b = Image.new("RGBA", (cols * (SIZE + 2), rows * (SIZE + 2)), (40, 38, 46, 255))
    for k, (_, img) in enumerate(results):
        b.alpha_composite(img, ((k % cols) * (SIZE + 2), (k // cols) * (SIZE + 2)))
    b.save(out_dir / "icons_all_1x.png")


def write_metrics(results: list[tuple[dict, Image.Image]], tabs: list[tuple[str, Image.Image]]):
    lines = METRICS.read_text(encoding="utf-8").splitlines()
    tab_paths = {f"res://{rel}" for rel, _ in tabs}
    kept = [ln for ln in lines if RES_PREFIX not in ln and not any(path in ln for path in tab_paths)]
    end = max(i for i, ln in enumerate(kept) if ln.strip() == "}")
    new_lines = []
    for res_path, img in [(f"res://{rel}", img) for rel, img in tabs] + [(f"{RES_PREFIX}{item['id']}.png", img) for item, img in results]:
        bbox = img.getbbox()
        if bbox is None:
            continue
        x0, y0, x1, y1 = bbox
        new_lines.append(f'\t"{res_path}": Rect2i({x0}, {y0}, {x1 - x0}, {y1 - y0}),')
    METRICS.write_text("\n".join(kept[:end] + new_lines + kept[end:]) + "\n", encoding="utf-8")


def main():
    board_dir = Path(sys.argv[sys.argv.index("--board") + 1]) if "--board" in sys.argv else None
    templates = load_templates()
    by_id = {item["id"]: item for item in templates}
    results = [(item, pixelize(item)) for item in templates]
    tabs = [(rel, pixelize(by_id[item_id], size=64, subject=54)) for rel, item_id in TAB_ICONS.items()]
    if board_dir:
        board(board_dir, results)
        strip = Image.new("RGBA", (len(tabs) * 136, 136), (40, 38, 46, 255))
        for k, (_, img) in enumerate(tabs):
            strip.alpha_composite(img.resize((128, 128), Image.NEAREST), (k * 136 + 4, 4))
        strip.save(board_dir / "tab_icons_2x.png")
    if "--dry" not in sys.argv:
        OUT.mkdir(parents=True, exist_ok=True)
        for item, img in results:
            img.save(OUT / f"{item['id']}.png")
        for rel, img in tabs:
            img.save(ROOT / rel)
        write_metrics(results, tabs)
        print(f"wrote {len(results)} icons and {len(tabs)} tab icons")


if __name__ == "__main__":
    main()
