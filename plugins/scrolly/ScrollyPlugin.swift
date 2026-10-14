import AppKit
import ApplicationServices

/// Scrolly reverses the vertical scroll of a mouse wheel, leaving the trackpad as it is.
/// The "natural scrolling" switch in macOS applies to both together; this lets a wheel mouse scroll the
/// classic way while the trackpad stays natural.
@objc(ScrollyPlugin)
final class ScrollyPlugin: NSObject, NotcholinoPlugin {

    // MARK: Plugin info

    var apiVersion: Int { notcholinoPluginAPIVersion }
    var pluginIdentifier: String { "scrolly" }
    var pluginName: String { "Scrolly" }
    var pluginVersion: String {
        Bundle(for: ScrollyPlugin.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    var pluginAuthor: String { "Giuseppe" }
    var pluginDescription: String { "Reverse the vertical scroll of your mouse wheel, without touching the trackpad." }

    // MARK: State

    private static let enabledKey = "plugin.scrolly.enabled"
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var needsAccess = false

    override init() {
        super.init()
        // Come back on after a relaunch, if it was on
        if UserDefaults.standard.bool(forKey: Self.enabledKey) { enable(prompt: false) }
    }

    var isActive: Bool { tap != nil }
    var controlCenterIcon: String { "arrow.up.arrow.down" }
    var statusText: String {
        if isActive { return "On" }
        if needsAccess && !AXIsProcessTrusted() { return "Allow Accessibility" }
        return "Off"
    }

    // MARK: A simple switch

    func controlCenterButtonTapped() { isActive ? disable() : enable(prompt: true) }

    func menuItems() -> [[String: Any]] {
        [["id": "toggle", "title": isActive ? "Turn off" : "Turn on", "destructive": isActive]]
    }

    func performMenuAction(_ id: String) { controlCenterButtonTapped() }

    func pluginWillUnload() { removeTap() }

    // MARK: The event filter

    private func enable(prompt: Bool) {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            needsAccess = true
            if prompt {
                let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            }
            return
        }
        let mask: CGEventMask = 1 << CGEventType.scrollWheel.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: scrollyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { needsAccess = true; return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        needsAccess = false
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
    }

    private func disable() {
        removeTap()
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
    }

    private func removeTap() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        source = nil
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}

private func scrollyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                             userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo { Unmanaged<ScrollyPlugin>.fromOpaque(userInfo).takeUnretainedValue().reenable() }
        return Unmanaged.passUnretained(event)
    }
    guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
    // A wheel with notches reports "not continuous"; trackpads and Magic Mouse report continuous scrolling.
    if event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 {
        for field: CGEventField in [.scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1] {
            event.setIntegerValueField(field, value: -event.getIntegerValueField(field))
        }
        let fixed = CGEventField.scrollWheelEventFixedPtDeltaAxis1
        event.setDoubleValueField(fixed, value: -event.getDoubleValueField(fixed))
    }
    return Unmanaged.passUnretained(event)
}
