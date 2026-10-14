# Changelog

## [0.2.1-alpha] - 2026-10-14

### Removed
- The iPhone option. macOS can't set an alarm on an iPhone, and a Reminder is only a notification and clutters the list, so it made no sense. Tomato no longer asks for Reminders access.

## [0.2.0-alpha] - 2026-10-14

### Changed
- It is now a Pomodoro timer: you set how many minutes of work and of break, with minus and plus buttons (hold to go faster), and it repeats, work then break then work again, until you press Stop. It rings at each switch.
- The clock shows the break in green, with a cup.
- The iPhone alert is a Reminder due when the current stretch ends, made for the next switch only and removed shortly after, so the list doesn't fill up. It stays a notification: macOS has no way to set an alarm on an iPhone.
- Needs Notcholino 0.10.0 or later (the number rows).

## [0.1.2-alpha] - 2026-10-14

### Changed
- The clock is now part of the notch: a black tab hangs from its bottom edge instead of a separate bubble, 2 points lower than before.

## [0.1.1-alpha] - 2026-10-14

### Changed
- A stopwatch icon for the button.

## [0.1.0-alpha] - 2026-10-14

### Added
- First release of Tomato: pick 5, 10, 15, 25, 45 or 60 minutes. A small clock appears just under the notch, and a sound plays at the end.
- Optional iPhone alert: when allowed, Tomato adds a Reminder with an alarm at the end time, which your iPhone shows as a notification through iCloud. It needs Reminders access and an iCloud Reminders list. There is no public way to make an iPhone ring directly from a Mac.
