#!/usr/bin/env python3
"""Crop render strips around the notch and stack them into one review sheet.
usage: crop.py OUT.png WIDTH_PT IN1.png [IN2.png ...]   (renders are 2x; notch centre x = 755.5 pt)"""
import sys
from PIL import Image, ImageDraw
out, width = sys.argv[1], float(sys.argv[2])
ims = []
for p in sys.argv[3:]:
    im = Image.open(p)
    cx = 755.5 * 2
    w = int(width * 2)
    box = (int(cx - w / 2), 0, int(cx + w / 2), im.height)
    c = im.crop(box)
    d = ImageDraw.Draw(c)
    d.text((10, c.height - 22), p.split('/')[-1], fill=(255, 255, 255))
    ims.append(c)
H = sum(i.height for i in ims) + 6 * (len(ims) - 1)
sheet = Image.new("RGB", (ims[0].width, H), (20, 20, 20))
y = 0
for i in ims:
    sheet.paste(i, (0, y)); y += i.height + 6
sheet.save(out)
print(out, sheet.size)
