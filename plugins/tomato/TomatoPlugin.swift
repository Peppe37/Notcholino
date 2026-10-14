import AppKit
import EventKit
import Foundation

/// Tomato is a Pomodoro timer: a stretch of work, a break, and again, until you stop it. You choose how many minutes each
/// lasts. A small clock hangs under the notch, a sound plays when each stretch ends, and, if you allow it, your iPhone is
/// alerted too.
///
/// An iPhone can't be rung from a Mac: no public API sets an alarm on it. What iCloud does share is a Reminder with an alarm,
/// so the iPhone alert is a notification from a Reminder due when the current stretch ends. It is created for the next switch
/// only, and removed again shortly after, so the list doesn't fill up. It needs Reminders access, and the default Reminders
/// list to be an iCloud one.
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
        static let iphone = "plugin.tomato.iphone"
        static let leftoverReminder = "plugin.tomato.reminderID"
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
    private var iphoneOn: Bool { UserDefaults.standard.bool(forKey: Key.iphone) }

    private enum Phase { case work, rest }
    private var phase = Phase.work
    private var endDate: Date?
    private var timer: Timer?
    private var pill: ClockPill?
    private var reminders: RemindersBridge?
    private var message: String?

    override init() {
        super.init()
        // An iPhone alert left behind by a previous run (the app quit while a timer was running)
        if let id = UserDefaults.standard.string(forKey: Key.leftoverReminder) {
            RemindersBridge.remove(identifier: id)
            UserDefaults.standard.removeObject(forKey: Key.leftoverReminder)
        }
    }

    // MARK: Control Center

    var isActive: Bool { endDate != nil }
    var controlCenterIcon: String { "stopwatch" }
    var controlCenterTintColor: String { isActive ? "#FF453A" : "" }

    var statusText: String {
        if let message { return message }
        guard let end = endDate else { return "" }
        return (phase == .work ? "Work " : "Break ") + Self.clock(end.timeIntervalSinceNow)
    }

    func menuItems() -> [[String: Any]] {
        var items: [[String: Any]] = [
            ["stepper": "Work", "id": "work", "value": workMinutes, "unit": "min", "min": Self.workRange.lowerBound, "max": Self.workRange.upperBound],
            ["stepper": "Break", "id": "break", "value": breakMinutes, "unit": "min", "min": Self.breakRange.lowerBound, "max": Self.breakRange.upperBound],
            isActive ? ["id": "stop", "title": "Stop", "destructive": true] : ["id": "start", "title": "Start"],
            ["id": "sound", "title": "Sound", "checked": soundOn],
            ["id": "iphone", "title": "iPhone", "checked": iphoneOn]
        ]
        if isActive { items.insert(["header": "A new stretch starts by itself after each one"], at: 0) }
        return items
    }

    func performMenuAction(_ id: String) {
        message = nil
        let d = UserDefaults.standard
        if id.hasPrefix("work="), let v = Int(id.dropFirst(5)) { d.set(min(max(v, Self.workRange.lowerBound), Self.workRange.upperBound), forKey: Key.work); return }
        if id.hasPrefix("break="), let v = Int(id.dropFirst(6)) { d.set(min(max(v, Self.breakRange.lowerBound), Self.breakRange.upperBound), forKey: Key.rest); return }
        switch id {
        case "start": start()
        case "stop": stop()
        case "sound": d.set(!soundOn, forKey: Key.sound)
        case "iphone":
            let turningOn = !iphoneOn
            d.set(turningOn, forKey: Key.iphone)
            if turningOn {
                RemindersBridge.requestAccess { [weak self] ok in
                    if !ok {
                        d.set(false, forKey: Key.iphone)
                        self?.message = "Allow Notcholino in Reminders to alert your iPhone"
                    } else if !RemindersBridge.usesICloud {
                        self?.message = "Turn on iCloud Reminders so your iPhone gets the alert"
                    }
                }
            }
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

    /// Starts a stretch of work or of break, and gets the iPhone alert ready for its end
    private func begin(_ next: Phase) {
        phase = next
        let end = Date().addingTimeInterval(TimeInterval((next == .work ? workMinutes : breakMinutes) * 60))
        endDate = end
        if pill == nil { pill = ClockPill() }
        pill?.show(text: Self.pillText(phase, end.timeIntervalSinceNow), color: Self.pillColor(phase))

        reminders?.removeScheduled(after: 60)
        reminders = nil
        if iphoneOn, RemindersBridge.isAuthorized, RemindersBridge.usesICloud {
            let bridge = RemindersBridge()
            let title = next == .work ? "🍅 Break over: back to work" : "🍅 Time for a break"
            if let id = bridge.schedule(at: end, title: title) { UserDefaults.standard.set(id, forKey: Key.leftoverReminder) }
            reminders = bridge
        }
    }

    private func tick() {
        guard let end = endDate else { return }
        let left = end.timeIntervalSinceNow
        if left <= 0 {
            if soundOn { Self.ring() }
            begin(phase == .work ? .rest : .work)
            return
        }
        pill?.update(text: Self.pillText(phase, left), color: Self.pillColor(phase))
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        pill?.hide()
        reminders?.removeScheduled(after: 0)
        reminders = nil
        UserDefaults.standard.removeObject(forKey: Key.leftoverReminder)
    }

    private static func pillText(_ phase: Phase, _ seconds: TimeInterval) -> String {
        (phase == .rest ? "☕ " : "") + clock(seconds)
    }

    private static func pillColor(_ phase: Phase) -> NSColor {
        phase == .rest ? NSColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1) : .white
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

// MARK: - The clock under the notch

/// The time left, in a black tab that hangs from the bottom of the notch, as if the notch itself grew a little.
/// It ignores the mouse, so it never gets in the way.
final class ClockPill {
    private var window: NSPanel?
    private let shape = TabShape()
    private let label = NSTextField(labelWithString: "")

    private let flare: CGFloat = 6          // the concave curves where the tab meets the notch
    private let gap: CGFloat = 6            // from the bottom of the notch to the clock
    private let clockHeight: CGFloat = 20
    private let bottomPadding: CGFloat = 4
    private var panelHeight: CGFloat { gap + clockHeight + bottomPadding }

    func show(text: String, color: NSColor = .white) {
        if window == nil { build() }
        update(text: text, color: color)
        position()
        window?.orderFrontRegardless()
    }

    func update(text: String, color: NSColor = .white) {
        label.stringValue = text
        label.textColor = color
        position()
    }

    func hide() { window?.orderOut(nil) }

    private func build() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 80, height: panelHeight),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        shape.flare = flare
        shape.frame = NSRect(x: 0, y: 0, width: 80, height: panelHeight)
        shape.autoresizingMask = [.width, .height]
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.alignment = .center
        shape.addSubview(label)
        panel.contentView = shape
        window = panel
    }

    /// Centered on the screen with the menu bar, starting right at the bottom of the notch (or the menu bar on a Mac without one)
    private func position() {
        guard let window, let screen = NSScreen.screens.first else { return }
        let top = max(screen.safeAreaInsets.top, 24)
        let body = max(66, CGFloat(label.stringValue.count) * 8 + 22)
        let width = body + flare * 2
        let frame = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - top - panelHeight + 1,
                           width: width, height: panelHeight)
        window.setFrame(frame, display: true)
        // The clock sits `gap` below the notch (the panel's top edge is 1 pt inside it)
        label.frame = NSRect(x: flare, y: gap + (clockHeight - 15) / 2, width: body, height: 15)
        shape.needsDisplay = true
    }
}

