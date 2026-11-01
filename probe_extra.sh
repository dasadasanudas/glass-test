#!/bin/sh
# Extra artifact collection for the glass probe. $1 = output directory.
# Public real-Mac reference screenshots (512 Pixels library) and the matching wallpaper.
OUT="$1"; mkdir -p "$OUT/refs"; cd "$OUT/refs" || exit 0
B=https://media.512pixels.net/downloads/macos-screenshots/26
for n in 26-Tahoe-Desktop 26-Tahoe-Finder-Control-Center 26-Tahoe-Finder-App-Switcher 26-Tahoe-Mission-Control 26-Tahoe-Spotlight 26-Tahoe-Notification-Center 26-Tahoe-Finder-Home 26-Tahoe-Apperance-Style-Light 26-Tahoe-Apperance-Style-Dark 26-Tahoe-Apperance-Style-Clear-Light 26-Tahoe-Widgets 26-Tahoe-Calculator 26-Tahoe-Stage-Manager; do
  curl -fsSL --max-time 30 -o "$n.png" "$B/$n.png" || echo "FAIL $n"
done
curl -fsSL --max-time 60 -o 26-Tahoe-Beach-Day.png https://media.512pixels.net/downloads/macos-wallpapers-6k/26-Tahoe-Beach-Day.png || echo "FAIL wallpaper"
sips -g pixelWidth -g pixelHeight -g space -g profile *.png 2>&1
sips --resampleHeight 1800 26-Tahoe-Beach-Day.png --out wall-h1800.png >/dev/null 2>&1 && sips -g pixelWidth -g pixelHeight -g profile wall-h1800.png
S=$(stat -f%z 26-Tahoe-Beach-Day.png 2>/dev/null || echo 0)
[ "$S" -gt 90000000 ] && rm -f 26-Tahoe-Beach-Day.png
ls -la
