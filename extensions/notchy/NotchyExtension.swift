// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

/// Notchy as an extension: the app loads this bundle from the store, hands it a `NotcholinoHost`, and everything else (the
/// cube, its page and settings, the voice shortcut, Mail, the AI) lives in here. Removing it from the store removes all of it.
@objc(NotchyExtension)
final class NotchyExtension: NSObject, NotcholinoExtension {
    var apiVersion: Int { notcholinoExtensionAPIVersion }
    var extensionIdentifier: String { "notchy" }
    var extensionName: String { "Notchy" }
    var extensionVersion: String { Bundle(for: NotchyExtension.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    var extensionAuthor: String { "Giuseppe" }
    var extensionDescription: String { "A small glass cube that lives in the notch: summaries, your day, the weather, the screen, email alerts and voice." }
    var extensionSymbol: String { "face.smiling.inverse" }
    var isAssistant: Bool { true }
    var pageVisible: Bool { NotchySettings.shared.pageVisible }

    func setHost(_ host: NotcholinoHost) { NotchyBridge.shared.host = host }

    func makePageView() -> NSView { hosting(NotchyNotchView()) }
    func makeSettingsView() -> NSView { hosting(NotchySettingsView()) }
    func makeWingView() -> NSView { hosting(NotchyWingView()) }

    /// A hosting view that takes the size it is given: with the default sizing options it asks its window to be as big as the page
    /// would like, and a settings page taller than the window made the whole Settings window lay out around it
    private func hosting<V: View>(_ view: V) -> NSView {
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        return host
    }

    /// Switched on (after loading, or from the store): start the things Notchy does by itself
    func extensionDidEnable() {
        NotchySettings.shared.enabled = true
        #if DEBUG
        NotchyDemo.listen()
        #endif
    }

    /// Switched off, removed, or the app is quitting: stop the timers, the shortcut and the Mail watcher
    func extensionWillUnload() { NotchySettings.shared.enabled = false }

    func receiveText(_ text: String) { NotchyAssistant.shared.send(text: text) }
    func receiveFiles(_ urls: [URL]) { NotchyAssistant.shared.send(files: urls) }

    /// Another extension asked for the AI: Notchy holds the keys, so it does the request
    func askAI(_ prompt: String, system: String?, completion: @escaping (String?, String?) -> Void) {
        guard NotchySettings.shared.enabled else { completion(nil, "Notchy is switched off."); return }
        Task { @MainActor in
            do { completion(try await NotchyClient.complete(prompt: prompt, system: system, task: .text), nil) }
            catch { completion(nil, error.localizedDescription) }
        }
    }

    func hostEvent(_ name: String, info: [String: Any]) {
        if name == "plugin" { NotchyPresence.shared.reactToPlugin() }
    }
}

/// The cube beside the closed notch, while it peeks out
struct NotchyWingView: View {
    @ObservedObject private var presence = NotchyPresence.shared

    var body: some View {
        NotchyCube(mood: presence.mood, size: 20, alive: false)
            .frame(width: 20, height: 20)
    }
}
