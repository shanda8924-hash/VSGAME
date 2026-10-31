"""Deterministic editing of original Minotaur pixels; never AI redraw the actor."""
from pathlib import Path
from PIL import Image, ImageDraw
import hashlib
import json
from export_minotaur_source_layers import load_source_layers

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/sprites/boss/Minotaur/Minotaur'
OUT = ROOT / 'assets/sprites/boss/Minotaur/hd2d/source_edit'
ART = ROOT / 'artifacts/hd2d_source_motion'


def source_parts(layers):
    original = layers['idle']['body'][0]
    mask = Image.new('L', (100, 100))
    ImageDraw.Draw(mask).polygon([(40, 51), (61, 51), (61, 52), (64, 52),
        (64, 53), (71, 53), (71, 55), (70, 55), (70, 57), (68, 58),
        (55, 58), (55, 56), (57, 55), (60, 54), (56, 54), (56, 53), (40, 53)], fill=255)
    weapon = Image.new('RGBA', (100, 100))
    weapon.paste(original, (0, 0), mask)
    steel = {original.getpixel((x, y)) for x in range(60, 71) for y in range(51, 58)}
    steel.update(original.getpixel((x, 52)) for x in range(41, 46))
    # Exclude the red loincloth/skin caught where the source shaft crosses it.
    for y in range(100):
        for x in range(100):
            if weapon.getpixel((x, y)) not in steel:
                weapon.putpixel((x, y), (0, 0, 0, 0))
    body = original.copy()
    body.paste((0, 0, 0, 0), (0, 0, 100, 100), mask)
    body.paste((0, 0, 0, 0), (60, 50, 74, 60))
    # Recover the two legs and loincloth hidden behind the original horizontal
    # handle from a source frame in which the weapon is raised. No repainting.
    leg_rect = (44, 51, 56, 59)
    body.paste(layers['attack1']['body'][0].crop(leg_rect), leg_rect[:2])
    # The inner blade edge used to remain beside the boot as a static 3px chip.
    # These pixels belong to the rotating weapon, not to the torso or leg patch.
    for point in [(57, 55), (58, 55), (59, 55)]:
        assert body.getpixel(point)[3] == 0, 'Weapon edge leaked into body cutout'
        assert weapon.getpixel(point) == original.getpixel(point), 'Original blade edge lost'
    assert body.crop((39, 37, 65, 50)).tobytes() == original.crop((39, 37, 65, 50)).tobytes(), 'Original head/armor changed'
    # A clean connected body must not contain another detached weapon fragment.
    visible = {(x, y) for y in range(100) for x in range(100) if body.getpixel((x, y))[3]}
    pending = [visible.pop()]
    while pending:
        x, y = pending.pop()
        for dx, dy in [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]:
            neighbor = (x + dx, y + dy)
            if neighbor in visible:
                visible.remove(neighbor)
                pending.append(neighbor)
    assert not visible, 'Detached pixels remain in body cutout'
    weapon.save(OUT / 'original_weapon_cutout.png')
    body.save(OUT / 'original_body_cutout.png')
    return body, weapon


