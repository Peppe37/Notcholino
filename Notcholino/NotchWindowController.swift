import AppKit
import SwiftUI

// MARK: - NSHostingView con scroll wheel e acceptsFirstMouse

final class NotchHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

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

    private var isPlayingCompact: Bool {
        music.isPlaying && !isExpanded && sysEvt.currentMode == .music
    }

    private var pillW: CGFloat {
        let base = baseW + CGFloat(tuningW) + flare * 2
        return isPlayingCompact ? base + 90 : base // Add extra width for compact icons
    }
    
    private var pillH: CGFloat { baseH + CGFloat(tuningH) }

    // Expanded size based on mode
    private var expandW: CGFloat {
        switch sysEvt.currentMode {
        case .volume, .brightness, .micMute, .mediaKey: return 340
        default: return 400
        }
    }
    private var expandH: CGFloat {
        switch sysEvt.currentMode {
        case .volume, .brightness:  return 80
        case .micMute:              return 70
        case .mediaKey:             return 80
        case .music:                return 180
        case .calendar:             return 200
        }
    }

    private var curW: CGFloat { isExpanded ? expandW : pillW }
    private var curH: CGFloat { isExpanded ? expandH : pillH }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Invisible footprint to maintain size and catch hover
                Color.clear
                    .frame(width: curW, height: curH)

                // Content Layer
                Group {
                    if isExpanded {
                        activeContent
                            .frame(width: expandW, height: expandH)
                            .transition(.opacity)
                    } else if isPlayingCompact {
                        compactMusicContent
                            .frame(width: pillW, height: pillH)
                            .transition(.opacity)
                    }
                }
                .frame(width: curW, height: curH)
                // Perfect clipping to avoid ghosting
                .clipShape(NotchShape(cornerRadius: isExpanded ? 28 : 10, flareRadius: flare))
            }
            .background(
                // Background and Shadow Layer
                NotchShape(cornerRadius: isExpanded ? 28 : 10, flareRadius: flare)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(isExpanded ? 0.6 : 0), radius: 24, y: 16)
            )
            .animation(.spring(response: 0.38, dampingFraction: 0.74), value: isExpanded)
            .animation(.spring(response: 0.38, dampingFraction: 0.74), value: curH)
            .animation(.spring(response: 0.38, dampingFraction: 0.74), value: curW)
            .animation(.spring(response: 0.3,  dampingFraction: 0.8),  value: sysEvt.currentMode)
            .animation(.spring(response: 0.3,  dampingFraction: 0.8),  value: isPlayingCompact)
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
            // Horizontal swipe
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onEnded { val in
                        guard isExpanded, isMusicMode else { return }
                        if val.translation.width < -30 {
                            withAnimation { activeTab = min(activeTab + 1, 1) }
                        } else if val.translation.width > 30 {
                            withAnimation { activeTab = max(activeTab - 1, 0) }
                        }
                    }
            )
            // Scroll wheel
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

    // MARK: - Compact Content (Live Activity Style)
    @ViewBuilder
    private var compactMusicContent: some View {
        HStack(spacing: 0) {
            // Left: Album Art
            ZStack {
                if let img = music.albumArt {
                    Image(nsImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                }
            }
            .padding(.leading, flare + 12)

            Spacer()

            // Right: Waveform
            WaveformView(isPlaying: true, color: .green)
                .frame(width: 24, height: 14)
                .padding(.trailing, flare + 12)
        }
    }

    // MARK: - Expanded Content
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

        default:
            VStack(spacing: 0) {
                if isMusicMode {
                    HStack(spacing: 6) {
                        Circle().fill(activeTab == 0 ? .white : Color.white.opacity(0.3)).frame(width: 5, height: 5)
                        Circle().fill(activeTab == 1 ? .white : Color.white.opacity(0.3)).frame(width: 5, height: 5)
                    }
                    .padding(.top, 10)
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
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: activeTab)
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
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15)).frame(height: 8)
                        Capsule().fill(color)
                            .frame(width: max(8, geo.size.width * value), height: 8)
                    }
                }
                .frame(height: 8)
            }

            Text("\(Int(value * 100))%")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

// MARK: - Media Key HUD

struct MediaKeyHUDView: View {
    let event: NotchMode.MediaKeyKind
    @ObservedObject var music: MusicManager

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(music.trackName.isEmpty ? "—" : music.trackName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(music.artistName.isEmpty ? "" : music.artistName)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
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
        HStack(spacing: 16) {
            Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(muted ? .red : .green)
                .frame(width: 32)

            Text(muted ? "Microphone Off" : "Microphone On")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.horizontal, 24)
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

    @State private var isDraggingSeek = false
    @State private var seekPreview:    Double = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [.purple.opacity(0.7), .blue.opacity(0.7)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    if let img = music.albumArt {
                        Image(nsImage: img)
                            .resizable().scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text(music.isPlaying ? music.trackName : "Nothing Playing")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(music.isPlaying ? music.artistName : "Open Spotify or Music")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)

                    if music.isPlaying && liveWaveform {
                        WaveformView(isPlaying: music.isPlaying, color: .green)
                            .frame(height: 14)
                            .padding(.top, 2)
                    }
                }

                Spacer()

                Group {
                    if music.activePlayer == "Spotify" {
                        Image(systemName: "waveform.circle.fill").foregroundStyle(.green)
                    } else if music.activePlayer == "Music" {
                        Image(systemName: "music.note.list").foregroundStyle(.pink)
                    }
                }
                .font(.system(size: 18))
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)

