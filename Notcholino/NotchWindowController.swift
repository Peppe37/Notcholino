import AppKit
import SwiftUI

// MARK: - NSHostingView con scroll wheel e acceptsFirstMouse

final class NotchHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // Route scroll wheel events as a notification (most reliable for nonactivatingPanel)
    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        NotificationCenter.default.post(
            name: .notchScrollWheel,
            object: nil,
            userInfo: ["dy": delta]
        )
    }
}

extension Notification.Name {
    static let notchScrollWheel = Notification.Name("notchScrollWheel")
}

// MARK: - Window Controller

class NotchWindowController: NSWindowController {

    init() {
        guard let screen = NSScreen.main else {
            super.init(window: nil)
            return
        }

        let W: CGFloat = 520
        let H: CGFloat = 280

        let panel = NSPanel(
            contentRect: NSRect(
                x: (screen.frame.width - W) / 2,
                y: screen.frame.height - H,
                width: W, height: H),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)

        panel.backgroundColor    = .clear
        panel.isOpaque           = false
        panel.hasShadow          = false
        panel.level              = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.isMovable          = false

        super.init(window: panel)

        let root = AnyView(NotchContentView())
        let hosting = NotchHostingView(rootView: root)
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Notch Shape

struct NotchShape: Shape {
    var cornerRadius: CGFloat
    var flareRadius:  CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(cornerRadius, flareRadius) }
        set { cornerRadius = newValue.first; flareRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let (w, h, r1, r2) = (rect.width, rect.height, flareRadius, cornerRadius)
        p.move(to: .init(x: 0, y: 0))
        p.addArc(center: .init(x: 0,       y: r1),     radius: r1, startAngle: .degrees(-90), endAngle: .degrees(0),   clockwise: false)
        p.addArc(center: .init(x: r1+r2,   y: h-r2),   radius: r2, startAngle: .degrees(180), endAngle: .degrees(90),  clockwise: true)
        p.addArc(center: .init(x: w-r1-r2, y: h-r2),   radius: r2, startAngle: .degrees(90),  endAngle: .degrees(0),   clockwise: true)
        p.addArc(center: .init(x: w,       y: r1),     radius: r1, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Main Notch Content View

struct NotchContentView: View {
    @State private var isExpanded   = false
    @State private var activeTab    = 0   // 0=music 1=calendar
    @State private var collapseTask: Task<Void, Never>?

    @StateObject private var music   = MusicManager()
    @StateObject private var sysEvt  = SystemEventsManager()

    @AppStorage("notchWidth")  private var tuningW: Double = 0
    @AppStorage("notchHeight") private var tuningH: Double = 0

    // Collapsed pill (matches real MacBook notch ~162×32)
    private let baseW: CGFloat = 162
    private let baseH: CGFloat = 32
    private let flare: CGFloat = 12

    private var pillW: CGFloat { baseW + CGFloat(tuningW) + flare * 2 }
    private var pillH: CGFloat { baseH + CGFloat(tuningH) }

    // Expanded size based on mode
    private var expandW: CGFloat {
        switch sysEvt.currentMode {
        case .volume, .brightness, .micMute, .mediaKey: return 300
        default: return 380
        }
    }
    private var expandH: CGFloat {
        switch sysEvt.currentMode {
        case .volume, .brightness:  return 80
        case .micMute:              return 64
        case .mediaKey:             return 72
        case .music:                return 170
        case .calendar:             return 190
        }
    }

    private var curW: CGFloat { isExpanded ? expandW : pillW }
    private var curH: CGFloat { isExpanded ? expandH : pillH }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Black background
                NotchShape(cornerRadius: isExpanded ? 26 : 10, flareRadius: flare)
                    .fill(Color.black)
                    .frame(width: curW, height: curH)
                    .shadow(color: .black.opacity(isExpanded ? 0.55 : 0), radius: 22, y: 14)

                // Content — clipped to shape
                Group {
                    if isExpanded {
                        activeContent
                            .frame(width: expandW, height: expandH)
                            .transition(.opacity)
                    }
                }
                .clipShape(NotchShape(cornerRadius: isExpanded ? 26 : 10, flareRadius: flare))
                .frame(width: curW, height: curH)
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.74), value: isExpanded)
            .animation(.spring(response: 0.38, dampingFraction: 0.74), value: curH)
            .animation(.spring(response: 0.38, dampingFraction: 0.74), value: curW)
            .animation(.spring(response: 0.3,  dampingFraction: 0.8),  value: sysEvt.currentMode)
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
            // Horizontal swipe — changes music/calendar tabs
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onEnded { val in
                        guard isExpanded, isMusicMode else { return }
                        if val.translation.width < -25 {
                            withAnimation { activeTab = min(activeTab + 1, 1) }
                        } else if val.translation.width > 25 {
                            withAnimation { activeTab = max(activeTab - 1, 0) }
                        }
                    }
            )
            // Scroll wheel via notification from NotchHostingView.scrollWheel
            .onReceive(NotificationCenter.default.publisher(for: .notchScrollWheel)) { notif in
                guard isExpanded, isMusicMode,
                      let dy = notif.userInfo?["dy"] as? CGFloat else { return }
                if dy > 5 {
                    withAnimation { activeTab = min(activeTab + 1, 1) }
                } else if dy < -5 {
                    withAnimation { activeTab = max(activeTab - 1, 0) }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isMusicMode: Bool {
        sysEvt.currentMode == .music || sysEvt.currentMode == .calendar
    }

    @ViewBuilder
    private var activeContent: some View {
        switch sysEvt.currentMode {
        case .volume(let v):
            SystemHUDView(
                icon: v == 0 ? "speaker.slash.fill" : (v < 0.4 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"),
                label: "Volume",
                value: CGFloat(v),
                color: .white
            )
        case .brightness(let b):
            SystemHUDView(icon: "sun.max.fill", label: "Brightness", value: CGFloat(b), color: .yellow)

        case .mediaKey(let k):
            MediaKeyHUDView(event: k, music: music)

        case .micMute(let m):
            MicHUDView(muted: m)

        default: // .music or .calendar
            VStack(spacing: 0) {
                // Tab dots
                if isMusicMode {
                    HStack(spacing: 5) {
                        Circle().fill(activeTab == 0 ? .white : Color.white.opacity(0.3)).frame(width: 4, height: 4)
                        Circle().fill(activeTab == 1 ? .white : Color.white.opacity(0.3)).frame(width: 4, height: 4)
                    }
                    .padding(.top, 9)
                    .allowsHitTesting(false)
                }

                if activeTab == 0 {
                    NowPlayingNotchView(music: music)
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
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: activeTab)
        }
    }
}

// MARK: - System HUD (Volume / Brightness)

struct SystemHUDView: View {
    let icon:  String
    let label: String
    let value: CGFloat
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))

                // Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15)).frame(height: 6)
                        Capsule().fill(color)
                            .frame(width: max(6, geo.size.width * value), height: 6)
                    }
                }
                .frame(height: 6)
            }

