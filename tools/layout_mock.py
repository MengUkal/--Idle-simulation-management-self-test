# -*- coding: utf-8 -*-
"""天赋树 UI 布局示意图 ×3（星座环 / 经典竖树 / 横向流）。
用战士树真实数据（ring1×3 / ring2×3 / ring3×1 / ring4 关键×3）绘制，
配色对齐 theme/fantasy.tres。仅作拍板参考，非最终实现。输出 tests/_layout_*.png
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "tests"))
os.makedirs(OUT, exist_ok=True)

W, H = 1280, 800
BG = (25, 19, 34)
PANEL = (36, 29, 51)
GOLD = (242, 201, 76)
CREAM = (232, 224, 207)
DIM = (140, 130, 115)
RED = (224, 86, 79)
GREEN = (88, 180, 107)
BLUE = (79, 143, 224)

_font_cache = {}


def font(size):
    if size not in _font_cache:
        _font_cache[size] = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", size)
    return _font_cache[size]


def node_box(d, xy, icon_char, name, rank, maxr, state, key=False, size=76):
    """state: maxed / partial / avail / locked"""
    x, y = xy
    half = size // 2
    if key:
        pts = [(x, y - half), (x + half, y), (x, y + half), (x - half, y)]
        d.polygon(pts, fill=PANEL, outline=GOLD, width=3)
    else:
        d.rounded_rectangle([x - half, y - half, x + half, y + half], radius=14,
                            fill=PANEL, outline=GOLD if state in ("maxed", "partial") else
                            (CREAM if state == "avail" else DIM), width=3)
    # 图标占位：中央大字符
    icol = CREAM if state != "locked" else DIM
    d.text((x, y - 6), icon_char, font=font(26), fill=icol, anchor="mm")
    # 等级点
    for i in range(maxr):
        px = x - (maxr - 1) * 5 + i * 10
        c = GOLD if i < rank else (90, 84, 100)
        d.ellipse([px - 3, y + half - 12, px + 3, y + half - 6], fill=c)
    # 名字
    d.text((x, y + half + 12), name, font=font(15),
           fill=CREAM if state != "locked" else DIM, anchor="mm")


def conn(d, a, b, lit, key=False):
    if lit:
        d.line([a, b], fill=GOLD, width=4)
    else:
        # 虚线
        import math
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dy) or 1
        ux, uy = dx / L, dy / L
        t = 0.0
        while t < L:
            e = min(t + 8, L)
            d.line([a[0] + ux * t, a[1] + uy * t, a[0] + ux * e, a[1] + uy * e],
                   fill=(100, 92, 110), width=2)
            t = e + 6


def header(d, title, note):
    d.rounded_rectangle([16, 16, W - 16, 84], radius=14, fill=PANEL)
    d.text((36, 30), title, font=font(30), fill=GOLD)
    d.text((W - 36, 30), note, font=font(18), fill=DIM, anchor="ra")


def frame(img, label):
    d = ImageDraw.Draw(img)
    d.text((20, H - 30), label, font=font(18), fill=DIM)
    return img


# ============ 方案 1：星座环（放射同心环，中心职业纹章） ============
img1 = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img1)
header(d, "方案一 · 星座环", "中心=职业纹章 ｜ 内环→外环=圈1→圈4 ｜ 环间连线=解锁")
cx, cy = W // 2, 460
rings = [(150, ["体", "金", "学"], [5, 5, 5], ["maxed", "partial", "partial"]),
         (255, ["吼", "掠", "耐"], [3, 0, 1], ["partial", "locked", "partial"]),
         (360, ["意"], [1], ["avail"]),
         (470, [("狂", "狂战之魂"), ("壁", "不屈之壁"), ("掠", "掠夺之道")], [0, 0, 0], ["locked"] * 3)]
# 中心职业纹章
d.ellipse([cx - 52, cy - 52, cx + 52, cy + 52], fill=PANEL, outline=GOLD, width=4)
d.text((cx, cy), "战", font=font(40), fill=GOLD, anchor="mm")
import math
pos1 = []
for r, chars, ranks, states in rings:
    key = isinstance(chars[0], tuple)
    n = len(chars)
    for i in range(n):
        a = -90 + i * (360 / n)
        x = cx + r * math.cos(math.radians(a))
        y = cy + r * math.sin(math.radians(a)) * 0.92
        pos1.append((x, y))
        if key:
            ch, nm = chars[i]
            node_box(d, (x, y), ch, nm, 0, 1, states[i], key=True, size=64)
        else:
            node_box(d, (x, y), chars[i], "", ranks[i], ranks[i] if False else 5,
                     states[i], size=68)
# 连线：环间相邻 + 中心→环1
for x, y in pos1[:3]:
    conn(d, (cx, cy), (x, y), True)
seq = [(0, 3), (1, 4), (2, 5), (3, 6), (5, 6), (4, 6), (6, 7), (7, 8), (6, 9)]
for a, b in seq:
    conn(d, pos1[a], pos1[b], a < 2 and b < 6)
frame(img1, "特点：最贴合「世界树星辰」世界观；环即层圈门槛，全树一屏无滚动；菱形=关键三选一")
img1.save(os.path.join(OUT, "_layout_1_ring.png"))

# ============ 方案 2：经典竖树（D4 式，根在下、关键在顶） ============
img2 = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img2)
header(d, "方案二 · 经典竖树（D4 蓝本）", "根=起点 ｜ 自下而上生长 ｜ 顶端=关键三选一")
col_x = [340, 640, 940]
rows_y = {1: 660, 2: 500, 3: 360, 4: 220}
names = {1: [("体", "锻体", 5, "maxed"), ("金", "掠取", 2, "partial"), ("学", "苦学", 0, "avail")],
         2: [("吼", "战吼", 3, "partial"), ("掠", "战利品", 0, "avail"), ("耐", "耐力", 1, "partial")],
         3: [("意", "不灭战意", 0, "avail")],
         4: [("狂", "狂战之魂", 0, "locked"), ("壁", "不屈之壁", 0, "locked"), ("掠", "掠夺之道", 0, "locked")]}
grid = {}
for ring, y in rows_y.items():
    xs = col_x if ring != 3 else [640]
    for i, x in enumerate(xs):
        ch, nm, rk, st = names[ring][i]
        grid[(ring, i)] = (x, y)
        node_box(d, (x, y), ch, nm, rk, 5 if ring in (1, 2) else (3 if ring == 3 else 1), st,
                 key=(ring == 4), size=76)
conn(d, (340, 660), (640, 660), True)
conn(d, (640, 660), (940, 660), True)
for i in range(3):
    conn(d, (col_x[i], rows_y[1]), (col_x[i], rows_y[2]), i < 2)
conn(d, (640, rows_y[2]), (640, rows_y[3]), True)
for i in range(3):
    conn(d, (640, rows_y[3]), (col_x[i], rows_y[4]), False)
d.text((640, 150), "▲ 关键天赋三选一（互斥）", font=font(18), fill=DIM, anchor="mm")
d.text((640, rows_y[1] + 70), "● 树根起点", font=font(16), fill=DIM, anchor="mm")
frame(img2, "特点：最像「树」；纵向滚动约一屏半；玩家对 D4/PoE 版式有肌肉记忆")
img2.save(os.path.join(OUT, "_layout_2_tree.png"))

# ============ 方案 3：横向流（左→右四列，宽屏友好） ============
img3 = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img3)
header(d, "方案三 · 横向流", "列=层圈 ｜ 左→右=成长方向 ｜ 宽屏零滚动")
col_x = [220, 540, 860, 1140]
rows_y = {1: [340, 460, 580], 2: [280, 460, 640], 3: [460], 4: [300, 460, 620]}
for ring, ys in rows_y.items():
    cx = col_x[ring - 1]
    d.text((cx, 150), "第 %d 层（需投入 %d）" % (ring, [0, 3, 12, 25][ring - 1]),
           font=font(17), fill=DIM, anchor="mm")
names3 = {1: [("体", "锻体", 5, "maxed"), ("金", "掠取", 2, "partial"), ("学", "苦学", 0, "avail")],
          2: [("吼", "战吼", 3, "partial"), ("掠", "战利品", 0, "avail"), ("耐", "耐力", 1, "partial")],
          3: [("意", "不灭战意", 0, "avail")],
          4: [("狂", "狂战之魂", 0, "locked"), ("壁", "不屈之壁", 0, "locked"), ("掠", "掠夺之道", 0, "locked")]}
grid3 = {}
for ring, ys in rows_y.items():
    for i, y in enumerate(ys):
        ch, nm, rk, st = names3[ring][i]
        grid3[(ring, i)] = (col_x[ring - 1], y)
        node_box(d, (col_x[ring - 1], y), ch, nm, rk,
                 5 if ring in (1, 2) else (3 if ring == 3 else 1), st, key=(ring == 4), size=72)
conn(d, (220, 460), (540, 460), True)
for i in range(3):
    conn(d, (540, rows_y[2][i]), (860, 460), i < 2)
conn(d, (860, 460), (1140, 460), False)
for i in range(3):
    conn(d, (860, 460), (1140, rows_y[4][i]), False)
frame(img3, "特点：1920 宽屏零滚动；成长方向=阅读方向；关键三选一在终端列，仪式感强")
img3.save(os.path.join(OUT, "_layout_3_flow.png"))

print("OK: 3 张布局示意图 ->", OUT)
