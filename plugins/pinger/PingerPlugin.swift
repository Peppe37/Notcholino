import AppKit
import Foundation
import Network

/// Pinger shows how fast your connection answers. The button is the latency in milliseconds, colored from green (quick) to
/// red (slow), or OFF when nothing answers. Click it for a graph of the last few minutes, the average, the packets lost and
/// whether a VPN is on.
///
/// Every five seconds it opens one TCP connection to a public server and closes it right away, which is as light as it gets.
@objc(PingerPlugin)
final class PingerPlugin: NSObject, NotcholinoPlugin {

    // MARK: Plugin info

    var apiVersion: Int { notcholinoPluginAPIVersion }
    var pluginIdentifier: String { "pinger" }
    var pluginName: String { "Pinger" }
    var pluginVersion: String {
        Bundle(for: PingerPlugin.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    var pluginAuthor: String { "Giuseppe" }
    var pluginDescription: String { "How fast your connection answers, as a number and a graph, and whether a VPN is on." }

    // MARK: State

    private static let targets = ["1.1.1.1", "8.8.8.8", "apple.com"]
    private static let targetKey = "plugin.pinger.target"
    private static let interval: TimeInterval = 5
    private static let maxSamples = 36           // three minutes
    private static let timeout: TimeInterval = 2

    private var target: String {
        let saved = UserDefaults.standard.string(forKey: Self.targetKey) ?? ""
        return Self.targets.contains(saved) ? saved : Self.targets[0]
    }

    /// Latency in ms, or nil for a probe that got no answer
    private var samples: [Double?] = []
    private var timer: Timer?
    private var inFlight = false
    /// The first probe pays for opening routes and caches, so it says nothing about the connection: it is thrown away
    private var warmingUp = true
    private let queue = DispatchQueue(label: "com.giuseppe.Notcholino.pinger", qos: .utility)

    override init() {
        super.init()
        probe()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.probe() }
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.probe() }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func pluginWillUnload() { timer?.invalidate(); timer = nil }

    private func probe() {
        guard !inFlight else { return }
        inFlight = true
        let host = target
        let started = DispatchTime.now()
        let connection = NWConnection(host: NWEndpoint.Host(host), port: 443, using: .tcp)
        var finished = false
        let finish: (Double?) -> Void = { [weak self] ms in
            guard !finished else { return }
            finished = true
            connection.cancel()
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                if self.warmingUp { self.warmingUp = false; return }
                self.samples.append(ms)
                if self.samples.count > Self.maxSamples { self.samples.removeFirst(self.samples.count - Self.maxSamples) }
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finish(Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000)
            case .failed, .waiting:
                finish(nil)
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.timeout) { finish(nil) }
    }

    // MARK: Numbers

    private var latest: Double?? { samples.last }
    private var good: [Double] { samples.compactMap { $0 } }
    /// Offline: the last two probes got no answer
    private var offline: Bool { samples.count >= 2 && samples.suffix(2).allSatisfy { $0 == nil } }

    private static func color(forMs ms: Double) -> String {
        ms < 60 ? "#30D158" : ms < 150 ? "#FFD60A" : ms < 300 ? "#FF9F0A" : "#FF453A"
    }

    /// A VPN adds a tunnel interface with an IPv4 address (the others the system keeps have none)
    private static var vpnIsOn: Bool {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return false }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let name = String(cString: entry.pointee.ifa_name)
            let flags = Int32(entry.pointee.ifa_flags)
            if (name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp")),
               flags & IFF_UP != 0, entry.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_INET) { return true }
            cursor = entry.pointee.ifa_next
        }
        return false
    }

    // MARK: Control Center

    var isActive: Bool { true }
    var controlCenterIcon: String { "network" }

    var controlCenterLabel: String {
        if offline { return "OFF" }
        guard let last = latest else { return "…" }
        guard let ms = last else { return "…" }
        return ms >= 1000 ? "1s+" : "\(Int(ms.rounded()))ms"
    }

    var controlCenterTintColor: String {
        if offline { return "#FF453A" }
        guard let last = latest, let ms = last else { return "#8E8E93" }
        return Self.color(forMs: ms)
    }

    var statusText: String { offline ? "No answer from \(target)" : "to \(target)" }

    func menuItems() -> [[String: Any]] {
        var items: [[String: Any]] = []
        if good.count > 1 {
            items.append(["graph": good, "caption": "Last \(max(1, samples.count * Int(Self.interval) / 60)) min", "color": controlCenterTintColor])
        }
        if let average = good.isEmpty ? nil : good.reduce(0, +) / Double(good.count) {
            items.append(["info": "Average", "value": "\(Int(average.rounded())) ms"])
        }
        let lost = samples.filter { $0 == nil }.count
        items.append(["info": "Lost", "value": samples.isEmpty ? "–" : "\(lost) of \(samples.count)"])
        items.append(["info": "VPN", "value": Self.vpnIsOn ? "On" : "Off"])
        items.append(["header": "Measure the way to"])
        for t in Self.targets { items.append(["id": t, "title": t, "checked": target == t]) }
        return items
    }

    func performMenuAction(_ id: String) {
        guard Self.targets.contains(id) else { return }
        UserDefaults.standard.set(id, forKey: Self.targetKey)
        samples = []
        warmingUp = true
        probe()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.probe() }
    }
}
