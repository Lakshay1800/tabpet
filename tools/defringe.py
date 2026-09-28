#!/usr/bin/env python3
"""Clean a corner-flood-fill key's leftovers on a sprite sheet, for dark
backgrounds: sealed white background pockets between legs or under a tail,
loose specks, and the matte edge left where the drawing was mixed with
white at the key's own edge.

The matte edge is unmixed pixel by pixel: color and coverage are solved
from each ring pixel's clean neighbors so it reproduces the original
composited color over white.

An optional band (BAND_TOP) lets a ground-band pocket that is not pure
white, such as a shadow core sealed by the key, qualify too.

usage: defringe.py in.rgba out.rgba WIDTH HEIGHT CELL [BAND_TOP]
"""
import sys
import numpy as np

WHITE_MIN = 250
NEUTRAL_MIN = 190     # in-band pocket floor: squirrel shadow core, not pure white
NEUTRAL_SPREAD = 30   # in-band pocket channel spread: excludes orange fur, cream belly
NEUTRAL_RB_MAX = 32   # in-band pocket R-B: shadow tail runs to 32, belly is >=35
POCKET_MIN = 6
POCKET_SMALL = 2
POCKET_NEAR = 8
POCKET_ZONE = 3
ZONE_MIN = 240
ZONE_SPREAD = 10
MAX_SPECK = 3
KEEP_AT = 0.97   # coverage at or above this: not a matte pixel
F_MIN_DIST = 8   # F closer to white than this on every channel: skip


def shifts(m):
    """The 8 neighbor views of m, each aligned to m's own grid."""
    h, w = m.shape[:2]
    out = []
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy == 0 and dx == 0:
                continue
            s = np.zeros_like(m)
            ys = slice(max(dy, 0), h + min(dy, 0))
            xs = slice(max(dx, 0), w + min(dx, 0))
            yd = slice(max(-dy, 0), h + min(-dy, 0))
            xd = slice(max(-dx, 0), w + min(-dx, 0))
            s[yd, xd] = m[ys, xs]
            out.append(s)
    return out


def near(m):
    out = np.zeros_like(m)
    for s in shifts(m):
        out |= s
    return out


