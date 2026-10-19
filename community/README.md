# Community plugins and extensions

Anyone can make a plugin or an extension and have it listed in the Notcholino store **under their own name**. The ones made by
the project itself are marked **Notcholino** with a blue check; yours say **by <your name>** and carry a "Made by the community"
notice. Nobody else can use the name of the project.

## How it stays safe

A plugin or an extension runs *inside* Notcholino, with the app's permissions. So nothing reaches a user's Mac unless:

1. **Its source is reviewed.** You open a pull request that adds a folder here. The maintainer reads the code before merging (the
   pull request may only touch `community/`, a bot enforces it).
2. **It is built by the project, not by you.** The binary is built by the project's own workflow from the merged source and
   published on its releases. You never upload a binary, and nothing you write runs at build time: the build target is generated
   from your `plugin.json`, so there are no build scripts, no dependencies and no build settings to hide anything in.
3. **What it can do is visible.** A script reads your source and finds what it uses (network, running commands, AppleScript,
   files, Keychain, accessibility, microphone, camera, screen, and a few more). You declare it in `capabilities`, the check fails
   if the source does something you did not declare or declares what it does not do, and the store shows it to the user before
   they install. Loading code from elsewhere, swapping the app's methods and running a script you carry are not allowed.
4. **What is downloaded is what was built.** The store lists the SHA-256 of each build, the app checks it after the download,
   and for extensions it checks the installed files again every time they are loaded.
5. **Updates are reviewed too.** A new version is a new pull request, and a new tag from the maintainer.

This makes a malicious submission hard, not impossible: a reviewer can miss something. That is why the store says who made each
thing and what it can do, and why the user is asked before installing.

## Adding yours

1. Fork the repository and create `community/plugins/<id>/` (or `community/extensions/<id>/`). `<id>` is 2 to 24 lowercase
   letters and digits.
2. Put in it:
   - `plugin.json`: like the official ones (see `plugins/*/plugin.json`), plus
     `"publisher": {"name": "Your Name", "github": "yourhandle"}`, `"principalClass"` (the `@objc` name of your class),
     `"capabilities": [...]`, and for an extension `"kind": "extension"` and `"apiVersion": 1`.
   - `<Target>Plugin.swift` (or `<Target>Extension.swift`): your code. Plugins follow [plugins/GUIDE.md](../plugins/GUIDE.md),
     extensions [extensions/GUIDE.md](../extensions/GUIDE.md).
   - `CHANGELOG.md` with a section for your version, and one or more screenshots in `media/`.
3. Run `python3 scripts/gen_community_targets.py` (it writes `community/targets.yml`) and `python3 scripts/check_plugins.py`.
4. Test it on your Mac (`scripts/dev-plugin.sh` for plugins, `scripts/dev-extension.sh` for extensions).
5. Open the pull request. Only files under `community/` may change.

When it is merged, the maintainer tags `<id>-v<version>`, the workflow builds and publishes it, and it appears in the store.

## What the reviewer looks for

- The code does what `details` says, and only that.
- Every capability declared is needed, and nothing hidden behind generic names.
- No data leaves the Mac that the text does not say.
- It does not imitate the project, another maker, or a system dialog.
- It stops cleanly (`pluginWillUnload` / `extensionWillUnload`) and does not leave anything behind (as `pmset` did once).
