# Changelog

All notable changes to Notcholino are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/Peppe37/Notcholino/compare/v0.2.0-alpha...HEAD
[0.2.0-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.1.1-alpha...v0.2.0-alpha
[0.1.1-alpha]: https://github.com/Peppe37/Notcholino/compare/v0.1.0-alpha...v0.1.1-alpha
[0.1.0-alpha]: https://github.com/Peppe37/Notcholino/releases/tag/v0.1.0-alpha
