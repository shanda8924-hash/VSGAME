from __future__ import annotations

from pathlib import Path
import random
import sys

from PIL import Image, ImageDraw


TILE = 16
FLOOR_COORDS = [(9, 10), (12, 8), (0, 9), (1, 10), (1, 11)]
STORAGE_COORDS = [(7, 5), (12, 5), (9, 5), (10, 5)]


def put_tile(atlas: Image.Image, tile: Image.Image, coord: tuple[int, int]) -> None:
    atlas.alpha_composite(tile, (coord[0] * TILE, coord[1] * TILE))


def luminance(pixel: tuple[int, int, int, int]) -> int:
    return (pixel[0] * 3 + pixel[1] * 6 + pixel[2]) // 10


def recolor(image: Image.Image, shadows: tuple[int, int, int], lights: tuple[int, int, int],
            accent: tuple[int, int, int] | None = None) -> Image.Image:
    result = Image.new("RGBA", image.size)
    values = []
    for pixel in image.get_flattened_data():
        if pixel[3] == 0:
            values.append((0, 0, 0, 0))
            continue
        t = luminance(pixel) / 255.0
        rgb = tuple(round(shadows[i] + (lights[i] - shadows[i]) * t) for i in range(3))
        if accent is not None and pixel[0] > pixel[2] * 1.28 and pixel[0] > 80:
            strength = min(0.72, max(0.0, (pixel[0] - 80) / 190.0))
            rgb = tuple(round(rgb[i] * (1.0 - strength) + accent[i] * strength) for i in range(3))
        values.append((*rgb, pixel[3]))
    result.putdata(values)
    return result


