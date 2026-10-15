# Changelog

## [0.2.0-alpha] - 2026-10-15

### Fixed
- **CloseMe could leave the Mac unable to sleep.** It switches on a global macOS setting (`SleepDisabled`) that macOS keeps across restarts, and in some cases (a restart while it was on, a watchdog that didn't survive) it stayed on: the Sleep item in the Apple menu stayed grey, the lid no longer put the Mac to sleep, and an external display kept its picture with the lid closed.

### Changed
- It only touches the setting if it was off, and gives back exactly what it found: if another app already switched it off, CloseMe leaves it alone and doesn't restore it.
- A one-shot launch daemon is installed with it and removed when it ends, so a restart while it is on switches the setting off at boot.
- If an earlier session still left it on, the next launch says so and the options offer **Restore sleep** (needs your password).
- The options say that it changes a macOS setting that is restored when you stop it or quit Notcholino.

## [0.1.0-alpha] - 2026-10-14

### Added
- CloseMe keeps the Mac running with the lid closed (1, 2, 4, 8 or 12 hours), and turns the screen brightness to zero when the lid closes, restoring it when it opens.
- It asks for your administrator password once to turn on, because macOS has no setting for this that works without it.
- Safety: a watchdog switches normal sleep back on as soon as you turn CloseMe off, Notcholino quits or crashes, or 12 hours pass. It also stops when the battery is at 10 % or less and the Mac is unplugged.
- Experimental: not tested with the lid physically closed yet.
