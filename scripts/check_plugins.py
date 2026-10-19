#!/usr/bin/env python3
"""Checks every plugin and extension before a pull request is merged:  python3 scripts/check_plugins.py

It makes sure each one can be shown in the store and released (the fields of plugin.json, a CHANGELOG section for the current
version, the pictures, the target), and that what comes from the community is safe to review: its maker is named, nobody
pretends to be the project, what its source can do is declared, and nothing tries to hide what the code does.
Exits with 1 on any problem."""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import store_items

ROOT = store_items.ROOT
CATEGORIES = {"System", "Productivity", "Utilities", "Network", "Privacy", "Media", "Fun", "AI"}
errors = []


def fail(item, msg):
    errors.append(f"{item}: {msg}")
    print(f"FAIL {item}: {msg}")


project = open(os.path.join(ROOT, "project.yml")).read()
targets_file = os.path.join(ROOT, "community", "targets.yml")
targets = open(targets_file).read() if os.path.isfile(targets_file) else ""
ids, names, targets_seen = set(), set(), set()
count = 0

for it in store_items.items():
    name, folder, official, kind, m = it["name"], it["dir"], it["official"], it["kind"], it["meta"]
    label = it["rel"]
    count += 1
    if m is None:
        fail(label, "plugin.json is not valid JSON"); continue

    for key in ("id", "target", "name", "description", "author", "icon", "version", "apiVersion"):
        if not m.get(key): fail(label, f"plugin.json needs \"{key}\"")
    if m.get("id") != name: fail(label, f"id \"{m.get('id')}\" must be the folder name")
    if not re.fullmatch(r"[a-z][a-z0-9]{1,23}", str(m.get("id", ""))): fail(label, "id: 2 to 24 lowercase letters and digits, starting with a letter")
    if m.get("id") in ids: fail(label, "id used twice (ids are shared by plugins and extensions)")
    ids.add(m.get("id"))
    if str(m.get("name", "")).lower() in names: fail(label, "another item already has this name")
    names.add(str(m.get("name", "")).lower())
    if m.get("target") in targets_seen: fail(label, "target used twice")
    targets_seen.add(m.get("target"))
    if (m.get("kind") or kind) != kind: fail(label, f"\"kind\" must be \"{kind}\" here")
    if not re.fullmatch(r"\d+\.\d+\.\d+(-alpha|-beta)?", str(m.get("version", ""))): fail(label, "version must look like 0.1.0-alpha")
    if len(m.get("description", "")) > 140: fail(label, "description is the one line of the store: keep it under 140 characters")
    if m.get("category") not in CATEGORIES: fail(label, f"category must be one of {sorted(CATEGORIES)}")
    tags = m.get("tags") or []
    if len(tags) < 3 or any(not isinstance(t, str) or t != t.lower() for t in tags): fail(label, "tags: at least 3 lowercase keywords people may search for")
    if "warning" in m and len(m["warning"]) < 20: fail(label, "warning: say what the problem is and how to get out of it")
    if len(m.get("details", "")) < 80: fail(label, "details: a paragraph about it (at least 80 characters)")
    if len(m.get("features") or []) < 2: fail(label, "features: at least 2 short points")
    if not m.get("permissions"): fail(label, "permissions: say what it needs (\"No permission needed.\" is an answer)")
    main_file = f"{m.get('target', name)}{'Extension' if kind == 'extension' else 'Plugin'}.swift"
    if not os.path.isfile(os.path.join(folder, main_file)): fail(label, f"missing {main_file}")
    log = os.path.join(folder, "CHANGELOG.md")
    if not os.path.isfile(log) or f"## [{m.get('version')}]" not in open(log).read(): fail(label, f"CHANGELOG.md needs a section \"## [{m.get('version')}]\"")
    media = os.path.join(folder, "media")
    shots = os.listdir(media) if os.path.isdir(media) else []
    if not shots: fail(label, "media/: add at least one screenshot (PNG or JPEG)")
    for f in shots:
        if os.path.getsize(os.path.join(media, f)) > 600_000: fail(label, f"media/{f} is over 600 KB")

    found, bad = store_items.scan(folder)
    if official:
        if f"\n  {m.get('target')}:" not in project: fail(label, f"project.yml has no target \"{m.get('target')}\"")
        continue

    # --- Community items: made by someone else, so everything has to be visible to the reviewer ---
    pub = m.get("publisher") or {}
    if not pub.get("name") or not pub.get("github"): fail(label, "publisher: {\"name\": ..., \"github\": ...} is required: the store shows who made it")
    if re.search(r"notcholino", " ".join([str(m.get("name", "")), str(m.get("id", "")), str(pub.get("name", "")), str(m.get("author", ""))]), re.I):
        fail(label, "the name of the project is reserved for what the project itself makes: choose a name without it")
    if m.get("official"): fail(label, "\"official\" is set by the store, not by the item")
    if not m.get("principalClass"): fail(label, "principalClass: the @objc name of your principal class")
    for f in ("project.yml",):
        if os.path.isfile(os.path.join(folder, f)): fail(label, f"{f} is not allowed here: the build target is generated")
    declared = set(m.get("capabilities") or [])
    unknown = declared - set(store_items.CAPABILITIES)
    if unknown: fail(label, f"unknown capabilities {sorted(unknown)}; choose from {sorted(store_items.CAPABILITIES)}")
    for cap in found:
        if cap not in declared: fail(label, f"the source uses something that needs \"{cap}\" but plugin.json does not declare it in \"capabilities\"")
    for cap in declared - set(found):
        fail(label, f"\"{cap}\" is declared but the source does not use it: declare only what it does")
    for why in bad: fail(label, f"not allowed in community code: it {why}")
    for f in os.listdir(folder):
        p = os.path.join(folder, f)
        if os.path.islink(p): fail(label, f"{f} is a link: not allowed")
        if os.path.isfile(p) and f.endswith((".sh", ".py", ".rb", ".pl", ".command", ".dylib", ".a", ".so", ".framework")): fail(label, f"{f}: no scripts or binaries, only Swift source")
    for dirpath, _, files in os.walk(folder):
        for f in files:
            if f.endswith((".dylib", ".a", ".so", ".o")) or (os.access(os.path.join(dirpath, f), os.X_OK) and not f.endswith((".swift", ".md", ".json", ".png", ".jpg", ".jpeg", ".webp"))):
                fail(label, f"{os.path.relpath(os.path.join(dirpath, f), folder)}: binaries and executable files are not allowed")

# The generated targets of the community items must be the ones in the repository
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_community_targets
if gen_community_targets.render() != targets:
    fail("community/targets.yml", "is out of date: run python3 scripts/gen_community_targets.py and commit it")

print()
if errors:
    print(f"{len(errors)} problem(s)"); sys.exit(1)
print(f"{count} plugins and extensions checked: all good")