def components(mask, eight):
    steps = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    if eight:
        steps += [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    h, w = mask.shape
    seen = np.zeros_like(mask)
    out = []
    for y0, x0 in zip(*np.where(mask)):
        if seen[y0, x0]:
            continue
        stack, pts = [(y0, x0)], []
        seen[y0, x0] = True
        while stack:
            y, x = stack.pop()
            pts.append((y, x))
            for dy, dx in steps:
                yy, xx = y + dy, x + dx
                if (0 <= yy < h and 0 <= xx < w and mask[yy, xx]
                        and not seen[yy, xx]):
                    seen[yy, xx] = True
                    stack.append((yy, xx))
        out.append(pts)
    return out


def white_patches(c):
    rgb_min = c[..., :3].min(axis=2)
    return components((c[..., 3] == 255) & (rgb_min >= WHITE_MIN), False)


def neutral_band_mask(c, band_mask):
    """In-band opaque pixels that cannot be this animal's fur/belly/eye:
    sealed shadow remnants, any size. No POCKET_MIN/site gating - the band
    restriction is itself the evidence, not component size."""
    if band_mask is None:
        return np.zeros(c.shape[:2], dtype=bool)
    rgb_min = c[..., :3].min(axis=2)
    rgb_max = c[..., :3].max(axis=2)
    spread = rgb_max.astype(int) - rgb_min.astype(int)
    rb = c[..., 0].astype(int) - c[..., 2].astype(int)
    return ((c[..., 3] == 255) & band_mask
            & (rgb_min >= NEUTRAL_MIN) & (spread <= NEUTRAL_SPREAD)
            & (np.abs(rb) <= NEUTRAL_RB_MAX))


def center(pts):
    return (sum(p[1] for p in pts) / len(pts),
            sum(p[0] for p in pts) / len(pts))


def loose_specks(present, clean):
    reach = clean.copy()
    while True:
        new = near(reach) & present & ~reach
        if not new.any():
            break
        reach |= new
    drop = np.zeros_like(present)
    for pts in components(present & ~reach, True):
        if len(pts) <= MAX_SPECK:
            for y, x in pts:
                drop[y, x] = True
    return drop


def main():
    if len(sys.argv) not in (6, 7):
        sys.exit("usage: defringe.py in.rgba out.rgba WIDTH HEIGHT CELL [BAND_TOP]")
    src, dst = sys.argv[1], sys.argv[2]
    w, h, cell = int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
    band_top = int(sys.argv[6]) if len(sys.argv) > 6 else None
    px = np.fromfile(src, dtype=np.uint8).reshape(h, w, 4).copy()
    cells = [px[r * cell:(r + 1) * cell, q * cell:(q + 1) * cell]
             for r in range(h // cell) for q in range(w // cell)]
    if band_top is not None:
        band_mask = np.zeros((cell, cell), dtype=bool)
        band_mask[band_top:, :] = True
    else:
        band_mask = None

    patches = [white_patches(c) for c in cells]
    sites = [center(p) for ps in patches for p in ps if len(p) >= POCKET_MIN]
    band_neutrals = [neutral_band_mask(c, band_mask) for c in cells]

    n_pocket_px = n_pockets = n_specks = n_ring = n_done = n_cleared = 0
    n_rim = 0
    n_band_neutral = 0
    worst = 0.0
    alpha_sum = 0.0
    for c, ps, bn in zip(cells, patches, band_neutrals):
        if not (c[..., 3] == 255).any():
            continue
        zone = np.zeros(c.shape[:2], dtype=bool)
        if bn.any():
            n_band_neutral += int(bn.sum())
            c[bn] = 0
            zone[bn] = True
        for pts in ps:
            if len(pts) < POCKET_MIN:
                if len(pts) < POCKET_SMALL:
                    continue
                cx, cy = center(pts)
                if not any(abs(cx - sx) <= POCKET_NEAR
                           and abs(cy - sy) <= POCKET_NEAR
                           for sx, sy in sites):
                    continue
            n_pockets += 1
            n_pocket_px += len(pts)
            for y, x in pts:
                c[y, x] = 0
                zone[y, x] = True

        for _ in range(POCKET_ZONE):
            zone |= near(zone)
        alpha = c[..., 3]
        lo = c[..., :3].min(axis=2)
        spread = c[..., :3].max(axis=2).astype(int) - lo
        eatable = (lo >= WHITE_MIN) | (
            zone & (lo >= ZONE_MIN) & (spread <= ZONE_SPREAD))
        while True:
            rim = (alpha == 255) & eatable & near(alpha == 0)
            if not rim.any():
                break
            n_rim += int(rim.sum())
            c[rim] = 0

        present = alpha > 0
        specks = loose_specks(
            present, (alpha == 255) & ~near(alpha == 0))
        c[specks] = 0
        n_specks += int(specks.sum())

        solid = alpha == 255
        ring = solid & near(alpha == 0)
        clean = solid & ~ring
        rgb = c[..., :3].astype(np.float64)
        acc = np.zeros_like(rgb)
        cnt = np.zeros(clean.shape, dtype=np.float64)
        for s_rgb, s_m in zip(shifts(rgb * clean[..., None]), shifts(clean)):
            acc += s_rgb
            cnt += s_m
        has = ring & (cnt > 0)
        f = np.where(cnt[..., None] > 0,
                     acc / np.maximum(cnt, 1)[..., None], 0)
        acc2 = np.zeros_like(rgb)
        cnt2 = np.zeros(clean.shape, dtype=np.float64)
        for s_f, s_m in zip(shifts(f * has[..., None]), shifts(has)):
            acc2 += s_f
            cnt2 += s_m
        borrow = ring & ~has & (cnt2 > 0)
        f = np.where(borrow[..., None],
                     acc2 / np.maximum(cnt2, 1)[..., None], f)
        has |= borrow

        d = 255.0 - f
        e = 255.0 - rgb
        den = (d * d).sum(axis=2)
        a = np.where(den > 0, (e * d).sum(axis=2) / np.maximum(den, 1e-9), 1.0)
        a = np.clip(a, 0.0, 1.0)
        # never below what C needs to stay reachable over white
        a = np.maximum(a, e.max(axis=2) / 255.0)
        todo = has & (d.max(axis=2) >= F_MIN_DIST) & (a < KEEP_AT)
        aq = np.round(a * 255.0)
        gone = todo & (aq == 0)
        todo &= aq > 0
        aq_f = np.maximum(aq, 1) / 255.0
        color = np.clip(np.round(255.0 - e / aq_f[..., None]), 0, 255)
        back = aq_f[..., None] * color + (1 - aq_f[..., None]) * 255.0
        if todo.any():
            worst = max(worst, float(np.abs(back - rgb)[todo].max()))
            alpha_sum += float(aq[todo].sum())
        c[..., :3][todo] = color[todo].astype(np.uint8)
        c[..., 3][todo] = aq[todo].astype(np.uint8)
        c[gone] = 0
        n_ring += int(ring.sum())
        n_done += int(todo.sum())
        n_cleared += int(gone.sum())

    px.tofile(dst)
    mean_a = alpha_sum / n_done / 255.0 if n_done else 0
    print(f"band-neutral {n_band_neutral} px "
          f"pockets {n_pockets} ({n_pocket_px} px) white rim {n_rim} px "
          f"specks {n_specks} px "
          f"ring {n_ring} rewritten {n_done} "
          f"({100.0 * n_done / max(n_ring, 1):.0f}%) cleared {n_cleared} "
          f"mean coverage {mean_a:.2f} worst error over white {worst:.2f}")


if __name__ == "__main__":
    main()
