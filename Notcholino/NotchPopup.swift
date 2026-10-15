// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// A small message that hangs under the closed notch for a few seconds ("AirPods connected", "Copied #FF8800").
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

/// The popup itself: a black tab hanging from the bottom of the notch, with the same curved joins as the notch
struct NotchPopupView: View {
    let popup: NotchPopup
    private let flare: CGFloat = 10

    var body: some View {
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
        .padding(.horizontal, flare + 14)
        .padding(.top, 6)
        .frame(height: 48)
        .frame(minWidth: 170)
        .background(NotchShape(cornerRadius: 18, flareRadius: flare).fill(Color.black))
    }
}
