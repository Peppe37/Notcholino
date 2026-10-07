import AppKit
print("Spotify:", NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") ?? "nil")
print("Music:", NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") ?? "nil")
