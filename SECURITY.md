# Security Policy

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

Report it privately with [GitHub's private vulnerability reporting](https://github.com/Peppe37/Notcholino/security/advisories/new) (Security tab → Report a vulnerability). Include what you found, how to reproduce it, and the version of Notcholino and macOS.

You will get an answer as soon as possible. This is a one-person, free project in alpha, so please allow a few days.

## What is in scope

- The app and the plugin loader: Notcholino loads plugins as code, downloaded only from this repository's releases and checked against a SHA-256 published on the project website.
- How the app stores the Spotify token (the macOS Keychain) and what it sends over the network.
- The release workflows and the installer.

## Supported versions

Only the latest release receives fixes.

## Good to know

- Notcholino has no analytics and no telemetry. It talks to the network only to: Spotify (when you connect your account, and to load cover art), GitHub (the plugin list, plugin downloads, and the website showing the latest release).
- The app is not notarized by Apple yet: see the first launch guide in the [README](README.md#first-launch-allowing-the-app).
