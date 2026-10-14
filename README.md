<p align="center">
  <img src="docs/assets/icon.png" width="112" alt="Notcholino logo">
</p>

<h1 align="center">Notcholino</h1>

<p align="center">
  A living Notch for macOS.<br>
  Turn the notch of your MacBook into a dynamic hub for music, calendar and system feedback.
</p>

<p align="center">
  <a href="https://github.com/Peppe37/Notcholino/releases"><img alt="Latest release" src="https://img.shields.io/github/v/release/Peppe37/Notcholino?include_prereleases&label=release"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-blue">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI-orange">
  <a href="LICENSE"><img alt="License: PolyForm Noncommercial" src="https://img.shields.io/badge/license-PolyForm%20Noncommercial-lightgrey"></a>
  <a href="https://peppe37.github.io/Notcholino/"><img alt="Website" src="https://img.shields.io/badge/website-live-brightgreen"></a>
</p>

<p align="center">
  <a href="https://peppe37.github.io/Notcholino/">Website</a> ·
  <a href="https://github.com/Peppe37/Notcholino/releases">Download</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="https://github.com/Peppe37/Notcholino/issues">Report an issue</a>
</p>

---

> **Status: alpha.** Notcholino is in early development. Expect rough edges and breaking changes between versions.

## What is it?

Notcholino is a free, open-source and non-commercial app that extends the hardware notch of your MacBook with a fluid overlay. It stays out of the way as a small pill, and expands when you hover it to show what matters: what is playing, what is on your calendar, and the volume and brightness you are changing.

## Features

**Available now**

- **Dynamic notch**: a native overlay that blends with the hardware notch and expands on hover. Works on the main display or on all displays.
- **Now Playing**: control Spotify and Apple Music from the notch. Album art, scrubbable progress bar, seek, shuffle and repeat, an animated waveform, and colors extracted from the artwork. Click the song to bring the player to the front.
- **Compact music mode**: while music plays, the collapsed notch shows the album art and a live waveform.
- **Spotify Like**: connect your account once (OAuth with PKCE) to like the current song from the notch.
- **Calendar**: today's date, the next event with its calendar color and location, and a month view. Pick which calendars to show, and click an event to open it in Calendar.
- **System HUDs**: volume and brightness feedback in the notch, replacing the native macOS HUD, with theme, label and decibel options.
- **Control Center and plugins**: a third panel in the notch holds plugin buttons. Tap one to open its options right inside the notch. Install, update and remove plugins from **Settings → Control Center → Plugin Store**: they are downloaded from this repository's releases, always at their latest version, after you confirm and a SHA-256 check.
- **Espresso** (first plugin): keeps your Mac and its screen awake, indefinitely or for 10 minutes up to 12 hours, or until a time you pick. See [plugins](plugins).
- **Native settings**: a System Settings–style preferences window built with SwiftUI, plus launch at login.
- **Gestures**: scroll or swipe horizontally to switch between tabs.

**Coming soon**

- Battery, connectivity, Focus and lock-screen notifications (the settings exist, the live activities are not wired yet).
- More plugins, and a guide for writing your own (see [plugins](plugins)).
- Raycast integration.
- Signed and notarized builds.

## Install

**Requirements:** macOS 14 Sonoma or later.

