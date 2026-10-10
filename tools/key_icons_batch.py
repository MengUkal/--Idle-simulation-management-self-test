# -*- coding: utf-8 -*-
"""21 个关键天赋像素图标批量生成（ComfyUI --scene 图标模式，128×128 不抠底）。
运行前置：ComfyUI 运行中（run_lowvram.bat）。输出：assets/art/talents/<节点id>.png
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_asset as g

KEYS = [
    # 战士（红）
    ("war_key_a", "berserker warrior spirit silhouette screaming with burning red aura and greatsword"),
    ("war_key_b", "impenetrable stone bulwark wall with glowing golden rune, defensive emblem"),
    ("war_key_c", "golden loot pile with red bandit mask and dagger, plunder emblem"),
    # 法师（紫）
    ("mag_key_a", "arcane star overloading with crackling purple energy explosion"),
    ("mag_key_b", "torrent of glowing blue magic crystals flowing like a river"),
    ("mag_key_c", "ancient magic tome with glowing purple runes and a sealed eye"),
    # 盗贼（暗绿）
    ("rog_key_a", "shadowy hooded figure harvesting glowing gold coins with a curved scythe"),
    ("rog_key_b", "twin daggers crossed with lethal green speed trails"),
    ("rog_key_c", "master thief silhouette stealing a glowing teal gem in the dark"),
    # 牧师（金）
    ("pri_key_a", "radiant holy light beams blessing a small village from above"),
    ("pri_key_b", "praying hands holding an eternal golden flame"),
    ("pri_key_c", "stoic monk meditating beside a single dim candle, austere"),
    # 圣骑士（金白）
    ("pal_key_a", "gleaming hammer of light striking down with judgment sparks"),
    ("pal_key_b", "oath shield with a glowing sigil planted on the ground"),
    ("pal_key_c", "two clasped hands of light forming a guardian oath emblem"),
    # 游侠（绿）
    ("ran_key_a", "eagle eye close-up with glowing green targeting gaze"),
    ("ran_key_b", "hunting trophy plaque with horns arrows and green ribbon"),
    ("ran_key_c", "lone wanderer in a cloak walking a long road at dusk"),
    # 术士（暗紫红）
    ("wrl_key_a", "demonic contract scroll burning with dark crimson fire"),
    ("wrl_key_b", "soul wisps being harvested into a dark lantern"),
    ("wrl_key_c", "forbidden grimoire sealed with a purple eye and chains"),
]

SUFFIX = ", single emblem icon composition, centered, dark simple background"

OUT_DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                        "..", "assets", "art", "talents"))

ok_all = True
for i, (kid, prompt) in enumerate(KEYS):
    seed = 200 + i * 7
    ok = g.run_scene(prompt, kid, w=128, h=128, scale=1, seed=seed,
                     colors=32, retries=2, out_dir=OUT_DIR)
    ok_all = ok_all and ok
print("key icons done, all ok:", ok_all)
sys.exit(0 if ok_all else 1)
