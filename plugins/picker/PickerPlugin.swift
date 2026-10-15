// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation

/// Picker is a color picker for anything on your screen. Click "Pick a color", point at a pixel and click: the color is
/// copied as HEX, RGB or HSL, and the last ones you picked stay in the options to copy again.
@objc(PickerPlugin)
final class PickerPlugin: NSObject, NotcholinoPlugin {

    // MARK: Plugin info

    var apiVersion: Int { notcholinoPluginAPIVersion }
    var pluginIdentifier: String { "picker" }
    var pluginName: String { "Picker" }
    var pluginVersion: String {
        Bundle(for: PickerPlugin.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    var pluginAuthor: String { "Giuseppe" }
    var pluginDescription: String { "Pick a color from anywhere on your screen and copy it as HEX, RGB or HSL." }

    // MARK: State

    private enum Key {
        static let format = "plugin.picker.format"
        static let recent = "plugin.picker.recent"
    }
    private static let formats = [("hex", "HEX"), ("rgb", "RGB"), ("hsl", "HSL")]
    private static let limit = 8

    private var format: String {
        let saved = UserDefaults.standard.string(forKey: Key.format) ?? "hex"
        return Self.formats.contains { $0.0 == saved } ? saved : "hex"
    }
    /// Picked colors as "RRGGBB", newest first
    private var recent: [String] { UserDefaults.standard.stringArray(forKey: Key.recent) ?? [] }
    private var picking = false
    private var popup: (([String: Any]) -> Void)?

    func setPopupHandler(_ handler: @escaping ([String: Any]) -> Void) { popup = handler }

    // MARK: Control Center

    var isActive: Bool { picking }
    var controlCenterIcon: String { "eyedropper" }
    var statusText: String { picking ? "Click a pixel" : "" }

    func menuItems() -> [[String: Any]] {
        var items: [[String: Any]] = [["id": "pick", "title": "Pick a color", "wide": true], ["header": "Copy as"]]
        for (id, title) in Self.formats { items.append(["id": "format:\(id)", "title": title, "checked": format == id]) }
        if !recent.isEmpty {
            items.append(["header": "Recent: click to copy again"])
            for (i, hex) in recent.enumerated() { items.append(["id": "again:\(i)", "title": "#\(hex)   \(Self.string(forHex: hex, format: format))", "wide": true]) }
        }
        return items
    }

    func performMenuAction(_ id: String) {
        if id == "pick" { pick(); return }
        if id.hasPrefix("format:") { UserDefaults.standard.set(String(id.dropFirst(7)), forKey: Key.format); return }
        if id.hasPrefix("again:"), let i = Int(id.dropFirst(6)), recent.indices.contains(i) { copy(hex: recent[i]) }
    }

    // MARK: Picking

    private func pick() {
        guard !picking else { return }
        picking = true
        // The loupe needs a moment, and the notch should get out of the way
        DispatchQueue.main.async {
            NSColorSampler().show { [weak self] color in
                DispatchQueue.main.async {
                    self?.picking = false
                    guard let color = color?.usingColorSpace(.sRGB) else { return }
                    let hex = String(format: "%02X%02X%02X", Int((color.redComponent * 255).rounded()),
                                     Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
                    var list = self?.recent ?? []
                    list.removeAll { $0 == hex }
                    list.insert(hex, at: 0)
                    UserDefaults.standard.set(Array(list.prefix(Self.limit)), forKey: Key.recent)
                    self?.copy(hex: hex)
                }
            }
        }
    }

    private func copy(hex: String) {
        let text = Self.string(forHex: hex, format: format)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        popup?(["title": text, "subtitle": "Copied", "icon": "eyedropper.full", "color": "#\(hex)", "seconds": 3.0])
    }

    /// "#FF8800", "rgb(255, 136, 0)" or "hsl(32, 100%, 50%)"
    static func string(forHex hex: String, format: String) -> String {
        guard let value = Int(hex, radix: 16) else { return "#\(hex)" }
        let r = Double((value >> 16) & 255), g = Double((value >> 8) & 255), b = Double(value & 255)
        switch format {
        case "rgb": return "rgb(\(Int(r)), \(Int(g)), \(Int(b)))"
        case "hsl":
            let (rn, gn, bn) = (r / 255, g / 255, b / 255)
            let mx = max(rn, gn, bn), mn = min(rn, gn, bn), d = mx - mn
            let l = (mx + mn) / 2
            var h = 0.0, s = 0.0
            if d > 0 {
                s = d / (1 - abs(2 * l - 1))
                if mx == rn { h = 60 * (((gn - bn) / d).truncatingRemainder(dividingBy: 6)) }
                else if mx == gn { h = 60 * ((bn - rn) / d + 2) }
                else { h = 60 * ((rn - gn) / d + 4) }
                if h < 0 { h += 360 }
            }
            return "hsl(\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
        default: return "#\(hex)"
        }
    }
}
