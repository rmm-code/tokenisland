#!/usr/bin/env bash
# Cuts the promo master capture into the three social deliverables with
# burned-in captions.
#
#   ./Scripts/promo_export.sh Master.mov [outdir]
#
# Captions are composited as PNGs rendered by promo_caption.swift — the
# ffmpeg on this machine is built without freetype/libass, so drawtext and
# subtitles are both unavailable.
#
# Tuning after the first real capture:
#   TI_TRIM_START / TI_TRIM_DUR   trim the master before anything else
#   TI_CROP="w:h:x:y"             punch-in region, in SOURCE pixels
#   TI_BEATS=/path/to/beats.txt   caption sheet ("start|end|text" per line)
#
# Vertical formats punch in by default: a full desktop scaled to 1080 wide
# leaves the notch panel too small to read on a phone.
set -euo pipefail

MASTER="${1:-}"
OUTDIR="${2:-outputs/promo}"
[ -n "$MASTER" ] && [ -f "$MASTER" ] || { echo "usage: $0 <master.mov> [outdir]" >&2; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
CAPTION_SWIFT="${HERE}/promo_caption.swift"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ti-promo-export.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUTDIR"

# ---------------------------------------------------------------- source

SRC_W=$(ffprobe -v error -select_streams v:0 -show_entries stream=width  -of csv=p=0 "$MASTER")
SRC_H=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$MASTER")
echo "Master: ${MASTER} (${SRC_W}x${SRC_H})"

# Punch-in regions, top-centre on the notch and its panel. Square and vertical
# want a taller, narrower region than the wide format: a 2:1 desktop band
# scaled to 1080 wide is only ~520px of a 1920-tall canvas, which strands the
# composition in dead space. Retune both against the real capture.
crop_spec() { # $1 width%, $2 height%
  local w=$(( SRC_W * $1 / 100 ))
  local h=$(( SRC_H * $2 / 100 ))
  echo "${w}:${h}:$(( (SRC_W - w) / 2 )):0"
}
CROP_SQUARE="${TI_CROP_SQUARE:-${TI_CROP:-$(crop_spec 58 62)}}"
CROP_VERT="${TI_CROP_VERT:-${TI_CROP:-$(crop_spec 50 66)}}"
echo "Punch-in — square: ${CROP_SQUARE} · vertical: ${CROP_VERT}"

TRIM=""
if [ -n "${TI_TRIM_START:-}" ]; then TRIM="-ss ${TI_TRIM_START}"; fi
if [ -n "${TI_TRIM_DUR:-}" ]; then TRIM="${TRIM} -t ${TI_TRIM_DUR}"; fi

# ---------------------------------------------------------------- captions

# Beat sheet: start|end|text (seconds, relative to the trimmed master).
BEATS_FILE="${TI_BEATS:-${WORK}/beats.txt}"
if [ ! -f "$BEATS_FILE" ]; then
  cat > "$BEATS_FILE" <<'BEATS'
0.4|4.0|4 AI agents. One notch.
4.4|9.0|Blue = working. Green = done. Orange = needs you.
9.4|16.0|Approve changes without leaving your editor.
16.4|22.0|Answer questions with one keystroke.
22.4|27.0|Know the moment it's done.
27.4|30.0|Plus live usage limits.
BEATS
fi
echo "Beats: $(grep -c . "$BEATS_FILE") captions from ${BEATS_FILE}"

# Renders every caption at $1 px wide / $2 pt and echoes the filter chain that
# overlays them, bottom-anchored $3 px above the canvas floor.
build_caption_filter() {
  local width="$1" size="$2" bottom_margin="$3"
  local idx=0 inputs="" chain="" label="[v]"
  while IFS='|' read -r start end text; do
    [ -n "${text:-}" ] || continue
    local png="${WORK}/cap-${width}-${idx}.png"
    swift "$CAPTION_SWIFT" --text "$text" --out "$png" --width "$width" --size "$size" > /dev/null
    inputs="${inputs} -i ${png}"
    local next="[c${idx}]"
    # Overlay input indices start at 1 — index 0 is the video.
    chain="${chain}${label}[$((idx + 1)):v]overlay=x=0:y=main_h-overlay_h-${bottom_margin}:enable='between(t,${start},${end})'${next};"
    label="${next}"
    idx=$((idx + 1))
  done < "$BEATS_FILE"
  # The trailing ';' is kept deliberately: it separates the chain from the
  # final format filter, and leaves a valid graph when there are no captions.
  echo "${inputs}§${chain}§${label}"
}

# Renders one deliverable.
#   $1 name  $2 out_w  $3 out_h  $4 font_size  $5 bottom_margin  $6 pre-filter
render() {
  local name="$1" ow="$2" oh="$3" size="$4" margin="$5" pre="$6"
  local built inputs chain last
  built="$(build_caption_filter "$ow" "$size" "$margin")"
  inputs="$(echo "$built" | awk -F'§' '{print $1}')"
  chain="$(echo "$built"  | awk -F'§' '{print $2}')"
  last="$(echo "$built"   | awk -F'§' '{print $3}')"

  local out="${OUTDIR}/TokenIsland-${name}.mp4"
  echo "→ ${name} (${ow}x${oh})"
  # shellcheck disable=SC2086
  ffmpeg -y -v error -stats $TRIM -i "$MASTER" $inputs \
    -filter_complex "[0:v]${pre},fps=30,format=rgba[v];${chain}${last}format=yuv420p[out]" \
    -map "[out]" -an \
    -c:v libx264 -profile:v high -preset slow -crf 19 -pix_fmt yuv420p \
    -movflags +faststart "$out"
  echo "   ${out}"
}

# 16:9 — full desktop, top-anchored so the notch is never cropped away.
render "16x9" 1920 1080 52 64 \
  "scale=1920:-2:flags=lanczos,crop=1920:1080:0:0"

# 1:1 — punched in, sat just above centre so the caption has its own space.
render "1x1" 1080 1080 44 84 \
  "crop=${CROP_SQUARE},scale=1080:-2:flags=lanczos,pad=1080:1080:0:(1080-ih)/2-60:color=0x0A0A0Cff"

# 9:16 — punched in and optically centred; the 300px caption margin keeps the
# bottom 14% clear of platform chrome.
render "9x16" 1080 1920 46 300 \
  "crop=${CROP_VERT},scale=1080:-2:flags=lanczos,pad=1080:1920:0:(1920-ih)/2-80:color=0x0A0A0Cff"

echo
echo "Done. Deliverables in ${OUTDIR}:"
ls -lh "$OUTDIR" | tail -n +2
