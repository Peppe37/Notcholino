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
