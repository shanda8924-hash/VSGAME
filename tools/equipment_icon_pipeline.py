"""Normalize generated equipment cutouts into Godot-ready pixel-art icons.

The chroma-key removal step is intentionally handled by the installed imagegen
skill helper.  This script performs only deterministic project-side work:
crop the opaque subject, fit it to a 64x64 canvas with nearest-neighbor
resampling, force binary alpha, and optionally build a review contact sheet.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


CANVAS_SIZE = 64
SUBJECT_SIZE = 54


def normalize_icon(source_path: Path, output_path: Path) -> None:
    image = Image.open(source_path).convert("RGBA")
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError(f"No opaque pixels found: {source_path}")

    subject = image.crop(bbox)
    scale = min(SUBJECT_SIZE / subject.width, SUBJECT_SIZE / subject.height)
    width = max(1, round(subject.width * scale))
    height = max(1, round(subject.height * scale))
    subject = subject.resize((width, height), Image.Resampling.NEAREST)

    # Pixel-art assets use hard transparency; this prevents soft chroma-key
    # edge pixels from becoming a blurry halo after Godot scales the texture.
    pixels = subject.load()
    for y in range(subject.height):
        for x in range(subject.width):
            red, green, blue, alpha_value = pixels[x, y]
            pixels[x, y] = (red, green, blue, 255 if alpha_value >= 128 else 0)

    canvas = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
    canvas.alpha_composite(
        subject,
        ((CANVAS_SIZE - width) // 2, (CANVAS_SIZE - height) // 2),
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output_path, "PNG", optimize=True)


def build_contact_sheet(icon_root: Path, output_path: Path) -> None:
    icon_paths = sorted(icon_root.rglob("*.png"))
    if not icon_paths:
        raise ValueError(f"No PNG icons found under: {icon_root}")

    columns = 5
    cell_width = 176
    cell_height = 112
    rows = (len(icon_paths) + columns - 1) // columns
    sheet = Image.new(
        "RGBA",
        (columns * cell_width, rows * cell_height),
        (20, 20, 26, 255),
    )
    draw = ImageDraw.Draw(sheet)
    for index, icon_path in enumerate(icon_paths):
        x = (index % columns) * cell_width
        y = (index // columns) * cell_height
        icon = Image.open(icon_path).convert("RGBA").resize(
            (80, 80), Image.Resampling.NEAREST
        )
        sheet.alpha_composite(icon, (x + 48, y + 4))
        draw.text((x + 6, y + 88), icon_path.stem[:26], fill=(235, 235, 240, 255))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output_path, "PNG")


def validate_icon(icon_path: Path) -> None:
    image = Image.open(icon_path).convert("RGBA")
    if image.size != (CANVAS_SIZE, CANVAS_SIZE):
        raise ValueError(f"Unexpected icon size {image.size}: {icon_path}")
    alpha_values = set(image.getchannel("A").get_flattened_data())
    if not alpha_values.issubset({0, 255}):
        raise ValueError(f"Non-binary alpha found: {icon_path}")
    if image.getpixel((0, 0))[3] != 0:
        raise ValueError(f"Top-left corner is not transparent: {icon_path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    normalize_parser = subparsers.add_parser("normalize")
    normalize_parser.add_argument("source", type=Path)
    normalize_parser.add_argument("output", type=Path)

    contact_parser = subparsers.add_parser("contact-sheet")
    contact_parser.add_argument("icon_root", type=Path)
    contact_parser.add_argument("output", type=Path)

    validate_parser = subparsers.add_parser("validate")
    validate_parser.add_argument("icon_root", type=Path)

    args = parser.parse_args()
    if args.command == "normalize":
        normalize_icon(args.source, args.output)
        validate_icon(args.output)
    elif args.command == "contact-sheet":
        build_contact_sheet(args.icon_root, args.output)
    else:
        for icon_path in sorted(args.icon_root.rglob("*.png")):
            validate_icon(icon_path)


if __name__ == "__main__":
    main()
