# Notcholino plugins

Plugins are small compiled bundles (`.bundle`) that add buttons to the **Control Center** panel of the notch. They live in this folder, one subfolder per plugin, and are released from this same repository.

| Plugin | What it does |
| --- | --- |
| [Espresso](espresso) | Keeps your Mac and its screen awake, indefinitely or for a set time. |
| [Scrolly](scrolly) | A switch that reverses the vertical scroll of your mouse wheel, without touching the trackpad. |
| [Hotter](hotter) | The temperature of your Mac as the button itself, from green to red, with a small graph. Apple silicon only. |
| [CloseMe](closeme) | *Experimental, not released yet.* Keeps the Mac running with the lid closed, with the screen off. |

## Installing a plugin

Open **Settings → Control Center → Plugin Store**, pick a plugin and click **Install**. Notcholino shows who made it, downloads the latest release from this repository, verifies its SHA-256 checksum and loads it. Plugins run inside the app with the same permissions as Notcholino, so only install ones you trust.

## Writing a plugin

A plugin is a class that conforms to `NotcholinoPlugin`, defined in [`Shared/NotcholinoPluginAPI.swift`](../Shared/NotcholinoPluginAPI.swift). That file is compiled into the app and into every plugin. The plugin describes itself (name, icon, state) and returns a **declarative menu**: Notcholino draws it in the notch, the plugin only reacts to `performMenuAction(_:)`. See [`espresso/EspressoPlugin.swift`](espresso/EspressoPlugin.swift) for a complete example.

A plugin can also make its button richer (since Notcholino 0.8.0, set `minAppVersion` in `plugin.json` when you use these): `controlCenterLabel` draws a short text such as `42°` instead of the symbol, `controlCenterTintColor` sets the button's color, `controlCenterButtonTapped()` turns the button into a plain switch, and a menu entry with a `graph` shows a small line graph. [Hotter](hotter) and [Scrolly](scrolly) use them.

To add one:

1. Create `plugins/<id>/` with your Swift source, a `plugin.json` and a `CHANGELOG.md`:
   ```json
   {
     "id": "espresso",
     "target": "Espresso",
     "name": "Espresso",
     "description": "Keep your Mac and its screen awake, indefinitely or for a set time.",
     "author": "Giuseppe",
     "icon": "cup.and.saucer.fill",
     "version": "0.1.0-alpha",
     "apiVersion": 1
   }
   ```
2. Add a `bundle` target to `project.yml` (copy the `Espresso` one), with the principal class set through `INFOPLIST_KEY_NSPrincipalClass`.
3. Run `xcodegen generate`, build the scheme, and drop the resulting `.bundle` into `~/Library/Application Support/Notcholino/Plugins/` to try it.

## Releasing a plugin

Plugins have their own versions and releases. Push a tag named `<id>-v<version>`:

```sh
git tag -a espresso-v0.1.0-alpha -m "Espresso 0.1.0-alpha"
git push origin espresso-v0.1.0-alpha
```

The *Plugin release* workflow checks the tag against `plugin.json` and the built bundle, packages it as a zip and publishes a GitHub release using the matching section of the plugin's `CHANGELOG.md`. It then regenerates the store manifest (`plugins.json` on the website), which always points to each plugin's latest release.
