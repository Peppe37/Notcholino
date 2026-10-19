# Changelog

All notable changes to Notcholino are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.18.0-alpha] - 2026-10-19

### Added
- When Notchy says something under the notch (what it saw in an image, a summary, an error), moving the pointer to the notch now opens Notchy's page with the whole note, instead of the page you had open.
- **Answer in**: pick the language Notchy replies in (Settings → Notchy), or leave it on the language of the text it was sent.

## [0.17.3-alpha] - 2026-10-19

### Fixed
- "Send to Notchy" was still missing from the right-click menu (Services): macOS needs the service to say it is unrestricted and has no required context. Now it appears for selected text and for files in Finder.

## [0.17.2-alpha] - 2026-10-19

### Fixed
- "Send to Notchy" now shows up in Finder's right-click menu for files (text, code, notes, PDFs and images): it declared the wrong kind of input before.

## [0.17.1-alpha] - 2026-10-19

### Fixed
- While Settings (or any normal window) is open, Notcholino now shows in the Dock and in Cmd-Tab, so you can switch back to it. It disappears again when the last window closes.

## [0.17.0-alpha] - 2026-10-19

### Added
- **Send to Notchy**: select text anywhere, or a file in Finder, right-click → Services → Send to Notchy. Notchy reads it and answers in a short note under the notch (and in its page): a summary or outline for text, notes, code and PDFs, a description for images, or an answer if you sent a question. The cube turns thoughtful while it works.
- A **Test** button for every task (text, images, voice) in Settings → Notchy: text asks for one word, images sends a tiny red square and checks the answer, voice checks the key and the model.
- A **refresh** button beside the model that asks the provider which models it really has, filtered to what can do that task.

### Changed
- Providers are only offered for what they can do: Anthropic and Ollama for text and images, Gemini and OpenAI for all three, ElevenLabs and macOS for voice, vLLM for text and images.
- Models are chosen from a short list that fits the task and the provider (Gemini now defaults to the `-latest` aliases, so it follows the current model; OpenAI uses a transcription model for voice), with "Other…" for any name.
- A busy provider (503/429) now says so and suggests another model, instead of a raw error.

## [0.16.0-alpha] - 2026-10-19

### Added
- **Notchy**, the first extension (extensions are bigger than plugins: they can have their own page, their own settings and use AI). A small glass cube that lives in the notch, with black eyes and moods that change its glow. It is off by default: turn it on in **Settings → Notchy**.
- A hidable Notchy page in the notch, and a cube that peeks out beside the notch now and then or when you have been in one app for a long time. Three levels: Silent, Normal (default) and Lively. The rules run on your Mac, with coarse timers and no AI.
- **Settings → Notchy**: pick a provider and model for text, for images and screen, and for voice-to-text, from Anthropic, Gemini, OpenAI, Ollama and vLLM (local or remote). Keys are kept only in the macOS Keychain and read only when you use Notchy, and each provider has a Test button.
- Coming next: Send to Notchy from the right-click menu, file summaries, day planning, and email and voice.

## [0.15.1-alpha] - 2026-10-17

### Added
- **Known problems in the store.** A plugin can carry a `warning` in `plugin.json`: it shows in orange on its card ("Known problem") and at the top of its page, with how to get out of it.
- CloseMe 0.2.0 and earlier are marked with one: they could leave the Mac unable to sleep (SleepDisabled) after being turned off. The fix, `sudo pmset -a disablesleep 0`, is in the warning and in the CloseMe options.

## [0.15.0-alpha] - 2026-10-16

### Added
- **The Plugin Store is a grid, with search.** It has its own page in the settings: cards with a big icon, the name, a line about the plugin and **Get / Update / Installed**, shelves by category, and a search field that looks at names, descriptions, what a plugin does and its **keywords** (`tags` in `plugin.json`). Clicking a card opens the plugin's page. The installed plugins (order, remove) stay in **Control Center**.
- **For plugin authors:** `category` and `tags` in `plugin.json`, a store-page section in `plugins/GUIDE.md`, a template in `scripts/new-plugin.sh` that already has all the store fields, and `scripts/check_plugins.py` (also run on every pull request) that checks them.

