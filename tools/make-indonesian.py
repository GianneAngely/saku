#!/usr/bin/env python3
"""Regenerates Sources/Saku/Core/Indonesian.swift from tools/id_strings.py and lists English strings without a translation."""
import glob, os, re, sys
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
from id_strings import ID
root = os.path.dirname(here)
pat = re.compile(r'tr\(\s*"((?:[^"\\]|\\.)*)"')
used = set()
for f in glob.glob(os.path.join(root, "Sources/Saku/**/*.swift"), recursive=True):
    if f.endswith("Indonesian.swift"): continue
    used.update(m.group(1) for m in pat.finditer(open(f).read()))
missing = sorted(k for k in used if k not in ID and k not in ("", "English", "zz unknown zz"))
lines = ["/// Bahasa Indonesia strings, keyed by the English text. Missing keys fall back to English.",
         "/// Generated from tools/id_strings.py (edit there, then run tools/make-indonesian.py).",
         "enum Indonesian {", "    static let table: [String: String] = ["]
for k in sorted(ID):
    lines.append('        "%s": "%s",' % (k.replace('"', '\\"'), ID[k].replace('"', '\\"')))
lines += ["    ]", "}", ""]
open(os.path.join(root, "Sources/Saku/Core/Indonesian.swift"), "w").write("\n".join(lines))
print(f"{len(ID)} strings written; {len(missing)} without translation")
for m in missing: print("  missing:", m)
