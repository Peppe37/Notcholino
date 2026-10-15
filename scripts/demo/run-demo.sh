#!/bin/bash
# Sets the stage for the demo video and puts everything back afterwards.
#
#   scripts/demo/run-demo.sh prepare     backs up your settings and plugins, installs all the plugins in a throwaway copy of the
#                                        app, covers the screen with a clean wallpaper and starts the notch on top of it
#   scripts/demo/run-demo.sh teardown    stops it all, restores your plugins and settings, and starts your own Notcholino again
#
# While it runs, the screen is covered and the mouse is driven by a script: don't touch the Mac.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
STATE=/tmp/demo-state
PLUGINS="$HOME/Library/Application Support/Notcholino/Plugins"
DOMAIN=com.giuseppe.Notcholino
VERSION="${DEMO_APP_VERSION:-0.12.0-alpha}"

prepare() {
  mkdir -p "$STATE"
  if [ ! -d "$STATE/plugins" ]; then
    cp -R "$PLUGINS" "$STATE/plugins"
    defaults export "$DOMAIN" "$STATE/prefs.plist" 2>/dev/null || true
  fi
  pkill -x Notcholino 2>/dev/null || true
  pkill -f "mediaremote-adapter.pl" 2>/dev/null || true
  sleep 1

  # The released app (signed with the fixed certificate, so macOS keeps the permissions you gave it)
  if [ ! -d /tmp/demo/Notcholino.app ]; then
    mkdir -p /tmp/demo /tmp/demo-mount
    curl -fsSL -o /tmp/demo/app.dmg "https://github.com/Peppe37/Notcholino/releases/download/v${VERSION}/Notcholino-${VERSION}.dmg"
    hdiutil attach -nobrowse -readonly -mountpoint /tmp/demo-mount /tmp/demo/app.dmg >/dev/null
    cp -R /tmp/demo-mount/Notcholino.app /tmp/demo/Notcholino.app
    hdiutil detach /tmp/demo-mount >/dev/null
  fi

  # Every plugin of the store, at its latest version
  rm -rf "$PLUGINS"; mkdir -p "$PLUGINS"
  python3 - "$PLUGINS" <<'PY'
import json, sys, urllib.request, zipfile, io, os, shutil
dest = sys.argv[1]
manifest = json.load(urllib.request.urlopen("https://peppe37.github.io/Notcholino/plugins.json"))
for p in manifest["plugins"]:
    data = urllib.request.urlopen(p["url"]).read()
    tmp = os.path.join(dest, "_x"); shutil.rmtree(tmp, ignore_errors=True); os.makedirs(tmp)
    zipfile.ZipFile(io.BytesIO(data)).extractall(tmp)
    bundle = [n for n in os.listdir(tmp) if n.endswith(".bundle")][0]
    os.rename(os.path.join(tmp, bundle), os.path.join(dest, p["id"] + ".bundle")); shutil.rmtree(tmp)
print("plugins:", sorted(f[:-7] for f in os.listdir(dest)))
PY
  # The first row of the Control Center: the ones the video shows
  defaults write "$DOMAIN" pluginOrder -array hotter batlife tomato picker pinger clippy devices espresso scrolly dusty quicky reader tidy closeme watcher
  defaults write "$DOMAIN" updateCheckEnabled -bool false

  /tmp/stage "$ROOT/docs/assets/shots/control-center.png" >/dev/null 2>&1 &
  echo $! > "$STATE/stage.pid"
  sleep 1
  NOTCHOLINO_NOW_PLAYING_SCRIPT="$HERE/fake_now_playing.pl" /tmp/demo/Notcholino.app/Contents/MacOS/Notcholino >/dev/null 2>&1 &
  echo $! > "$STATE/app.pid"
  sleep 6
  echo "stage and notch are up"
}

teardown() {
  echo "quit" >> /tmp/stage-cmd.txt 2>/dev/null || true
  sleep 1
  pkill -x stage 2>/dev/null || true
  [ -f "$STATE/app.pid" ] && kill "$(cat "$STATE/app.pid")" 2>/dev/null || true
  pkill -f "/tmp/demo/Notcholino.app" 2>/dev/null || true
  pkill -f "mediaremote-adapter.pl" 2>/dev/null || true
  sleep 1
  if [ -d "$STATE/plugins" ]; then
    rm -rf "$PLUGINS"; cp -R "$STATE/plugins" "$PLUGINS"
  fi
  if [ -f "$STATE/prefs.plist" ]; then defaults import "$DOMAIN" "$STATE/prefs.plist"; else defaults delete "$DOMAIN" pluginOrder 2>/dev/null || true; defaults delete "$DOMAIN" updateCheckEnabled 2>/dev/null || true; fi
  # Whatever the video dropped on the Shelf
  find "$HOME/Library/Application Support/Notcholino/Shelf" -mindepth 1 -delete 2>/dev/null || true
  rm -rf "$STATE"
  open /Applications/Notcholino.app
  echo "everything is back as it was"
}

case "${1:-}" in
  prepare) prepare ;;
  teardown) teardown ;;
  *) echo "usage: $0 prepare | teardown" ;;
esac
