# -*- coding: utf-8 -*-
"""怪物像素立绘生成器 v2（M3 全权批次）：16x16 手绘字符网格 -> 64x64 像素风立绘。
字符: .=透明 B=底 S=影 M=主 L=亮。美术产物存在时不覆盖（FORCE_SLUGS 除外）。
用法: python tools/gen_monster_pixel.py
"""
import os
import struct
import zlib

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "art", "monsters")
SIZE = 16
SCALE = 4  # 16*4 = 64

# 需强制重生成的 slug（覆盖旧的色块占位）；美术真产物不在此列
FORCE_SLUGS = {
    "stardustmoth", "moosedeer", "frostowl", "meteorfly",
    "silverwhale", "nightweaver", "stargazer",
}

G = {
    "cloudlark": (
        [
            "................",
            "......LLLL......",
            ".....LMMMML.....",
            "....LMMMMMM.....",
            "....MMMMSMM.....",
            "....MMMMSM......",
            "...BMMMMSM......",
            "..BMMMMMSM.BB...",
            ".BBMMMMMMBBB....",
            ".B.BMMMMSB......",
            "....BMMSB.......",
            ".....BMMB.......",
            "......BMB.......",
            ".......B........",
            "................",
            "................",
        ],
        {"B": (60, 70, 110), "S": (140, 160, 200), "M": (200, 215, 240), "L": (245, 250, 255)},
    ),
    "cloudsheep": (
        [
            "................",
            "................",
            "....MMMM.MM.....",
            "...MMMMMMMMM....",
            "..MMMMMMMMMMM...",
            "..MMMMMMMMMMM...",
            ".MMMMMMMMMMMM...",
            ".MMMLLLLMMMMM...",
            ".SMMMLLLMMMMM...",
            "..SSSSSSSSSS....",
            "...B......B.....",
            "...B......B.....",
            "................",
            "................",
            "................",
            "................",
        ],
        {"B": (80, 85, 100), "S": (150, 155, 170), "M": (225, 228, 238), "L": (250, 250, 255)},
    ),
    "kitefiend": (
        [
            "................",
            ".......LL.......",
            "......LMM.......",
            ".....LMMML......",
            "....MMMMMML.....",
            "...MMMMMMMML....",
            "..MMMMMMMMML....",
            ".MMMMMMMMMM.....",
            "..MMMMMMMM......",
            "...MMMMMM.......",
            "....MMMM........",
            ".....BMMB.......",
            "......BB..B.....",
            "..........B.....",
            "................",
            "................",
        ],
        {"B": (55, 45, 95), "S": (110, 95, 170), "M": (160, 140, 220), "L": (230, 220, 255)},
    ),
    "dewspirit": (
        [
            "................",
            ".......LL.......",
            "......LMM.......",
            ".....LMMMM......",
            "....MMMMMMM.....",
            "....MMMMMMMM....",
            "...MMMMMMMMM....",
            "...MMMMMMMMM....",
            "...SMMMMMMMM....",
            "....SMMMMMMM....",
            ".....SMMMMMM....",
            "......SMMMMM....",
            ".......SMMMM....",
            "........SSMM....",
            "..........SS....",
            "................",
        ],
        {"B": (45, 85, 95), "S": (90, 150, 155), "M": (150, 210, 215), "L": (220, 245, 245)},
    ),
    "thunderdragonfly": (
        [
            "................",
            "..LL............",
            ".LMM............",
            "..BMMMLL........",
            "...BMMMMMLL.....",
            "....BMMMMMMML...",
            ".....BMMMMMMML..",
            "......BMMMMMM...",
            ".....SBBBBMM....",
            "....SS......B...",
            "...SS...........",
            "..SS............",
            ".SS.............",
            "................",
            "................",
            "................",
        ],
        {"B": (70, 65, 40), "S": (160, 145, 80), "M": (215, 195, 100), "L": (250, 240, 170)},
    ),
    "mistfish": (
        [
            "................",
            "................",
            "......LLLL......",
            ".....LMMMML.....",
            "....MMMMMMMM....",
            "...MMMMMMMMMM...",
            "..MMMSMMMMMMMM..",
            "..MMMSMMMMMMML..",
            "..MMMSMMMMMMM...",
            "...MMSMMMMMM....",
            "....MSSMMMML....",
            "......BSSL......",
            ".......B........",
            "................",
            "................",
            "................",
        ],
        {"B": (50, 80, 105), "S": (100, 140, 165), "M": (160, 200, 220), "L": (225, 245, 250)},
    ),
    "watchereagle": (
        [
            "................",
            "......LLMM......",
            ".....LMMMMM.....",
            "....MMMMMMMM....",
            "....MMMMSMMM....",
            "....MMMSMMML....",
            "....MMMSMMML....",
            "....MMMMMMM.....",
            ".....MMMMM......",
            "....BMMMMMB.....",
            "...BBMMMMMB.....",
            "..B..BMMMB......",
            "......BMB.......",
            "......BMB.......",
            ".......B........",
            "................",
        ],
        {"B": (65, 55, 90), "S": (130, 115, 160), "M": (190, 175, 220), "L": (245, 235, 255)},
    ),
    "stardustmoth": (
        [
            "................",
            ".MM..........MM.",
            ".MMM...LL...MMM.",
            ".MMMM.LMML.MMMM.",
            "..MMMMLMMMLMMMM.",
            "...MMMLLMMLMM...",
            "....MMLMMMMLM...",
            "....MMLLLLMLM...",
            "....MMLMMMMLM...",
            "...MMMLLMMLMM...",
            "..MMMMLMMMLMMMM.",
            ".MMMM.LMML.MMMM.",
            ".MMM...LL...MMM.",
            ".MM..........MM.",
            "................",
            "................",
        ],
        {"B": (50, 45, 95), "S": (120, 110, 180), "M": (180, 170, 230), "L": (250, 240, 190)},
    ),
    "moosedeer": (
        [
            "...M.......M....",
            "....M.....M.....",
            "....MM...MM.....",
            ".....MLLLLM.....",
            ".....MLMMML.....",
            ".....MLMMML.....",
            "....MMMMMMMM....",
            "....MMMMMMMM....",
            "....MMSMMSMM....",
            "....MMMMMMMM....",
            ".....MMMMMM.....",
            ".....BMMMMB.....",
            ".....BBMMBB.....",
            ".......BMB......",
            ".......BMB......",
            "................",
        ],
        {"B": (60, 75, 60), "S": (110, 135, 105), "M": (170, 195, 160), "L": (230, 245, 220)},
    ),
    "frostowl": (
        [
            "................",
            "................",
            "....MM....MM....",
            "...MMMM..MMMM...",
            "...MMMMMMMMMM...",
            "....MMMMMMMM....",
            "...MMMMMMMMMM...",
            "..MMMMMMMMMMMM..",
            "..MMLLMMMMLLMM..",
            "..MMLLMMMMLLMM..",
            "..MMMMMMMMMMMM..",
            "...MMMMMMMMMM...",
            "....SSSSSSSS....",
            "................",
            "................",
            "................",
        ],
        {"B": (55, 80, 105), "S": (130, 165, 190), "M": (200, 225, 240), "L": (120, 200, 250)},
    ),
    "meteorfly": (
        [
            "................",
            ".LL.............",
            "..MML...........",
            "....MML.........",
            "......MMML......",
            "........MMMML...",
            "..........MMMM..",
            ".........MMMMM..",
            "........MMMMMM..",
            ".......MMMMMM...",
            "......BMMMMM....",
            ".....BBMMMMB....",
            "....BB..BMMB....",
            "........BB......",
            "................",
            "................",
        ],
        {"B": (85, 50, 40), "S": (170, 90, 70), "M": (225, 140, 100), "L": (255, 220, 160)},
    ),
    "silverwhale": (
        [
            "................",
            "................",
            "................",
            "....MMMMMMM.....",
            "..MMMMMMMMMMM...",
            ".MMMMMMMMMMMMM..",
            ".MMMLMMMMMMMMM..",
            ".MMMMSMMMMMMMM..",
            ".MMMMSSMMMMMMM..",
            "..MMMMSSMMMMM...",
            "...MMMMMMMMM....",
            "....MMMMMMMM....",
            "......MMMMMM....",
            ".......M...M....",
            "................",
            "................",
        ],
        {"B": (45, 60, 95), "S": (100, 120, 165), "M": (170, 190, 230), "L": (235, 245, 255)},
    ),
    "nightweaver": (
        [
            "................",
            ".....M....M.....",
            "......M..M......",
            "....MMM..MMM....",
            ".....MMMMMM.....",
            "....MMMMMMMM....",
            ".....MMMMMM.....",
            "..M...MMMM...M..",
            ".MM..MM..MM..MM.",
            "M..MMMM..MMMM..M",
            "...MM..MM..MM...",
            "..M..M....M..M..",
            ".M...........M..",
            "................",
            "................",
            "................",
        ],
        {"B": (40, 35, 65), "S": (95, 85, 140), "M": (150, 140, 200), "L": (220, 210, 250)},
    ),
    "stargazer": (
        [
            "................",
            "....MMMMMMMM....",
            "...MMMLLLLMMM...",
            "...MMLLLLMLLM...",
            "...MMMMMMMMMM...",
            "...MMMMSSMMMM...",
            "....MMMSMSMM....",
            "....MMMMMMMM....",
            ".....MMMMMM.....",
            "....BMMMMMMB....",
            "...BBMMMMMMBB...",
            "..B..BMMMMLB....",
            ".....BMLLLLB....",
            ".....BLLLLLB....",
            "......BBBB......",
            "................",
        ],
        {"B": (60, 55, 105), "S": (125, 115, 185), "M": (185, 175, 235), "L": (255, 245, 200)},
    ),
}


