# Your first plugin in ten minutes

A Notcholino plugin is one Swift class in a small bundle. Notcholino loads it, draws its button in the Control Center, and shows the options the plugin describes. You write what it does; you never write any interface.

You need a Mac with macOS 14 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## 1. Get the code and create the plugin

```sh
git clone https://github.com/Peppe37/Notcholino.git
cd Notcholino
scripts/new-plugin.sh hello Hello "Says hello from the notch"
```

This creates `plugins/hello/` with a working example, a `plugin.json`, a `CHANGELOG.md`, and adds a `Hello` target to `project.yml`. (`hello` is the id, used for the folder and the release tag; `Hello` is the name on the button.)

## 2. Read the example

Open `plugins/hello/HelloPlugin.swift`. It has four parts:

| Part | What it is |
| --- | --- |
| **About the plugin** | Name, version, author and description, shown in the store and in Settings. |
| **The button** | `controlCenterIcon` (an [SF Symbol](https://developer.apple.com/sf-symbols/)), `isActive` (lights it up), and optionally `controlCenterLabel` (a short text like `42°` in place of the symbol) and `controlCenterTintColor` (`"#RRGGBB"`). |
| **The options** | `menuItems()` returns what opens when you click the button, as plain dictionaries. |
| **The reaction** | `performMenuAction(_:)` is called with the `id` of the option that was chosen. |

The state you show goes in `statusText`; every button has the same size and a single label, its name.

## 3. Try it

```sh
scripts/dev-plugin.sh Hello
```

It builds the plugin and copies it to `~/Library/Application Support/Notcholino/Plugins`. Quit and reopen Notcholino (a plugin that is already loaded is not reloaded), open the Control Center page of the notch, and click the new button.

To try a plugin without the app (to see what it would show and to run its actions from a terminal):

```sh
swiftc -parse-as-library -o /tmp/plugin-harness scripts/plugin-harness.swift Shared/NotcholinoPluginAPI.swift
/tmp/plugin-harness /path/to/Hello.bundle one two
```

## 4. What the options can be

Each entry of `menuItems()` is a dictionary. Pick the keys you need:

| You write | You get |
| --- | --- |
| `["id": "x", "title": "Do x"]` | A button. Optional: `"checked": true` highlights it, `"destructive": true` makes it red, `"wide": true` gives it a whole row for longer text. |
| `["header": "Title"]` | A small section title. |
| `["info": "Battery", "value": "82 %"]` | A read-only row, label on the left and value on the right. |
| `["graph": [1, 2, 3], "caption": "Last minutes", "color": "#30D158"]` | A small line graph. |
| `["stepper": "Work", "id": "work", "value": 25, "unit": "min", "min": 1, "max": 180]` | A number with minus and plus (hold to repeat). You get `performMenuAction("work=26")`. |

More things a plugin can do:

- **A plain switch.** Implement `controlCenterButtonTapped()` and a click on the button calls it instead of opening options. ([Tidy](tidy), [Scrolly](scrolly))
- **A popup under the closed notch.** Keep the function from `setPopupHandler(_:)` and call it with `["title": "...", "subtitle": "...", "icon": "bolt.fill", "color": "#30D158", "seconds": 3]`. ([Picker](picker), [Reader](reader))
- **An icon beside the notch.** `notchSideIcon` and `notchSideIconColor`, read about once a second. ([Watcher](watcher))
- **No button at all.** `controlCenterHidden` returns `true`, for a plugin that only uses popups and icons.
- **Clean up.** `pluginWillUnload()` is called when the plugin is removed: stop timers and release what you hold.

When you use something added after 0.8.0, set `minAppVersion` in `plugin.json`, so the store tells people with an older app to update. The full list, with the version each thing arrived in, is in [`Shared/NotcholinoPluginAPI.swift`](../Shared/NotcholinoPluginAPI.swift).

## 5. Habits of a good plugin

- **Never wait on the main thread.** Your code runs inside the app: a system call that waits (a permission, the network, a process) freezes the notch for everyone. Do slow work on a background queue and keep the result in a property. (Notcholino itself froze once on exactly this.)
- **Be quiet when idle.** A timer that fires once a second keeps the Mac from resting. Use the slowest interval that feels right, and none when nothing is happening.
- **Keep data local.** Nothing leaves the Mac unless the user asked for it. Say clearly in the plugin's description what it reads.
- **Permissions belong to the app.** A plugin runs with Notcholino's permissions. If you need one the app doesn't declare yet (a new usage description), open an issue first.

## 6. Make its store page

The Plugin Store shows each plugin as a card in a grid and, when you open it, a page with pictures and text. Everything on it comes from files in your plugin's folder, so there is no form to fill in:

| Where | What it shows |
| --- | --- |
| `plugin.json` → `description` | The one line on the card (under 140 characters) |
| `plugin.json` → `category` | The shelf: System, Productivity, Utilities, Network, Privacy, Media or Fun |
| `plugin.json` → `tags` | The words the store search looks for (at least 3, lowercase): think of what a person would type to find it, such as `battery`, `clipboard`, `timer` |
| `plugin.json` → `details` | The paragraph on the page |
| `plugin.json` → `features` | The "What it does" list (2 to 5 short points) |
| `plugin.json` → `permissions` | "What it needs": say it plainly, even if it is "No permission needed." |
| `CHANGELOG.md` | "What's new": the section of the current version |
| `media/` | The pictures, in alphabetical order (PNG or JPEG, under 600 KB each). Take them in the notch: the Control Center with your button, and its options |
| `plugin.json` → `video` | Optional: a link to a short video |

`python3 scripts/check_plugins.py` checks all of it, and so does the pull request.

## 7. Share it

1. Make sure `plugin.json` is right (`version`, `minAppVersion`, `icon`, and the store fields above) and `CHANGELOG.md` has a section for the version.
2. Run `python3 scripts/check_plugins.py`.
3. Open a pull request that adds `plugins/<id>/` and the target in `project.yml`. Say what the plugin does and which Macs it was tried on.
4. Once it is merged, a release tagged `<id>-v<version>` builds it, publishes it and adds it to the in-app store (see [Releasing a plugin](README.md#releasing-a-plugin)). The store only installs plugins from this repository's releases, and checks their checksum.

Plugins live in the same repository as the app, so they are under the same license, the [GPL-3.0](../LICENSE). By sending one you agree to that.

Looking for something to build? See [IDEAS.md](IDEAS.md).
