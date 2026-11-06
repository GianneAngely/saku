#!/usr/bin/env python3
"""Makes the README pictures in .github/readme/: the app icon, the Download button and one card per feature
(a close-up of the open notch from previews/ on the Saku gradient).
usage: make-readme-art.py"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = os.path.join(root, ".github", "readme")
os.makedirs(out, exist_ok=True)
TOP, BOTTOM = (43, 27, 58), (192, 96, 143)

def font(size, weight):
    f = ImageFont.truetype("/System/Library/Fonts/SFNSRounded.ttf", size)
    f.set_variation_by_name(weight)
    return f

def gradient(w, h):
    bg = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(bg)
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)], fill=tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)))
    return bg.convert("RGBA")

def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius, fill=255)
    img = img.convert("RGBA")
    img.putalpha(mask)
    return img

# App icon, small enough for the README header.
Image.open(os.path.join(root, "design/icon/AppIcon-1024.png")).convert("RGBA").resize((256, 256), Image.LANCZOS) \
    .save(os.path.join(out, "icon.png"), optimize=True)

# Download button (2x).
W, H = 600, 128
button = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(button)
d.rounded_rectangle((0, 0, W - 1, H - 1), H // 2, fill=(180, 70, 122))
label = "Download for macOS"
f = font(44, "Bold")
box = d.textbbox((0, 0), label, font=f)
d.text(((W - (box[2] - box[0])) / 2 - box[0], (H - (box[3] - box[1])) / 2 - box[1]), label, font=f, fill=(255, 255, 255))
button.save(os.path.join(out, "download.png"), optimize=True)

def panel(img):
    """The open notch panel inside a preview: black, hanging from the top edge."""
    grey = img.convert("L")
    dark = [x for x in range(img.width) if grey.getpixel((x, 250)) < 24]
    left, right = min(dark), max(dark)
    bottom = max(next(y for y in range(img.height - 1, 0, -1) if grey.getpixel((x, y)) < 24) for x in (left + 60, right - 60))
    return left, right, bottom

# Feature cards: the panel below its tab bar (or the part of it named here), on the gradient.
CW, CH, PAD = 1200, 500, 48
cards = {  # name: (preview, share of the panel width, top of the crop)
    "music": ("open-home-music", 0.633, 66),
    "files": ("open-tray", 1, 66),
    "clipboard": ("open-clipboard", 1, 66),
    "timers": ("open-timers-pomodoro", 1, 66),
    "calendar": ("open-calendar", 1, 66),
    "todo": ("open-todo-google", 1, 66),
    "teleprompter": ("prompter-reading", 1, 12),
    "all-features": ("open-finder", 1, 66),
}
for name, (src, share, top) in cards.items():
    img = Image.open(os.path.join(root, "previews", src + ".png")).convert("RGB")
    left, right, bottom = panel(img)
    shot = img.crop((left + 14, top, left + 14 + round((right - left - 28) * share), bottom - 14))
    s = min((CW - 2 * PAD) / shot.width, (CH - 2 * PAD) / shot.height)
    shot = rounded(shot.resize((round(shot.width * s), round(shot.height * s)), Image.LANCZOS), 26)
    card = gradient(CW, CH)
    x, y = (CW - shot.width) // 2, (CH - shot.height) // 2
    shadow = Image.new("RGBA", card.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x, y + 12, x + shot.width, y + shot.height + 12), 26, fill=(20, 8, 30, 110))
    card = Image.alpha_composite(card, shadow.filter(ImageFilter.GaussianBlur(16)))
    card.alpha_composite(shot, (x, y))
    card = rounded(card, 36)
    card.save(os.path.join(out, name + ".png"), optimize=True)
print("made", len(cards), "cards, icon.png and download.png in", out)
