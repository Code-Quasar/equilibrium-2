#!/usr/bin/env python3
"""Synthesises the four ambient soundtrack loops (original, no samples):
calm, strained, polluted, crisis. Pure Python, then ffmpeg → Ogg Vorbis.

    python3 tools/make_music.py assets/music
"""
import math, random, struct, subprocess, sys, wave, os

RATE = 22050
T = 32.0          # loop length in seconds
X = 3.0           # extra tail, crossfaded into the head for a seamless loop
TAU = 2 * math.pi


def hz(n):  # MIDI note → Hz
    return 440.0 * 2 ** ((n - 69) / 12)


def render(fn, seed):
    rnd = random.Random(seed)
    n = int((T + X) * RATE)
    out = [fn(i / RATE, rnd) for i in range(n)]
    loop = int(T * RATE)
    fade = int(X * RATE)
    for i in range(fade):  # tail into head
        k = i / fade
        out[i] = out[i] * k + out[loop + i] * (1 - k)
    out = out[:loop]
    peak = max(abs(s) for s in out) or 1.0
    return [s / peak * 0.7 for s in out]


def pad(t, notes, lfo=16.0, bright=0.25):
    s = 0.0
    for j, f in enumerate(notes):
        a = 0.6 + 0.4 * math.sin(TAU * t / lfo + j * 1.7)
        s += a * (math.sin(TAU * f * t) + bright * math.sin(TAU * 2 * f * t + 0.3) + 0.5 * math.sin(TAU * (f + 0.6) * t))
    return s / len(notes)


def bell(t, step, seq, decay=3.5, vol=0.35):
    i = int(t / step)
    f = seq[i % len(seq)]
    dt = t - i * step
    if f <= 0:
        return 0.0
    e = math.exp(-decay * dt) * min(dt * 80, 1)
    return vol * e * (math.sin(TAU * f * t) + 0.3 * math.sin(TAU * 2.76 * f * t))


class Wind:
    def __init__(self):
        self.y = 0.0
        self.z = 0.0

    def __call__(self, rnd, amt):
        self.y += (rnd.uniform(-1, 1) - self.y) * amt
        self.z += (self.y - self.z) * amt
        return self.z


wind = Wind()


def calm(t, rnd):
    p = pad(t, [hz(48), hz(55), hz(62), hz(64), hz(71)], 16, 0.2)
    seq = [hz(n) for n in [76, 79, 0, 74, 72, 0, 79, 81, 0, 76, 0, 74, 72, 0, 67, 0]]
    return 0.55 * p + bell(t, 1.0, seq, 2.6, 0.32)


def strained(t, rnd):
    p = pad(t, [hz(45), hz(52), hz(55), hz(60)], 8, 0.15)
    seq = [hz(n) for n in [69, 0, 72, 0, 67, 0, 0, 64]]
    pulse = 0.12 * math.sin(TAU * hz(33) * t) * (0.5 + 0.5 * math.sin(TAU * t / 2))
    return 0.55 * p + bell(t, 2.0, seq, 1.8, 0.3) + pulse


def polluted(t, rnd):
    p = pad(t, [hz(38), hz(45), hz(50), hz(53)], 32, 0.05)
    w = wind(rnd, 0.02) * (0.6 + 0.4 * math.sin(TAU * t / 8))
    seq = [hz(n) for n in [62, 0, 0, 0, 61, 0, 0, 0]]
    return 0.5 * p + 1.6 * w + bell(t, 4.0, seq, 0.9, 0.22)


def crisis(t, rnd):
    beat = 0.5  # 120 bpm
    k = t % beat
    kick = math.exp(-14 * k) * math.sin(TAU * (hz(26) + 60 * math.exp(-30 * k)) * t)
    bass_seq = [hz(38), hz(38), hz(44), hz(38)]
    b = bass_seq[int(t / 2) % 4]
    bass = 0.35 * math.sin(TAU * b * t) * math.exp(-4 * (t % 0.25))
    p = pad(t, [hz(50), hz(56), hz(62)], 4, 0.3)
    tick = rnd.uniform(-1, 1) * math.exp(-60 * ((t + 0.25) % 0.5)) * 0.25
    return 0.5 * kick + bass + 0.35 * p + tick


def write(path, samples):
    tmp = path + ".wav"
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32000)) for s in samples))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "3", path], check=True)
    os.remove(tmp)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "assets/music"
    os.makedirs(out, exist_ok=True)
    for i, (name, fn) in enumerate([("calm", calm), ("strained", strained), ("polluted", polluted), ("crisis", crisis)]):
        write(os.path.join(out, name + ".ogg"), render(fn, 2050 + i))
        print("wrote", name)
