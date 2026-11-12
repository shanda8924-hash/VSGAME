"""Normalize generated equipment cutouts into Godot-ready pixel-art icons.

The chroma-key removal step is intentionally handled by the installed imagegen
skill helper.  This script performs only deterministic project-side work:
crop the opaque subject, fit it to a 64x64 canvas with nearest-neighbor
resampling, force binary alpha, and optionally build a review contact sheet.
"""

from __future__ import annotations

import argparse
from collections import deque
import json
from pathlib import Path

from PIL import Image, ImageDraw


CANVAS_SIZE = 64
SUBJECT_SIZE = 54


def normalize_icon(source_path: Path, output_path: Path) -> None:
    normalize_image(Image.open(source_path).convert("RGBA"), output_path)


def normalize_image(image: Image.Image, output_path: Path, pixel_grid: int = 1) -> None:
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError(f"No opaque pixels found: {source_path}")

    subject = image.crop(bbox)
    scale = min((SUBJECT_SIZE // pixel_grid) / subject.width, (SUBJECT_SIZE // pixel_grid) / subject.height)
    width = max(1, round(subject.width * scale))
    height = max(1, round(subject.height * scale))
    subject = subject.resize((width, height), Image.Resampling.NEAREST)
    if pixel_grid > 1:
        subject = subject.resize((width * pixel_grid, height * pixel_grid), Image.Resampling.NEAREST)
        width, height = subject.size

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


def import_royal_atlas(source_path: Path, project_root: Path) -> None:
    """Extract the approved 5x5 atlas without clipping tips at nominal cell borders.

    Connected opaque components belong to the nearest grid cell by their centre.
    This retains separated gloves, bowstrings and small metal parts. It performs
    asset slicing/nearest-size normalization only; the art comes from imagegen.
    """
    image = Image.open(source_path).convert("RGBA")
    templates = json.loads((project_root / "data/equipment/templates.json").read_text(encoding="utf-8-sig"))
    if len(templates) != 25:
        raise ValueError("The royal atlas contains exactly 25 catalog icons")
    width, height = image.size
    alpha = image.getchannel("A")
    pixels = alpha.load()
    visited = bytearray(width * height)
    groups: list[list[list[tuple[int, int]]]] = [[] for _ in templates]
    for y in range(height):
        for x in range(width):
            if visited[y * width + x] or pixels[x, y] < 128:
                continue
            queue = deque([(x, y)])
            visited[y * width + x] = 1
            component = []
            while queue:
                cx, cy = queue.popleft()
                component.append((cx, cy))
                for nx, ny in [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)]:
                    if 0 <= nx < width and 0 <= ny < height:
                        offset = ny * width + nx
                        if not visited[offset] and pixels[nx, ny] >= 128:
                            visited[offset] = 1
                            queue.append((nx, ny))
            if len(component) < 64:
                continue
            center_x = sum(point[0] for point in component) / len(component)
            center_y = sum(point[1] for point in component) / len(component)
            column = min(4, int(center_x * 5 / width))
            row = min(4, int(center_y * 5 / height))
            groups[row * 5 + column].append(component)
    for template, components in zip(templates, groups):
        largest = max((len(component) for component in components), default=0)
        group = [point for component in components if len(component) >= max(64, largest * 0.02) for point in component]
        if len(group) < 400:
            raise ValueError(f"Incomplete atlas object: {template['id']}")
        mask = Image.new("L", image.size, 0)
        mask_pixels = mask.load()
        for x, y in group:
            mask_pixels[x, y] = pixels[x, y]
        cutout = image.copy()
        cutout.putalpha(mask)
        output = project_root / template["icon_path"].removeprefix("res://")
        normalize_image(cutout, output, pixel_grid=2)
        validate_icon(output)
        print(f"{template['id']}: {output.relative_to(project_root)}")
    write_icon_bounds(project_root)


def write_icon_bounds(project_root: Path) -> None:
    """Bake CPU-side pixel bounds so ground drops never read GPU textures back."""
    templates = json.loads((project_root / "data/equipment/templates.json").read_text(encoding="utf-8-sig"))
    lines = ["extends RefCounted", "## Generated by tools/equipment_icon_pipeline.py bounds. Do not hand-edit.", "const BOUNDS := {"]
    for template in templates:
        path = template["icon_path"]
        image = Image.open(project_root / path.removeprefix("res://")).convert("RGBA")
        x0, y0, x1, y1 = image.getchannel("A").getbbox()
        lines.append(f'\t"{path}": Rect2i({x0}, {y0}, {x1 - x0}, {y1 - y0}),')
    lines.append("}\n")
    (project_root / "resources/equipment_icon_metrics.gd").write_text("\n".join(lines), encoding="utf-8")


def validate_catalog(project_root: Path) -> None:
    templates = json.loads((project_root / "data/equipment/templates.json").read_text(encoding="utf-8-sig"))
    metrics = (project_root / "resources/equipment_icon_metrics.gd").read_text(encoding="utf-8")
    unique_images = set()
    for template in templates:
        path = template["icon_path"]
        local = project_root / path.removeprefix("res://")
        validate_icon(local)
        image = Image.open(local).convert("RGBA")
        x0, y0, x1, y1 = image.getchannel("A").getbbox()
        entry = f'"{path}": Rect2i({x0}, {y0}, {x1 - x0}, {y1 - y0})'
        if entry not in metrics:
            raise ValueError(f"Stale runtime bounds: {path}; run the bounds command")
        unique_images.add(image.tobytes())
    if len(unique_images) != len(templates):
        raise ValueError("Two catalog items have identical icons")
    print(f"PASS: {len(templates)} distinct 64x64 binary-alpha icons; every runtime bound matches")


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

    atlas_parser = subparsers.add_parser("import-royal-atlas")
    atlas_parser.add_argument("source", type=Path)
    atlas_parser.add_argument("project_root", type=Path)
    bounds_parser = subparsers.add_parser("bounds")
    bounds_parser.add_argument("project_root", type=Path)
    catalog_parser = subparsers.add_parser("validate-catalog")
    catalog_parser.add_argument("project_root", type=Path)

    args = parser.parse_args()
    if args.command == "normalize":
        normalize_icon(args.source, args.output)
        validate_icon(args.output)
    elif args.command == "contact-sheet":
        build_contact_sheet(args.icon_root, args.output)
    elif args.command == "import-royal-atlas":
        import_royal_atlas(args.source, args.project_root)
    elif args.command == "bounds":
        write_icon_bounds(args.project_root)
    elif args.command == "validate-catalog":
        validate_catalog(args.project_root)
    else:
        for icon_path in sorted(args.icon_root.rglob("*.png")):
            validate_icon(icon_path)


if __name__ == "__main__":
    main()
