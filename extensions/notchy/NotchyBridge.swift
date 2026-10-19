// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

/// What Notchy asks of the app. The app hands over a `NotcholinoHost` when it loads the extension; everything Notchy does with
/// popups, the calendar, the music player and the other plugins goes through here.
final class NotchyBridge {
    static let shared = NotchyBridge()
    var host: NotcholinoHost?

    func popup(icon: String? = nil, title: String, subtitle: String? = nil, tint: Color = .white, seconds: Double = 3, opensPage: Bool = false) {
        var info: [String: Any] = ["title": title, "seconds": seconds, "opensPage": opensPage]
        if let icon { info["icon"] = icon }
        if let subtitle { info["subtitle"] = subtitle }
        if let c = NSColor(tint).usingColorSpace(.sRGB) {
            info["color"] = String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
        }
        host?.showPopup(info)
    }

    func dismissPopup() { host?.dismissPopup() }
    func setWing(_ visible: Bool) { host?.setWingVisible(visible) }
    func agendaLines() -> [String] { host?.agendaLines() ?? [] }
    func nextEventLine() -> String? { host?.nextEventLine() }
    func hasCalendarAccess() -> Bool { host?.hasCalendarAccess() ?? false }
    func isMusicPlaying() -> Bool { host?.isMusicPlaying() ?? false }
    func activePluginIDs() -> [String] { host?.activePluginIDs() ?? [] }
}
