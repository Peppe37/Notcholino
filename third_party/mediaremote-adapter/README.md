# MediaRemote Adapter (vendored)

Copy of [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) at commit `797729d` (2026-10-10), BSD-3-Clause, unmodified. See `LICENSE`.

Notcholino uses it to read the system "Now Playing" information (YouTube or Netflix in a browser, Amazon Music, Podcasts, ...) and to control playback, on macOS versions where Apple restricts the MediaRemote framework. It works by running the system `/usr/bin/perl`, which is allowed to use MediaRemote, with the `MediaRemoteAdapter` framework built from these sources.

To update it, replace `src/`, `include/` and `bin/` with the upstream ones and re-run the app's Now Playing checks.
