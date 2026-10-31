"""Mechanical preparation of imagegen artwork (no procedural replacement art).

The original atlas and prompt are retained beside the manifest. The user approved
cropping, nearest-neighbour reduction and alpha cleanup for Godot sprite import.
Run: python tools/import_generated_pixel_vfx.py --manifest assets/vfx/pixel/source_manifest.json
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/vfx/pixel"


def cell(image: Image.Image, column: int, row: int, columns: int, rows: int) -> Image.Image:
    return image.crop((round(image.width * column / columns), round(image.height * row / rows),
                       round(image.width * (column + 1) / columns), round(image.height * (row + 1) / rows)))


def hard_alpha(image: Image.Image, threshold: int = 160) -> Image.Image:
    result = image.convert("RGBA")
    result.putalpha(result.getchannel("A").point(lambda a: 255 if a >= threshold else 0))
    # Transparent RGB is cleared, preventing coloured fringes on import.
    clean = Image.new("RGBA", result.size)
    clean.paste(result, (0, 0), result.getchannel("A"))
    return clean


def animation_rows(path: Path, names: list[str], threshold: int = 160, row_bounds: list | None = None) -> list[dict]:
    source = Image.open(path).convert("RGBA")
    if source.getchannel("A").getextrema()[0] == 255:
        raise ValueError(f"Atlas has no transparency: {path}")
    results = []
    for row, name in enumerate(names):
        band = source
        if row_bounds:
            band = source.crop((0, row_bounds[row][0], source.width, row_bounds[row][1]))
        frames = [hard_alpha(cell(band, col, 0 if row_bounds else row, 6, 1 if row_bounds else len(names)), threshold) for col in range(6)]
        # One common crop for the WHOLE sequence: do not scale each animation
        # frame to its own bounding box, which would destroy growth/collapse.
        boxes = [frame.getbbox() for frame in frames]
        if any(box is None for box in boxes):
            raise ValueError(f"Empty animation frame in {name}: {boxes}")
        left = min(box[0] for box in boxes)
        top = min(box[1] for box in boxes)
        right = max(box[2] for box in boxes)
        bottom = max(box[3] for box in boxes)
        center_x, center_y = (left + right) / 2, (top + bottom) / 2
        extent = max(right - left, bottom - top) / 0.90
        crop = (round(center_x - extent / 2), round(center_y - extent / 2),
                round(center_x + extent / 2), round(center_y + extent / 2))
        strip = Image.new("RGBA", (384, 64))
        counts = []
        for index, frame in enumerate(frames):
            small = frame.crop(crop).resize((64, 64), Image.Resampling.NEAREST)
            strip.paste(small, (index * 64, 0))
            counts.append(small.getchannel("A").histogram()[255])
        if min(counts) == 0:
            raise ValueError(f"Lost fragments during nearest reduction: {name}")
        strip.save(OUT / f"{name}.png")
        results.append({"id": name, "file": f"assets/vfx/pixel/{name}.png", "frames": 6,
                        "opaque_pixels": counts, "source": str(path.relative_to(ROOT)).replace("\\", "/")})
    return results


def single_animation(path: Path, name: str, threshold: int = 160) -> list[dict]:
    """A single effect has six cells, read across three columns then two rows."""
    source = Image.open(path).convert("RGBA")
    if source.getchannel("A").getextrema()[0] == 255:
        raise ValueError(f"Atlas has no transparency: {path}")
    frames = [hard_alpha(cell(source, i % 3, i // 3, 3, 2), threshold) for i in range(6)]
    # Atlas cells are square, but imperfect model framing can vary a few pixels.
    # Keep the original cell centre: it anchors lightning roots and slash centres.
    half = max(max(frame.size) for frame in frames) / 2
    sheet = Image.new("RGBA", (384, 64))
    counts = []
    for index, frame in enumerate(frames):
        cx, cy = frame.width / 2, frame.height / 2
        frame = frame.crop((round(cx-half), round(cy-half), round(cx+half), round(cy+half)))
        small = frame.resize((64, 64), Image.Resampling.NEAREST)
        sheet.paste(small, (index * 64, 0))
        counts.append(small.getchannel("A").histogram()[255])
    if not all(counts):
        raise ValueError(f"Empty prepared animation frame: {name}")
    sheet.save(OUT / f"{name}.png")
    return [{"id": name, "file": f"assets/vfx/pixel/{name}.png", "frames": 6,
             "opaque_pixels": counts, "source": str(path.relative_to(ROOT)).replace("\\", "/")}]


def markers(path: Path) -> list[dict]:
    source = Image.open(path).convert("RGBA")
    results = []
    for index, (name, size, active) in enumerate([
        ("warning_ring", 64, 58), ("projectile_core", 24, 20),
        ("loot_seal", 64, 56),
    ]):
        image = hard_alpha(cell(source, index % 2, index // 2, 2, 2))
        bounds = image.getbbox()
        if bounds is None:
            raise ValueError(f"Missing marker: {name}")
        image = image.crop(bounds)
        ratio = active / max(image.size)
        image = image.resize((max(1, round(image.width * ratio)), max(1, round(image.height * ratio))), Image.Resampling.NEAREST)
        result = Image.new("RGBA", (size, size))
        result.paste(image, ((size - image.width) // 2, (size - image.height) // 2))
        result.save(OUT / f"{name}.png")
        results.append({"id": name, "file": f"assets/vfx/pixel/{name}.png", "frames": 1,
                        "bounds": result.getbbox(), "source": str(path.relative_to(ROOT)).replace("\\", "/")})
    return results


def wall_edges(path: Path) -> None:
    source = Image.open(path).convert("RGB")
    strip = Image.new("RGBA", (128, 16))
    for index in range(8):
        tile = cell(source, index % 4, index // 4, 4, 2)
        # The generator left a black sheet gutter. Trim the gutter, not the
        # designed mortar seams inside a tile. No drawing/rotation/recolouring.
        mask = tile.convert("L").point(lambda value: 255 if value > 5 else 0)
        bounds = mask.getbbox()
        if bounds is None:
            raise ValueError("Blank wall tile")
        small = tile.crop(bounds).resize((16, 16), Image.Resampling.NEAREST).convert("RGBA")
        strip.paste(small, (16 * index, 0))
    strip.save(ROOT / "assets/tiles/royal/wall_edges.png")


def preview(results: list[dict]) -> None:
    height = len(results) * 86
    contact = Image.new("RGB", (600, height), "#172131")
    painter = ImageDraw.Draw(contact)
    for index, entry in enumerate(results):
        image = Image.open(ROOT / entry["file"]).convert("RGBA")
        y = index * 86
        painter.text((8, y + 3), entry["id"], fill="#fff2ce")
        contact.paste(image, (196, y + 18), image)
    contact.save(ROOT / "artifacts/pixel_vfx_contact_sheet.png")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    result = []
    for atlas in manifest["atlases"]:
        path = ROOT / atlas["source"]
        kind = atlas.get("kind", "animation")
        if kind == "wall":
            wall_edges(path)
        elif kind == "markers":
            result.extend(markers(path))
        elif kind == "single":
            result.extend(single_animation(path, atlas["id"], atlas.get("alpha_threshold", 160)))
        else:
            result.extend(animation_rows(path, atlas["rows"], atlas.get("alpha_threshold", 160), atlas.get("row_bounds")))
    (OUT / "asset_inventory.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    preview(result)
    print(f"Prepared {len(result)} VFX PNGs; all animation frames nonempty, binary alpha, nearest pixels.")


if __name__ == "__main__":
    main()