### Changed
- **Icons now live inside the black of the notch.** The moon and the icons of plugins such as Watcher (microphone, camera) used to sit outside it, on the menu bar. The closed notch now widens to hold them, as it does for the album art and the waveform, and the icons sit beside the hardware notch.

## [0.14.1-alpha] - 2026-10-16

### Added
- **Plugin updates in one place.** The store says how many updates there are and **Update all** installs them all with one question at the start and a single restart at the end. The menu bar menu shows "Plugin updates available" when there is one. The list is read once at launch and once a day (the same switch as the update notice: **Settings → About → Check for new versions**).

## [0.14.0-alpha] - 2026-10-16

### Added
- **A real plugin store.** Each plugin has its own page, opened by clicking its row in **Settings → Control Center**: screenshots, a longer description, what it does, what it needs (permissions) and what is new in its latest version, with **Get**, **Update** and **Installed** in the same place. The pages are built from `plugin.json`, the plugin's `CHANGELOG.md` and the pictures in `plugins/<id>/media`, so a plugin author only edits those files.

### Changed
- **Updating a plugin no longer needs a manual restart.** After an update the app asks "Restart now?" and reopens itself in a second, with everything as it was (two copies of one plugin's code can't live together in a running app, so a restart is the only safe way to load the new one).

## [0.13.6-alpha] - 2026-10-16

### Fixed
- **No more Keychain password question at launch.** Spotify's token is stored in the old file-based Keychain, which asks for the login password when the item was made by a build with another signature, and ignores the setting meant to prevent it. Notcholino now switches the Keychain's user interaction off for its background reads, so they fail quietly; the question only appears when you click Like.

## [0.13.5-alpha] - 2026-10-16

### Changed
- The drawn notch is 4 pt wider than the gap macOS leaves in the menu bar (189 pt on a 14" MacBook Pro): the black of the real notch is a little wider than that gap, and the drawn one now covers it.
- **Settings → General → Notch Size Tuning** shows a sample strip under the notch while you move the sliders, so you can match the drawn notch to the real one by eye, and has a **Reset** button. 0 is the measured size.

## [0.13.4-alpha] - 2026-10-16

### Fixed
- **The notch is now as wide as the real one.** The closed notch, and the strip that grows under it for popups and Tomato's countdown, were drawn 162 pt wide while the hardware notch of a 14" MacBook Pro is 185 pt: the strip looked narrower than the notch above it. Notcholino now measures the hardware notch of each screen and uses its width. (Screenshots don't show the hardware notch, which is why they looked right.)
- **Keychain questions can no longer freeze the app.** Reading Spotify's token from the Keychain could wait for the login password on the main thread, with the whole notch (popups included) stuck behind it. Every Keychain call now runs in the background.

## [0.13.3-alpha] - 2026-10-16

### Fixed
- Bluetooth popups: "Disconnected" is only shown if the device is really disconnected a moment later (a device that drops and returns at once, or a late notification, no longer says it), and the same news is never shown twice in a few seconds. Each device now keeps a single disconnect notification instead of piling them up.

## [0.13.2-alpha] - 2026-10-15

