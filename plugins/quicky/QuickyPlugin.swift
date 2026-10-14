import AppKit
import Foundation

/// Quicky has three things macOS keeps hidden in menus: lock the screen now, turn the display off, start the screen saver.
@objc(QuickyPlugin)
final class QuickyPlugin: NSObject, NotcholinoPlugin {

    // MARK: Plugin info

    var apiVersion: Int { notcholinoPluginAPIVersion }
    var pluginIdentifier: String { "quicky" }
    var pluginName: String { "Quicky" }
    var pluginVersion: String {
        Bundle(for: QuickyPlugin.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    var pluginAuthor: String { "Giuseppe" }
    var pluginDescription: String { "Lock the screen, turn the display off or start the screen saver, in one click." }

    // MARK: Control Center

    var isActive: Bool { false }
    var controlCenterIcon: String { "lock.display" }
    var statusText: String { "" }

    func menuItems() -> [[String: Any]] {
        [["id": "lock", "title": "Lock"],
         ["id": "display", "title": "Display off"],
         ["id": "saver", "title": "Screen saver"]]
    }

    func performMenuAction(_ id: String) {
        switch id {
        case "lock": lockScreen()
        case "display": run("/usr/bin/pmset", ["displaysleepnow"])
        case "saver": run("/usr/bin/open", ["-a", "ScreenSaverEngine"])
        default: break
        }
    }

    // MARK: Actions

    private func lockScreen() {
        // The lock that the system's own shortcut uses, from the login framework
        typealias Lock = @convention(c) () -> Int32
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            _ = unsafeBitCast(symbol, to: Lock.self)()
        } else {
            // Without it, turning the display off locks the Mac if it asks for a password right away
            run("/usr/bin/pmset", ["displaysleepnow"])
        }
    }

    private func run(_ path: String, _ arguments: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = arguments
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
    }
}
