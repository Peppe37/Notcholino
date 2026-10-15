// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation

/// Devices shows the battery of what is connected over Bluetooth: AirPods (each earbud and the case), a mouse, a keyboard, a
/// trackpad, a controller. The button is the lowest of them, colored by how low it is; click it for the list.
///
/// macOS reports them through its Bluetooth report, which takes a moment to build, so it is read in the background, and
/// again only when the options are opened (and every few minutes).
@objc(DevicesPlugin)
final class DevicesPlugin: NSObject, NotcholinoPlugin {

    // MARK: Plugin info

    var apiVersion: Int { notcholinoPluginAPIVersion }
    var pluginIdentifier: String { "devices" }
    var pluginName: String { "Devices" }
    var pluginVersion: String {
        Bundle(for: DevicesPlugin.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    var pluginAuthor: String { "Giuseppe" }
    var pluginDescription: String { "The battery of your AirPods, mouse, keyboard and other Bluetooth devices." }

    // MARK: Readings

    struct Device { let name: String; let parts: [(label: String, percent: Int)] }

    private var devices: [Device] = []
    private var loaded = false
    private var refreshing = false
    private var lastRefresh = Date.distantPast
    private var timer: Timer?

    override init() {
        super.init()
        refresh()
        let t = Timer(timeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func pluginWillUnload() { timer?.invalidate(); timer = nil }

    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        lastRefresh = Date()
        DispatchQueue.global(qos: .utility).async {
            let found = Self.readDevices()
            DispatchQueue.main.async {
                self.devices = found
                self.loaded = true
                self.refreshing = false
            }
        }
    }

    /// From `system_profiler`'s Bluetooth report: the connected devices that tell their battery
    private static func readDevices() -> [Device] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["-json", "SPBluetoothDataType"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let report = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = report["device_connected"] as? [[String: [String: Any]]] else { return [] }
        var result: [Device] = []
        for entry in connected {
            for (name, info) in entry {
                var parts: [(String, Int)] = []
                for (key, label) in [("device_batteryLevelLeft", "L"), ("device_batteryLevelRight", "R"),
                                     ("device_batteryLevelCase", "Case"), ("device_batteryLevelMain", ""), ("device_batteryLevel", "")] {
                    if let text = info[key] as? String, let value = Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) {
                        parts.append((label, value))
                    }
                }
                if !parts.isEmpty { result.append(Device(name: name, parts: parts)) }
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    private var lowest: Int? { devices.flatMap { $0.parts.map(\.percent) }.min() }

    // MARK: Control Center

    var isActive: Bool { lowest != nil }
    var controlCenterIcon: String { "airpodspro" }

    var controlCenterLabel: String { lowest.map { "\($0)%" } ?? "" }

    var controlCenterTintColor: String {
        guard let level = lowest else { return "" }
        return level <= 20 ? "#FF453A" : level <= 40 ? "#FF9F0A" : "#30D158"
    }

    var statusText: String { loaded && devices.isEmpty ? "" : "lowest battery" }

    func menuItems() -> [[String: Any]] {
        if Date().timeIntervalSince(lastRefresh) > 30 { refresh() }
        if !loaded { return [["header": "Looking for devices…"]] }
        if devices.isEmpty { return [["header": "No connected device reports its battery."]] }
        return devices.map { device in
            let value = device.parts.map { $0.label.isEmpty ? "\($0.percent)%" : "\($0.label) \($0.percent)%" }.joined(separator: " · ")
            return ["info": device.name, "value": value]
        }
    }

    func performMenuAction(_ id: String) {}
}
