"""Build Godot-ready Fusion pixel VFX sprite sheets from ImageGen source sheets.

Each transparent source contains five isolated designs from left to right:
Attack, Trail, Hit, Burst, Intro.  The generated key art is reduced with
nearest-neighbour sampling and expanded into a six-frame 64 px animation.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "artifacts" / "fusion_vfx_pixel_sources"
OUTPUT_DIR = ROOT / "assets" / "vfx" / "fusions"
FRAME_SIZE = 64
FRAME_COUNT = 6

FUSIONS = (
    "frostfire",
    "plasma",
    "solar",
    "inferno",
    "superconductor",
    "aurora",
    "void_frost",
    "judgment",
    "voidstorm",
    "eclipse",
)
MODES = ("attack", "trail", "hit", "burst", "intro")
DISPLAY_NAMES = {
    "frostfire": "THERMAL_SHOCK",
    "plasma": "PLASMA",
    "solar": "SOLAR_FLARE",
    "inferno": "INFERNO",
    "superconductor": "SUPERCONDUCTOR",
    "aurora": "AURORA",
    "void_frost": "BLACK_ICE",
    "judgment": "RADIANT_ARC",
    "voidstorm": "VOIDSTORM",
    "eclipse": "ECLIPSE",
}

# All new attribute sheets use the same phenomenon lifecycle.  Pixels are
# revealed from the centre, stay strongly coloured at peak, then disappear by
# losing their outer shape and throwing a few fragments.  Whole-frame opacity
# animation is intentionally forbidden: it reads as a translucent illustration
# being tweened instead of energy forming and breaking apart in the world.
LIFECYCLE_EXTENTS = (0.24, 0.56, 0.84, 1.0, 0.66, 0.28)
HORIZONTAL_MODES = {"attack", "trail"}
TARGET_BOX = {
    "attack": (54, 54),
    "trail": (58, 48),
    "hit": (56, 56),
    "burst": (60, 60),
    "intro": (60, 60),
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _trim_cell(cell: Image.Image) -> Image.Image:
    alpha = cell.getchannel("A").point(lambda value: 255 if value >= 24 else 0)
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError("generated cell has no opaque pixels")
    trimmed = cell.crop(bbox)
    pixels = list(trimmed.get_flattened_data())
    # Chroma removal intentionally keeps a soft fringe.  At 64 px that fringe
    # becomes muddy, so only the near-transparent tail is snapped to zero.
    cleaned = [
        (red, green, blue, 0 if alpha_value < 20 else alpha_value)
        for red, green, blue, alpha_value in pixels
    ]
    trimmed.putdata(cleaned)
    return trimmed


def _fit_key_art(image: Image.Image, mode: str, fusion_id: str) -> Image.Image:
    # Runtime rotates Trail sprites to the combat segment angle.  ImageGen can
    # occasionally compose a thin trail vertically, so normalize the source to
    # a right-facing strip before the Godot-side rotation is applied.
    if mode == "trail" and (image.height > image.width * 1.15 or fusion_id == "frostfire"):
        image = image.rotate(-90, expand=True)
    max_width, max_height = TARGET_BOX[mode]
    ratio = min(max_width / image.width, max_height / image.height)
    size = (max(1, round(image.width * ratio)), max(1, round(image.height * ratio)))
    resized = image.resize(size, Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE))
    canvas.alpha_composite(resized, ((FRAME_SIZE - size[0]) // 2, (FRAME_SIZE - size[1]) // 2))
    return canvas


def _geometry_metric(x: int, y: int, bbox: tuple[int, int, int, int], horizontal: bool) -> float:
    left, top, right, bottom = bbox
    centre_x = (left + right - 1) * 0.5
    centre_y = (top + bottom - 1) * 0.5
    half_width = max((right - left) * 0.5, 1.0)
    half_height = max((bottom - top) * 0.5, 1.0)
    nx = abs(x - centre_x) / half_width
    if horizontal:
        return nx
    ny = abs(y - centre_y) / half_height
    return (nx * nx + ny * ny) ** 0.5


def _animation_frame(key_art: Image.Image, mode: str, frame_index: int) -> Image.Image:
    """Reveal/erode geometry while preserving the source colour and opacity."""
    bbox = key_art.getchannel("A").getbbox()
    if bbox is None:
        return Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE))
    extent = LIFECYCLE_EXTENTS[frame_index]
    horizontal = mode in HORIZONTAL_MODES
    collapse = frame_index >= 4
    fragment_shift = 2 if frame_index == 4 else 4
    source = key_art.load()
    frame = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE))
    output = frame.load()

    for y in range(FRAME_SIZE):
        for x in range(FRAME_SIZE):
            red, green, blue, alpha = source[x, y]
            if alpha < 24:
                continue
            metric = _geometry_metric(x, y, bbox, horizontal)
            if metric <= extent:
                # Pixel art must read as fully emitted energy from frame one.
                # Preserve brighter antialiasing, but never make the whole body
                # faint merely because it is young or old.
                strong_alpha = max(alpha, 210)
                if collapse and metric > max(0.0, extent - 0.15):
                    # Irregular holes make the outer edge crumble instead of
                    # producing a perfectly clean scale-down silhouette.
                    if (x * 17 + y * 31 + frame_index * 13) % 5 == 0:
                        continue
                output[x, y] = (red, green, blue, strong_alpha)
                continue
            if not collapse:
                continue
            # A sparse sample of removed edge pixels becomes short-lived debris.
            # This is spatial breakup, not a global alpha fade.
            if metric <= extent + 0.38 and (x * 13 + y * 7 + frame_index * 11) % 19 == 0:
                left, top, right, bottom = bbox
                centre_x = (left + right - 1) * 0.5
                centre_y = (top + bottom - 1) * 0.5
                dx = -1 if x < centre_x else 1
                dy = -1 if y < centre_y else 1
                if horizontal:
                    dy = ((x + y) % 3) - 1
                px = max(0, min(FRAME_SIZE - 1, x + dx * fragment_shift))
                py = max(0, min(FRAME_SIZE - 1, y + dy * max(1, fragment_shift // 2)))
                output[px, py] = (red, green, blue, max(alpha, 205))
    return frame


def _make_sprite_sheet(key_art: Image.Image, mode: str) -> Image.Image:
    sheet = Image.new("RGBA", (FRAME_SIZE * FRAME_COUNT, FRAME_SIZE))
    for index in range(FRAME_COUNT):
        frame = _animation_frame(key_art, mode, index)
        sheet.alpha_composite(frame, (index * FRAME_SIZE, 0))
    return sheet


def _catalog_background(width: int, height: int) -> Image.Image:
    image = Image.new("RGBA", (width, height), (17, 20, 30, 255))
    draw = ImageDraw.Draw(image)
    tile = 8
    colors = ((30, 34, 48, 255), (42, 47, 62, 255))
    for y in range(0, height, tile):
        for x in range(0, width, tile):
            draw.rectangle((x, y, x + tile - 1, y + tile - 1), fill=colors[(x // tile + y // tile) % 2])
    return image


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    catalog_cell = (112, 92)
    catalog = _catalog_background(catalog_cell[0] * len(MODES), catalog_cell[1] * len(FUSIONS) + 26)
    draw = ImageDraw.Draw(catalog)
    font = ImageFont.load_default()
    manifest: dict[str, object] = {
        "generator": "built-in image_gen + chroma-key removal + tools/build_fusion_pixel_vfx.py",
        "frame_size": [FRAME_SIZE, FRAME_SIZE],
        "frames": FRAME_COUNT,
        "fusions": {},
    }

    for column, mode in enumerate(MODES):
        draw.text((column * catalog_cell[0] + 8, 8), mode.upper(), fill=(235, 238, 248, 255), font=font)

    for row, fusion_id in enumerate(FUSIONS):
        source_path = SOURCE_DIR / f"{fusion_id}_transparent.png"
        source = Image.open(source_path).convert("RGBA")
        outputs: dict[str, object] = {}
        for index, mode in enumerate(MODES):
            x0 = source.width * index // len(MODES)
            x1 = source.width * (index + 1) // len(MODES)
            key_art = _fit_key_art(_trim_cell(source.crop((x0, 0, x1, source.height))), mode, fusion_id)
            sheet = _make_sprite_sheet(key_art, mode)
            fusion_dir = OUTPUT_DIR / fusion_id
            fusion_dir.mkdir(parents=True, exist_ok=True)
            output_path = fusion_dir / f"fx_fusion_{fusion_id}_{mode}_6f.png"
            sheet.save(output_path, optimize=True)
            outputs[mode] = {
                "path": output_path.relative_to(ROOT).as_posix(),
                "sha256": _sha256(output_path),
                "opaque_pixels": sum(1 for value in sheet.getchannel("A").get_flattened_data() if value > 0),
            }

            preview = sheet.crop((FRAME_SIZE * 3, 0, FRAME_SIZE * 4, FRAME_SIZE))
            px = index * catalog_cell[0] + (catalog_cell[0] - FRAME_SIZE) // 2
            py = 26 + row * catalog_cell[1] + 4
            catalog.alpha_composite(preview, (px, py))
            if index == 0:
                draw.text((4, py + FRAME_SIZE + 2), DISPLAY_NAMES[fusion_id], fill=(194, 208, 235, 255), font=font)

        manifest["fusions"][fusion_id] = {
            "source": source_path.relative_to(ROOT).as_posix(),
            "source_sha256": _sha256(source_path),
            "outputs": outputs,
        }

    catalog_path = SOURCE_DIR / "fusion_pixel_asset_catalog.png"
    catalog.save(catalog_path, optimize=True)
    manifest["catalog"] = catalog_path.relative_to(ROOT).as_posix()
    manifest_path = SOURCE_DIR / "fusion_pixel_asset_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Built {len(FUSIONS) * len(MODES)} Fusion VFX sprite sheets")
    print(f"Manifest: {manifest_path}")
    print(f"Catalog:  {catalog_path}")


if __name__ == "__main__":
    main()
