"""Cuts the presentation GIFs from footage recorded by tools/record_showcase.gd.

    python make_gifs.py SOLO_RECORDING SIDE_BY_SIDE_RECORDING OUTPUT_DIR

Each recording holds A/ and B/, one folder per segment, frames named
<wall clock ms>_<tick>.jpg. Every frame comes from the running game; clips are
only cut, cropped, sped up (time-lapses say so in their name) or laid side by side.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

SOLO, PAIR, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
REC = SOLO
os.makedirs(OUT, exist_ok=True)


def frames(player, segment, rec=None):
    folder = os.path.join(rec or REC, player, segment)
    out = []
    for name in sorted(os.listdir(folder)):
        ms, tick = name[:-4].split("_")
        out.append((int(ms), int(tick), os.path.join(folder, name)))
    return out


def at_tick(seq, tick):
    """Wall clock of the first frame at or after a game tick."""
    for ms, t, _ in seq:
        if t >= tick:
            return ms
    return seq[-1][0]


def pick(seq, ms):
    """The frame nearest a wall-clock time."""
    return min(seq, key=lambda f: abs(f[0] - ms))[2]


def timeline(seq, start_tick, end_tick, fps, speed=1.0):
    """Wall-clock sample times from start_tick to end_tick, fps out, sped up by speed."""
    a, z = at_tick(seq, start_tick), at_tick(seq, end_tick)
    step = 1000.0 / fps * speed
    t, out = a, []
    while t <= z:
        out.append(t)
        t += step
    return out


def load(path, box=None, size=None):
    im = Image.open(path).convert("RGB")
    if box:
        w, h = im.size
        im = im.crop((int(box[0] * w), int(box[1] * h), int(box[2] * w), int(box[3] * h)))
    if size:
        im = im.resize(size, Image.LANCZOS)
    return im


def label(im, text):
    d = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype("arialbd.ttf", 18)
    except OSError:
        font = ImageFont.load_default()
    w = d.textlength(text, font=font)
    d.rounded_rectangle((10, 10, 26 + w, 40), 8, fill=(10, 16, 22))
    d.text((18, 14), text, font=font, fill=(255, 255, 255))
    return im


ONLY = sys.argv[4] if len(sys.argv) > 4 else ""     # rebuild just this clip


def save(name, images, fps):
    """One palette for the whole clip and no dithering: steady colours, small files."""
    path = os.path.join(OUT, name + ".gif")
    sample = Image.new("RGB", (images[0].width, images[0].height * 3))
    for k, i in enumerate([0, len(images) // 2, len(images) - 1]):
        sample.paste(images[i], (0, images[0].height * k))
    ref = sample.quantize(colors=160, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = [im.quantize(palette=ref, dither=Image.Dither.NONE) for im in images]
    pal[0].save(path, save_all=True, append_images=pal[1:], duration=int(1000 / fps), loop=0, optimize=True, disposal=1)
    print(f"{name}.gif  {len(images)} frames  {len(images) / fps:.1f} s  {os.path.getsize(path) / 1e6:.1f} MB")


FULL = (800, 450)
HALF = (600, 338)
GAME = (0.0, 0.0, 0.79, 1.0)   # the minigame and its header, without the side scores


def single(name, player, segment, start, end, fps, speed=1.0, box=None, size=FULL):
    seq = frames(player, segment)
    save(name, [load(pick(seq, ms), box, size) for ms in timeline(seq, start, end, fps, speed)], fps)


def lapse(name, player, start, end, fps, size=FULL):
    if ONLY and ONLY != name:
        return
    seq = [f for f in frames(player, "lapse") if start <= f[1] <= end]
    save(name, [load(p, None, size) for _, _, p in seq], fps)


def side_by_side(name, segment, cuts, fps, labels=None):
    """Player A on the left, B on the right, the same moment of the match."""
    a, b = frames("A", segment, PAIR), frames("B", segment, PAIR)
    out = []
    for start, end, speed in cuts:
        for ms in timeline(a, start, end, fps, speed):
            left, right = load(pick(a, ms), None, HALF), load(pick(b, ms), None, HALF)
            if labels:
                left, right = label(left, labels[0]), label(right, labels[1])
            canvas = Image.new("RGB", (HALF[0] * 2 + 8, HALF[1]), (8, 12, 16))
            canvas.paste(left, (0, 0))
            canvas.paste(right, (HALF[0] + 8, 0))
            out.append(canvas)
    save(name, out, fps)


def lapse_pair(name, start, end, fps, labels):
    a = {t: p for _, t, p in frames("A", "lapse", PAIR)}
    b = {t: p for _, t, p in frames("B", "lapse", PAIR)}
    out = []
    for t in range(start, end + 1):
        if t in a and t in b:
            canvas = Image.new("RGB", (HALF[0] * 2 + 8, HALF[1]), (8, 12, 16))
            canvas.paste(label(load(a[t], None, HALF), labels[0]), (0, 0))
            canvas.paste(label(load(b[t], None, HALF), labels[1]), (HALF[0] + 8, 0))
            out.append(canvas)
    save(name, out, fps)


def triptych(name, cuts, fps):
    """Three minigames, each cropped to its game area, side by side."""
    panels = []
    for segment, start, end in cuts:
        seq = frames("A", segment)
        panels.append([load(pick(seq, ms), GAME, (420, 301)) for ms in timeline(seq, start, end, fps)])
    n = min(len(p) for p in panels)
    out = []
    for i in range(n):
        canvas = Image.new("RGB", (420 * 3 + 16, 301), (8, 12, 16))
        for k, p in enumerate(panels):
            canvas.paste(p[i], (k * 428, 0))
        out.append(canvas)
    save(name, out, fps)


def single_pair(name, player, segment, start, end, fps, speed=1.0):
    seq = frames(player, segment, PAIR)
    save(name, [load(pick(seq, ms)) for ms in timeline(seq, start, end, fps, speed)], fps)


# Visit recording (record_showcase.gd ... visit): B is already visiting A's city
# (Rivals > Visit) when A places a Small Factory; both screens update live.
if ONLY == "08_live_visit":
    side_by_side("08_live_visit", "visit", [(12, 17, 1.0), (17, 42, 4.0), (42, 47, 1.0)], 10,
                 ("Player A builds", "Player B visits A's city"))
    sys.exit()

# Event timeline (developer schedule): collection 270, sorting 330, recycling 390;
# each: announcement +0, countdown +8, play +11 .. +36, results +36 .. +41.
# Solo recording (1280x720): player A.
lapse("01_environmental_crisis_timelapse", "A", 80, 262, 13)
single("04A_industrial_expansion", "A", "build", 3, 46, 10, speed=3.0)
single("05A_collection_crisis", "A", "em1", 288, 298, 10, box=GAME, size=(700, 500))
single("05B_sorting_overload", "A", "em2", 349, 359, 10, box=GAME, size=(700, 500))
single("05C_recycling_breakdown", "A", "em3", 405, 415, 10, box=GAME, size=(700, 500))
triptych("05_eco_emergencies_showcase", [("em1", 288, 298), ("em2", 349, 359), ("em3", 405, 415)], 10)
# Side-by-side recording (two 760x428 windows, the same match): player B and both players.
single_pair("02_city_building", "B", "build", 3, 18, 10)
single_pair("03_recycling_pipeline", "B", "pipeline", 47, 95, 10, speed=3.0)
single_pair("04B_recycling_investment", "B", "build", 3, 46, 10, speed=3.0)
side_by_side("04_industry_vs_recycling", "build", [(3, 46, 3.0)], 10, ("Expand industry", "Invest in recycling"))
side_by_side("06_multiplayer_competition", "em1", [(278, 282, 1.0), (288, 293, 1.0), (307, 311, 1.0), (313, 317, 1.0)], 10, ("Player 1", "Player 2"))
lapse_pair("07_two_futures_timelapse", 100, 262, 12, ("Growth without balance", "Growth with balance"))
