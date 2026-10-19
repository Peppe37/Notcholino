// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// How Notchy feels. The eyes tell it first (so it also reads without colors), the glow tells it second.
enum NotchyMood: String, CaseIterable {
    case calm, curious, happy, thinking, sleepy

    var tint: Color {
        switch self {
        case .calm:     return Color(red: 0.47, green: 0.65, blue: 1.00)
        case .curious:  return Color(red: 1.00, green: 0.80, blue: 0.35)
        case .happy:    return Color(red: 0.35, green: 0.94, blue: 0.63)
        case .thinking: return Color(red: 0.71, green: 0.55, blue: 1.00)
        case .sleepy:   return Color(red: 1.00, green: 0.55, blue: 0.47)
        }
    }

    var title: String {
        switch self {
        case .calm: return "Calm"
        case .curious: return "Curious"
        case .happy: return "Happy"
        case .thinking: return "Thinking"
        case .sleepy: return "Sleepy"
        }
    }
}

/// Notchy: a soft, glassy white cube with two black eyes that have little white reflections, and no mouth.
/// Drawn with SwiftUI shapes (no pictures), and animated only when something happens: a blink every few seconds while it is on
/// screen, and a squash and stretch when the mood changes. Nothing runs while it is hidden.
struct NotchyCube: View {
    var mood: NotchyMood = .calm
    /// Side of the cube in points (the body is a bit wider than tall)
    var size: CGFloat = 60
    /// Where it looks: -1 left … 1 right
    var gaze: CGFloat = 0
    /// Blinks by itself while true
    var alive = true
    /// Things it wears or holds, drawn with shapes too
    var accessories: Set<NotchyAccessory> = []

    @State private var blinking = false
    @State private var squash: CGSize = CGSize(width: 1, height: 1)
    @State private var blinkTask: Task<Void, Never>?

    private var w: CGFloat { size }
    private var h: CGFloat { size * 0.93 }

    var body: some View {
        ZStack {
            body(in: CGSize(width: w, height: h))
            eyes
            ForEach(Array(accessories), id: \.self) { accessory in
                NotchyAccessoryView(accessory: accessory, size: size)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: accessories)
        .frame(width: w, height: h)
        .scaleEffect(squash)
        .animation(.spring(response: 0.32, dampingFraction: 0.5), value: squash)
        .onChange(of: mood) { _ in bounce() }
        .onAppear { startBlinking() }
        .onDisappear { blinkTask?.cancel(); blinkTask = nil }
    }

    // MARK: Body: glass

    private func body(in s: CGSize) -> some View {
        let radius = s.width * 0.30
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [.white.opacity(0.62), .white.opacity(0.26), .white.opacity(0.40)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            // the light of the mood, coming from below, inside the glass
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [mood.tint.opacity(0.12), mood.tint.opacity(0.70)], startPoint: .top, endPoint: .bottom))
                    .animation(.easeInOut(duration: 0.4), value: mood)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.45), lineWidth: max(0.5, s.width * 0.014))
            )
            // the reflection on top
            .overlay(alignment: .topLeading) {
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: s.width * 0.46, height: s.height * 0.17)
                    .rotationEffect(.degrees(-8))
                    .offset(x: s.width * 0.11, y: s.height * 0.07)
            }
            .shadow(color: mood.tint.opacity(0.35), radius: s.width * 0.16)
    }

    // MARK: Eyes

    private var eyes: some View {
        HStack(spacing: w * 0.23) {
            eye
            eye
        }
        .offset(x: gaze * w * 0.06, y: -h * 0.02)
    }

    private var eye: some View {
        let ew = w * eyeSize.width, eh = w * eyeSize.height
        return ZStack {
            eyeShape.fill(Color(red: 0.02, green: 0.025, blue: 0.04)).frame(width: ew, height: eh)
            if mood != .sleepy && mood != .happy {
                Circle().fill(.white).frame(width: ew * 0.32, height: ew * 0.32).offset(x: -ew * 0.16, y: -eh * 0.24)
                Circle().fill(.white.opacity(0.8)).frame(width: ew * 0.15, height: ew * 0.15).offset(x: ew * 0.20, y: eh * 0.26)
            }
        }
        .scaleEffect(x: 1, y: blinking ? 0.08 : 1, anchor: .center)
        .animation(.easeOut(duration: 0.08), value: blinking)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: mood)
        .frame(width: ew, height: w * 0.30)
    }

    /// Width and height of an eye, in units of the cube's width
    private var eyeSize: CGSize {
        switch mood {
        case .calm:     return CGSize(width: 0.17, height: 0.26)
        case .curious:  return CGSize(width: 0.20, height: 0.30)
        case .thinking: return CGSize(width: 0.18, height: 0.20)
        case .happy:    return CGSize(width: 0.17, height: 0.10)
        case .sleepy:   return CGSize(width: 0.17, height: 0.035)
        }
    }

    private var eyeShape: some Shape {
        switch mood {
        case .happy:
            return AnyShape(UnevenRoundedRectangle(topLeadingRadius: 99, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 99))
        case .sleepy:
            return AnyShape(Capsule())
        default:
            return AnyShape(Ellipse())
        }
    }

    // MARK: Life

    /// A small jump: the cube squashes, stretches and settles
    func bounce() {
        squash = CGSize(width: 1.10, height: 0.88)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 110_000_000)
            squash = CGSize(width: 0.95, height: 1.07)
            try? await Task.sleep(nanoseconds: 160_000_000)
            squash = CGSize(width: 1, height: 1)
        }
    }

    private func startBlinking() {
        guard alive, blinkTask == nil else { return }
        blinkTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 2.4...5.6) * 1_000_000_000))
                guard !Task.isCancelled, mood != .sleepy else { continue }
                blinking = true
                try? await Task.sleep(nanoseconds: 110_000_000)
                blinking = false
            }
        }
    }
}

