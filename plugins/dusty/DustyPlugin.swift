import AppKit
import ApplicationServices
import Foundation
import IOKit.pwr_mgt

/// Dusty is a clean mode. Pick 5 to 60 seconds: the screen goes black and the keyboard, the trackpad and the mouse stop
/// responding, so you can wipe them without pressing anything by mistake. ⌘⇧C ends it at once.
///
/// It needs the Accessibility permission to be able to ignore the keyboard and the pointer. If the permission is missing,
/// the screen is NOT blackened (you would be unable to tell why nothing works). The power button and Touch ID can't be
/// blocked, and macOS itself ends a blocking tap that stops answering.
@objc(DustyPlugin)
final class DustyPlugin: NSObject, NotcholinoPlugin {

    // MARK: Plugin info

    var apiVersion: Int { notcholinoPluginAPIVersion }
    var pluginIdentifier: String { "dusty" }
    var pluginName: String { "Dusty" }
    var pluginVersion: String {
        Bundle(for: DustyPlugin.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    var pluginAuthor: String { "Giuseppe" }
    var pluginDescription: String { "Clean mode: black screen and a locked keyboard and trackpad for 5 to 60 seconds. ⌘⇧C ends it." }

    // MARK: State

    private static let seconds = [5, 10, 15, 20, 30, 45, 60]

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var overlays: [NSWindow] = []
    private var countdowns: [NSTextField] = []
    private var endDate: Date?
    private var timer: Timer?
    private var assertion = IOPMAssertionID(0)
    private var message: String?
    private var terminationObserver: NSObjectProtocol?

    override init() {
        super.init()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in self?.finish() }
    }

    // MARK: Control Center

    var isActive: Bool { endDate != nil }
    var controlCenterIcon: String { "sparkles" }
    var statusText: String {
        if let message { return message }
        guard let end = endDate else { return "" }
        return "\(max(0, Int(end.timeIntervalSinceNow.rounded(.up)))) s left"
    }

    func menuItems() -> [[String: Any]] {
        var items: [[String: Any]] = [["header": "Lock keyboard, trackpad and screen for"]]
        for s in Self.seconds { items.append(["id": "\(s)", "title": "\(s) s"]) }
        return items
    }

    func performMenuAction(_ id: String) {
        message = nil
        guard !isActive, let s = Int(id) else { return }
        start(seconds: s)
    }

    func pluginWillUnload() { finish() }

    // MARK: Start and stop

    private func start(seconds: Int) {
        guard AXIsProcessTrusted() else {
            message = "Allow Notcholino in Accessibility first"
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            return
        }
        guard installTap() else { message = "Could not lock the keyboard"; return }

        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        // Ignored input doesn't count as activity: keep the display from going to sleep in the middle of it
        IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "Notcholino Dusty" as CFString, &assertion)
        showOverlays()

        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let end = endDate else { return }
        let left = end.timeIntervalSinceNow
        if left <= 0 { finish(); return }
        let text = "\(Int(left.rounded(.up))) s      ⌘⇧C to cancel"
        countdowns.forEach { $0.stringValue = text }
    }

    /// Ends the clean mode: input and screen come back
    fileprivate func finish() {
        timer?.invalidate()
        timer = nil
        removeTap()
        hideOverlays()
        if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
        endDate = nil
    }

    // MARK: Ignoring the keyboard and the pointer

    private func installTap() -> Bool {
        guard tap == nil else { return true }
        // Every kind of event: keys, the pointer, scrolling, gestures, media keys
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: ~CGEventMask(0), callback: dustyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    private func removeTap() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        source = nil
    }

    fileprivate func reenableTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    // MARK: The black screen

    private func showOverlays() {
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.alphaValue = 0

            let label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: 15, weight: .medium)
            label.textColor = NSColor.white.withAlphaComponent(0.28)
            label.alignment = .center
            label.frame = NSRect(x: 0, y: 36, width: screen.frame.width, height: 22)
            window.contentView?.addSubview(label)

            window.orderFrontRegardless()
            window.animator().alphaValue = 1
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.25; window.animator().alphaValue = 1 }
            overlays.append(window)
            countdowns.append(label)
        }
        tick()
    }

    private func hideOverlays() {
        let windows = overlays
        overlays = []
        countdowns = []
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            windows.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { windows.forEach { $0.orderOut(nil) } })
    }
}

private func dustyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                           userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let plugin = Unmanaged<DustyPlugin>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        plugin.reenableTap()
        return Unmanaged.passUnretained(event)
    }
    // ⌘⇧C ends it at once (key code 8 is "C")
    if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 8 {
        let f = event.flags
        if f.contains(.maskCommand) && f.contains(.maskShift) && !f.contains(.maskControl) && !f.contains(.maskAlternate) {
            DispatchQueue.main.async { plugin.finish() }
        }
    }
    return nil   // everything else is swallowed
}
