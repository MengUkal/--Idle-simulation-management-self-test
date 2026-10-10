# -*- coding: utf-8 -*-
r"""程序化美术管线（方案A）：生成游戏全套图标 PNG。

产物（assets/art/ 下，Godot 自动导入）：
  tiles/tile_{i}_{tag}.png  元素棋子，i=0火 1水 2風 3土 4光 5闇，
                            tag = plain / lh(横线) / lv(竖线) / bomb(爆炸)
  tiles/tile_bird.png       魔力鸟（专属深紫金边棋子）
  ui/ui_gil.png             吉尔货币图标
  ui/ui_essence.png         元素精华图标
  preview.png               全部图标拼合预览（仅供人看）

用法：
  python tools/artgen.py            # 默认 128px
  python tools/artgen.py --size 256 # 任意尺寸重生成
风格基线：扁平圆角块 + 深色描边 + 白色符号（配 balance.gd 的 ELEMENT_COLORS）。
（2026-10-10 重建版：含三尖火苗 / 新月底色抠法 / 光元素暖棕暗色变体三项迭代。）
"""

import argparse
import math
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
ART = os.path.join(ROOT, "assets", "art")

S = 128  # 出图边长，由 --size 覆盖
BG = (0, 0, 0, 0)

# 与 balance.gd ELEMENT_COLORS 一致：0火 1水 2風 3土 4光 5闇
ELEMENTS = [
    ("fire",  "火", (0xE0, 0x56, 0x4F, 255)),
    ("water", "水", (0x4F, 0x8F, 0xE0, 255)),
    ("wind",  "風", (0x58, 0xB4, 0x6B, 255)),
    ("earth", "土", (0xC2, 0x95, 0x4A, 255)),
    ("light", "光", (0xF2, 0xE6, 0xC8, 255)),
    ("dark",  "闇", (0x8A, 0x5F, 0xBF, 255)),
]
SYMBOL_WHITE = (255, 255, 255, 255)
SYMBOL_ON_LIGHT = (0x6B, 0x54, 0x2A, 255)  # 光元素浅底上的符号色
SHADOW = (0, 0, 0, 80)


def px(k):
    """随尺寸缩放的像素值"""
    return max(1, int(round(S * k)))


def darken(c, k=0.72):
    return tuple(int(v * k) for v in c[:3]) + (c[3],)


def light_up(c, k=1.32):
    return tuple(min(255, int(v * k)) for v in c[:3]) + (c[3],)


def cubic(p0, p1, p2, p3, n=28):
    """三次贝塞尔采样"""
    out = []
    for i in range(n + 1):
        t = i / n
        mt = 1 - t
        x = mt**3 * p0[0] + 3 * mt * mt * t * p1[0] + 3 * mt * t * t * p2[0] + t**3 * p3[0]
        y = mt**3 * p0[1] + 3 * mt * mt * t * p1[1] + 3 * mt * t * t * p2[1] + t**3 * p3[1]
        out.append((x, y))
    return out


def arc_pts(cx, cy, rx, ry, a0, a1, n=28):
    """椭圆弧采样（角度制，0=右，顺时针增大朝下）"""
    return [
        (cx + rx * math.cos(math.radians(a)), cy + ry * math.sin(math.radians(a)))
        for a in [a0 + (a1 - a0) * i / n for i in range(n + 1)]
    ]


# ---------- 棋子底板 ----------

def tile(color, highlight=True, border_color=None):
    img = Image.new("RGBA", (S, S), BG)
    d = ImageDraw.Draw(img)
    m = px(0.045)
    d.rounded_rectangle([m, m, S - m, S - m], radius=px(0.19), fill=color,
                        outline=border_color or darken(color, 0.62), width=px(0.04))
    if highlight:
        d.rounded_rectangle([m + px(0.09), m + px(0.07), S - m - px(0.09), m + px(0.17)],
                            radius=px(0.05), fill=light_up(color, 1.30))
    return img


# ---------- 元素符号（白色/深棕，画在底板中心） ----------

def _flame_poly(cx, cy, sc, tip_dx=0.0):
    """火苗外轮廓：尖顶 + 右侧 S 形腰 + 底部圆弧。sc=整体缩放"""
    k = S * sc
    T = (cx + tip_dx * k, cy - 0.37 * k)
    M = (cx + 0.27 * k, cy + 0.00 * k)
    bc = (cx, cy + 0.15 * k)
    r = 0.24 * k
    R = (cx + r, bc[1])
    L = (cx - r, bc[1])
    right = cubic(T, (cx + 0.12 * k, cy - 0.25 * k), (cx + 0.27 * k, cy - 0.15 * k), M)
    right += cubic(M, (cx + 0.29 * k, cy + 0.05 * k), (cx + 0.26 * k, cy + 0.09 * k), R)[1:]
    bottom = arc_pts(bc[0], bc[1], r, r * 0.95, 0, 180)[1:]
    left = cubic(L, (cx - 0.29 * k, cy + 0.01 * k), (cx - 0.14 * k, cy - 0.22 * k), T)[1:]
    return right + bottom + left


def sym_flame(d, cx, cy, col, tile_col):
    """火：三尖营火造型（主焰 + 左右火舌）+ 底色镂空内焰"""
    o = (255, 255, 255, 255)
    # 左火舌
    d.polygon(
        [(cx - S * 0.20, cy + S * 0.17)]
        + cubic((cx - S * 0.20, cy + S * 0.17), (cx - S * 0.26, cy + S * 0.02),
                (cx - S * 0.24, cy - S * 0.05), (cx - S * 0.165, cy - S * 0.145))
        + cubic((cx - S * 0.165, cy - S * 0.145), (cx - S * 0.10, cy - S * 0.06),
                (cx - S * 0.04, cy - S * 0.02), (cx - S * 0.02, cy + S * 0.20))[1:],
        fill=o)
    # 右火舌
    d.polygon(
        [(cx + S * 0.05, cy + S * 0.20)]
        + cubic((cx + S * 0.05, cy + S * 0.20), (cx + S * 0.10, cy + S * 0.02),
                (cx + S * 0.14, cy - S * 0.03), (cx + S * 0.205, cy - S * 0.10))
        + cubic((cx + S * 0.205, cy - S * 0.10), (cx + S * 0.27, cy - S * 0.01),
                (cx + S * 0.27, cy + S * 0.06), (cx + S * 0.25, cy + S * 0.16))[1:],
        fill=o)
    # 主焰（最高尖）
    d.polygon(_flame_poly(cx, cy, 1.02, tip_dx=0.04), fill=o)
    # 内焰镂空
    d.polygon(_flame_poly(cx, cy + 0.02 * S, 0.46, tip_dx=0.02), fill=tile_col)


