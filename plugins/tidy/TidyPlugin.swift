// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation

/// Tidy hides the icons on your Desktop with one click, for a clean screen when you share it or record it, and shows them
/// again with another. It uses Finder's own setting, so the files stay where they are.
///
/// Finder has to restart for the change to apply: its windows close and open again, which takes a second.
@objc(TidyPlugin)
final class TidyPlugin: NSObject, NotcholinoPlugin {

    // MARK: Plugin info

    var apiVersion: Int { notcholinoPluginAPIVersion }
    var pluginIdentifier: String { "tidy" }
    var pluginName: String { "Tidy" }
    var pluginVersion: String {
        Bundle(for: TidyPlugin.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    var pluginAuthor: String { "Giuseppe" }
    var pluginDescription: String { "Hide the icons on your Desktop with one click, and show them again with another." }

    // MARK: State

    private var iconsHidden = TidyPlugin.readHidden()
    private var busy = false

    /// Finder's setting, "CreateDesktop": missing or true means the icons show
    static func readHidden() -> Bool {
        let value = CFPreferencesCopyAppValue("CreateDesktop" as CFString, "com.apple.finder" as CFString)
        if let flag = value as? Bool { return !flag }
        return false
    }

    // MARK: Control Center

    var isActive: Bool { iconsHidden }
    var controlCenterIcon: String { "menubar.dock.rectangle" }
    var controlCenterTintColor: String { iconsHidden ? "#64D2FF" : "" }
    var statusText: String { "" }
    func menuItems() -> [[String: Any]] { [] }
    func performMenuAction(_ id: String) {}

    /// The button is a switch
    func controlCenterButtonTapped() {
        guard !busy else { return }
        busy = true
        let hide = !iconsHidden
        iconsHidden = hide          // the button answers at once
        DispatchQueue.global(qos: .userInitiated).async {
            Self.run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", hide ? "false" : "true"])
            Self.run("/usr/bin/killall", ["Finder"])
            DispatchQueue.main.async {
                self.iconsHidden = Self.readHidden()
                self.busy = false
            }
        }
    }

    private static func run(_ path: String, _ arguments: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = arguments
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
    }
}
