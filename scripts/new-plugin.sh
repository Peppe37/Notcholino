#!/bin/bash
# Creates a new plugin: its folder with a small working example, plugin.json, CHANGELOG.md and the target in project.yml.
#
#   scripts/new-plugin.sh <id> <Name> ["One-line description"]
#   scripts/new-plugin.sh hello Hello "Says hello from the notch"
#
# <id> is lowercase letters and digits (it is the install folder and the tag prefix), <Name> is the button's name.
set -euo pipefail
cd "$(dirname "$0")/.."

id="${1:-}"; name="${2:-}"; desc="${3:-A new Notcholino plugin}"
if [[ ! "$id" =~ ^[a-z][a-z0-9]*$ ]] || [[ ! "$name" =~ ^[A-Z][A-Za-z0-9]*$ ]]; then
  echo "usage: $0 <id> <Name> [\"description\"]   (id: lowercase letters and digits; Name: starts with a capital, letters and digits only)"
  exit 1
fi
[ -e "plugins/$id" ] && { echo "plugins/$id already exists"; exit 1; }
grep -q "^  $name:" project.yml && { echo "project.yml already has a target called $name"; exit 1; }

author="$(git config user.name || echo "Your name")"
min_app="$(grep -m1 'MARKETING_VERSION' project.yml | sed 's/.*"\(.*\)".*/\1/')"
mkdir -p "plugins/$id"

cat > "plugins/$id/${name}Plugin.swift" <<SWIFT
// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation

/// $desc
///
/// This is a small working example: a button that counts how many times you chose an option, shows the count as its
/// label, and says something in a popup under the notch. Replace what is inside with your own idea.
/// The whole API is documented in Shared/NotcholinoPluginAPI.swift and in plugins/README.md.
@objc(${name}Plugin)
final class ${name}Plugin: NSObject, NotcholinoPlugin {

    // MARK: About the plugin

    var apiVersion: Int { notcholinoPluginAPIVersion }
    var pluginIdentifier: String { "$id" }
    var pluginName: String { "$name" }
    var pluginVersion: String {
        Bundle(for: ${name}Plugin.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    var pluginAuthor: String { "$author" }
    var pluginDescription: String { "$desc" }

    // MARK: State

    private var count = 0
    private var popup: (([String: Any]) -> Void)?

    /// Notcholino hands you a function to show a popup under the closed notch
    func setPopupHandler(_ handler: @escaping ([String: Any]) -> Void) { popup = handler }

    // MARK: The button in the Control Center

    /// The button lights up while this is true
    var isActive: Bool { count > 0 }
    /// An SF Symbol (https://developer.apple.com/sf-symbols/)
    var controlCenterIcon: String { "puzzlepiece.extension" }
    /// A short text drawn in the button instead of the symbol (return "" to keep the symbol)
    var controlCenterLabel: String { count > 0 ? "\(count)" : "" }
    /// The button's color as "#RRGGBB" ("" for the default)
    var controlCenterTintColor: String { count > 0 ? "#30D158" : "" }
    /// Shown at the top right of the options
    var statusText: String { count == 0 ? "" : "chosen \(count) time\(count == 1 ? "" : "s")" }

    // MARK: The options that open when you click the button

    func menuItems() -> [[String: Any]] {
        [
            ["header": "Pick one"],
            ["id": "one", "title": "One"],
            ["id": "two", "title": "Two"],
            ["id": "three", "title": "Three"],
            ["id": "reset", "title": "Reset", "destructive": true]
        ]
    }

    func performMenuAction(_ id: String) {
        if id == "reset" { count = 0; return }
        count += 1
        popup?(["title": "You chose \(id)", "subtitle": "$name", "icon": "checkmark.circle.fill", "color": "#30D158"])
    }
}
SWIFT

cat > "plugins/$id/plugin.json" <<JSON
{
  "id": "$id",
  "target": "$name",
  "name": "$name",
  "description": "$desc",
  "author": "$author",
  "icon": "puzzlepiece.extension",
  "version": "0.1.0-alpha",
  "apiVersion": 1,
  "minAppVersion": "$min_app",
  "category": "Utilities",
  "tags": ["replace", "with", "words", "people", "search"],
  "details": "A paragraph for the plugin's page in the store: what it is for, what you see, how you use it. At least a few sentences.",
  "features": ["The first thing it does", "The second thing it does"],
  "permissions": "No permission needed."
}
JSON

cat > "plugins/$id/CHANGELOG.md" <<MD
# Changelog

## [0.1.0-alpha] - $(date +%Y-%m-%d)

### Added
- First version of $name.
MD

python3 - "$id" "$name" <<'PY'
import re, sys
pid, name = sys.argv[1], sys.argv[2]
s = open("project.yml").read()
block = f'''  {name}:
    type: bundle
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - plugins/{pid}
      - Shared
    settings:
      base:
        PRODUCT_NAME: {name}
        PRODUCT_BUNDLE_IDENTIFIER: com.giuseppe.Notcholino.plugin.{pid}
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_NSPrincipalClass: {name}Plugin
        MARKETING_VERSION: "0.1.0-alpha"
        CURRENT_PROJECT_VERSION: "1"
        CODE_SIGN_IDENTITY: "-"
        DEVELOPMENT_TEAM: ""
'''
m = re.search(r"\n  MediaRemoteAdapter:\n", s)
s = s[:m.start() + 1] + block + s[m.start() + 1:]
open("project.yml", "w").write(s)
PY

mkdir -p "plugins/$id/media"
echo "Add one or two screenshots of the plugin in plugins/$id/media (PNG or JPEG): they are the pictures of its store page." > "plugins/$id/media/README.txt"

echo
echo "Created plugins/$id and the $name target."
echo "Next:  scripts/dev-plugin.sh $name     (builds it and installs it for Notcholino to load)"
echo "Then fill in plugins/$id/plugin.json (category, tags, details, features, permissions) and run:  python3 scripts/check_plugins.py"