def rock_floor(seed: int, theme: str) -> Image.Image:
    rng = random.Random(seed)
    variant = seed % 5
    if theme == "amethyst_depths":
        base = (45, 43, 66, 255)
        slabs = [(51, 49, 75), (57, 51, 79), (39, 40, 62)]
        seam = (30, 31, 50)
        speck = (82, 76, 104)
        accent = (58, 142, 161)
    else:
        base = (46, 39, 36, 255)
        slabs = [(53, 45, 41), (58, 47, 41), (39, 35, 35)]
        seam = (28, 27, 28)
        speck = (91, 67, 51)
        accent = (139, 47, 24)
    image = Image.new("RGBA", (16, 16), base)
    draw = ImageDraw.Draw(image)
    shapes = [
        [(-3, 1), (7, -2), (14, 4), (11, 13), (2, 17), (-3, 11)],
        [(2, -2), (14, 0), (18, 8), (10, 17), (-2, 13), (-1, 5)],
        [(-2, -1), (8, 1), (16, 9), (15, 17), (4, 15), (-3, 7)],
        [(5, -2), (18, 2), (14, 12), (7, 18), (-2, 12), (0, 3)],
        [(-2, 4), (5, -2), (16, 1), (18, 12), (8, 17), (-2, 14)],
    ]
    draw.polygon(shapes[variant], fill=slabs[variant % len(slabs)])
    if variant in (0, 2, 4):
        paths = [
            [(-1, 13), (5, 11), (9, 12), (16, 9)],
            [(3, -1), (5, 5), (4, 10), (1, 16)],
            [(13, -1), (11, 5), (13, 10), (9, 16)],
        ]
        draw.line(paths[variant // 2], fill=seam, width=1)
    if theme == "amethyst_depths" and variant == 1:
        draw.line((0, 5, 5, 7, 10, 6, 16, 9), fill=accent)
        draw.point((10, 6), fill=(102, 201, 209))
    elif theme == "ruin_forge" and variant == 3:
        draw.line((1, 14, 7, 10, 10, 11, 15, 6), fill=accent)
        draw.point((7, 10), fill=(229, 92, 30))
    for _ in range(4):
        draw.point((rng.randrange(1, 15), rng.randrange(1, 15)), fill=speck)
    return image


def theme_atlas(base: Image.Image, theme: str) -> tuple[Image.Image, list[Image.Image]]:
    if theme == "amethyst_depths":
        atlas = recolor(base, (20, 18, 34), (105, 96, 132), (91, 174, 183))
        floors = [rock_floor(730 + index, theme) for index in range(5)]
    else:
        atlas = recolor(base, (21, 18, 18), (105, 76, 57), (178, 91, 41))
        floors = [rock_floor(910 + index, theme) for index in range(5)]
    for coord, tile in zip(FLOOR_COORDS, floors):
        put_tile(atlas, tile, coord)
    for coord in STORAGE_COORDS:
        box = (coord[0] * 16, coord[1] * 16, coord[0] * 16 + 16, coord[1] * 16 + 16)
        tile = atlas.crop(box)
        if theme == "amethyst_depths":
            tile = recolor(tile, (25, 22, 39), (151, 126, 171), (75, 198, 203))
        else:
            tile = recolor(tile, (27, 20, 17), (158, 100, 58), (221, 107, 35))
        put_tile(atlas, tile, coord)
    return atlas, floors


def theme_combat(size: tuple[int, int], floors: list[Image.Image], theme: str) -> Image.Image:
    # Room identity now comes from the continuous macro floor and hand-placed
    # decals. Keeping this atlas transparent avoids visible 16 px repetition.
    return Image.new("RGBA", size)


def macro_floor(source_atlas: Image.Image, theme: str) -> Image.Image:
    rng = random.Random(42052 if theme == "amethyst_depths" else 42053)
    if theme == "amethyst_depths":
        shadow, light, gold = (28, 27, 45), (111, 101, 132), (76, 124, 144)
        haze = (84, 55, 112, 24)
        seam, accent, glint = (28, 29, 46, 255), (48, 117, 137, 255), (97, 200, 203, 255)
    else:
        shadow, light, gold = (27, 24, 24), (105, 78, 59), (131, 72, 39)
        haze = (105, 47, 24, 20)
        seam, accent, glint = (25, 24, 24, 255), (121, 44, 25, 255), (224, 88, 28, 255)

    source_tiles = []
    for x, y in FLOOR_COORDS:
        tile = source_atlas.crop((x * 16, y * 16, x * 16 + 16, y * 16 + 16))
        source_tiles.append(recolor(tile, shadow, light, gold))
    image = Image.new("RGBA", (256, 256))
    for y in range(16):
        for x in range(16):
            index = (x * 17 + y * 31 + rng.randrange(13)) % len(source_tiles)
            tile = source_tiles[index]
            if (x * 7 + y * 11) % 9 == 0:
                tile = tile.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            image.alpha_composite(tile, (x * 16, y * 16))

    # Low-alpha masses create room-scale material changes while retaining the
    # hand-authored stone detail and value range of MAP1 beneath them.
    overlay = Image.new("RGBA", image.size)
    od = ImageDraw.Draw(overlay)
    od.polygon([(13, 18), (67, 8), (108, 37), (99, 85), (45, 103), (11, 69)], fill=haze)
    od.polygon([(132, 11), (211, 18), (243, 61), (218, 108), (157, 96), (116, 51)], fill=haze)
    od.polygon([(19, 132), (82, 106), (126, 143), (110, 218), (52, 244), (12, 203)], fill=haze)
    image = Image.alpha_composite(image, overlay)
    d = ImageDraw.Draw(image)
    veins = [
        [(18, 54), (49, 60), (75, 49), (105, 58)],
        [(177, 21), (181, 51), (203, 65), (197, 94)],
        [(145, 202), (181, 181), (215, 192), (242, 175)],
    ] if theme == "amethyst_depths" else [
        [(18, 191), (51, 170), (78, 183), (105, 154), (134, 163)],
        [(159, 19), (153, 53), (178, 77), (169, 103)],
        [(185, 145), (211, 162), (218, 198), (242, 219)],
    ]
    for points in veins:
        d.line(points, fill=accent, width=1 if theme == "amethyst_depths" else 2)
        d.point(points[len(points) // 2], fill=glint)
    for _ in range(42):
        x, y = rng.randrange(6, 247), rng.randrange(6, 247)
        length = rng.randrange(3, 9)
        d.line((x, y, min(255, x + length), y + rng.choice((-1, 0, 1))), fill=seam)
    return image


def wall_variant_tile(base: Image.Image, mask: int, variant: int, theme: str) -> Image.Image:
    tile = base.copy()
    d = ImageDraw.Draw(tile)
    rng = random.Random(mask * 1009 + variant * 9173 + (21 if theme == "amethyst_depths" else 37))
    south = bool(mask & 4)
    if theme == "amethyst_depths":
        mortar = (28, 28, 44, 255)
        bevel = (77, 70, 96, 255)
        chip = (48, 45, 68, 255)
        metal = (58, 83, 101, 255)
        accent = (77, 170, 184, 255)
        core = (159, 105, 202, 255)
    else:
        mortar = (27, 24, 24, 255)
        bevel = (74, 55, 45, 255)
        chip = (48, 37, 33, 255)
        metal = (55, 50, 48, 255)
        accent = (153, 69, 34, 255)
        core = (235, 119, 31, 255)

    # Keep the outer three pixels from the authored junction tile intact. The
    # interior receives masonry courses so corners and collision silhouettes
    # remain exactly aligned while long walls stop looking like one flat fill.
    courses = (5, 10) if south else (6, 12)
    for course_index, y in enumerate(courses):
        d.line((3, y, 12, y), fill=mortar)
        joint = 6 + ((variant + course_index * 2) % 5)
        d.line((joint, max(3, y - 4), joint, y - 1), fill=mortar)
        if joint + 4 <= 12:
            d.point((joint + 4, y - 1), fill=bevel)
    if south:
        d.line((3, 3, 12, 3), fill=bevel)
        d.line((3, 13, 12, 13), fill=(19, 19, 27, 255) if theme == "amethyst_depths" else (22, 19, 18, 255))

    for _ in range(2 + variant):
        x, y = rng.randrange(4, 12), rng.randrange(4, 13)
        d.point((x, y), fill=chip)
        if rng.random() < 0.45 and x < 11:
            d.point((x + 1, y), fill=mortar)

    if variant == 1:
        # A chipped course catches a small highlight, used on roughly a quarter
        # of world cells by StageEnvironment's deterministic variant selector.
        x = 4 + (mask % 6)
        d.line((x, 8, min(12, x + 3), 7), fill=chip)
        d.point((min(12, x + 3), 7), fill=bevel)
    elif variant == 2:
        if theme == "amethyst_depths":
            x = 6 + (mask % 4)
            d.polygon([(x - 2, 11), (x, 6), (x + 2, 11)], fill=core)
            d.line((x, 7, x, 10), fill=accent)
        else:
            d.line((4, 8, 12, 8), fill=metal, width=2)
            d.point((5, 8), fill=accent)
            d.point((11, 8), fill=accent)
    elif variant == 3:
        if theme == "amethyst_depths":
            d.line((4, 11, 7, 8, 10, 9, 12, 5), fill=accent)
            d.point((7, 8), fill=(151, 224, 219, 255))
            d.point((12, 5), fill=core)
        else:
            d.rectangle((5, 5, 11, 11), outline=metal)
            d.line((6, 10, 10, 6), fill=accent)
            d.point((10, 6), fill=core)
    tile.putalpha(255)
    return tile


def wall_identity(image: Image.Image, theme: str) -> Image.Image:
    if theme == "amethyst_depths":
        wall = recolor(image, (17, 18, 31), (105, 101, 130))
    else:
        wall = recolor(image, (18, 17, 18), (101, 76, 60))
    muted_trim = (35, 37, 50, 255) if theme == "amethyst_depths" else (39, 31, 28, 255)
    source_pixels = list(image.get_flattened_data())
    wall_pixels = list(wall.get_flattened_data())
    for index, source_pixel in enumerate(source_pixels):
        if source_pixel[3] > 0 and source_pixel[0] > source_pixel[2] * 1.28 and source_pixel[0] > 80:
            wall_pixels[index] = muted_trim
    wall.putdata(wall_pixels)
    atlas = Image.new("RGBA", (1024, 256))
    for mask in range(256):
        source = wall.crop(((mask & 15) * 16, (mask >> 4) * 16, (mask & 15) * 16 + 16, (mask >> 4) * 16 + 16))
        for variant in range(4):
            prepared = wall_variant_tile(source, mask, variant, theme)
            atlas.paste(prepared, (((mask & 15) * 4 + variant) * 16, (mask >> 4) * 16))
    return atlas


def wall_overlay_atlas(theme: str) -> Image.Image:
    atlas = Image.new("RGBA", (128, 64))
    d = ImageDraw.Draw(atlas)
    if theme == "amethyst_depths":
        stone, edge, dark = (62, 58, 82, 255), (119, 99, 143, 255), (27, 25, 43, 255)
        cloth, trim, glow = (52, 31, 76, 255), (151, 93, 185, 255), (92, 211, 210, 255)
    else:
        stone, edge, dark = (70, 53, 45, 255), (132, 91, 61, 255), (29, 24, 23, 255)
        cloth, trim, glow = (73, 25, 22, 255), (178, 91, 38, 255), (247, 126, 28, 255)

    # Three two-cell banners. Their whole silhouettes are authored together,
    # then consumed as top/base tile pairs by the existing placement code.
    for column in range(3):
        x0 = column * 16
        d.line((x0 + 2, 3, x0 + 13, 3), fill=edge, width=2)
        d.point((x0 + 1, 3), fill=trim)
        d.point((x0 + 14, 3), fill=trim)
        d.polygon([(x0 + 4, 5), (x0 + 12, 5), (x0 + 12, 25), (x0 + 8, 30), (x0 + 4, 25)], fill=cloth, outline=dark)
        d.line((x0 + 5, 7, x0 + 11, 7), fill=trim)
        if theme == "amethyst_depths" and column == 0:
            d.polygon([(x0 + 8, 10), (x0 + 11, 16), (x0 + 8, 22), (x0 + 5, 16)], outline=trim)
            d.line((x0 + 8, 11, x0 + 8, 21), fill=glow)
        elif theme == "amethyst_depths" and column == 1:
            d.polygon([(x0 + 5, 13), (x0 + 8, 10), (x0 + 11, 13), (x0 + 9, 18), (x0 + 6, 21), (x0 + 8, 16)], fill=trim)
            d.point((x0 + 8, 13), fill=glow)
            d.line((x0 + 6, 23, x0 + 10, 23), fill=edge)
        elif theme == "amethyst_depths":
            d.line((x0 + 5, 20, x0 + 5, 13, x0 + 8, 17, x0 + 11, 12, x0 + 11, 20), fill=trim)
            d.line((x0 + 5, 20, x0 + 11, 20), fill=glow)
            d.point((x0 + 8, 14), fill=(220, 188, 233, 255))
        elif column == 0:
            d.line((x0 + 5, 12, x0 + 11, 20), fill=trim, width=2)
            d.line((x0 + 11, 12, x0 + 5, 20), fill=glow)
        elif column == 1:
            d.polygon([(x0 + 8, 10), (x0 + 11, 16), (x0 + 9, 22), (x0 + 5, 20), (x0 + 7, 16)], fill=trim, outline=glow)
            d.point((x0 + 8, 17), fill=(255, 203, 70, 255))
        else:
            d.polygon([(x0 + 5, 12), (x0 + 8, 9), (x0 + 11, 12), (x0 + 10, 19), (x0 + 6, 19)], fill=trim)
            d.point((x0 + 7, 14), fill=dark)
            d.point((x0 + 9, 14), fill=dark)
            d.line((x0 + 6, 21, x0 + 10, 21), fill=glow)

    # Boss-room pilaster at column 3: carved crystal buttress or riveted iron.
    px = 48
    d.polygon([(px + 5, 1), (px + 11, 1), (px + 13, 5), (px + 11, 30), (px + 5, 30), (px + 3, 5)], fill=stone, outline=dark)
    d.line((px + 5, 4, px + 11, 4), fill=edge)
    d.line((px + 4, 27, px + 12, 27), fill=edge)
    if theme == "amethyst_depths":
        d.polygon([(px + 8, 8), (px + 11, 15), (px + 8, 23), (px + 5, 15)], fill=trim, outline=glow)
    else:
        d.line((px + 5, 9, px + 11, 9), fill=trim, width=2)
        d.line((px + 5, 20, px + 11, 20), fill=trim, width=2)
        for y in (10, 21):
            d.point((px + 6, y), fill=glow)
            d.point((px + 10, y), fill=glow)

    # Small wall grille and rare cage occupy the existing one-cell contracts.
    for column in (4, 5):
        x0 = column * 16
        d.rectangle((x0 + 3, 3, x0 + 12, 14), fill=dark, outline=edge)
        for x in range(x0 + 5, x0 + 12, 3):
            d.line((x, 4, x, 13), fill=trim)
        d.line((x0 + 4, 7, x0 + 11, 7), fill=edge)
        if column == 5:
            d.point((x0 + 8, 11), fill=glow)

    # Two 32px terrain obstacles. They retain the same four-cell footprint and
    # collision contract but now read as architecture from their own map.
    if theme == "amethyst_depths":
        d.ellipse((2, 51, 29, 62), fill=dark, outline=edge)
        d.polygon([(7, 54), (11, 36), (16, 31), (21, 36), (25, 54)], fill=stone, outline=edge)
        d.polygon([(12, 52), (16, 36), (20, 52)], fill=trim, outline=glow)
        d.line((16, 38, 16, 50), fill=(180, 229, 225, 255))
        d.ellipse((35, 37, 61, 62), fill=stone, outline=edge, width=2)
        d.ellipse((40, 42, 56, 58), fill=dark, outline=trim)
        d.polygon([(48, 43), (53, 50), (48, 57), (43, 50)], outline=glow)
    else:
        d.rectangle((3, 39, 29, 60), fill=dark, outline=edge)
        d.polygon([(7, 39), (11, 34), (21, 34), (25, 39)], fill=stone, outline=trim)
        d.rectangle((9, 45, 23, 57), fill=(65, 34, 27, 255), outline=edge)
        d.rectangle((12, 48, 20, 55), fill=(190, 54, 20, 255))
        d.rectangle((14, 48, 18, 52), fill=glow)
        d.ellipse((35, 36, 61, 62), fill=stone, outline=edge, width=2)
        d.ellipse((41, 42, 55, 56), fill=dark, outline=trim, width=2)
        for x, y in ((48, 34), (48, 62), (34, 48), (62, 48)):
            d.rectangle((x - 2, y - 2, x + 2, y + 2), fill=edge)
        d.line((43, 53, 53, 43), fill=glow, width=2)
    return atlas


def crystal_cluster(variant: int) -> Image.Image:
    image = Image.new("RGBA", (48, 48))
    d = ImageDraw.Draw(image)
    dark, shadow = (41, 28, 62), (24, 23, 40)
    mid, light, core = (112, 55, 159), (185, 99, 221), (102, 224, 221)
    d.ellipse((5, 37, 43, 45), fill=shadow)
    if variant == 2:
        d.polygon([(13, 38), (16, 13), (23, 6), (31, 13), (35, 38)], fill=(52, 48, 72), outline=(122, 104, 151))
        d.rectangle((17, 17, 31, 34), outline=(88, 68, 113))
        d.polygon([(21, 29), (24, 18), (28, 28), (24, 34)], fill=mid, outline=light)
        d.line((24, 19, 24, 31), fill=core)
        d.rectangle((10, 37, 38, 41), fill=(45, 39, 59), outline=(87, 68, 103))
        return image
    if variant == 3:
        d.line((7, 35, 39, 35), fill=(76, 70, 79), width=2)
        d.line((12, 40, 36, 40), fill=(51, 47, 55), width=2)
        d.rectangle((12, 22, 36, 35), fill=(55, 49, 63), outline=(111, 91, 121))
        d.polygon([(15, 22), (20, 11), (25, 23)], fill=mid, outline=light)
        d.polygon([(23, 23), (29, 8), (34, 23)], fill=dark, outline=light)
        d.line((20, 14, 20, 21), fill=core)
        for x in (16, 32):
            d.ellipse((x - 4, 34, x + 4, 42), fill=(30, 29, 36), outline=(98, 85, 105))
        return image
    layouts = [
        [(8, 38, 16, 17), (15, 40, 25, 5), (24, 40, 33, 13), (31, 41, 40, 23)],
        [(6, 40, 15, 25), (13, 41, 22, 10), (22, 41, 32, 18), (31, 41, 42, 29)],
    ][variant]
    for index, (x1, y1, x2, y2) in enumerate(layouts):
        color = mid if index % 2 == 0 else dark
        d.polygon([(x1, y1), ((x1 + x2) // 2, y2), (x2, y1)], fill=color, outline=light)
        d.line((((x1 + x2) // 2, y2 + 3), ((x1 + x2) // 2, y1 - 2)), fill=core)
    d.line((7, 41, 41, 41), fill=(76, 55, 91), width=2)
    return image


def forge_prop(variant: int) -> Image.Image:
    image = Image.new("RGBA", (48, 48))
    d = ImageDraw.Draw(image)
    shadow = (20, 19, 20)
    iron, edge, brass = (54, 47, 44), (111, 86, 68), (155, 94, 45)
    hot, core = (211, 56, 19), (255, 177, 42)
    d.ellipse((5, 38, 43, 45), fill=shadow)
    if variant == 0:
        d.rectangle((9, 25, 39, 40), fill=iron, outline=edge)
        d.polygon([(13, 25), (18, 13), (30, 13), (35, 25)], fill=(43, 38, 38), outline=brass)
        d.rectangle((17, 19, 31, 28), fill=hot)
        d.rectangle((20, 19, 28, 24), fill=core)
    elif variant == 1:
        d.polygon([(8, 20), (35, 20), (42, 25), (34, 29), (27, 29), (25, 39), (15, 39), (17, 28), (10, 26)], fill=iron, outline=edge)
        d.line((11, 21, 35, 21), fill=(156, 126, 96), width=2)
    elif variant == 2:
        d.ellipse((7, 15, 31, 39), fill=iron, outline=brass, width=2)
        d.ellipse((13, 21, 25, 33), outline=edge, width=2)
        d.ellipse((25, 24, 42, 41), fill=(43, 38, 37), outline=edge, width=2)
        for angle in range(0, 8, 2):
            d.rectangle((17 + angle, 11 + (angle % 4), 20 + angle, 17 + (angle % 4)), fill=brass)
    else:
        d.rectangle((14, 13, 34, 40), fill=iron, outline=edge)
        d.rectangle((11, 9, 37, 15), fill=(42, 36, 35), outline=brass)
        d.rectangle((19, 22, 29, 37), fill=(87, 37, 27))
        d.line((21, 34, 27, 25), fill=hot, width=2)
        d.point((27, 25), fill=core)
    return image


def prop_sheet(theme: str) -> Image.Image:
    sheet = Image.new("RGBA", (48 * 4, 48))
    for variant in range(4):
        prop = crystal_cluster(variant) if theme == "amethyst_depths" else forge_prop(variant)
        sheet.alpha_composite(prop, (variant * 48, 0))
    return sheet


def ground_detail_pattern(theme: str, variant: int) -> Image.Image:
    image = Image.new("RGBA", (32, 32))
    d = ImageDraw.Draw(image)
    rng = random.Random(1701 + variant + (0 if theme == "amethyst_depths" else 100))
    if theme == "amethyst_depths":
        muted, accent, bright = (72, 59, 94, 150), (69, 157, 174, 205), (128, 221, 220, 220)
        if variant in (0, 1):
            path = [(0, 24), (7, 20), (13, 22), (19, 15), (25, 17), (32, 11)] if variant == 0 else [(5, 0), (7, 8), (14, 12), (12, 20), (20, 32)]
            d.line(path, fill=accent)
            for point in path[1:-1:2]:
                d.point(point, fill=bright)
        elif variant in (2, 3):
            for _ in range(12):
                x, y = rng.randrange(2, 28), rng.randrange(3, 27)
                d.polygon([(x, y + 3), (x + 2, y), (x + 4, y + 3)], fill=muted)
        elif variant in (4, 5):
            d.ellipse((3, 9, 29, 25), fill=(37, 79, 96, 110), outline=accent)
            d.arc((7, 12, 25, 22), 190, 335, fill=bright)
        else:
            d.arc((4, 4, 28, 28), 200, 344, fill=muted, width=2)
            d.line((8, 24, 24, 8), fill=accent)
    else:
        muted, accent, bright = (91, 65, 53, 155), (166, 54, 24, 220), (255, 137, 34, 235)
        if variant in (0, 1, 2):
            paths = [
                [(0, 23), (8, 18), (12, 20), (19, 10), (24, 13), (32, 7)],
                [(4, 0), (6, 9), (13, 13), (11, 21), (19, 32)],
                [(0, 8), (9, 11), (15, 18), (22, 17), (32, 25)],
            ]
            d.line(paths[variant], fill=accent, width=2)
            for point in paths[variant][1:-1:2]:
                d.point(point, fill=bright)
        elif variant in (3, 4):
            d.rectangle((3, 6, 29, 26), fill=(31, 29, 30, 150), outline=muted)
            for x in range(6, 29, 5):
                d.line((x, 7, x, 25), fill=(111, 79, 57, 170))
            d.line((4, 10, 28, 10), fill=(143, 81, 42, 180))
        elif variant == 5:
            for _ in range(14):
                x, y = rng.randrange(3, 27), rng.randrange(4, 27)
                d.rectangle((x, y, x + 2, y + 1), fill=muted)
        else:
            d.arc((4, 4, 28, 28), 0, 355, fill=muted, width=2)
            for x, y in ((8, 8), (24, 8), (8, 24), (24, 24)):
                d.ellipse((x - 1, y - 1, x + 1, y + 1), fill=bright)
    return image


def ground_detail_atlas(theme: str) -> Image.Image:
    atlas = Image.new("RGBA", (128, 64))
    for variant in range(8):
        x = (variant % 4) * 32
        y = (variant // 4) * 32
        atlas.alpha_composite(ground_detail_pattern(theme, variant), (x, y))
    return atlas


def torch_sheet(theme: str) -> Image.Image:
    sheet = Image.new("RGBA", (96, 24))
    for frame in range(6):
        tile = Image.new("RGBA", (16, 24))
        d = ImageDraw.Draw(tile)
        if theme == "amethyst_depths":
            d.rectangle((7, 11, 9, 21), fill=(93, 91, 111))
            d.rectangle((5, 19, 11, 22), fill=(45, 43, 60))
            outer, inner = (72, 91, 197), (104, 228, 226)
        else:
            d.rectangle((7, 11, 9, 21), fill=(111, 79, 53))
            d.rectangle((5, 19, 11, 22), fill=(55, 39, 31))
            outer, inner = (217, 60, 16), (255, 181, 36)
        shift = (frame % 3) - 1
        d.polygon([(8, 12), (4 + shift, 8), (7, 1), (11 + shift, 7), (10, 11)], fill=outer)
        d.polygon([(8, 10), (6 + shift, 7), (8, 3), (9 + shift, 8)], fill=inner)
        sheet.alpha_composite(tile, (frame * 16, 0))
    return sheet


def build_theme(source_root: Path, output_root: Path, theme: str) -> None:
    source = source_root / "assets" / "tiles" / "royal"
    destination = output_root / theme
    destination.mkdir(parents=True, exist_ok=True)
    base = Image.open(source / "dungeon_atlas.png").convert("RGBA")
    atlas, floors = theme_atlas(base, theme)
    atlas.save(destination / "dungeon_atlas.png")
    macro_floor(base, theme).save(destination / "floor_macro.png")
    combat_size = Image.open(source / "combat_atlas.png").size
    theme_combat(combat_size, floors, theme).save(destination / "combat_atlas.png")
    wall_identity(Image.open(source / "wall_relief.png").convert("RGBA"), theme).save(destination / "wall_relief.png")
    wall_overlay_atlas(theme).save(destination / "wall_overlays.png")
    if theme == "amethyst_depths":
        recolor(Image.open(source / "boss_floor_border.png").convert("RGBA"), (39, 31, 57), (169, 130, 191), (80, 193, 198)).save(destination / "boss_floor_border.png")
        recolor(Image.open(source / "boss_floor_seal.png").convert("RGBA"), (43, 30, 62), (177, 120, 203), (85, 208, 208)).save(destination / "boss_floor_seal.png")
        recolor(Image.open(source / "royal_inlay.png").convert("RGBA"), (41, 28, 58), (170, 119, 198), (86, 211, 210)).save(destination / "royal_inlay.png")
    else:
        recolor(Image.open(source / "boss_floor_border.png").convert("RGBA"), (36, 27, 24), (157, 98, 58), (218, 91, 30)).save(destination / "boss_floor_border.png")
        recolor(Image.open(source / "boss_floor_seal.png").convert("RGBA"), (41, 25, 20), (170, 82, 38), (237, 91, 25)).save(destination / "boss_floor_seal.png")
        recolor(Image.open(source / "royal_inlay.png").convert("RGBA"), (38, 26, 22), (158, 86, 45), (226, 96, 29)).save(destination / "royal_inlay.png")
    prop_sheet(theme).save(destination / "crystal.png")
    ground_detail_atlas(theme).save(destination / "ground_details.png")
    torch_sheet(theme).save(destination / "torch_6f.png")


def preview(output_root: Path) -> None:
    canvas = Image.new("RGBA", (864, 432), (7, 8, 12, 255))
    for theme_index, theme in enumerate(("amethyst_depths", "ruin_forge")):
        folder = output_root / theme
        atlas = Image.open(folder / "dungeon_atlas.png").convert("RGBA")
        macro = Image.open(folder / "floor_macro.png").convert("RGBA")
        wall = Image.open(folder / "wall_relief.png").convert("RGBA")
        props = Image.open(folder / "crystal.png").convert("RGBA")
        details = Image.open(folder / "ground_details.png").convert("RGBA")
        torch = Image.open(folder / "torch_6f.png").convert("RGBA").crop((0, 0, 16, 24))
        ox = theme_index * 432
        for y in range(4, 23):
            for x in range(1, 26):
                sx, sy = (x % 16) * 16, (y % 16) * 16
                tile = macro.crop((sx, sy, sx + 16, sy + 16))
                put_tile(canvas, tile, (x + ox // 16, y))
        for x in range(1, 26):
            wall_x = (4 * 4 + x % 4) * 16
            wall_tile = wall.crop((wall_x, 0, wall_x + 16, 16))
            put_tile(canvas, wall_tile, (x + ox // 16, 3))
            put_tile(canvas, wall_tile, (x + ox // 16, 23))
        canvas.alpha_composite(details, (ox + 128, 144))
        for index, (x, y) in enumerate(((4, 8), (17, 14), (8, 18))):
            prop = props.crop((index * 48, 0, index * 48 + 48, 48))
            canvas.alpha_composite(prop, (ox + x * 16, y * 16))
        for x in (4, 12, 20):
            canvas.alpha_composite(torch.resize((32, 48), Image.Resampling.NEAREST), (ox + x * 16, 48))
    canvas.save(output_root / "map_theme_asset_preview.png")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: build_map_themes.py SOURCE_REPO OUTPUT_DIR")
    source_root = Path(sys.argv[1])
    output_root = Path(sys.argv[2])
    for theme in ("amethyst_depths", "ruin_forge"):
        build_theme(source_root, output_root, theme)
    preview(output_root)
    print("MAP_THEME_ASSETS_V3 PASS: layered floors + four wall variants + bespoke architecture overlays")


if __name__ == "__main__":
    main()
