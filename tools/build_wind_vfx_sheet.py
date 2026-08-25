"""Normalize the approved ImageGen wind-blade artwork into a Godot sprite sheet.

The source is a six-panel horizontal composition.  This tool keeps a fixed crop
for every panel so the apparent size growth remains part of the animation,
then downsamples with nearest-neighbour and hardens alpha for crisp pixel edges.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


FRAME_COUNT = 6
FRAME_SIZE = 64


def build(source_path: Path, output_path: Path) -> None:
    source = Image.open(source_path).convert("RGBA")
    alpha_bounds = source.getchannel("A").getbbox()
    if alpha_bounds is None:
        raise ValueError("source contains no visible pixels")

    width, height = source.size
    panel_width = width / FRAME_COUNT
    crop_side = min(height, int(round(panel_width * 1.12)))
    content_center_y = (alpha_bounds[1] + alpha_bounds[3]) * 0.5
    top = int(round(content_center_y - crop_side * 0.5))
    top = max(0, min(top, height - crop_side))

    sheet = Image.new("RGBA", (FRAME_SIZE * FRAME_COUNT, FRAME_SIZE), (0, 0, 0, 0))
    for frame_index in range(FRAME_COUNT):
        center_x = (frame_index + 0.5) * panel_width
        left = int(round(center_x - crop_side * 0.5))
        frame = Image.new("RGBA", (crop_side, crop_side), (0, 0, 0, 0))
        source_left = max(0, left)
        source_right = min(width, left + crop_side)
        if source_right > source_left:
            source_crop = source.crop((source_left, top, source_right, top + crop_side))
            frame.alpha_composite(source_crop, (source_left - left, 0))
        frame = frame.resize((FRAME_SIZE, FRAME_SIZE), Image.Resampling.NEAREST)
        pixels = frame.load()
        for y in range(FRAME_SIZE):
            for x in range(FRAME_SIZE):
                red, green, blue, alpha = pixels[x, y]
                pixels[x, y] = (red, green, blue, 255 if alpha >= 96 else 0)
        sheet.alpha_composite(frame, (frame_index * FRAME_SIZE, 0))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output_path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    build(args.source, args.output)


if __name__ == "__main__":
    main()
