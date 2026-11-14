#!/bin/bash
# Renders every README image from scratch:
#   tools/readme-images/render.sh [--lang en|de] [out-dir]     (defaults: en, assets/readme)
#
# --lang sets the language the app's own parts render in (overlay, legend, footer). Everything drawn around them
# stays English. Rerun after any change to the overlay or the card; the images follow the code on main.
#
# 1. screen.swift draws the invented screen (a made-up plant shop; nothing from a real screen).
# 2. ReadmeImages.swift runs once as a temporary test in Tests/AIRenderTests/: the real reducer, overlay and card
#    renderer produce the overlay frames and card.png. The copy is removed again, also on failure.
# 3. stage.swift composes the final images around those renders; ffmpeg turns the hero frames into a GIF.
#
# Needs the host (AppKit, Core Animation) and ffmpeg. Touches neither the running app nor the clipboard.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd -P)
cd "$root"
lang=en
if [ "${1:-}" = --lang ]; then lang=${2:?--lang needs en or de}; shift 2; fi
case "$lang" in en|de) ;; *) echo "unknown language: $lang" >&2; exit 64 ;; esac
out=${1:-assets/readme}
mkdir -p "$out"
out=$(cd "$out" && pwd -P)
work=$(mktemp -d /private/tmp/ainnotator-readme.XXXXXXXX)
temp=Tests/AIRenderTests/ReadmeImagesTemp.swift
if [ -e "$temp" ]; then echo "$temp exists; remove it first." >&2; exit 2; fi
cleanup() { rm -f "$root/$temp"; rm -rf "$work"; }
trap cleanup EXIT

swiftc -O -o "$work/screen" tools/readme-images/screen.swift
swiftc -O -o "$work/stage" tools/readme-images/stage.swift
"$work/screen" "$work/screen.png"

cp tools/readme-images/ReadmeImages.swift "$temp"
README_SRC="$work/screen.png" README_OUT="$work" README_LANG="$lang" swift test --filter readmeImages
rm -f "$temp"
test -s "$work/card.png" && test -s "$work/timeline.tsv" && test -s "$work/overlay-final.png" && test -s "$work/geometry.tsv"

sips -s format png -Z 512 Bundle/AppIcon.icns --out "$work/icon.png" >/dev/null
"$work/stage" hero-still "$work" "$out/hero.png"
"$work/stage" anatomy "$work" "$out/card-anatomy.png"
# The blind test shows the material that was actually tested.
"$work/stage" blind research/blind-test "$out/blind-test.png"
"$work/stage" everywhere "$work" "$out/everywhere.png"
"$work/stage" social "$work" "$work/icon.png" "$out/social-preview.png"

# Hero: frames at 1760 px, so the GIF stays sharp at README width on Retina. One palette for all frames.
"$work/stage" hero-frames "$work" "$work/frames" 1.375
bytes=5000001
for colors in 256 192 128; do
  ffmpeg -v error -y -framerate 12 -i "$work/frames/frame-%03d.png" -vf "palettegen=max_colors=$colors:stats_mode=diff" "$work/palette.png"
  ffmpeg -v error -y -framerate 12 -i "$work/frames/frame-%03d.png" -i "$work/palette.png" \
    -filter_complex "[0:v][1:v]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" -loop 0 -map_metadata -1 "$out/hero.gif"
  bytes=$(stat -f%z "$out/hero.gif")
  [ "$bytes" -le 5000000 ] && break
done
[ "$bytes" -le 5000000 ] || { echo 'hero.gif exceeds 5 MB' >&2; exit 1; }
# GitHub takes at most 1 MB for the social preview.
[ "$(stat -f%z "$out/social-preview.png")" -lt 1000000 ] || { echo 'social-preview.png exceeds 1 MB' >&2; exit 1; }

for name in hero.gif hero.png card-anatomy.png blind-test.png everywhere.png social-preview.png; do
  file="$out/$name"
  if [ ! -s "$file" ] && [ "$name" = blind-test.png ]; then continue; fi
  test -s "$file"
  size=$(sips -g pixelWidth -g pixelHeight "$file" | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w "x" h}')
  printf '%-20s %-10s %8s bytes\n' "$name" "$size" "$(stat -f%z "$file")"
done
