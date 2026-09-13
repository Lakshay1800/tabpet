#!/usr/bin/env bash
# pill-geometry.sh - measure the floating pill's rim/edges across a frame stack.
#
# For each frame, prints one CSV line: frame,top,left,right
#   top:   pill's top rim row, found by scanning a single column from the top
#          of the image downward for the first pixel darker than the
#          background threshold (the rim sits on a light background).
#   left/right: pill's side edges, found by scanning the row `top + 12`
#          (inside the pill, below the rim) from each side inward for the
#          first pixel darker than the threshold.
#
# Method: `magick <png> -colorspace gray -depth 8 -crop 1x<h>+<x>+0 +repage
# txt:-` dumps one pixel-value-per-line column strip; the row scan does the
# same with a 1-row-tall crop. Both are parsed with awk. This is 3 magick
# invocations per frame (identify, column dump, row dump) - measured fast
# enough for ~100 frames; per-pixel `-format %[fx:...]` sampling was not
# needed.
#
# Limits:
#   - Light-background frames only; a dark UI element under the sample
#     column (a companion, a dark background image) will fool the rim scan into
#     reporting its own edge instead of the pill's.
#   - Pass --x at a column with only glass/background beneath it, never
#     through the companion or other foreground art.
#   - If a frame has no pixel darker than the threshold anywhere in the
#     scanned column/row, top/left/right print as -1 for that frame and a
#     warning goes to stderr.
#
# Usage:
#   pill-geometry.sh out/around/frames
#   pill-geometry.sh out/around/frames/0001.png
#   pill-geometry.sh out/drag/frames --x 200 --bg-threshold 220
#
# Deps: ImageMagick 7 (magick).

set -euo pipefail

X=""
THRESHOLD=235
TARGET=""

usage() { sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --x)              X="$2"; shift 2 ;;
    --bg-threshold)   THRESHOLD="$2"; shift 2 ;;
    -h|--help)        usage ;;
    -*) echo "unknown arg: $1" >&2; usage ;;
    *)
      [[ -z "$TARGET" ]] || { echo "unexpected extra argument: $1" >&2; usage; }
      TARGET="$1"; shift ;;
  esac
done

[[ -n "$TARGET" ]] || usage
[[ -e "$TARGET" ]] || { echo "error: not found: $TARGET" >&2; exit 1; }
(( THRESHOLD >= 0 && THRESHOLD <= 255 )) || { echo "error: --bg-threshold must be 0-255" >&2; exit 1; }

command -v magick >/dev/null || { echo "missing dependency: magick" >&2; exit 2; }

if [[ -d "$TARGET" ]]; then
  FRAMES=( "$TARGET"/*.png )
else
  FRAMES=( "$TARGET" )
fi
(( ${#FRAMES[@]} > 0 )) && [[ -e "${FRAMES[0]}" ]] || { echo "error: no png frames found in $TARGET" >&2; exit 1; }

# First pixel darker than THRESHOLD in a magick txt: pixel-enumeration dump,
# read from stdin; prints its 0-based position along the scanned axis, or
# empty if none found.
first_dark_row() {
  awk -F'[(),]' -v thr="$THRESHOLD" '
    /^#/ { next }
    { if ($3 + 0 < thr) { print NR - 2; exit } }
  '
}

scan_from_right() {
  awk -F'[(),]' -v thr="$THRESHOLD" '
    /^#/ { next }
    { vals[NR - 2] = $3 + 0; n = NR - 1 }
    END {
      for (i = n - 1; i >= 0; i--) if (vals[i] < thr) { print i; exit }
    }
  '
}

echo "frame,top,left,right"

# space-separated accumulators, not arrays with namerefs: this script targets
# macOS's stock bash 3.2, which has neither `local -n` nor associative arrays.
TOPS=""
LEFTS=""
RIGHTS=""

for f in "${FRAMES[@]}"; do
  name=$(basename "$f" .png)
  read -r W H < <(magick identify -format '%w %h\n' "$f")
  if [[ -n "$X" ]]; then
    x="$X"
  else
    x=$(( W / 2 ))
  fi
  if (( x < 0 || x >= W )); then
    echo "warning: --x $x out of bounds (width $W) for $f" >&2
    echo "$name,-1,-1,-1"
    TOPS="$TOPS -1"; LEFTS="$LEFTS -1"; RIGHTS="$RIGHTS -1"
    continue
  fi

  # `|| true`: awk's early `exit` in first_dark_row/scan_from_right closes its
  # stdin before magick finishes writing the rest of the column/row dump; on
  # a tall full-resolution screenshot (not just a cropped video frame) that
  # remainder is large enough that magick's write blocks and gets SIGPIPE,
  # which `pipefail` + `set -e` then treats as a hard failure even though
  # awk already produced the value we wanted. Discovered running this tool
  # directly on a full-screen `simctl io screenshot` (2622px tall) for the
  # seat-check measurements.
  top=$(magick "$f" -colorspace gray -depth 8 -crop "1x${H}+${x}+0" +repage txt:- | first_dark_row || true)
  if [[ -z "$top" ]]; then
    echo "warning: no rim found at column $x in $f (threshold $THRESHOLD)" >&2
    echo "$name,-1,-1,-1"
    TOPS="$TOPS -1"; LEFTS="$LEFTS -1"; RIGHTS="$RIGHTS -1"
    continue
  fi

  row=$(( top + 12 ))
  if (( row >= H )); then
    echo "warning: top+12 ($row) is outside frame height ($H) for $f" >&2
    echo "$name,$top,-1,-1"
    TOPS="$TOPS $top"; LEFTS="$LEFTS -1"; RIGHTS="$RIGHTS -1"
    continue
  fi

  row_dump=$(magick "$f" -colorspace gray -depth 8 -crop "${W}x1+0+${row}" +repage txt:-)
  left=$(printf '%s\n' "$row_dump" | first_dark_row || true)
  right=$(printf '%s\n' "$row_dump" | scan_from_right || true)
  [[ -n "$left" ]] || { echo "warning: no left edge found at row $row in $f" >&2; left=-1; }
  [[ -n "$right" ]] || { echo "warning: no right edge found at row $row in $f" >&2; right=-1; }

  echo "$name,$top,$left,$right"
  TOPS="$TOPS $top"; LEFTS="$LEFTS $left"; RIGHTS="$RIGHTS $right"
done

# takes a space-separated list of ints (not an array by nameref: macOS's
# stock bash 3.2 has no `local -n`).
summarize() {
  local values="$1" label="$2"
  local min="" max=""
  for v in $values; do
    [[ -n "$min" ]] || min=$v
    [[ -n "$max" ]] || max=$v
    (( v < min )) && min=$v
    (( v > max )) && max=$v
  done
  echo "$label: min=$min max=$max range=$(( max - min ))"
}

summarize "$TOPS" top
summarize "$LEFTS" left
summarize "$RIGHTS" right
