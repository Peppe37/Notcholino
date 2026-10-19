# Writing a Notcholino extension

A **plugin** is a button in the Control Center. An **extension** is bigger: it has its own **page in the notch**, its own
**settings**, and can ask **Notchy's AI** for help. Official extensions (like Notchy) are part of the app. Extensions written by
other developers are loaded in **developer mode**.

## Security, in short

An extension is a compiled bundle that runs *inside* Notcholino, with the app's permissions. So:

- Nothing is loaded unless the user turns on **Settings → Plugin Store → Extensions → Developer mode**.
- Extensions are loaded only from `~/Library/Application Support/Notcholino/Extensions`. There is no download, no store and no
  automatic install for them.
- An extension never sees the user's AI keys. If it asks Notchy's AI for something, the app does the request, and only if the
  user ticked **Allow it to use Notchy's AI** for that extension.
- Only load extensions you wrote or read the code of.

## The API

`ExtensionAPI/NotcholinoExtensionAPI.swift` is the whole contract: one Objective-C compatible protocol, `NotcholinoExtension`.
You provide an identifier, a name, version, author, description and an SF Symbol, plus:

- `makePageView() -> NSView`: the page in the notch (about 640 × 150 points).
- optional `makeSettingsView() -> NSView`: shown in a sheet from the Extensions settings.
- optional `setPopupHandler(_:)`: keep the handler and call it to show a small popup under the notch.
- optional `setAskHandler(_:)`: keep the handler and call it with a prompt to get an answer from the user's text AI.
- optional `extensionWillUnload()`: release things.

## Build one

```bash
cp -R extensions/hello extensions/mine      # start from the example
# edit extensions/mine/*.swift: rename the class, change the page
scripts/dev-extension.sh extensions/mine MyExtension
```

The second argument is the `@objc(...)` name of your principal class. The script builds a `.bundle` with `swiftc` (no Xcode
project needed) and installs it in the folder above. Turn on developer mode and restart Notcholino to load it. The example in
`extensions/hello` shows a page, a settings view, and a button that asks Notchy's AI for a joke.

## Getting an extension in the store

There is no store for extensions yet. If you build something useful, open an issue or a pull request: official extensions are
reviewed and shipped inside the app.
