# -*- coding: utf-8 -*-
"""bgm_floor6 程序化合成（M3 全权批次）：星梢星空氛围 BGM（A 小调五声琶音 + 长音垫，60s 无缝循环）。
纯 stdlib 合成 WAV 16bit/44100Hz 单声道；音频线产物到位可覆盖（bgm_floor6.ogg 优先于 .wav）。
用法: python tools/gen_bgm6.py
"""
import math
import os
import struct
import wave

SR = 44100
DUR = 60.0
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "bgm", "bgm_floor6.wav")

# A 小调五声：A3 C4 D4 E4 G4 A4 C5 E5（Hz）
ARP = [220.0, 261.63, 293.66, 329.63, 392.0, 440.0, 523.25, 659.26]
PAD = [110.0, 130.81, 164.81]  # A2 C3 E3 长音垫


def note(freq, t, dur, vol):
    """正弦 + 二次谐波，指数衰减包络。"""
    if t < 0 or t > dur:
        return 0.0
    env = math.exp(-3.0 * t / dur) * min(1.0, t * 40.0)
    return vol * env * (math.sin(2 * math.pi * freq * t) + 0.35 * math.sin(4 * math.pi * freq * t))


def main():
    n = int(SR * DUR)
    buf = [0.0] * n
    # 长音垫：每 8 秒换一个和弦音（A2/C3/E3 轮转），慢正弦
    for i in range(n):
        t = i / SR
        seg = int(t / 8.0) % 3
        f = PAD[seg]
        # 相位连续：段内局部相位
        lt = t - seg * 8.0
        buf[i] += 0.10 * math.sin(2 * math.pi * f * t) * (0.6 + 0.4 * math.sin(2 * math.pi * 0.05 * t))
    # 琶音：每 0.375 秒一音，五声上行下行循环
    step = 0.375
    for k in range(int(DUR / step)):
        f = ARP[k % len(ARP)] if (k // len(ARP)) % 2 == 0 else ARP[len(ARP) - 1 - k % len(ARP)]
        t0 = k * step
        i0 = int(t0 * SR)
        for j in range(int(step * SR)):
            idx = i0 + j
            if idx >= n:
                break
            buf[idx] += note(f, j / SR, step * 1.6, 0.16)
    # 星光闪烁：每 5 秒左右一个高频短音（很轻）
    for k in range(int(DUR / 5.0)):
        i0 = int((k * 5.0 + (k * 2.3) % 3.0) * SR)
        f = 1046.5 * (1.0 + 0.25 * (k % 3))
        for j in range(int(0.12 * SR)):
            idx = i0 + j
            if idx >= n:
                break
            buf[idx] += 0.03 * math.exp(-8.0 * j / SR) * math.sin(2 * math.pi * f * j / SR)
    # 首尾 1.5s 淡入淡出（循环无缝）
    fade = int(1.5 * SR)
    for i in range(fade):
        buf[i] *= i / fade
        buf[n - 1 - i] *= i / fade
    # 写 WAV 16bit
    peak = max(1e-6, max(abs(b) for b in buf))
    gain = 0.72 / peak
    path = os.path.abspath(OUT)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for b in buf:
            v = int(max(-1.0, min(1.0, b * gain)) * 32767)
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))
    print("bgm_floor6.wav 合成完成: %.1f 秒, %d 样本 -> %s" % (DUR, n, path))


if __name__ == "__main__":
    main()
