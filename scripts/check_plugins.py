#!/usr/bin/env python3
"""Checks every plugin's files before a pull request is merged:  python3 scripts/check_plugins.py

It makes sure a plugin can be shown in the store and released: the fields of plugin.json, a CHANGELOG section for the
current version, the pictures, the target in project.yml. Exits with 1 on any problem."""
import json, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PLUGINS = os.path.join(ROOT, "plugins")
CATEGORIES = {"System", "Productivity", "Utilities", "Network", "Privacy", "Media", "Fun"}
errors = []

def fail(plugin, msg):
    errors.append(f"{plugin}: {msg}")
    print(f"FAIL {plugin}: {msg}")

project = open(os.path.join(ROOT, "project.yml")).read()
ids = set()
for name in sorted(os.listdir(PLUGINS)):
    folder = os.path.join(PLUGINS, name)
    meta_path = os.path.join(folder, "plugin.json")
    if not os.path.isfile(meta_path):
        continue
    try:
        m = json.load(open(meta_path))
    except ValueError as e:
        fail(name, f"plugin.json is not valid JSON ({e})"); continue
    for key in ("id", "target", "name", "description", "author", "icon", "version", "apiVersion"):
        if not m.get(key): fail(name, f"plugin.json needs \"{key}\"")
    if m.get("id") != name: fail(name, f"id \"{m.get('id')}\" must be the folder name")
    if m.get("id") in ids: fail(name, "id used twice")
    ids.add(m.get("id"))
    if not re.fullmatch(r"\d+\.\d+\.\d+(-alpha|-beta)?", str(m.get("version", ""))): fail(name, "version must look like 0.1.0-alpha")
    if len(m.get("description", "")) > 140: fail(name, "description is the one line of the store: keep it under 140 characters")
    if m.get("category") not in CATEGORIES: fail(name, f"category must be one of {sorted(CATEGORIES)}")
    tags = m.get("tags") or []
    if len(tags) < 3 or any(not isinstance(t, str) or t != t.lower() for t in tags): fail(name, "tags: at least 3 lowercase keywords people may search for")
    if len(m.get("details", "")) < 80: fail(name, "details: a paragraph about the plugin (at least 80 characters)")
    if len(m.get("features") or []) < 2: fail(name, "features: at least 2 short points")
    if not m.get("permissions"): fail(name, "permissions: say what it needs (\"No permission needed.\" is an answer)")
    if not os.path.isfile(os.path.join(folder, f"{m.get('target', name)}Plugin.swift")): fail(name, f"missing {m.get('target')}Plugin.swift")
    if f"\n  {m.get('target')}:" not in project: fail(name, f"project.yml has no target \"{m.get('target')}\"")
    log = os.path.join(folder, "CHANGELOG.md")
    if not os.path.isfile(log) or f"## [{m.get('version')}]" not in open(log).read(): fail(name, f"CHANGELOG.md needs a section \"## [{m.get('version')}]\"")
    media = os.path.join(folder, "media")
    shots = [f for f in os.listdir(media)] if os.path.isdir(media) else []
    if not shots: fail(name, "media/: add at least one screenshot (PNG or JPEG)")
    for f in shots:
        if os.path.getsize(os.path.join(media, f)) > 600_000: fail(name, f"media/{f} is over 600 KB")

print()
if errors:
    print(f"{len(errors)} problem(s)"); sys.exit(1)
print(f"{len(ids)} plugins checked: all good")
