# Contributing to Notcholino

Thanks for wanting to help. Notcholino is a small project and every bit counts: bug reports, ideas, translations, screenshots, code, or just telling a friend.

## Ways to help without code

- **Report a bug** or **ask for a feature** with the [issue templates](https://github.com/Peppe37/Notcholino/issues/new/choose).
- **Ask questions and share ideas** in [Discussions](https://github.com/Peppe37/Notcholino/discussions).
- **Star the repository** and tell others about it: it is the best way to help an open source project be found.
- **Try the alpha** on different Macs and macOS versions and tell us what you see.

## Building

You need a recent Xcode (the releases are built with Xcode 26) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
git clone https://github.com/Peppe37/Notcholino.git
cd Notcholino
xcodegen generate
open Notcholino.xcodeproj
```

The Xcode project is generated from `project.yml` and is not committed: change targets and settings there.

## Project layout

| Folder | What is in it |
| --- | --- |
| `Notcholino/` | The app: notch window and views, Now Playing, Calendar and Reminders, settings, permissions. |
| `Shared/` | The plugin API, compiled into the app and into every plugin. |
| `plugins/` | Plugins, one folder each. See [plugins/README.md](plugins/README.md). |
| `third_party/` | Vendored dependencies, with their licenses. |
| `docs/` | The website (GitHub Pages) and its assets. |
| `dmg/` | The window of the installer DMG. |
| `scripts/` | Benchmark, signing setup and the plugin manifest generator. |

## Sending a pull request

1. Fork, then create a branch from `main`.
2. Keep the change focused: one fix or feature per pull request.
3. Match the style of the surrounding code: naming, comment density, SwiftUI idioms.
4. Add a line to `CHANGELOG.md` under **Unreleased** (what changed, for users).
5. Say how you tested it, and include a screenshot or a short recording for anything visual.
6. If you touch performance-sensitive code (timers, polling, the mouse and key monitors), run `scripts/benchmark.sh` before and after and mention the numbers.

Commit messages: a short imperative first line ("Fix hover collapsing the notch"), then a few lines of why if it is not obvious.

## Versions and releases

Releases are `0.x.y-alpha`: `x` goes up for features, `y` for fixes. The maintainer publishes them by pushing a tag, and the release workflow does the rest. Plugins have their own versions and tags (`<plugin>-v<version>`).

## A note on the license

Notcholino is released under the [PolyForm Noncommercial 1.0.0](LICENSE) license. By sending a contribution you agree that it is licensed under the same terms.

## Being kind

Be respectful and patient, especially with newcomers. See the [Code of Conduct](CODE_OF_CONDUCT.md).
