import SwiftUI

@main
struct NotcholinoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup(id: "settings") {
            ContentView()
        }

        MenuBarExtra("Notcholino", systemImage: "capsule.portrait.fill") {
            OpenSettingsButton()
            Divider()
            Button("Quit Notcholino") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

struct OpenSettingsButton: View {
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Button("Preferences...") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var notchControllers: [NotchWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupNotches()
        SystemNowPlayingMonitor.shared.apply()

        NotificationCenter.default.addObserver(self, selector: #selector(setupNotches), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: "displayScreens", options: .new, context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "displayScreens" {
            setupNotches()
        }
    }

    @objc private func setupNotches() {
        // Close existing notches
        for controller in notchControllers {
            controller.close()
        }
        notchControllers.removeAll()

        let displayScreens = UserDefaults.standard.integer(forKey: "displayScreens")

        if displayScreens == 1 {
            // All screens
            for screen in NSScreen.screens {
                let controller = NotchWindowController(screen: screen)
                controller.window?.orderFront(nil)
                notchControllers.append(controller)
            }
        } else {
            // Main screen only (first screen is always the primary display with menu bar)
            if let primaryScreen = NSScreen.screens.first {
                let controller = NotchWindowController(screen: primaryScreen)
                controller.window?.orderFront(nil)
                notchControllers.append(controller)
            }
        }
    }
}
import SwiftUI
import Combine

/// Manages loading and removing plugins (the protocol lives in Shared/NotcholinoPluginAPI.swift).
final class PluginManager: ObservableObject {
    static let shared = PluginManager()

    @Published var loadedPlugins: [NotcholinoPlugin] = []
    @Published var loadErrors: [String] = []

    let pluginsDirectory: URL
    private var pluginsByPath: [String: NotcholinoPlugin] = [:]

    init() {
        // Plugins live in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        pluginsDirectory = appSupport.appendingPathComponent("Notcholino/Plugins")

        try? FileManager.default.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
        loadPlugins()
    }

    /// Loads every .bundle in the Plugins directory that is not loaded yet.
    /// Plugins already loaded keep their instance (and state).
    func loadPlugins() {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: pluginsDirectory, includingPropertiesForKeys: nil) else { return }
        for url in urls where url.pathExtension == "bundle" && pluginsByPath[url.path] == nil {
            _ = load(bundleAt: url)
        }
    }

    /// Loads a single plugin bundle. Returns nil (and records the reason) if it can't be used.
    @discardableResult
    func load(bundleAt url: URL) -> NotcholinoPlugin? {
        guard let bundle = Bundle(url: url),
              let principalClass = bundle.principalClass as? NSObject.Type,
              let plugin = principalClass.init() as? NotcholinoPlugin else {
            return fail("\(url.lastPathComponent): no NotcholinoPlugin principal class")
        }
        guard plugin.apiVersion == notcholinoPluginAPIVersion else {
            return fail("\(plugin.pluginName): needs plugin API \(plugin.apiVersion), this app has \(notcholinoPluginAPIVersion)")
        }
        guard !loadedPlugins.contains(where: { $0.pluginIdentifier == plugin.pluginIdentifier }) else {
            return fail("\(plugin.pluginName): already loaded")
        }
        pluginsByPath[url.path] = plugin
        loadedPlugins.append(plugin)
        return plugin
    }

    /// Unloads the plugin and deletes its bundle. Its code stays in memory until the app restarts.
    func remove(identifier: String) {
        guard let entry = pluginsByPath.first(where: { $0.value.pluginIdentifier == identifier }) else { return }
        entry.value.pluginWillUnload?()
        pluginsByPath[entry.key] = nil
        loadedPlugins.removeAll { $0.pluginIdentifier == identifier }
        try? FileManager.default.removeItem(atPath: entry.key)
    }

    func bundleURL(forIdentifier identifier: String) -> URL {
        pluginsDirectory.appendingPathComponent("\(identifier).bundle")
    }

    private func fail(_ message: String) -> NotcholinoPlugin? {
        print("Plugin not loaded: \(message)")
        DispatchQueue.main.async { self.loadErrors.append(message) }
        return nil
    }
}
