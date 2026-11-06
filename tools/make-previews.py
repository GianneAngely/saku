#!/usr/bin/env python3
"""Turns `Saku --render DIR` output into the repo's previews (HD crops, a tour GIF) and the README screenshot.
usage: make-previews.py RENDER_DIR"""
import os, sys
from PIL import Image, ImageDraw

src = sys.argv[1]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = os.path.join(root, "previews")
os.makedirs(out, exist_ok=True)
CX = 755.5 * 2          # notch centre in the 2x renders (measured on this Mac)

def crop(name, half_w_pt, h_pt):
    im = Image.open(os.path.join(src, name + ".png")).convert("RGB")
    return im.crop((int(CX - half_w_pt * 2), 0, int(CX + half_w_pt * 2), int(h_pt * 2)))

# 1. One HD picture per state (2x).
open_scenes = [n[:-4] for n in sorted(os.listdir(src)) if n.endswith(".png") and (n.startswith("open-") or n.startswith("prompter-") or n.startswith("alert") or n.startswith("drop"))]
closed_scenes = [n[:-4] for n in sorted(os.listdir(src)) if n.startswith("closed-")]
settings = [n[:-4] for n in sorted(os.listdir(src)) if n.startswith("settings-")]
def height(n):
    return 470 if n == "open-web" else 380 if n.startswith("open-finder") else 290

for n in open_scenes:
    crop(n, 400, height(n)).save(os.path.join(out, n + ".png"))
for n in closed_scenes:
    crop(n, 330, 56).save(os.path.join(out, n + ".png"))
for n in settings:
    Image.open(os.path.join(src, n + ".png")).convert("RGB").save(os.path.join(out, n + ".png"))

# 2. README screenshot: six states on a soft backdrop, 2 columns.
picks = ["open-home-full", "open-timers-pomodoro", "prompter-reading", "open-todo-google", "open-tray", "open-system"]
TW, TH = 1000, 354           # each tile, about 2048 px wide in all
tiles = [crop(n, 370, 262).resize((TW, TH), Image.LANCZOS) for n in picks]
gap, pad = 32, 44
W = pad * 2 + TW * 2 + gap
H = pad * 2 + TH * 3 + gap * 2 + 90
bg = Image.new("RGB", (W, H))
top, bottom = (43, 27, 58), (192, 96, 143)
d = ImageDraw.Draw(bg)
for y in range(H):
    t = y / H
    d.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
strip = crop("closed-music", 300, 40).resize((810, 54), Image.LANCZOS)
bg.paste(strip, ((W - 810) // 2, pad - 16))
for i, t in enumerate(tiles):
    x = pad + (i % 2) * (TW + gap)
    y = pad + 90 + (i // 2) * (TH + gap)
    bg.paste(t, (x, y))
bg.save(os.path.join(root, "screenshot.png"))

# 3. Tour GIF: each state for 1.6 s with a short cross-fade, one shared palette (ffmpeg), 1200 px wide.
import shutil, subprocess, tempfile
# Starts on the open notch, so the first frame (and the README hero) shows Saku at work; the closed notch ends the loop.
order = ["open-home-full", "open-timers-pomodoro", "closed-pomodoro", "prompter-reading",
         "open-calendar-new-event", "closed-meeting", "open-todo", "open-finder", "open-system", "open-trackers", "open-tray", "drop-targets",
         "open-clipboard", "open-ai", "open-tools", "alert-countdown", "closed-plain", "closed-music"]
shots = [crop(n, 400, 290).resize((1200, 435), Image.LANCZOS) for n in order if os.path.exists(os.path.join(src, n + ".png"))]
fps, hold, fade = 10, 16, 3
tmp = tempfile.mkdtemp()
k = 0
for i, a in enumerate(shots):
    b = shots[(i + 1) % len(shots)]
    for _ in range(hold):
        a.save(os.path.join(tmp, "f%04d.png" % k)); k += 1
    for j in range(1, fade + 1):
        Image.blend(a, b, j / (fade + 1)).save(os.path.join(tmp, "f%04d.png" % k)); k += 1
gif = os.path.join(out, "saku-tour.gif")
pal = os.path.join(tmp, "pal.png")
subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(fps), "-i", os.path.join(tmp, "f%04d.png"),
                "-vf", "palettegen=stats_mode=full:max_colors=256", pal], check=True)
subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(fps), "-i", os.path.join(tmp, "f%04d.png"), "-i", pal,
                "-lavfi", "paletteuse=dither=sierra2_4a:diff_mode=rectangle", "-loop", "0", gif], check=True)
shutil.rmtree(tmp)
print("previews:", len(os.listdir(out)), "files; screenshot", bg.size)
