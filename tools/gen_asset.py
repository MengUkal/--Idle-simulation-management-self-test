# -*- coding: utf-8 -*-
r"""怪物头像生成管线（本地 ComfyUI + DreamShaper8 + PixelArtRedmond LoRA → 像素风透明 PNG）。

前置：
  1. ComfyUI 已启动：F:\AI\ComfyUI\run_lowvram.bat（127.0.0.1:8188，仅生图时开）
  2. 模型就位：dreamshaper_8.safetensors → models/checkpoints/
              PixelArtRedmond15V.safetensors → models/loras/

用法（在游戏仓库根目录）：
  python tools/gen_asset.py --monster 树精史莱姆 --desc "green slime with a leaf on head"
  python tools/gen_asset.py --batch ../monsters.json   # 批量（名字+描述列表）
  python tools/gen_asset.py --preview                  # 拼合 assets/art/monsters 预览图

输出：挂机放置增量rpg/assets/art/monsters/<名字拼音或指定id>.png（128×128 透明底）
"""

import argparse
import json
import os
import struct
import sys
import time
import urllib.request
import urllib.error

# ---------- 配置 ----------
COMFY = "http://127.0.0.1:8188"
CKPT = "dreamshaper_8.safetensors"
LORA = "PixelArtRedmond15V.safetensors"

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
OUT_DIR = os.path.join(ROOT, "assets", "art", "monsters")

# 生成尺寸：SD1.5 原生 512，出图后降采样到 OUT_SIZE 实现像素化
GEN_SIZE = 512
OUT_SIZE = 128

# 统一风格前缀（风格一致性第一锁：所有怪物共用）
STYLE_POS = ("pixel art sprite, game monster avatar, one single creature, solo, "
             "centered, chibi proportions, cute japanese fantasy RPG style, "
             "bold dark outline, limited palette, plain white background")
STYLE_NEG = ("blurry, smooth gradients, realistic, photo, text, watermark, signature, "
             "multiple creatures, two, twins, pair, group, background scenery, "
             "grey background, gradient background, frame, border, "
             "jpeg artifacts, human, humanoid face")

# 场景图（背景/立绘）风格：不抠底，负面词不能含 scenery
SCENE_STYLE_POS = ("pixel art, japanese fantasy RPG scenery, detailed, vibrant colors, "
                   "cozy atmosphere, game background illustration")
SCENE_NEG = ("blurry, realistic, photo, text, watermark, signature, frame, border, "
             "jpeg artifacts, human, humanoid face")

# 每只怪：中文名 -> (文件名标识, 英文特征描述)。新怪加一行即可。
MONSTERS = {
    "树精史莱姆": ("slime",   "green slime monster with a small leaf sprout on head, big round eyes"),
    "風狼":       ("windwolf", "wind wolf, sleek grey-blue wolf with swirling wind trails, sharp ears"),
    "岩甲龟":     ("turtle",   "armored rock turtle, brown stone shell plates, sturdy limbs"),
    "水妖":       ("nymph",    "cute blue water blob monster, round droplet body with small splash crown on head, big eyes, floating"),
    "光萤":       ("firefly",  "glowing firefly bug monster, round chubby body with warm glowing lantern tail, tiny wings, big eyes"),
    "暗影鼠":     ("rat",      "shadow rat, dark purple mouse with smoky tail, glowing eyes"),
    "树根守卫":   ("guardian", "elite tree root guardian, gnarled wooden arms, glowing green core, imposing"),
    "荆棘树妖":   ("thorntree","thorn tree dryad, dark bark body with pink thorn flowers, sharp claws"),
    "風羽隼":     ("falcon",   "wind falcon, teal feathers, long streaming tail feathers"),
    "苔石巨人":   ("golem",    "mossy stone golem, round boulder body, moss patches, heavy fists"),
    "沼泽水灵":   ("bogspirit","swamp sludge blob monster, murky green droplet creature with reeds sprouting from head, big eyes"),
    "暗藤魔":     ("vine",     "dark thorn vine monster, writhing black thorny vines forming a small creature, single glowing red eye"),
    "辉羽蝶":     ("butterfly","radiant butterfly, glowing white-gold wings, light dust trail"),
    "守林古树":   ("ancient",  "elite ancient forest tree boss, huge face in trunk, glowing amber eyes"),
}


# ---------- ComfyUI API ----------

