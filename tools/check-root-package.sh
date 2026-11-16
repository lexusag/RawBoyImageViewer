#!/bin/sh
# The repository root's Package.swift (what RawBoy Desktop depends on by git tag) and Packages/Package.swift (the Viewer
# app's own package) must declare the same name, platforms, products and targets (names, kinds, dependencies, excludes).
# Only `path:` and the optimisation flags may differ. Usage: tools/check-root-package.sh
set -e
cd "$(dirname "$0")/.."
normalise() {
    swift package --package-path "$1" dump-package | python3 -c '
import json, sys
p = json.load(sys.stdin)
def deps(t):
    out = []
    for d in t.get("dependencies", []):
        for kind, v in d.items():
            out.append((kind, v[0] if isinstance(v, list) else v))
    return sorted(out)
print(json.dumps({
    "name": p["name"],
    "platforms": sorted((x["platformName"], x["version"]) for x in p.get("platforms", [])),
    "products": sorted((x["name"], tuple(x["targets"]), tuple(x["type"].keys())) for x in p["products"]),
    "targets": sorted((t["name"], t["type"], deps(t), sorted(t.get("exclude", []))) for t in p["targets"]),
}, indent=1, sort_keys=True))'
}
normalise . > "${TMPDIR:-/tmp}/root-package.json"
normalise Packages > "${TMPDIR:-/tmp}/packages-package.json"
if diff -u "${TMPDIR:-/tmp}/packages-package.json" "${TMPDIR:-/tmp}/root-package.json"; then
    echo "Package.swift and Packages/Package.swift declare the same targets."
else
    echo "Package.swift and Packages/Package.swift differ: change both together." >&2
    exit 1
fi
