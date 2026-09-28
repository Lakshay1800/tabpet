#!/usr/bin/env python3
"""Separate a painted ground shadow from the animal by position, not color,
for a shadow that shares its color family with the fur (a color key alone
cannot tell them apart). Runs on the ORIGINAL sheet, in raw RGBA.

Per cell: an anchor is opaque fur (saturated or dark); the paw line is the
lowest row with at least three anchor pixels. A light, non-anchor pixel
reachable from transparency through other light pixels below the paw line
is the shadow. A sealed component of near-white pixels close to the paw
line, with no path to transparency, is a background pocket seen through
the legs.

usage: ground-shadow.py in.rgba out.rgba WIDTH HEIGHT CELL K
"""
import sys
from collections import deque

import numpy as np

FUR_RB = 70
DARK_LUMA = 90
LIGHT_LUMA = 100
POCKET_UP = 60
POCKET_MIN = 4
NEAR_WHITE_MIN = 235
NEAR_WHITE_SPREAD = 20
NEAR_WHITE_SHARE = 0.9

NEIGHBORS = [(dy, dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx]


def flood(seeds, passable, size):
    seen = np.zeros((size, size), dtype=bool)
    queue = deque()
    for y, x in seeds:
        if not seen[y, x]:
            seen[y, x] = True
            queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for dy, dx in NEIGHBORS:
            ny, nx = y + dy, x + dx
            if 0 <= ny < size and 0 <= nx < size and passable[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                queue.append((ny, nx))
    return seen


def components(mask, size):
    left = mask.copy()
    out = []
    for y, x in zip(*np.nonzero(mask)):
        if not left[y, x]:
            continue
        comp = flood([(y, x)], left, size) & left
        left &= ~comp
        out.append(comp)
    return out


def main():
    if len(sys.argv) != 7:
        sys.exit("usage: ground-shadow.py in.rgba out.rgba WIDTH HEIGHT CELL K")
    src, dst = sys.argv[1], sys.argv[2]
    w, h, cell, k = (int(v) for v in sys.argv[3:7])
    px = np.fromfile(src, dtype=np.uint8).reshape(h, w, 4).copy()
    rgb = px[..., :3].astype(int)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    luma = 0.299 * r + 0.587 * g + 0.114 * b
    opaque = px[..., 3] >= 128
    anchor = opaque & (((r - b) >= FUR_RB) | (luma < DARK_LUMA))
    near_white = (rgb.min(axis=2) >= NEAR_WHITE_MIN) & (
        (rgb.max(axis=2) - rgb.min(axis=2)) <= NEAR_WHITE_SPREAD
    )
    total_shadow = total_pocket = 0
    for cy in range(0, h, cell):
        for cx in range(0, w, cell):
            sl = (slice(cy, cy + cell), slice(cx, cx + cell))
            anc = anchor[sl]
            rows = np.nonzero(anc.sum(axis=1) >= 3)[0]
            if rows.size == 0:
                continue
            paw = int(rows.max())
            cand = opaque[sl] & ~anc & (luma[sl] >= LIGHT_LUMA)
            clear = ~opaque[sl]

            band = np.zeros((cell, cell), dtype=bool)
            band[max(0, paw - k):, :] = True
            shadow_cand = cand & band
            seeds = []
            for y, x in zip(*np.nonzero(shadow_cand)):
                y0, y1 = max(0, y - 1), min(cell, y + 2)
                x0, x1 = max(0, x - 1), min(cell, x + 2)
                if y == cell - 1 or x == 0 or x == cell - 1 or clear[y0:y1, x0:x1].any():
                    seeds.append((y, x))
            shadow = flood(seeds, shadow_cand, cell) & shadow_cand

            zone = np.zeros((cell, cell), dtype=bool)
            zone[max(0, paw - POCKET_UP):, :] = True
            rest = cand & zone & ~shadow
            # a pocket has no path to transparency, before or after the shadow goes
            open_now = clear | shadow
            pocket = np.zeros((cell, cell), dtype=bool)
            for comp in components(rest, cell):
                ys, xs = np.nonzero(comp)
                touches = False
                for y, x in zip(ys, xs):
                    y0, y1 = max(0, y - 1), min(cell, y + 2)
                    x0, x1 = max(0, x - 1), min(cell, x + 2)
                    if open_now[y0:y1, x0:x1].any():
                        touches = True
                        break
                if touches:
                    continue
                n = int(comp.sum())
                share = float(near_white[sl][comp].mean())
                if n >= POCKET_MIN and share >= NEAR_WHITE_SHARE:
                    pocket |= comp

            gone = shadow | pocket
            if not gone.any():
                continue
            print(
                f"cell r{cy // cell}c{cx // cell}: paw line {paw}, shadow {int(shadow.sum())}, "
                f"pockets {int(pocket.sum())}"
            )
            total_shadow += int(shadow.sum())
            total_pocket += int(pocket.sum())
            sub = px[sl]
            sub[gone, 3] = 0
    print(f"total: shadow {total_shadow}, pockets {total_pocket}")
    px.tofile(dst)


if __name__ == "__main__":
    main()
