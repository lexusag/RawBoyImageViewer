#!/bin/sh
# Compares the colours in DesignTokens.swift with RawBoy's DESIGN.md front matter, so the two apps can't drift apart.
# Usage: tools/check-design-tokens.sh [path to a RawBoy checkout]   (default: ../RawBoy)
set -e
cd "$(dirname "$0")/.."
RAWBOY=${1:-../RawBoy}
DESIGN="$RAWBOY/DESIGN.md"
TOKENS=Packages/Sources/RawBoyBrowseKit/DesignTokens.swift
[ -f "$DESIGN" ] || { echo "No $DESIGN: pass the path to a RawBoy checkout." >&2; exit 2; }

# kebab-case name → camelCase, as DesignTokens names them.
camel() { echo "$1" | awk -F- '{ out = $1; for (i = 2; i <= NF; i++) out = out toupper(substr($i, 1, 1)) substr($i, 2); print out }'; }

status=0
FAIL=$(mktemp)
rm "$FAIL"
# The colours block of the front matter: lines like `  ink-black: "#121212"` until the next top-level key.
sed -n '/^colors:/,/^[a-z]/p' "$DESIGN" | grep -E '^\s+[a-z-]+: "#[0-9a-fA-F]{6}"' | while IFS= read -r line; do
    name=$(echo "$line" | sed -E 's/^ *([a-z-]+):.*/\1/')
    hex=$(echo "$line" | sed -E 's/.*"#([0-9a-fA-F]{6})".*/\1/' | tr 'a-f' 'A-F')
    swift=$(camel "$name")
    ours=$(grep -E "static let $swift: UInt32 = 0x" "$TOKENS" | sed -E 's/.*0x([0-9A-Fa-f]{6}).*/\1/' | tr 'a-f' 'A-F')
    if [ -z "$ours" ]; then
        echo "missing: $name (#$hex) has no DesignTokens.Colour.$swift"
        echo fail > "$FAIL"
    elif [ "$ours" != "$hex" ]; then
        echo "differs: $name is #$hex in RawBoy, #$ours here"
        echo fail > "$FAIL"
    else
        echo "ok: $name #$hex"
    fi
done
if [ -f "$FAIL" ]; then rm "$FAIL"; status=1; fi
exit $status
