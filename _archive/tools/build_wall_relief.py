"""Keep the original raised wall and use its bright side for every return.

Only approved image preparation: sheet cutting, nearest resizing and compositing.
The original body, facade and boundary pixels stay authoritative. No new drawing.
Run: python tools/build_wall_relief.py
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/tiles/royal"


def tile(image, x, y=0):
    return image.crop((x * 16, y * 16, (x + 1) * 16, (y + 1) * 16))


def build():
    original = Image.open(OUT / "dungeon_atlas.png").convert("RGBA")
    body, front = tile(original, 7, 3), tile(original, 9, 3)
    edges = Image.open(OUT / "wall_edges.png").convert("RGBA")
    # The user's purple-circled EXISTING bright side: two stone pixels and one
    # contact-mortar pixel. Mirror that same material, not the darker right tile.
    bright_side = tile(edges, 2).crop((0, 0, 3, 16))
    sides = [bright_side, bright_side.transpose(Image.Transpose.FLIP_LEFT_RIGHT)]
    # Three-pixel inward returns use the same side stone all the way down.
    # Only the top four rows carry the neighbouring facade's gold coping.
    returns = []
    for left in [True, False]:
        patch = sides[0 if left else 1].copy()
        facing_x = 13 if left else 0
        coping = front.crop((facing_x, 0, facing_x + 3, 4))
        patch.paste(coping.transpose(Image.Transpose.FLIP_LEFT_RIGHT), (0, 0))
        returns.append(patch)
    atlas = Image.new("RGBA", (256, 256))
    for mask in range(256):
        north, east, south, west = [bool(mask & bit) for bit in [1, 2, 4, 8]]
        if south:
            result = front.copy()
            for left, visible in [(True, west), (False, east)]:
                if not visible:
                    continue
                start = 0 if left else 13
                cap = sides[0 if left else 1].copy()
                cap.paste(front.crop((start, 0, start + 3, 4)), (0, 0))
                result.paste(cap, (start, 0))
        else:
            result = body.copy()
            # Keep the original back coping; every visible side shares the
            # bright strip. No differently shaded center or right-side material.
            if north:
                result.paste(tile(edges, 1).crop((0, 0, 16, 3)), (0, 0))
            if west:
                result.paste(sides[0], (0, 0))
            if east:
                result.paste(sides[1], (13, 0))
            for left, visible in [(True, not west and bool(mask & 128)),
                                  (False, not east and bool(mask & 64))]:
                if visible:
                    result.paste(returns[0 if left else 1], (0 if left else 13, 0))
            # Rear concave corners also carry the existing coping, not a new
            # brighter material. Their footprint is restricted to 3x3 pixels.
            for left, visible in [(True, not north and not west and bool(mask & 16)),
                                  (False, not north and not east and bool(mask & 32))]:
                if visible:
                    start = 0 if left else 13
                    result.paste(sides[0 if left else 1].crop((0, 0, 3, 3)), (start, 0))
        result.putalpha(255)
        atlas.paste(result, (mask % 16 * 16, mask // 16 * 16))
    assert tile(atlas, 0).tobytes() == body.tobytes(), "Original dark wall changed"
    assert tile(atlas, 4).tobytes() == front.tobytes(), "Original straight facade changed"
    assert atlas.getchannel("A").getextrema() == (255, 255)
    for mask in range(256):
        prepared = tile(atlas, mask % 16, mask // 16)
        reference = front if mask & 4 else body
        assert prepared.crop((4, 4, 12, 12)).tobytes() == reference.crop((4, 4, 12, 12)).tobytes()
    atlas.save(OUT / "wall_relief.png")
    print("WALL_RELIEF_BUILD PASS: original body/facade, mirrored bright 3px sides/returns, 256 masks")


if __name__ == "__main__":
    build()
