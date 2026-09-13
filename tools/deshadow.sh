#!/usr/bin/env bash
# deshadow.sh <in.png> <out.png> [cell=240] [band=180] [disk=11]
# Removes a keyed-but-opaque painted ground shadow from a sprite sheet. A pixel
# is shadow when it is opaque, light and unsaturated, in the bottom rows of its
# cell, thinner than the opening disk (the body survives the opening, a sliver
# does not), and not within 2px of dark drawing (paw outlines keep their edge).
set -euo pipefail
IN=$1; OUT=$2; CELL=${3:-240}; BAND=${4:-180}; DISK=${5:-11}
T=$(mktemp -d)
magick "$IN" -channel A -separate +channel "$T/alpha.png"
magick "$IN" -alpha off -colorspace HSL -channel B -separate +channel "$T/light.png"
magick "$IN" -alpha off -colorspace HSL -channel G -separate +channel "$T/sat.png"
magick "$T/alpha.png" -threshold 50% -morphology Open "Disk:$DISK" "$T/body.png"
magick "$T/light.png" "$T/alpha.png" -fx "(u<0.40 && v>0.5) ? 1 : 0" -delete 1--1 -morphology Dilate Disk:1.5 "$T/darkguard.png"
magick "$T/alpha.png" "$T/light.png" "$T/sat.png" "$T/body.png" "$T/darkguard.png" \
  -fx "(u>0 && v>=0.25 && v<=1.0 && (j%$CELL)>=$BAND && u[3]<0.5 && u[4]<0.5) ? 1 : 0" -delete 1--1 "$T/puddle.png"
magick "$T/puddle.png" -morphology Dilate Disk:2 -blur 0x0.7 "$T/puddle-soft.png"
magick "$T/alpha.png" "$T/puddle-soft.png" -fx "u*(1-v)" -delete 1--1 "$T/alpha-new.png"
# drop alpha islands under 30px (specks the cut leaves behind)
magick "$T/alpha-new.png" -threshold 20% -define connected-components:area-threshold=30 -define connected-components:mean-color=true -connected-components 8 -threshold 50% "$T/keep.png"
magick "$T/alpha-new.png" "$T/keep.png" -fx "u*v" -delete 1--1 "$T/alpha-final.png"
magick "$IN" "$T/alpha-final.png" -alpha off -compose CopyOpacity -composite "$OUT"
[ -n "${KEEP:-}" ] && cp "$T/puddle.png" "${OUT%.png}-mask.png" && cp "$T/body.png" "${OUT%.png}-body.png"
rm -rf "$T"
