import AppKit
import SwiftUI

// MARK: - Window Controller

class NotchWindowController: NSWindowController {

    init() {
        guard let screen = NSScreen.main else {
            super.init(window: nil)
            return
        }

        // Position: centered horizontally, pinned to the very top of the screen
        let windowWidth: CGFloat = 520
        let windowHeight: CGFloat = 260

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

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.isMovable = false

        super.init(window: panel)

        let hostingView = NSHostingView(rootView: NotchContentView())
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Notch Shape

/// The rounded pill that expands downward from the top menu bar.
/// The top two corners are "inverted" (concave) to match the real physical notch flares.
struct NotchShape: Shape {
    var cornerRadius: CGFloat
    var flareRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadius, flareRadius) }
        set { cornerRadius = newValue.first; flareRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let r1 = flareRadius   // inverted top-corner arc radius
        let r2 = cornerRadius  // bottom corner radius

        // Start top-left
        p.move(to: CGPoint(x: 0, y: 0))
        // Concave top-left flare
        p.addArc(center: CGPoint(x: 0, y: r1), radius: r1,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        // Bottom-left rounded corner
        p.addArc(center: CGPoint(x: r1 + r2, y: h - r2), radius: r2,
                 startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        // Bottom-right rounded corner
        p.addArc(center: CGPoint(x: w - r1 - r2, y: h - r2), radius: r2,
                 startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        // Concave top-right flare
        p.addArc(center: CGPoint(x: w, y: r1), radius: r1,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Main Notch Content View

struct NotchContentView: View {
    @State private var isExpanded = false
    @State private var activeTab: Int = 0   // 0 = NowPlaying, 1 = Calendar
    @State private var collapseTask: Task<Void, Never>?

    // Shared MusicManager — single instance lives as long as the view
    @StateObject private var musicManager = MusicManager()

    // Tuning from settings
    @AppStorage("notchWidth")  private var tuningW: Double = 0
    @AppStorage("notchHeight") private var tuningH: Double = 0

    // Collapsed pill dimensions (matching real MacBook notch)
    private let baseW: CGFloat = 162
    private let baseH: CGFloat = 32
    private let flare: CGFloat = 12

    private var pillW: CGFloat { baseW + CGFloat(tuningW) + flare * 2 }
    private var pillH: CGFloat { baseH + CGFloat(tuningH) }

    private var expandW: CGFloat { 440 }
    private var expandH: CGFloat { activeTab == 0 ? 168 : 188 }

    private var currentW: CGFloat { isExpanded ? expandW : pillW }
    private var currentH: CGFloat { isExpanded ? expandH : pillH }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // ── Black background shape ──────────────────────────────────
                NotchShape(cornerRadius: isExpanded ? 28 : 10, flareRadius: flare)
                    .fill(Color.black)
                    .frame(width: currentW, height: currentH)
                    .shadow(color: .black.opacity(isExpanded ? 0.5 : 0), radius: 20, y: 12)

                // ── Content clipped to the shape (prevents ghosting) ────────
                NotchShape(cornerRadius: isExpanded ? 28 : 10, flareRadius: flare)
                    .fill(Color.black) // opaque background so content is readable
                    .frame(width: currentW, height: currentH)
                    .overlay(
                        Group {
                            if isExpanded {
                                tabContent
                                    .frame(width: expandW, height: expandH)
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }
                        }
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: activeTab)
                        , alignment: .center
                    )
                    .clipShape(NotchShape(cornerRadius: isExpanded ? 28 : 10, flareRadius: flare))
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.72), value: isExpanded)
            .animation(.spring(response: 0.4, dampingFraction: 0.72), value: currentH)
            .animation(.spring(response: 0.4, dampingFraction: 0.72), value: activeTab)
            .onHover { hovering in
                collapseTask?.cancel()
                if hovering {
                    withAnimation { isExpanded = true }
                } else {
                    collapseTask = Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation { isExpanded = false }
                    }
                }
            }
            // Swipe to change tab
            .gesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onEnded { val in
                        guard isExpanded else { return }
                        if val.translation.width < -30 {
                            withAnimation { activeTab = min(activeTab + 1, 1) }
                        } else if val.translation.width > 30 {
                            withAnimation { activeTab = max(activeTab - 1, 0) }
                        }
                    }
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var tabContent: some View {
        VStack(spacing: 0) {
            // ── Tab dots ────────────────────────────────────────────────────
            HStack(spacing: 6) {
                Circle().fill(activeTab == 0 ? Color.white : Color.white.opacity(0.3))
                    .frame(width: 5, height: 5)
                Circle().fill(activeTab == 1 ? Color.white : Color.white.opacity(0.3))
                    .frame(width: 5, height: 5)
            }
            .padding(.top, 8)

            if activeTab == 0 {
                NowPlayingNotchView(musicManager: musicManager)
            } else {
                CalendarNotchView()
            }
        }
    }
}

// MARK: - Now Playing Notch View

struct NowPlayingNotchView: View {
    @ObservedObject var musicManager: MusicManager

    @AppStorage("npShowShuffle")   private var showShuffle   = false
    @AppStorage("npShowRepeat")    private var showRepeat     = false
    @AppStorage("npShowFavorites") private var showFavorites  = false

    var body: some View {
        VStack(spacing: 10) {
            // ── Track info row ───────────────────────────────────────────────
            HStack(spacing: 12) {
                // Album art placeholder (gradient)
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 46, height: 46)
                    Text(musicManager.trackName.isEmpty ? "♪" : String(musicManager.trackName.prefix(1)))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(musicManager.isPlaying ? musicManager.trackName : "Nothing Playing")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(musicManager.isPlaying ? musicManager.artistName : "Open Spotify or Music")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()

                // Player logo
                Group {
                    if musicManager.activePlayer == "Spotify" {
                        Image(systemName: "waveform.circle.fill").foregroundStyle(.green)
                    } else if musicManager.activePlayer == "Music" {
                        Image(systemName: "music.note.list").foregroundStyle(.pink)
                    }
                }
                .font(.system(size: 16))
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)

            // ── Progress bar ─────────────────────────────────────────────────
            HStack(spacing: 8) {
                Text(musicManager.formatTime(musicManager.trackPosition))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12)).frame(height: 4)
                        let pct = musicManager.trackDuration > 0
                            ? CGFloat(musicManager.trackPosition / musicManager.trackDuration)
                            : 0
                        Capsule().fill(Color.white.opacity(0.9))
                            .frame(width: max(4, geo.size.width * pct), height: 4)
                    }
                }
                .frame(height: 4)

