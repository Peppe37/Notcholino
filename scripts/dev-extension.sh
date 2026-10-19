#!/bin/bash
# Builds an extension from a folder of Swift files and installs it where Notcholino loads extensions in developer mode.
#
#   scripts/dev-extension.sh extensions/hello HelloExtension
#
# The second argument is the principal class (the @objc name of your class). Quit and reopen Notcholino to load it.
# Needs Xcode's command line tools. No XcodeGen, no project file.
set -euo pipefail
cd "$(dirname "$0")/.."

dir="${1:?usage: $0 <folder with .swift files> <PrincipalClass>}"
class="${2:?usage: $0 <folder with .swift files> <PrincipalClass>}"
name="$(basename "$dir")"
out="$(mktemp -d)/$name.bundle"
mkdir -p "$out/Contents/MacOS"

swiftc -emit-library -module-name "$class" -target "$(uname -m)-apple-macos14.0" \
  -Xlinker -bundle -o "$out/Contents/MacOS/$name" \
  ExtensionAPI/NotcholinoExtensionAPI.swift "$dir"/*.swift

cat > "$out/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.notcholino.extension.$name</string>
<key>CFBundleName</key><string>$name</string>
<key>CFBundleExecutable</key><string>$name</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleVersion</key><string>1</string>
<key>NSPrincipalClass</key><string>$class</string>
</dict></plist>
PLIST

dest="$HOME/Library/Application Support/Notcholino/Extensions"
mkdir -p "$dest"
# Replace a previous build of the same extension (the old one stays loaded until Notcholino restarts)
if [ -d "$dest/$name.bundle" ]; then
  trash="$(mktemp -d)"
  mv "$dest/$name.bundle" "$trash/"
fi
cp -R "$out" "$dest/$name.bundle"
echo "Installed $dest/$name.bundle"
echo "Turn on developer mode in Settings → Plugin Store → Extensions, then quit and reopen Notcholino."
