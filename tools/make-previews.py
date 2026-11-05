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
for n in open_scenes:
    tall = n in ("open-web",)
    crop(n, 400, 470 if tall else 290).save(os.path.join(out, n + ".png"))
for n in closed_scenes:
    crop(n, 330, 56).save(os.path.join(out, n + ".png"))
for n in settings:
    Image.open(os.path.join(src, n + ".png")).convert("RGB").save(os.path.join(out, n + ".png"))

# 2. README screenshot: six states on a soft backdrop, 2 columns.
picks = ["open-home-full", "open-timers-pomodoro", "prompter-reading", "open-tray", "open-clipboard", "open-ai"]
tiles = [crop(n, 370, 262).resize((740, 262)) for n in picks]
gap, pad = 24, 32
W = pad * 2 + 740 * 2 + gap
H = pad * 2 + 262 * 3 + gap * 2 + 70
bg = Image.new("RGB", (W, H))
top, bottom = (43, 27, 58), (192, 96, 143)
d = ImageDraw.Draw(bg)
for y in range(H):
    t = y / H
    d.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
strip = crop("closed-music", 300, 40).resize((600, 40))
bg.paste(strip, ((W - 600) // 2, pad - 12))
for i, t in enumerate(tiles):
    x = pad + (i % 2) * (740 + gap)
    y = pad + 70 + (i // 2) * (262 + gap)
    bg.paste(t, (x, y))
bg.save(os.path.join(root, "screenshot.png"))

# 3. Tour GIF (1.6 s per state, closed and open).
order = ["closed-plain", "closed-music", "open-home-full", "open-timers-pomodoro", "closed-pomodoro", "open-tray", "drop-targets",
         "open-clipboard", "prompter-reading", "open-calendar", "closed-meeting", "open-ai", "open-translate", "open-tools",
         "open-trackers", "open-system", "alert-countdown"]
frames = []
for n in order:
    if not os.path.exists(os.path.join(src, n + ".png")): continue
    f = crop(n, 400, 290).resize((1200, 435), Image.LANCZOS)
    frames.append(f.convert("P", palette=Image.ADAPTIVE, colors=255))
frames[0].save(os.path.join(out, "saku-tour.gif"), save_all=True, append_images=frames[1:], duration=1600, loop=0, optimize=True)
print("previews:", len(os.listdir(out)), "files; screenshot", bg.size)