            VStack(spacing: 6) {
                GeometryReader { geo in
                    let pct: CGFloat = music.trackDuration > 0
                        ? (isDraggingSeek ? CGFloat(seekPreview / music.trackDuration) : CGFloat(music.trackPosition / music.trackDuration))
                        : 0

                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15)).frame(height: 6)
                        Capsule().fill(Color.white.opacity(0.85))
                            .frame(width: max(6, geo.size.width * pct), height: 6)

                        Circle().fill(.white)
                            .frame(width: 12, height: 12)
                            .offset(x: max(0, geo.size.width * pct - 6))
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
                                music.seek(to: fraction * music.trackDuration)
                                isDraggingSeek = false
                            }
                    )
                }
                .frame(height: 12)

                HStack {
                    Text(music.formatTime(isDraggingSeek ? seekPreview : music.trackPosition))
                    Spacer()
                    let rem = music.trackDuration - (isDraggingSeek ? seekPreview : music.trackPosition)
                    Text(rem > 0 ? "-\(music.formatTime(rem))" : "")
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            HStack(spacing: 0) {
                if showShuffle {
                    IconButton(icon: "shuffle", size: 15, opacity: 0.5) { }
                    Spacer()
                }

                Spacer()
                IconButton(icon: "backward.fill", size: 22) { music.previousTrack() }
                Spacer().frame(width: 28)
                
                Button {
                    music.playPause()
                } label: {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.15)).frame(width: 44, height: 44)
                        Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .highPriorityGesture(TapGesture().onEnded { music.playPause() })

                Spacer().frame(width: 28)
                IconButton(icon: "forward.fill", size: 22) { music.nextTrack() }
                Spacer()

                if showRepeat    { Spacer(); IconButton(icon: "repeat", size: 15, opacity: 0.5) { } }
                if showFavorites { Spacer(); IconButton(icon: "heart",  size: 15, opacity: 0.5) { } }
                if !showRepeat && !showFavorites {
                    IconButton(icon: "airplayaudio", size: 15, opacity: 0.5) { }
                    Spacer()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Waveform

struct WaveformView: View {
    let isPlaying: Bool
    var color: Color = .green

    @State private var heights: [CGFloat] = [0.4, 0.7, 0.5, 0.9, 0.6, 0.8, 0.4]
    @State private var timer: Timer?

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<heights.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.opacity(0.85))
                    .frame(width: 3, height: max(4, heights[i] * 14))
                    .animation(
                        .easeInOut(duration: Double.random(in: 0.25...0.5))
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.05),
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.28, repeats: true) { _ in
            randomizeHeights()
        }
    }

    private func stopAnimating() {
        timer?.invalidate()
        withAnimation { heights = heights.map { _ in 0.2 } }
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
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white.opacity(opacity))
                .frame(width: 36, height: 36)
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

    private var dayName: String  { format("EEEE").uppercased() } // Full day name
    private var dayNum:  String  { format("d") }
    private var monthName: String { format("MMMM yyyy").uppercased() } // Full month year

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
            VStack(alignment: .leading, spacing: 2) {
                Text(dayName)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.red)
                Text(dayNum)
                    .font(.system(size: displayMode == 0 ? 56 : 76, weight: .light))
                    .foregroundStyle(.white)
                    .padding(.top, -8)
                    .padding(.bottom, 4)
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("No events today")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("Your schedule is clear")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.bottom, 20)
            }
            .padding(.leading, 32)
            .padding(.top, 24)

            if displayMode == 0 {
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(monthName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.red)
                        .padding(.bottom, 2)

                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { i in
                            Text(wds[i])
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(i >= 5 ? .white.opacity(0.3) : .white.opacity(0.5))
                                .frame(width: 22, alignment: .center)
                        }
                    }

                    ForEach(0..<monthGrid.count, id: \.self) { row in
                        HStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { col in
                                let t = monthGrid[row][col]
                                ZStack {
                                    if t == dayNum { Circle().fill(Color.red).frame(width: 20, height: 20) }
                                    Text(t)
                                        .font(.system(size: 11, weight: t == dayNum ? .bold : .medium))
                                        .foregroundStyle(t.isEmpty ? .clear : t == dayNum ? .white : .white.opacity(0.6))
                                }
                                .frame(width: 22, height: 20)
                            }
                        }
                    }
                }
                .padding(.trailing, 28)
                .padding(.top, 24)
            }
        }
    }
}
