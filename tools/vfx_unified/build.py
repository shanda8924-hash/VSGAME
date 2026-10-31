"""全VFXシートを生成して assets/vfx/ へ上書きする。

  python3 tools/vfx_unified/build.py            # 生成して上書き
  python3 tools/vfx_unified/build.py --board DIR  # 旧(HEAD)と新の比較ボードも DIR へ書く
"""
from __future__ import annotations

import io
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
from effects import ANIMATED, STATIC, build_animated, build_static  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
VFX = ROOT / "assets" / "vfx"


def old_image(rel: str) -> Image.Image | None:
    try:
        data = subprocess.run(["git", "-C", str(ROOT), "show", f"HEAD:assets/vfx/{rel}"], capture_output=True, check=True).stdout
        return Image.open(io.BytesIO(data)).convert("RGBA")
    except Exception:
        return None


def frames_of(img: Image.Image, n: int = 6, fw: int | None = None, fh: int | None = None):
    fh = fh or img.height
    fw = fw or img.width // n
    return [img.crop((i * fw, 0, (i + 1) * fw, fh)) for i in range(min(n, img.width // max(fw, 1)))]


def board(out_dir: Path, results):
    """旧（上段）と新（下段）を、ゲーム内の表示サイズへ最近傍拡大して並べる。床色の上に置く。"""
    out_dir.mkdir(parents=True, exist_ok=True)
    groups = {}
    for rel, new, disp in results:
        groups.setdefault(rel.split("/")[0] + ("_sig" if "signature" in rel else "_act" if "active_" in rel else "_con" if "concept_" in rel else ""), []).append((rel, new, disp))
    for name, items in groups.items():
        rows = []
        for rel, new, disp in items:
            dw, dh = (disp, disp) if isinstance(disp, int) else disp
            old = old_image(rel)
            pair = []
            for label, img, is_new in (("old", old, False), ("new", new, True)):
                if img is None:
                    continue
                if rel.startswith("imported/") and not is_new:
                    fr = [img.crop((256, i * 64, 320, (i + 1) * 64)) for i in range(5)]
                elif rel == "dodge/holy_chest.png" and not is_new:
                    fr = frames_of(img, 16, 48, 48)[::3][:6]
                elif rel == "dodge/holy_impact.png" and not is_new:
                    fr = frames_of(img, 7, 32, 32)[:6]
                elif img.width == img.height or rel in ("pixel/loot_seal.png",):
                    fr = [img]
                else:
                    fr = frames_of(img)
                pair.append((label, [f.resize((dw, dh), Image.NEAREST) for f in fr]))
            rows.append((rel, pair, dw, dh))
        W = max(20 + 6 * (dw + 8) for _, _, dw, _ in rows) + 60
        H = sum(len(p) * (dh + 6) + 22 for _, p, _, dh in rows)
        b = Image.new("RGBA", (W, H), (38, 36, 44, 255))
        d = ImageDraw.Draw(b)
        # 床の目安（32pxタイル）
        for y in range(0, H, 32):
            for x in range(0, W, 32):
                if (x // 32 + y // 32) % 2:
                    d.rectangle([x, y, x + 31, y + 31], fill=(44, 42, 50, 255))
        y = 0
        for rel, pair, dw, dh in rows:
            d.text((4, y + 4), rel, fill=(255, 240, 200, 255))
            y += 18
            for label, frs in pair:
                d.text((4, y + dh // 2), label, fill=(200, 200, 210, 255))
                for i, fr in enumerate(frs):
                    b.alpha_composite(fr, (40 + i * (dw + 8), y))
                y += dh + 6
            y += 4
        b.save(out_dir / f"compare_{name}.png")


def main():
    board_dir = None
    if "--board" in sys.argv:
        board_dir = Path(sys.argv[sys.argv.index("--board") + 1])
    results = []
    for entry in ANIMATED:
        img = build_animated(entry)
        results.append((entry[0], img, entry[5]))
    for entry in STATIC:
        img = build_static(entry)
        results.append((entry[0], img, entry[5]))
    if board_dir:
        board(board_dir, results)
    if "--dry" not in sys.argv:
        for rel, img, _ in results:
            dst = VFX / rel
            img.save(dst)
        print(f"wrote {len(results)} sheets")


if __name__ == "__main__":
    main()
