#!/usr/bin/env bash
# frame-stack.sh - drive a Maestro flow against a booted simulator while
# recording, then cut the recording into frames and a contact sheet.
#
# Why --udid is mandatory: `simctl io booted` picks whichever simulator
# `simctl` considers "the" booted device, which is ambiguous the moment two
# simulators are booted at once. A run where the recorder captured a
# different device than the one Maestro drove looks fine (it produces a
# video) and is silently wrong. Always pass the same UDID to both simctl and
# maestro so the recording matches the driven device.
#
# Lock-file gotcha: `xcrun simctl io <UDID> recordVideo` holds a host-wide
# recording lock for the life of the process. A recorder that never gets a
# clean SIGINT (killed with -9, a crashed shell, an earlier run that was
# ctrl-C'd past this script's trap) leaves the lock held: the next
# recordVideo invocation fails with "Host recording is already in progress",
# and writing to the same output path can fail EBUSY. This script always
# sends SIGINT and waits for the file to stop growing before exiting, and
# traps EXIT/INT/TERM so a leaked recorder process is the exception.
#
# Maestro's synthetic swipe does not drive the UITabBar's built-in drag
# gesture the way a finger does - a frame stack from a Maestro `swipe` proves
# tap/drag behavior the app itself owns, not a real bar-scrub. Proving the
# bar-drag interaction needs a finger, or a device-recorded touch input
# replayed over accessibility, as the driver.
#
# Usage:
#   frame-stack.sh --udid <UDID> --flow apps/example/maestro/around.yaml --out out/around
#   frame-stack.sh --udid <UDID> --flow apps/example/maestro/drag.yaml --out out/drag \
#     --crop-bottom 0.25 --fps 24 --sheet-cols 10 --every 2
#   frame-stack.sh --udid <UDID> --flow apps/example/maestro/around.yaml --out out/around \
#     --force -- --debug-output out/maestro-debug
#
# Find a UDID: xcrun simctl list devices booted
#
# Flags:
#   --udid <UDID>          required, the simulator to record and drive
#   --flow <path>           required, path to a Maestro flow yaml
#   --out <dir>             required, output directory (recording, frames/, sheet.png)
#   --crop-bottom <0-1>     fraction of height kept from the bottom (default 0.22)
#   --fps <n>               frame extraction rate (default 30)
#   --sheet-cols <n>        contact sheet grid columns (default 12)
#   --every <n>             keep only every Nth frame in the sheet (frames/ keeps all)
#   --force                 allow writing into a non-empty --out
#   -- <args>               everything after -- is passed through to `maestro test`
#
# Deps: xcrun, maestro, ffmpeg, ffprobe, ImageMagick 7 (magick).

set -euo pipefail

UDID=""
FLOW=""
OUT=""
CROP="0.22"
FPS="30"
COLS="12"
EVERY="1"
FORCE=0
EXTRA_ARGS=()

usage() { sed -n '2,47p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --udid)        UDID="$2"; shift 2 ;;
    --flow)        FLOW="$2"; shift 2 ;;
    --out)         OUT="$2"; shift 2 ;;
    --crop-bottom) CROP="$2"; shift 2 ;;
    --fps)         FPS="$2"; shift 2 ;;
    --sheet-cols)  COLS="$2"; shift 2 ;;
    --every)       EVERY="$2"; shift 2 ;;
    --force)       FORCE=1; shift ;;
    -h|--help)     usage ;;
    --)            shift; EXTRA_ARGS=("$@"); break ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

if [[ -z "$UDID" ]]; then
  echo "error: --udid is required (booted is ambiguous with two booted simulators; see header)" >&2
  exit 1
fi
[[ -n "$FLOW" ]] || { echo "error: --flow is required" >&2; usage; }
[[ -n "$OUT" ]]  || { echo "error: --out is required" >&2; usage; }
[[ -f "$FLOW" ]] || { echo "error: flow not found: $FLOW" >&2; exit 1; }

for bin in xcrun maestro ffmpeg ffprobe magick; do
  command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 2; }
done

if [[ -d "$OUT" ]] && [[ -n "$(ls -A "$OUT" 2>/dev/null)" ]] && [[ "$FORCE" -ne 1 ]]; then
  echo "error: --out ($OUT) exists and is non-empty; pass --force to reuse it" >&2
  exit 1
fi

