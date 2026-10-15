// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
import IOKit

/// BatLife shows how your battery is doing. The Control Center button is the charge level, colored by how full it is
/// (blue while charging). Click it for the details: health, charge cycles, power, time left and temperature.
@objc(BatLifePlugin)
final class BatLifePlugin: NSObject, NotcholinoPlugin {

    // MARK: Plugin info

    var apiVersion: Int { notcholinoPluginAPIVersion }
    var pluginIdentifier: String { "batlife" }
    var pluginName: String { "BatLife" }
    var pluginVersion: String {
        Bundle(for: BatLifePlugin.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    var pluginAuthor: String { "Giuseppe" }
    var pluginDescription: String { "Battery level, health, cycles, power and time left, from your Mac's battery." }

    // MARK: Readings

    struct Battery {
        var percent: Int
        var isCharging: Bool
        var isPluggedIn: Bool
        var isFull: Bool
        var healthPercent: Double?
        var cycles: Int?
        var designCycles: Int?
        var watts: Double?            // positive while charging, negative while discharging
        var minutes: Int?             // to empty, or to full while charging
        var temperature: Double?      // °C
        var adapterWatts: Int?
    }

    private static let graphKey = "plugin.batlife.graph"
    private var showGraph: Bool { UserDefaults.standard.bool(forKey: Self.graphKey) }

    private var battery: Battery?
    private var hasBattery = true
    private var powerHistory: [Double] = []
    private var timer: Timer?
    private static let interval: TimeInterval = 10
    private static let maxSamples = 36           // six minutes

    override init() {
        super.init()
        sample()
        for delay in [1.0, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.sample() }
        }
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func sample() {
        guard let b = Self.read() else { hasBattery = false; battery = nil; return }
        hasBattery = true
        battery = b
        if let w = b.watts {
            powerHistory.append(w)
            if powerHistory.count > Self.maxSamples { powerHistory.removeFirst(powerHistory.count - Self.maxSamples) }
        }
    }

    // MARK: Control Center

    var isActive: Bool { true }
    var controlCenterIcon: String { "battery.100" }
    var controlCenterLabel: String { battery.map { "\($0.percent)%" } ?? "--" }

    var controlCenterTintColor: String {
        guard let b = battery else { return "#6e6e73" }
        if b.isCharging { return "#0A84FF" }
        switch b.percent {
        case ...20: return "#FF453A"
        case ...40: return "#FF9F0A"
        default:    return "#30D158"
        }
    }

    var statusText: String { hasBattery ? "" : "This Mac has no battery" }

    func menuItems() -> [[String: Any]] {
        guard let b = battery else { return [] }
        var items: [[String: Any]] = []
        if showGraph, powerHistory.count > 1, let lo = powerHistory.min(), let hi = powerHistory.max() {
            items.append([
                "graph": powerHistory,
                "caption": String(format: "Power, last %.0f min  ·  %.0f to %.0f W", max(Double(powerHistory.count) * Self.interval / 60, 1), lo, hi),
                "color": controlCenterTintColor
            ])
        }
        func row(_ label: String, _ value: String) { items.append(["info": label, "value": value]) }
        row("Health", b.healthPercent.map { String(format: "%.0f %%", $0) } ?? "n/a")
        row("Cycles", b.cycles.map { c in b.designCycles.map { "\(c) of \($0)" } ?? "\(c)" } ?? "n/a")
        row(b.isCharging ? "Charging" : "Using", b.watts.map { String(format: "%.1f W", abs($0)) } ?? "n/a")
        if b.isFull {
            row("Status", "Fully charged")
        } else if b.isCharging {
            row("Until full", b.minutes.map(Self.duration) ?? "calculating…")
        } else if b.isPluggedIn {
            row("Status", "Plugged in, not charging")
        } else {
            row("Time left", b.minutes.map(Self.duration) ?? "calculating…")
        }
        row("Temperature", b.temperature.map { String(format: "%.1f °C", $0) } ?? "n/a")
        if let w = b.adapterWatts, b.isPluggedIn { row("Charger", "\(w) W") }
        items.append(["id": "graph", "title": "Power graph", "checked": showGraph])
        return items
    }

    func performMenuAction(_ id: String) {
        if id == "graph" { UserDefaults.standard.set(!showGraph, forKey: Self.graphKey) }
    }

    func pluginWillUnload() { timer?.invalidate(); timer = nil }

    private static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    // MARK: IOKit

    /// The battery's registry entry, readable without admin rights
    static func read() -> Battery? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let d = props?.takeRetainedValue() as? [String: Any],
              (d["BatteryInstalled"] as? Bool) ?? true else { return nil }

        func int(_ key: String) -> Int? { (d[key] as? NSNumber)?.intValue }
        /// Signed values (like the current) are stored as unsigned 64-bit numbers
        func signed(_ key: String) -> Int64? { (d[key] as? NSNumber).map { Int64(bitPattern: $0.uint64Value) } }

        let current = int("CurrentCapacity") ?? 0
        let maxCapacity = int("MaxCapacity") ?? 100
        let percent = maxCapacity > 0 ? Int((Double(current) / Double(maxCapacity) * 100).rounded()) : current

        let design = int("DesignCapacity")
        let nominal = int("NominalChargeCapacity") ?? int("AppleRawMaxCapacity")
        let health = (design != nil && nominal != nil && design! > 0) ? Double(nominal!) / Double(design!) * 100 : nil

        var watts: Double?
        if let mv = int("Voltage"), let ma = signed("InstantAmperage") ?? signed("Amperage") {
            watts = Double(mv) / 1000 * Double(ma) / 1000
        }
        let charging = (d["IsCharging"] as? Bool) ?? false
        let minutesKey = charging ? "AvgTimeToFull" : "AvgTimeToEmpty"
        let minutes = int(minutesKey).flatMap { $0 > 0 && $0 < 65535 ? $0 : nil }
        let temperature = int("Temperature").map { Double($0) / 100 }
        let adapter = (d["AdapterDetails"] as? [String: Any]).flatMap { ($0["Watts"] as? NSNumber)?.intValue }

        return Battery(
            percent: min(max(percent, 0), 100),
            isCharging: charging,
            isPluggedIn: (d["ExternalConnected"] as? Bool) ?? false,
            isFull: (d["FullyCharged"] as? Bool) ?? false,
            healthPercent: health,
            cycles: int("CycleCount"),
            designCycles: int("DesignCycleCount9C"),
            watts: watts,
            minutes: minutes,
            temperature: temperature,
            adapterWatts: adapter)
    }
}
