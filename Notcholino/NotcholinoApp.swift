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

/// Protocol that compiled plugins (.bundle) must implement and export as their Principal Class.
@objc(NotcholinoPlugin)
public protocol NotcholinoPlugin: NSObjectProtocol {
    var pluginName: String { get }
    var pluginVersion: String { get }
    var pluginAuthor: String { get }
    var pluginDescription: String { get }
    
    /// Called when the button in the Control Center is clicked
    func onControlCenterButtonClick()
    
    /// Optional: Return the name of an SF Symbol for the Control Center button
    var controlCenterIcon: String { get }
}

/// Manages downloading, loading, and interacting with plugins.
final class PluginManager: ObservableObject {
    static let shared = PluginManager()
    
    @Published var loadedPlugins: [NotcholinoPlugin] = []
    
    private let pluginsDirectory: URL
    
    init() {
        // Define the plugins directory in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        pluginsDirectory = appSupport.appendingPathComponent("Notcholino/Plugins")
        
        createPluginsDirectoryIfNeeded()
        loadPlugins()
    }
    
    private func createPluginsDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: pluginsDirectory.path) {
            try? FileManager.default.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    /// Loads all .bundle files from the Plugins directory
    func loadPlugins() {
        loadedPlugins.removeAll()
        
        guard let urls = try? FileManager.default.contentsOfDirectory(at: pluginsDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        
        let bundleURLs = urls.filter { $0.pathExtension == "bundle" }
        
        for url in bundleURLs {
            guard let bundle = Bundle(url: url) else { continue }
            
            // Try to load the principal class
            if let principalClass = bundle.principalClass as? NSObject.Type,
               let pluginInstance = principalClass.init() as? NotcholinoPlugin {
                loadedPlugins.append(pluginInstance)
                print("Successfully loaded plugin: \(pluginInstance.pluginName)")
            } else {
                print("Failed to find NotcholinoPlugin principal class in bundle: \(url.lastPathComponent)")
            }
        }
    }
}
