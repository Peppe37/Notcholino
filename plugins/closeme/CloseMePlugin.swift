import AppKit
import Foundation
import IOKit
import IOKit.ps

/// CloseMe keeps your Mac running when you close the lid, and turns the screen brightness to zero when it sees the lid
/// close, so the display doesn't heat up shut inside the lid.
///
/// macOS has no setting for this that works without admin rights: no power assertion stops the Mac from sleeping when the
/// lid closes (Apple's own documentation says so). The one switch that does is `pmset disablesleep`, which needs an
/// administrator password. It stays on until it is switched off again, so CloseMe never leaves it on by itself:
/// a small watchdog, started together with it as root, switches it back off as soon as any of these happens:
/// you turn CloseMe off, Notcholino quits or crashes, or 12 hours have passed. CloseMe also stops by itself when the
/// battery is nearly empty and the Mac is not plugged in.
@objc(CloseMePlugin)
final class CloseMePlugin: NSObject, NotcholinoPlugin {

    // MARK: Plugin info

    var apiVersion: Int { notcholinoPluginAPIVersion }
    var pluginIdentifier: String { "closeme" }
    var pluginName: String { "CloseMe" }
    var pluginVersion: String {
        Bundle(for: CloseMePlugin.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    var pluginAuthor: String { "Giuseppe" }
    var pluginDescription: String { "Close the lid and keep the Mac running. The screen goes dark so it doesn't overheat." }

    // MARK: State

    private static let savedBrightnessKey = "plugin.closeme.savedBrightness"
    /// The watchdog's last resort: it gives up and restores sleep after this long
    private static let hardLimit: TimeInterval = 12 * 3600
    private static let batteryStopLevel = 10

    private static let durations: [(id: String, title: String, seconds: TimeInterval)] = [
        ("1h", "1 hour", 3600), ("2h", "2 hours", 2 * 3600), ("4h", "4 hours", 4 * 3600),
        ("8h", "8 hours", 8 * 3600), ("12h", "12 hours", 12 * 3600)
    ]

    private var active = false
    private var waitingForPassword = false
    private var endDate: Date?
    private var selected: String?
    private var lidClosed = false
    private var message: String?
    private var timer: Timer?
    private var ticks = 0
    private var terminationObserver: NSObjectProtocol?

    private var flagPath: String { "/tmp/notcholino-closeme-\(getpid()).flag" }

    override init() {
        super.init()
        // If a previous run was cut short while the lid was closed, the brightness may still be at zero
        if !Self.isLidClosed(), let saved = UserDefaults.standard.object(forKey: Self.savedBrightnessKey) as? Float {
            BuiltInDisplay.setLevel(saved)
            UserDefaults.standard.removeObject(forKey: Self.savedBrightnessKey)
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in self?.stop() }
    }

    // MARK: Control Center

    var isActive: Bool { active }
    var controlCenterIcon: String { active ? "laptopcomputer.and.arrow.down" : "laptopcomputer" }

    var statusText: String {
        if waitingForPassword { return "Waiting for password…" }
        if let message { return message }
        guard active else { return "" }
        if lidClosed { return "Lid closed, screen off" }
        guard let end = endDate else { return "On" }
        let left = max(0, Int(end.timeIntervalSinceNow.rounded(.up)))
        return left >= 3600 ? "\(left / 3600)h \((left % 3600) / 60)m left" : "\(max(left / 60, 1))m left"
    }

    func menuItems() -> [[String: Any]] {
        var items: [[String: Any]] = [["header": active
            ? "Your Mac keeps running with the lid closed. Never put it in a bag like this."
            : "Keep running with the lid closed for"]]
        for d in Self.durations {
            items.append(["id": d.id, "title": d.title, "checked": selected == d.id])
        }
        if active { items.append(["id": "off", "title": "Turn off", "destructive": true]) }
        return items
    }

    func performMenuAction(_ id: String) {
        message = nil
        if id == "off" { stop(); return }
        guard let d = Self.durations.first(where: { $0.id == id }) else { return }
        selected = id
        endDate = Date().addingTimeInterval(d.seconds)
        if !active { start() }   // already on: only the end time changes, no new password needed
    }

    func pluginWillUnload() { stop() }

    // MARK: Turning it on

    private func start() {
        guard !waitingForPassword else { return }
        waitingForPassword = true
        FileManager.default.createFile(atPath: flagPath, contents: Data())

        let pid = getpid()
        let deadline = Int(Date().addingTimeInterval(Self.hardLimit).timeIntervalSince1970)
        // Runs as root: switch sleep off, then leave a watchdog that switches it back on when it must
        let watchdog = "while /bin/kill -0 \(pid) 2>/dev/null && [ -e \(flagPath) ] && [ $(/bin/date +%s) -lt \(deadline) ]; do /bin/sleep 2; done; /usr/bin/pmset -a disablesleep 0"
        let shell = "/usr/bin/pmset -a disablesleep 1 && { /usr/bin/nohup /bin/sh -c '\(watchdog)' > /dev/null 2>&1 & }"
        let script = "do shell script \"\(shell)\" with prompt \"CloseMe keeps your Mac running when the lid is closed.\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = Pipe()
        let errors = Pipe()
        process.standardError = errors
        process.terminationHandler = { [weak self] proc in
            let text = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async { self?.didAskForPassword(success: proc.terminationStatus == 0, errorText: text) }
        }
        do { try process.run() } catch {
            waitingForPassword = false
            message = "Could not ask for permission"
            try? FileManager.default.removeItem(atPath: flagPath)
        }
    }

    private func didAskForPassword(success: Bool, errorText: String) {
        waitingForPassword = false
        guard success, Self.sleepIsDisabled() else {
            // -128 is "cancelled"
            message = errorText.contains("-128") ? nil : "Could not turn on"
            selected = nil
            endDate = nil
            try? FileManager.default.removeItem(atPath: flagPath)
            return
        }
        active = true
        lidClosed = Self.isLidClosed()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: While it is on

    private func tick() {
        ticks += 1
        if let end = endDate, Date() >= end { stop(); return }
        if ticks % 20 == 0, Self.batteryIsNearlyEmpty() {
            stop()
            message = "Stopped: battery low"
            return
        }
        let closed = Self.isLidClosed()
        if closed && !lidClosed {
            // The lid has just closed: remember the brightness, then turn the screen off
            if let level = BuiltInDisplay.level, level > 0 {
                UserDefaults.standard.set(level, forKey: Self.savedBrightnessKey)
            }
            BuiltInDisplay.setLevel(0)
        } else if closed, (BuiltInDisplay.level ?? 0) > 0 {
            BuiltInDisplay.setLevel(0)             // something raised it again
        } else if !closed && lidClosed {
            restoreBrightness()
        }
        lidClosed = closed
    }

    private func restoreBrightness() {
        if let saved = UserDefaults.standard.object(forKey: Self.savedBrightnessKey) as? Float {
            BuiltInDisplay.setLevel(saved)
            UserDefaults.standard.removeObject(forKey: Self.savedBrightnessKey)
        }
    }

    // MARK: Turning it off

    private func stop() {
        timer?.invalidate()
        timer = nil
        // The watchdog sees the flag is gone and switches sleep back on within two seconds
        try? FileManager.default.removeItem(atPath: flagPath)
        if active { restoreBrightness() }
        active = false
        selected = nil
        endDate = nil
        lidClosed = false
    }

    // MARK: System state

    /// Whether `pmset disablesleep` is on (the Mac then shows "SleepDisabled 1")
    private static func sleepIsDisabled() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g"]
        let out = Pipe()
        p.standardOutput = out
        try? p.run()
        p.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return text.split(separator: "\n").contains { $0.contains("SleepDisabled") && $0.trimmingCharacters(in: .whitespaces).hasSuffix("1") }
    }

    static func isLidClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        return (value as? Bool) ?? false
    }

    private static func batteryIsNearlyEmpty() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue,
                  let level = d[kIOPSCurrentCapacityKey] as? Int else { continue }
            if level <= batteryStopLevel { return true }
        }
        return false
    }
}

/// Brightness of the built-in display (DisplayServices, a private framework looked up by name)
private enum BuiltInDisplay {
    private typealias GetFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getFunc: GetFunc? = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: GetFunc.self) }
    private static let setFunc: SetFunc? = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: SetFunc.self) }

    private static var displayID: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        // "Online" also lists a display that is asleep, which the built-in one may be with the lid closed
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static var level: Float? {
        guard let id = displayID, let getFunc else { return nil }
        var value: Float = 0
        return getFunc(id, &value) == 0 ? value : nil
    }

    static func setLevel(_ value: Float) {
        guard let id = displayID, let setFunc else { return }
        _ = setFunc(id, value)
    }
}
