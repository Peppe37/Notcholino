import AppKit
import EventKit
import Foundation

/// Tomato is a focus timer. Pick a length and a small clock appears just under the notch. When time is up it plays a sound
/// and, if you allow it, your iPhone alerts too.
///
/// There is no public way to make an iPhone ring from a Mac, so the iPhone alert uses what iCloud does share: a Reminder with
/// an alarm at the end time. Your iPhone shows it as a notification with the usual sound, a few seconds late at most. It needs
/// Reminders access, and the default Reminders list to be an iCloud one.
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
    var pluginDescription: String { "A focus timer with a small clock under the notch, a sound at the end and an optional iPhone alert." }

    // MARK: Settings and state

    private enum Key {
        static let sound = "plugin.tomato.sound"
        static let iphone = "plugin.tomato.iphone"
        static let leftoverReminder = "plugin.tomato.reminderID"
    }
    private var soundOn: Bool { UserDefaults.standard.object(forKey: Key.sound) as? Bool ?? true }
    private var iphoneOn: Bool { UserDefaults.standard.bool(forKey: Key.iphone) }

    private static let lengths: [(id: String, title: String, minutes: Int)] = [
        ("5", "5 min", 5), ("10", "10 min", 10), ("15", "15 min", 15),
        ("25", "25 min", 25), ("45", "45 min", 45), ("60", "60 min", 60)
    ]

    private var endDate: Date?
    private var selected: String?
    private var finishedAt: Date?
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
    var controlCenterIcon: String { "timer" }
    var controlCenterTintColor: String { isActive ? "#FF453A" : "" }

    var statusText: String {
        if let message { return message }
        guard let end = endDate else { return "" }
        return Self.clock(end.timeIntervalSinceNow) + " left"
    }

    func menuItems() -> [[String: Any]] {
        var items: [[String: Any]] = [["header": isActive ? "Running" : "Start a timer"]]
        for l in Self.lengths { items.append(["id": l.id, "title": l.title, "checked": selected == l.id]) }
        items.append(["id": "sound", "title": "Sound", "checked": soundOn])
        items.append(["id": "iphone", "title": "iPhone", "checked": iphoneOn])
        if isActive { items.append(["id": "off", "title": "Stop", "destructive": true]) }
        return items
    }

    func performMenuAction(_ id: String) {
        message = nil
        let d = UserDefaults.standard
        switch id {
        case "off": stop()
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
        default:
            if let l = Self.lengths.first(where: { $0.id == id }) { start(minutes: l.minutes, id: id) }
        }
    }

    func pluginWillUnload() { stop() }

    // MARK: Running

    private func start(minutes: Int, id: String) {
        cancelTimerOnly()
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        endDate = end
        selected = id
        finishedAt = nil

        if pill == nil { pill = ClockPill() }
        pill?.show(text: Self.clock(end.timeIntervalSinceNow))

        if iphoneOn, RemindersBridge.isAuthorized, RemindersBridge.usesICloud {
            reminders = RemindersBridge()
            if let id = reminders?.schedule(at: end) { UserDefaults.standard.set(id, forKey: Key.leftoverReminder) }
        }

        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let end = endDate else { return }
        let left = end.timeIntervalSinceNow
        if left <= 0 { finish(); return }
        pill?.update(text: Self.clock(left))
    }

    private func finish() {
        cancelTimerOnly()
        endDate = nil
        selected = nil
        pill?.update(text: "Done", done: true)
        if soundOn { Self.ring() }
        // The iPhone gets its alert from the reminder at this very moment: complete it a bit later
        if let reminders {
            DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
                reminders.removeScheduled()
                UserDefaults.standard.removeObject(forKey: Key.leftoverReminder)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.endDate == nil { self?.pill?.hide() }
        }
    }

    private func stop() {
        cancelTimerOnly()
        endDate = nil
        selected = nil
        pill?.hide()
        reminders?.removeScheduled()
        reminders = nil
        UserDefaults.standard.removeObject(forKey: Key.leftoverReminder)
    }

    private func cancelTimerOnly() {
        timer?.invalidate()
        timer = nil
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

/// A small black pill with the time left, just below the notch. It ignores the mouse, so it never gets in the way.
final class ClockPill {
    private var window: NSPanel?
    private let label = NSTextField(labelWithString: "")

    func show(text: String) {
        if window == nil { build() }
        update(text: text)
        position()
        window?.orderFrontRegardless()
    }

    func update(text: String, done: Bool = false) {
        label.stringValue = done ? "✓ Done" : text
        label.textColor = done ? NSColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1) : .white
        position()
    }

    func hide() { window?.orderOut(nil) }

    private func build() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 66, height: 20),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let box = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.88).cgColor
        box.layer?.cornerRadius = 10
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 2, width: box.bounds.width, height: 15)
        label.autoresizingMask = [.width]
        box.addSubview(label)
        box.autoresizingMask = [.width, .height]
        panel.contentView = box
        window = panel
    }

    /// Centered on the screen with the menu bar, right under the notch (or the menu bar on a Mac without one)
    private func position() {
        guard let window, let screen = NSScreen.screens.first else { return }
        let top = max(screen.safeAreaInsets.top, 24)
        let width: CGFloat = max(66, CGFloat(label.stringValue.count) * 8 + 22)
        let frame = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - top - 4 - 20, width: width, height: 20)
        window.setFrame(frame, display: true)
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
    func schedule(at date: Date) -> String? {
        guard let calendar = Self.store.defaultCalendarForNewReminders() else { return nil }
        let reminder = EKReminder(eventStore: Self.store)
        reminder.calendar = calendar
        reminder.title = "🍅 Tomato: time's up!"
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

    func removeScheduled() {
        guard let identifier else { return }
        Self.remove(identifier: identifier)
        self.identifier = nil
    }

    static func remove(identifier: String) {
        guard isAuthorized, let item = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        try? store.remove(item, commit: true)
    }
}
