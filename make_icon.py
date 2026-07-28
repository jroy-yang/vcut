"""Generate vcut.ico from scratch — pure Python stdlib (no PIL/anything).

Design: dark navy (#1a3a8a) background with white film-strip-on-left
and white play-triangle-on-right. Produces 6 sizes (16/32/48/64/128/256)
embedded in a single .ico file as 32-bit BGRA BMPs (no AND mask needed).

Run:  python make_icon.py
Out:  ./vcut.ico
"""
from __future__ import annotations

import struct
import zlib
from pathlib import Path

# BG = navy #1a3a8a, RGBA byte order
BG = (0x1A, 0x3A, 0x8A, 0xFF)
WHITE = (0xFF, 0xFF, 0xFF, 0xFF)

# For 32-bit BMP (ICO): pixels are stored as BGRA, so we swap R<->B.
def _bgra(rgba): return (rgba[2], rgba[1], rgba[0], rgba[3])

SIZES = (16, 32, 48, 64, 128, 256)


def _in_triangle(px: float, py: float, tri: list[tuple[float, float]]) -> bool:
    """Barycentric inside-test for a 3-point triangle."""
    (x1, y1), (x2, y2), (x3, y3) = tri
    d1 = (px - x2) * (y1 - y2) - (x1 - x2) * (py - y2)
    d2 = (px - x3) * (y2 - y3) - (x2 - x3) * (py - y3)
    d3 = (px - x1) * (y3 - y1) - (x3 - x1) * (py - y1)
    has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (has_neg and has_pos)


def render_icon(size: int) -> bytes:
    """Return raw BGRA pixel data for the icon at the given size, bottom-up."""
    cx = size / 2
    cy = size / 2
    # Play triangle: pointing right, slightly off-center
    tri = [
        (cx + size * 0.05, cy - size * 0.32),  # top
        (cx + size * 0.05, cy + size * 0.32),  # bottom-left
        (cx + size * 0.38, cy),                 # right point
    ]
    # Film strip on the left
    strip_x1 = int(size * 0.10)
    strip_x2 = int(size * 0.30)
    strip_y1 = int(size * 0.25)
    strip_y2 = int(size * 0.75)
    strip_h = strip_y2 - strip_y1
    frame_h = max(1, strip_h // 4)

    def in_strip_hole(px: int, py: int) -> bool:
        if not (strip_x1 <= px < strip_x2 and strip_y1 <= py < strip_y2):
            return False
        rel_y = py - strip_y1
        for i in range(3):
            hole_y = (i + 1) * frame_h
            if hole_y <= rel_y < hole_y + frame_h:
                return True
        return False

    rows: list[bytes] = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            if in_strip_hole(x, y):
                row.extend(_bgra(BG))
            elif _in_triangle(x + 0.5, y + 0.5, tri) or (strip_x1 <= x < strip_x2 and strip_y1 <= y < strip_y2):
                row.extend(_bgra(WHITE))
            else:
                row.extend(_bgra(BG))
        rows.append(bytes(row))
    # BMP-in-ICO is bottom-up
    return b"".join(reversed(rows))


def _bmp_payload(size: int, pixels_bottom_up: bytes) -> bytes:
    """Wrap raw BGRA data into a BITMAPINFOHEADER (no AND mask)."""
    bih = struct.pack(
        "<IIIHHIIIIII",
        40,             # biSize
        size,           # biWidth
        size,           # biHeight (= actual height; no AND mask for 32bpp)
        1,              # biPlanes
        32,             # biBitCount
        0,              # biCompression (BI_RGB)
        0,              # biSizeImage
        0,              # biXPelsPerMeter
        0,              # biYPelsPerMeter
        0,              # biClrUsed
        0,              # biClrImportant
    )
    return bih + pixels_bottom_up


def build_ico(sizes: tuple[int, ...], out_path: Path) -> None:
    entries: list[tuple[int, int, bytes]] = []  # (width, height, bmp_payload)
    for s in sizes:
        px = render_icon(s)
        entries.append((s, s, _bmp_payload(s, px)))

    # ICONDIR (6 bytes): reserved=0, type=1 (icon), count=N
    icondir = struct.pack("<HHH", 0, 1, len(entries))

    # Compute offsets
    dir_size = 16 * len(entries)
    offset = 6 + dir_size
    dir_bytes = b""
    payloads = b""
    for w, h, payload in entries:
        # 0 means 256 in the 1-byte width/height fields
        w_byte = 0 if w == 256 else w
        h_byte = 0 if h == 256 else h
        dir_bytes += struct.pack(
            "<BBBBHHII",
            w_byte, h_byte,  # width, height
            0, 0,            # color count, reserved
            1, 32,           # planes, bpp
            len(payload),    # bytes in resource
            offset,          # offset from start of file
        )
        payloads += payload
        offset += len(payload)

    out_path.write_bytes(icondir + dir_bytes + payloads)
    print(f"[icon] wrote {out_path}  ({out_path.stat().st_size:,} bytes, {len(sizes)} sizes)")


def build_png_preview(size: int, out_path: Path) -> None:
    """Write a single PNG (top-down RGBA) using stdlib zlib, for README preview."""
    # Render top-down
    pixels_topdown = bytearray()
    cx = size / 2
    cy = size / 2
    tri = [
        (cx + size * 0.05, cy - size * 0.32),
        (cx + size * 0.05, cy + size * 0.32),
        (cx + size * 0.38, cy),
    ]
    strip_x1 = int(size * 0.10)
    strip_x2 = int(size * 0.30)
    strip_y1 = int(size * 0.25)
    strip_y2 = int(size * 0.75)
    strip_h = strip_y2 - strip_y1
    frame_h = max(1, strip_h // 4)

    for y in range(size):
        pixels_topdown.append(0)  # filter byte: None
        for x in range(size):
            in_hole = False
            if strip_x1 <= x < strip_x2 and strip_y1 <= y < strip_y2:
                rel_y = y - strip_y1
                for i in range(3):
                    hole_y = (i + 1) * frame_h
                    if hole_y <= rel_y < hole_y + frame_h:
                        in_hole = True
                        break
            in_tri = _in_triangle(x + 0.5, y + 0.5, tri)
            in_strip = strip_x1 <= x < strip_x2 and strip_y1 <= y < strip_y2
            # PNG uses RGBA byte order; BG tuple is already (R, G, B, A)
            color = BG if (in_hole or not (in_tri or in_strip)) else WHITE
            pixels_topdown.extend(color)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)  # 8-bit RGBA
    idat = zlib.compress(bytes(pixels_topdown), level=9)
    iend = b""

    out_path.write_bytes(sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", iend))
    print(f"[icon] wrote PNG preview {out_path}  ({out_path.stat().st_size:,} bytes)")


if __name__ == "__main__":
    here = Path(__file__).parent
    build_ico(SIZES, here / "vcut.ico")
    build_png_preview(512, here / "vcut-icon-preview.png")