def sym_drop(d, cx, cy, col, tile_col=None):
    """水：对称水滴 + 高光"""
    r = S * 0.235
    bc = (cx, cy + S * 0.11)
    tip = (cx, cy - S * 0.35)
    L = (cx - r, bc[1])
    R = (cx + r, bc[1])
    right = cubic(tip, (cx + S * 0.035, cy - S * 0.16), (cx + r * 1.02, cy - S * 0.04), R)
    bottom = arc_pts(bc[0], bc[1], r, r * 0.96, 0, 180)
    left = cubic(L, (cx - r * 1.02, cy - S * 0.04), (cx - S * 0.035, cy - S * 0.16), tip)
    d.polygon(right + bottom + left, fill=col)
    d.ellipse([cx - r * 0.45, bc[1] + r * 0.10, cx - r * 0.10, bc[1] + r * 0.58],
              fill=light_up(col, 1.5))


def sym_wind(d, cx, cy, col, tile_col=None):
    """風：三条卷尾风线"""
    w = px(0.085)
    y0, gap = cy - S * 0.22, S * 0.20
    for i, (x2, sweep) in enumerate([(cx + S * 0.14, -90), (cx + S * 0.16, -90), (cx + S * 0.30, -90)]):
        y = y0 + i * gap
        x1 = cx - S * 0.32
        d.line([x1, y, x2, y], fill=col, width=w)
        rr = px(0.105) if i < 2 else px(0.125)
        if i < 2:
            d.arc([x2 - rr, y - rr, x2 + rr, y + rr], sweep, 180, fill=col, width=w)
        else:
            d.arc([x2 - rr, y - rr * 1.6, x2 + rr, y + rr * 0.4], sweep, 90, fill=col, width=w)
        r_ = w / 2
        d.ellipse([x1 - r_, y - r_, x1 + r_, y + r_], fill=col)


def sym_earth(d, cx, cy, col, tile_col=None):
    """土：双峰山 + 雪顶"""
    base = cy + S * 0.30
    d.polygon([(cx - S * 0.36, base), (cx - S * 0.04, base - S * 0.54),
               (cx + S * 0.28, base)], fill=col)
    d.polygon([(cx - S * 0.10, base), (cx + S * 0.17, base - S * 0.34),
               (cx + S * 0.40, base)], fill=darken(col, 0.82))
    d.polygon([(cx - S * 0.115, base - S * 0.40), (cx - S * 0.04, base - S * 0.54),
               (cx + S * 0.035, base - S * 0.40),
               (cx - S * 0.005, base - S * 0.335)], fill=(255, 255, 255, 235))


def sym_light(d, cx, cy, col, tile_col=None):
    """光：太阳（浅底上用深色）"""
    r = S * 0.165
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
    w = px(0.06)
    for a in range(0, 360, 45):
        rad = math.radians(a)
        x1, y1 = cx + math.cos(rad) * r * 1.5, cy + math.sin(rad) * r * 1.5
        x2, y2 = cx + math.cos(rad) * r * 2.2, cy + math.sin(rad) * r * 2.2
        d.line([x1, y1, x2, y2], fill=col, width=w)
        hr = w / 2
        d.ellipse([x2 - hr, y2 - hr, x2 + hr, y2 + hr], fill=col)


def sym_dark(d, cx, cy, col, tile_col):
    """闇：新月（用底色圆抠出，不透底）+ 两颗小星"""
    r = S * 0.25
    ax, ay = cx - S * 0.02, cy + S * 0.01
    d.ellipse([ax - r, ay - r, ax + r, ay + r], fill=col)
    # 抠月：与主圆同径、向右上偏移 0.5r → 经典弦月
    bx, by = cx + S * 0.105, cy - S * 0.105
    d.ellipse([bx - r * 0.96, by - r * 0.96, bx + r * 0.96, by + r * 0.96], fill=tile_col)
    # 小星画在月牙同侧空白处
    for sx, sy, ss in [(-S * 0.27, -S * 0.23, S * 0.05), (-S * 0.15, -S * 0.35, S * 0.034)]:
        x, y = cx + sx, cy + sy
        d.polygon([(x, y - ss), (x + ss * 0.32, y), (x, y + ss), (x - ss * 0.32, y)], fill=col)


SYMBOLS = {"fire": sym_flame, "water": sym_drop, "wind": sym_wind,
           "earth": sym_earth, "light": sym_light, "dark": sym_dark}


# ---------- 特殊棋子标记（白+描影，叠在压暗底板上） ----------

def arrow_pts(x0, x1, y, head):
    """水平双头箭头多边形"""
    return [(x0, y), (x0 + head, y - head * 0.9), (x0 + head, y - head * 0.28),
            (x1 - head, y - head * 0.28), (x1 - head, y - head * 0.9),
            (x1, y), (x1 - head, y + head * 0.9), (x1 - head, y + head * 0.28),
            (x0 + head, y + head * 0.28), (x0 + head, y + head * 0.9)]


def mark_line_h(d, cx, cy):
    pts = arrow_pts(cx - S * 0.30, cx + S * 0.30, cy, S * 0.13)
    d.polygon([(x, y + px(0.03)) for x, y in pts], fill=SHADOW)
    d.polygon(pts, fill=SYMBOL_WHITE, outline=darken((120, 120, 120, 255), 1), width=2)


def mark_line_v(d, cx, cy):
    pts = [(y, x) for x, y in arrow_pts(cy - S * 0.30, cy + S * 0.30, cx, S * 0.13)]
    d.polygon([(x + px(0.03), y) for x, y in pts], fill=SHADOW)
    d.polygon(pts, fill=SYMBOL_WHITE, outline=darken((120, 120, 120, 255), 1), width=2)


def mark_bomb(d, cx, cy):
    """八向星爆"""
    ro, ri = S * 0.32, S * 0.14
    pts = []
    for i in range(16):
        rad = math.radians(i * 22.5 - 90)
        rr = ro if i % 2 == 0 else ri
        pts.append((cx + rr * math.cos(rad), cy + rr * math.sin(rad)))
    d.polygon([(x, y + px(0.028)) for x, y in pts], fill=SHADOW)
    d.polygon(pts, fill=SYMBOL_WHITE)
    d.ellipse([cx - S * 0.05, cy - S * 0.05, cx + S * 0.05, cy + S * 0.05],
              fill=(0xF2, 0xC9, 0x4C, 255))


MARKS = {"lh": mark_line_h, "lv": mark_line_v, "bomb": mark_bomb}


