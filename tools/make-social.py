#!/usr/bin/env python3
"""Makes the GitHub social preview (1280x640): app icon, name, tagline and the open notch.
usage: make-social.py [ICON_PNG]   (default: Resources/AppIcon.icns via sips)"""
import os, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFilter, ImageFont

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 1280, 640

def font(size, weight):
    f = ImageFont.truetype("/System/Library/Fonts/SFNSRounded.ttf", size)
    f.set_variation_by_name(weight)
    return f

if len(sys.argv) > 1:
    icon = Image.open(sys.argv[1]).convert("RGBA")
else:
    tmp = os.path.join(tempfile.mkdtemp(), "icon.png")
    subprocess.run(["sips", "-s", "format", "png", "-Z", "512", os.path.join(root, "Resources/AppIcon.icns"), "--out", tmp],
                   check=True, capture_output=True)
    icon = Image.open(tmp).convert("RGBA")

bg = Image.new("RGB", (W, H))
d = ImageDraw.Draw(bg)
top, bottom = (43, 27, 58), (192, 96, 143)
for y in range(H):
    t = y / H
    d.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
bg = bg.convert("RGBA")

# Left: icon, name, tagline.
bg.alpha_composite(icon.resize((176, 176), Image.LANCZOS), (64, 92))
d = ImageDraw.Draw(bg)
d.text((76, 284), "Saku", font=font(104, "Heavy"), fill=(255, 255, 255))
d.text((80, 412), "A free pocket of tools", font=font(36, "Semibold"), fill=(255, 236, 246))
d.text((80, 456), "in your MacBook's notch", font=font(36, "Semibold"), fill=(255, 236, 246))
d.text((80, 534), "Music · Tray · Timers · Calendar · Teleprompter", font=font(22, "Medium"), fill=(255, 214, 233))

# Right: the top of a Mac screen with the notch open, as a rounded card with a soft shadow.
shot = Image.open(os.path.join(root, "previews/open-home-full.png")).convert("RGBA")
shot = shot.crop((80, 0, shot.width - 80, shot.height))   # leave the menu bar words out
pw = 680
shot = shot.resize((pw, int(shot.height * pw / shot.width)), Image.LANCZOS)
mask = Image.new("L", shot.size, 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot.width - 1, shot.height - 1], radius=22, fill=255)
shadow = Image.new("RGBA", (shot.width + 100, shot.height + 100), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([50, 64, shot.width + 50, shot.height + 50], radius=22, fill=(20, 8, 30, 160))
x, y = W - pw - 48, (H - shot.height) // 2 - 10
bg.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(24)), (x - 50, y - 50))
bg.paste(shot, (x, y), mask)
ImageDraw.Draw(bg).rounded_rectangle([x, y, x + shot.width - 1, y + shot.height - 1], radius=22, outline=(255, 255, 255, 60), width=2)

out = os.path.join(root, ".github/social-preview.png")
bg.convert("RGB").save(out, optimize=True)
print(out)
