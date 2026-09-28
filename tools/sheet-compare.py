#!/usr/bin/env python3
"""Compare a cleaned sheet to its original, cell by cell: pixels removed,
any enclosed hole that is not near-white background, the largest connected
chunk of removed animal (anchor) pixels, light pixels left near the ground
that touch transparency (visible on a dark bar), and whether the paw line
(lowest row over 10% alpha) moved.

Prints one line per cell with something to report, then totals.

usage: sheet-compare.py original.png cleaned.png CELL
"""
import subprocess
import sys
from collections import deque

import numpy as np

NEIGHBORS = [(dy, dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx]


def load(path):
    w, h = (int(v) for v in subprocess.check_output(["magick", "identify", "-format", "%w %h", path]).split())
    raw = subprocess.check_output(["magick", path, "-depth", "8", "rgba:-"])
    return np.frombuffer(raw, dtype=np.uint8).reshape(h, w, 4).astype(int)


def flood(seed_mask, passable, size):
    seen = seed_mask.copy()
    queue = deque(zip(*np.nonzero(seed_mask)))
    while queue:
        y, x = queue.popleft()
        for dy, dx in NEIGHBORS:
            ny, nx = y + dy, x + dx
            if 0 <= ny < size and 0 <= nx < size and passable[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                queue.append((ny, nx))
    return seen


def biggest_component(mask, size):
    left = mask.copy()
    best = 0
    for y, x in zip(*np.nonzero(mask)):
        if not left[y, x]:
            continue
        seed = np.zeros((size, size), dtype=bool)
        seed[y, x] = True
        comp = flood(seed, left, size) & left
        left &= ~comp
        best = max(best, int(comp.sum()))
    return best


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: sheet-compare.py original.png cleaned.png CELL")
    orig, cand, cell = load(sys.argv[1]), load(sys.argv[2]), int(sys.argv[3])
    assert orig.shape == cand.shape, "dimensions differ"
    h, w = orig.shape[:2]
    totals = dict(removed=0, holes_not_white=0, animal_big=0, light_left=0)
    paw_moves = []
    for cy in range(0, h, cell):
        for cx in range(0, w, cell):
            o = orig[cy:cy + cell, cx:cx + cell]
            c = cand[cy:cy + cell, cx:cx + cell]
            if not (o[..., 3] >= 128).any():
                continue
            r, g, b = o[..., 0], o[..., 1], o[..., 2]
            luma = 0.299 * r + 0.587 * g + 0.114 * b
            o_op = o[..., 3] >= 128
            anchor = o_op & (((r - b) >= 70) | (luma < 90))
            removed = o_op & (c[..., 3] == 0)
            # holes: removed pixels with no path to the original background
            c_clear = c[..., 3] == 0
            reach = flood(~o_op, c_clear, cell)
            enclosed = removed & ~reach
            mn, mx = o[..., :3].min(axis=2), o[..., :3].max(axis=2)
            near_white = (mn >= 235) & ((mx - mn) <= 20)
            holes_bad = enclosed & ~near_white
            animal_removed = removed & anchor
            animal_big = biggest_component(animal_removed, cell)
            # light left near the ground, as seen on a dark bar
            rows = np.nonzero(anchor.sum(axis=1) >= 3)[0]
            paw = int(rows.max())
            a = c[..., 3] / 255.0
            dark = np.array([16, 16, 20])
            flat = c[..., :3] * a[..., None] + dark * (1 - a[..., None])
            fl = 0.299 * flat[..., 0] + 0.587 * flat[..., 1] + 0.114 * flat[..., 2]
            band = np.zeros((cell, cell), dtype=bool)
            band[max(0, paw - 16):, :] = True
            c_anchor = (c[..., 3] > 0) & (((c[..., 0] - c[..., 2]) >= 60) | False)
            light_left = band & (c[..., 3] > 0) & (fl > 120) & ~c_anchor
            # only count what sits BELOW or beside the feet, touching transparency
            touching = flood(light_left & False, light_left, cell)
            seeds = np.zeros((cell, cell), dtype=bool)
            for y, x in zip(*np.nonzero(light_left)):
                y0, y1 = max(0, y - 1), min(cell, y + 2)
                x0, x1 = max(0, x - 1), min(cell, x + 2)
                if (c[y0:y1, x0:x1, 3] == 0).any():
                    seeds[y, x] = True
            touching = flood(seeds, light_left, cell) & light_left
            # paw line at the pipeline convention, alpha over 10 percent
            def lowest(img):
                rr = np.nonzero((img[..., 3] > 25).any(axis=1))[0]
                return int(rr.max())
            po, pc = lowest(o), lowest(c)
            paw_moves.append(pc - po)
            n_removed = int(removed.sum())
            n_bad = int(holes_bad.sum())
            n_light = int(touching.sum())
            totals["removed"] += n_removed
            totals["holes_not_white"] += n_bad
            totals["animal_big"] += 1 if animal_big > 3 else 0
            totals["light_left"] += n_light
            if n_bad or animal_big > 3 or n_light > 10 or pc != po:
                print(
                    f"r{cy // cell}c{cx // cell}: removed {n_removed}, enclosed {int(enclosed.sum())} "
                    f"(not near white {n_bad}), biggest animal piece removed {animal_big}, "
                    f"light at the ground touching background {n_light}, lowest row {po} -> {pc}"
                )
    print("TOTALS", totals, "lowest row moves", sorted(set(paw_moves)))


if __name__ == "__main__":
    main()
