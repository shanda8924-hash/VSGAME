"""Export untouched Minotaur body/fx pixels from the authored Aseprite layers.

The original file has RGBA, normal-blend, opaque layers and raw/compressed cels.
This deliberately supports that source format, not arbitrary Aseprite documents.
No resampling, palette changes, redrawing, or edits to the original files occur.
Import load_source_layers() for in-memory 100x100 body/fx frames in the same
coordinate system as the original sheets. The CLI exports eight PNG strips.
"""
from __future__ import annotations

import struct
import zlib
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "assets/sprites/boss/Minotaur"
SOURCE = SOURCE_DIR / "Minotaur.aseprite"
OUTPUT = SOURCE_DIR / "hd2d/source_edit/layers"
ANIMATIONS = {"idle": "Idle", "attack1": "Attack01", "attack2": "Attack02", "attack3": "Attack03"}


def _decode_source(path: Path) -> tuple[tuple[int, int], list[str], list[dict[int, Image.Image]], dict[str, tuple[int, int]]]:
    data = path.read_bytes()

    def u16(offset: int) -> int:
        return struct.unpack_from("<H", data, offset)[0]

    def u32(offset: int) -> int:
        return struct.unpack_from("<I", data, offset)[0]

    def text(offset: int) -> str:
        length = u16(offset)
        return data[offset + 2:offset + 2 + length].decode("utf-8")

    assert u32(0) == len(data) and u16(4) == 0xA5E0, "Not the expected complete Aseprite source"
    assert u16(12) == 32, "Only authored RGBA source is supported"
    size = (u16(8), u16(10))
    layers: list[str] = []
    frames: list[dict[int, Image.Image]] = []
    tags: dict[str, tuple[int, int]] = {}
    offset = 128
    for _frame_index in range(u16(6)):
        frame_end = offset + u32(offset)
        assert u16(offset + 4) == 0xF1FA and frame_end <= len(data), "Invalid frame header"
        chunk_count = u32(offset + 12) if u16(offset + 6) == 0xFFFF else u16(offset + 6)
        chunk_offset = offset + 16
        frame: dict[int, Image.Image] = {}
        for _chunk in range(chunk_count):
            chunk_end = chunk_offset + u32(chunk_offset)
            assert chunk_offset + 6 <= chunk_end <= frame_end, "Truncated source chunk"
            kind = u16(chunk_offset + 4)
            payload = chunk_offset + 6
            if kind == 0x2004:  # Layer declaration.
                assert u16(payload + 2) == 0 and u16(payload + 4) == 0, "Unexpected grouped/tile layer"
                assert u16(payload + 10) == 0 and data[payload + 12] == 255, "Unexpected layer blend/opacity"
                layers.append(text(payload + 16))
            elif kind == 0x2005:  # Cel, positioned in the full original canvas.
                layer = u16(payload)
                x, y = struct.unpack_from("<hh", data, payload + 2)
                assert data[payload + 6] == 255 and u16(payload + 9) == 0, "Unexpected cel opacity/z-index"
                cel_kind = u16(payload + 7)
                assert cel_kind in (0, 2), "Unexpected linked/tile cel in authored source"
                width, height = u16(payload + 16), u16(payload + 18)
                pixels = data[payload + 20:chunk_end]
                if cel_kind == 2:
                    pixels = zlib.decompress(pixels)
                assert len(pixels) == width * height * 4, "Incorrect RGBA cel byte count"
                cel = Image.frombytes("RGBA", (width, height), pixels)
                canvas = Image.new("RGBA", size)
                canvas.paste(cel, (x, y))
                frame[layer] = canvas
            elif kind == 0x2018:  # Animation tags, inclusive source-frame indices.
                tag_offset = payload + 10
                for _tag in range(u16(payload)):
                    name = text(tag_offset + 17)
                    assert data[tag_offset + 4] == 0, "Unexpected reverse/ping-pong source tag"
                    tags[name] = (u16(tag_offset), u16(tag_offset + 2))
                    tag_offset += 19 + u16(tag_offset + 17)
            chunk_offset = chunk_end
        assert chunk_offset == frame_end, "Unconsumed source-frame data"
        frames.append(frame)
        offset = frame_end
    assert offset == len(data), "Unconsumed source-file data"
    return size, layers, frames, tags


def load_source_layers(path: Path = SOURCE) -> dict[str, dict[str, list[Image.Image]]]:
    """Return exact original body/fx frames; verify their composite against PNGs.

    Weapon, hands, horns and body are originally one `body` layer. The white
    attack effect is a separate `fx` layer and can be omitted without repainting.
    Missing fx cels are represented by transparent, full-canvas images.
    """
    size, layers, frames, tags = _decode_source(path)
    assert size == (100, 100) and layers == ["shadow", "body", "fx"], "Unexpected source layout"
    result: dict[str, dict[str, list[Image.Image]]] = {}
    for name, source_tag in ANIMATIONS.items():
        start, end = tags[source_tag]
        clips: dict[str, list[Image.Image]] = {"body": [], "fx": []}
        reference_path = path.parent / "Minotaur" / f"Minotaur_{source_tag}.png"
        with Image.open(reference_path) as source_png:
            reference = source_png.convert("RGBA")
        assert reference.size == (size[0] * (end - start + 1), size[1]), f"{source_tag}: source sheet size mismatch"
        for local_index, source_index in enumerate(range(start, end + 1)):
            for layer_name in clips:
                index = layers.index(layer_name)
                clips[layer_name].append(frames[source_index].get(index, Image.new("RGBA", size)).copy())
            composite = Image.alpha_composite(clips["body"][-1], clips["fx"][-1])
            expected = reference.crop((local_index * size[0], 0, (local_index + 1) * size[0], size[1]))
            assert composite.tobytes() == expected.tobytes(), f"{source_tag} frame {local_index}: extracted body+fx differs from original no-shadow PNG"
        result[name] = clips
    return result


def export_layers(output: Path = OUTPUT) -> list[Path]:
    clips = load_source_layers()
    output.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for animation, layers in clips.items():
        for layer_name, frames in layers.items():
            strip = Image.new("RGBA", (100 * len(frames), 100))
            for index, frame in enumerate(frames):
                strip.paste(frame, (100 * index, 0))
            path = output / f"minotaur_{animation}_{layer_name}.png"
            strip.save(path, optimize=False, compress_level=9)
            written.append(path)
    return written


if __name__ == "__main__":
    for exported in export_layers():
        print(exported.relative_to(ROOT).as_posix())
    print("Verified 28 source frames: extracted body + fx exactly equals original no-shadow PNGs.")
