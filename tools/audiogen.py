#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""audiogen.py —— 程序化音频管线（音效 + BGM，纯合成、零采样、零版权风险）

哲学与 tools/artgen.py 对齐：
  - 全部资产由代码生成，参数即风格，重跑全套一致更新；
  - 内容清单见 CATALOG / SONGS，接新需求 = 加一个函数 + 登记一行；
  - 产物：SFX → assets/audio/sfx/*.wav（44.1k/16bit/mono）
          BGM → assets/audio/bgm/*.ogg（44.1k/stereo/Vorbis，循环无缝）
  - 生成后必须跑一次 godot --headless --import（见 docs/开发环境.md 的坑）。

用法：
  python tools/audiogen.py --list                 # 列出资产目录
  python tools/audiogen.py --demo                 # 风格样张 → docs/音频样张/（含 BGM 的 mp3 预览副本）
  python tools/audiogen.py --all                  # 全量 → assets/audio/
  python tools/audiogen.py --only ui_click,level_up [--outdir X]
依赖：numpy / scipy / soundfile（pip 安装，详见 docs/音频制作计划.md）
"""
import argparse
import os
import sys

import numpy as np
from scipy import signal as sps
import soundfile as sf

SR = 44100
rng = np.random.default_rng(20261010)

# ---------------------------------------------------------------- 基础 DSP


def t_axis(dur):
    return np.arange(int(round(dur * SR))) / SR


def adsr(n, a=0.005, d=0.05, s=0.7, r=0.1):
    """包络：总长 n 个采样；a/d/r 单位秒。s=持续电平(0~1)。"""
    env = np.full(n, float(s))
    na, nd, nr = (int(x * SR) for x in (a, d, r))
    na, nd, nr = min(na, n), min(nd, max(n - na, 0)), min(nr, n)
    if na:
        env[:na] = np.linspace(0, 1, na, endpoint=False)
    if nd:
        env[na:na + nd] = np.linspace(1, s, nd, endpoint=False)
    if nr:
        env[n - nr:] *= np.linspace(1, 0, nr)
    return env


def osc(freq, dur, kind="sine", detune=0.0, vib_hz=0.0, vib_amt=0.0):
    t = t_axis(dur)
    f = np.full_like(t, float(freq))
    if detune:
        f *= 2 ** (detune / 1200.0)
    if vib_hz:
        f *= 2 ** (vib_amt * np.sin(2 * np.pi * vib_hz * t) / 1200.0)
    ph = 2 * np.pi * np.cumsum(f) / SR
    if kind == "sine":
        return np.sin(ph)
    if kind == "saw":
        return sps.sawtooth(ph)
    if kind == "square":
        return sps.square(ph, 0.5)
    if kind == "triangle":
        return sps.sawtooth(ph, 0.5)
    raise ValueError(kind)


def sweep(f0, f1, dur, kind="sine", curve=1.0):
    t = t_axis(dur)
    k = (t / max(t[-1], 1e-9)) ** curve if len(t) else t
    f = f0 * (f1 / f0) ** k
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def noise(dur):
    return rng.standard_normal(int(round(dur * SR)))


def _butter(x, fc, kind, order=2):
    fc = min(max(fc, 20.0), SR * 0.45)
    sos = sps.butter(order, fc / (SR * 0.5), kind, output="sos")
    return sps.sosfilt(sos, x)


def lp(x, fc, order=2):
    return _butter(np.asarray(x, float), fc, "low", order)


def hp(x, fc, order=2):
    return _butter(np.asarray(x, float), fc, "high", order)


def bp(x, lo, hi, order=2):
    return _butter(_butter(np.asarray(x, float), lo, "high", order), hi, "low", order)


def _lfiir(x, dly, b_head, a_tail):
    """y[n] = b_head·x[..] + a_tail·y[..] 的通用梳状实现（dly=延迟采样数）。"""
    dly = int(dly)
    b = np.zeros(dly + 1); a = np.zeros(dly + 1)
    b[:len(b_head)] = b_head; b[dly] = max(b[dly], b_head[-1] if b_head[-1] else 0)
    b[dly] = b_head[-1] if dly >= len(b_head) - 1 else b[dly]
    a[dly] = a_tail
    return sps.lfilter(b, a, x)


def comb(x, dly, g):
    return sps.lfilter([1.0], np.concatenate(([1.0], np.zeros(int(dly) - 1), [-g])), x)


def allpass(x, dly, g):
    dly = int(dly)
    b = np.concatenate(([-g], np.zeros(dly - 1), [1.0]))
    a = np.concatenate(([1.0], np.zeros(dly - 1), [-g]))
    return sps.lfilter(b, a, x)


def reverb(x, mix=0.25, spread=0):
    """Schroeder 混响；spread 用于生成右声道（延迟错开）。"""
    x = np.asarray(x, float)
    ds = [1557, 1617, 1491, 1422]
    aps = [225, 556]
    y = np.zeros_like(x)
    for i, d in enumerate(ds):
        y += comb(x, d + spread * (i + 1) * 7, 0.76)
    y /= len(ds)
    for d in aps:
        y = allpass(y, d + spread * 11, 0.5)
    return y * mix + x * (1 - mix)


def pan(x, p=0.0):
    """p∈[-1,1] → 立体声 (L,R)，恒功率。"""
    th = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(th), x * np.sin(th)], axis=1)


def normalize(x, peak_db=-3.0):
    x = np.asarray(x, float)
    m = np.max(np.abs(x))
    if m > 0:
        x = x / m * (10 ** (peak_db / 20))
    return x


def softclip(x):
    x = np.asarray(x, float)
    m = np.max(np.abs(x))
    if m > 0.95:
        x = np.tanh(1.4 * x / m) / np.tanh(1.4) * m * 0.98
    return x


def place(buf, x, t_sec, gain=1.0):
    i = int(round(t_sec * SR))
    if i >= len(buf):
        return
    x = np.asarray(x, float) * gain
    j = min(i + len(x), len(buf))
    seg = x[: j - i]
    if seg.ndim == 1 and buf.ndim == 2:
        seg = seg[:, None]
    buf[i:j] += seg


def fade_edges(x, fin=0.002, fout=0.01):
    x = np.asarray(x, float).copy()
    ni, nf = int(fin * SR), int(fout * SR)
    ni, nf = min(ni, len(x)), min(nf, len(x))
    if ni:
        x[:ni] *= np.linspace(0, 1, ni)
    if nf:
        x[-nf:] *= np.linspace(1, 0, nf)
    return x


def loop_fold(x, total_n, tail_n):
    """把渲染时多出来的混响尾巴折回开头 → 无缝循环。"""
    out = np.array(x[:total_n], float, copy=True)
    tail = x[total_n: total_n + tail_n]
    out[: len(tail)] += tail
    return out


def n2f(midi):
    return 440.0 * 2 ** ((midi - 69) / 12.0)


# ---------------------------------------------------------------- 音色库


def bell(f0, dur, bright=1.0, decay=3.0):
    t = t_axis(dur)
    partials = [(1.0, 1.0), (2.76, 0.45 * bright), (5.40, 0.22 * bright), (8.93, 0.10 * bright)]
    y = np.zeros_like(t)
    for r, a in partials:
        y += a * np.sin(2 * np.pi * f0 * r * t) * np.exp(-decay * r * t)
    return y * adsr(len(t), a=0.002, d=dur * 0.4, s=0.25, r=dur * 0.3)


def pluck(f0, dur, damp=4.0, bright=1.0):
    """加法拨弦（竖琴/木琴族）：谐波各自衰减。"""
    t = t_axis(dur)
    y = np.zeros_like(t)
    for h in range(1, 7):
        a = bright ** (h - 1) / h
        if a < 0.01:
            break
        y += a * np.sin(2 * np.pi * f0 * h * t) * np.exp(-damp * h ** 0.8 * t)
    return fade_edges(y * adsr(len(t), 0.002, dur * 0.3, 0.2, dur * 0.2), fout=0.005)


def pluck_ks(f0, dur, decay=0.996):
    """Karplus-Strong 拨弦（木吉他感）。分块向量化。"""
    p = max(2, int(round(SR / f0)))
    n = int(round(dur * SR))
    blocks = n // p + 2
    buf = rng.standard_normal((blocks, p)) * adsr(p, 0.001, 0.02, 0.8, 0.0)
    prev_last = 0.0
    for k in range(2, blocks):
        b1 = buf[k - 1]
        nxt = decay * 0.5 * (b1 + np.concatenate(([prev_last], b1[:-1])))
        buf[k] = nxt
        prev_last = b1[-1]
    y = buf.reshape(-1)[:n]
    return fade_edges(lp(y, 5200, 2) * adsr(n, 0.001, dur * 0.5, 0.3, dur * 0.25), fout=0.004)


def pad(freqs, dur, cutoff=1100.0, level=1.0):
    t = t_axis(dur)
    y = np.zeros_like(t)
    for f in freqs:
        for det in (-7, 0, 7):
            y += osc(f, dur, "saw", detune=det, vib_hz=0.18, vib_amt=4)
    y = lp(y / (len(freqs) * 3), cutoff, 2)
    return y * level * adsr(len(t), a=dur * 0.3, d=dur * 0.2, s=0.8, r=dur * 0.35)


def choir(freqs, dur, level=1.0):
    t = t_axis(dur)
    y = np.zeros_like(t)
    for f in freqs:
        y += osc(f, dur, "saw", vib_hz=5.0, vib_amt=6)
        y += 0.5 * osc(f * 2.0, dur, "sine", vib_hz=4.7, vib_amt=5)
    y = lp(y / (2 * len(freqs)), 900, 2)
    breath = bp(noise(dur), 500, 2500) * 0.02
    return (y + breath) * level * adsr(len(t), a=dur * 0.35, d=dur * 0.2, s=0.85, r=dur * 0.4)


def flute(f0, dur, level=1.0):
    y = osc(f0, dur, "sine", vib_hz=5.2, vib_amt=7)
    y += 0.12 * osc(f0 * 2, dur, "sine")
    y += 0.05 * bp(noise(dur), f0 * 0.9, f0 * 2.5)
    return y * level * adsr(len(t_axis(dur)), a=0.06, d=0.1, s=0.8, r=0.12)


def kick(dur=0.25, f0=120, f1=44, level=1.0):
    y = sweep(f0, f1, dur, curve=0.5) * np.exp(-9 * t_axis(dur))
    click = hp(noise(0.01), 2000) * 0.4
    y[: len(click)] += click
    return y * level


def shaker(dur=0.07, level=1.0):
    return hp(noise(dur), 6000) * np.exp(-40 * t_axis(dur)) * level


def tamb(dur=0.09, level=1.0):
    y = bp(noise(dur), 4000, 12000)
    return y * np.exp(-28 * t_axis(dur)) * level


def whoosh(dur, lo=300, hi=2400, up=True, level=1.0):
    """中心频率扫动的带通噪声。"""
    seg = 10
    n = int(round(dur * SR))
    out = np.zeros(n)
    edge = np.linspace(0, n, seg + 1).astype(int)
    for i in range(seg):
        a, b = edge[i], edge[i + 1]
        k = i / (seg - 1)
        k = k if up else 1 - k
        fc = lo * (hi / lo) ** k
        seg_n = np.clip(b - a + 400, 1, n - a)  # 段间重叠 400 采样
        x = noise(seg_n / SR)
        out[a:a + seg_n] += bp(x, fc * 0.6, fc * 1.6)
    out /= seg * 0.35
    return fade_edges(out, 0.02, 0.03) * level * adsr(n, 0.15, 0.2, 0.9, 0.25)


def zap(f0, f1, dur, level=1.0):
    y = sweep(f0, f1, dur, curve=1.3)
    y += 0.3 * sweep(f0 * 2, f1 * 2, dur, curve=1.3)
    return fade_edges(y * np.exp(-2.5 * t_axis(dur)) * level, 0.002, 0.01)


def thud(dur=0.28, f0=95, level=1.0):
    y = sweep(f0, f0 * 0.55, dur, curve=0.6) * np.exp(-11 * t_axis(dur))
    y += lp(noise(dur), 300) * np.exp(-20 * t_axis(dur)) * 0.7
    return fade_edges(y * level, 0.001, 0.02)


def coin_hit(f0=1980, dur=0.16, level=1.0):
    t = t_axis(dur)
    y = np.sin(2 * np.pi * f0 * t) + 0.6 * np.sin(2 * np.pi * f0 * 1.502 * t)
    return fade_edges(y * np.exp(-18 * t) * level, 0.001, 0.02)


def sparkle(dur=0.8, base=1760, n=6, level=1.0, spread=0.5):
    buf = np.zeros(int(dur * SR))
    bd = min(0.3, max(0.08, dur - 0.05))
    hi = max(0.01, dur - bd - 0.01)
    for i in range(n):
        f = base * 2 ** (rng.integers(0, 8) / 12)
        place(buf, bell(f, bd, bright=1.2, decay=6), rng.uniform(0, hi), 0.5)
    return fade_edges(normalize(buf, 0) * level, 0.005, 0.05) if np.max(np.abs(buf)) > 0 else buf


# ---------------------------------------------------------------- SFX 合成器


def s_ui_click():
    dur = 0.05
    y = osc(1250, dur) * np.exp(-70 * t_axis(dur))
    n = noise(0.03)
    y[: len(n)] += hp(n, 3000) * np.exp(-160 * t_axis(0.03)) * 0.5
    return normalize(fade_edges(y, 0.001, 0.01), -9)


def s_ui_open():
    y = whoosh(0.28, 500, 2600, up=True, level=0.8)
    y += 0.4 * np.concatenate((np.zeros(int(0.1 * SR)), osc(880, 0.18) * adsr(int(0.18 * SR), 0.01, 0.05, 0.4, 0.08)))
    return normalize(y, -10)


def s_ui_close():
    y = whoosh(0.24, 2200, 500, up=False, level=0.8)
    return normalize(y, -10)


def s_level_up():
    notes = [62, 66, 69, 74]  # D4 F#4 A4 D5
    buf = np.zeros(int(1.0 * SR))
    for i, m in enumerate(notes):
        place(buf, pluck(n2f(m), 0.7, damp=3.5), i * 0.09, 0.9)
        place(buf, bell(n2f(m + 12), 0.5, bright=0.8, decay=4), i * 0.09 + 0.02, 0.35)
    place(buf, reverb(buf[: int(0.4 * SR)], 0.3), 0.35, 0.5)
    return normalize(softclip(buf), -6)


def s_money_not_enough():
    seg = []
    for _ in range(2):
        y = osc(105, 0.11, "square") * adsr(int(0.11 * SR), 0.004, 0.02, 0.6, 0.04)
        seg.append(lp(y, 700))
    buf = np.concatenate([seg[0], np.zeros(int(0.05 * SR)), seg[1]])
    return normalize(fade_edges(buf, 0.002, 0.02), -8)


def s_essence_gain():
    y = bell(n2f(81), 0.5, bright=1.3, decay=5)
    y2 = np.concatenate((np.zeros(int(0.07 * SR)), bell(n2f(88), 0.43, bright=1.3, decay=5)))
    y[: len(y2)] += 0.5 * y2
    return normalize(y, -8)


def s_line_up():
    buf = np.zeros(int(0.4 * SR))
    place(buf, pluck(n2f(69), 0.3), 0.0, 0.9)
    place(buf, pluck(n2f(76), 0.35), 0.1, 0.9)
    return normalize(buf, -8)


def s_floor_unlock():
    buf = np.zeros(int(1.3 * SR))
    th = thud(0.2, 130)  # 枝务厅"盖章"
    n = hp(noise(0.08), 1500) * np.exp(-60 * t_axis(0.08)) * 0.8
    th[: len(n)] += n
    place(buf, th, 0.0, 0.9)
    for i, m in enumerate([62, 66, 69, 74, 78]):
        place(buf, bell(n2f(m), 0.8, bright=0.9, decay=3), 0.25 + i * 0.06, 0.5)
    return normalize(softclip(buf), -6)


def s_floor_switch():
    return normalize(whoosh(0.7, 250, 3000, up=True, level=0.9), -9)


def s_rebirth():
    dur = 6.0
    buf = np.zeros(int(dur * SR))
    place(buf, whoosh(3.2, 200, 1800, up=True, level=0.5), 0.0, 0.7)          # 世界之冬的风
    place(buf, bell(n2f(38), 2.5, bright=0.7, decay=1.6), 1.2, 0.9)           # 深钟 D2
    place(buf, choir([n2f(50), n2f(57), n2f(62), n2f(66)], 3.4, level=0.8), 2.4, 0.75)  # D A D F#
    place(buf, sparkle(1.6, base=1174, n=8, level=0.7), 3.4, 0.6)             # 果实微光
    place(buf, bell(n2f(74), 1.6, bright=1.1, decay=2.5), 4.0, 0.5)
    st = pan(np.stack([reverb(buf[:, 0], 0.3), reverb(buf[:, 1], 0.3, spread=1)], 1), 0.0) if buf.ndim == 2 else None
    return normalize(softclip(buf), -5)


def s_swap_ok():
    y = zap(520, 880, 0.08)
    k = pluck_ks(660, 0.08, 0.99)
    y[: len(k)] += 0.4 * k
    return normalize(fade_edges(y, 0.002, 0.01), -8)


def s_swap_fail():
    y = thud(0.16, 80)
    y += 0.5 * osc(140, 0.16, "triangle") * np.exp(-18 * t_axis(0.16))
    return normalize(y, -8)


def s_clear_normal():
    """普通消除（六色通用）：暖噗 + D 调中性短音，信息量轻。"""
    dur = 0.26
    y = sweep(190, 88, dur, curve=0.8) * np.exp(-10 * t_axis(dur))
    n = lp(noise(dur), 2800) * np.exp(-16 * t_axis(dur))
    y[: len(n)] += 0.55 * n
    p = pluck(n2f(62), 0.2, damp=7, bright=0.6)
    y[: len(p)] += 0.5 * p
    return normalize(fade_edges(y, 0.002, 0.02), -6)


def s_clear_effective():
    """克制命中：明显更奖励——上扫 zap + 亮铃 A5 + 微光 + 低频分量。"""
    dur = 0.42
    buf = np.zeros(int(dur * SR))
    place(buf, zap(620, 2100, 0.16), 0.0, 0.9)
    place(buf, sweep(160, 70, 0.3, curve=0.6) * np.exp(-9 * t_axis(0.3)), 0.0, 0.8)
    place(buf, bell(n2f(81), 0.35, bright=1.3, decay=5), 0.05, 0.8)
    sp = sparkle(dur, base=1976, n=5, level=0.9)
    i = int(0.08 * SR)
    buf[i: i + len(sp)] += sp[: len(buf) - i]
    return normalize(softclip(buf), -5)


def s_special_line():
    y = zap(700, 2600, 0.13)
    b = bell(n2f(86), 0.13, bright=1.2, decay=8)
    y[: len(b)] += 0.4 * b
    return normalize(y, -6)


def s_special_bomb():
    dur = 0.5
    y = sweep(150, 40, dur, curve=0.5) * np.exp(-7 * t_axis(dur))
    y += lp(noise(dur), 900) * np.exp(-9 * t_axis(dur)) * 1.1
    c = hp(noise(0.05), 2500) * np.exp(-60 * t_axis(0.05)) * 0.8
    y[: len(c)] += c
    return normalize(softclip(y), -5)


def s_special_bird():
    buf = np.zeros(int(0.75 * SR))
    place(buf, whoosh(0.45, 400, 3200, up=True, level=0.8), 0.0, 0.9)
    for i, m in enumerate([74, 78, 81, 86]):                       # D 大调碎金上行
        place(buf, bell(n2f(m), 0.4, bright=1.3, decay=5), 0.18 + i * 0.055, 0.55)
    return normalize(buf, -6)


def s_skill_cast():
    """职业技能施法（七职业通用）：凝聚上扬 + 低频落点 + 钟音尾韵（区别于 special_* 的炸裂感）。"""
    dur = 0.55
    buf = np.zeros(int(dur * SR))
    place(buf, sweep(180, 760, 0.28, curve=1.2) * np.exp(-5 * t_axis(0.28)), 0.0, 0.85)
    n = bp(noise(0.25), 500, 2400) * np.exp(-9 * t_axis(0.25))
    place(buf, n, 0.10, 0.7)
    place(buf, sweep(90, 46, 0.3, curve=0.6) * np.exp(-8 * t_axis(0.3)), 0.12, 0.9)
    place(buf, bell(n2f(74), 0.45, bright=1.1, decay=4), 0.24, 0.5)
    return normalize(softclip(buf), -5)


def s_skill_ready():
    """充能型技能充能完成：暖双音上行 + 微光（区别于 essence_gain 的水晶叮）。"""
    buf = np.zeros(int(0.45 * SR))
    place(buf, bell(n2f(81), 0.3, bright=0.9, decay=6), 0.0, 0.7)
    place(buf, bell(n2f(86), 0.35, bright=1.0, decay=5), 0.09, 0.8)
    sp = sparkle(0.3, base=2349, n=3, level=0.6)
    i = int(0.1 * SR)
    buf[i: i + len(sp)] += sp[: len(buf) - i]
    return normalize(buf, -8)


def s_combo_chain():
    """连锁计时音：游戏里用 pitch_scale 按连击数升调。"""
    y = pluck(n2f(74), 0.12, damp=9, bright=0.7)
    o = osc(1480, 0.05) * np.exp(-80 * t_axis(0.05))
    y[: len(o)] += 0.5 * o
    return normalize(fade_edges(y, 0.002, 0.01), -7)


def s_monster_hit():
    y = thud(0.14, 140)
    c = hp(noise(0.05), 1200) * np.exp(-50 * t_axis(0.05)) * 0.5
    y[: len(c)] += c
    return normalize(y, -9)


def s_monster_die():
    dur = 0.5
    y = lp(noise(dur), 2400) * np.exp(-10 * t_axis(dur)) * 0.9     # 碎裂
    sw = sweep(300, 90, dur * 0.5, curve=0.7) * np.exp(-12 * t_axis(dur * 0.5)) * 0.7
    y[: len(sw)] += sw
    for i, m in enumerate([74, 78]):                               # 金色小尾巴
        place(y, bell(n2f(m), 0.25, bright=1.1, decay=7), 0.2 + i * 0.07, 0.4)
    return normalize(y, -6)


def s_battle_win():
    seq = [(0.0, 62), (0.12, 66), (0.24, 69), (0.36, 74), (0.62, 74)]
    buf = np.zeros(int(1.7 * SR))
    for i, (tt, m) in enumerate(seq):
        g = 0.9 if i < 4 else 1.0
        place(buf, bell(n2f(m + 12), 0.7, bright=0.9, decay=3.2), tt, 0.6 * g)
        place(buf, pluck(n2f(m), 0.5, damp=4), tt, 0.5 * g)
    p = pad([n2f(50), n2f(57), n2f(62)], 1.0, cutoff=800, level=0.25) * adsr(int(1.0 * SR), 0.2, 0.2, 0.8, 0.4)
    buf[: len(p)] += p
    return normalize(softclip(buf), -6)


def s_battle_retreat():
    seq = [(0.0, 69), (0.22, 65), (0.44, 62)]
    buf = np.zeros(int(1.0 * SR))
    for tt, m in seq:
        place(buf, bell(n2f(m), 0.5, bright=0.6, decay=4), tt, 0.7)
    return normalize(buf, -8)


def s_trade_buy():
    buf = np.zeros(int(0.35 * SR))
    place(buf, coin_hit(1900), 0.0, 0.9)
    place(buf, coin_hit(2400), 0.07, 0.9)
    return normalize(buf, -7)


def s_trade_sell():
    buf = np.zeros(int(0.5 * SR))
    for i, f in enumerate((2400, 2100, 2600, 2250)):
        place(buf, coin_hit(f, 0.14), i * 0.055 + rng.uniform(0, 0.012), 0.8)
    return normalize(buf, -7)


def s_save_tick():
    y = osc(1800, 0.03) * np.exp(-120 * t_axis(0.03)) * 0.4
    return normalize(fade_edges(y, 0.001, 0.008), -18)             # 刻意极轻


# ---------------------------------------------------------------- 音序器（BGM）

def seq_render(song, seed=20261010):
    """song: dict(bpm, bars(和弦列表), layers=[fn(bar_idx, chord, bar_t0, buf)])→buf(tail 已含)"""
    r = np.random.default_rng(seed)
    bar_sec = 60.0 / song["bpm"] * 4
    n_bars = len(song["bars"])
    total = int(round(n_bars * bar_sec * SR))
    tail = int(1.2 * SR)
    buf = np.zeros((total + tail, 2))
    ctx = {"rng": r, "bar_sec": bar_sec, "total": total}
    for bar_idx, chord in enumerate(song["bars"]):
        for layer in song["layers"]:
            layer(bar_idx, chord, bar_idx * bar_sec, buf, ctx)
    return buf, total, tail, bar_sec


def _layer_guitar_arp(pattern):
    """pattern(chord, bar_idx, rng) → [(step16, midi, dur_sec)]"""
    step = 60.0

    def layer(bar_idx, chord, t0, buf, ctx):
        for st, deg, dur in pattern(chord, bar_idx, ctx["rng"]):
            m = chord[deg % len(chord)] + 12 * (deg // len(chord))
            place(buf, pan(pluck_ks(n2f(m), dur, 0.995), -0.25), t0 + st / 16 * ctx["bar_sec"], 0.5)
    return layer


def _bass_midi(m):
    """把任意和弦音钳到 E2~D3 的低音音域。"""
    while m < 40:
        m += 12
    while m > 52:
        m -= 12
    return m


def _layer_bass(levels=(1, 3)):
    def layer(bar_idx, chord, t0, buf, ctx):
        root = _bass_midi(chord[0]) - 12
        for beat in levels:
            dur = ctx["bar_sec"] / 4 * 1.6
            y = osc(n2f(root), dur, "sine") + 0.3 * osc(n2f(root + 12), dur, "triangle")
            place(buf, y * adsr(len(y), 0.004, 0.1, 0.5, 0.15), t0 + (beat - 1) * ctx["bar_sec"] / 4, 0.55)
    return layer


def _layer_oompah(gain=0.5):
    """根-五(七)度交替的四拍低音（波尔卡/侏儒商会感）。"""
    def layer(bar_idx, chord, t0, buf, ctx):
        for beat in range(4):
            m = _bass_midi(chord[0] if beat % 2 == 0 else chord[-1]) - 12
            dur = ctx["bar_sec"] / 4 * 1.4
            y = osc(n2f(m), dur, "sine") + 0.3 * osc(n2f(m + 12), dur, "triangle")
            place(buf, y * adsr(len(y), 0.004, 0.08, 0.5, 0.12), t0 + beat * ctx["bar_sec"] / 4, gain)
    return layer


def _layer_melody(notes_by_bar, timbre="bell", gain=0.5, pan_p=0.15):
    """notes_by_bar: list[list[(step16, midi, dur_sec)]]，长度须 = bars 数（None=休止小节）"""

    def layer(bar_idx, chord, t0, buf, ctx):
        ev = notes_by_bar[bar_idx] if bar_idx < len(notes_by_bar) else None
        if not ev:
            return
        for st, m, dur in ev:
            if timbre == "bell":
                y = bell(n2f(m), dur, bright=1.0, decay=3.5)
            elif timbre == "flute":
                y = flute(n2f(m), dur)
            elif timbre == "accord":
                y = lp(osc(n2f(m), dur, "square", vib_hz=5.5, vib_amt=8), 2200)
                y *= adsr(len(y), 0.02, 0.08, 0.75, 0.1)
            else:
                y = pluck(n2f(m), dur)
            place(buf, pan(y, pan_p), t0 + st / 16 * ctx["bar_sec"], gain)
    return layer


def _layer_perc(kind="shaker", steps=(0, 2, 4, 6, 8, 10, 12, 14), gain=0.16, skip=None):
    def layer(bar_idx, chord, t0, buf, ctx):
        if skip and skip(bar_idx):
            return
        for st in steps:
            y = shaker() if kind == "shaker" else tamb() if kind == "tamb" else kick()
            place(buf, pan(y, 0.2 if kind != "kick" else 0.0), t0 + st / 16 * ctx["bar_sec"], gain)
    return layer


def _layer_kick(steps=(0, 8), gain=0.35):
    def layer(bar_idx, chord, t0, buf, ctx):
        for st in steps:
            place(buf, kick(), t0 + st / 16 * ctx["bar_sec"], gain)
    return layer


def _layer_pad(voicing, gain=0.22):
    def layer(bar_idx, chord, t0, buf, ctx):
        dur = ctx["bar_sec"] * 1.05
        ms = voicing(chord)
        y = pad([n2f(m) for m in ms], dur, cutoff=900)
        place(buf, y, t0, gain)
    return layer


def _bgm_floor1():
    """一层·树根之街 v2：D 大调民谣。FF6 式和声色彩（含 6/7 音）、主题动机 a-b-a-c、
    长笛低八度对答、A 段轻打击 / A' 段铃鼓加厚的编曲层次。96bpm · 16 小节 · 40s。"""
    bpm = 96
    q = 60.0 / bpm
    D, G, FSm, A, Bm = [50, 54, 57], [55, 59, 62], [54, 57, 61], [57, 61, 64], [47, 50, 54]
    bars = [D, G, FSm, A, D, Bm, G, A, D, G, FSm, A, Bm, G, A, D]

    def arp(chord, bar_idx, r):
        order = (0, 1, 2, 3, 2, 3, 1, 2, 0, 2, 1, 3, 2, 3, 2, 1)
        out = []
        for i in range(16):
            d = order[i]
            m = chord[d % len(chord)] + 12 * (1 if d >= len(chord) else 0) + 12
            out.append((i, m, 0.30))
        return out

    def sec(events):
        return [(st, m, b * q) for st, m, b in events]

    # 主题动机：a(0-1) a'(2-3) b(4-5) c(6-7) + A' 段加密变奏(8-15)
    mel = [[] for _ in range(16)]
    mel[0] = sec([(6, 74, 0.5), (8, 78, 0.75), (12, 81, 1.0)])
    mel[1] = sec([(0, 83, 0.75), (4, 81, 0.5), (6, 78, 0.5), (8, 74, 2.0)])
    mel[2] = sec([(6, 74, 0.5), (8, 81, 0.75), (12, 78, 1.0)])
    mel[3] = sec([(0, 73, 0.75), (4, 69, 0.5), (6, 73, 0.5), (8, 74, 2.0)])
    mel[4] = sec([(6, 74, 0.5), (8, 78, 0.75), (12, 81, 1.0)])
    mel[5] = sec([(0, 86, 0.75), (4, 83, 0.75), (8, 78, 2.0)])
    mel[6] = sec([(0, 79, 0.75), (4, 81, 0.5), (6, 83, 0.5), (8, 78, 0.75), (12, 74, 1.0)])
    mel[7] = sec([(0, 76, 1.0), (8, 73, 3.0)])
    mel[8] = sec([(0, 74, 0.5), (2, 76, 0.5), (4, 78, 0.75), (8, 81, 1.5)])
    mel[9] = sec([(0, 83, 0.5), (2, 81, 0.5), (4, 78, 0.5), (6, 81, 0.5), (8, 83, 2.0)])
    mel[10] = sec([(6, 81, 0.5), (8, 78, 0.75), (12, 74, 1.5)])
    mel[11] = sec([(0, 73, 0.75), (4, 76, 0.75), (8, 78, 2.0)])
    mel[12] = sec([(0, 74, 0.5), (4, 78, 0.5), (8, 81, 0.5), (12, 83, 1.5)])
    mel[13] = sec([(0, 81, 0.75), (4, 78, 0.75), (8, 74, 2.0)])
    mel[14] = sec([(0, 73, 0.5), (2, 74, 0.5), (4, 76, 0.5), (6, 78, 0.5), (8, 79, 2.0)])
    mel[15] = sec([(0, 74, 3.0), (12, 69, 0.5), (14, 71, 0.5)])

    # 长笛对答：旋律休止处补句（低八度，音量小）
    ans = [[] for _ in range(16)]
    ans[1] = sec([(8, 62, 2.0)])
    ans[3] = sec([(8, 64, 2.0)])
    ans[5] = sec([(8, 59, 2.0)])
    ans[7] = sec([(8, 57, 2.0)])
    ans[9] = sec([(8, 62, 2.0)])
    ans[11] = sec([(8, 64, 2.0)])
    ans[13] = sec([(8, 59, 2.0)])
    ans[14] = sec([(8, 57, 1.0), (12, 61, 1.5)])

    layers = [
        _layer_pad(lambda c: c, gain=0.15),
        _layer_bass(),
        _layer_guitar_arp(arp),
        _layer_melody(mel, "bell", gain=0.42, pan_p=0.3),
        _layer_melody(ans, "flute", gain=0.20, pan_p=-0.35),
        _layer_perc("shaker", (0, 2, 4, 6, 8, 10, 12, 14), 0.09, skip=lambda b: b >= 8),
        _layer_perc("tamb", (4, 12), 0.15, skip=lambda b: b < 8),
        _layer_kick((0, 8), 0.22),
    ]
    return dict(bpm=bpm, bars=bars, layers=layers, name="bgm_floor1", desc="一层·树根之街")


def _bgm_floor2():
    """二层·翠枝回廊 v2：A 大调（maj7 色彩）。竖琴十六分琶音 + 长笛完整长句，
    后 8 小节旋律加密 + 风铃变密（翠枝高处风更活跃）。84bpm · 16 小节 · 45.7s。"""
    bpm = 84
    q = 60.0 / bpm
    A, FSm7, D, E = [57, 61, 64, 68], [54, 57, 61, 64], [50, 54, 57, 61], [52, 56, 59, 64]
    bars = [A, FSm7, D, E] * 4

    def arp(chord, bar_idx, r):
        order = (0, 2, 1, 3, 2, 4, 3, 2, 0, 2, 1, 3, 2, 4, 3, 2)
        out = []
        for i in range(16):
            d = order[i]
            m = chord[d % len(chord)] + 12 * (1 if d >= len(chord) else 0)
            out.append((i, m, 0.5))
        return out

    def sec(events):
        return [(st, m, b * q) for st, m, b in events]

    mel = [[] for _ in range(16)]
    mel[0] = sec([(0, 76, 1.5), (6, 78, 1.0), (12, 81, 1.8)])
    mel[1] = sec([(0, 76, 1.5), (8, 78, 2.4)])
    mel[2] = sec([(0, 78, 1.5), (8, 74, 2.4)])
    mel[3] = sec([(0, 76, 1.0), (6, 73, 1.0), (12, 76, 1.8)])
    mel[4] = sec([(0, 81, 1.5), (8, 83, 2.4)])
    mel[5] = sec([(0, 85, 1.5), (8, 81, 1.0), (12, 78, 1.8)])
    mel[6] = sec([(0, 78, 2.0), (8, 74, 2.4)])
    mel[7] = sec([(0, 76, 3.5)])
    mel[8] = sec([(0, 76, 1.0), (4, 78, 1.0), (8, 81, 1.0), (12, 80, 1.0)])
    mel[9] = sec([(0, 83, 1.2), (6, 81, 0.8), (12, 78, 1.8)])
    mel[10] = sec([(0, 78, 1.2), (8, 81, 1.0), (12, 83, 1.6)])
    mel[11] = sec([(0, 80, 1.0), (4, 78, 1.0), (8, 76, 2.4)])
    mel[12] = sec([(0, 86, 1.5), (8, 85, 2.0)])
    mel[13] = sec([(0, 81, 1.5), (8, 76, 2.2)])
    mel[14] = sec([(0, 78, 1.0), (4, 80, 1.0), (8, 81, 1.0), (12, 83, 1.8)])
    mel[15] = sec([(0, 81, 4.0)])

    def chimes(bar_idx, chord, t0, buf, ctx):
        r = ctx["rng"]
        if bar_idx >= 8 and r.random() < 0.6:
            st = int(r.integers(0, 16))
            m = 88 + int(r.integers(0, 5))
            place(buf, pan(bell(n2f(m), 0.6, bright=1.4, decay=5), 0.6),
                  t0 + st / 16 * ctx["bar_sec"], 0.16)

    layers = [
        _layer_pad(lambda c: c, gain=0.12),
        _layer_bass(levels=(1, 3)),
        _layer_guitar_arp(arp),
        _layer_melody(mel, "flute", gain=0.48, pan_p=-0.2),
        chimes,
        _layer_perc("shaker", (4, 12), 0.07),
    ]
    return dict(bpm=bpm, bars=bars, layers=layers, name="bgm_floor2", desc="二层·翠枝回廊")


def _bgm_market():
    """交易所·尼达维勒商会 v2：E 小调波尔卡。根-五交替低音 + 手风琴半音装饰旋律，
    和声走向 Em-G-Am-B7 / C-Am-B7 更有推进感。112bpm · 16 小节 · ~34s。"""
    bpm = 112
    q = 60.0 / bpm
    Em, Am, B7, C, G = [52, 55, 59], [57, 60, 64], [47, 51, 57], [48, 52, 55], [55, 59, 62]
    bars = [Em, G, Am, B7, Em, C, B7, Em, Em, G, Am, B7, C, Am, B7, Em]

    def arp(chord, bar_idx, r):
        out = []
        for i in range(8):
            if i % 2 == 1 and r.random() < 0.3:
                continue
            m = chord[i % len(chord)] + 12 * (1 if i % 3 == 2 else 0)
            out.append((i * 2, m, 0.35))
        return out

    def sec(events):
        return [(st, m, b * q) for st, m, b in events]

    # 手风琴旋律：半音下邻音装饰（侏儒式的市侩俏皮），A 段 + 变奏段
    mel = [[] for _ in range(16)]
    mel[0] = sec([(0, 76, 0.35), (1, 75, 0.15), (2, 76, 0.35), (4, 79, 0.9), (8, 76, 0.35), (10, 74, 0.35), (12, 76, 1.0)])
    mel[1] = sec([(0, 79, 0.7), (4, 83, 0.7), (8, 79, 1.2), (12, 74, 0.9)])
    mel[2] = sec([(0, 81, 0.35), (2, 79, 0.35), (4, 76, 0.9), (8, 72, 0.35), (10, 74, 0.35), (12, 76, 1.0)])
    mel[3] = sec([(0, 75, 0.35), (1, 74, 0.15), (2, 75, 0.35), (4, 78, 0.9), (8, 75, 0.35), (10, 74, 0.35), (12, 71, 1.0)])
    mel[4] = sec([(0, 76, 0.35), (1, 75, 0.15), (2, 76, 0.35), (4, 79, 0.9), (8, 83, 0.7), (12, 79, 1.2)])
    mel[5] = sec([(0, 79, 0.35), (2, 78, 0.35), (4, 79, 0.9), (8, 74, 0.7), (12, 79, 1.2)])
    mel[6] = sec([(0, 78, 0.35), (1, 77, 0.15), (2, 78, 0.35), (4, 74, 0.9), (8, 71, 0.7), (12, 74, 1.2)])
    mel[7] = sec([(0, 67, 1.5), (8, 71, 2.2)])
    mel[8] = mel[0]
    mel[9] = sec([(0, 79, 0.7), (4, 83, 0.7), (8, 86, 1.2), (12, 83, 0.9)])
    mel[10] = sec([(0, 81, 0.35), (2, 79, 0.35), (4, 76, 0.9), (8, 81, 0.35), (10, 79, 0.35), (12, 76, 1.0)])
    mel[11] = sec([(0, 75, 0.35), (1, 74, 0.15), (2, 75, 0.35), (4, 78, 0.9), (8, 83, 0.35), (10, 78, 0.35), (12, 75, 1.0)])
    mel[12] = sec([(0, 84, 0.7), (4, 79, 0.7), (8, 76, 1.2), (12, 72, 0.9)])
    mel[13] = sec([(0, 81, 0.35), (2, 79, 0.35), (4, 76, 0.9), (8, 74, 0.35), (10, 76, 0.35), (12, 79, 1.0)])
    mel[14] = sec([(0, 78, 0.35), (1, 77, 0.15), (2, 78, 0.35), (4, 74, 0.9), (8, 71, 0.35), (10, 74, 0.35), (12, 78, 1.0)])
    mel[15] = sec([(0, 76, 1.0), (4, 74, 0.5), (6, 76, 0.5), (8, 79, 0.5), (10, 78, 0.5), (12, 76, 1.6)])

    def coins(bar_idx, chord, t0, buf, ctx):
        if bar_idx % 8 == 7:
            for i, f in enumerate((2600, 3100)):
                place(buf, pan(coin_hit(f, 0.12, 0.5), 0.5), t0 + (12 + i * 2) / 16 * ctx["bar_sec"], 0.28)

    layers = [
        _layer_oompah(gain=0.5),
        _layer_guitar_arp(arp),
        _layer_melody(mel, "accord", gain=0.45, pan_p=-0.15),
        _layer_perc("tamb", (4, 12), 0.15),
        _layer_kick((0, 8), 0.3),
        coins,
    ]
    return dict(bpm=bpm, bars=bars, layers=layers, name="bgm_market", desc="交易所·尼达维勒商会")


BGM_TARGET_RMS = 0.125  # 三首 BGM 响度基准（纯技术项）：切层/切场景音量不跳变


def _bgm_floor3():
    """三层·苍干栈道 v1（工程会话需求单#1，2026-10-11）：D 混合利底亚，100bpm，比二层轻快。
    长风灌袖的木质栈道：十六分木拨弦当"栈道板"节奏 + 长笛八分跑句 + 周期风声灌袖 + 风铃 + 弱拍木点。"""
    bpm = 100
    q = 60.0 / bpm
    D, C, G, A = [50, 54, 57], [48, 52, 55], [55, 59, 62], [57, 61, 64]
    bars = [D, C, G, D, D, C, G, D, D, C, G, D, D, C, G, A]

    def arp(chord, bar_idx, r):
        order = (0, 2, 1, 3, 2, 3, 1, 2, 0, 2, 1, 3, 2, 4, 3, 2)
        out = []
        for i in range(16):
            d = order[i]
            m = chord[d % len(chord)] + 12 * (1 if d >= len(chord) else 0) + 12
            out.append((i, m, 0.26))
        return out

    def sec(events):
        return [(st, m, b * q) for st, m, b in events]

    mel = [[] for _ in range(16)]
    mel[0] = sec([(0, 78, 0.5), (2, 81, 0.5), (4, 83, 0.5), (6, 81, 0.5), (8, 78, 0.75), (12, 74, 1.0)])
    mel[1] = sec([(0, 76, 0.5), (2, 74, 0.5), (4, 72, 1.0), (8, 74, 2.0)])
    mel[2] = sec([(0, 79, 0.5), (2, 81, 0.5), (4, 83, 1.0), (8, 79, 0.75), (12, 74, 1.0)])
    mel[3] = sec([(0, 78, 1.0), (4, 74, 1.0), (8, 78, 2.0)])
    mel[4] = mel[0]
    mel[5] = sec([(0, 76, 0.5), (2, 74, 0.5), (4, 72, 0.75), (8, 76, 0.75), (12, 79, 1.0)])
    mel[6] = sec([(0, 83, 0.5), (2, 81, 0.5), (4, 79, 1.0), (8, 74, 0.75), (12, 71, 1.0)])
    mel[7] = sec([(0, 74, 3.5)])
    mel[8] = sec([(0, 78, 0.5), (2, 81, 0.5), (4, 83, 0.5), (6, 85, 0.5), (8, 83, 0.75), (12, 78, 1.0)])
    mel[9] = sec([(0, 84, 0.5), (2, 83, 0.5), (4, 79, 1.0), (8, 76, 0.75), (12, 74, 1.0)])
    mel[10] = sec([(0, 79, 0.5), (2, 83, 0.5), (4, 86, 1.0), (8, 83, 0.75), (12, 79, 1.0)])
    mel[11] = sec([(0, 78, 0.75), (4, 81, 0.75), (8, 83, 2.0)])
    mel[12] = mel[8]
    mel[13] = sec([(0, 84, 0.5), (2, 81, 0.5), (4, 79, 0.75), (8, 76, 0.75), (12, 72, 1.0)])
    mel[14] = sec([(0, 74, 0.5), (2, 76, 0.5), (4, 78, 0.5), (6, 79, 0.5), (8, 81, 0.75), (12, 83, 1.0)])
    mel[15] = sec([(0, 85, 1.0), (4, 81, 0.75), (8, 78, 2.5)])

    # 低八度铃音对答（栈道下的回声）
    ans = [[] for _ in range(16)]
    ans[1] = sec([(8, 62, 1.8)])
    ans[3] = sec([(8, 59, 1.8)])
    ans[9] = sec([(8, 62, 1.8)])
    ans[11] = sec([(8, 64, 1.8)])
    ans[13] = sec([(8, 60, 1.8)])
    ans[15] = sec([(8, 57, 1.8)])

    def wind(bar_idx, chord, t0, buf, ctx):
        # 长风灌袖：每 4 小节一次低音量风声灌入（混在乐里，不抢旋律）
        if bar_idx % 4 == 3:
            place(buf, pan(whoosh(1.6, 300, 1600, up=True, level=0.5), -0.4),
                  t0 + ctx["bar_sec"] * 0.5, 0.10)

    def chimes(bar_idx, chord, t0, buf, ctx):
        r = ctx["rng"]
        if r.random() < 0.35:
            st = int(r.integers(0, 16))
            m = 86 + int(r.integers(0, 5))
            place(buf, pan(bell(n2f(m), 0.5, bright=1.3, decay=5), 0.55),
                  t0 + st / 16 * ctx["bar_sec"], 0.14)

    def woodblock(bar_idx, chord, t0, buf, ctx):
        # 木质栈道板：弱拍短促木点（風系藤蔓生态的轻打击）
        for st in (4, 12):
            y = bp(noise(0.05), 800, 2400) * np.exp(-60 * t_axis(0.05))
            place(buf, pan(y, 0.25), t0 + st / 16 * ctx["bar_sec"], 0.14)

    layers = [
        _layer_pad(lambda c: c, gain=0.12),
        _layer_bass(levels=(1, 3)),
        _layer_guitar_arp(arp),
        _layer_melody(mel, "flute", gain=0.46, pan_p=-0.2),
        _layer_melody(ans, "bell", gain=0.22, pan_p=0.35),
        wind,
        chimes,
        woodblock,
        _layer_perc("shaker", (0, 4, 8, 12), 0.06),
        _layer_kick((0, 8), 0.2),
    ]
    return dict(bpm=bpm, bars=bars, layers=layers, name="bgm_floor3", desc="三层·苍干栈道")


def _bgm_floor4():
    """四层·落英花冠 预备样张（圣经第九轮拍板立项，内容未实装）：B 小调柔色，78bpm，16 小节 48s。
    花瓣雨生态：竖琴十六分如落英铺地 + 钟琴长句摇曳 + 高音区"花瓣反光"随机微光 + 暖垫，夜祭前的安眠曲气质。"""
    bpm = 78
    q = 60.0 / bpm
    Bm, G, D, A = [47, 50, 54], [55, 59, 62], [50, 54, 57], [57, 61, 64]
    bars = [Bm, G, D, A] * 4

    def arp(chord, bar_idx, r):
        order = (0, 1, 2, 3, 2, 3, 1, 2, 0, 2, 1, 3, 2, 3, 2, 1)
        out = []
        for i in range(16):
            d = order[i]
            m = chord[d % len(chord)] + 12 * (1 if d >= len(chord) else 0)
            out.append((i, m, 0.45))
        return out

    def sec(events):
        return [(st, m, b * q) for st, m, b in events]

    mel = [[] for _ in range(16)]
    mel[0] = sec([(0, 74, 1.0), (6, 71, 0.5), (8, 74, 1.0), (12, 78, 1.6)])
    mel[1] = sec([(0, 79, 1.2), (6, 78, 0.5), (8, 74, 1.0), (12, 71, 1.6)])
    mel[2] = sec([(0, 74, 1.0), (6, 78, 0.5), (8, 81, 1.0), (12, 78, 1.6)])
    mel[3] = sec([(0, 76, 1.2), (8, 73, 1.2), (12, 69, 1.6)])
    mel[4] = sec([(0, 74, 0.75), (4, 71, 0.75), (8, 74, 0.75), (12, 79, 1.6)])
    mel[5] = sec([(0, 78, 1.0), (6, 74, 0.5), (8, 71, 1.0), (12, 67, 1.6)])
    mel[6] = sec([(0, 74, 1.0), (6, 78, 0.5), (8, 81, 0.75), (12, 83, 1.6)])
    mel[7] = sec([(0, 81, 2.5), (8, 73, 1.6)])
    mel[8] = sec([(0, 74, 0.5), (2, 76, 0.5), (4, 78, 0.75), (8, 81, 0.75), (12, 78, 1.5)])
    mel[9] = sec([(0, 79, 0.75), (4, 78, 0.75), (8, 74, 0.75), (12, 71, 1.5)])
    mel[10] = sec([(0, 74, 0.5), (4, 78, 0.5), (8, 81, 0.75), (12, 85, 1.5)])
    mel[11] = sec([(0, 83, 0.75), (4, 81, 0.75), (8, 78, 2.2)])
    mel[12] = sec([(0, 74, 0.5), (2, 71, 0.5), (4, 74, 0.75), (8, 79, 0.75), (12, 78, 1.5)])
    mel[13] = sec([(0, 79, 0.75), (4, 83, 0.75), (8, 79, 0.75), (12, 74, 1.5)])
    mel[14] = sec([(0, 78, 0.75), (4, 81, 0.75), (8, 78, 0.75), (12, 74, 1.5)])
    mel[15] = sec([(0, 73, 1.0), (4, 76, 1.0), (8, 81, 2.2)])

    def twinkle(bar_idx, chord, t0, buf, ctx):
        # 花瓣反光：高音区稀疏微光（比二层风铃更轻更密）
        r = ctx["rng"]
        if r.random() < 0.5:
            st = int(r.integers(0, 16))
            m = 89 + int(r.integers(0, 6))
            place(buf, pan(bell(n2f(m), 0.45, bright=1.2, decay=5.5), 0.5),
                  t0 + st / 16 * ctx["bar_sec"], 0.12)

    layers = [
        _layer_pad(lambda c: c, gain=0.13),
        _layer_bass(levels=(1, 3)),
        _layer_guitar_arp(arp),
        _layer_melody(mel, "bell", gain=0.42, pan_p=0.25),
        twinkle,
        _layer_perc("shaker", (0, 8), 0.05),
        _layer_kick((0, 8), 0.12),
    ]
    return dict(bpm=bpm, bars=bars, layers=layers, name="bgm_floor4", desc="四层·落英花冠（预备）")


def bgm_to_stereo(buf, total, tail):
    left = reverb(buf[:, 0], 0.22)
    right = reverb(buf[:, 1], 0.22, spread=1)
    st = np.stack([loop_fold(left, total, tail), loop_fold(right, total, tail)], axis=1)
    st = normalize(softclip(st), -6)
    # 响度统一：实测三首 RMS 相差最大 ~24%（floor2 明显更响），拉齐到 BGM_TARGET_RMS
    rms = float(np.sqrt(np.mean(st ** 2)))
    if rms > 0:
        st = st * (BGM_TARGET_RMS / rms)
    m = float(np.max(np.abs(st)))
    if m > 0.95:  # 拉响度后防削波
        st = st * (0.95 / m)
    return st


# ---------------------------------------------------------------- 2026-10-11 增补（精英登场 / 变体池 / 待拍板样张 / 环境音）


def s_elite_appear():
    """精英登场：低音暗钟 + 小二度压迫 + 暗色噪声涌起（区别于 floor_unlock 的明亮盖章）。"""
    dur = 1.1
    buf = np.zeros(int(dur * SR))
    place(buf, bell(n2f(38), 1.0, bright=0.55, decay=2.2), 0.0, 0.9)
    place(buf, bell(n2f(63), 0.7, bright=0.7, decay=4), 0.15, 0.5)
    w = bp(noise(dur), 200, 900) * adsr(int(dur * SR), 0.25, 0.2, 0.8, 0.4)
    place(buf, w, 0.0, 0.55)
    place(buf, sweep(70, 40, 0.5, curve=0.6) * np.exp(-6 * t_axis(0.5)), 0.0, 0.8)
    return normalize(softclip(buf), -6)


def s_clear_normal_b():
    """普通消除变体 B：偏高亮一档的暖噗（同族轮播防腻）。"""
    dur = 0.24
    y = sweep(230, 105, dur, curve=0.8) * np.exp(-11 * t_axis(dur))
    n = bp(noise(dur), 700, 3400) * np.exp(-18 * t_axis(dur))
    y[: len(n)] += 0.5 * n
    p = pluck(n2f(69), 0.18, damp=8, bright=0.6)
    y[: len(p)] += 0.45 * p
    return normalize(fade_edges(y, 0.002, 0.02), -6)


def s_clear_normal_c():
    """普通消除变体 C：偏低沉一档（同族轮播防腻）。"""
    dur = 0.28
    y = sweep(150, 72, dur, curve=0.8) * np.exp(-9 * t_axis(dur))
    n = lp(noise(dur), 1600) * np.exp(-13 * t_axis(dur))
    y[: len(n)] += 0.6 * n
    p = pluck(n2f(57), 0.22, damp=7, bright=0.5)
    y[: len(p)] += 0.5 * p
    return normalize(fade_edges(y, 0.002, 0.02), -6)


def s_clear_effective_b():
    """克制命中变体 B：zap 高窗 + B5 亮铃（同族轮播防腻）。"""
    dur = 0.4
    buf = np.zeros(int(dur * SR))
    place(buf, zap(820, 2600, 0.14), 0.0, 0.85)
    place(buf, sweep(180, 76, 0.28, curve=0.6) * np.exp(-9 * t_axis(0.28)), 0.0, 0.75)
    place(buf, bell(n2f(83), 0.32, bright=1.25, decay=5.5), 0.05, 0.75)
    sp = sparkle(dur, base=2217, n=4, level=0.8)
    i = int(0.08 * SR)
    buf[i: i + len(sp)] += sp[: len(buf) - i]
    return normalize(softclip(buf), -5)


def s_swap_ok_b():
    """交换成功变体 B：木拨弦主导（少啾多木，同族轮播防腻）。"""
    y = pluck_ks(880, 0.09, 0.99)
    z = zap(640, 1040, 0.07)
    y[: len(z)] += 0.5 * z
    return normalize(fade_edges(y, 0.002, 0.01), -8)


def s_talent_node():
    """天赋节点点亮（待拍板样张）：暖双拨弦 + 微光，区别于 level_up 琶音。"""
    buf = np.zeros(int(0.5 * SR))
    place(buf, pluck(n2f(69), 0.35, damp=4), 0.0, 0.9)
    place(buf, pluck(n2f(76), 0.4, damp=4), 0.08, 0.7)
    place(buf, sparkle(0.35, base=1568, n=3, level=0.5), 0.12, 0.8)
    return normalize(buf, -6)


def s_paragon_node():
    """巅峰节点点亮（待拍板样张）：深钟 + 金色微光，厚重一档。"""
    buf = np.zeros(int(0.8 * SR))
    place(buf, bell(n2f(50), 0.7, bright=0.8, decay=3.5), 0.0, 0.8)
    place(buf, bell(n2f(74), 0.5, bright=1.1, decay=4), 0.1, 0.5)
    place(buf, sparkle(0.5, base=1976, n=5, level=0.7), 0.15, 0.9)
    return normalize(buf, -5)


def _amb_floor1(dur):
    """一层·树根之街：炉火低鸣 + 稀疏噼啪 + 远街人声嗡嗡（LFO 取整周期保证循环无缝）。"""
    t = t_axis(dur)
    bed = lp(noise(dur), 240) * (1.0 + 0.35 * np.sin(2 * np.pi * 21.0 / dur * t + 1.3))
    crackle = (rng.random(len(t)) > 0.99955) * rng.standard_normal(len(t))
    voices = bp(noise(dur), 250, 520) * (1.0 + 0.5 * np.sin(2 * np.pi * 6.0 / dur * t))
    return bed * 0.9 + lp(crackle, 4000) * 1.1 + voices * 0.16


def _amb_floor2(dur):
    """二层·翠枝回廊：林间软风 + 叶沙 + 稀疏鸟点。"""
    t = t_axis(dur)
    wind = bp(noise(dur), 380, 1100) * (1.0 + 0.45 * np.sin(2 * np.pi * 9.0 / dur * t + 0.7))
    leaves = hp(noise(dur), 5500) * 0.05
    buf = wind * 0.5 + leaves
    for _ in range(max(2, int(dur / 6))):
        f0 = 2600 * 2 ** (rng.integers(0, 7) / 12)
        chirp = sweep(f0, f0 * 1.4, 0.09) * np.exp(-30 * t_axis(0.09))
        i = int(rng.uniform(0.5, dur - 1.0) * SR)
        buf[i: i + len(chirp)] += chirp * 0.16
    return buf


def _amb_floor3(dur):
    """三层·苍干栈道：高空劲风大幅起伏 + 偶发栈道板吱呀。"""
    t = t_axis(dur)
    wind = bp(noise(dur), 260, 1500) * (1.0 + 0.6 * np.sin(2 * np.pi * 7.0 / dur * t + 2.1))
    buf = wind * 0.75
    for _ in range(max(2, int(dur / 8))):
        creak = osc(170, 0.22, "saw", vib_hz=27, vib_amt=60) * np.exp(-14 * t_axis(0.22))
        creak = bp(creak, 120, 900)
        i = int(rng.uniform(0.5, dur - 1.0) * SR)
        buf[i: i + len(creak)] += creak * 0.3
    return buf


AMBIENCE = {"amb_floor1": _amb_floor1, "amb_floor2": _amb_floor2, "amb_floor3": _amb_floor3}
SAMPLE_EXTRA = {"talent_node": s_talent_node, "paragon_node": s_paragon_node}


def gen_ambience(sid, outdir, sub="ambience"):
    """环境音：30s 无缝循环（尾巴折回 + 整周期 LFO），双声道独立实现去相关，
    响度固定很低（RMS≈0.045，垫底用）。demo 输出样张区（sub=ambience）；--all 转正（sub=amb）。"""
    total, tail = int(30 * SR), int(1.5 * SR)

    def render():
        buf = np.zeros(total + tail)
        y = AMBIENCE[sid](30.0 + 1.5)
        buf[: len(y)] += y
        return loop_fold(buf, total, tail)

    st = np.stack([render(), render()], axis=1)
    rms = float(np.sqrt(np.mean(st ** 2)))
    if rms > 0:
        st = st * (0.045 / rms)
    path = os.path.join(outdir, sub, sid + ".ogg")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    _sf_write_chunked(path, st.astype(np.float32), SR, "OGG", "VORBIS")
    return 30.0, float(np.max(np.abs(st)))


# ---------------------------------------------------------------- 资产目录

CATALOG = {
    # id: (函数, 相对 assets/audio 的路径, 优先级, 说明)
    "ui_click":         (s_ui_click,         "sfx/ui_click.wav",         "P0", "通用按钮点击"),
    "ui_open":          (s_ui_open,          "sfx/ui_open.wav",          "P1", "面板/弹窗打开"),
    "ui_close":         (s_ui_close,         "sfx/ui_close.wav",         "P1", "面板/弹窗关闭"),
    "level_up":         (s_level_up,         "sfx/level_up.wav",         "P0", "献金升级成功"),
    "money_not_enough": (s_money_not_enough, "sfx/money_not_enough.wav", "P0", "钱不够（献金/交易通用拒绝音）"),
    "essence_gain":     (s_essence_gain,     "sfx/essence_gain.wav",     "P1", "精华入账"),
    "line_up":          (s_line_up,          "sfx/line_up.wav",          "P1", "训练线升级"),
    "floor_unlock":     (s_floor_unlock,     "sfx/floor_unlock.wav",     "P1", "登层签证解锁（盖章+和弦）"),
    "floor_switch":     (s_floor_switch,     "sfx/floor_switch.wav",     "P1", "层间切换"),
    "rebirth":          (s_rebirth,          "sfx/rebirth.wav",          "P0", "重生演出「世界之冬」（6s）"),
    "swap_ok":          (s_swap_ok,          "sfx/swap_ok.wav",          "P0", "三消交换成功"),
    "swap_fail":        (s_swap_fail,        "sfx/swap_fail.wav",        "P0", "三消交换无效弹回"),
    "clear_normal":     (s_clear_normal,     "sfx/clear_normal.wav",     "P0", "普通消除（六色通用）"),
    "clear_effective":  (s_clear_effective,  "sfx/clear_effective.wav",  "P0", "克制命中消除（更强奖励反馈）"),
    "special_line":     (s_special_line,     "sfx/special_line.wav",     "P0", "特殊棋子·直线引爆"),
    "special_bomb":     (s_special_bomb,     "sfx/special_bomb.wav",     "P0", "特殊棋子·爆炸引爆"),
    "special_bird":     (s_special_bird,     "sfx/special_bird.wav",     "P0", "魔力鸟全消"),
    "skill_cast":       (s_skill_cast,       "sfx/skill_cast.wav",       "P0", "职业技能施法（七职业通用，2026-10-11 补缺口）"),
    "skill_ready":      (s_skill_ready,      "sfx/skill_ready.wav",      "P1", "充能型技能充能完成提示"),
    "combo_chain":      (s_combo_chain,      "sfx/combo_chain.wav",      "P0", "连锁（pitch_scale 升调）"),
    "elite_appear":     (s_elite_appear,     "sfx/elite_appear.wav",     "P1", "精英怪登场（暗钟压迫感，2026-10-11）"),
    "talent_node":      (s_talent_node,      "sfx/talent_node.wav",      "P1", "天赋节点点亮（2026-10-11 转正，替代复用 level_up）"),
    "paragon_node":     (s_paragon_node,     "sfx/paragon_node.wav",     "P1", "巅峰节点点亮（2026-10-11 转正，替代复用 level_up）"),
    "monster_hit":      (s_monster_hit,      "sfx/monster_hit.wav",      "P1", "怪物受击（低频短促）"),
    "monster_die":      (s_monster_die,      "sfx/monster_die.wav",      "P0", "怪物击杀·金色爆碎"),
    "battle_win":       (s_battle_win,       "sfx/battle_win.wav",       "P0", "战斗胜利·赏金结算"),
    "battle_retreat":   (s_battle_retreat,   "sfx/battle_retreat.wav",   "P1", "步数耗尽撤退"),
    "trade_buy":        (s_trade_buy,        "sfx/trade_buy.wav",        "P0", "交易所买入"),
    "trade_sell":       (s_trade_sell,       "sfx/trade_sell.wav",       "P0", "交易所卖出"),
    "save_tick":        (s_save_tick,        "sfx/save_tick.wav",        "P2", "存档提示（建议默认静音）"),
}

# 变体池：同族轮播防腻（sfx.gd 的 play() 对 _b/_c 后缀自动随机轮播，缺失自动回退本体）
VARIANTS = {
    "clear_normal": ("s_clear_normal_b", "s_clear_normal_c"),
    "clear_effective": ("s_clear_effective_b",),
    "swap_ok": ("s_swap_ok_b",),
}

SONG_BUILDERS = {"bgm_floor1": _bgm_floor1, "bgm_floor2": _bgm_floor2, "bgm_market": _bgm_market, "bgm_floor3": _bgm_floor3, "bgm_floor4": _bgm_floor4}
SONG_PRIO = {"bgm_floor1": "P0", "bgm_floor2": "P0", "bgm_market": "P0", "bgm_floor3": "P0", "bgm_floor4": "P2 预备"}

DEMO = [
    "ui_click", "level_up", "money_not_enough", "floor_unlock", "rebirth",
    "swap_ok", "swap_fail", "clear_normal", "clear_effective",
    "special_bomb", "special_bird", "special_line",
    "combo_chain", "monster_die", "battle_win", "trade_buy", "trade_sell",
]


# ---------------------------------------------------------------- 生成入口


def gen_sfx(sid, outdir):
    fn, rel, _, _ = CATALOG[sid]
    y = normalize(softclip(np.asarray(fn(), float)), -3.0 if not sid.startswith(("ui_", "save_")) else -9.0)
    path = os.path.join(outdir, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sf.write(path, y.astype(np.float32), SR, subtype="PCM_16")
    n_var = 0
    for vname in VARIANTS.get(sid, ()):  # 变体池：_b/_c 后缀文件，sfx.gd 端随机轮播
        vy = normalize(softclip(np.asarray(globals()[vname](), float)), -3.0)
        vpath = path.replace(".wav", "_" + vname.rsplit("_", 1)[-1] + ".wav")
        sf.write(vpath, vy.astype(np.float32), SR, subtype="PCM_16")
        n_var += 1
    return len(y) / SR, float(np.max(np.abs(y))), n_var


def _sf_write_chunked(path, data, sr, fmt, subtype):
    """分块写长音频（实测 libsndfile 1.2.2 一次喂 40s+ 立体声给 vorbis/mp3 编码器会栈溢出）。"""
    ch = data.shape[1] if data.ndim > 1 else 1
    with sf.SoundFile(path, "w", samplerate=sr, channels=ch, format=fmt, subtype=subtype) as f:
        step = sr * 5
        for i in range(0, len(data), step):
            f.write(data[i: i + step])


def gen_song(sid, outdir, mp3_copy=False):
    spec = SONG_BUILDERS[sid]()
    buf, total, tail, bar_sec = seq_render(spec)
    st = bgm_to_stereo(buf, total, tail)
    rel = f"bgm/{sid}.ogg"
    path = os.path.join(outdir, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    _sf_write_chunked(path, st.astype(np.float32), SR, "OGG", "VORBIS")
    dur = total / SR
    if mp3_copy:
        mp3 = path.replace(".ogg", ".mp3")
        _sf_write_chunked(mp3, (st * 10 ** (-1.0 / 20)).astype(np.float32), SR, "MP3", "MPEG_LAYER_III")
    return dur, float(np.max(np.abs(st))), n_bars_info(spec, bar_sec)


def n_bars_info(spec, bar_sec):
    return f"{len(spec['bars'])} 小节 @ {spec['bpm']}bpm（{len(spec['bars']) * bar_sec:.1f}s 循环）"


def main():
    ap = argparse.ArgumentParser(description="程序化音频管线（音效+BGM）")
    ap.add_argument("--all", action="store_true", help="全量生成到 assets/audio/")
    ap.add_argument("--demo", action="store_true", help="风格样张到 docs/音频样张/")
    ap.add_argument("--only", type=str, default="", help="逗号分隔的资产 id（与 --outdir 配合）")
    ap.add_argument("--outdir", type=str, default="", help="输出根目录（默认 assets/audio）")
    ap.add_argument("--list", action="store_true", help="列出资产目录")
    args = ap.parse_args()

    proj = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    if args.list:
        print("== SFX ==")
        for k, (_, rel, prio, desc) in CATALOG.items():
            print(f"  {k:18s} {prio}  {desc}")
        print("== BGM ==")
        for k, v in SONG_PRIO.items():
            print(f"  {k:18s} {v}")
        return 0

    jobs = []
    if args.demo:
        outdir = os.path.join(proj, "docs", "音频样张")
        jobs = [("sfx", s) for s in DEMO] + [("bgm", s) for s in ("bgm_floor1", "bgm_floor2", "bgm_floor3", "bgm_floor4")]
    elif args.all:
        outdir = os.path.join(proj, "assets", "audio")
        jobs = [("sfx", s) for s in CATALOG] + [("bgm", s) for s in SONG_BUILDERS]
    elif args.only:
        outdir = args.outdir or os.path.join(proj, "assets", "audio")
        for sid in [s.strip() for s in args.only.split(",") if s.strip()]:
            if sid in CATALOG:
                jobs.append(("sfx", sid))
            elif sid in SONG_BUILDERS:
                jobs.append(("bgm", sid))
            else:
                print(f"!! 未知资产 id：{sid}", file=sys.stderr)
    else:
        ap.print_help()
        return 1

    print(f"输出目录：{outdir}")
    for kind, sid in jobs:
        if kind == "sfx":
            dur, peak, n_var = gen_sfx(sid, outdir)
            print(f"  [sfx] {sid:18s} {dur:5.2f}s  peak {20 * np.log10(max(peak, 1e-9)):6.1f} dB"
                  + (f"（+{n_var} 变体）" if n_var else ""))
        else:
            dur, peak, info = gen_song(sid, outdir, mp3_copy=args.demo)
            print(f"  [bgm] {sid:18s} {info}  peak {20 * np.log10(max(peak, 1e-9)):6.1f} dB"
                  + ("（+mp3 预览副本）" if args.demo else ""))
    if args.demo:
        # 待拍板样张：新系统专属音（拍板后进 CATALOG 接线）
        for sid, fn in SAMPLE_EXTRA.items():
            y = normalize(softclip(np.asarray(fn(), float)), -3.0)
            path = os.path.join(outdir, "待拍板", sid + ".wav")
            os.makedirs(os.path.dirname(path), exist_ok=True)
            sf.write(path, y.astype(np.float32), SR, subtype="PCM_16")
            print(f"  [样张] 待拍板/{sid}.wav")
        for sid in AMBIENCE:  # 环境音样张（拍板后转正接 ambience 通道）
            dur, peak = gen_ambience(sid, outdir)
            print(f"  [样张] ambience/{sid}.ogg  30s 循环  peak {20 * np.log10(max(peak, 1e-9)):6.1f} dB")
    elif args.all:
        for sid in AMBIENCE:  # 环境音转正（2026-10-11 拍板开工）：assets/audio/amb/，Sfx 层随 BGM 切换
            dur, peak = gen_ambience(sid, outdir, sub="amb")
            print(f"  [amb] {sid:18s} 30s 循环  peak {20 * np.log10(max(peak, 1e-9)):6.1f} dB")
    print("完成。提示：进游戏前跑一次 godot --headless --import 注册资产。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