def make_element_tile(idx, key, color, tag):
    """tag: plain / lh / lv / bomb"""
    if tag == "plain":
        img = tile(color)
        col = SYMBOL_WHITE if key != "light" else SYMBOL_ON_LIGHT
        SYMBOLS[key](ImageDraw.Draw(img), S // 2, S // 2 + S * 0.015, col, color)
    else:
        # 光元素暗色调暖棕，其余均匀压暗
        dk = tuple(int(c * f) for c, f in zip(color[:3], (0.55, 0.45, 0.30))) + (255,) \
            if key == "light" else darken(color, 0.52)
        img = tile(dk, highlight=False)
        MARKS[tag](ImageDraw.Draw(img), S // 2, S // 2)
    return img


def make_bird_tile():
    """魔力鸟：深紫底 + 金边 + 白鸟剪影"""
    bgc = (0x3A, 0x2F, 0x55, 255)
    gold = (0xF2, 0xC9, 0x4C, 255)
    img = Image.new("RGBA", (S, S), BG)
    d = ImageDraw.Draw(img)
    m = px(0.045)
    d.rounded_rectangle([m, m, S - m, S - m], radius=px(0.19), fill=bgc,
                        outline=gold, width=px(0.045))
    cx, cy = S * 0.48, S * 0.54
    # 尾羽
    d.polygon([(cx - S * 0.30, cy + S * 0.10), (cx - S * 0.16, cy - S * 0.02),
               (cx - S * 0.14, cy + S * 0.14)], fill=SYMBOL_WHITE)
    # 身体
    d.ellipse([cx - S * 0.26, cy - S * 0.16, cx + S * 0.18, cy + S * 0.26], fill=SYMBOL_WHITE)
    # 头
    hx, hy, hr = cx + S * 0.14, cy - S * 0.13, S * 0.14
    d.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=SYMBOL_WHITE)
    # 喙（金）
    d.polygon([(hx + hr * 0.7, hy - S * 0.03), (hx + hr + S * 0.10, hy + S * 0.03),
               (hx + hr * 0.7, hy + S * 0.09)], fill=gold)
    # 眼
    d.ellipse([hx - S * 0.005, hy - S * 0.055, hx + S * 0.055, hy + S * 0.005],
              fill=(0x2A, 0x24, 0x38, 255))
    # 翅膀（弧线）
    d.arc([cx - S * 0.20, cy - S * 0.02, cx + S * 0.10, cy + S * 0.26],
          200, 340, fill=darken(bgc, 0.8), width=px(0.035))
    # 脚下小彩虹弧（点出"彩虹鸟"身份）
    for i, rc in enumerate([(0xE0, 0x56, 0x4F, 255), (0xF2, 0xC9, 0x4C, 255), (0x58, 0xB4, 0x6B, 255)]):
        rr = S * (0.30 + i * 0.045)
        d.arc([cx - rr, S * 0.80 - rr + S * 0.16, cx + rr, S * 0.80 + rr + S * 0.16],
              180, 360, fill=rc, width=px(0.022))
    return img


# ---------- UI 图标 ----------

def make_gil():
    """吉尔金币"""
    gold, rim, inner = (0xF2, 0xC9, 0x4C, 255), (0xC0, 0x8A, 0x28, 255), (0xFF, 0xE0, 0x8A, 255)
    img = Image.new("RGBA", (S, S), BG)
    d = ImageDraw.Draw(img)
    d.ellipse([S * 0.08, S * 0.08, S * 0.92, S * 0.92], fill=gold, outline=rim, width=px(0.055))
    d.ellipse([S * 0.20, S * 0.20, S * 0.80, S * 0.80], fill=inner, outline=rim, width=px(0.02))
    # G 字：优先系统粗体字，失败则手绘
    try:
        font = ImageFont.truetype(r"C:\Windows\Fonts\arialbd.ttf", int(S * 0.42))
        bb = d.textbbox((0, 0), "G", font=font)
        d.text((S / 2 - (bb[2] + bb[0]) / 2, S / 2 - (bb[3] + bb[1]) / 2), "G",
               font=font, fill=darken(rim, 0.75))
    except OSError:
        d.arc([S * 0.32, S * 0.30, S * 0.70, S * 0.70], -70, 200, fill=rim, width=px(0.06))
        d.line([S * 0.51, S * 0.485, S * 0.70, S * 0.485], fill=rim, width=px(0.06))
    return img


def make_essence():
    """元素精华：多彩宝石"""
    img = Image.new("RGBA", (S, S), BG)
    d = ImageDraw.Draw(img)
    teal, teal_d = (0x5F, 0xD3, 0xC9, 255), (0x2E, 0x9E, 0x96, 255)
    pink = (0xE0, 0x6A, 0xB0, 255)
    top = [(S * 0.50, S * 0.10), (S * 0.80, S * 0.38), (S * 0.50, S * 0.66), (S * 0.20, S * 0.38)]
    bot = [(S * 0.20, S * 0.38), (S * 0.80, S * 0.38), (S * 0.50, S * 0.92)]
    d.polygon(top, fill=teal)
    d.polygon(bot, fill=teal_d)
    # 左上高光面 + 右侧粉面（多彩感）
    d.polygon([(S * 0.50, S * 0.10), (S * 0.20, S * 0.38), (S * 0.50, S * 0.66),
               (S * 0.50, S * 0.38)], fill=light_up(teal, 1.25))
    d.polygon([(S * 0.80, S * 0.38), (S * 0.50, S * 0.66), (S * 0.50, S * 0.92)], fill=pink)
    d.line([top[0], top[1], top[2], top[3], top[0]], fill=darken(teal_d, 0.8), width=px(0.028))
    d.line([top[3], top[1]], fill=darken(teal_d, 0.8), width=px(0.022))
    # 星光
    for x, y, ss in [(S * 0.66, S * 0.16, S * 0.06), (S * 0.30, S * 0.56, S * 0.045)]:
        d.polygon([(x, y - ss), (x + ss * 0.3, y), (x, y + ss), (x - ss * 0.3, y)],
                  fill=(255, 255, 255, 240))
    return img


# ---------- 交易所标的图标（透明底小图标） ----------

def _shard(d, cx, cy, w, h, col, lean=0.0):
    """单个竖菱形晶柱"""
    pts = [(cx + lean * h, cy - h / 2), (cx + lean * h + w / 2, cy),
           (cx, cy + h / 2), (cx - w / 2 + lean * h, cy)]
    d.polygon(pts, fill=col)
    d.line([pts[0], pts[2]], fill=light_up(col, 1.35), width=3)


def make_target_huo():
    """火晶石：红色晶簇"""
    img = Image.new("RGBA", (S, S), BG)
    d = ImageDraw.Draw(img)
    red, red_d = (0xE0, 0x56, 0x4F, 255), (0xA8, 0x36, 0x30, 255)
    _shard(d, S * 0.36, S * 0.56, S * 0.22, S * 0.52, red_d, lean=-0.12)
    _shard(d, S * 0.62, S * 0.60, S * 0.24, S * 0.62, red, lean=0.10)
    _shard(d, S * 0.52, S * 0.34, S * 0.20, S * 0.42, light_up(red, 1.15), lean=0.0)
    d.line([(S * 0.52, S * 0.18), (S * 0.52, S * 0.44)], fill=(255, 255, 255, 200), width=3)
    return img


def make_target_feng():
    """風羽绢：青绿羽绢（羽毛形 + 羽肋）"""
    img = Image.new("RGBA", (S, S), BG)
    d = ImageDraw.Draw(img)
    teal, teal_d = (0x58, 0xB4, 0x6B, 255), (0x3A, 0x8A, 0x4A, 255)
    # 羽片：两条贝塞尔围出的月牙羽形
    tip, base = (S * 0.74, S * 0.20), (S * 0.28, S * 0.80)
    side_a = cubic(base, (S * 0.22, S * 0.46), (S * 0.40, S * 0.20), tip)
    side_b = cubic(tip, (S * 0.66, S * 0.42), (S * 0.46, S * 0.72), base)[1:]
    d.polygon(side_a + side_b, fill=teal)
    # 羽肋
    d.line([base, tip], fill=(255, 255, 255, 210), width=4)
    # 缺口（羽枝分叉感）：底色斜切两刀
    d.line([(S * 0.40, S * 0.30), (S * 0.52, S * 0.42)], fill=BG, width=5)
    d.line([(S * 0.52, S * 0.52), (S * 0.64, S * 0.64)], fill=BG, width=5)
    # 羽根
    d.line([base, (S * 0.18, S * 0.92)], fill=teal_d, width=5)
    return img


def make_target_sheng():
    """生命露：青露水滴 + 嫩叶 + 星光"""
    img = Image.new("RGBA", (S, S), BG)
    d = ImageDraw.Draw(img)
    teal = (0x5F, 0xD3, 0xC9, 255)
    r = S * 0.28
    bc = (S * 0.52, S * 0.62)
    tip = (S * 0.52, S * 0.14)
    L, R = (bc[0] - r, bc[1]), (bc[0] + r, bc[1])
    right = cubic(tip, (tip[0] + S * 0.03, tip[1] + S * 0.14), (bc[0] + r * 1.02, bc[1] - r * 0.5), R)
    bottom = arc_pts(bc[0], bc[1], r, r * 0.96, 0, 180)[1:]
    left = cubic(L, (bc[0] - r * 1.02, bc[1] - r * 0.5), (tip[0] - S * 0.03, tip[1] + S * 0.14), tip)[1:]
    d.polygon(right + bottom + left, fill=teal)
    d.ellipse([bc[0] - r * 0.40, bc[1] + r * 0.08, bc[0] - r * 0.06, bc[1] + r * 0.52],
              fill=light_up(teal, 1.4))
    # 嫩叶
    d.polygon([(tip[0], tip[1] - S * 0.02), (tip[0] + S * 0.16, tip[1] - S * 0.10),
               (tip[0] + S * 0.06, tip[1] - S * 0.16)], fill=(0x58, 0xB4, 0x6B, 255))
    # 星光
    for x, y, ss in [(S * 0.24, S * 0.26, S * 0.05), (S * 0.78, S * 0.42, S * 0.04)]:
        d.polygon([(x, y - ss), (x + ss * 0.3, y), (x, y + ss), (x - ss * 0.3, y)],
                  fill=(255, 255, 255, 220))
    return img


# ---------- 训练线图标（攻击/赏金/收入） ----------

def make_line_atk():
    """攻击：斜置剑（刃 + 护手 + 柄）"""
    img = Image.new("RGBA", (S, S), BG)
    d = ImageDraw.Draw(img)
    steel, steel_l = (0xD8, 0xDE, 0xE8, 255), (0xFF, 0xFF, 0xFF, 255)
    gold = (0xF2, 0xC9, 0x4C, 255)
    # 刃（斜 45°，从右上尖到中左）
    d.polygon([(S * 0.82, S * 0.14), (S * 0.86, S * 0.18), (S * 0.40, S * 0.62),
               (S * 0.34, S * 0.56)], fill=steel)
    d.line([(S * 0.82, S * 0.16), (S * 0.38, S * 0.58)], fill=steel_l, width=3)
    # 护手（垂直于刃的金条）
    d.polygon([(S * 0.30, S * 0.50), (S * 0.38, S * 0.42), (S * 0.56, S * 0.60),
               (S * 0.48, S * 0.68)], fill=gold)
    # 柄 + 柄头
    d.polygon([(S * 0.32, S * 0.62), (S * 0.40, S * 0.70), (S * 0.24, S * 0.86),
               (S * 0.16, S * 0.78)], fill=(0x8a, 0x5a, 0x2b, 255))
    d.ellipse([S * 0.12, S * 0.76, S * 0.24, S * 0.88], fill=gold)
    return img


def make_line_bounty():
    """赏金：钱袋（束口布袋 + 金币）"""
    img = Image.new("RGBA", (S, S), BG)
    d = ImageDraw.Draw(img)
    bag, bag_d = (0xC2, 0x95, 0x4A, 255), (0x8a, 0x5a, 0x2b, 255)
    # 袋身
    d.ellipse([S * 0.20, S * 0.34, S * 0.80, S * 0.90], fill=bag, outline=bag_d, width=4)
    # 束口
    d.rounded_rectangle([S * 0.36, S * 0.26, S * 0.64, S * 0.40], radius=6,
                        fill=bag_d, outline=darken(bag_d, 0.8), width=3)
    # 袋口露出金币
    d.ellipse([S * 0.42, S * 0.16, S * 0.58, S * 0.32], fill=(0xF2, 0xC9, 0x4C, 255),
              outline=(0xC0, 0x8A, 0x28, 255), width=3)
    # 袋面 "G" 印记
    try:
        font = ImageFont.truetype(r"C:\Windows\Fonts\arialbd.ttf", int(S * 0.30))
        bb = d.textbbox((0, 0), "G", font=font)
        d.text((S * 0.5 - (bb[2] + bb[0]) / 2, S * 0.63 - (bb[3] + bb[1]) / 2), "G",
               font=font, fill=darken(bag_d, 0.7))
    except OSError:
        d.arc([S * 0.42, S * 0.50, S * 0.62, S * 0.70], -60, 200, fill=bag_d, width=4)
    return img


def make_line_income():
    """收入：底轴 + 上升折线 + 箭头"""
    img = Image.new("RGBA", (S, S), BG)
    d = ImageDraw.Draw(img)
    green = (0x58, 0xB4, 0x6B, 255)
    # 坐标轴
    d.line([S * 0.18, S * 0.16, S * 0.18, S * 0.82], fill=(0xE8, 0xE0, 0xCF, 255), width=5)
    d.line([S * 0.18, S * 0.82, S * 0.84, S * 0.82], fill=(0xE8, 0xE0, 0xCF, 255), width=5)
    # 上升折线
    pts = [(S * 0.24, S * 0.68), (S * 0.40, S * 0.52), (S * 0.54, S * 0.60),
           (S * 0.74, S * 0.28)]
    d.line(pts, fill=green, width=6, joint="curve")
    for p in pts:
        d.ellipse([p[0] - 5, p[1] - 5, p[0] + 5, p[1] + 5], fill=green)
    # 箭头
    ex, ey = pts[-1]
    d.polygon([(ex + S * 0.10, ey - S * 0.12), (ex - S * 0.01, ey - S * 0.14),
               (ex + S * 0.04, ey - S * 0.01)], fill=green)
    return img


# ---------- 职业/种族纹章（金环=职业，银环=种族） ----------

EMBLEM_RING_CLASS = (0xF2, 0xC9, 0x4C, 255)
EMBLEM_RING_RACE = (0xA8, 0x9F, 0xD6, 255)
EMBLEM_BG = (0x24, 0x1D, 0x33, 255)
UI_DIR = os.path.join(ART, "ui")


def _emblem_base(d, ring):
    d.ellipse([S * 0.07, S * 0.07, S * 0.93, S * 0.93], fill=EMBLEM_BG)
    d.ellipse([S * 0.07, S * 0.07, S * 0.93, S * 0.93], outline=ring, width=px(0.05))


def _emblem_warrior(d):
    col = (0xD8, 0xDE, 0xE8, 255)
    d.line([S * 0.26, S * 0.26, S * 0.72, S * 0.70], fill=col, width=7)
    d.line([S * 0.74, S * 0.26, S * 0.28, S * 0.70], fill=col, width=7)
    d.ellipse([S * 0.44, S * 0.42, S * 0.56, S * 0.54], fill=(0xF2, 0xC9, 0x4C, 255))


def _emblem_mage(d):
    d.line([S * 0.50, S * 0.34, S * 0.50, S * 0.82], fill=(0x8a, 0x5a, 0x2b, 255), width=7)
    d.ellipse([S * 0.38, S * 0.14, S * 0.62, S * 0.38], fill=(0x8A, 0x5F, 0xBF, 255),
              outline=(0xF2, 0xC9, 0x4C, 255), width=4)
    d.ellipse([S * 0.45, S * 0.21, S * 0.55, S * 0.31], fill=(0xE8, 0xE0, 0xCF, 255))


def _emblem_rogue(d):
    col = (0xC0, 0xC8, 0xD8, 255)
    d.polygon([(S * 0.70, S * 0.20), (S * 0.78, S * 0.28), (S * 0.46, S * 0.60),
               (S * 0.40, S * 0.52)], fill=col)
    d.polygon([(S * 0.36, S * 0.48), (S * 0.46, S * 0.58), (S * 0.54, S * 0.50),
               (S * 0.44, S * 0.40)], fill=(0xF2, 0xC9, 0x4C, 255))
    d.polygon([(S * 0.38, S * 0.58), (S * 0.46, S * 0.66), (S * 0.32, S * 0.80),
               (S * 0.24, S * 0.72)], fill=(0x2a, 0x24, 0x38, 255))
    d.ellipse([S * 0.26, S * 0.66, S * 0.36, S * 0.76], fill=(0xF2, 0xC9, 0x4C, 255))


def _emblem_priest(d):
    gold = (0xF2, 0xC9, 0x4C, 255)
    d.arc([S * 0.34, S * 0.30, S * 0.66, S * 0.62], 0, 180, fill=gold, width=7)
    d.line([S * 0.34, S * 0.46, S * 0.66, S * 0.46], fill=gold, width=6)
    d.line([S * 0.50, S * 0.46, S * 0.50, S * 0.68], fill=gold, width=6)
    d.line([S * 0.36, S * 0.72, S * 0.64, S * 0.72], fill=gold, width=6)
    d.ellipse([S * 0.44, S * 0.14, S * 0.56, S * 0.26], outline=gold, width=4)


def _emblem_paladin(d):
    col = (0xE8, 0xE0, 0xCF, 255)
    d.polygon([(S * 0.50, S * 0.12), (S * 0.78, S * 0.24), (S * 0.74, S * 0.60),
               (S * 0.50, S * 0.86), (S * 0.26, S * 0.60), (S * 0.22, S * 0.24)],
              fill=(0x4a, 0x3d, 0x6b, 255), outline=col, width=4)
    d.line([S * 0.50, S * 0.24, S * 0.50, S * 0.66], fill=(0xF2, 0xC9, 0x4C, 255), width=6)
    d.line([S * 0.34, S * 0.38, S * 0.66, S * 0.38], fill=(0xF2, 0xC9, 0x4C, 255), width=6)


def _emblem_ranger(d):
    col = (0x58, 0xB4, 0x6B, 255)
    d.arc([S * 0.24, S * 0.18, S * 0.60, S * 0.82], 290, 70, fill=col, width=7)
    d.line([S * 0.34, S * 0.20, S * 0.46, S * 0.80], fill=(0xE8, 0xE0, 0xCF, 255), width=3)
    d.line([S * 0.28, S * 0.74, S * 0.72, S * 0.30], fill=(0xE8, 0xE0, 0xCF, 255), width=5)
    d.polygon([(S * 0.72, S * 0.30), (S * 0.60, S * 0.30), (S * 0.70, S * 0.42)], fill=col)


def _emblem_warlock(d):
    col = (0x8A, 0x5F, 0xBF, 255)
    d.polygon([(S * 0.30, S * 0.30), (S * 0.24, S * 0.12), (S * 0.44, S * 0.24)], fill=col)
    d.polygon([(S * 0.70, S * 0.30), (S * 0.76, S * 0.12), (S * 0.56, S * 0.24)], fill=col)
    d.arc([S * 0.28, S * 0.28, S * 0.72, S * 0.68], 20, 160, fill=col, width=6)
    d.arc([S * 0.28, S * 0.28, S * 0.72, S * 0.68], 200, 340, fill=col, width=6)
    d.ellipse([S * 0.44, S * 0.40, S * 0.56, S * 0.56], fill=(0xE0, 0x56, 0x4F, 255))


def _emblem_human(d):
    col = (0xE0, 0x56, 0x4F, 255)
    d.line([S * 0.34, S * 0.14, S * 0.34, S * 0.86], fill=(0x8a, 0x5a, 0x2b, 255), width=6)
    d.polygon([(S * 0.34, S * 0.16), (S * 0.76, S * 0.24), (S * 0.34, S * 0.40)], fill=col)


def _emblem_elf(d):
    col = (0x58, 0xB4, 0x6B, 255)
    d.polygon([(S * 0.38, S * 0.60), (S * 0.30, S * 0.20), (S * 0.58, S * 0.48)], fill=col)
    d.polygon([(S * 0.62, S * 0.60), (S * 0.70, S * 0.20), (S * 0.42, S * 0.48)], fill=col)
    d.line([S * 0.34, S * 0.60, S * 0.66, S * 0.60], fill=col, width=5)
    d.line([S * 0.50, S * 0.60, S * 0.50, S * 0.80], fill=col, width=4)


def _emblem_dwarf(d):
    col = (0xC2, 0x95, 0x4A, 255)
    d.line([S * 0.50, S * 0.20, S * 0.50, S * 0.80], fill=(0x8a, 0x5a, 0x2b, 255), width=8)
    d.polygon([(S * 0.50, S * 0.20), (S * 0.78, S * 0.28), (S * 0.78, S * 0.50),
               (S * 0.50, S * 0.44)], fill=col)
    d.polygon([(S * 0.50, S * 0.20), (S * 0.22, S * 0.28), (S * 0.22, S * 0.50),
               (S * 0.50, S * 0.44)], fill=darken(col, 0.85))


def _emblem_giantsblood(d):
    col = (0xE0, 0x56, 0x4F, 255)
    d.polygon([(S * 0.20, S * 0.78), (S * 0.42, S * 0.30), (S * 0.58, S * 0.60),
               (S * 0.70, S * 0.42), (S * 0.82, S * 0.78)], fill=col)
    d.ellipse([S * 0.62, S * 0.18, S * 0.80, S * 0.36], fill=(0xF2, 0xC9, 0x4C, 255))


def _emblem_orc(d):
    col = (0xE0, 0x56, 0x4F, 255)
    d.arc([S * 0.14, S * 0.40, S * 0.62, S * 1.10], 250, 340, fill=col, width=9)
    d.arc([S * 0.38, S * 0.40, S * 0.86, S * 1.10], 200, 290, fill=col, width=9)
    d.line([S * 0.30, S * 0.62, S * 0.70, S * 0.62], fill=(0x3a, 0x8a, 0x4a, 255), width=8)


def _emblem_gnome(d):
    col = (0xF2, 0xC9, 0x4C, 255)
    cx, cy, r1, r2 = S * 0.5, S * 0.52, S * 0.26, S * 0.36
    for a in range(0, 360, 45):
        rad = math.radians(a)
        x1, y1 = cx + math.cos(rad) * r2 * 0.86, cy + math.sin(rad) * r2 * 0.86
        x2, y2 = cx + math.cos(rad) * r2 * 1.14, cy + math.sin(rad) * r2 * 1.14
        d.line([x1, y1, x2, y2], fill=col, width=8)
    d.ellipse([cx - r1, cy - r1, cx + r1, cy + r1], fill=col)
    d.ellipse([cx - S * 0.08, cy - S * 0.08, cx + S * 0.08, cy + S * 0.08], fill=EMBLEM_BG)


def _emblem_troll(d):
    col = (0x8a, 0x8a, 0x96, 255)
    d.line([S * 0.30, S * 0.84, S * 0.62, S * 0.30], fill=(0x8a, 0x5a, 0x2b, 255), width=8)
    d.rounded_rectangle([S * 0.48, S * 0.16, S * 0.84, S * 0.44], radius=10, fill=col)
    d.ellipse([S * 0.54, S * 0.22, S * 0.62, S * 0.30], fill=darken((0x8a, 0x8a, 0x96, 255), 0.7))


def _emblem_dark_elf(d):
    col = (0x8A, 0x5F, 0xBF, 255)
    r = S * 0.24
    cx, cy = S * 0.50, S * 0.46
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
    d.ellipse([cx - r * 0.10 - r * 0.95, cy - r * 1.12, cx - r * 0.10 + r * 0.95, cy + r * 0.78],
              fill=EMBLEM_BG)
    d.polygon([(S * 0.60, S * 0.62), (S * 0.72, S * 0.82), (S * 0.50, S * 0.76)],
              fill=(0xC0, 0xC8, 0xD8, 255))


def _emblem_high_elf(d):
    col = (0xF2, 0xC9, 0x4C, 255)
    cx, cy = S * 0.5, S * 0.5
    for rr, w_mul in [(S * 0.30, 4), (S * 0.16, 3)]:
        pts = []
        for i in range(8):
            rad = math.radians(i * 45 - 90)
            rr2 = rr if i % 2 == 0 else rr * 0.38
            pts.append((cx + rr2 * math.cos(rad), cy + rr2 * math.sin(rad)))
        d.polygon(pts, fill=col)
    d.ellipse([cx - S * 0.05, cy - S * 0.05, cx + S * 0.05, cy + S * 0.05], fill=EMBLEM_BG)


EMBLEM_CLASSES = {
    "warrior": _emblem_warrior, "mage": _emblem_mage, "rogue": _emblem_rogue,
    "priest": _emblem_priest, "paladin": _emblem_paladin, "ranger": _emblem_ranger,
    "warlock": _emblem_warlock,
}
EMBLEM_RACES = {
    "human": _emblem_human, "elf": _emblem_elf, "dwarf": _emblem_dwarf,
    "giantsblood": _emblem_giantsblood, "orc": _emblem_orc, "gnome": _emblem_gnome,
    "troll": _emblem_troll, "dark_elf": _emblem_dark_elf, "high_elf": _emblem_high_elf,
}


def make_class_emblems():
    made = []
    for cid, fn in EMBLEM_CLASSES.items():
        img = Image.new("RGBA", (S, S), BG)
        d = ImageDraw.Draw(img)
        _emblem_base(d, EMBLEM_RING_CLASS)
        fn(d)
        path = os.path.join(UI_DIR, f"class_{cid}.png")
        img.save(path)
        made.append(path)
    return made


def make_race_emblems():
    made = []
    for rid, fn in EMBLEM_RACES.items():
        img = Image.new("RGBA", (S, S), BG)
        d = ImageDraw.Draw(img)
        _emblem_base(d, EMBLEM_RING_RACE)
        fn(d)
        path = os.path.join(UI_DIR, f"race_{rid}.png")
        img.save(path)
        made.append(path)
    return made


# ---------- 天赋节点效果图标（按 mods 键，透明底） ----------

def make_effect_icons():
    """9 种效果图标：键名 → PNG（eff_*.png），天赋节点按 mod 键引用。"""
    out = {}

    def new():
        i = Image.new("RGBA", (S, S), BG)
        return i, ImageDraw.Draw(i)

    # 伤害：红剑
    i, d = new()
    d.polygon([(S * 0.80, S * 0.12), (S * 0.88, S * 0.20), (S * 0.46, S * 0.62),
               (S * 0.38, S * 0.54)], fill=(0xE0, 0x56, 0x4F, 255))
    d.polygon([(S * 0.36, S * 0.52), (S * 0.48, S * 0.64), (S * 0.30, S * 0.82),
               (S * 0.18, S * 0.70)], fill=(0xC0, 0xC8, 0xD8, 255))
    out["eff_damage"] = i

    # 弱点：紫色裂星
    i, d = new()
    col = (0x8A, 0x5F, 0xBF, 255)
    cx, cy = S * 0.5, S * 0.52
    pts = []
    for k in range(8):
        rad = math.radians(k * 45 - 90)
        rr = S * (0.34 if k % 2 == 0 else 0.14)
        pts.append((cx + rr * math.cos(rad), cy + rr * math.sin(rad)))
    d.polygon(pts, fill=col)
    d.line([(cx - S * 0.16, cy - S * 0.10), (cx + S * 0.14, cy + S * 0.12)],
           fill=(255, 255, 255, 220), width=4)
    out["eff_weakness"] = i

    # 收入：金币叠 + 上升箭
    i, d = new()
    gold = (0xF2, 0xC9, 0x4C, 255)
    d.ellipse([S * 0.16, S * 0.56, S * 0.60, S * 0.84], fill=gold,
              outline=(0xC0, 0x8A, 0x28, 255), width=3)
    d.ellipse([S * 0.28, S * 0.44, S * 0.72, S * 0.72], fill=(0xFF, 0xE0, 0x8A, 255),
              outline=(0xC0, 0x8A, 0x28, 255), width=3)
    d.line([S * 0.40, S * 0.58, S * 0.60, S * 0.58], fill=(0xC0, 0x8A, 0x28, 255), width=4)
    d.line([S * 0.60, S * 0.44, S * 0.80, S * 0.20], fill=(0x58, 0xB4, 0x6B, 255), width=6)
    d.polygon([(S * 0.84, S * 0.12), (S * 0.82, S * 0.30), (S * 0.66, S * 0.22)],
              fill=(0x58, 0xB4, 0x6B, 255))
    out["eff_income"] = i

    # 训练：翻开的书
    i, d = new()
    cover = (0x8A, 0x5F, 0xBF, 255)
    d.polygon([(S * 0.50, S * 0.30), (S * 0.20, S * 0.36), (S * 0.20, S * 0.72),
               (S * 0.50, S * 0.78)], fill=(0x3a, 0x2f, 0x55, 255), outline=cover, width=3)
    d.polygon([(S * 0.50, S * 0.30), (S * 0.80, S * 0.36), (S * 0.80, S * 0.72),
               (S * 0.50, S * 0.78)], fill=(0x3a, 0x2f, 0x55, 255), outline=cover, width=3)
    d.line([S * 0.50, S * 0.28, S * 0.50, S * 0.80], fill=cover, width=4)
    for k in range(3):
        y = S * (0.42 + k * 0.10)
        d.line([S * 0.28, y, S * 0.46, y - S * 0.02], fill=(0xE8, 0xE0, 0xCF, 200), width=3)
        d.line([S * 0.54, y - S * 0.02, S * 0.72, y], fill=(0xE8, 0xE0, 0xCF, 200), width=3)
    out["eff_train"] = i

    # 赏金：钱袋（复用袋形）
    out["eff_bounty"] = make_line_bounty()

    # 精华：青水晶滴（复用露滴形，去星光）
    i, d = new()
    teal = (0x5F, 0xD3, 0xC9, 255)
    r = S * 0.26
    bc = (S * 0.5, S * 0.62)
    tip = (S * 0.5, S * 0.16)
    L, R = (bc[0] - r, bc[1]), (bc[0] + r, bc[1])
    right = cubic(tip, (tip[0] + S * 0.03, tip[1] + S * 0.14), (bc[0] + r * 1.02, bc[1] - r * 0.5), R)
    bottom = arc_pts(bc[0], bc[1], r, r * 0.96, 0, 180)[1:]
    left = cubic(L, (bc[0] - r * 1.02, bc[1] - r * 0.5), (tip[0] - S * 0.03, tip[1] + S * 0.14), tip)[1:]
    d.polygon(right + bottom + left, fill=teal)
    d.ellipse([bc[0] - r * 0.38, bc[1] + r * 0.08, bc[0] - r * 0.05, bc[1] + r * 0.5],
              fill=light_up(teal, 1.4))
    out["eff_ep"] = i

    # 步数：靴子
    i, d = new()
    boot = (0xE8, 0xE0, 0xCF, 255)
    d.polygon([(S * 0.30, S * 0.20), (S * 0.46, S * 0.20), (S * 0.46, S * 0.56),
               (S * 0.72, S * 0.56), (S * 0.78, S * 0.72), (S * 0.78, S * 0.80),
               (S * 0.30, S * 0.80)], fill=boot)
    d.rectangle([S * 0.30, S * 0.20, S * 0.46, S * 0.30], fill=(0xC0, 0x8A, 0x28, 255))
    out["eff_steps"] = i

    # 连锁：三环斜链
    i, d = new()
    col = (0x58, 0xB4, 0x6B, 255)
    for k, (cx, cy) in enumerate([(S * 0.28, S * 0.68), (S * 0.50, S * 0.50), (S * 0.72, S * 0.32)]):
        rr = S * 0.13
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=col, width=6)
    out["eff_chain"] = i

    # 果实：橙果 + 叶
    i, d = new()
    d.ellipse([S * 0.24, S * 0.36, S * 0.76, S * 0.88], fill=(0xE8, 0x9A, 0x4C, 255))
    d.line([S * 0.50, S * 0.36, S * 0.54, S * 0.22], fill=(0x8a, 0x5a, 0x2b, 255), width=5)
    d.polygon([(S * 0.54, S * 0.24), (S * 0.72, S * 0.14), (S * 0.62, S * 0.30)],
              fill=(0x58, 0xB4, 0x6B, 255))
    out["eff_fruit"] = i

    made = []
    for name, img in out.items():
        path = os.path.join(UI_DIR, name + ".png")
        img.save(path)
        made.append(path)
    return made


