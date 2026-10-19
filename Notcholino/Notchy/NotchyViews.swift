// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

// MARK: - The page in the notch

/// Notchy's page in the notch: it is here, resting. Tap it to pet it. (Files, questions and the day come in the next steps.)
struct NotchyNotchView: View {
    /// From the notch, which owns the music player: Notchy puts on headphones while it plays
    var musicPlaying = false
    @ObservedObject private var presence = NotchyPresence.shared
    @ObservedObject private var settings = NotchySettings.shared
    @ObservedObject private var assistant = NotchyAssistant.shared
    @ObservedObject private var calendar = CalendarManager.shared
    @ObservedObject private var voice = NotchyVoice.shared
    @State private var mood: NotchyMood = .calm
    @State private var gaze: CGFloat = 0
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 22) {
            // Three yes/no questions every few seconds, only while this page is on screen
            TimelineView(.periodic(from: .now, by: 4)) { _ in
                NotchyCube(mood: shownMood, size: 78, gaze: gaze, accessories: NotchyAccessory.current(musicPlaying: musicPlaying))
            }
            .onTapGesture { pet() }
            VStack(alignment: .leading, spacing: 4) {
                Text("Notchy").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                ScrollView {
                    Text(status).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 70)
                if settings.providerID(for: .text) != nil {
                    HStack(spacing: 8) {
                        PageButton(title: "Plan my day", symbol: "calendar.badge.clock", busy: busy) { assistant.planDay() }
                        PageButton(title: "Look at the screen", symbol: "eye", busy: busy) { assistant.lookAtScreen() }
                    }
                    if settings.providerID(for: .speech) != nil {
                        Text("Hold \(voice.shortcutLabel) to talk").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var busy: Bool { if case .thinking = assistant.state { return true } else { return false } }

    private var shownMood: NotchyMood {
        switch assistant.state {
        case .thinking: return .thinking
        case .reply: return .happy
        case .failed: return .sleepy
        case .idle: return mood
        }
    }

    private var status: String {
        switch assistant.state {
        case .thinking(let what): return "Reading \(what)…"
        case .reply(let text): return text
        case .failed(let why): return why
        case .idle: break
        }
        guard let id = settings.providerID(for: .text), let p = NotchyProvider.provider(id) else {
            return "Choose a provider in Settings → Notchy to ask it things."
        }
        // Worked out on the Mac, no AI involved
        if let next = calendar.upcomingEvent, let start = next.startDate, !next.isAllDay {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            return "Next: \(next.title ?? "event") at \(f.string(from: start)). Right-click text or a file → Services → Send to Notchy, or plan your day."
        }
        return "Ready · text with \(p.name). Select text or a file, right-click → Services → Send to Notchy."
    }

    private func pet() {
        resetTask?.cancel()
        mood = .happy
        gaze = 0
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            mood = .calm
        }
    }
}

private struct PageButton: View {
    let title: String
    let symbol: String
    let busy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(.white.opacity(0.14)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.5 : 1)
    }
}
