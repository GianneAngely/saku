#!/usr/bin/env python3
"""Writes Saku's original sounds (pure Python, no samples): a soft three-note bell for timers.
usage: make-sounds.py OUTDIR"""
import math, struct, sys, wave, os

RATE = 44100

def bell(freq, start, dur, amp, out):
    for i in range(int(dur * RATE)):
        t = i / RATE
        env = (1 - math.exp(-t * 90)) * math.exp(-t * 4.2)
        # bell-ish partials
        v = (math.sin(2 * math.pi * freq * t)
             + 0.42 * math.sin(2 * math.pi * freq * 2.01 * t) * math.exp(-t * 3)
             + 0.18 * math.sin(2 * math.pi * freq * 3.02 * t) * math.exp(-t * 6))
        j = int(start * RATE) + i
        if j < len(out):
            out[j] += amp * env * v

def write(path, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(32767 * 0.7 * s / peak)) for s in samples))

out_dir = sys.argv[1]
os.makedirs(out_dir, exist_ok=True)
# Timer done: G5, C6, E6 rising, last note rings longer.
s = [0.0] * int(2.2 * RATE)
bell(783.99, 0.00, 1.2, 0.55, s)
bell(1046.50, 0.16, 1.4, 0.50, s)
bell(1318.51, 0.32, 1.8, 0.45, s)
write(os.path.join(out_dir, "timer-done.wav"), s)
# Gentle nudge for reminders: a single soft C6 with a quieter octave.
s = [0.0] * int(1.4 * RATE)
bell(1046.50, 0.0, 1.3, 0.5, s)
bell(523.25, 0.0, 1.3, 0.25, s)
write(os.path.join(out_dir, "nudge.wav"), s)
print("wrote", out_dir)
