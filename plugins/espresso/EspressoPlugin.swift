// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import IOKit.pwr_mgt

/// Espresso keeps your Mac awake (and the screen on) for as long as you choose,
/// like the `caffeinate` command line tool.
@objc(EspressoPlugin)
final class EspressoPlugin: NSObject, NotcholinoPlugin {

    // MARK: Plugin info

    var apiVersion: Int { notcholinoPluginAPIVersion }
    var pluginIdentifier: String { "espresso" }
    var pluginName: String { "Espresso" }
    var pluginVersion: String {
        Bundle(for: EspressoPlugin.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    var pluginAuthor: String { "Giuseppe" }
    var pluginDescription: String { "Keep your Mac and its screen awake, indefinitely or for a set time." }

    // MARK: State

    private var assertionIDs: [IOPMAssertionID] = []
    private var endDate: Date?
    private var timer: Timer?
    /// Id of the option currently running ("indefinite", "1h", "until", ...)
    private var selected: String?

    private static let durations: [(id: String, title: String, seconds: TimeInterval)] = [
        ("10m", "10 min", 10 * 60),
        ("30m", "30 min", 30 * 60),
        ("1h", "1 hour", 60 * 60),
        ("2h", "2 hours", 2 * 60 * 60),
        ("4h", "4 hours", 4 * 60 * 60),
        ("8h", "8 hours", 8 * 60 * 60),
        ("12h", "12 hours", 12 * 60 * 60)
    ]

    var isActive: Bool { !assertionIDs.isEmpty }

    var controlCenterIcon: String { isActive ? "cup.and.saucer.fill" : "cup.and.saucer" }

    var statusText: String {
        guard isActive else { return "" }
        guard let end = endDate else { return "Always on" }
        let left = max(0, Int(end.timeIntervalSinceNow.rounded(.up)))
        if left >= 3600 { return "\(left / 3600)h \((left % 3600) / 60)m left" }
        if left >= 60 { return "\(left / 60)m left" }
        return "\(left)s left"
    }

    // MARK: Menu

    func menuItems() -> [[String: Any]] {
        var items: [[String: Any]] = [
            ["id": "indefinite", "title": "Indefinitely", "checked": selected == "indefinite"]
        ]
        for d in Self.durations {
            items.append(["id": d.id, "title": d.title, "checked": selected == d.id])
        }
        items.append(["id": "until", "title": "Until…", "checked": selected == "until"])
        if isActive {
            items.append(["id": "off", "title": "Turn off", "destructive": true])
        }
        return items
    }

    func performMenuAction(_ id: String) {
        switch id {
        case "off":
            stop()
        case "indefinite":
            start(duration: nil, id: id)
        case "until":
            askUntil()
        default:
            if let d = Self.durations.first(where: { $0.id == id }) {
                start(duration: d.seconds, id: id)
            }
        }
    }

    func pluginWillUnload() { stop() }

    // MARK: Power assertions

    private func start(duration: TimeInterval?, id: String) {
        stop()
        // Display assertion keeps the screen on; the system one keeps the Mac from idle sleep
        for type in [kIOPMAssertPreventUserIdleDisplaySleep, kIOPMAssertPreventUserIdleSystemSleep] {
            var assertionID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Notcholino Espresso" as CFString, &assertionID)
            if result == kIOReturnSuccess { assertionIDs.append(assertionID) }
        }
        guard isActive else { return }
        selected = id
        if let duration {
            endDate = Date().addingTimeInterval(duration)
            let t = Timer(timeInterval: duration, repeats: false) { [weak self] _ in self?.stop() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        selected = nil
        assertionIDs.forEach { IOPMAssertionRelease($0) }
        assertionIDs.removeAll()
    }

    // MARK: "Until…"

    private func askUntil() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Keep awake until…"
        alert.informativeText = "Your Mac may sleep again at the time you pick."
        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 110, height: 28))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        picker.dateValue = Date().addingTimeInterval(60 * 60)
        alert.accessoryView = picker
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Today at the chosen time, or tomorrow if that time has already passed
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: picker.dateValue)
        guard var target = cal.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: Date()) else { return }
        if target <= Date() { target = cal.date(byAdding: .day, value: 1, to: target) ?? target }
        start(duration: target.timeIntervalSinceNow, id: "until")
    }
}
