# Changelog

## [0.1.1-alpha] - 2026-10-14

### Fixed
- The graph was slow to appear and each reading briefly held up the notch. Readings are now taken in the background, the sensors are looked up once, and a few quick readings at the start fill the graph within a second.
- The button no longer has the words "Average" or "Highest" under it.

## [0.1.0-alpha] - 2026-10-14

### Added
- First release of Hotter: the Control Center button is the temperature of your Mac, and its color goes from green to red as it heats up.
- Click it to choose the average (of the chip's sensors) or the highest reading, to switch between °C and °F, and to show or hide a small graph of the last six minutes.
- Reads the sensors of Apple silicon Macs without admin rights. It is not available on Intel Macs.
