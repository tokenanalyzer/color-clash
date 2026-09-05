#!/usr/bin/env python3
"""Shared checkerboard-keying pipeline fix (Phase C).

Several of the supplied multi-pose sheets under game/assets/story/ are RGB
(no alpha) with a light-grey CHECKERBOARD baked into the "empty" pixels —
verified pixel colours ~(254,254,254) / ~(238,238,238) / ~(243,243,243)
depending on the sheet — even though some are named "*_transparent". Slicing
them at runtime showed that checker on the physical device.

This keys the checkerboard to real alpha and writes a NEW file next to the
original; the source PNG is never modified and no art is redrawn — only the
baked grey background becomes transparent. Safe because character art in
this pack never uses near-white/near-grey fills at this brightness+
saturation (verified per-sheet before shipping each derived file).

Usage as a library:
    from key_checkerboard import key_image
    key_image("in.png", "out.png")

Usage as a CLI:
    python key_checkerboard.py in.png out.png
"""
import sys
from PIL import Image

# checkerboard = very bright + almost no colour.
BRIGHT_MIN = 232      # min channel value to be "background bright"
SAT_MAX = 10           # max (max-min) channel spread to be "grey"
FEATHER_MIN = 210      # partial transparency band for a soft edge
FEATHER_SAT = 18


def _key_pixel(r, g, b):
    mn, mx = min(r, g, b), max(r, g, b)
    spread = mx - mn
    if mn >= BRIGHT_MIN and spread <= SAT_MAX:
        return 0
    if mn >= FEATHER_MIN and spread <= FEATHER_SAT:
        t = (mn - FEATHER_MIN) / float(BRIGHT_MIN - FEATHER_MIN)
        return int(max(0.0, min(1.0, 1.0 - t)) * 255)
    return 255


def key_image(src_path, dst_path):
    im = Image.open(src_path).convert("RGB")
    W, H = im.size
    px = im.load()
    out = Image.new("RGBA", (W, H))
    op = out.load()
    keyed = 0
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            a = _key_pixel(r, g, b)
            op[x, y] = (r, g, b, a)
            if a == 0:
                keyed += 1
    out.save(dst_path)
    pct = 100.0 * keyed / (W * H)
    print("wrote %s  (%dx%d, %.1f%% keyed transparent)" % (dst_path, W, H, pct))
    return pct


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: key_checkerboard.py <src.png> <dst.png>")
        sys.exit(1)
    key_image(sys.argv[1], sys.argv[2])
