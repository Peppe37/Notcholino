# Changelog

All notable changes to Notcholino are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/Peppe37/Notcholino/compare/v0.5.1-alpha...HEAD
[0.5.1-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.5.0-alpha...v0.5.1-alpha
[0.5.0-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.4.1-alpha...v0.5.0-alpha
[0.4.1-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.4.0-alpha...v0.4.1-alpha
[0.4.0-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.3.0-alpha...v0.4.0-alpha
[0.3.0-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.2.1-alpha...v0.3.0-alpha
[0.2.1-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.2.0-alpha...v0.2.1-alpha
[0.2.0-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.1.1-alpha...v0.2.0-alpha
[0.1.1-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.1.0-alpha...v0.1.1-alpha
[0.1.0-alpha]: https://github.com/Peppe37/Notcholino/releases/tag/v0.1.0-alpha
