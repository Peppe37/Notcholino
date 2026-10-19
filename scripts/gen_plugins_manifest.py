#!/usr/bin/env python3
"""Builds docs/plugins.json, the plugin store manifest read by the app.

Metadata comes from the item's plugin.json (plugins/, extensions/ for the project's own, community/ for other people's, see
scripts/store_items.py), the version and download from the latest GitHub release whose tag is "<id>-v<version>". Plugins and
extensions go in separate lists, so an older app (which only reads "plugins") never sees an extension.
Needs the `gh` CLI (GH_TOKEN set).
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import store_items

REPO = os.environ.get("GITHUB_REPOSITORY", "Peppe37/Notcholino")
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def releases():
    out = subprocess.check_output(["gh", "api", f"repos/{REPO}/releases?per_page=100"])
    return [r for r in json.loads(out) if not r.get("draft")]


def sha256_of(asset):
    digest = asset.get("digest") or ""
    if digest.startswith("sha256:"):
        return digest.split(":", 1)[1]
    # Older releases have no digest field: hash the download
    with urllib.request.urlopen(asset["browser_download_url"]) as resp:
        return hashlib.sha256(resp.read()).hexdigest()


SITE = "https://peppe37.github.io/Notcholino"


def latest_changes(path, version):
    """The bullet points of the CHANGELOG section for `version` (as plain sentences)"""
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return []
    m = re.search(r"^## \[%s\][^\n]*\n(.*?)(?=^## \[|\Z)" % re.escape(version), text, re.S | re.M)
    if not m:
        return []
    return [re.sub(r"[`*]", "", l[2:].strip()) for l in m.group(1).splitlines() if l.startswith("- ")][:4]


def main():
    all_releases = releases()  # newest first
    plugins, extensions, api_version, ext_api_version = [], [], 1, 1
    for it in store_items.items():
        meta, name, folder = it["meta"], it["name"], it["dir"]
        if not meta:
            continue
        prefix = f"{meta['id']}-v"
        release = next((r for r in all_releases if r["tag_name"].startswith(prefix)), None)
        asset = next((a for a in (release or {}).get("assets", []) if a["name"].endswith(".zip")), None)
        if not release or not asset:
            print(f"skip {meta['id']}: no release yet")
            continue
        entry = {
            "id": meta["id"],
            "name": meta["name"],
            "description": meta["description"],
            "author": meta["author"],
            "icon": meta["icon"],
            "version": release["tag_name"][len(prefix):],
            "url": asset["browser_download_url"],
            "sha256": sha256_of(asset),
            "kind": it["kind"],
            # Who made it: the project's own items say so, the community's name their maker (checked by check_plugins.py)
            "official": it["official"],
            "publisher": {"name": "Notcholino"} if it["official"] else {"name": meta["publisher"]["name"], "github": meta["publisher"]["github"]},
            "source": f"https://github.com/{REPO}/tree/main/{it['rel']}",
            **({"minAppVersion": meta["minAppVersion"]} if meta.get("minAppVersion") else {}),
        }
        # What its code can do: found in the source, plus what its maker declared
        found, _ = store_items.scan(folder)
        caps = sorted(set(found) | set(meta.get("capabilities") or []))
        if caps:
            entry["capabilities"] = caps
        # Store page: the long text, the features, the permissions, what is new, and the screenshots in <folder>/media
        for key in ("details", "features", "permissions", "video", "category", "tags", "warning"):
            if meta.get(key):
                entry[key] = meta[key]
        entry["whatsNew"] = latest_changes(os.path.join(folder, "CHANGELOG.md"), entry["version"])
        media = os.path.join(folder, "media")
        if os.path.isdir(media):
            out = os.path.join(ROOT, "docs", "plugins", meta["id"])
            os.makedirs(out, exist_ok=True)
            shots = []
            for f in sorted(os.listdir(media)):
                if f.lower().endswith((".png", ".jpg", ".jpeg", ".webp")):
                    shutil.copy2(os.path.join(media, f), os.path.join(out, f))
                    shots.append(f"{SITE}/plugins/{meta['id']}/{f}")
            if shots:
                entry["screenshots"] = shots
        if it["kind"] == "extension":
            ext_api_version = meta.get("apiVersion", ext_api_version)
            extensions.append(entry)
        else:
            api_version = meta.get("apiVersion", api_version)
            plugins.append(entry)
        print(f"{meta['id']} {entry['version']} ({it['kind']}, {'official' if it['official'] else 'community'})")

    out_path = os.path.join(ROOT, "docs", "plugins.json")
    with open(out_path, "w") as f:
        json.dump({"apiVersion": api_version, "plugins": plugins,
                   **({"extensionApiVersion": ext_api_version, "extensions": extensions} if extensions else {})}, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
