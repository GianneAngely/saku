"""Outlines for Saku's clay icon on a 1024 px canvas (the 824 pt macOS tile sits at 100..924)."""
import math, re

T0, TC = 100.0, 512.0          # tile top edge, tile centre


def notch(w=392.0, h=178.0, r=74.0, top=T0 - 60):
    """The notch pocket hanging from the top of the tile."""
    x0, x1 = TC - w / 2, TC + w / 2
    y1 = T0 + h
    k = 0.5523 * r
    return (f"M{x0:.1f},{top:.1f} L{x1:.1f},{top:.1f} L{x1:.1f},{y1 - r:.1f} "
            f"C{x1:.1f},{y1 - r + k:.1f} {x1 - r + k:.1f},{y1:.1f} {x1 - r:.1f},{y1:.1f} "
            f"L{x0 + r:.1f},{y1:.1f} C{x0 + r - k:.1f},{y1:.1f} {x0:.1f},{y1 - r + k:.1f} {x0:.1f},{y1 - r:.1f} Z")


def _rot(x, y, cx, cy, deg):
    a = math.radians(deg)
    return cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a)


def petal(cx, cy, deg, w=206.0, t=262.0, b=16.0, cut=0.08):
    """One sakura petal pointing away from (cx, cy), with the little V cut at its tip."""
    P = lambda x, y: "%.1f,%.1f" % _rot(x, y, cx, cy, deg)
    return (f"M{P(0, -b)} "
            f"C{P(-w * .20, -b - t * .06)} {P(-w / 2, -t * .38)} {P(-w / 2, -t * .62)} "
            f"C{P(-w / 2, -t * .88)} {P(-w * .30, -t)} {P(-w * .12, -t)} "
            f"L{P(0, -t * (1 - cut))} L{P(w * .12, -t)} "
            f"C{P(w * .30, -t)} {P(w / 2, -t * .88)} {P(w / 2, -t * .62)} "
            f"C{P(w / 2, -t * .38)} {P(w * .20, -b - t * .06)} {P(0, -b)} Z")


def flatten(d, steps=10):
    """Absolute M/L/C/Z path into polygons."""
    toks = re.findall(r"[MLCZ]|-?\d+\.?\d*", d)
    polys, cur, i, pt = [], [], 0, None
    while i < len(toks):
        t = toks[i]
        if t == "M":
            if cur:
                polys.append(cur)
            pt = (float(toks[i + 1]), float(toks[i + 2])); cur = [pt]; i += 3
        elif t == "L":
            pt = (float(toks[i + 1]), float(toks[i + 2])); cur.append(pt); i += 3
        elif t == "C":
            p1 = (float(toks[i + 1]), float(toks[i + 2])); p2 = (float(toks[i + 3]), float(toks[i + 4])); p3 = (float(toks[i + 5]), float(toks[i + 6]))
            p0 = pt
            for k in range(1, steps + 1):
                u = k / steps
                cur.append(((1 - u) ** 3 * p0[0] + 3 * (1 - u) ** 2 * u * p1[0] + 3 * (1 - u) * u * u * p2[0] + u ** 3 * p3[0],
                            (1 - u) ** 3 * p0[1] + 3 * (1 - u) ** 2 * u * p1[1] + 3 * (1 - u) * u * u * p2[1] + u ** 3 * p3[1]))
            pt = p3; i += 7
        else:
            i += 1
    if cur:
        polys.append(cur)
    return polys
