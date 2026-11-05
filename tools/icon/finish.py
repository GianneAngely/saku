#!/usr/bin/env python3
"""Turns the raw Blender renders into the icon master (soft macOS shadow) and the small notch mark.
usage: finish.py ICON_RAW.png MARK_RAW.png"""
import os, sys
from PIL import Image, ImageFilter

root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

icon = Image.open(sys.argv[1]).convert("RGBA").resize((1024, 1024), Image.LANCZOS)
shadow = Image.new("RGBA", icon.size, (24, 10, 36, 0))
shadow.putalpha(icon.split()[3].point(lambda v: int(v * 0.42)))
out = Image.new("RGBA", icon.size, (0, 0, 0, 0))
out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(16)), (0, 12))
out.alpha_composite(icon)
out.save(os.path.join(root, "design/icon/AppIcon-1024.png"))

mark = Image.open(sys.argv[2]).convert("RGBA")
mark = mark.crop(mark.getbbox() or (0, 0, mark.width, mark.height))
side = max(mark.size)
square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
square.alpha_composite(mark, ((side - mark.width) // 2, (side - mark.height) // 2))
square.resize((256, 256), Image.LANCZOS).save(os.path.join(root, "Resources/mark.png"))
print("wrote design/icon/AppIcon-1024.png and Resources/mark.png")
