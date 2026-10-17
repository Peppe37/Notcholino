// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
import IOKit
import IOKit.ps

/// CloseMe keeps your Mac running when you close the lid, and turns the screen brightness to zero when it sees the lid
/// close, so the display doesn't heat up shut inside the lid.
///
/// macOS has no setting for this that works without admin rights: no power assertion stops the Mac from sleeping when the
/// lid closes on battery (Apple's own documentation says so). The one switch that does is `pmset disablesleep`, which needs
/// an administrator password. It is a global setting that macOS keeps across restarts, so CloseMe is built so that it can
/// never be left on:
///
/// - It only touches the setting if it was off, and it puts back exactly what it found (off).
/// - A small watchdog, started as root together with it, switches it off again as soon as any of these happens: you turn
///   CloseMe off, Notcholino quits (⌘Q, logout, update, a plugin removal) or crashes, or 12 hours have passed.
/// - A one-shot job (a launch daemon) is installed with it and removed when it ends: if the Mac restarts while it is on,
///   the job switches the setting off at boot.
/// - If something still goes wrong, Notcholino notices at the next launch and the options offer "Restore sleep".
/// CloseMe also stops by itself when the battery is nearly empty and the Mac is not plugged in.
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
    /// Whether this session switched the setting on (and so has to give it back)
    private var ownsSetting = false
    private var endDate: Date?
    private var selected: String?
    private var lidClosed = false
    private var message: String?
    private var timer: Timer?
    private var ticks = 0
    private var terminationObserver: NSObjectProtocol?

    private var flagPath: String { "/tmp/notcholino-closeme-\(getpid()).flag" }

    private static let daemonLabel = "com.giuseppe.Notcholino.closeme-reset"
    private static let daemonPath = "/Library/LaunchDaemons/com.giuseppe.Notcholino.closeme-reset.plist"
    private static var sessionFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notcholino/closeme-session.json")
    }
    /// True when an earlier session left the setting on and nothing of ours is running: the options offer to fix it
    private var orphaned = false
    private var popup: (([String: Any]) -> Void)?

    func setPopupHandler(_ handler: @escaping ([String: Any]) -> Void) { popup = handler }

    override init() {
        super.init()
        // If a previous run was cut short while the lid was closed, the brightness may still be at zero
        if !Self.isLidClosed(), let saved = UserDefaults.standard.object(forKey: Self.savedBrightnessKey) as? Float {
            BuiltInDisplay.setLevel(saved)
            UserDefaults.standard.removeObject(forKey: Self.savedBrightnessKey)
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in self?.stop() }
        checkLeftovers()
    }

    /// A session that was cut short (a crash, a force quit, a restart): did it leave the setting on?
    private func checkLeftovers() {
        guard let data = try? Data(contentsOf: Self.sessionFile),
              let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let pid = (info["pid"] as? Int).map(pid_t.init) ?? 0
        if pid > 0, pid != getpid(), kill(pid, 0) == 0 { return }       // that session is still running
        if Self.sleepIsDisabled() {
            orphaned = true
            // The watchdog normally fixed it already; if it is still on, say so
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self, self.orphaned else { return }
                self.popup?(["title": "CloseMe left sleep switched off", "subtitle": "Open CloseMe and choose Restore sleep",
                             "icon": "exclamationmark.triangle.fill", "color": "#FF9F0A", "seconds": 8.0])
            }
        } else {
            try? FileManager.default.removeItem(at: Self.sessionFile)
        }
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
        var items: [[String: Any]] = []
        if !active && !waitingForPassword && Self.sleepIsDisabled() {
            items.append(["header": "Sleep is switched off on this Mac (SleepDisabled). If CloseMe is off, this is a leftover."])
            items.append(["id": "restore", "title": "Restore sleep (needs your password)", "wide": true])
        }
        items.append(["header": active
            ? "Your Mac keeps running with the lid closed. Never put it in a bag like this."
            : "Keep running with the lid closed for. While on, it changes a macOS setting that is restored when you stop it or quit Notcholino."])
        for d in Self.durations {
            items.append(["id": d.id, "title": d.title, "checked": selected == d.id])
        }
        if active { items.append(["id": "off", "title": "Turn off", "destructive": true]) }
        return items
    }

    func performMenuAction(_ id: String) {
        message = nil
        if id == "off" { stop(); return }
        if id == "restore" { restoreSleep(); return }
        guard let d = Self.durations.first(where: { $0.id == id }) else { return }
        selected = id
        endDate = Date().addingTimeInterval(d.seconds)
        if !active { start() }   // already on: only the end time changes, no new password needed
    }

    func pluginWillUnload() { stop() }

    // MARK: Turning it on

    private func start() {
        guard !waitingForPassword else { return }

        // Already off by someone else (another app, or a leftover): not ours to change and not ours to restore
        if Self.sleepIsDisabled() {
            ownsSetting = false
            active = true
            lidClosed = Self.isLidClosed()
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            return
        }

        waitingForPassword = true
        ownsSetting = true
        FileManager.default.createFile(atPath: flagPath, contents: Data())

        let pid = getpid()
        let deadline = Int(Date().addingTimeInterval(Self.hardLimit).timeIntervalSince1970)
        // The watchdog is a launchd job, not a background process started by the password dialog: macOS ends the processes
        // that dialog starts as soon as it is done, which left sleep switched off with nothing to switch it back on.
        // launchd keeps the job alive, and starts it again at boot: after a restart the flag in /tmp is gone, so it switches
        // sleep back on at once.
        let loop = "while /bin/kill -0 \(pid) 2>/dev/null && [ -e \(flagPath) ] && [ $(/bin/date +%s) -lt \(deadline) ]; do /bin/sleep 2; done; /usr/bin/pmset -a disablesleep 0; /bin/rm -f \(Self.daemonPath); /bin/launchctl bootout system/\(Self.daemonLabel)"
        let daemon = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Label</key><string>\(Self.daemonLabel)</string>
        <key>RunAtLoad</key><true/>
        <key>ProgramArguments</key><array><string>/bin/sh</string><string>-c</string>
        <string>\(loop)</string></array>
        </dict></plist>
        """
        let daemonSource = "/tmp/notcholino-closeme-\(pid).plist"
        try? daemon.write(toFile: daemonSource, atomically: true, encoding: .utf8)
        // As root: put the job in place, switch sleep off, start the job. If anything fails, sleep is put back at once.
        let shell = "/usr/bin/install -m 644 -o root -g wheel \(daemonSource) \(Self.daemonPath) && /usr/bin/pmset -a disablesleep 1 && /bin/launchctl bootstrap system \(Self.daemonPath) || { /usr/bin/pmset -a disablesleep 0; /bin/rm -f \(Self.daemonPath); exit 1; }"
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
            try? FileManager.default.removeItem(atPath: daemonSource)
        }
    }

    private func didAskForPassword(success: Bool, errorText: String) {
        waitingForPassword = false
        try? FileManager.default.removeItem(atPath: "/tmp/notcholino-closeme-\(getpid()).plist")
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
        writeSession()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Written while the setting is ours, removed when it is given back: it is how a later launch knows a session was cut short
    private func writeSession() {
        let info: [String: Any] = ["pid": Int(getpid()), "started": Date().timeIntervalSince1970, "previous": false]
        if let data = try? JSONSerialization.data(withJSONObject: info) { try? data.write(to: Self.sessionFile, options: .atomic) }
    }

    /// Switches sleep back on by hand, for a setting an earlier session left behind
    private func restoreSleep() {
        let shell = "/usr/bin/pmset -a disablesleep 0; /bin/launchctl bootout system/\(Self.daemonLabel) 2>/dev/null; /bin/rm -f \(Self.daemonPath)"
        let script = "do shell script \"\(shell)\" with prompt \"CloseMe puts your Mac's sleep back on.\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if Self.sleepIsDisabled() { self.message = "Could not restore sleep" }
                else {
                    self.orphaned = false
                    try? FileManager.default.removeItem(at: Self.sessionFile)
                    self.popup?(["title": "Sleep restored", "subtitle": "Your Mac can sleep again", "icon": "checkmark.circle.fill", "color": "#30D158"])
                }
            }
        }
        try? process.run()
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
        let owned = ownsSetting
        if ownsSetting { try? FileManager.default.removeItem(at: Self.sessionFile); ownsSetting = false }
        if owned {
            // Trust, but check: if sleep is still off a few seconds later, say so and offer the button to put it back
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self, !self.active, Self.sleepIsDisabled() else { return }
                self.orphaned = true
                self.popup?(["title": "Sleep is still switched off", "subtitle": "Open CloseMe and choose Restore sleep",
                             "icon": "exclamationmark.triangle.fill", "color": "#FF9F0A", "seconds": 10.0])
            }
        }
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