def build_motion():
    OUT.mkdir(parents=True, exist_ok=True)
    ART.mkdir(parents=True, exist_ok=True)
    layers = load_source_layers()
    # Keep the old decomposition as provenance/debug evidence, but the live
    # cleave no longer rotates a detached weapon. The authored Attack01 body
    # already moves grip, forearms, shoulders and torso together with the blade.
    source_parts(layers)
    authored_frames = layers['attack1']['body']
    assert len(authored_frames) == 8
    upper_body_poses = {frame.crop((38, 38, 62, 57)).tobytes() for frame in authored_frames}
    assert len(upper_body_poses) >= 6, 'Authored cleave must move hands, arms and torso'
    palette = {pixel for channel in layers.values() for frame in channel['body']
        for pixel in frame.get_flattened_data() if pixel[3]}
    gallery = Image.new('RGBA', (1600, 750), '#29333d')
    drawn = ImageDraw.Draw(gallery)
    all_frames = {}
    for row, name in enumerate(['side', 'back', 'front']):
        frames = []
        # Three anticipation, three active and two follow-through frames. The
        # separate white source fx is intentionally omitted because the shared
        # 3D crescent owns the visual footprint and the authoritative hit.
        for i, source_frame in enumerate(authored_frames):
            frame = source_frame.copy()
            assert frame.tobytes() == source_frame.tobytes()
            assert {p for p in frame.get_flattened_data() if p[3]} <= palette
            frames.append(frame)
            tile = frame.crop((25, 25, 85, 75)).resize((192, 160), Image.Resampling.NEAREST)
            gallery.alpha_composite(tile, (i * 200, row * 200 + 32))
            drawn.text((i * 200 + 4, row * 200 + 8), f'{name} {i}', fill='white')
        sheet = Image.new('RGBA', (800, 100))
        for i, frame in enumerate(frames):
            sheet.alpha_composite(frame, (i * 100, 0))
        sheet.save(OUT / f'minotaur_cleave_{name}_8f.png')
        all_frames[name] = frames
    old = layers['idle']['body'][0].crop((25, 25, 85, 75)).resize((192, 160), Image.Resampling.NEAREST)
    gallery.alpha_composite(old, (0, 580))
    drawn.text((210, 650), 'ORIGINAL pixels / source parts only / no AI-redrawn actor', fill='white')
    gallery.save(ART / 'source_motion_comparison.png')
    animation = []
    for frame in all_frames['side']:
        view = Image.new('RGBA', (600, 275), '#29333d')
        view.alpha_composite(layers['idle']['body'][0].crop((25, 25, 85, 75)).resize((300, 250), Image.Resampling.NEAREST), (0, 25))
        view.alpha_composite(frame.crop((25, 25, 85, 75)).resize((300, 250), Image.Resampling.NEAREST), (300, 25))
        labels = ImageDraw.Draw(view)
        labels.text((115, 15), 'ORIGINAL', fill='white')
        labels.text((412, 15), 'SOURCE EDIT', fill='white')
        animation.append(view.convert('RGB'))
    animation[0].save(ART / 'source_cleave_preview.gif', save_all=True,
        append_images=animation[1:], duration=[180, 200, 670, 60, 60, 60, 220, 400], loop=0)
    previous_motion = ART / 'before_full_body_motion_side_8f.png'
    if previous_motion.exists():
        old_sheet = Image.open(previous_motion).convert('RGBA')
        comparison = Image.new('RGBA', (1600, 420), '#29333d')
        labels = ImageDraw.Draw(comparison)
        labels.text((315, 8), 'BEFORE: detached weapon rotation', fill='white')
        labels.text((1115, 8), 'AFTER: authored hand / arm / shoulder / torso motion', fill='white')
        for index in range(8):
            before = old_sheet.crop((index * 100 + 32, 32, index * 100 + 78, 64))
            after = all_frames['side'][index].crop((32, 32, 78, 64))
            comparison.alpha_composite(before.resize((184, 128), Image.Resampling.NEAREST), (index * 200 + 8, 38))
            comparison.alpha_composite(after.resize((184, 128), Image.Resampling.NEAREST), (index * 200 + 8, 238))
            labels.text((index * 200 + 8, 174), str(index), fill='white')
        comparison.save(ART / 'full_body_motion_comparison.png')
    # Keep a close-up of the reported held pose beside its pre-fix counterpart.
    previous = ART / 'before_cleanup_side_8f.png'
    if previous.exists():
        before = Image.open(previous).convert('RGBA').crop((200, 0, 300, 100))
        comparison = Image.new('RGBA', (680, 270), '#29333d')
        labels = ImageDraw.Draw(comparison)
        for index, (label, frame) in enumerate([('BEFORE', before), ('AFTER', all_frames['side'][2])]):
            comparison.alpha_composite(frame.crop((36, 35, 76, 63)).resize((320, 224), Image.Resampling.NEAREST), (index * 340 + 10, 34))
            labels.text((index * 340 + 140, 12), label, fill='white')
        comparison.save(ART / 'weapon_edge_cleanup.png')
    provenance = {
        'method': 'Exact eight authored Attack01 body frames from the native Aseprite; white source fx omitted; no detached-weapon transform and no image generation',
        'source': 'assets/sprites/boss/Minotaur/Minotaur.aseprite',
        'source_sha256': hashlib.sha256((SOURCE.parent / 'Minotaur.aseprite').read_bytes()).hexdigest(),
        'limitations': 'Original three-quarter authored body clip is preserved for every heading; front/back labels select the world-space crescent, NOT newly drawn character views.',
        'palette_subset_asserted': True,
        'full_body_articulation': 'Grip, forearms, shoulders and torso use the original Attack01 animation in all eight frames; the weapon is never animated independently.',
        'legacy_weapon_edge_cleanup': 'The retained decomposition reference assigns inner blade contour (57..59,55) to the weapon and keeps one connected body.',
    }
    (OUT / 'provenance.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Prepared source-authored 3 x 8 frames; hand/arm/shoulder/torso motion and exact source pixels verified.')


def original_gallery():
    ART.mkdir(parents=True, exist_ok=True)
    gallery = Image.new('RGBA', (1600, 880), '#29333d')
    draw = ImageDraw.Draw(gallery)
    for row, name in enumerate(['Idle', 'Attack01', 'Attack02', 'Attack03']):
        source = Image.open(SOURCE / f'Minotaur_{name}.png').convert('RGBA')
        for i in range(source.width // 100):
            frame = source.crop((i * 100 + 20, 15, i * 100 + 90, 80))
            gallery.alpha_composite(frame.resize((196, 182), Image.Resampling.NEAREST), (i * 200, row * 220 + 24))
            draw.text((i * 200 + 8, row * 220 + 6), f'{name} {i}', fill='white')
    gallery.save(ART / 'original_frames.png')
    image = Image.open(SOURCE / 'Minotaur_Idle.png').convert('RGBA')
    grid = Image.new('RGBA', (640, 480), '#29333d')
    grid.alpha_composite(image.crop((36, 35, 76, 63)).resize((600, 420), Image.Resampling.NEAREST), (30, 30))
    pen = ImageDraw.Draw(grid)
    for x in range(41):
        pen.line((30+x*15, 30, 30+x*15, 450), fill='#46515b')
        if x%2==0: pen.text((30+x*15, 10), str(36+x), fill='white')
    for y in range(29):
        pen.line((30, 30+y*15, 630, 30+y*15), fill='#46515b')
        pen.text((5, 30+y*15), str(35+y), fill='white')
    grid.save(ART / 'source_grid.png')


if __name__ == '__main__':
    original_gallery()
    build_motion()
