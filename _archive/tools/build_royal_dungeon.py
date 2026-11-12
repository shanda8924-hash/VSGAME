"""Pack generated royal-dungeon art into the game's existing 16px atlas contract.

No runtime image reads, new collisions, shader, or per-frame map work. Re-run with
the retained source to reproduce every texture. Preview is an asset assembly,
not a screenshot from Godot.
"""
from pathlib import Path
import sys
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/source_art/royal_dungeon_source.png"
OUT = ROOT / "assets/tiles/royal"
N = Image.Resampling.NEAREST
# Restrained shared floor values: actors and gold props carry the contrast.
SLATE = [(25, 31, 42), (32, 39, 50), (38, 46, 57), (44, 53, 64),
         (50, 60, 70), (57, 67, 77), (63, 74, 83), (70, 81, 89)]
FLOOR_COORDS = [(9, 10), (12, 8), (0, 9), (1, 10), (1, 11)]


def source_cell(source, column, row):
    # The generated 1254px sheet has fractional 313.5px cells.
    edges = [round(i * source.width / 4) for i in range(5)]
    return source.crop((edges[column], edges[row], edges[column + 1], edges[row + 1]))


def fitted(cell, size, margin=1):
    alpha = cell.getchannel("A").point(lambda a: 255 if a >= 160 else 0)
    cell.putalpha(alpha)
    bounds = alpha.getbbox()
    if not bounds:
        raise ValueError("Empty generated prop")
    cell = cell.crop(bounds)
    ratio = min((size[0] - margin * 2) / cell.width, (size[1] - margin * 2) / cell.height)
    cell = cell.resize((max(1, round(cell.width * ratio)), max(1, round(cell.height * ratio))), N)
    result = Image.new("RGBA", size)
    result.alpha_composite(cell, ((size[0] - cell.width) // 2, size[1] - margin - cell.height))
    return result


def floor_tile(cell):
    tile = cell.resize((16, 16), N).convert("RGBA")
    # Quantize brightness into one material; no patchwork of region palettes.
    values = []
    for red, green, blue, _ in list(tile.get_flattened_data()):
        luminance = (red * 3 + green * 6 + blue) // 10
        values.append((*SLATE[min(7, max(0, (luminance - 16) // 22))], 255))
    tile.putdata(values)
    return tile


def place(atlas, tile, coord):
    atlas.alpha_composite(tile, (coord[0] * 16, coord[1] * 16))


def architecture_overlays(source):
    """Keep original cutout alpha: wall/floor is supplied by Godot, not baked in."""
    overlay = Image.new("RGBA", (128, 64))
    banner = source_cell(source, 2, 2)
    for column in range(3):
        place(overlay, fitted(banner, (16, 32), 1), (column, 0))
    place(overlay, fitted(source_cell(source, 3, 1), (16, 32)), (3, 0))
    place(overlay, fitted(source_cell(source, 0, 3), (16, 16)), (4, 0))
    place(overlay, fitted(source_cell(source, 3, 3), (16, 16)), (5, 0))
    place(overlay, fitted(source_cell(source, 3, 1), (32, 32)), (0, 2))
    place(overlay, fitted(source_cell(source, 2, 3), (32, 32)), (2, 2))
    overlay.save(OUT / "wall_overlays.png")
    for name, size in [("boss_floor_seal", (128, 128)), ("boss_floor_border", (48, 48))]:
        path = ROOT / "tools/source_art" / (name + "_source.png")
        if not path.exists():
            continue
        art = Image.open(path).convert("RGBA")
        assert art.getchannel("A").getextrema()[0] == 0, f"No transparency: {name}"
        art.putalpha(art.getchannel("A").point(lambda alpha: 255 if alpha >= 160 else 0))
        # Keep border coordinates continuous across all nine slices. Resizing each
        # tile separately would introduce seams; seal is fitted with clear margin.
        prepared = art.resize(size, N) if name.endswith("border") else fitted(art, size, 8)
        prepared.save(OUT / (name + ".png"))
        assert set(prepared.getchannel("A").tobytes()) == {0, 255}
    assert set(overlay.getchannel("A").tobytes()) == {0, 255}


def wall_junctions():
    """Bake generated corner returns into existing materials; no runtime compositing.

    Row 0: front endpoints, column = left 1 / right 2 / both 3.
    Rows 1..3: inner returns with the same side bits; column = old edge mask.
    Only narrow corner strips change. Unaffected straight-wall pixels stay exact.
    """
    source = Image.open(ROOT / "tools/source_art/wall_junctions_source.png").convert("RGBA")
    corners = []
    for index in range(4):
        x, y = index % 2, index // 2
        # Remove the generated sheet's frame, not the stone bevel itself.
        bounds = (round(x * source.width / 2) + 16, round(y * source.height / 2) + 16,
                  round((x + 1) * source.width / 2) - 16, round((y + 1) * source.height / 2) - 16)
        corners.append(source.crop(bounds).resize((16, 16), N))
    base = Image.open(OUT / "dungeon_atlas.png").convert("RGBA")
    wall = base.crop((112, 48, 128, 64))
    front = base.crop((144, 48, 160, 64))
    edges = Image.open(OUT / "wall_edges.png").convert("RGBA")
    atlas = Image.new("RGBA", (128, 64))
    for sides in range(1, 4):
        endpoint = front.copy()
        if sides & 1:
            endpoint.paste(corners[2].crop((0, 0, 2, 16)), (0, 0))
        if sides & 2:
            endpoint.paste(corners[3].crop((14, 0, 16, 16)), (14, 0))
        place(atlas, endpoint, (sides, 0))
        for mask in range(8):
            tile = wall.copy() if mask == 0 else edges.crop((mask * 16, 0, (mask + 1) * 16, 16))
            for side, bit, corner, start, edge_mask in [(0, 1, 1, 0, 2), (1, 2, 0, 12, 4)]:
                if not sides & bit:
                    continue
                tile.paste(corners[corner].crop((start, 0, start + 4, 16)), (start, 0))
                # Match the exact front coping height and the side-wall rim below.
                front_start = 12 if side == 0 else 0
                tile.paste(front.crop((front_start, 0, front_start + 4, 3)), (start, 0))
                tile.paste(edges.crop((edge_mask * 16 + start, 0, edge_mask * 16 + start + 4, 1)), (start, 15))
            # Keep the existing upper boundary when a thin wall also borders floor above.
            if mask & 1:
                tile.paste(edges.crop((mask * 16, 0, (mask + 1) * 16, 1)), (0, 0))
            place(atlas, tile, (mask, sides))
    atlas.save(OUT / "wall_junctions.png")
    assert set(atlas.getchannel("A").tobytes()) == {0, 255}
    assert all(atlas.crop((x * 16, y * 16, x * 16 + 16, y * 16 + 16)).getchannel("A").getextrema() == (255, 255)
               for y in range(4) for x in range(8) if y > 0 or 1 <= x <= 3)
    print("WALL_JUNCTION_ASSETS PASS: 27 baked 16px tiles; original straight materials preserved")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    source = Image.open(SOURCE).convert("RGBA")
    architecture_overlays(source)
    floors = [floor_tile(source_cell(source, 0, 0)), floor_tile(source_cell(source, 1, 0))]
    # Moss is kept sparse in source details, not a green tint across whole rooms.
    floors += [floors[0].transpose(Image.Transpose.FLIP_LEFT_RIGHT), floors[1].transpose(Image.Transpose.FLIP_TOP_BOTTOM), floors[0].copy()]
    wall = source_cell(source, 0, 1).resize((16, 16), N)
    front = source_cell(source, 1, 1).resize((16, 16), N)
    wall.putalpha(255)
    front.putalpha(255)
    atlas = Image.new("RGBA", (352, 192))
    for coord, tile in zip(FLOOR_COORDS, floors):
        place(atlas, tile, coord)
    place(atlas, wall, (7, 3))
    place(atlas, front, (9, 3))
    pillar = fitted(source_cell(source, 3, 1), (16, 32))
    pillar_back = Image.new("RGBA", (16, 32))
    pillar_back.alpha_composite(wall, (0, 0))
    pillar_back.alpha_composite(wall, (0, 16))
    pillar_back.alpha_composite(pillar)
    place(atlas, pillar_back, (20, 0))
    for coord, index in [((7, 5), 0), ((12, 5), 1), ((9, 5), 0), ((10, 5), 1)]:
        # Whole silhouette fitted within each registered tile, never a cropped half.
        place(atlas, fitted(source_cell(source, index, 2), (16, 16)), coord)
    banner = fitted(source_cell(source, 2, 2), (16, 16), 2)
    for coord in [(0, 4), (5, 4)]:
        tile = wall.copy()
        tile.alpha_composite(banner)
        place(atlas, tile, coord)
    grate = fitted(source_cell(source, 3, 3), (16, 16))
    tile = wall.copy()
    tile.alpha_composite(grate)
    place(atlas, tile, (1, 4))
    relief = fitted(source_cell(source, 0, 3), (16, 32))
    relief_back = pillar_back.copy()
    relief_back.alpha_composite(relief)
    place(atlas, relief_back, (13, 0))
    # Threshold is one complete inlaid slab, not a slice from an unrelated object.
    place(atlas, floor_tile(source_cell(source, 3, 0)), (9, 1))
    # Sparse crack-only decal derived from the authored cracked stone, not rubble.
    crack = Image.new("RGBA", (16, 16))
    broken = floors[1]
    for y in range(3, 13):
        for x in range(3, 13):
            if broken.getpixel((x, y))[:3] == SLATE[0]:
                crack.putpixel((x, y), (*SLATE[0], 255))
    place(atlas, crack, (7, 9))
    atlas.save(OUT / "dungeon_atlas.png")
    wall_junctions()

    combat = Image.new("RGBA", (128, 96))
    for y in range(6):
        for x in range(8):
            place(combat, floors[x % len(floors)], (x, y))
    # Only true hazard floor differs. Same stone beneath an unmistakable amber vent.
    for x in range(4, 8):
        tile = floors[x % 5].copy()
        d = ImageDraw.Draw(tile)
        d.rectangle((3, 4, 12, 11), fill=(22, 25, 30), outline=(121, 88, 41))
        for bar in (5, 8, 11):
            d.line((bar, 5, bar, 10), fill=(219, 120, 37))
        place(combat, tile, (x, 0))
    for x in range(8):
        place(combat, front if x % 2 else wall, (x, 2))
    for x, source_position in [(0, (3, 1)), (2, (2, 3))]:
        block = Image.new("RGBA", (32, 32))
        for oy in range(2):
            for ox in range(2):
                place(block, floors[0], (ox, oy))
        block.alpha_composite(fitted(source_cell(source, *source_position), (32, 32)))
        place(combat, block, (x, 3))
    combat.save(OUT / "combat_atlas.png")
    inlay = Image.new("RGBA", (48, 48))
    original_inlay = source_cell(source, 3, 0).resize((48, 48), N)
    for y in range(48):
        for x in range(48):
            r, g, b, _ = original_inlay.getpixel((x, y))
            if r > b * 1.5 and r > 85 and g > b * 1.1:
                inlay.putpixel((x, y), (r, g, b, 255))
    inlay.save(OUT / "royal_inlay.png")
    torch = fitted(source_cell(source, 1, 3), (16, 24))
    torch.save(OUT / "torch.png")
    fitted(source_cell(source, 3, 2), (24, 24), 2).save(OUT / "crystal.png")

    # Offline scene-style assembly at actual pixel density, with complete objects.
    preview = Image.new("RGBA", (320, 208), (12, 16, 24))
    for y in range(2, 12):
        for x in range(1, 19):
            place(preview, floors[(x * 17 + y * 7) % 5], (x, y))
    for x in range(1, 19):
        place(preview, front, (x, 1))
        place(preview, wall, (x, 0))
        place(preview, wall, (x, 12))
    for y in range(13):
        place(preview, wall, (0, y))
        place(preview, wall, (19, y))
    for x in [2, 17]:
        preview.alpha_composite(pillar_back, (x * 16, 0))
        preview.alpha_composite(torch, ((x + (1 if x == 2 else -1)) * 16, 8))
    for offset, cell in enumerate([0, 1, 0]):
        preview.alpha_composite(fitted(source_cell(source, cell, 2), (16, 16)), ((2 + offset) * 16, 40))
    preview.alpha_composite(fitted(source_cell(source, 2, 3), (32, 32)), (144, 82))
    preview.alpha_composite(fitted(source_cell(source, 3, 2), (24, 24)), (259, 164))
    preview.resize((1280, 832), N).save(ROOT / "artifacts/royal_dungeon_asset_preview.png")

    for coord in [(7, 5), (12, 5), (9, 5), (10, 5)]:
        tile = atlas.crop((coord[0] * 16, coord[1] * 16, (coord[0] + 1) * 16, (coord[1] + 1) * 16))
        x0, y0, x1, y1 = tile.getchannel("A").getbbox()
        assert x0 > 0 and y0 > 0 and x1 < 16 and y1 < 16, f"Clipped storage: {coord}"
    assert len(set(atlas.getchannel("A").tobytes())) <= 2, "Unexpected semitransparent pixels"
    print("ROYAL_DUNGEON_ASSETS PASS: 5 textures, complete storage silhouettes, binary alpha; preview is OFFLINE")


if __name__ == "__main__":
    if sys.argv[1:] == ["--wall-junctions"]:
        wall_junctions()
    else:
        main()
