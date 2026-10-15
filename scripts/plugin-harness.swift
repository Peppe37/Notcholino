// SPDX-License-Identifier: GPL-3.0-only
// Tries a plugin without the app: loads its bundle, prints what the app would show, and runs the menu actions you give.
//
//   swiftc -parse-as-library -o /tmp/plugin-harness scripts/plugin-harness.swift Shared/NotcholinoPluginAPI.swift
//   /tmp/plugin-harness path/to/Hello.bundle            # prints the button and the options
//   /tmp/plugin-harness path/to/Hello.bundle one two    # then chooses "one", then "two", printing after each
//
// A popup the plugin asks for is printed as POPUP. The button's tap (for a plugin that is a plain switch) is the action "tap".
import AppKit

@main
struct PluginHarness {
    static var plugin: NotcholinoPlugin!
    static var actions: [String] = []

    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2, let bundle = Bundle(path: args[1]),
              let cls = bundle.principalClass as? NSObject.Type,
              let loaded = cls.init() as? NotcholinoPlugin else {
            print("usage: plugin-harness <path/to/Plugin.bundle> [action ids...]")
            exit(1)
        }
        plugin = loaded
        actions = Array(args.dropFirst(2))
        NSApplication.shared.setActivationPolicy(.accessory)
        plugin.setPopupHandler? { print("POPUP", $0) }
        // The plugin gets a moment to start its timers and read its first values
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: step)
        NSApplication.shared.run()
    }

    static func show() {
        print("--- \(plugin.pluginName) \(plugin.pluginVersion) (API \(plugin.apiVersion))")
        if plugin.controlCenterHidden ?? false {
            print("button: none (this plugin has no button)")
        } else {
            print("button: icon=\(plugin.controlCenterIcon) label='\(plugin.controlCenterLabel ?? "")' color=\(plugin.controlCenterTintColor ?? "default") lit=\(plugin.isActive)")
        }
        if let side = plugin.notchSideIcon, !side.isEmpty { print("beside the notch: \(side) \(plugin.notchSideIconColor ?? "")") }
        if !plugin.statusText.isEmpty { print("status: \(plugin.statusText)") }
        for item in plugin.menuItems() {
            print("   ", item.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "  "))
        }
    }

    static func step() {
        show()
        guard !actions.isEmpty else { exit(0) }
        let action = actions.removeFirst()
        print("\n> \(action)")
        if action == "tap" { plugin.controlCenterButtonTapped?() } else { plugin.performMenuAction(action) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: step)
    }
}
