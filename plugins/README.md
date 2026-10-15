# Notcholino plugins

Plugins are small compiled bundles (`.bundle`) that add buttons to the **Control Center** panel of the notch. They live in this folder, one subfolder per plugin, and are released from this same repository.

| Plugin | What it does |
| --- | --- |
| [Espresso](espresso) | Keeps your Mac and its screen awake, indefinitely or for a set time. |
| [Scrolly](scrolly) | A switch that reverses the vertical scroll of your mouse wheel, without touching the trackpad. |
| [Hotter](hotter) | The temperature of your Mac as the button itself, from green to red, with a small graph. Apple silicon only. |
| [CloseMe](closeme) | *Experimental.* Keeps the Mac running with the lid closed, with the screen off. Asks for your administrator password. |
| [BatLife](batlife) | Battery level as the button, with health, cycles, power and time left. |
| [Tomato](tomato) | A Pomodoro timer with work and break minutes of your choice, a small clock under the notch and a sound. |
| [Dusty](dusty) | Clean mode: black screen and a locked keyboard and trackpad for 5 to 60 seconds. ⌘⇧C ends it. |
| [Clippy](clippy) | The last 10 things you copied, to copy again with a click. Kept in memory only. |
| [Watcher](watcher) | No button: an icon beside the notch while the microphone or the camera is in use, and a popup when it starts. |
| [Pinger](pinger) | The latency of your connection as the button, with a graph and the VPN state. |
| [Picker](picker) | Pick a color from the screen and copy it as HEX, RGB or HSL. |
| [Reader](reader) | Drag over any text on the screen and it is copied to the clipboard. |
| [Devices](devices) | The battery of your AirPods, mouse, keyboard and other Bluetooth devices. |
| [Quicky](quicky) | Lock the screen, turn the display off or start the screen saver. |
| [Tidy](tidy) | Hide the icons on your Desktop with one click. |

New to this? Follow [the guide](GUIDE.md): you can have a plugin on your notch in ten minutes. Looking for an idea? See [IDEAS.md](IDEAS.md).

## Installing a plugin

Open **Settings → Control Center → Plugin Store**, pick a plugin and click **Install**. Notcholino shows who made it, downloads the latest release from this repository, verifies its SHA-256 checksum and loads it. Plugins run inside the app with the same permissions as Notcholino, so only install ones you trust.

## Writing a plugin

A plugin is a class that conforms to `NotcholinoPlugin`, defined in [`Shared/NotcholinoPluginAPI.swift`](../Shared/NotcholinoPluginAPI.swift). That file is compiled into the app and into every plugin. The plugin describes itself (name, icon, state) and returns a **declarative menu**: Notcholino draws it in the notch, the plugin only reacts to `performMenuAction(_:)`. See [`espresso/EspressoPlugin.swift`](espresso/EspressoPlugin.swift) for a complete example.

A plugin can also make its button richer (since Notcholino 0.8.0, set `minAppVersion` in `plugin.json` when you use these): `controlCenterLabel` draws a short text such as `42°` instead of the symbol, `controlCenterTintColor` sets the button's color, `controlCenterButtonTapped()` turns the button into a plain switch, a menu entry with a `graph` shows a small line graph, and (since Notcholino 0.10.0) a `stepper` entry is a number with minus and plus buttons that repeat while held; the new value comes back as `performMenuAction("<id>=<value>")`. [Hotter](hotter), [BatLife](batlife), [Scrolly](scrolly) and [Tomato](tomato) use them. Every button in the Control Center has the same size and a single label, its name: a plugin's state goes in `statusText`, shown when its options are open.
A menu entry with `info` and `value` adds a read-only row.

Since Notcholino 0.11.0 a plugin can also reach out of the Control Center (set `minAppVersion` to `0.11.0` when you use these):

- `setPopupHandler(_:)` gives the plugin a function to call whenever it has something to say: it shows a small popup under the closed notch with a `title`, an optional `subtitle`, an SF Symbol `icon`, a `color` and the number of `seconds`. [Picker](picker) and [Reader](reader) use it to say what they copied.
- `notchSideIcon` and `notchSideIconColor` draw an SF Symbol beside the closed notch while the name isn't empty. [Watcher](watcher) uses it while the microphone or the camera is on.
- `controlCenterHidden` removes the plugin's button, for one that only uses popups and icons.
- A menu entry can have `"wide": true` to take a whole row instead of a small chip, for longer text. [Clippy](clippy) uses it.

To add one, the quickest way is `scripts/new-plugin.sh <id> <Name>`, which creates all of this for you (see [the guide](GUIDE.md)). By hand:

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
