// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// A small message that grows out of the closed notch for a few seconds ("AirPods connected", "Copied #FF8800").
struct NotchPopup: Identifiable, Equatable {
    let id = UUID()
    var icon: String?
    var title: String
    var subtitle: String?
    var tint: Color
    var seconds: Double
}

/// Where popups come from: the app itself (devices, power) and plugins. One shows at a time; a new one replaces it.
final class PopupCenter: ObservableObject {
    static let shared = PopupCenter()

    @Published private(set) var current: NotchPopup?
    private var hideTask: Task<Void, Never>?

    func show(icon: String? = nil, title: String, subtitle: String? = nil, tint: Color = .white, seconds: Double = 3) {
        let popup = NotchPopup(icon: icon, title: title, subtitle: subtitle, tint: tint, seconds: max(1, min(seconds, 15)))
        DispatchQueue.main.async {
            self.hideTask?.cancel()
            self.current = popup
            self.hideTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(popup.seconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run { if self?.current?.id == popup.id { self?.current = nil } }
            }
        }
    }

    /// From a plugin: the dictionary documented in NotcholinoPluginAPI.swift
    func show(from dictionary: [String: Any]) {
        guard let title = dictionary["title"] as? String, !title.isEmpty else { return }
        show(icon: dictionary["icon"] as? String,
             title: title,
             subtitle: dictionary["subtitle"] as? String,
             tint: Color(hex: dictionary["color"] as? String ?? "") ?? .white,
             seconds: dictionary["seconds"] as? Double ?? 3)
    }

    func dismiss() {
        hideTask?.cancel()
        DispatchQueue.main.async { self.current = nil }
    }
}

/// What the closed notch shows in the strip that grows under it: a popup, or the text of a plugin (a countdown)
enum NotchExtension: Equatable {
    case popup(NotchPopup)
    case text(String, Color)

    /// How much taller the notch gets
    var height: CGFloat {
        switch self {
        case .popup(let p): return (p.subtitle?.isEmpty == false) ? 40 : 30
        case .text:         return 26
        }
    }

    /// The width this content needs, to widen the notch when it doesn't fit (never narrower than the notch itself)
    var contentWidth: CGFloat {
        func width(_ s: String, _ font: NSFont) -> CGFloat { ceil((s as NSString).size(withAttributes: [.font: font]).width) }
        switch self {
        case .popup(let p):
            let t = width(p.title, .systemFont(ofSize: 12, weight: .semibold))
            let s = width(p.subtitle ?? "", .systemFont(ofSize: 10.5, weight: .medium))
            return max(t, s) + (p.icon == nil ? 0 : 34) + 32
        case .text(let s, _):
            return width(s, .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)) + 32
        }
    }
}

/// The content of the strip, drawn inside the notch's own black shape
struct NotchExtensionView: View {
    let content: NotchExtension

    var body: some View {
        switch content {
        case .popup(let popup):
            HStack(spacing: 10) {
                if let icon = popup.icon {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(popup.tint)
                        .frame(width: 24)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(popup.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let subtitle = popup.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }
            .fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 4)
        case .text(let text, let color):
            Text(text)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 4)
        }
    }
}
