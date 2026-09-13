#!/usr/bin/env bash
# sprite-sheet.sh - slice a pose-loop video into a companion sprite sheet.
#
# Pipeline: video (character loop on a plain background) -> N evenly-spaced
# frames -> center square crop -> corner-floodfill background keying ->
# grid montage with transparent background.
#
# Grid geometry must match the companion registry:
#   idle/sit: --frames 25 --cols 5   (5x5 @ 12 FPS in-app)
#   run:      --frames 12 --cols 4   (4x3; FPS is per-animal in registry)
#
# Usage:
#   sprite-sheet.sh -i otter-idle.mp4 -o otter-idle.png
#   sprite-sheet.sh -i otter-run.mp4 -o otter-run.png --frames 12 --cols 4
#   sprite-sheet.sh -i in.mp4 -o out.png --crop 720:720:280:0 --fuzz 12 --no-key
#   sprite-sheet.sh -i run.mp4 -o run.png --frames 12 --cols 4 --from 18 --to 33
#     (--from/--to: 1-based source frame window to sample evenly; a run loop
#      is one gait period, a sit is stop -> settled, an idle is one closure)
#   sprite-sheet.sh -i idle.mp4 -o idle.png --flip   (mirror, e.g. tail side)
#   sprite-sheet.sh -i sit.mp4 -o sit.png --shift 120:0 --fade-edge 24 --fade-sides left
#     (--shift X:Y: move the drawing X px right / Y px down in source pixels
#      before scaling, white-padded, to center a body or align a baseline;
#      --fade-edge N: where the drawing runs off a source frame edge, ramp its
#      alpha over N cell px so the cut dissolves; --fade-sides limits which
#      edges, default left,right,top; the bottom is never faded)
#   sprite-sheet.sh -i single.mp4 -o run.png --frames 12 --cols 4 --from 8 --to 33 --track
#     (--track: re-center every frame horizontally on the character's body,
#      for a run segment where the character travels across the frame; the
#      square crop keeps its size and vertical position, the x follows a
#      median-smoothed body center, white-padded at the frame edges)
#
# Deps: ffmpeg, ffprobe, ImageMagick 7 (magick).

set -euo pipefail

FRAMES=25
COLS=5
CELL=240
FUZZ=8
CROP=""          # w:h:x:y ffmpeg crop; default = centered square
KEY=1            # 1 = floodfill-key background from corners
FROM=1           # first source frame (1-based) of the sampling window
TO=0             # last source frame of the window; 0 = last frame of the clip
FLIP=0           # 1 = mirror every frame horizontally
SHIFT="0:0"      # X:Y source px; +X moves the drawing right, +Y down (white pad, crop back)
TRACK=0          # 1 = per-frame horizontal re-centering on the body (traveling run)
FADE=0           # cell px alpha ramp on the source edges the drawing runs off
FADE_SIDES="left,right,top"  # which edges --fade-edge may touch; bottom never
INPUT=""
OUTPUT=""

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input)  INPUT="$2"; shift 2 ;;
    -o|--output) OUTPUT="$2"; shift 2 ;;
    --frames)    FRAMES="$2"; shift 2 ;;
    --cols)      COLS="$2"; shift 2 ;;
    --cell)      CELL="$2"; shift 2 ;;
    --fuzz)      FUZZ="$2"; shift 2 ;;
    --crop)      CROP="$2"; shift 2 ;;
    --from)      FROM="$2"; shift 2 ;;
    --to)        TO="$2"; shift 2 ;;
    --flip)      FLIP=1; shift ;;
    --shift)     SHIFT="$2"; shift 2 ;;
    --fade-edge) FADE="$2"; shift 2 ;;
    --fade-sides) FADE_SIDES="$2"; shift 2 ;;
    --track)     TRACK=1; shift ;;
    --no-key)    KEY=0; shift ;;
    -h|--help)   usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$INPUT" && -n "$OUTPUT" ]] || usage
[[ -f "$INPUT" ]] || { echo "input not found: $INPUT" >&2; exit 1; }
for bin in ffmpeg ffprobe magick; do
  command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 1; }
done
(( FRAMES % COLS == 0 )) || { echo "--frames ($FRAMES) must divide evenly by --cols ($COLS)" >&2; exit 1; }
ROWS=$(( FRAMES / COLS ))

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sprite-sheet.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Default crop: centered square on the shorter edge.
if [[ -z "$CROP" ]]; then
  IFS=, read -r W H < <(ffprobe -v error -select_streams v:0 \
    -show_entries stream=width,height -of csv=p=0 "$INPUT")
  if (( W > H )); then CROP="$H:$H:$(( (W - H) / 2 )):0"; else CROP="$W:$W:0:$(( (H - W) / 2 ))"; fi
fi