/// Black, flat on top where it joins the notch (with a small concave curve on each side) and rounded at the bottom
private final class TabShape: NSView {
    var flare: CGFloat = 6
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width, h = bounds.height, f = flare, r: CGFloat = 10
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 0))
        path.line(to: NSPoint(x: w, y: 0))
        path.curve(to: NSPoint(x: w - f, y: f), controlPoint1: NSPoint(x: w - f, y: 0), controlPoint2: NSPoint(x: w - f, y: 0))
        path.line(to: NSPoint(x: w - f, y: h - r))
        path.curve(to: NSPoint(x: w - f - r, y: h), controlPoint1: NSPoint(x: w - f, y: h - r / 2), controlPoint2: NSPoint(x: w - f - r / 2, y: h))
        path.line(to: NSPoint(x: f + r, y: h))
        path.curve(to: NSPoint(x: f, y: h - r), controlPoint1: NSPoint(x: f + r / 2, y: h), controlPoint2: NSPoint(x: f, y: h - r / 2))
        path.line(to: NSPoint(x: f, y: f))
        path.curve(to: NSPoint(x: 0, y: 0), controlPoint1: NSPoint(x: f, y: 0), controlPoint2: NSPoint(x: f, y: 0))
        path.close()
        NSColor.black.setFill()
        path.fill()
    }
}

// MARK: - iPhone alert through iCloud Reminders

final class RemindersBridge {
    private static let store = EKEventStore()
    private var identifier: String?

    static var isAuthorized: Bool {
        let s = EKEventStore.authorizationStatus(for: .reminder)
        return s == .fullAccess || s == .authorized
    }

    /// An alert only reaches the iPhone if the Reminders list syncs through iCloud
    static var usesICloud: Bool {
        guard let calendar = store.defaultCalendarForNewReminders() else { return false }
        return calendar.source.sourceType == .calDAV
    }

    static func requestAccess(_ done: @escaping (Bool) -> Void) {
        if isAuthorized { DispatchQueue.main.async { done(true) }; return }
        store.requestFullAccessToReminders { granted, _ in DispatchQueue.main.async { done(granted) } }
    }

    /// Creates a reminder due at `date`, with an alarm at that moment. Returns its identifier.
    func schedule(at date: Date, title: String) -> String? {
        guard let calendar = Self.store.defaultCalendarForNewReminders() else { return nil }
        let reminder = EKReminder(eventStore: Self.store)
        reminder.calendar = calendar
        reminder.title = title
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        reminder.addAlarm(EKAlarm(absoluteDate: date))
        do {
            try Self.store.save(reminder, commit: true)
            identifier = reminder.calendarItemIdentifier
            return identifier
        } catch {
            return nil
        }
    }

    /// Removes the reminder after a delay (the iPhone needs the alarm to fire first)
    func removeScheduled(after seconds: TimeInterval) {
        guard let identifier else { return }
        self.identifier = nil
        if seconds <= 0 { Self.remove(identifier: identifier); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { Self.remove(identifier: identifier) }
    }

    static func remove(identifier: String) {
        guard isAuthorized, let item = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        try? store.remove(item, commit: true)
    }
}
