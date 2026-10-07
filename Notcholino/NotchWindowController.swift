import AppKit
import SwiftUI

// MARK: - NSHostingView che accetta i click anche senza essere key window

final class NotchHostingView: NSHostingView<NotchContentView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

// MARK: - Window Controller

class NotchWindowController: NSWindowController {

    private var scrollMonitor: Any?

    init() {
        guard let screen = NSScreen.main else {
            super.init(window: nil)
            return
        }

        let windowWidth: CGFloat  = 540
        let windowHeight: CGFloat = 270

        let windowRect = NSRect(
            x: (screen.frame.width - windowWidth) / 2,
            y: screen.frame.height - windowHeight,
            width: windowWidth,
            height: windowHeight
        )

        let panel = NSPanel(
            contentRect: windowRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor   = .clear
        panel.isOpaque          = false
        panel.hasShadow         = false
        panel.level             = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.isMovable          = false

        super.init(window: panel)

        let rootView = NotchContentView()
        let hosting  = NotchHostingView(rootView: rootView)
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Notch Shape (unchanged)

struct NotchShape: Shape {
    var cornerRadius: CGFloat
    var flareRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadius, flareRadius) }
        set { cornerRadius = newValue.first; flareRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let (w, h, r1, r2) = (rect.width, rect.height, flareRadius, cornerRadius)
        p.move(to: CGPoint(x: 0, y: 0))
        p.addArc(center: CGPoint(x: 0,   y: r1),     radius: r1, startAngle: .degrees(-90), endAngle: .degrees(0),   clockwise: false)
        p.addArc(center: CGPoint(x: r1+r2, y: h-r2), radius: r2, startAngle: .degrees(180), endAngle: .degrees(90),  clockwise: true)
        p.addArc(center: CGPoint(x: w-r1-r2, y: h-r2), radius: r2, startAngle: .degrees(90), endAngle: .degrees(0),  clockwise: true)
        p.addArc(center: CGPoint(x: w,   y: r1),     radius: r1, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Main Notch Content View

struct NotchContentView: View {
    @State private var isExpanded    = false
    @State private var activeTab: Int = 0   // 0=NowPlaying  1=Calendar
    @State private var collapseTask: Task<Void, Never>?

    // Single shared instance
    @StateObject private var musicManager = MusicManager()

    @AppStorage("notchWidth")  private var tuningW: Double = 0
    @AppStorage("notchHeight") private var tuningH: Double = 0

    private let baseW:  CGFloat = 162
    private let baseH:  CGFloat = 32
    private let flare:  CGFloat = 12

    private var pillW: CGFloat { baseW + CGFloat(tuningW) + flare * 2 }
    private var pillH: CGFloat { baseH + CGFloat(tuningH) }
    private var expandW: CGFloat { 460 }
    private var expandH: CGFloat { activeTab == 0 ? 172 : 192 }

    private var curW: CGFloat { isExpanded ? expandW : pillW }
    private var curH: CGFloat { isExpanded ? expandH : pillH }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {

                // ── Black base shape ─────────────────────────────────────────
                NotchShape(cornerRadius: isExpanded ? 28 : 10, flareRadius: flare)
                    .fill(Color.black)
                    .frame(width: curW, height: curH)
                    .shadow(color: .black.opacity(isExpanded ? 0.5 : 0), radius: 20, y: 12)

                // ── Content (clipped to shape to prevent ghosting) ───────────
                Group {
                    if isExpanded {
                        VStack(spacing: 0) {
                            // Tab indicator dots
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(activeTab == 0 ? Color.white : Color.white.opacity(0.3))
                                    .frame(width: 5, height: 5)
                                Circle()
                                    .fill(activeTab == 1 ? Color.white : Color.white.opacity(0.3))
                                    .frame(width: 5, height: 5)
                            }
                            .padding(.top, 10)
                            .allowsHitTesting(false) // dots are decorative

                            if activeTab == 0 {
                                NowPlayingNotchView(musicManager: musicManager)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal:   .move(edge: .leading).combined(with: .opacity)))
                            } else {
                                CalendarNotchView()
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .leading).combined(with: .opacity),
                                        removal:   .move(edge: .trailing).combined(with: .opacity)))
                            }
                        }
                        .frame(width: expandW, height: expandH)
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.8), value: activeTab)
                .clipShape(NotchShape(cornerRadius: isExpanded ? 28 : 10, flareRadius: flare))
                .frame(width: curW, height: curH)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.72), value: isExpanded)
            .animation(.spring(response: 0.4, dampingFraction: 0.72), value: curH)
            .onHover { hovering in
                collapseTask?.cancel()
                if hovering {
                    withAnimation { isExpanded = true }
                } else {
                    collapseTask = Task {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        guard !Task.isCancelled else { return }
                        await MainActor.run { withAnimation { isExpanded = false } }
                    }
                }
            }
            // ── Horizontal swipe (drag) changes tab ──────────────────────────
            // Use simultaneousGesture so buttons inside still receive taps
            .simultaneousGesture(
                DragGesture(minimumDistance: 25, coordinateSpace: .local)
                    .onEnded { val in
                        guard isExpanded else { return }
                        if val.translation.width < -30 {
                            withAnimation { activeTab = min(activeTab + 1, 1) }
                        } else if val.translation.width > 30 {
                            withAnimation { activeTab = max(activeTab - 1, 0) }
                        }
                    }
            )
            // ── Vertical scroll (two-finger trackpad) changes tab ────────────
            .onScrollWheel { delta in
                guard isExpanded else { return }
                if delta.y > 10 {
                    withAnimation { activeTab = min(activeTab + 1, 1) }
                } else if delta.y < -10 {
                    withAnimation { activeTab = max(activeTab - 1, 0) }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Scroll wheel modifier

struct ScrollWheelModifier: ViewModifier {
    let action: (CGPoint) -> Void

    func body(content: Content) -> some View {
        content.background(
            ScrollWheelReceiver(action: action)
        )
    }
}

struct ScrollWheelReceiver: NSViewRepresentable {
    let action: (CGPoint) -> Void

    func makeNSView(context: Context) -> ScrollView { ScrollView(action: action) }
    func updateNSView(_ nsView: ScrollView, context: Context) { nsView.action = action }

    final class ScrollView: NSView {
        var action: (CGPoint) -> Void
        init(action: @escaping (CGPoint) -> Void) {
            self.action = action
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func scrollWheel(with event: NSEvent) {
            action(CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY))
        }
    }
}

extension View {
    func onScrollWheel(action: @escaping (CGPoint) -> Void) -> some View {
        self.modifier(ScrollWheelModifier(action: action))
    }
}

// MARK: - Now Playing

struct NowPlayingNotchView: View {
    @ObservedObject var musicManager: MusicManager

    @AppStorage("npShowShuffle")   private var showShuffle   = false
    @AppStorage("npShowRepeat")    private var showRepeat    = false
    @AppStorage("npShowFavorites") private var showFavorites = false

    var body: some View {
        VStack(spacing: 8) {
            // ── Track info ───────────────────────────────────────────────────
            HStack(spacing: 12) {
                // Album art
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(
                            colors: [.purple.opacity(0.8), .blue.opacity(0.8)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 46, height: 46)

                    if let img = musicManager.albumArt {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(musicManager.isPlaying ? musicManager.trackName : "Nothing Playing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(musicManager.isPlaying
                         ? musicManager.artistName
                         : "Open Spotify or Music")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer()

                Group {
                    if musicManager.activePlayer == "Spotify" {
                        Image(systemName: "waveform.circle.fill").foregroundStyle(.green)
                    } else if musicManager.activePlayer == "Music" {
                        Image(systemName: "music.note.list").foregroundStyle(.pink)
                    }
                }
                .font(.system(size: 15))
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)

            // ── Progress bar ─────────────────────────────────────────────────
            HStack(spacing: 6) {
                Text(musicManager.formatTime(musicManager.trackPosition))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1)).frame(height: 3)
                        let pct: CGFloat = musicManager.trackDuration > 0
                            ? CGFloat(musicManager.trackPosition / musicManager.trackDuration)
                            : 0
                        Capsule().fill(Color.white.opacity(0.85))
                            .frame(width: max(3, geo.size.width * pct), height: 3)
                    }
                }
                .frame(height: 3)

                let rem = musicManager.trackDuration - musicManager.trackPosition
                Text(rem > 0 ? "-\(musicManager.formatTime(rem))" : "")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)

            // ── Controls ─────────────────────────────────────────────────────
            HStack(spacing: 24) {
                if showShuffle {
                    NotchButton(icon: "shuffle", size: 13) { }
                }

                NotchButton(icon: "backward.fill", size: 18) {
                    musicManager.previousTrack()
                }

                // Play/Pause — explicit high-priority button
                Button {
                    musicManager.playPause()
                } label: {
                    Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .highPriorityGesture(TapGesture().onEnded { musicManager.playPause() })

                NotchButton(icon: "forward.fill", size: 18) {
                    musicManager.nextTrack()
                }

                if showRepeat    { NotchButton(icon: "repeat", size: 13)      { } }
                if showFavorites { NotchButton(icon: "heart",  size: 13)      { } }
                if !showRepeat && !showFavorites {
                    NotchButton(icon: "airplayaudio", size: 13) { }
                }
            }
            .padding(.bottom, 12)
        }
    }
}

struct NotchButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Calendar

struct CalendarNotchView: View {
    @AppStorage("calDisplayMode") private var displayMode = 0

    private var cal:       Calendar  { .current }
    private var today:     Date      { Date() }

    private var dayName: String {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: today).uppercased()
    }
    private var dayNum: String  { "\(cal.component(.day, from: today))" }
    private var monthName: String {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f.string(from: today).uppercased()
    }

    private var monthGrid: [[String]] {
        var c = cal.dateComponents([.year, .month], from: today); c.day = 1
        guard let first = cal.date(from: c),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }
        var wd = cal.component(.weekday, from: first) - 2
        if wd < 0 { wd += 7 }
        var flat = Array(repeating: "", count: wd) + (1...range.count).map { "\($0)" }
        while flat.count % 7 != 0 { flat.append("") }
        return stride(from: 0, to: flat.count, by: 7).map { Array(flat[$0..<min($0+7, flat.count)]) }
    }

    private let weekdays = ["M","T","W","T","F","S","S"]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left: today's date
            VStack(alignment: .leading, spacing: 0) {
                Text(dayName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.red)
                Text(dayNum)
                    .font(.system(size: displayMode == 0 ? 48 : 68, weight: .thin))
                    .foregroundStyle(.white)
                    .padding(.top, -4)
                Spacer()
                VStack(alignment: .leading, spacing: 1) {
                    Text("No events today")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Your schedule is clear")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.bottom, 12)
            }
            .padding(.leading, 18)
            .padding(.top, 12)

            if displayMode == 0 {
                Spacer()

                // Right: mini month grid
                VStack(alignment: .trailing, spacing: 4) {
                    Text(monthName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.red)

                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { i in
                            Text(weekdays[i])
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(i >= 5 ? .white.opacity(0.25) : .white.opacity(0.45))
                                .frame(width: 20, alignment: .center)
                        }
                    }

                    ForEach(0..<monthGrid.count, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { col in
                                let txt = monthGrid[row][col]
                                ZStack {
                                    if txt == dayNum {
                                        Circle().fill(Color.red).frame(width: 17, height: 17)
                                    }
                                    Text(txt)
                                        .font(.system(size: 9, weight: txt == dayNum ? .bold : .regular))
                                        .foregroundStyle(txt.isEmpty ? .clear
                                                        : txt == dayNum ? .white
                                                        : .white.opacity(0.5))
                                }
                                .frame(width: 20, height: 17)
                            }
                        }
                    }
                }
                .padding(.trailing, 14)
                .padding(.top, 12)
            }
        }
    }
}