            Text("\(Int(value * 100))%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Media Key HUD

struct MediaKeyHUDView: View {
    let event: NotchMode.MediaKeyKind
    @ObservedObject var music: MusicManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(music.trackName.isEmpty ? "—" : music.trackName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(music.artistName.isEmpty ? "" : music.artistName)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var iconName: String {
        switch event {
        case .play:     return "play.fill"
        case .pause:    return "pause.fill"
        case .next:     return "forward.fill"
        case .previous: return "backward.fill"
        }
    }
}

// MARK: - Mic HUD

struct MicHUDView: View {
    let muted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 22))
                .foregroundStyle(muted ? .red : .green)

            Text(muted ? "Microphone Off" : "Microphone On")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - Now Playing Notch View

struct NowPlayingNotchView: View {
    @ObservedObject var music: MusicManager

    @AppStorage("npShowShuffle")   private var showShuffle   = false
    @AppStorage("npShowRepeat")    private var showRepeat    = false
    @AppStorage("npShowFavorites") private var showFavorites = false
    @AppStorage("npLiveWaveform")  private var liveWaveform  = true

    // Seek drag
    @State private var isDraggingSeek = false
    @State private var seekPreview:    Double = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // ── Album art ───────────────────────────────────────────────
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [.purple.opacity(0.7), .blue.opacity(0.7)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    if let img = music.albumArt {
                        Image(nsImage: img)
                            .resizable().scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .frame(width: 44, height: 44)

                // ── Track info + waveform ───────────────────────────────────
                VStack(alignment: .leading, spacing: 2) {
                    Text(music.isPlaying ? music.trackName : "Nothing Playing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(music.isPlaying ? music.artistName : "Open Spotify or Music")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)

                    if music.isPlaying && liveWaveform {
                        WaveformView(isPlaying: music.isPlaying)
                            .frame(height: 14)
                    }
                }

                Spacer()

                // ── Player icon ─────────────────────────────────────────────
                Group {
                    if music.activePlayer == "Spotify" {
                        Image(systemName: "waveform.circle.fill").foregroundStyle(.green)
                    } else if music.activePlayer == "Music" {
                        Image(systemName: "music.note.list").foregroundStyle(.pink)
                    }
                }
                .font(.system(size: 14))
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // ── Scrubable progress bar ──────────────────────────────────────
            VStack(spacing: 3) {
                GeometryReader { geo in
                    let pct: CGFloat = music.trackDuration > 0
                        ? (isDraggingSeek
                            ? CGFloat(seekPreview / music.trackDuration)
                            : CGFloat(music.trackPosition / music.trackDuration))
                        : 0

                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1)).frame(height: 4)
                        Capsule().fill(Color.white.opacity(0.8))
                            .frame(width: max(4, geo.size.width * pct), height: 4)

                        // Thumb
                        Circle().fill(.white)
                            .frame(width: 9, height: 9)
                            .offset(x: max(0, geo.size.width * pct - 4.5))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                isDraggingSeek = true
                                let fraction = max(0, min(1, val.location.x / geo.size.width))
                                seekPreview = fraction * music.trackDuration
                            }
                            .onEnded { val in
                                let fraction = max(0, min(1, val.location.x / geo.size.width))
                                let newPos = fraction * music.trackDuration
                                music.seek(to: newPos)
                                isDraggingSeek = false
                            }
                    )
                }
                .frame(height: 10)

                HStack {
                    Text(music.formatTime(isDraggingSeek ? seekPreview : music.trackPosition))
                    Spacer()
                    let rem = music.trackDuration - (isDraggingSeek ? seekPreview : music.trackPosition)
                    Text(rem > 0 ? "-\(music.formatTime(rem))" : "")
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)

            // ── Controls ────────────────────────────────────────────────────
            HStack(spacing: 0) {
                if showShuffle {
                    IconButton(icon: "shuffle", size: 13, opacity: 0.45) { }
                    Spacer()
                }

                Spacer()

                IconButton(icon: "backward.fill", size: 19) { music.previousTrack() }

                Spacer().frame(width: 20)

                // Play/Pause — contentShape + highPriorityGesture to win over DragGesture
                Button {
                    music.playPause()
                } label: {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.12)).frame(width: 38, height: 38)
                        Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .highPriorityGesture(TapGesture().onEnded { music.playPause() })

                Spacer().frame(width: 20)

                IconButton(icon: "forward.fill", size: 19) { music.nextTrack() }

                Spacer()

                if showRepeat    { Spacer(); IconButton(icon: "repeat", size: 13, opacity: 0.45) { } }
                if showFavorites { Spacer(); IconButton(icon: "heart",  size: 13, opacity: 0.45) { } }
                if !showRepeat && !showFavorites {
                    IconButton(icon: "airplayaudio", size: 13, opacity: 0.45) { }
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
    }
}

// MARK: - Waveform (animated EQ bars)

struct WaveformView: View {
    let isPlaying: Bool

    @State private var heights: [CGFloat] = [0.4, 0.7, 0.5, 0.9, 0.6, 0.8, 0.4]
    @State private var timer: Timer?

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<heights.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.green.opacity(0.75))
                    .frame(width: 2.5, height: max(3, heights[i] * 12))
                    .animation(
                        .easeInOut(duration: Double.random(in: 0.2...0.45))
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.04),
                        value: heights[i]
                    )
            }
        }
        .onAppear { startAnimating() }
        .onDisappear { timer?.invalidate() }
        .onChange(of: isPlaying) { playing in
            if playing { startAnimating() } else { stopAnimating() }
        }
    }

    private func startAnimating() {
        guard isPlaying else { return }
        randomizeHeights()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            randomizeHeights()
        }
    }

    private func stopAnimating() {
        timer?.invalidate()
        withAnimation { heights = heights.map { _ in 0.15 } }
    }

    private func randomizeHeights() {
        withAnimation { heights = heights.map { _ in CGFloat.random(in: 0.2...1.0) } }
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon:    String
    let size:    CGFloat
    var opacity: Double = 1.0
    let action:  () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white.opacity(opacity))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Calendar Notch View

