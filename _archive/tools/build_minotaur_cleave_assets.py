"""Prepare imagegen artwork: cut cells, remove pale checker background, align feet.

No character drawing/pose synthesis here. Original sheets are never modified.
Run with --source-dir pointing at the directory containing the generated PNGs.
"""
from pathlib import Path
import argparse
import shutil
from collections import deque
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/sprites/boss/Minotaur/hd2d"
ART = ROOT / "artifacts/hd2d_cleave_assets"
CELL = 100
BASELINE = 58
BODY_HEIGHT = 20
# Original generated canvas coordinates: (feet center X, feet Y, horn top Y).
CONFIG = {
    "side": ("exec-22460927-e534-414b-83bb-a01a12822065.png", [
        (158, 413, 270), (631, 413, 268), (991, 413, 268), (1351, 413, 268),
        (158, 718, 577), (596, 718, 577), (1000, 718, 577), (1384, 718, 577),
    ]),
    "back": ("exec-fc27cbc9-ed9e-4461-82bf-8f61e3211474.png", [
        (222, 405, 244), (632, 405, 244), (1044, 405, 244), (1386, 405, 244),
        (259, 720, 563), (611, 720, 563), (1000, 720, 563), (1389, 720, 563),
    ]),
    "front": ("exec-3b7ddfa8-51f2-4224-be1b-c9ea775f2785.png", [
        (284, 344, 155), (736, 344, 151), (1140, 344, 155), (1513, 344, 155),
        (280, 691, 500), (688, 691, 500), (1150, 691, 500), (1532, 691, 500),
    ]),
}


def remove_background(source):
    source = source.convert("RGBA")
    pixels = source.load()
    # Generated source came as RGB with a pale checker, despite requesting alpha.
    # Its background is >220 in every channel; character pixels stay much darker.
    for y in range(source.height):
        for x in range(source.width):
            r, g, b, a = pixels[x, y]
            if min(r, g, b) > 220 and max(r, g, b) - min(r, g, b) < 18:
                pixels[x, y] = (0, 0, 0, 0)
            else:
                pixels[x, y] = (r, g, b, 255 if a >= 128 else 0)
    return source


def prepare(direction, source_dir):
    filename, anchors = CONFIG[direction]
    source_path = source_dir / filename
    raw_dir = OUT / "source"
    raw_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source_path, raw_dir / f"minotaur_cleave_{direction}_generated.png")
    source = remove_background(Image.open(source_path))
    frames = []
    for index, (anchor_x, feet_y, horn_y) in enumerate(anchors):
        col, row = index % 4, index // 4
        left, top = round(col * source.width / 4), round(row * source.height / 2)
        right, bottom = round((col + 1) * source.width / 4), round((row + 1) * source.height / 2)
        if direction == "front" and row == 1:
            # The generated last near-side blade reaches left of the nominal grid.
            # Separate at the actual empty gutter, never clip the solid weapon.
            left, right = [0, 467, 970, 1310, source.width][col:col + 2]
        cell = source.crop((left, top, right, bottom))
        cell = keep_character_component(cell)
        bounds = cell.getbbox()
        assert bounds, (direction, index, "empty cell")
        cut = cell.crop(bounds)
        scale = BODY_HEIGHT / (feet_y - horn_y)
        resized = cut.resize((max(1, round(cut.width * scale)), max(1, round(cut.height * scale))), Image.Resampling.NEAREST)
        x = round(CELL / 2 - (anchor_x - left - bounds[0]) * scale)
        y = round(BASELINE - (feet_y - top - bounds[1]) * scale)
        assert x >= 0 and y >= 0 and x + resized.width <= CELL and y + resized.height <= CELL
        frame = Image.new("RGBA", (CELL, CELL))
        frame.alpha_composite(resized, (x, y))
        frames.append(frame)
    # Front cell3 was drawn right-facing; use its ready-left pose for sweep start,
    # then the foreshortened down-pointing cell4 and right-pointing cell5.
    if direction == "front":
        frames[3] = frames[0].copy()
    if direction == "back":
        # Dedicated newly generated foreshortened contact pose: the solid blade
        # points away and is naturally hidden by the torso at the middle angle.
        single_path = source_dir / "exec-04eaf4b8-2895-40c9-b7df-2a5a0c31e8e0.png"
        shutil.copy2(single_path, raw_dir / "minotaur_cleave_back_center_generated.png")
        single = keep_character_component(remove_background(Image.open(single_path)))
        bounds = single.getbbox()
        cut = single.crop(bounds)
        scale = BODY_HEIGHT / (844 - 416)
        resized = cut.resize((round(cut.width * scale), round(cut.height * scale)), Image.Resampling.NEAREST)
        centered = Image.new("RGBA", (CELL, CELL))
        centered.alpha_composite(resized, (round(CELL / 2 - (620 - bounds[0]) * scale), round(BASELINE - (844 - bounds[1]) * scale)))
        frames[4] = centered
    sheet = Image.new("RGBA", (CELL * 8, CELL))
    for index, frame in enumerate(frames):
        sheet.alpha_composite(frame, (CELL * index, 0))
    sheet.save(OUT / f"minotaur_cleave_{direction}_8f.png")
    return frames


def keep_character_component(cell):
    pixels = cell.load()
    remaining = {(x, y) for y in range(cell.height) for x in range(cell.width) if pixels[x, y][3]}
    largest = set()
    while remaining:
        start = remaining.pop()
        component = {start}
        todo = deque([start])
        while todo:
            x, y = todo.popleft()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                point = (x + dx, y + dy)
                if point in remaining:
                    remaining.remove(point)
                    component.add(point)
                    todo.append(point)
        if len(component) > len(largest):
            largest = component
    for y in range(cell.height):
        for x in range(cell.width):
            if (x, y) not in largest:
                pixels[x, y] = (0, 0, 0, 0)
    return cell


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", required=True, type=Path)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    ART.mkdir(parents=True, exist_ok=True)
    gallery = Image.new("RGBA", (8 * 300, 4 * 260), (30, 38, 46, 255))
    for row, direction in enumerate(CONFIG):
        frames = prepare(direction, args.source_dir)
        for index, frame in enumerate(frames):
            enlarged = frame.crop((22, 22, 82, 74)).resize((300, 260), Image.Resampling.NEAREST)
            gallery.alpha_composite(enlarged, (index * 300, row * 260))
    original = Image.open(ROOT / "assets/sprites/boss/Minotaur/Minotaur/Minotaur_Idle.png").convert("RGBA")
    reference = original.crop((22, 22, 82, 74)).resize((300, 260), Image.Resampling.NEAREST)
    gallery.alpha_composite(reference, (0, 780))
    gallery.save(ART / "aligned_frames.png")
    print("Prepared 3 x 8 transparent frames; source art preserved;", OUT)


if __name__ == "__main__":
    main()
