// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

/// Snap: grab a window and the notch opens with a small screen to drop it on, to put it on a half, a quarter or the whole screen.
@objc(SnapExtension)
final class SnapExtension: NSObject, NotcholinoExtension {
    var apiVersion: Int { notcholinoExtensionAPIVersion }
    var extensionIdentifier: String { "snap" }
    var extensionName: String { "Snap" }
    var extensionVersion: String { Bundle(for: SnapExtension.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    var extensionAuthor: String { "Giuseppe" }
    var extensionDescription: String { "Grab a window and the notch opens: drop it on a half, a corner or the whole screen." }
    var extensionSymbol: String { "rectangle.split.2x2" }

    /// Its page in the notch only opens by itself while a window is grabbed, so it does not take a place among the pages
    var pageVisible: Bool { false }

    func setHost(_ host: NotcholinoHost) { SnapBridge.shared.host = host }

    func makePageView() -> NSView { SnapHostingView(rootView: SnapPage()) }
    func makeSettingsView() -> NSView { NSHostingView(rootView: SnapSettingsView()) }

    func extensionDidEnable() {
        let d = UserDefaults.standard
        SnapEngine.shared.centerAction = SnapCenterAction(rawValue: d.string(forKey: "snapCenterAction") ?? "fill") ?? .fill
        SnapEngine.shared.gap = CGFloat(d.double(forKey: "snapGap"))
        SnapEngine.shared.start()
    }

    func extensionWillUnload() { SnapEngine.shared.stop() }
}
