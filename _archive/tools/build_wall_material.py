"""Prepare generated wall/torch art: shared pixels enforce material and rim width.

Python performs approved sheet cutting, nearest scaling, alpha cleanup and
assembly only. The stone, miters and six flame silhouettes are image_gen art.
Usage: python tools/build_wall_material.py [--walls | --torch]
"""
from pathlib import Path
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/source_art"
OUT = ROOT / "assets/tiles/royal"
NEAREST = Image.Resampling.NEAREST
CW = Image.Transpose.ROTATE_270
RIM = 4


def turn(image, count):
    for _ in range(count):
        image = image.transpose(CW)
    return image


def walls():
    art = Image.open(SOURCE / "wall_material_source.png").convert("RGBA")
    art.putalpha(255)  # Walls are solid material, never translucent sheet pixels.
    middle = art.width // 2
    outer = art.crop((0, 0, middle, art.height)).resize((48, 48), NEAREST)
    room = art.crop((middle, 0, art.width, art.height))
    opening = room.convert("L").point(lambda value: 255 if value < 12 else 0).getbbox()
    assert opening is not None, "Generated master has no square room opening"
    # Align the generated inner opening to the exact 16px cell lattice. This
    # nine-slice prep moves no in-game cell; it only normalizes source sampling.
    xs, ys = [0, opening[0], opening[2], room.width], [0, opening[1], opening[3], room.height]
    inner = Image.new("RGBA", (48, 48))
    for y in range(3):
        for x in range(3):
            piece = room.crop((xs[x], ys[y], xs[x + 1], ys[y + 1]))
            inner.paste(piece.resize((16, 16), NEAREST), (16 * x, 16 * y))
    body = outer.crop((16, 16, 32, 32))
    edge = outer.crop((16, 0, 32, RIM))
    convex = outer.crop((0, 0, RIM, RIM))
    concave = inner.crop((32, 32, 32 + RIM, 32 + RIM))
    # The source's fine brass inlay can fall BETWEEN nearest-neighbor samples.
    # Preserve that authored row at one native pixel, using source pixels only.
    x0, x1 = middle // 3, middle * 2 // 3
    gold_rows = []
    for y in range(art.height // 8):
        samples = [art.getpixel((x, y)) for x in range(x0, x1, 8)]
        if sum(r > b * 1.6 and g > b * 1.3 and r > 90 for r, g, b, _ in samples) > len(samples) * 0.8:
            gold_rows.append(y)
    assert gold_rows, "Master has no authored brass coping row"
    gold_y = gold_rows[len(gold_rows) // 2]
    edge.paste(art.crop((x0, gold_y, x1, gold_y + 1)).resize((16, 1), NEAREST), (0, 1))
    # Exact shared edge pixels at tile seams; preserve the authored miter inside.
    vertical = turn(edge, 3)
    convex.paste(edge.crop((0, 0, 1, RIM)), (RIM - 1, 0))
    convex.paste(vertical.crop((0, 0, RIM, 1)), (0, RIM - 1))
    concave.paste(edge.crop((15, 0, 16, RIM)), (0, 0))
    concave.paste(vertical.crop((0, 15, RIM, 16)), (0, 0))
    # Every orientation uses identical authored cross-section pixels, rotated
    # offline, not separately generated colors or different face thicknesses.
    atlas = Image.new("RGBA", (256, 256))
    edge_positions = [(0, 0), (16 - RIM, 0), (0, 16 - RIM), (0, 0)]
    corner_positions = [(0, 0), (16 - RIM, 0), (16 - RIM, 16 - RIM), (0, 16 - RIM)]
    adjacent = [(1, 8), (1, 2), (4, 2), (4, 8)]
    for mask in range(256):
        tile = body.copy()
        for direction in range(4):
            if mask & (1 << direction):
                tile.paste(turn(edge, direction), edge_positions[direction])
        for corner, (a, b) in enumerate(adjacent):
            patch = None
            if mask & a and mask & b:
                patch = convex
            elif not mask & a and not mask & b and mask & (16 << corner):
                patch = concave
            if patch is not None:
                tile.paste(turn(patch, corner), corner_positions[corner])
        tile.putalpha(255)
        atlas.paste(tile, (mask % 16 * 16, mask // 16 * 16))
    atlas.save(OUT / "wall_material.png")
    assert atlas.getchannel("A").getextrema() == (255, 255)
    # Inner-corner-only masks may alter exactly one 4x4 corner, never a whole
    # column into a differently colored front face.
    for corner, (cx, cy) in enumerate(corner_positions):
        mask = 16 << corner
        tile = atlas.crop((mask % 16 * 16, mask // 16 * 16, mask % 16 * 16 + 16, mask // 16 * 16 + 16))
        assert all(tile.getpixel((x, y)) == body.getpixel((x, y))
                   for y in range(16) for x in range(16) if not (cx <= x < cx + RIM and cy <= y < cy + RIM))
    print("WALL_MATERIAL_BUILD PASS: one body, 4px cross-section, 256 masks, binary alpha")


def torch():
    art = Image.open(SOURCE / "torch_flame_source.png").convert("RGBA")
    assert art.getchannel("A").getextrema()[0] == 0, "Generated flame must have real transparent background"
    art.putalpha(art.getchannel("A").point(lambda value: 255 if value >= 160 else 0))
    art.putdata([pixel if pixel[3] else (0, 0, 0, 0) for pixel in art.get_flattened_data()])
    old = Image.open(OUT / "torch.png").convert("RGBA")
    bracket = old.crop((0, 12, 16, 24))
    result = Image.new("RGBA", (96, 24))
    flames = []
    for index in range(6):
        x, y = index % 3, index // 3
        # All cells use identical crop/scale/anchor; no frame-by-frame fitting
        # that would make the flame body jump or erase the changing height.
        frame = art.crop((round(x * art.width / 3), round(y * art.height / 2),
                          round((x + 1) * art.width / 3), round((y + 1) * art.height / 2)))
        flame = frame.resize((16, 12), NEAREST)
        flames.append(flame)
    # Remove the sheet's shared transparent bottom gutter so fire meets the
    # bowl. One common offset preserves every silhouette and animation anchor.
    base_row = max(flame.getbbox()[3] for flame in flames)
    assert all(flame.getbbox()[3] == base_row for flame in flames), "Flame bases must share one anchor"
    for index, flame in enumerate(flames):
        result.paste(flame.crop((0, 0, 16, base_row)), (index * 16, 12 - base_row))
        result.paste(bracket, (index * 16, 12))
    assert len({flame.tobytes() for flame in flames}) == 6, "Flames are not six distinct animation frames"
    assert set(result.getchannel("A").tobytes()) == {0, 255}
    for index in range(6):
        assert result.crop((index * 16, 12, index * 16 + 16, 24)).tobytes() == bracket.tobytes()
        assert any(result.getpixel((index * 16 + x, 11))[3] and bracket.getpixel((x, 0))[3]
                   for x in range(16)), "Flame must touch the fixed torch bowl"
    result.save(OUT / "torch_6f.png")
    print("TORCH_BUILD PASS: six unique flames, identical fixed bracket, binary alpha")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    if "--torch" not in sys.argv:
        walls()
    if "--walls" not in sys.argv:
        torch()
