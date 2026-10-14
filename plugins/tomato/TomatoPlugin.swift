import AppKit
import Foundation

/// Tomato is a Pomodoro timer: a stretch of work, a break, and again, until you stop it. You choose how many minutes each
/// lasts. A small clock hangs under the notch and a sound plays when each stretch ends.
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
    private var pill: ClockPill?

    // MARK: Control Center

    var isActive: Bool { endDate != nil }
    var controlCenterIcon: String { "stopwatch" }
    var controlCenterTintColor: String { isActive ? "#FF453A" : "" }

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
        if pill == nil { pill = ClockPill() }
        pill?.show(text: Self.pillText(phase, end.timeIntervalSinceNow), color: Self.pillColor(phase))
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