1. Download `Notcholino-<version>.dmg` from the [Releases page](https://github.com/Peppe37/Notcholino/releases).
2. Open the DMG and drag **Notcholino** to **Applications**.
3. Launch it. macOS will block it the first time, see below.

### First launch: allowing the app

Notcholino is not notarized by Apple yet (that requires a paid developer account), so macOS says it cannot verify the app. This is expected. To open it:

1. Open **Notcholino** from Applications. When the warning appears, click **Done** (not "Move to Trash").
2. Open **System Settings → Privacy & Security**.
3. Scroll to the **Security** section, find "Notcholino.app was blocked" and click **Open Anyway**.
4. Confirm with your password or Touch ID, then click **Open**. You only need to do this once.

Prefer the Terminal? This does the same thing by removing the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/Notcholino.app
```

The code is fully open source, and the release is built by GitHub Actions from the tagged source. If you would rather not trust a prebuilt binary, [build it yourself](#building-from-source).

### Permissions

Notcholino asks for what it needs, when it needs it:

| Permission | Why |
| --- | --- |
| **Automation** (Apple Events) | To read and control Spotify and Apple Music. |
| **Calendars** | To show your upcoming events. |

Spotify Like uses your Spotify account through the official Web API, and only if you click **Connect** in the settings.

## Usage

- **Hover** the notch to expand it, move away to collapse it.
- **Scroll or swipe** horizontally to switch between Control Center, Now Playing and Calendar, or click the dots at the top.
- **Click the song info** to open the active music player. **Click an event or a day** to open it in Calendar.
- Use the **menu bar icon → Preferences…** (or <kbd>⌘</kbd><kbd>,</kbd>) to open the settings and quit the app.

## Performance

Notcholino is meant to stay out of your way. These figures were measured on a MacBook Pro with an Apple M5 and macOS 26.6, with a Release build, averaged over 30 seconds per scenario, with no music player open.

| | Idle (notch closed) | Open (hovering) |
| --- | --- | --- |
| **Memory** (physical footprint) | 42 MB | 44 MB |
| **CPU** | 0.00 % | 0.01 % |
| **Energy impact** (Activity Monitor scale) | 0.00 | 0.02 |
| **Idle wakeups per second** | 0.0 | 0.0 |

- **Peak memory** is about 87 MB, only while the app starts.
- **Disk**: the app is 2.5 MB, the DMG 1.7 MB. The [Espresso](plugins/espresso) plugin is 120 KB (a 21 KB download). Nothing else is stored except the plugins you install.
- **Espresso** adds about 1.5 MB of memory while it is on and no measurable CPU or energy. It holds two power assertions so the Mac and its screen stay awake: the extra power comes from the screen staying on, not from the plugin.
- **With a player open**, Notcholino reads Spotify or Music with a short AppleScript (about 28 ms of CPU each): every 3 seconds while playing, every 8 seconds while paused, plus right away when the player reports a change. With no player open it asks nothing.
- **Temperature and GPU**: Notcholino only draws a small SwiftUI overlay, with no compute or Metal work of its own, and the thermal state stayed nominal. Per-process temperature and GPU time need root: run `sudo powermetrics --samplers cpu_power,gpu_power,thermal -i 1000 -n 10` to see them on your Mac.

Version 0.4.0 cut this down: before, the app started an `osascript` process every 2 seconds even with no player open, and scanned every running process once a second to hide the system volume HUD. Measured the same way, 0.3.0 used 0.15 % CPU and energy impact 0.17 when idle, plus about 1.4 % of a core in short-lived `osascript` processes that do not show up in the app's own numbers.

To measure on your own Mac (no `sudo` needed):

```sh
scripts/benchmark.sh /path/to/Notcholino.app 30
```

## Building from source

You need a recent Xcode (the releases are built with Xcode 26) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
git clone https://github.com/Peppe37/Notcholino.git
cd Notcholino
xcodegen generate
open Notcholino.xcodeproj
```

The Xcode project is generated from `project.yml` and is not committed. Build and run the **Notcholino** scheme.

## Releases and versioning

Notcholino follows [Semantic Versioning](https://semver.org/) and keeps a [Keep a Changelog](https://keepachangelog.com/) style [CHANGELOG](CHANGELOG.md).

Pushing a tag like `v0.1.0-alpha` triggers the release workflow: it checks the tag against the version in `project.yml`, builds the app, packages a DMG and publishes a GitHub release (marked as pre-release when the tag has a suffix) using the changelog entry as notes. The website is deployed to GitHub Pages from the `docs/` folder.

Plugins are versioned and released on their own, from tags named `<plugin>-v<version>` (for example `espresso-v0.1.0-alpha`). The plugin release workflow publishes the release and refreshes the plugin store manifest. See [plugins](plugins) for details.

## License

Notcholino is released under the **PolyForm Noncommercial 1.0.0** license.

- You **can** download, modify, fork and use Notcholino for free.
- You **cannot** use it for commercial purposes or sell it.

See the [LICENSE](LICENSE) file for details.
