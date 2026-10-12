# -*- coding: utf-8 -*-
"""怪物占位立绘生成器（工程 M3 全权批次）：为缺失的 <slug>.png 生成 64x64 像素占位头像。
纯 stdlib（与 gen_board_tex.py 同管线）；美术产物存在时不覆盖——美术线到位后重跑即可自动跳过。
用法: python tools/gen_monster_placeholder.py
"""
import os
import struct
import zlib

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "art", "monsters")

# slug -> (底色RGB, 图案色RGB, 元素中文名)
MONSTERS = {
    # 五层·云顶鹰巢（设定包第十轮）
    "cloudlark": ((96, 140, 200), (230, 240, 252), "風"),
    "cloudsheep": ((170, 190, 215), (245, 248, 252), "水"),
    "kitefiend": ((120, 110, 190), (235, 225, 250), "風"),
    "dewspirit": ((110, 175, 175), (240, 252, 250), "水"),
    "thunderdragonfly": ((200, 180, 90), (250, 245, 210), "光"),
    "mistfish": ((90, 130, 160), (225, 240, 248), "水"),
    "watchereagle": ((70, 80, 120), (240, 230, 200), "闇"),
    # 六层·星梢（M3.0 工程提案）
    "stardustmoth": ((85, 75, 150), (250, 240, 200), "光"),
    "moosedeer": ((80, 130, 105), (235, 245, 230), "土"),
    "frostowl": ((140, 185, 215), (245, 250, 255), "火"),
    "meteorfly": ((190, 110, 80), (255, 230, 190), "風"),
    "silverwhale": ((105, 125, 175), (230, 240, 252), "水"),
    "nightweaver": ((60, 55, 90), (200, 190, 235), "闇"),
    "stargazer": ((55, 50, 100), (250, 235, 170), "光"),
}

SIZE = 64


def _chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def write_png(path, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    png = (b"\x89PNG\r\n\x1a\n"
           + _chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
           + _chunk(b"IDAT", zlib.compress(raw))
           + _chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def gen(slug, bg, pat, elem_char):
    """深底 + 元素色边框 + 中央菱形图案 + 四角星点（像素风占位）。"""
    rows = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            # 边框（外 3px 图案色）
            if x < 3 or x >= SIZE - 3 or y < 3 or y >= SIZE - 3:
                row.extend(pat)
                continue
            # 中央菱形（|dx|+|dy| <= 14）
            dx, dy = abs(x - SIZE // 2), abs(y - SIZE // 2)
            if dx + dy <= 14:
                row.extend(pat)
            elif dx + dy <= 17:
                row.extend(bg)
            # 四角星点（十字 sparkle）
            elif (x in (10, 11, 12, 13, 14, 15, 48, 49, 50, 51, 52, 53) and y in (10, 11, 12, 50, 51, 52)) or \
                 (y in (10, 11, 12, 13, 14, 15, 48, 49, 50, 51, 52, 53) and x in (10, 11, 12, 50, 51, 52)):
                row.extend(pat)
            else:
                row.extend(bg)
        rows.append(row)
    write_png(os.path.join(OUT_DIR, "%s.png" % slug), rows)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    made, skipped = 0, 0
    for slug, (bg, pat, _e) in MONSTERS.items():
        path = os.path.join(OUT_DIR, "%s.png" % slug)
        if os.path.exists(path):
            skipped += 1
            continue
        gen(slug, bg, pat, _e)
        made += 1
    # 层卡卡面（金边深紫 + 中央大星 + 层号横条）
    cards = {"card_floor3": "III", "card_floor4": "IV", "card_floor5": "V", "card_floor6": "VI"}
    for cid, num in cards.items():
        path = os.path.join(OUT_DIR, "%s.png" % cid)
        if os.path.exists(path):
            skipped += 1
            continue
        rows = []
        for y in range(64):
            row = []
            for x in range(64):
                edge = x < 4 or x >= 60 or y < 4 or y >= 60
                inner_border = (x in (6, 7, 56, 57) or y in (6, 7, 56, 57)) and 6 <= x < 58 and 6 <= y < 58
                dx, dy = abs(x - 32), abs(y - 32)
                star = (dx + dy <= 12) or (x in range(30, 34) and 20 <= y < 45) or (y in range(30, 34) and 20 <= x < 45)
                band = 44 <= y < 52 and 10 <= x < 54
                if edge or inner_border:
                    row.extend((212, 175, 90))
                elif band:
                    row.extend((30, 26, 48))
                elif star:
                    row.extend((245, 225, 150))
                else:
                    row.extend((32, 28, 52))
            rows.append(row)
        write_png(path, rows)
        made += 1
    print("占位立绘/卡面生成 %d 枚，跳过已存在 %d 枚 -> %s" % (made, skipped, os.path.abspath(OUT_DIR)))


if __name__ == "__main__":
    main()
