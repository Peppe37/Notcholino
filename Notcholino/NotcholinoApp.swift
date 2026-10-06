import SwiftUI

@main
struct NotcholinoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var notchWindowController: NotchWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup the Notch Window when the app launches
        notchWindowController = NotchWindowController()
        notchWindowController?.showWindow(nil)
    }
}