# Dump every frame cropped+scaled to cell size, then pick evenly spaced ones.
# Dumping all is slower than a select filter but immune to nb_frames metadata lies.
IFS=: read -r CW CH _ _ <<< "$CROP"
IFS=: read -r SX SY <<< "$SHIFT"
PX=$(( SX > 0 ? SX : 0 )); PY=$(( SY > 0 ? SY : 0 ))
NX=$(( SX < 0 ? -SX : 0 )); NY=$(( SY < 0 ? -SY : 0 ))
VF="crop=$CROP"
if (( SX != 0 || SY != 0 )); then
  VF="$VF,pad=$(( CW + PX + NX )):$(( CH + PY + NY )):$PX:$PY:white,crop=$CW:$CH:$NX:$NY"
fi
VF="$VF,scale=$CELL:$CELL:flags=lanczos"
(( FLIP )) && VF="$VF,hflip"
# Where the source frame's edges land in the cell after the shift (the fade
# ramps start there, not at the cell edge).
LX=$(( PX * CELL / CW )); RX=$(( CELL - 1 - NX * CELL / CW )); TY=$(( PY * CELL / CH ))
if (( FLIP )); then t=$LX; LX=$(( CELL - 1 - RX )); RX=$(( CELL - 1 - t )); fi

opaque_px() { magick "$1" -crop "$2" +repage -alpha extract -threshold 50% -format '%[fx:int(mean*w*h)]' info:; }
# Alpha ramp on each source edge the drawing runs off (>= 8 opaque px on that
# edge line). Bottom is never faded: feet on the ground line read as sinking.
fade_edges() {
  local f=$1 n=$FADE mask="$WORK/fade-mask.png" fa="$WORK/fade-a.png" hit=0
  magick -size "${CELL}x${CELL}" xc:white "$mask"
  if [[ ",$FADE_SIDES," == *,left,* ]] && (( $(opaque_px "$f" "1x${CELL}+${LX}+0") >= 8 )); then
    magick "$mask" \( -size "${CELL}x${n}" gradient:black-white -rotate -90 \) -geometry "+${LX}+0" -composite "$mask"; hit=1
  fi
  if [[ ",$FADE_SIDES," == *,right,* ]] && (( $(opaque_px "$f" "1x${CELL}+${RX}+0") >= 8 )); then
    magick "$mask" \( -size "${CELL}x${n}" gradient:white-black -rotate -90 \) -geometry "+$(( RX - n + 1 ))+0" -composite "$mask"; hit=1
  fi
  if [[ ",$FADE_SIDES," == *,top,* ]] && (( $(opaque_px "$f" "${CELL}x1+0+${TY}") >= 8 )); then
    magick "$mask" \( -size "${CELL}x${n}" gradient:black-white \) -geometry "+0+${TY}" -composite "$mask"; hit=1
  fi
  (( hit )) || return 0
  magick "$f" -alpha extract "$fa"
  magick "$fa" "$mask" -compose Multiply -composite "$fa"
  magick "$f" -alpha off "$fa" -compose CopyOpacity -composite "$f"
}
if (( TRACK )); then
  # Dump at source size; each picked frame is cropped around its own body
  # center below, then scaled through the same lanczos as the fixed path.
  ffmpeg -v error -i "$INPUT" -fps_mode passthrough "$WORK/all_%05d.png"
else
  ffmpeg -v error -i "$INPUT" -vf "$VF" -fps_mode passthrough "$WORK/all_%05d.png"
fi