struct CalendarNotchView: View {
    @AppStorage("calDisplayMode") private var displayMode = 0

    private var cal:   Calendar { .current }
    private var today: Date     { Date() }

    private var dayName: String  { format("EEE").uppercased() }
    private var dayNum:  String  { format("d") }
    private var monthName: String { format("MMM").uppercased() }

    private func format(_ f: String) -> String {
        let df = DateFormatter(); df.dateFormat = f; return df.string(from: today)
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

    private let wds = ["M","T","W","T","F","S","S"]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(dayName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.red)
                Text(dayNum)
                    .font(.system(size: displayMode == 0 ? 46 : 64, weight: .thin))
                    .foregroundStyle(.white)
                    .padding(.top, -4)
                Spacer()
                VStack(alignment: .leading, spacing: 1) {
                    Text("No events today")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Your schedule is clear")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.bottom, 12)
            }
            .padding(.leading, 16)
            .padding(.top, 12)

            if displayMode == 0 {
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(monthName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.red)

                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { i in
                            Text(wds[i])
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(i >= 5 ? .white.opacity(0.25) : .white.opacity(0.4))
                                .frame(width: 19, alignment: .center)
                        }
                    }

                    ForEach(0..<monthGrid.count, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { col in
                                let t = monthGrid[row][col]
                                ZStack {
                                    if t == dayNum { Circle().fill(Color.red).frame(width: 16, height: 16) }
                                    Text(t)
                                        .font(.system(size: 9, weight: t == dayNum ? .bold : .regular))
                                        .foregroundStyle(t.isEmpty ? .clear : t == dayNum ? .white : .white.opacity(0.5))
                                }
                                .frame(width: 19, height: 16)
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