                let rem = musicManager.trackDuration - musicManager.trackPosition
                Text(rem > 0 ? "-\(musicManager.formatTime(rem))" : "")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 18)

            // ── Controls ─────────────────────────────────────────────────────
            HStack(spacing: 28) {
                if showShuffle {
                    Button { } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                    }.buttonStyle(.plain)
                }

                Button { musicManager.previousTrack() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                }.buttonStyle(.plain)

                Button { musicManager.playPause() } label: {
                    Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white)
                }.buttonStyle(.plain)

                Button { musicManager.nextTrack() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                }.buttonStyle(.plain)

                if showRepeat {
                    Button { } label: {
                        Image(systemName: "repeat")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                    }.buttonStyle(.plain)
                }

                if showFavorites {
                    Button { } label: {
                        Image(systemName: "heart")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                    }.buttonStyle(.plain)
                }

                if !showRepeat && !showFavorites {
                    Button { } label: {
                        Image(systemName: "airplayaudio")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.bottom, 10)
        }
    }
}

// MARK: - Calendar Notch View

struct CalendarNotchView: View {
    @AppStorage("calDisplayMode") private var displayMode = 0

    // Real calendar values
    private var calendar: Calendar { .current }
    private var today: Date { Date() }

    private var dayName: String {
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: today).uppercased()
    }
    private var dayNumber: String {
        "\(calendar.component(.day, from: today))"
    }
    private var monthName: String {
        let f = DateFormatter(); f.dateFormat = "MMM"
        return f.string(from: today).uppercased()
    }

    // Build a 6×7 grid of day numbers for the current month
    private var monthGrid: [[String]] {
        let comps = calendar.dateComponents([.year, .month], from: today)
        var startComps = comps; startComps.day = 1
        guard let firstDay = calendar.date(from: startComps),
              let range = calendar.range(of: .day, in: .month, for: firstDay) else { return [] }

        // weekday of first day (1=Sun,2=Mon...7=Sat) → shift to Mon-first
        var weekday = calendar.component(.weekday, from: firstDay) - 2
        if weekday < 0 { weekday += 7 }

        var flat = Array(repeating: "", count: weekday)
        flat += (1...range.count).map { "\($0)" }
        while flat.count % 7 != 0 { flat.append("") }

        return stride(from: 0, to: flat.count, by: 7).map { Array(flat[$0..<$0+7]) }
    }

    private var todayNum: String { dayNumber }
    private let weekdays = ["M","T","W","T","F","S","S"]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left: day display
            VStack(alignment: .leading, spacing: 0) {
                Text(dayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.red)
                Text(dayNumber)
                    .font(.system(size: displayMode == 0 ? 52 : 72, weight: .light))
                    .foregroundStyle(.white)
                    .padding(.top, -6)

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text("No events today")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Your day is clear")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.bottom, 14)
            }
            .padding(.leading, 20)
            .padding(.top, 14)
            .frame(maxWidth: displayMode == 1 ? .infinity : nil, alignment: displayMode == 1 ? .center : .leading)

            if displayMode == 0 {
                Spacer()

                // Right: mini month grid
                VStack(spacing: 5) {
                    HStack(spacing: 0) {
                        Spacer()
                        Text(monthName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.red)
                    }
                    .frame(width: 162)

                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { i in
                            Text(weekdays[i])
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(i >= 5 ? .white.opacity(0.3) : .white.opacity(0.5))
                                .frame(width: 22, alignment: .center)
                        }
                    }

                    ForEach(0..<monthGrid.count, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { col in
                                let txt = monthGrid[row][col]
                                ZStack {
                                    if txt == todayNum {
                                        Circle().fill(Color.red)
                                            .frame(width: 19, height: 19)
                                    }
                                    Text(txt)
                                        .font(.system(size: 10, weight: txt == todayNum ? .bold : .regular))
                                        .foregroundStyle(txt.isEmpty ? .clear : (txt == todayNum ? .white : .white.opacity(0.55)))
                                }
                                .frame(width: 22, height: 19)
                            }
                        }
                    }
                }
                .padding(.trailing, 16)
                .padding(.top, 14)
            }
        }
    }
}
