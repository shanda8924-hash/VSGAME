"""Generate deterministic SFC-style pixel art for the VSGAME shop UI.

Every asset is drawn directly on its final-size canvas.  There is no resize,
filter, anti-aliasing, or font rendering step, so edges stay aligned to the
pixel grid.  Each image is validated after saving for dimensions,
transparency, and a maximum of eight visible RGBA colors.

Run without arguments to regenerate every PNG under ``assets/ui/shop``.
Use ``--only weapon_icon`` (or another asset stem) for an individual image.
The 48x48 shop frame is intended for a 9-slice control with 10px patch margins.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Callable

from PIL import Image, ImageDraw


RGBA = tuple[int, int, int, int]
TRANSPARENT: RGBA = (0, 0, 0, 0)

# Palette constants live together here so later color tuning does not require
# touching drawing coordinates.  Every per-asset palette stays at eight visible
# colors or fewer (transparent pixels are not counted as a visible color).
METAL_GOLD = {
    "outline": (24, 24, 38, 255),
    "metal_dark": (52, 72, 104, 255),
    "metal_mid": (116, 148, 181, 255),
    "metal_light": (210, 232, 238, 255),
    "metal_glint": (245, 252, 244, 255),
    "gold_dark": (128, 72, 22, 255),
    "gold_mid": (224, 157, 38, 255),
    "gold_light": (255, 224, 100, 255),
}

FIRE = {
    "outline": (55, 24, 42, 255),
    "red": (170, 42, 36, 255),
    "orange_dark": (228, 76, 30, 255),
    "orange": (255, 132, 30, 255),
    "yellow": (255, 205, 54, 255),
    "hot": (255, 244, 154, 255),
}

POTION = {
    "outline": (24, 26, 42, 255),
    "glass_dark": (55, 92, 112, 255),
    "glass_mid": (112, 165, 174, 255),
    "glass_light": (210, 240, 224, 255),
    "liquid_dark": (25, 104, 58, 255),
    "liquid_mid": (48, 182, 82, 255),
    "liquid_light": (134, 238, 105, 255),
    "cork": (172, 102, 42, 255),
}

FRAME = {
    "outline": (26, 20, 28, 255),
    "gold_deep": (103, 58, 22, 255),
    "gold_dark": (157, 91, 28, 255),
    "gold_mid": (224, 158, 48, 255),
    "gold_light": (255, 224, 112, 255),
    "steel": (83, 92, 112, 255),
    "navy": (10, 19, 38, 220),
}

CURSOR = {
    "outline": (71, 38, 18, 255),
    "gold": (232, 162, 42, 255),
    "highlight": (255, 232, 116, 255),
}

WOOD = {
    "outline": (39, 27, 35, 255),
    "deep": (80, 43, 29, 255),
    "dark": (121, 67, 35, 255),
    "mid": (173, 104, 48, 255),
    "light": (222, 156, 74, 255),
    "glint": (248, 198, 112, 255),
    "iron": (92, 99, 111, 255),
    "nail": (205, 211, 198, 255),
}

LANTERN = {
    "outline": (36, 25, 35, 255),
    "metal_dark": (71, 55, 61, 255),
    "metal_mid": (132, 106, 85, 255),
    "metal_light": (213, 172, 100, 255),
    "ember": (168, 49, 30, 255),
    "orange": (244, 105, 31, 255),
    "yellow": (255, 196, 55, 255),
    "hot": (255, 241, 149, 255),
}


OUTPUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "ui" / "shop"
FRAME_PATCH_MARGIN = 10


def canvas(size: tuple[int, int]) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGBA", size, TRANSPARENT)
    return image, ImageDraw.Draw(image)


def save(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG", optimize=True)


def generate_weapon_icon(path: Path) -> None:
    """16x16 diagonal sword, lit from the upper-left."""
    image, draw = canvas((16, 16))
    p = METAL_GOLD

    # Blade silhouette and stepped point.
    draw.polygon([(3, 10), (5, 12), (12, 5), (14, 1), (10, 2)], fill=p["outline"])
    draw.polygon([(5, 10), (6, 10), (12, 4), (13, 2), (11, 3), (4, 10)], fill=p["metal_mid"])
    draw.line([(5, 9), (11, 3)], fill=p["metal_light"], width=1)
    draw.point((12, 2), fill=p["metal_glint"])
    draw.line([(6, 11), (12, 5)], fill=p["metal_dark"], width=1)

    # Gold guard and pommel retain the same upper-left highlight language.
    draw.polygon([(2, 9), (3, 8), (8, 13), (7, 14)], fill=p["outline"])
    draw.line([(3, 9), (7, 13)], fill=p["gold_mid"], width=2)
    draw.point((3, 9), fill=p["gold_light"])
    draw.line([(3, 12), (1, 14)], fill=p["outline"], width=3)
    draw.line([(3, 12), (2, 13)], fill=p["gold_dark"], width=2)
    draw.rectangle((0, 13, 2, 15), fill=p["outline"])
    draw.point((1, 14), fill=p["gold_mid"])
    save(image, path)


def generate_upgrade_icon(path: Path) -> None:
    """16x16 metal shield with a compact gold heraldic mark."""
    image, draw = canvas((16, 16))
    p = METAL_GOLD

    draw.polygon([(3, 2), (12, 2), (14, 4), (13, 11), (8, 15), (3, 11), (2, 4)], fill=p["outline"])
    draw.polygon([(4, 3), (11, 3), (13, 5), (12, 10), (8, 13), (4, 10), (3, 5)], fill=p["metal_mid"])
    draw.line([(4, 4), (4, 9), (8, 12)], fill=p["metal_light"], width=1)
    draw.line([(5, 3), (10, 3)], fill=p["metal_glint"], width=1)
    draw.line([(12, 5), (11, 10), (8, 13)], fill=p["metal_dark"], width=1)

    draw.rectangle((7, 5, 9, 10), fill=p["gold_dark"])
    draw.rectangle((5, 7, 11, 9), fill=p["gold_dark"])
    draw.rectangle((7, 5, 8, 9), fill=p["gold_mid"])
    draw.rectangle((5, 7, 9, 8), fill=p["gold_mid"])
    draw.point((7, 6), fill=p["gold_light"])
    save(image, path)


def generate_status_icon(path: Path) -> None:
    """16x16 flame with a hot inner core and a strong readable silhouette."""
    image, draw = canvas((16, 16))
    p = FIRE

    outline = [(7, 1), (10, 4), (10, 7), (13, 5), (14, 9), (13, 13), (10, 15), (5, 15), (2, 12), (2, 8), (5, 5), (5, 2)]
    draw.polygon(outline, fill=p["outline"])
    draw.polygon([(7, 2), (9, 5), (8, 9), (11, 7), (13, 9), (12, 12), (9, 14), (5, 13), (3, 11), (4, 7), (6, 6)], fill=p["red"])
    draw.polygon([(7, 5), (9, 8), (8, 11), (11, 9), (12, 11), (10, 13), (6, 13), (4, 11), (5, 8)], fill=p["orange_dark"])
    draw.polygon([(7, 7), (9, 10), (8, 13), (5, 11)], fill=p["orange"])
    draw.polygon([(7, 9), (8, 11), (7, 13), (6, 11)], fill=p["yellow"])
    draw.point((7, 10), fill=p["hot"])
    save(image, path)


def generate_recovery_icon(path: Path) -> None:
    """16x16 potion bottle with green liquid and upper-left glass glints."""
    image, draw = canvas((16, 16))
    p = POTION

    draw.rectangle((6, 1, 10, 3), fill=p["outline"])
    draw.rectangle((7, 1, 9, 2), fill=p["cork"])
    draw.rectangle((5, 3, 11, 6), fill=p["outline"])
    draw.polygon([(5, 5), (3, 8), (3, 13), (5, 15), (11, 15), (13, 13), (13, 8), (11, 5)], fill=p["outline"])
    draw.polygon([(6, 5), (4, 8), (4, 12), (6, 14), (10, 14), (12, 12), (12, 8), (10, 5)], fill=p["glass_dark"])
    draw.rectangle((6, 4, 10, 6), fill=p["glass_mid"])
    draw.polygon([(4, 10), (12, 10), (12, 12), (10, 14), (6, 14), (4, 12)], fill=p["liquid_dark"])
    draw.rectangle((5, 10, 11, 12), fill=p["liquid_mid"])
    draw.rectangle((6, 10, 10, 11), fill=p["liquid_light"])
    draw.line([(5, 8), (5, 10)], fill=p["glass_light"], width=1)
    draw.point((6, 7), fill=p["glass_light"])
    save(image, path)


def generate_shop_frame(path: Path) -> None:
    """48x48 9-slice frame; use 10px patch margins in Godot."""
    image, draw = canvas((48, 48))
    p = FRAME

    # Stepped silhouette leaves the four extreme corner pixels transparent.
    draw.rectangle((4, 0, 43, 47), fill=p["navy"])
    draw.rectangle((0, 4, 47, 43), fill=p["navy"])

    # Double metal border: deep outer rail, bright inner rail, then a steel lip.
    draw.line([(4, 0), (43, 0), (47, 4), (47, 43), (43, 47), (4, 47), (0, 43), (0, 4), (4, 0)], fill=p["outline"], width=1)
    draw.line([(5, 1), (42, 1), (46, 5), (46, 42), (42, 46), (5, 46), (1, 42), (1, 5), (5, 1)], fill=p["gold_deep"], width=2)
    draw.line([(6, 3), (41, 3), (44, 6), (44, 41), (41, 44), (6, 44), (3, 41), (3, 6), (6, 3)], fill=p["gold_mid"], width=1)
    draw.line([(7, 4), (40, 4), (43, 7), (43, 40), (40, 43), (7, 43), (4, 40), (4, 7), (7, 4)], fill=p["gold_light"], width=1)
    draw.line([(8, 6), (39, 6), (41, 8), (41, 39), (39, 41), (8, 41), (6, 39), (6, 8), (8, 6)], fill=p["steel"], width=1)
    draw.line([(9, 7), (38, 7), (40, 9), (40, 38), (38, 40), (9, 40), (7, 38), (7, 9), (9, 7)], fill=p["gold_dark"], width=1)

    # Riveted diamond ornaments are contained inside the 10px corner patches.
    for center_x, center_y in ((6, 6), (41, 6), (6, 41), (41, 41)):
        draw.polygon([(center_x, center_y - 2), (center_x + 2, center_y), (center_x, center_y + 2), (center_x - 2, center_y)], fill=p["outline"])
        draw.polygon([(center_x, center_y - 1), (center_x + 1, center_y), (center_x, center_y + 1), (center_x - 1, center_y)], fill=p["gold_mid"])
        draw.point((center_x, center_y - 1), fill=p["gold_light"])
    save(image, path)


def generate_cursor(path: Path) -> None:
    """8x8 right-pointing SFC menu cursor."""
    image, draw = canvas((8, 8))
    p = CURSOR
    draw.polygon([(0, 1), (7, 4), (0, 7)], fill=p["outline"])
    draw.polygon([(1, 2), (5, 4), (1, 6)], fill=p["gold"])
    draw.line([(1, 2), (4, 3)], fill=p["highlight"], width=1)
    save(image, path)


def generate_crate(path: Path) -> None:
    """32x32 merchant crate with reinforced corners and diagonal bracing."""
    image, draw = canvas((32, 32))
    p = WOOD

    draw.rectangle((2, 4, 29, 29), fill=p["outline"])
    draw.rectangle((4, 5, 27, 27), fill=p["mid"])
    draw.rectangle((4, 5, 27, 8), fill=p["light"])
    draw.rectangle((4, 24, 27, 27), fill=p["dark"])
    draw.rectangle((4, 9, 27, 10), fill=p["deep"])
    draw.rectangle((4, 18, 27, 20), fill=p["deep"])

    # Pixel-stepped X brace, darker lower-right and highlighted upper-left.
    for step in range(18):
        x = 6 + step
        y_a = 8 + step
        y_b = 25 - step
        if 8 <= y_a <= 25:
            draw.rectangle((x, y_a, min(x + 2, 27), min(y_a + 2, 27)), fill=p["dark"])
            draw.point((x, y_a), fill=p["light"])
        if 8 <= y_b <= 25:
            draw.rectangle((x, y_b, min(x + 2, 27), min(y_b + 2, 27)), fill=p["dark"])
            draw.point((x, y_b), fill=p["light"])

    draw.rectangle((2, 4, 5, 29), fill=p["outline"])
    draw.rectangle((4, 6, 5, 27), fill=p["iron"])
    draw.rectangle((26, 4, 29, 29), fill=p["outline"])
    draw.rectangle((26, 6, 27, 27), fill=p["iron"])
    for x, y in ((4, 7), (27, 7), (4, 26), (27, 26)):
        draw.point((x, y), fill=p["nail"])
    draw.line([(7, 6), (19, 6)], fill=p["glint"], width=1)
    save(image, path)


def generate_lantern(path: Path) -> None:
    """16x24 warm hanging lantern; opaque glow pixels suit a PointLight child."""
    image, draw = canvas((16, 24))
    p = LANTERN

    # Handle and cap.
    draw.line([(5, 5), (5, 2), (7, 0), (9, 0), (11, 2), (11, 5)], fill=p["outline"], width=2)
    draw.line([(6, 4), (6, 2), (7, 1), (9, 1), (10, 2), (10, 4)], fill=p["metal_light"], width=1)
    draw.polygon([(4, 5), (12, 5), (14, 8), (13, 9), (3, 9), (2, 8)], fill=p["outline"])
    draw.rectangle((5, 6, 11, 7), fill=p["metal_mid"])
    draw.line([(5, 6), (9, 6)], fill=p["metal_light"], width=1)

    # Warm glass chamber with a left-up hot core.
    draw.polygon([(3, 9), (13, 9), (12, 19), (10, 21), (6, 21), (4, 19)], fill=p["outline"])
    draw.polygon([(5, 10), (11, 10), (11, 18), (9, 20), (6, 20), (5, 18)], fill=p["ember"])
    draw.rectangle((6, 11, 10, 18), fill=p["orange"])
    draw.rectangle((6, 12, 9, 17), fill=p["yellow"])
    draw.rectangle((7, 12, 8, 15), fill=p["hot"])
    draw.line([(4, 10), (4, 18)], fill=p["metal_mid"], width=1)
    draw.line([(12, 10), (12, 18)], fill=p["metal_dark"], width=1)

    # Weighted base.
    draw.polygon([(4, 20), (12, 20), (14, 22), (13, 23), (3, 23), (2, 22)], fill=p["outline"])
    draw.rectangle((5, 20, 11, 21), fill=p["metal_mid"])
    draw.line([(5, 20), (9, 20)], fill=p["metal_light"], width=1)
    save(image, path)


ASSETS: dict[str, tuple[tuple[int, int], Callable[[Path], None]]] = {
    "weapon_icon": ((16, 16), generate_weapon_icon),
    "upgrade_icon": ((16, 16), generate_upgrade_icon),
    "status_icon": ((16, 16), generate_status_icon),
    "recovery_icon": ((16, 16), generate_recovery_icon),
    "shop_frame": ((48, 48), generate_shop_frame),
    "cursor": ((8, 8), generate_cursor),
    "crate": ((32, 32), generate_crate),
    "lantern": ((16, 24), generate_lantern),
}


def validate_asset(path: Path, expected_size: tuple[int, int]) -> int:
    image = Image.open(path).convert("RGBA")
    if image.size != expected_size:
        raise ValueError(f"Unexpected size {image.size}, expected {expected_size}: {path}")
    colors = {pixel for pixel in image.get_flattened_data() if pixel[3] > 0}
    if len(colors) > 8:
        raise ValueError(f"Palette exceeds 8 visible colors ({len(colors)}): {path}")
    if image.getpixel((0, 0))[3] != 0:
        raise ValueError(f"Top-left background is not transparent: {path}")
    alpha_values = {pixel[3] for pixel in image.get_flattened_data()}
    if path.stem == "shop_frame":
        if 220 not in alpha_values or 0 not in alpha_values:
            raise ValueError("shop_frame must contain transparent corners and alpha-220 navy center")
    elif not alpha_values.issubset({0, 255}):
        raise ValueError(f"Non-binary alpha found outside shop_frame: {path}")
    return len(colors)


def build_preview_sheet(output_dir: Path, preview_path: Path) -> None:
    """Build a nearest-neighbor QA sheet outside the runtime asset set."""
    columns = 4
    cell_width = 216
    cell_height = 236
    rows = (len(ASSETS) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * cell_width, rows * cell_height), (9, 13, 20, 255))
    draw = ImageDraw.Draw(sheet)
    for index, stem in enumerate(ASSETS):
        source = Image.open(output_dir / f"{stem}.png").convert("RGBA")
        scale = max(1, min(8, 176 // max(source.size)))
        enlarged = source.resize(
            (source.width * scale, source.height * scale),
            Image.Resampling.NEAREST,
        )
        cell_x = (index % columns) * cell_width
        cell_y = (index // columns) * cell_height
        x = cell_x + (cell_width - enlarged.width) // 2
        y = cell_y + 12
        # A dark-blue swatch makes transparent edges legible without changing assets.
        draw.rectangle((cell_x + 8, cell_y + 8, cell_x + cell_width - 8, cell_y + 196), fill=(17, 25, 39, 255))
        sheet.alpha_composite(enlarged, (x, y))
        draw.text((cell_x + 12, cell_y + 204), stem, fill=(235, 238, 244, 255))
    preview_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(preview_path, "PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--only",
        choices=sorted(ASSETS),
        help="Regenerate just one asset stem (default: all assets).",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=OUTPUT_DIR,
        help=f"PNG output directory (default: {OUTPUT_DIR}).",
    )
    parser.add_argument(
        "--preview",
        type=Path,
        help="Optional nearest-neighbor QA contact-sheet path (not a runtime asset).",
    )
    args = parser.parse_args()

    selected = [args.only] if args.only else list(ASSETS)
    for stem in selected:
        expected_size, generator = ASSETS[stem]
        output_path = args.output_dir / f"{stem}.png"
        generator(output_path)
        color_count = validate_asset(output_path, expected_size)
        print(f"generated {output_path} size={expected_size[0]}x{expected_size[1]} colors={color_count}")

    if "shop_frame" in selected:
        print(f"shop_frame 9-slice patch margin: {FRAME_PATCH_MARGIN}px")
    if args.preview:
        if args.only:
            raise ValueError("--preview requires a full generation run (omit --only)")
        build_preview_sheet(args.output_dir, args.preview)
        print(f"preview {args.preview}")


if __name__ == "__main__":
    main()