def api_json(path, payload=None, timeout=30):
    url = COMFY + path
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def build_workflow(pos, neg, seed, w=0, h=0):
    """SD1.5 txt2img 标准工作流（checkpoint → LoRA → 采样 → 保存）。
    pos/neg 为完整提示词（风格前缀由调用方拼好）；w/h=0 时用 GEN_SIZE。"""
    return {
        "3": {"class_type": "KSampler", "inputs": {
            "seed": seed, "steps": 24, "cfg": 7.0, "sampler_name": "euler_ancestral",
            "scheduler": "normal", "denoise": 1.0,
            "model": ["10", 0], "positive": ["6", 0], "negative": ["7", 0],
            "latent_image": ["5", 0]}},
        "4": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": CKPT}},
        "5": {"class_type": "EmptyLatentImage", "inputs": {
            "width": w or GEN_SIZE, "height": h or GEN_SIZE, "batch_size": 1}},
        "6": {"class_type": "CLIPTextEncode", "inputs": {"text": pos, "clip": ["11", 0]}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"text": neg, "clip": ["11", 0]}},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["3", 0], "vae": ["4", 2]}},
        "9": {"class_type": "SaveImage", "inputs": {"filename_prefix": "monster", "images": ["8", 0]}},
        "10": {"class_type": "LoraLoader", "inputs": {
            "lora_name": LORA, "strength_model": 1.0, "strength_clip": 1.0,
            "model": ["4", 0], "clip": ["4", 1]}},
        "11": {"class_type": "CLIPSetLastLayer", "inputs": {"stop_at_clip_layer": -2, "clip": ["10", 1]}},
    }


def gen_one(pos, neg, seed, timeout=300, w=0, h=0):
    """排队一张图，轮询到完成，返回 PNG 字节"""
    ws_data = api_json("/prompt", {"prompt": build_workflow(pos, neg, seed, w, h)})
    pid = ws_data["prompt_id"]
    t0 = time.time()
    while time.time() - t0 < timeout:
        time.sleep(2.0)
        try:
            hist = api_json("/history/" + pid)
        except urllib.error.URLError:
            continue
        if pid not in hist:
            continue
        outputs = hist[pid].get("outputs", {})
        for node in outputs.values():
            for img in node.get("images", []):
                if img.get("type") == "output":
                    q = "/view?filename={}&subfolder={}&type={}".format(
                        urllib.parse.quote(img["filename"]),
                        urllib.parse.quote(img.get("subfolder", "")),
                        img.get("type", "output"))
                    req = urllib.request.Request(COMFY + q)
                    with urllib.request.urlopen(req, timeout=60) as r:
                        return r.read()
        if hist[pid].get("status", {}).get("status_str") == "error":
            raise RuntimeError("ComfyUI 报错，prompt_id=%s" % pid)
    raise TimeoutError("生成超时（%ds）" % timeout)


# ---------- 像素化后处理 ----------