ALL=( "$WORK"/all_*.png )
TOTAL=${#ALL[@]}
(( TO > 0 )) || TO=$TOTAL
(( FROM >= 1 && TO <= TOTAL && FROM <= TO )) \
  || { echo "window $FROM..$TO outside the clip's $TOTAL frames" >&2; exit 1; }
SPAN=$(( TO - FROM + 1 ))
(( SPAN >= FRAMES )) || { echo "window has only $SPAN frames, need $FRAMES" >&2; exit 1; }

# --track: body center per frame of the window. Key a 360px copy, keep the
# lower half of the character's rows (legs and belly; a swinging tail carries
# little mass there), take the horizontal center of mass, median-smooth over 5.
body_center() { # file -> cx in source px
  local m="$WORK/track-mask.png" g top bot h
  magick "$1" -scale 360x360! -alpha set -fuzz "$FUZZ%" -fill none \
    -draw "color 0,0 floodfill" -draw "color 359,0 floodfill" \
    -draw "color 0,359 floodfill" -draw "color 359,359 floodfill" \
    -alpha extract -threshold 50% "$m"
  g=$(magick "$m" -scale 1x360! -threshold 0 -format '%@' info: 2>/dev/null)
  h=${g%%x*}; g=${g#*x}; h=${g%%+*}; top=${g##*+}; (( h > 0 )) || { echo -1; return; }
  bot=$(( top + h ))
  magick "$m" -crop "360x$(( h / 2 ))+0+$(( bot - h / 2 ))" +repage -scale 360x1! -depth 8 txt:- \
    | awk -F'[,: ()]+' 'NR>1 { x=$1; v=$3; s+=v; sx+=v*x } END { if (s>0) printf "%d", sx/s; else print -1 }'
}
if (( TRACK )); then
  IFS=, read -r W H < <(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$INPUT")
  : > "$WORK/centers.txt"
  for (( j = FROM - 1; j < TO; j++ )); do
    c=$(body_center "${ALL[$j]}"); (( c >= 0 )) && c=$(( c * W / 360 ))
    echo "$c" >> "$WORK/centers.txt"
  done
  # median of 5, edges clamped; -1 (no drawing) falls back to the frame center
  awk -v W="$W" '{ a[NR]=$1 } END { for (i=1;i<=NR;i++) { n=0; for (k=i-2;k<=i+2;k++) { kk=k<1?1:(k>NR?NR:k); if (a[kk]>=0) b[++n]=a[kk] } if (n==0) { print int(W/2); continue } for (p=1;p<=n;p++) for (q=p+1;q<=n;q++) if (b[q]<b[p]) { t=b[p]; b[p]=b[q]; b[q]=t } print b[int((n+1)/2)] } }' \
    "$WORK/centers.txt" > "$WORK/centers-smooth.txt"
  CENTERS=(); while IFS= read -r line; do CENTERS+=( "$line" ); done < "$WORK/centers-smooth.txt"  # bash 3.2: no mapfile
  echo "track: body center x $(head -1 "$WORK/centers-smooth.txt") -> $(tail -1 "$WORK/centers-smooth.txt") over the window (source px)"
fi

for (( i = 0; i < FRAMES; i++ )); do
  # loop-style spacing: the sample after the last would land on TO+1, so one
  # gait period loops without a repeated frame (a run sheet: window = 12/11 of the period)
  idx=$(( FROM - 1 + i * SPAN / FRAMES ))
  src="${ALL[$idx]}"
  dst=$(printf '%s/frame_%03d.png' "$WORK" "$i")
  if (( TRACK )); then
    # square crop of the configured size at the configured y, x centered on the
    # body; pad white so the crop can run past the frame edge
    cx=${CENTERS[$(( idx - FROM + 1 ))]}
    IFS=: read -r _ _ _ CY0 <<< "$CROP"
    tsrc="$WORK/track_$i.png"
    magick "$src" -bordercolor white -border "${CW}x0" \
      -crop "${CW}x${CH}+$(( cx + CW - CW / 2 ))+${CY0}" +repage \
      -filter Lanczos -resize "${CELL}x${CELL}!" "$tsrc"
    src="$tsrc"
  fi
  if (( KEY )); then
    # Flood-fill transparency inward from all four corners; fuzz absorbs
    # video-compression noise in the flat background.
    edge=$(( CELL - 1 ))
    magick "$src" -alpha set -fuzz "$FUZZ%" -fill none \
      -draw "color 0,0 floodfill" -draw "color $edge,0 floodfill" \
      -draw "color 0,$edge floodfill" -draw "color $edge,$edge floodfill" \
      "$dst"
  else
    cp "$src" "$dst"
  fi
  (( FADE > 0 )) && fade_edges "$dst"
done

# Row-by-row append instead of montage (montage needs a font config even unlabeled).
for (( r = 0; r < ROWS; r++ )); do
  row_frames=()
  for (( c = 0; c < COLS; c++ )); do
    row_frames+=( "$(printf '%s/frame_%03d.png' "$WORK" $(( r * COLS + c )))" )
  done
  magick "${row_frames[@]}" -background none +append +repage "$(printf '%s/row_%03d.png' "$WORK" "$r")"
done
# +repage strips stale page geometry the appends inherit from the source frames;
# without it, downstream ImageMagick ops (e.g. -flatten) crop the sheet to one cell.
magick "$WORK"/row_*.png -background none -append +repage "$OUTPUT"

read -r OW OH < <(magick identify -format '%w %h\n' "$OUTPUT")
EXPECT_W=$(( COLS * CELL )); EXPECT_H=$(( ROWS * CELL ))
[[ "$OW" == "$EXPECT_W" && "$OH" == "$EXPECT_H" ]] \
  || { echo "sheet is ${OW}x${OH}, expected ${EXPECT_W}x${EXPECT_H}" >&2; exit 1; }

SIZE=$(du -h "$OUTPUT" | cut -f1 | tr -d ' ')
echo "wrote $OUTPUT: ${COLS}x${ROWS} grid, $FRAMES frames @ ${CELL}px cells (${OW}x${OH}, $SIZE), picked from $TOTAL source frames"