# ---------- 巅峰板块纹章（破坏冰蓝 / 经济金 / 通用绿） ----------

def _emblem_p1(d):
    """世界之冬：六臂雪花 + 中央冰晶"""
    col = (0x9A, 0xD8, 0xF0, 255)
    cx, cy = S * 0.5, S * 0.5
    for a in range(0, 360, 60):
        rad = math.radians(a)
        x2, y2 = cx + math.cos(rad) * S * 0.30, cy + math.sin(rad) * S * 0.30
        d.line([cx, cy, x2, y2], fill=col, width=7)
        for t in (0.5, 0.75):
            bx, by = cx + (x2 - cx) * t, cy + (y2 - cy) * t
            for s in (-1, 1):
                rad2 = rad + s * 0.5
                d.line([bx, by, bx + math.cos(rad2) * S * 0.06, by + math.sin(rad2) * S * 0.06],
                       fill=col, width=4)
    d.ellipse([cx - S * 0.09, cy - S * 0.09, cx + S * 0.09, cy + S * 0.09],
              fill=light_up(col, 1.3))


def _emblem_p2(d):
    """尼达维勒分号：天平（横梁 + 双盘 + 立柱）"""
    gold = (0xF2, 0xC9, 0x4C, 255)
    d.line([S * 0.26, S * 0.30, S * 0.74, S * 0.30], fill=gold, width=6)
    d.line([S * 0.50, S * 0.30, S * 0.50, S * 0.72], fill=gold, width=6)
    d.line([S * 0.36, S * 0.72, S * 0.64, S * 0.72], fill=gold, width=6)
    for sx in (S * 0.26, S * 0.74):
        d.line([sx, S * 0.30, sx, S * 0.44], fill=gold, width=4)
        d.arc([sx - S * 0.11, S * 0.40, sx + S * 0.11, S * 0.58], 0, 180, fill=gold, width=5)
    d.ellipse([S * 0.44, S * 0.20, S * 0.56, S * 0.32], fill=(0xE8, 0xE0, 0xCF, 255))


