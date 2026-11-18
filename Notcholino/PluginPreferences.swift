// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Stable actions for existing bundles. Live menu rows such as clipboard history and recent colours
/// are never offered as fixed shortcuts. Third-party plugins can opt in with their own static IDs.
struct PluginShortcutAction: Identifiable {
    enum Command { case open, button, menu(String), toggle(on: String, off: String) }

    let id: String
    let title: String
    let command: Command

    private static func menu(_ id: String, _ title: String) -> Self {
        Self(id: "menu:" + id, title: title, command: .menu(id))
    }

    static func actions(for plugin: NotcholinoPlugin) -> [Self] {
        let id = plugin.pluginIdentifier
        let title = id == "clippy" ? "Open clipboard history" : "Open in the notch"
        var result = [Self(id: "open", title: title, command: .open)]
        if plugin.responds(to: #selector(NotcholinoPlugin.controlCenterButtonTapped)) {
            let primary: String
            switch id {
            case "reader": primary = "Select text on screen"
            case "scrolly": primary = "Toggle reverse scrolling"
            case "tidy": primary = "Toggle desktop icons"
            default: primary = "Run primary action"
            }
            result.append(Self(id: "primary", title: primary, command: .button))
        }
        switch id {
        case "clippy": result.append(menu("copy:0", "Copy most recent item"))
        case "picker": result.append(menu("pick", "Pick a colour"))
        case "espresso": result.append(Self(id: "toggle", title: "Toggle keep awake", command: .toggle(on: "indefinite", off: "off")))
        case "tomato": result.append(Self(id: "toggle", title: "Start or stop the timer", command: .toggle(on: "start", off: "stop")))
        case "quicky":
            result += [menu("lock", "Lock screen"), menu("display", "Turn off the display"), menu("saver", "Start screen saver")]
        default: break
        }
        for entry in plugin.shortcutActions?() ?? [] {
            guard let id = entry["id"], !id.isEmpty, let title = entry["title"], !title.isEmpty,
                  !result.contains(where: { $0.id == "menu:" + id }) else { continue }
            result.append(menu(id, title))
        }
        return result
    }

    func perform(on plugin: NotcholinoPlugin, open: (String) -> Void) {
        switch command {
        case .open: open(plugin.pluginIdentifier)
        case .button: plugin.controlCenterButtonTapped?()
        case .menu(let id):
            if plugin.menuItems().contains(where: { $0["id"] as? String == id }) { plugin.performMenuAction(id) }
        case .toggle(let on, let off):
            let id = plugin.isActive ? off : on
            if plugin.menuItems().contains(where: { $0["id"] as? String == id }) { plugin.performMenuAction(id) }
        }
    }
}

enum PluginPreferences {
    static func guide(for plugin: NotcholinoPlugin) -> String {
        if let guide = plugin.pluginUsage, !guide.isEmpty { return guide }
        switch plugin.pluginIdentifier {
        case "batlife": return "Open BatLife in the notch to see battery health, charge cycles and power. Turn on Power graph to see how power use changes."
        case "clippy": return "Copy text, an image or a file as usual, then open Clippy in the notch. Click an item to copy it again. Clear empties the history. History stays in memory and disappears when Notcholino quits."
        case "closeme": return "Open CloseMe and choose how long the Mac should stay awake with the lid shut. macOS may ask for your password. Choose Turn off when finished, and never put the Mac in a bag while CloseMe is active."
        case "devices": return "Open Devices in the notch to see battery levels reported by your connected accessories. Some devices do not report a charge level."
        case "dusty": return "Open Dusty and choose a cleaning duration to lock the keyboard and pointer. Press ⌘⇧C to end clean mode early."
        case "espresso": return "Open Espresso and choose a duration or an end time to keep the Mac awake. To stop early, reopen Espresso and choose Turn off."
        case "hotter": return "Open Hotter to see your Mac’s temperature. Choose an average or the highest reading, show the graph, and switch between Celsius and Fahrenheit."
        case "picker": return "Choose Pick a color, then click a pixel on screen. Picker copies that colour in the selected format. Click a recent colour to copy it again."
        case "pinger": return "Open Pinger to see response time and whether a VPN is active. Choose a target in Settings to change where Pinger measures latency."
        case "quicky": return "Open Quicky and choose Lock, Display off or Screen saver. Each command runs immediately."
        case "reader": return "Click Reader or run its shortcut, then drag over text on the screen. Reader recognises the text on your Mac and copies it. Grant Screen Recording if macOS asks."
        case "scrolly": return "Click Scrolly to reverse the mouse wheel’s vertical direction. Click again to restore it. The trackpad is unaffected. Grant Accessibility if macOS asks."
        case "tidy": return "Click Tidy to hide the desktop icons. Click again to show them. Tidy restores the icons when Notcholino quits."
        case "tomato": return "Set the work and break lengths, then choose Start. Work and break alternate automatically until you choose Stop."
        case "watcher": return "Watcher runs as soon as it is installed. Look beside the notch for the microphone or camera indicator. A popup appears when recording starts; Watcher never records anything."
        default:
            return plugin.controlCenterHidden == true
                ? "This plugin runs in the background. Check its description and options for how it works."
                : "Open this plugin in the notch’s Control Center. Choose an option or use its primary button."
        }
    }

    /// Use the same IDs and values as the notch. Never read a dynamic menu merely to build a
    /// settings page for a plugin without preferences (particularly clipboard history).
    static func settings(for plugin: NotcholinoPlugin) -> [[String: Any]] {
        if let own = plugin.settingsItems?() { return own }
        let keys: Set<String>
        switch plugin.pluginIdentifier {
        case "batlife": keys = ["graph"]
        case "hotter": keys = ["average", "highest", "graph", "fahrenheit"]
        case "picker": return plugin.menuItems().filter { ($0["id"] as? String)?.hasPrefix("format:") == true }
        case "pinger": keys = ["1.1.1.1", "8.8.8.8", "apple.com"]
        case "tomato": keys = ["work", "break", "sound"]
        default: return []
        }
        return plugin.menuItems().filter { ($0["id"] as? String).map(keys.contains) == true }
    }
}
