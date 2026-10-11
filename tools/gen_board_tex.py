"""一次性生成棋盘系第二批的两张像素贴图（花障 / 香雾）。纯 stdlib，无第三方依赖。
用法: python tools/gen_board_tex.py
产物: assets/art/tiles/obstacle_flower.png, assets/art/tiles/smoke_fog.png（84x84，8x8 像素图 10 倍放大）
"""
import zlib
import struct
import os

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "art", "tiles")

OBST_MAP = [
    ".oooooo.",
    "oVVVVVVo",
    "oWLwwVVo",
    "oWLwwVVo",
    "oVwwwwDo",
    "oVwwwDDo",
    "oVVDDDVo",
    ".oooooo.",
]
OBST_PAL = {
    ".": (0, 0, 0, 0),
    "o": (36, 26, 51, 255),
    "V": (107, 79, 160, 255),
    "L": (180, 154, 224, 255),
    "W": (138, 111, 192, 255),
    "w": (138, 111, 192, 255),
    "D": (74, 52, 112, 255),
}

FOG_MAP = [
    "aaaaaaab",
    "aaabbbba",
    "abbcccbb",
    "abccccbb",
    "abccccbb",
    "abbcccbb",
    "aaabbbba",
    "aaaaaaab",
]
FOG_PAL = {
    ".": (0, 0, 0, 0),
    "a": (138, 147, 173, 205),
    "b": (168, 176, 196, 230),
    "c": (196, 203, 220, 248),
}


def write_png(path, w, h, get_pixel):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            raw.extend(get_pixel(x, y))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw)))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def render(map_rows, pal, path):
    n = len(map_rows[0])
    px = 10
    margin = 2
    size = n * px + margin * 2

    def get_pixel(x, y):
        cx = (x - margin) // px
        cy = (y - margin) // px
        if 0 <= cx < n and 0 <= cy < n:
            return pal[map_rows[cy][cx]]
        return (0, 0, 0, 0)

    write_png(path, size, size, get_pixel)
    print("wrote", path, size, "x", size)


if __name__ == "__main__":
    render(OBST_MAP, OBST_PAL, os.path.join(OUT_DIR, "obstacle_flower.png"))
    render(FOG_MAP, FOG_PAL, os.path.join(OUT_DIR, "smoke_fog.png"))