### Fixed
- The strip under the closed notch (popups, Tomato's countdown) is now **exactly as wide as the notch**, and follows it when it is wider (while music plays, for instance). A long text shrinks and is cut to fit: the notch no longer widens for it.

## [0.13.1-alpha] - 2026-10-15

### Fixed
- **Leaving the Mac as if Notcholino had never run.** Whatever way the app ends (⌘Q, logout, an update, `kill`, a plugin removed), every plugin now gets to undo what it did: a plain `kill` used to end the app without any cleanup.
- **CloseMe could leave `SleepDisabled` on** (the Sleep item greyed out, the lid not putting the Mac to sleep, an external display kept on with the lid closed). It is fixed in CloseMe 0.2.0, which only changes the setting when it was off, gives back what it found, installs a one-shot job that undoes it at boot, and offers **Restore sleep** if something is still left over after a crash. Espresso was checked and does not use that setting: it only holds power assertions, which end with the process.
- Tidy (hide the Desktop icons) brings the icons back when Notcholino quits, and after a crash.

## [0.13.0-alpha] - 2026-10-15

### Changed
- **Popups come out of the notch**: a popup (AirPods, charger, disk, or a plugin's) is now part of the notch itself, which grows a strip as wide as the notch, instead of a separate tab hanging under it.
- Plugins can make the closed notch grow a strip too, for a countdown (`notchExtensionText`). Tomato uses it, so its clock is the same width as the notch.
- The moon and the plugins' side icons now sit right next to the notch row and stay there when a strip grows. The Focus status is checked every 2 seconds, and Settings says when macOS is not sharing it.

### Fixed
- Spotify's Keychain item could make macOS ask for the login password at launch when it had been made by a build with another signature. Notcholino now reads it quietly in the background and only lets macOS ask when you click Like.

## [0.12.0-alpha] - 2026-10-15

### Added
- **Homebrew**: `brew install --cask Peppe37/tap/notcholino`, from the new [tap](https://github.com/Peppe37/homebrew-tap), which follows every release by itself and opens the app without the first-launch warning.
- **Plugin tools**: a step-by-step guide (`plugins/GUIDE.md`), `scripts/new-plugin.sh` to create a plugin and its project target in one command, `scripts/dev-plugin.sh` to build and install it, `scripts/plugin-harness.swift` to try it without the app, and a list of ideas (`plugins/IDEAS.md`).

### Changed
- **License: from PolyForm Noncommercial 1.0.0 to the GNU GPL v3.0.** Notcholino is now really open source: you can use, study, modify and share it, and a modified version that is shared has to stay GPL-3.0 with its source. Versions up to 0.11.x keep the license they were released with.

## [0.11.0-alpha] - 2026-10-15

### Added
- **Shelf**: drag a screenshot, a recording or any file toward the notch and it opens on the Shelf, which keeps its own copy (nothing is saved on the Desktop). Drag the file out again whenever you like. The page sits between Control Center and Now Playing and only shows while it holds something. **Settings → Shelf** sets how long files stay: until you remove them (the default), 24 hours, or until restart.
- **Device popups**: a small message under the closed notch when a Bluetooth device connects or disconnects (AirPods and others, with the battery when macOS says it), when the charger is plugged in or removed, and when a disk is connected or ejected. Each can be switched off in **Settings → Devices**. Bluetooth needs your permission, asked there.
- **Do Not Disturb**: a moon beside the closed notch while a Focus is on (macOS says whether, not which). Needs a permission, asked in **Settings → Devices**.
- **Join** button on calendar events that have a Zoom, Meet, Teams, Webex, Whereby or Jitsi link, green from ten minutes before the start.
- Plugins can show a popup under the closed notch, draw an icon beside it, have no button at all, and have options that take a whole row: see `plugins/README.md`.
- Eight new plugins, released on their own: **Clippy** (clipboard history), **Watcher** (microphone and camera in use), **Pinger** (connection latency), **Picker** (color picker), **Reader** (copy text from the screen), **Devices** (Bluetooth device batteries), **Quicky** (lock, display off, screen saver) and **Tidy** (hide Desktop icons).

## [0.10.1-alpha] - 2026-10-14

### Fixed
- The app could freeze completely, notch and Settings window together, right after an update that changed the app's signature. Checking whether Notcholino may control Spotify or Music waited for the system on the main thread, and the system sometimes never answered. The check now runs in the background and never holds up the app.

### Added
- An update notice: once a day (and never more often) Notcholino makes one small request to GitHub for the list of releases and, if there is a newer version, shows "Update available" in the menu bar menu and in **Settings → About**. It never downloads or installs anything by itself. You can switch it off in **Settings → About → Check for new versions**.

## [0.10.0-alpha] - 2026-10-14

### Added
- Plugin options can have a number with minus and plus buttons (hold to repeat): the `stepper` entry, documented in `plugins/README.md`. The Tomato plugin uses it.

## [0.9.1-alpha] - 2026-10-14

### Changed
- Active Control Center buttons use the colors of the website preview: Espresso orange, Scrolly blue, Tomato red, Dusty cyan, CloseMe purple. A reading (Hotter, BatLife) is its color on a dark tint of it.
- Closing the notch: the content now fades as one piece and stays in place while the shape closes over it, instead of fading in layers.

### Removed
- Settings that did nothing: the Battery, Connectivity, Focus and Lock Screen pages, and "Hide in fullscreen apps", "Hide in Mission Control" and "Hide while gaming". They will come back when they actually work.

### Added
- Order of the Control Center buttons: use the arrows next to each plugin in **Settings → Control Center**. The order runs left to right, row by row.

## [0.9.0-alpha] - 2026-10-14

### Changed
- Control Center buttons are all the same size and aligned, with one label (the plugin's name): the state text that used to appear under some buttons now shows when the plugin's options are open. A button reflects a tap at once instead of at the next refresh.

### Added
- Plugin options can have read-only rows (a label and a value).
- New plugins, released on their own: **BatLife** (battery level, health, cycles, power and time left), **Tomato** (focus timer with a clock under the notch, a sound, and an optional iPhone alert through iCloud Reminders), **Dusty** (clean mode: black screen and locked keyboard and trackpad for 5 to 60 seconds, ⌘⇧C to end it) and **CloseMe** (keep the Mac running with the lid closed, experimental).
- Updated plugins: **Scrolly** now reverses smooth-scrolling mice such as the Logitech MX Master, and **Hotter** loads its graph faster.
- `scripts/scroll-diagnose.swift` shows how your scroll events look to macOS.

## [0.8.0-alpha] - 2026-10-14

### Added
- Plugins can have a richer Control Center button: a short text instead of the icon (like a temperature), their own color, a plain on/off switch behaviour, and a small line graph in their options.
- New plugins, released on their own: **Scrolly** (reverse the mouse wheel's vertical scroll, trackpad untouched) and **Hotter** (the Mac's temperature as the button, from green to red, with an optional graph). CloseMe (keep the Mac running with the lid closed) is in the repository but not released until it has been tested with a real closed lid.
- The plugin store shows "Needs Notcholino x.y.z+" for plugins that need a newer app, and doesn't install them.

## [0.7.1-alpha] - 2026-10-14

### Fixed
- The full month calendar touched the bottom edge of the notch. The notch is now a little taller in that view and the grid is more compact, so there is a margin even for months with six weeks.

### Documentation
- Website: the dots of the preview notch did not react to clicks (a panel covered them); they now work and grow on hover like in the app. The preview also follows a two-finger horizontal swipe on a trackpad, not only a mouse drag.

## [0.7.0-alpha] - 2026-10-14

### Changed
- The notch no longer opens when the pointer merely passes near it, for example over a browser's tab bar or address bar. Opening now needs the pointer on a thin strip along the top edge of the screen, a bit narrower than the hardware notch. Once open, the whole notch keeps it open as before.

### Added
- Settings → General → Opening: choose between the small opening area (default) and the whole notch.

## [0.6.1-alpha] - 2026-10-14

### Changed
- Releases are now signed with a fixed certificate instead of a different one-off signature each time. macOS recognises every update as the same app, so Calendar, Reminders, Automation and Accessibility permissions, and access to the Spotify token in the Keychain, are kept across updates. Updating to this version asks for them one last time. It is not Apple's notarization: the first-launch warning remains.

## [0.6.0-alpha] - 2026-10-14

### Added
- Settings → General → Gestures → Invert swipe direction: reverses the two-finger swipe (and the mouse wheel) that moves between panels. Click and drag is not affected.

## [0.5.3-alpha] - 2026-10-14

### Fixed
- After an update or a reinstall the volume and brightness HUD of macOS came back even though Accessibility looked switched on in System Settings, and toggling it did not help: macOS ties that permission to the exact signature of each build, so the old entry no longer applies. The Authorize button for Accessibility now clears the old entry and asks again.

## [0.5.2-alpha] - 2026-10-14

### Fixed
- The Permissions list in the settings kept showing "Authorize" for permissions that had just been granted in System Settings. It now updates when you come back to the app, and every couple of seconds while it is on screen.

### Documentation
- Ways to sponsor the project (GitHub Sponsors, Ko-fi, Buy Me a Coffee): `FUNDING.yml`, the README and the website.

## [0.5.1-alpha] - 2026-10-14

### Fixed
- High and growing CPU use while music was playing (tens of percent after a while, and extra work for WindowServer). The music waveform stacked a new animation on top of the previous ones every 0.28 s; it is now drawn with Core Animation and uses almost no CPU.

### Changed
- `scripts/benchmark.sh --playing` also measures with music playing, using a stand-in for the system Now Playing.

### Documentation
- README: badges, table of contents, FAQ, privacy, roadmap, and support and contributing sections.
- Website: FAQ, support and community section, social preview image, structured data, `robots.txt` and `sitemap.xml`.
- Community files: issue templates, pull request template, `CONTRIBUTING.md`, `SECURITY.md` and `CODE_OF_CONDUCT.md`.
- Removed leftover experiment scripts from the repository root.

## [0.5.0-alpha] - 2026-10-14

### Added
- Now Playing works with any app: besides Spotify and Music, Notcholino shows what macOS reports as playing (YouTube, Netflix or Prime Video in a browser, Amazon Music, Podcasts...) with play/pause, next, previous and seek. It can be turned off with Settings → Now Playing → Detect any app.
- Reminders: the reminders due today (and overdue ones) appear in the calendar panel, and can be completed from the notch.
- Authorize buttons: where a permission is missing (Calendar, Reminders, controlling Spotify or Music) the notch shows a button to grant it, and Connect for your Spotify account. Settings → General → Permissions lists every permission with its status.
- A friendlier message when a Spotify account is not allowed to use Notcholino's Spotify app.
- `scripts/setup-signing.sh` and support in the release workflow to sign releases with a fixed certificate, so macOS keeps permissions and Keychain access across updates.

### Changed
- When Spotify and Music are both open, the controls and the displayed song follow whichever is playing, instead of always going to Spotify.
- A paused song stays on screen instead of showing "Nothing Playing".
- The Default player setting now works (Auto-detect, Apple Music, Spotify). The "Idle timeout" and "YouTube Music" options did nothing and were removed.

### Fixed
- Spotify no longer asks for your login password several times per launch: the token is read from the Keychain once and updated in place.
- The playback position of a paused song was not refreshed.

## [0.4.1-alpha] - 2026-10-14

### Fixed
- On macOS 26 the system volume and brightness HUD still showed next to the one in the notch. Notcholino now handles those keys itself, so only the notch shows the change. This needs the Accessibility permission; without it the keys work as before and both HUDs show.

### Added
- A status and a shortcut to the Accessibility settings in the Sound and Display settings.
- Shift + Option with the volume or brightness keys gives quarter steps, like macOS.

## [0.4.0-alpha] - 2026-10-14

### Added
- Benchmark script (`scripts/benchmark.sh`) and published performance figures for memory, CPU, energy and disk, in the README and on the website.

### Changed
- Much lighter when idle: CPU 0.15 % → 0.00 %, energy impact 0.17 → 0.00, and no more wakeups.
- Notcholino no longer starts an `osascript` process every 2 seconds. With Spotify and Music closed it asks nothing; with a player open it refreshes on the player's own notifications, with a slower safety poll (3 s while playing, 8 s while paused).
- The playback position timer only runs while music is playing.
- Hiding the system volume/brightness HUD no longer scans every running process each second: it checks right after a volume or brightness key press.
- Mouse tracking only reports to the notch while the cursor is over it.

## [0.3.0-alpha] - 2026-10-14

### Added
- Plugin system: the Control Center panel shows plugin buttons, and each plugin provides a declarative menu that Notcholino draws inside the notch.
- Plugin Store in Settings → Control Center: install, update and remove plugins from this repository's releases, with a confirmation and a SHA-256 check.
- Plugins are released on their own (tags `<plugin>-v<version>`), and the website publishes a manifest that always points to each plugin's latest release.
- Website: the interactive preview has a Control Center tab with a working Espresso demo, plus a plugins section.
- Documentation for writing and releasing plugins (`plugins/README.md`).

### Changed
- Plugin API version 1 replaces the earlier experimental protocol.

## [0.2.1-alpha] - 2026-10-14

### Changed
- The DMG now opens with a styled install window: gradient background, arrow and drag-to-Applications layout.

## [0.2.0-alpha] - 2026-10-14

### Added
- Control Center section in the settings, with a switch to hide the panel from the notch.
- Single-day calendar view: the weekday on the left and the events of the day on the right, using the whole width.
- The tab dots grow when hovered and can be clicked to switch panel.

### Fixed
- Tab dots were hidden behind the hardware notch: they are now placed using the real notch height of each screen.
- Trackpad swipes are now horizontal, in the same direction as click-and-drag, and reach every panel.
- The Now Playing and Calendar switches in the settings now really hide those panels in the notch.
- The About page shows the real app version.

## [0.1.1-alpha] - 2026-10-14

### Added
- Application icon.

### Documentation
- First launch guide explaining how to allow the app on macOS (README and website).

## [0.1.0-alpha] - 2026-10-13

First public alpha. Expect rough edges and breaking changes.

### Added
- Dynamic notch overlay that extends the hardware notch, expands on hover and supports multiple displays.
- Native System Settings–style preferences window built with SwiftUI.
- Now Playing for Spotify and Apple Music: album art, scrubbable progress bar, seek, shuffle/repeat state, animated waveform and colors extracted from the artwork.
- Spotify Like via the Web API (OAuth PKCE) and AirPlay button, with configurable left/right accessory buttons.
- Compact music mode with album art and waveform.
- Calendar tab using EventKit, with selectable calendars, color-coded events and locations; clicking an event opens it in Calendar.
- System HUDs for volume, brightness, media and microphone, replacing the native macOS HUD, with theme, label and decibel options.
- Scroll-wheel and swipe gestures to switch between tabs.
- Foundation for a Swift `.bundle` plugin architecture and a Control Center tab.
- Landing page on GitHub Pages and an automated release pipeline.

### Known issues
- The app is not notarized, so macOS 15 and later block it on first launch. Open **System Settings → Privacy & Security**, scroll to **Security** and click **Open Anyway**, or run `xattr -dr com.apple.quarantine /Applications/Notcholino.app`.

### Fixed
- Hover glitches: ghosting, the notch collapsing immediately when moved below 32px, and per-display hover state.
- Crashes caused by a constraint loop in the hosting view and by AppleScript on music videos and local files.
- Volume and brightness synchronization.
- Content clipping behind the physical notch on wide MacBook Pro models.

[Unreleased]: https://github.com/Peppe37/Notcholino/compare/v0.9.0-alpha...HEAD
[0.9.0-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.8.0-alpha...v0.9.0-alpha
[0.8.0-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.7.1-alpha...v0.8.0-alpha
[0.7.1-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.7.0-alpha...v0.7.1-alpha
[0.7.0-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.6.1-alpha...v0.7.0-alpha
[0.6.1-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.6.0-alpha...v0.6.1-alpha
[0.6.0-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.5.3-alpha...v0.6.0-alpha
[0.5.3-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.5.2-alpha...v0.5.3-alpha
[0.5.2-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.5.1-alpha...v0.5.2-alpha
[0.5.1-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.5.0-alpha...v0.5.1-alpha
[0.5.0-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.4.1-alpha...v0.5.0-alpha
[0.4.1-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.4.0-alpha...v0.4.1-alpha
[0.4.0-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.3.0-alpha...v0.4.0-alpha
[0.3.0-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.2.1-alpha...v0.3.0-alpha
[0.2.1-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.2.0-alpha...v0.2.1-alpha
[0.2.0-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.1.1-alpha...v0.2.0-alpha
[0.1.1-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.1.0-alpha...v0.1.1-alpha
[0.1.0-alpha]: https://github.com/Peppe37/Notcholino/releases/tag/v0.1.0-alpha