mkdir -p "$OUT/frames"
RECORDING="$OUT/recording.mp4"
rm -f "$RECORDING"

REC_PID=""
cleanup() {
  # safety net: catches ctrl-C or an unexpected exit mid-flow. A recorder
  # left running holds the host recording lock for the next invocation.
  if [[ -n "$REC_PID" ]] && kill -0 "$REC_PID" 2>/dev/null; then
    kill -9 "$REC_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

xcrun simctl io "$UDID" recordVideo --codec h264 --force "$RECORDING" &
REC_PID=$!
sleep 1

MAESTRO_EXIT=0
# ${arr[@]+"${arr[@]}"} guard: macOS's stock bash 3.2 treats a bare
# "${EXTRA_ARGS[@]}" on an empty array as an unbound variable under set -u.
maestro --udid "$UDID" test "$FLOW" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} || MAESTRO_EXIT=$?

# Stop the recorder and wait for the mp4 to stop growing (it flushes on
# SIGINT, not instantly) before touching the file with ffmpeg.
if kill -0 "$REC_PID" 2>/dev/null; then
  kill -INT "$REC_PID" 2>/dev/null || true
  prev_size=-1
  waited=0
  while (( waited < 10 )); do
    sleep 1
    waited=$(( waited + 1 ))
    if ! kill -0 "$REC_PID" 2>/dev/null; then
      break
    fi
    cur_size=$(stat -f%z "$RECORDING" 2>/dev/null || echo 0)
    if [[ "$cur_size" == "$prev_size" ]]; then
      break
    fi
    prev_size="$cur_size"
  done
fi

if [[ "$MAESTRO_EXIT" -ne 0 ]]; then
  echo "warning: maestro exited $MAESTRO_EXIT; still processing the recording" >&2
fi
[[ -s "$RECORDING" ]] || { echo "error: no recording written to $RECORDING" >&2; exit 1; }

ffmpeg -v error -y -i "$RECORDING" \
  -vf "crop=iw:ih*${CROP}:0:ih*(1-${CROP}),fps=${FPS}" \
  "$OUT/frames/%04d.png"

FRAME_FILES=( "$OUT"/frames/*.png )
FRAME_COUNT=${#FRAME_FILES[@]}
(( FRAME_COUNT > 0 )) || { echo "error: no frames extracted" >&2; exit 1; }

if (( EVERY > 1 )); then
  SHEET_FILES=()
  idx=0
  for f in "${FRAME_FILES[@]}"; do
    if (( idx % EVERY == 0 )); then
      SHEET_FILES+=( "$f" )
    fi
    idx=$(( idx + 1 ))
  done
else
  SHEET_FILES=( "${FRAME_FILES[@]}" )
fi

# `magick montage` calls annotate to lay out its default per-tile label even
# with no -label passed; on a host with a broken/empty fontconfig cache that
# is a hard failure ("unable to read font"), same issue sprite-sheet.sh
# already works around. Build the grid with bordered-tile row/column append
# instead, which never touches text rendering.
SHEET_WORK="$(mktemp -d "${TMPDIR:-/tmp}/frame-stack-sheet.XXXXXX")"
row_files=()
row_imgs=()
tile_idx=0
sheet_total=${#SHEET_FILES[@]}
for f in "${SHEET_FILES[@]}"; do
  bordered="$SHEET_WORK/$(printf 'b%05d.png' "$tile_idx")"
  magick "$f" -bordercolor '#222' -border 2 "$bordered"
  row_imgs+=( "$bordered" )
  tile_idx=$(( tile_idx + 1 ))
  if (( tile_idx % COLS == 0 )) || (( tile_idx == sheet_total )); then
    row_out="$SHEET_WORK/$(printf 'row%03d.png' "${#row_files[@]}")"
    magick "${row_imgs[@]}" -background '#222' +append +repage "$row_out"
    row_files+=( "$row_out" )
    row_imgs=()
  fi
done
magick "${row_files[@]}" -background '#222' -append +repage "$OUT/sheet.png"
rm -rf "$SHEET_WORK"

DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$RECORDING")

echo "frames: $FRAME_COUNT ($OUT/frames)"
echo "sheet: $OUT/sheet.png (${#SHEET_FILES[@]} tiles, ${COLS} cols)"
echo "recording duration: ${DURATION}s ($RECORDING)"
