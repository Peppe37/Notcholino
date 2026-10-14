# Changelog

## [0.1.2-alpha] - 2026-10-14

### Changed
- A mouse icon for the button, instead of two arrows.

## [0.1.1-alpha] - 2026-10-14

### Fixed
- It did not reverse mice with smooth scrolling, such as the Logitech MX Master with Logi Options+: macOS sees those as continuous scrolling and the check mistook them for a trackpad. A scroll is now taken for a mouse's when it has no trackpad gesture phase, so wheels and smooth mice are reversed and the trackpad is left alone.
- The button showed the change late and carried the words "On" and "Off": it now changes at once and shows only its color.

## [0.1.0-alpha] - 2026-10-14

### Added
- First release of Scrolly: a switch in the Control Center that reverses the vertical scroll of a mouse wheel. The trackpad and horizontal scrolling are not touched.
- Needs the Accessibility permission, and it comes back on after Notcholino restarts if it was on.
- Mice that scroll smoothly (some use "smooth scrolling" software) are seen by macOS as a trackpad and are not reversed.
