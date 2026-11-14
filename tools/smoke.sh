#!/bin/sh
# Opens a folder in a debug build the way Finder does (LaunchServices, so the app comes to the front), steps through
# photos, zooms to 1:1 and prints the viewer's trace: load times and the presentation options (menu bar and Dock
# hidden = 10). Usage: [SNAPSHOT=<folder>] tools/smoke.sh <folder> [steps]
# With SNAPSHOT, the edge panels are drawn into <folder>/panel-*.png. With CULL=1 it rates three photos, moves the
# reject to _bin and back: only ever on a folder of copies.
set -e
cd "$(dirname "$0")/.."
APP="$PWD/build/DerivedData/Build/Products/Debug/RawBoy Viewer.app"
[ -d "$APP" ] || { echo "Build first: xcodebuild -scheme RawBoyViewer -derivedDataPath build/DerivedData build" >&2; exit 2; }
OUT=$(mktemp)
open -W -n --stdout "$OUT" --stderr /dev/null \
    --env RAWBOY_TRACE=1 --env RAWBOY_AUTOPLAY="${2:-6}" ${SNAPSHOT:+--env RAWBOY_SNAPSHOT="$SNAPSHOT"} ${CULL:+--env RAWBOY_CULL=1} ${M7:+--env RAWBOY_M7=1} -a "$APP" "$1"
cat "$OUT"
rm "$OUT"
