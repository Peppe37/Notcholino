// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation

/// Tomato is a Pomodoro timer: a stretch of work, a break, and again, until you stop it. You choose how many minutes each
/// lasts. The notch grows a small strip with the countdown and a sound plays when each stretch ends.
@objc(TomatoPlugin)
final class TomatoPlugin: NSObject, NotcholinoPlugin {

    // MARK: Plugin info

    var apiVersion: Int { notcholinoPluginAPIVersion }
    var pluginIdentifier: String { "tomato" }
    var pluginName: String { "Tomato" }
    var pluginVersion: String {
        Bundle(for: TomatoPlugin.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    var pluginAuthor: String { "Giuseppe" }
    var pluginDescription: String { "A Pomodoro timer: work and break minutes of your choice, repeating, with a clock under the notch and a sound." }

    // MARK: Settings and state

    private enum Key {
        static let work = "plugin.tomato.workMinutes"
        static let rest = "plugin.tomato.breakMinutes"
        static let sound = "plugin.tomato.sound"
    }
    private static let workRange = 1...180
    private static let breakRange = 1...60

    private var workMinutes: Int {
        let v = UserDefaults.standard.integer(forKey: Key.work)
        return Self.workRange.contains(v) ? v : 25
    }
    private var breakMinutes: Int {
        let v = UserDefaults.standard.integer(forKey: Key.rest)
        return Self.breakRange.contains(v) ? v : 5
    }
    private var soundOn: Bool { UserDefaults.standard.object(forKey: Key.sound) as? Bool ?? true }

    private enum Phase { case work, rest }
    private var phase = Phase.work
    private var endDate: Date?
    private var timer: Timer?

    // MARK: Control Center

    var isActive: Bool { endDate != nil }
    var controlCenterIcon: String { "stopwatch" }
    var controlCenterTintColor: String { isActive ? "#FF453A" : "" }

    /// The countdown, in the strip that makes the closed notch a little longer (the break is green, with a cup)
    var notchExtensionText: String {
        guard let end = endDate else { return "" }
        return (phase == .rest ? "☕ " : "") + Self.clock(end.timeIntervalSinceNow)
    }
    var notchExtensionColor: String { phase == .rest ? "#30D158" : "#FFFFFF" }

    var statusText: String {
        guard let end = endDate else { return "" }
        return (phase == .work ? "Work " : "Break ") + Self.clock(end.timeIntervalSinceNow)
    }

    func menuItems() -> [[String: Any]] {
        var items: [[String: Any]] = [
            ["stepper": "Work", "id": "work", "value": workMinutes, "unit": "min", "min": Self.workRange.lowerBound, "max": Self.workRange.upperBound],
            ["stepper": "Break", "id": "break", "value": breakMinutes, "unit": "min", "min": Self.breakRange.lowerBound, "max": Self.breakRange.upperBound],
            isActive ? ["id": "stop", "title": "Stop", "destructive": true] : ["id": "start", "title": "Start"],
            ["id": "sound", "title": "Sound", "checked": soundOn]
        ]
        if isActive { items.insert(["header": "A new stretch starts by itself after each one"], at: 0) }
        return items
    }

    func performMenuAction(_ id: String) {
        let d = UserDefaults.standard
        if id.hasPrefix("work="), let v = Int(id.dropFirst(5)) { d.set(min(max(v, Self.workRange.lowerBound), Self.workRange.upperBound), forKey: Key.work); return }
        if id.hasPrefix("break="), let v = Int(id.dropFirst(6)) { d.set(min(max(v, Self.breakRange.lowerBound), Self.breakRange.upperBound), forKey: Key.rest); return }
        switch id {
        case "start": start()
        case "stop": stop()
        case "sound": d.set(!soundOn, forKey: Key.sound)
        default: break
        }
    }

    func pluginWillUnload() { stop() }

    // MARK: Running

    private func start() {
        guard !isActive else { return }
        begin(.work)
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Starts a stretch of work or of break
    private func begin(_ next: Phase) {
        phase = next
        let end = Date().addingTimeInterval(TimeInterval((next == .work ? workMinutes : breakMinutes) * 60))
        endDate = end
    }

    private func tick() {
        guard let end = endDate else { return }
        let left = end.timeIntervalSinceNow
        if left <= 0 {
            if soundOn { Self.ring() }
            begin(phase == .work ? .rest : .work)
            return
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        endDate = nil
    }


    /// "24:31", or "1:05:00" for an hour or more
    private static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Three rings of a system sound
    private static func ring() {
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.1) {
                (NSSound(named: "Hero") ?? NSSound(named: "Glass"))?.play()
            }
        }
    }
}