def _chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def write_png(path, grid, pal):
    out = []
    for gy in range(SIZE):
        scaled_row = []
        for gx in range(SIZE):
            ch = grid[gy][gx]
            if ch == ".":
                px = (14, 12, 20)  # 暗底（与战斗背景同族）
            else:
                px = pal.get(ch, pal["B"])
            scaled_row.extend([px] * SCALE)
        for _ in range(SCALE):
            out.append([c for px in scaled_row for c in px])
    raw = b"".join(b"\x00" + bytes(r) for r in out)
    png = (b"\x89PNG\r\n\x1a\n"
           + _chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE * SCALE, SIZE * SCALE, 8, 2, 0, 0, 0))
           + _chunk(b"IDAT", zlib.compress(raw))
           + _chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def main():
    for slug, (grid, _pal) in G.items():
        for gy, line in enumerate(grid):
            if len(line) != SIZE:
                raise SystemExit("网格错误: %s 行 %d 长度 %d (需 %d)" % (slug, gy, len(line), SIZE))
    os.makedirs(OUT_DIR, exist_ok=True)
    made, skipped = 0, 0
    for slug, (grid, pal) in G.items():
        path = os.path.join(OUT_DIR, "%s.png" % slug)
        if os.path.exists(path) and slug not in FORCE_SLUGS:
            skipped += 1
            continue
        write_png(path, grid, pal)
        made += 1
    print("像素立绘生成 %d 枚，保护跳过 %d 枚（美术真产物）" % (made, skipped))


if __name__ == "__main__":
    main()