def _emblem_p3(d):
    """枝务厅编制：圆印章内嫩叶双芽"""
    col = (0x58, 0xB4, 0x6B, 255)
    d.ellipse([S * 0.18, S * 0.18, S * 0.82, S * 0.82], outline=col, width=6)
    d.line([S * 0.50, S * 0.72, S * 0.50, S * 0.44], fill=col, width=6)
    d.polygon([(S * 0.50, S * 0.48), (S * 0.28, S * 0.38), (S * 0.46, S * 0.28)], fill=col)
    d.polygon([(S * 0.50, S * 0.48), (S * 0.72, S * 0.38), (S * 0.54, S * 0.28)],
              fill=light_up(col, 1.2))
    d.ellipse([S * 0.44, S * 0.20, S * 0.56, S * 0.32], fill=(0xF2, 0xC9, 0x4C, 255))


EMBLEM_BOARDS = {
    "p1": (_emblem_p1, (0x9A, 0xD8, 0xF0, 255)),
    "p2": (_emblem_p2, (0xF2, 0xC9, 0x4C, 255)),
    "p3": (_emblem_p3, (0x58, 0xB4, 0x6B, 255)),
}


def make_board_emblems():
    made = []
    for bid, (fn, ring) in EMBLEM_BOARDS.items():
        img = Image.new("RGBA", (S, S), BG)
        d = ImageDraw.Draw(img)
        _emblem_base(d, ring)
        fn(d)
        path = os.path.join(UI_DIR, f"board_{bid}.png")
        img.save(path)
        made.append(path)
    return made


