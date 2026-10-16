#!/usr/bin/env python3
"""Builds docs/plugins.json, the plugin store manifest read by the app.

Metadata comes from plugins/<id>/plugin.json, the version and download from the latest
GitHub release whose tag is "<id>-v<version>". Needs the `gh` CLI (GH_TOKEN set).
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import urllib.request

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
    plugins, api_version = [], 1
    plugins_dir = os.path.join(ROOT, "plugins")
    for name in sorted(os.listdir(plugins_dir)):
        meta_path = os.path.join(plugins_dir, name, "plugin.json")
        if not os.path.isfile(meta_path):
            continue
        meta = json.load(open(meta_path))
        prefix = f"{meta['id']}-v"
        release = next((r for r in all_releases if r["tag_name"].startswith(prefix)), None)
        asset = next((a for a in (release or {}).get("assets", []) if a["name"].endswith(".zip")), None)
        if not release or not asset:
            print(f"skip {meta['id']}: no release yet")
            continue
        api_version = meta.get("apiVersion", api_version)
        plugins.append({
            "id": meta["id"],
            "name": meta["name"],
            "description": meta["description"],
            "author": meta["author"],
            "icon": meta["icon"],
            "version": release["tag_name"][len(prefix):],
            "url": asset["browser_download_url"],
            "sha256": sha256_of(asset),
            **({"minAppVersion": meta["minAppVersion"]} if meta.get("minAppVersion") else {}),
        })
        # Store page: the long text, the features, the permissions, what is new, and the screenshots in plugins/<id>/media
        entry = plugins[-1]
        for key in ("details", "features", "permissions", "video", "category", "tags"):
            if meta.get(key):
                entry[key] = meta[key]
        entry["whatsNew"] = latest_changes(os.path.join(plugins_dir, name, "CHANGELOG.md"), entry["version"])
        media = os.path.join(plugins_dir, name, "media")
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
        print(f"{meta['id']} {plugins[-1]['version']}")

    out_path = os.path.join(ROOT, "docs", "plugins.json")
    with open(out_path, "w") as f:
        json.dump({"apiVersion": api_version, "plugins": plugins}, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