def pixelate(png_bytes, out_path):
    """512 出图 → 128 降采样 → 32 色量化 → 边缘连通白底抠透明"""
    from PIL import Image
    import io
    img = Image.open(io.BytesIO(png_bytes)).convert("RGB")
    # 1) 降采样（像素化的核心：缩小即出像素块）
    small = img.resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)
    # 2) 调色板量化锁风格
    q = small.quantize(colors=32, method=Image.MEDIANCUT).convert("RGB")
    # 3) 抠背景：四角取参考色，从边缘 flood fill（容差内才算背景，保住主体内部同色区）
    px = q.load()
    W, H = q.size

    def corner_avg(x0, y0):
        rs = gs = bs = 0
        for yy in range(y0, y0 + 6):
            for xx in range(x0, x0 + 6):
                r, g, b = px[xx, yy]
                rs += r
                gs += g
                bs += b
        return (rs // 36, gs // 36, bs // 36)

    corners = [corner_avg(0, 0), corner_avg(W - 6, 0),
               corner_avg(0, H - 6), corner_avg(W - 6, H - 6)]
    TOL = 26

    def is_bg(x, y):
        r, g, b = px[x, y]
        for cr, cg, cb in corners:
            if abs(r - cr) <= TOL and abs(g - cg) <= TOL and abs(b - cb) <= TOL:
                return True
        return False

    stack = [(x, y) for x in range(W) for y in (0, H - 1)] + \
            [(x, y) for y in range(H) for x in (0, W - 1)]
    bg = [[False] * W for _ in range(H)]
    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= W or y >= H or bg[y][x] or not is_bg(x, y):
            continue
        bg[y][x] = True
        stack.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    out = q.convert("RGBA")
    opx = out.load()
    n_trans = 0
    for y in range(H):
        for x in range(W):
            if bg[y][x]:
                opx[x, y] = (0, 0, 0, 0)
                n_trans += 1
    out.save(out_path)
    return n_trans


# ---------- 主流程 ----------

def slug_ok(name):
    for ch in name:
        if ch in '/\\:*?"<>|':
            return False
    return True


def run(monster, desc, seed=42, retries=2, min_trans=0.20):
    """生成一只怪物头像。质量门：透明率 >= min_trans 才收货，否则换 seed 重出。"""
    if monster not in MONSTERS:
        print("未知的怪物：%s（可选：%s）" % (monster, "、".join(MONSTERS)))
        return False
    slug = MONSTERS[monster][0]
    os.makedirs(OUT_DIR, exist_ok=True)
    out_path = os.path.join(OUT_DIR, slug + ".png")
    print("生成 %s（%s）seed=%d ..." % (monster, slug, seed))
    for attempt in range(retries + 1):
        cur = seed + attempt * 1000
        try:
            png = gen_one(desc + ", " + STYLE_POS, STYLE_NEG, cur)
        except Exception as e:
            print("  第 %d 次失败：%s" % (attempt + 1, e))
            if attempt == retries:
                return False
            continue
        n = pixelate(png, out_path)
        ratio = n / float(OUT_SIZE * OUT_SIZE)
        print("  第 %d 次出图：透明率 %.0f%%" % (attempt + 1, 100.0 * ratio))
        if ratio >= min_trans:
            print("  OK -> %s" % out_path)
            return True
    print("  ⚠ %d 次均低于 %.0f%%，保留最后一次（建议换描述或 --seed）" % (retries + 1, 100.0 * min_trans))
    return True


BG_DIR = os.path.join(ROOT, "assets", "art", "bg")


def run_scene(prompt, out_name, w=640, h=360, scale=1, seed=7, colors=48, retries=2):
    """场景图（背景/立绘）：不抠底；scale>1 时最近邻放大保像素感。"""
    os.makedirs(BG_DIR, exist_ok=True)
    out_path = os.path.join(BG_DIR, out_name + ".png")
    print("生成场景 %s（%dx%d, x%d）seed=%d ..." % (out_name, w, h, scale, seed))
    for attempt in range(retries + 1):
        cur = seed + attempt * 1000
        try:
            png = gen_one(prompt + ", " + SCENE_STYLE_POS, SCENE_NEG, cur, w=w, h=h)
        except Exception as e:
            print("  第 %d 次失败：%s" % (attempt + 1, e))
            if attempt == retries:
                return False
            continue
        from PIL import Image
        import io
        img = Image.open(io.BytesIO(png)).convert("RGB")
        if (img.width, img.height) != (w, h):
            img = img.resize((w, h), Image.LANCZOS)
        img = img.quantize(colors=colors, method=Image.MEDIANCUT).convert("RGB")
        if scale > 1:
            img = img.resize((w * scale, h * scale), Image.NEAREST)
        img.save(out_path)
        print("  OK -> %s" % out_path)
        return True
    return False


def preview():
    from PIL import Image
    files = sorted(f for f in os.listdir(OUT_DIR) if f.endswith(".png") and not f.startswith("_"))
    if not files:
        print("没有可预览的头像")
        return
    pad, n = 8, len(files)
    sheet = Image.new("RGBA", (n * (OUT_SIZE // 2 + pad) + pad, OUT_SIZE // 2 + 2 * pad), (34, 32, 38, 255))
    for i, f in enumerate(files):
        im = Image.open(os.path.join(OUT_DIR, f))
        im.thumbnail((OUT_SIZE // 2, OUT_SIZE // 2))
        sheet.paste(im, (pad + i * (OUT_SIZE // 2 + pad), pad), im)
    p = os.path.join(OUT_DIR, "_preview.png")
    sheet.save(p)
    print("预览：", p)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--monster", help="怪物中文名（见脚本内 MONSTERS 表）")
    ap.add_argument("--desc", help="临时英文特征描述（配合 --monster 覆盖内置描述）")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--preview", action="store_true", help="仅拼合预览图")
    ap.add_argument("--scene", help="场景模式：英文场景描述（如世界树立绘/背景）")
    ap.add_argument("--out", help="场景模式输出文件名（不含扩展名）")
    ap.add_argument("--w", type=int, default=640, help="场景模式宽度（默认 640）")
    ap.add_argument("--h", type=int, default=360, help="场景模式高度（默认 360）")
    ap.add_argument("--scale", type=int, default=1, help="场景模式最近邻放大倍数")
    args = ap.parse_args()
    if args.preview:
        preview()
        return
    if args.scene:
        if not args.out:
            ap.error("场景模式需要 --out")
        ok = run_scene(args.scene, args.out, args.w, args.h, args.scale, args.seed)
        sys.exit(0 if ok else 1)
    if not args.monster:
        ap.error("需要 --monster / --scene / --preview 之一")
    desc = args.desc or MONSTERS.get(args.monster, ("", ""))[1]
    ok = run(args.monster, desc, args.seed)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
