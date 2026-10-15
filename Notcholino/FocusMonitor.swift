// SPDX-License-Identifier: GPL-3.0-only
import Intents
import SwiftUI

/// Whether a Focus (Do Not Disturb and the others) is on. macOS only says "on" or "off", not which one, and only after the
/// user allows it. Reads it every few seconds, and only while it is allowed and switched on in Settings.
final class FocusMonitor: ObservableObject {
    static let shared = FocusMonitor()

    @Published private(set) var isFocused = false
    @Published private(set) var authorization = INFocusStatusCenter.default.authorizationStatus
    /// Allowed, but macOS doesn't tell: the status is unknown (nil), not "off"
    @Published private(set) var notShared = false

    private var timer: Timer?

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "focusMoonEnabled") as? Bool ?? true }

    func start() {
        guard timer == nil else { return }
        refresh()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        let status = INFocusStatusCenter.default.authorizationStatus
        if status != authorization { authorization = status }
        let reported = status == .authorized ? INFocusStatusCenter.default.focusStatus.isFocused : nil
        let unknown = isEnabled && status == .authorized && reported == nil
        if unknown != notShared { notShared = unknown }
        let on = isEnabled && reported == true
        if on != isFocused { isFocused = on }
    }

    /// Shows the system question the first time, or opens System Settings if it was refused
    func requestAccess() {
        if authorization == .notDetermined {
            INFocusStatusCenter.default.requestAuthorization { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Focus") {
            NSWorkspace.shared.open(url)
        }
    }
}
