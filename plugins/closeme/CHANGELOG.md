# Changelog

## [0.1.0-alpha] - 2026-10-14

### Added
- CloseMe keeps the Mac running with the lid closed (1, 2, 4, 8 or 12 hours), and turns the screen brightness to zero when the lid closes, restoring it when it opens.
- It asks for your administrator password once to turn on, because macOS has no setting for this that works without it.
- Safety: a watchdog switches normal sleep back on as soon as you turn CloseMe off, Notcholino quits or crashes, or 12 hours pass. It also stops when the battery is at 10 % or less and the Mac is unplugged.
- Experimental: not tested with the lid physically closed yet.
