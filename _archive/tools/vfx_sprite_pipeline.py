"""Normalize a chroma-key-removed horizontal VFX strip into Godot-ready pixel frames."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def _alpha_bbox(image: Image.Image, threshold: int) -> tuple[int, int, int, int] | None:
    alpha = image.getchannel("A").point(lambda value: 255 if value >= threshold else 0)
    return alpha.getbbox()


def normalize_strip(
    source_path: Path,
    output_path: Path,
    frame_count: int,
    frame_size: int,
    alpha_threshold: int,
    content_ratio: float,
) -> None:
    source = Image.open(source_path).convert("RGBA")
    source_width, source_height = source.size
    frames: list[Image.Image] = []
    max_half_extent = 1.0

    for index in range(frame_count):
        left = round(source_width * index / frame_count)
        right = round(source_width * (index + 1) / frame_count)
        frame = source.crop((left, 0, right, source_height))
        frames.append(frame)
        bbox = _alpha_bbox(frame, alpha_threshold)
        if bbox is None:
            continue
        center_x = frame.width / 2.0
        center_y = frame.height / 2.0
        max_half_extent = max(
            max_half_extent,
            abs(bbox[0] - center_x),
            abs(bbox[2] - center_x),
            abs(bbox[1] - center_y),
            abs(bbox[3] - center_y),
        )

    crop_half = max_half_extent / max(min(content_ratio, 0.95), 0.1)
    sheet = Image.new("RGBA", (frame_size * frame_count, frame_size), (0, 0, 0, 0))
    nonempty_frames = 0

    for index, frame in enumerate(frames):
        center_x = frame.width / 2.0
        center_y = frame.height / 2.0
        crop = frame.crop(
            (
                round(center_x - crop_half),
                round(center_y - crop_half),
                round(center_x + crop_half),
                round(center_y + crop_half),
            )
        )
        pixel_frame = crop.resize((frame_size, frame_size), Image.Resampling.NEAREST)
        pixels = pixel_frame.load()
        for y in range(frame_size):
            for x in range(frame_size):
                red, green, blue, alpha = pixels[x, y]
                if alpha < alpha_threshold:
                    pixels[x, y] = (0, 0, 0, 0)
                else:
                    pixels[x, y] = (red, green, blue, 255)
        if pixel_frame.getchannel("A").getbbox() is not None:
            nonempty_frames += 1
        sheet.alpha_composite(pixel_frame, (index * frame_size, 0))

    if nonempty_frames != frame_count:
        raise ValueError(
            f"Expected {frame_count} non-empty frames, found {nonempty_frames}: {source_path}"
        )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output_path, optimize=False)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--frames", type=int, default=6)
    parser.add_argument("--frame-size", type=int, default=64)
    parser.add_argument("--alpha-threshold", type=int, default=72)
    parser.add_argument("--content-ratio", type=float, default=0.82)
    args = parser.parse_args()
    normalize_strip(
        args.input,
        args.output,
        args.frames,
        args.frame_size,
        args.alpha_threshold,
        args.content_ratio,
    )


if __name__ == "__main__":
    main()