# ---------- 主流程 ----------

def main():
    global S
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=128)
    args = ap.parse_args()
    S = args.size

    tiles_dir = os.path.join(ART, "tiles")
    ui_dir = os.path.join(ART, "ui")
    os.makedirs(tiles_dir, exist_ok=True)
    os.makedirs(ui_dir, exist_ok=True)

    made = []
    sheet_rows = []
    for i, (key, _cn, color) in enumerate(ELEMENTS):
        row = []
        for tag in ["plain", "lh", "lv", "bomb"]:
            img = make_element_tile(i, key, color, tag)
            path = os.path.join(tiles_dir, f"tile_{i}_{key}_{tag}.png")
            img.save(path)
            made.append(path)
            row.append(img)
        sheet_rows.append(row)

    bird = make_bird_tile()
    bird.save(os.path.join(tiles_dir, "tile_bird.png"))
    made.append(bird)

    gil = make_gil()
    gil.save(os.path.join(ui_dir, "ui_gil.png"))
    ess = make_essence()
    ess.save(os.path.join(ui_dir, "ui_essence.png"))
    made += [gil, ess]

    # 交易所标的图标
    targets = {"target_huo": make_target_huo(), "target_feng": make_target_feng(),
               "target_sheng": make_target_sheng()}
    for name, img in targets.items():
        path = os.path.join(ui_dir, name + ".png")
        img.save(path)
        made.append(path)

    # 训练线图标
    lines = {"line_atk": make_line_atk(), "line_bounty": make_line_bounty(),
             "line_income": make_line_income()}
    for name, img in lines.items():
        path = os.path.join(ui_dir, name + ".png")
        img.save(path)
        made.append(path)

    # 职业/种族纹章
    made += make_class_emblems()
    made += make_race_emblems()

    # 天赋效果图标
    made += make_effect_icons()

    # 巅峰板块纹章
    made += make_board_emblems()

    # 预览拼图：5 行（元素4变体）+ 1 行（鸟+UI）
    pad = px(0.06)
    cols = 6
    rows = len(sheet_rows) + 1
    W = cols * S + (cols + 1) * pad
    H = rows * S + (rows + 1) * pad
    sheet = Image.new("RGBA", (W, H), (34, 32, 38, 255))
    for r, row in enumerate(sheet_rows):
        for c, img in enumerate(row):
            sheet.paste(img, (pad + c * (S + pad), pad + r * (S + pad)), img)
    extras = [bird, gil, ess]
    for c, img in enumerate(extras):
        sheet.paste(img, (pad + c * (S + pad), pad + len(sheet_rows) * (S + pad)), img)
    preview = os.path.join(ART, "preview.png")
    sheet.save(preview)

    print("OK: %d 个文件 -> %s" % (len(made) + 1, ART))
    print("preview:", preview)


if __name__ == "__main__":
    main()
