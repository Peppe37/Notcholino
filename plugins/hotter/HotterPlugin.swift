import AppKit
import Foundation

/// Hotter shows how hot the Mac is. The Control Center button is the temperature itself, and its color goes from green
/// to red as the Mac gets hotter. Click it to choose the average or the highest reading, and to show a small graph.
@objc(HotterPlugin)
final class HotterPlugin: NSObject, NotcholinoPlugin {

    // MARK: Plugin info

    var apiVersion: Int { notcholinoPluginAPIVersion }
    var pluginIdentifier: String { "hotter" }
    var pluginName: String { "Hotter" }
    var pluginVersion: String {
        Bundle(for: HotterPlugin.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    var pluginAuthor: String { "Giuseppe" }
    var pluginDescription: String { "The temperature of your Mac in the Control Center, with a color that turns red as it heats up." }

    // MARK: Settings

    private enum Key {
        static let mode = "plugin.hotter.mode"           // "average" or "highest"
        static let graph = "plugin.hotter.graph"
        static let fahrenheit = "plugin.hotter.fahrenheit"
    }
    private var mode: String { UserDefaults.standard.string(forKey: Key.mode) ?? "average" }
    private var showGraph: Bool { UserDefaults.standard.object(forKey: Key.graph) as? Bool ?? true }
    private var fahrenheit: Bool { UserDefaults.standard.bool(forKey: Key.fahrenheit) }

    // MARK: Readings

    private let sensors = TemperatureSensors()
    private var history: [Double] = []          // in °C, one reading every `interval`
    private var last: Reading?
    private var timer: Timer?
    private static let interval: TimeInterval = 5
    private static let maxSamples = 72          // six minutes

    struct Reading { var average: Double; var highest: Double }

    override init() {
        super.init()
        sample()
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func sample() {
        guard let reading = sensors.read() else { return }
        last = reading
        history.append(value(of: reading))
        if history.count > Self.maxSamples { history.removeFirst(history.count - Self.maxSamples) }
    }

    /// The reading for the chosen mode, in °C
    private func value(of r: Reading) -> Double { mode == "highest" ? r.highest : r.average }

    private func display(_ celsius: Double) -> Double { fahrenheit ? celsius * 9 / 5 + 32 : celsius }

    // MARK: Control Center

    var isActive: Bool { true }
    var controlCenterIcon: String { "thermometer.medium" }

    var controlCenterLabel: String {
        guard let r = last else { return "--" }
        return "\(Int(display(value(of: r)).rounded()))°"
    }

    var controlCenterTintColor: String {
        guard let r = last else { return "#6e6e73" }
        return Self.color(forCelsius: value(of: r))
    }

    var statusText: String {
        guard last != nil else { return sensors.isAvailable ? "Reading…" : "Not available" }
        return mode == "highest" ? "Highest" : "Average"
    }

    func menuItems() -> [[String: Any]] {
        var items: [[String: Any]] = []
        if showGraph, history.count > 1, let lo = history.min(), let hi = history.max() {
            let minutes = Double(history.count) * Self.interval / 60
            let unit = fahrenheit ? "°F" : "°C"
            items.append([
                "graph": history.map(display),
                "caption": String(format: "Last %.0f min  ·  %.0f–%.0f%@", max(minutes, 1), display(lo), display(hi), unit),
                "color": Self.color(forCelsius: history.last ?? 30)
            ])
        }
        items.append(["id": "average", "title": "Average", "checked": mode == "average"])
        items.append(["id": "highest", "title": "Highest", "checked": mode == "highest"])
        items.append(["id": "graph", "title": "Graph", "checked": showGraph])
        items.append(["id": "fahrenheit", "title": "°F", "checked": fahrenheit])
        return items
    }

    func performMenuAction(_ id: String) {
        let d = UserDefaults.standard
        switch id {
        case "average", "highest":
            d.set(id, forKey: Key.mode)
            history.removeAll()                       // the graph follows the chosen reading
            sample()
        case "graph":      d.set(!showGraph, forKey: Key.graph)
        case "fahrenheit": d.set(!fahrenheit, forKey: Key.fahrenheit)
        default: break
        }
    }

    func pluginWillUnload() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Color

    /// Green when cool, through yellow and orange, to red when hot (35 °C and below → green, 95 °C and above → red)
    static func color(forCelsius t: Double) -> String {
        let x = min(max((t - 35) / 60, 0), 1)
        let hue = 0.36 * (1 - x)
        let c = NSColor(hue: CGFloat(hue), saturation: 0.82, brightness: 0.88, alpha: 1).usingColorSpace(.sRGB) ?? .red
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

/// Temperature sensors of Apple silicon, read through IOKit's HID event system (no admin rights needed).
/// The functions are not in the public headers, so they are looked up by name.
final class TemperatureSensors {
    private typealias Client = UnsafeMutableRawPointer
    private typealias Service = UnsafeMutableRawPointer

    private let client: Client?
    private let setMatching: (@convention(c) (Client, CFDictionary) -> Int32)?
    private let copyServices: (@convention(c) (Client) -> Unmanaged<CFArray>?)?
    private let copyProperty: (@convention(c) (Service, CFString) -> Unmanaged<CFTypeRef>?)?
    private let copyEvent: (@convention(c) (Service, Int64, Int32, Int64) -> UnsafeMutableRawPointer?)?
    private let floatValue: (@convention(c) (UnsafeMutableRawPointer, Int32) -> Double)?

    var isAvailable: Bool { client != nil }

    init() {
        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        func load<T>(_ name: String, _ type: T.Type) -> T? {
            guard let handle, let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: type)
        }
        let create = load("IOHIDEventSystemClientCreate", (@convention(c) (CFAllocator?) -> Client?).self)
        setMatching = load("IOHIDEventSystemClientSetMatching", (@convention(c) (Client, CFDictionary) -> Int32).self)
        copyServices = load("IOHIDEventSystemClientCopyServices", (@convention(c) (Client) -> Unmanaged<CFArray>?).self)
        copyProperty = load("IOHIDServiceClientCopyProperty", (@convention(c) (Service, CFString) -> Unmanaged<CFTypeRef>?).self)
        copyEvent = load("IOHIDServiceClientCopyEvent", (@convention(c) (Service, Int64, Int32, Int64) -> UnsafeMutableRawPointer?).self)
        floatValue = load("IOHIDEventGetFloatValue", (@convention(c) (UnsafeMutableRawPointer, Int32) -> Double).self)
        client = create?(kCFAllocatorDefault)
        if let client, let setMatching {
            // Usage page 0xff00, usage 5: temperature sensors
            _ = setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        }
    }

    /// Average of the chip's die sensors and the hottest valid sensor, in °C
    func read() -> HotterPlugin.Reading? {
        guard let client, let copyServices, let copyProperty, let copyEvent, let floatValue,
              let services = copyServices(client)?.takeRetainedValue() as [AnyObject]? else { return nil }
        var dies: [Double] = [], all: [Double] = []
        for service in services {
            let ref = Unmanaged.passUnretained(service).toOpaque()
            let name = (copyProperty(ref, "Product" as CFString)?.takeRetainedValue() as? String) ?? ""
            // "tcal" is a calibration value, not a temperature
            guard !name.contains("tcal"), let event = copyEvent(ref, 15, 0, 0) else { continue }
            let value = floatValue(event, 15 << 16)
            Unmanaged<AnyObject>.fromOpaque(event).release()
            guard value > 0, value < 130 else { continue }   // some sensors report garbage when idle
            all.append(value)
            if name.contains("tdie") { dies.append(value) }
        }
        guard let highest = all.max() else { return nil }
        let pool = dies.isEmpty ? all : dies
        return HotterPlugin.Reading(average: pool.reduce(0, +) / Double(pool.count), highest: highest)
    }
}
