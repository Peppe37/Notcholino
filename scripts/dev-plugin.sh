#!/bin/bash
# Builds a plugin and installs it in ~/Library/Application Support/Notcholino/Plugins, where Notcholino loads it.
#
#   scripts/dev-plugin.sh <Name>
#
# Quit and reopen Notcholino to load it (a plugin already loaded is not reloaded). Needs XcodeGen and Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

name="${1:?usage: $0 <Name>}"
id="$(python3 - "$name" <<'PY'
import json, glob, sys
for f in glob.glob("plugins/*/plugin.json"):
    d = json.load(open(f))
    if d["target"] == sys.argv[1]: print(d["id"])
PY
)"
[ -n "$id" ] || { echo "no plugin with the target $name (see plugins/*/plugin.json)"; exit 1; }

xcodegen generate -q
build="$(mktemp -d)"
xcodebuild -project Notcholino.xcodeproj -scheme "$name" -configuration Release -derivedDataPath "$build" build -quiet
dest="$HOME/Library/Application Support/Notcholino/Plugins"
mkdir -p "$dest"
rm -rf "$dest/$id.bundle"
cp -R "$build/Build/Products/Release/$name.bundle" "$dest/$id.bundle"
echo "Installed $dest/$id.bundle"
echo "Quit and reopen Notcholino to load it."
