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
    var notchWindowController: NotchWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        notchWindowController = NotchWindowController()
        notchWindowController?.window?.orderFront(nil)
    }
}
