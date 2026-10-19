#!/usr/bin/env python3
"""Shared by the store scripts: where plugins and extensions live, and what their source can do.

Layout (every item is a folder with a plugin.json):
  plugins/<id>/                 official plugins (made by the Notcholino project)
  extensions/<id>/              official extensions
  community/plugins/<id>/       plugins made by other people, added through a reviewed pull request
  community/extensions/<id>/    extensions made by other people

Run as `python3 scripts/store_items.py <id>` to print the folder of an item (used by the release workflow)."""
import json, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# (folder, official)
ROOTS = [("plugins", True), ("extensions", True), ("community/plugins", False), ("community/extensions", False)]

# What a piece of source can do, found by looking for the APIs that do it. Everything found is shown in the store; for community
# items it must also be declared in plugin.json ("capabilities"), so a reviewer sees it before reading a line.
CAPABILITIES = {
    "network":       r"URLSession|URLRequest|NWConnection|NWPathMonitor|WKWebView|CFNetwork|NSURLConnection",
    "shell":         r"\bProcess\(|NSTask|posix_spawn|\bpopen\(|\bsystem\(",
    "applescript":   r"NSAppleScript|OSAScript|NSAppleEventDescriptor",
    "files":         r"FileManager|NSOpenPanel|NSSavePanel|NSHomeDirectory|contentsOf:|\.write\(to:",
    "keychain":      r"SecItem|kSecClass",
    "accessibility": r"AXUIElement|AXIsProcessTrusted|CGEvent\.tapCreate|CGEventTapCreate|CGEventPost",
    "microphone":    r"AVAudioRecorder|AVAudioEngine|AVCaptureDevice|AVAudioSession|SFSpeech",
    "camera":        r"AVCaptureSession|AVCaptureDevice\.default\(for: *\.video",
    "screen":        r"CGWindowListCreateImage|SCStream|SCScreenshotManager|CGDisplayStream|CGDisplayCreateImage",
    "bluetooth":     r"CoreBluetooth|IOBluetooth|CBCentralManager",
    "location":      r"CoreLocation|CLLocationManager",
    "contacts":      r"Contacts\b|CNContactStore",
    "calendar":      r"EventKit|EKEventStore",
}

# Never allowed in community code: ways to hide what the code does, or to change the app around it
FORBIDDEN = {
    "loads other code":        r"\bdlopen\(|\bdlsym\(|NSClassFromString|Bundle\(path:|\.load\(\)",
    "swaps the app's methods": r"method_exchangeImplementations|class_replaceMethod|method_setImplementation|objc_setAssociatedObject",
    "runs a script it carries": r"JavaScriptCore|JSContext|evaluateJavaScript",
}


def items():
    """Every item: dict with path, meta, official, kind"""
    out = []
    for rel, official in ROOTS:
        base = os.path.join(ROOT, rel)
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            meta_path = os.path.join(base, name, "plugin.json")
            if os.path.isfile(meta_path):
                try:
                    meta = json.load(open(meta_path, encoding="utf-8"))
                except ValueError:
                    meta = None
                out.append({"dir": os.path.join(base, name), "rel": f"{rel}/{name}", "name": name, "meta": meta,
                            "official": official, "kind": (meta or {}).get("kind") or ("extension" if rel.endswith("extensions") else "plugin")})
    return out


def sources(folder):
    for dirpath, _, files in os.walk(folder):
        for f in files:
            if f.endswith((".swift", ".m", ".h", ".mm", ".c")):
                yield os.path.join(dirpath, f)


def scan(folder):
    """(capabilities found, forbidden things found) in the source files of one item"""
    found, bad = set(), set()
    for path in sources(folder):
        text = open(path, encoding="utf-8", errors="replace").read()
        text = re.sub(r"//.*", "", text)                     # a mention in a comment is not use
        for cap, pat in CAPABILITIES.items():
            if re.search(pat, text):
                found.add(cap)
        for why, pat in FORBIDDEN.items():
            if re.search(pat, text):
                bad.add(why)
    return sorted(found), sorted(bad)


if __name__ == "__main__":
    wanted = sys.argv[1]
    for it in items():
        if it["name"] == wanted:
            print(it["rel"]); sys.exit(0)
    sys.exit(f"No plugin or extension '{wanted}'")