// MARK: - Accessories

/// What Notchy picks up from the Mac and from the official plugins, if they are installed
enum NotchyAccessory: String, Hashable {
    case headphones   // music is playing
    case tomato       // a Tomato timer is running
    case coffee       // Espresso is keeping the Mac awake

    /// What is going on right now. Cheap: three yes/no answers, asked only while Notchy's page is on screen.
    @MainActor static func current(musicPlaying: Bool) -> Set<NotchyAccessory> {
        var set: Set<NotchyAccessory> = []
        if musicPlaying { set.insert(.headphones) }
        for plugin in PluginManager.shared.loadedPlugins where plugin.isActive {
            if plugin.pluginIdentifier == "tomato" { set.insert(.tomato) }
            if plugin.pluginIdentifier == "espresso" { set.insert(.coffee) }
        }
        return set
    }
}

struct NotchyAccessoryView: View {
    let accessory: NotchyAccessory
    let size: CGFloat

    var body: some View {
        switch accessory {
        case .headphones:
            ZStack {
                // The band over the top, and a cup on each side
                Circle().trim(from: 0.5, to: 1)
                    .stroke(Color(white: 0.16), style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
                    .frame(width: size * 0.95, height: size * 0.95)
                    .offset(y: -size * 0.08)
                ForEach([-1.0, 1.0], id: \.self) { side in
                    RoundedRectangle(cornerRadius: size * 0.05, style: .continuous)
                        .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: size * 0.05).strokeBorder(.white.opacity(0.25), lineWidth: 0.6))
                        .frame(width: size * 0.12, height: size * 0.26)
                        .offset(x: CGFloat(side) * size * 0.475, y: size * 0.0)
                }
            }
        case .tomato:
            // A small tomato on top, like a hat
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.45, blue: 0.35), Color(red: 0.85, green: 0.15, blue: 0.12)],
                                             center: .topLeading, startRadius: 1, endRadius: size * 0.25))
                    .frame(width: size * 0.3, height: size * 0.27)
                Capsule().fill(Color(red: 0.25, green: 0.7, blue: 0.3)).frame(width: size * 0.16, height: size * 0.05)
                    .rotationEffect(.degrees(-18)).offset(y: -size * 0.13)
                Capsule().fill(Color(red: 0.25, green: 0.7, blue: 0.3)).frame(width: size * 0.12, height: size * 0.045)
                    .rotationEffect(.degrees(28)).offset(x: size * 0.02, y: -size * 0.12)
            }
            .offset(x: size * 0.12, y: -size * 0.49)
        case .coffee:
            // A cup held at the bottom right, with steam
            ZStack {
                Capsule().fill(.white.opacity(0.7)).frame(width: size * 0.035, height: size * 0.12)
                    .offset(x: -size * 0.04, y: -size * 0.17)
                Capsule().fill(.white.opacity(0.5)).frame(width: size * 0.035, height: size * 0.09)
                    .offset(x: size * 0.04, y: -size * 0.15)
                RoundedRectangle(cornerRadius: size * 0.04, style: .continuous)
                    .fill(LinearGradient(colors: [.white, Color(white: 0.82)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.24, height: size * 0.2)
                Circle().strokeBorder(.white.opacity(0.9), lineWidth: size * 0.03).frame(width: size * 0.12, height: size * 0.12)
                    .offset(x: size * 0.15, y: -size * 0.01)
                RoundedRectangle(cornerRadius: size * 0.02).fill(Color(red: 0.42, green: 0.26, blue: 0.16))
                    .frame(width: size * 0.2, height: size * 0.035).offset(y: -size * 0.08)
            }
            .offset(x: size * 0.4, y: size * 0.42)
        }
    }
}
