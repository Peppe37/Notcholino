#!/bin/bash
# Builds what the preview video needs, in /tmp:
#   /tmp/stage, /tmp/mouse, /tmp/demowin   the helpers (wallpaper and captions, mouse, two windows for the Snap scene)
#   /tmp/demo                              a throwaway copy of the app, its plugins and its extensions
#
#   scripts/demo/build.sh
#
# Then:  scripts/demo/play-v2.sh up, start the screen recorder, scripts/demo/play-v2.sh play, stop it, scripts/demo/play-v2.sh down
set -euo pipefail
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

swiftc -o /tmp/stage scripts/demo/stage/main.swift
swiftc -o /tmp/mouse scripts/demo/mouse/main.swift
swiftc -o /tmp/demowin scripts/demo/windows/main.swift

xcodegen generate >/dev/null
OUT=/tmp/demo-build
xcodebuild -scheme Notcholino -configuration Release -derivedDataPath "$OUT" build -quiet
xcodebuild -project Notcholino.xcodeproj -scheme Notchy -configuration Debug -derivedDataPath "$OUT" build -quiet    # debug: it has the demo hook
xcodebuild -project Notcholino.xcodeproj -scheme Snap -configuration Release -derivedDataPath "$OUT" build -quiet

rm -rf /tmp/demo && mkdir -p /tmp/demo/ext /tmp/demo/plugins
cp -R "$OUT/Build/Products/Release/Notcholino.app" /tmp/demo/Notcholino.app
cp -R "$OUT/Build/Products/Debug/Notchy.bundle" /tmp/demo/ext/notchy.bundle
cp -R "$OUT/Build/Products/Release/Snap.bundle" /tmp/demo/ext/snap.bundle

# The plugins the video shows, at their latest version from the store
python3 - /tmp/demo/plugins <<'PY'
import json, sys, urllib.request, zipfile, io, os, shutil
dest = sys.argv[1]
want = ["espresso", "tomato", "hotter", "pinger", "clippy", "picker", "devices", "quicky"]
manifest = json.load(urllib.request.urlopen("https://peppe37.github.io/Notcholino/plugins.json"))
for p in manifest["plugins"]:
    if p["id"] not in want: continue
    data = urllib.request.urlopen(p["url"]).read()
    tmp = os.path.join(dest, "_x"); shutil.rmtree(tmp, ignore_errors=True); os.makedirs(tmp)
    zipfile.ZipFile(io.BytesIO(data)).extractall(tmp)
    bundle = [n for n in os.listdir(tmp) if n.endswith(".bundle")][0]
    os.rename(os.path.join(tmp, bundle), os.path.join(dest, p["id"] + ".bundle")); shutil.rmtree(tmp)
print("plugins:", sorted(os.listdir(dest)))
PY
echo "ready: scripts/demo/play-v2.sh up"
