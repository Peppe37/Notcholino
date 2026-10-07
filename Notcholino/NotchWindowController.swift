import AppKit
import SwiftUI

// MARK: - NSHostingView con scroll wheel e acceptsFirstMouse

final class NotchHostingView: NSHostingView<AnyView> {
    var notchID: UUID = UUID()

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        NotificationCenter.default.post(
            name: .notchScrollWheel,
            object: notchID,
            userInfo: ["dy": delta]
        )
    }
}

extension Notification.Name {
    static let notchScrollWheel = Notification.Name("notchScrollWheel")
    static let notchLayoutChanged = Notification.Name("notchLayoutChanged")
    static let notchMouseLeft = Notification.Name("notchMouseLeft")
    static let notchMouseEntered = Notification.Name("notchMouseEntered")
}

// MARK: - Window Controller

class NotchWindowController: NSWindowController {

    /// Size of the visible notch (not the window), used to decide where clicks are ours.
    private var notchSize = NSSize(width: 174, height: 32)
    private var monitors: [Any] = []
    let notchID = UUID()

    let targetScreen: NSScreen

    init(screen: NSScreen) {
        self.targetScreen = screen

        let W: CGFloat = 520
        let H: CGFloat = 310

        let panel = NSPanel(
            contentRect: NSRect(
                x: screen.frame.midX - W / 2,
                y: screen.frame.maxY - H,
                width: W, height: H),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)

        panel.backgroundColor    = .clear
        panel.isOpaque           = false
        panel.hasShadow          = false
        panel.level              = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovable          = false

        super.init(window: panel)

        let root = AnyView(NotchContentView(notchID: notchID))
        let hosting = NotchHostingView(rootView: root)
        hosting.notchID = notchID
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        // Don't let SwiftUI resize the window to its content (it did: 406x210, and
        // the constraint update loop crashed with NSGenericException)
        hosting.sizingOptions = []

        // Host inside a plain container so the hosting view can never drive the
        // window's size or size limits
        let container = NSView(frame: NSRect(origin: .zero, size: NSSize(width: W, height: H)))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container

        NotificationCenter.default.addObserver(
            forName: .notchLayoutChanged, object: notchID, queue: .main
        ) { [weak self] notif in
            guard let w = notif.userInfo?["w"] as? CGFloat,
                  let h = notif.userInfo?["h"] as? CGFloat else { return }
            self?.notchSize = NSSize(width: w, height: h)
            self?.updateMouseTransparency()
        }

        // The window stays at full size (resizing it made the expansion glitch), so
        // instead let clicks fall through to other apps whenever the cursor is
        // outside the visible notch.
        panel.ignoresMouseEvents = true
        let handler: (NSEvent) -> Void = { [weak self] _ in self?.updateMouseTransparency() }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: handler) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { e in handler(e); return e }) { monitors.append(l) }
    }

    deinit { monitors.forEach { NSEvent.removeMonitor($0) } }

    private func updateMouseTransparency() {
        guard let window else { return }
        let f = window.frame
        let rect = NSRect(x: f.midX - notchSize.width / 2, y: f.maxY - notchSize.height,
                          width: notchSize.width, height: notchSize.height).insetBy(dx: -4, dy: -4)
        let inside = rect.contains(NSEvent.mouseLocation)
        guard window.ignoresMouseEvents == inside else { return }
        window.ignoresMouseEvents = !inside
        // A window that ignores events never gets mouseExited, so tell the view
        if inside {
            NotificationCenter.default.post(name: .notchMouseEntered, object: notchID)
        } else {
            NotificationCenter.default.post(name: .notchMouseLeft, object: notchID)
        }
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
    let notchID: UUID
    @State private var isHovering   = false
    @State private var activeTab    = 0   // 0=music 1=calendar
    @State private var collapseTask: Task<Void, Never>?

    @StateObject private var music   = MusicManager()
    @StateObject private var sysEvt  = SystemEventsManager()
    @ObservedObject private var calMgr = CalendarManager.shared

    @AppStorage("notchWidth")  private var tuningW: Double = 0
    @AppStorage("notchHeight") private var tuningH: Double = 0

    // Collapsed pill (matches real MacBook notch ~162×32)
    private let baseW: CGFloat = 162
    private let baseH: CGFloat = 32
    private let flare: CGFloat = 12

    private var isPlayingCompact: Bool {
        music.isPlaying && !isHovering && !isSystemHudActive
    }

    private var isSystemHudActive: Bool {
        switch sysEvt.currentMode {
        case .volume, .brightness: return true
        default: return false
        }
    }

    private var pillW: CGFloat {
        let base = baseW + CGFloat(tuningW) + flare * 2
        return isPlayingCompact ? base + 130 : base // Extra width to clear wide MacBook Pro hardware notches
    }

    private var pillH: CGFloat { baseH + CGFloat(tuningH) }

    // Expanded size based on mode
    private var expandW: CGFloat {
        if isHovering { return 400 }
        return isSystemHudActive ? 340 : 400
    }

    private var expandH: CGFloat {
        let baseH: CGFloat = (activeTab == 0) ? (180 + 24) : (200 + 24)
        if isHovering {
            return isSystemHudActive ? baseH + 46 : baseH
        } else {
            switch sysEvt.currentMode {
            case .volume, .brightness: return 54 // scaled down from 60 to fit perfectly when closed
            default: return baseH
            }
        }
    }

    private var isExpanded: Bool {
        return isHovering || isSystemHudActive
    }

    private var curW: CGFloat { isExpanded ? expandW : pillW }
    private var curH: CGFloat { isExpanded ? expandH : pillH }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Invisible footprint to maintain size and catch hover
                Color.clear
                    .frame(width: curW, height: curH)
                    .contentShape(NotchShape(cornerRadius: isExpanded ? 28 : 10, flareRadius: flare))

                // Content Layer
                Group {
                    if isExpanded {
                        VStack(spacing: 0) {
                            if isHovering || !isSystemHudActive {
                                if activeTab == 0 {
                                    NowPlayingNotchView(music: music)
                                } else {
                                    CalendarNotchView()
                                }
                            }

                            if isSystemHudActive {
                                activeContent
                                    .frame(height: isHovering ? 46 : 54, alignment: .bottom)
                                    .padding(.bottom, isHovering ? 0 : 8)
                                    .scaleEffect(isHovering ? 0.7 : 0.85) // Scale down appropriately
                            }
                        }
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
            .onAppear { publishLayout() }
            .onChange(of: isHovering) { _ in publishLayout() }
            .onChange(of: sysEvt.currentMode) { _ in publishLayout() }
            .onChange(of: music.isPlaying) { _ in publishLayout() }
            .onChange(of: activeTab) { _ in publishLayout() }
            .onReceive(NotificationCenter.default.publisher(for: .notchMouseEntered)) { notif in
                if (notif.object as? UUID) == notchID { setHovering(true) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .notchMouseLeft)) { notif in
                if (notif.object as? UUID) == notchID { setHovering(false) }
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
                guard (notif.object as? UUID) == notchID,
                      isExpanded, isMusicMode,
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
        .environmentObject(calMgr)
    }

    private func setHovering(_ hovering: Bool) {
        collapseTask?.cancel()
        if hovering {
            withAnimation { isHovering = true }
        } else {
            collapseTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { withAnimation { isHovering = false } }
            }
        }
    }

    private func publishLayout() {
        NotificationCenter.default.post(
            name: .notchLayoutChanged, object: notchID,
            userInfo: ["w": curW, "h": curH])
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
            .padding(.leading, flare + 14)

            Spacer()

            // Right: Waveform
            WaveformView(isPlaying: true, fill: AnyShapeStyle(music.primaryColor))
                .frame(width: 24, height: 14)
                .padding(.trailing, flare + 14)
        }
    }

    // MARK: - Expanded Content
    @ViewBuilder
    private var activeContent: some View {
        switch sysEvt.currentMode {
        case .volume(let v):
            SystemHUDView(
                icon: v == 0 ? "speaker.slash.fill" : (v < 0.4 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"),
                value: CGFloat(v),
                isVolume: true
            )
        case .brightness(let b):
            SystemHUDView(icon: "sun.max.fill", value: CGFloat(b), isVolume: false)

        case .mediaKey, .micMute:
            EmptyView()

        default:
            VStack(spacing: 0) {
                // Hardware notch clearance spacer
                Spacer().frame(height: 24)

                if isMusicMode {
                    HStack(spacing: 6) {
                        Circle().fill(activeTab == 0 ? .white : Color.white.opacity(0.3)).frame(width: 5, height: 5)
                        Circle().fill(activeTab == 1 ? .white : Color.white.opacity(0.3)).frame(width: 5, height: 5)
                    }
                    .padding(.top, 4)
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
    let value: CGFloat
    let isVolume: Bool

    @AppStorage("soundTheme")      private var soundTheme = 1
    @AppStorage("soundShowText")   private var soundShowText = true

    @AppStorage("displayTheme")    private var displayTheme = 1
    @AppStorage("displayShowText") private var displayShowText = true

    private var barColor: Color {
        if isVolume {
            if soundTheme == 0 { return .white }
            if value > 0.8 { return .red }
            if value > 0.6 { return .yellow }
            return .white
        } else {
            if displayTheme == 0 { return .white }
            return .yellow
        }
    }

    private var textString: String {
        return "\(Int(value * 100))%"
    }

    private var showText: Bool {
        return isVolume ? soundShowText : displayShowText
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(barColor)
                .frame(width: 24)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15)).frame(height: 6)
                    Capsule().fill(barColor)
                        .frame(width: max(6, geo.size.width * value), height: 6)
                }
            }
            .frame(height: 6)

            if showText {
                Text(textString)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 50, alignment: .trailing)
            }
        }
        .padding(.horizontal, 24)
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

    @AppStorage("npLeftAccessory")  private var leftAccessory  = "shuffle"
    @AppStorage("npRightAccessory") private var rightAccessory = "repeat"
    @AppStorage("npLiveWaveform")   private var liveWaveform   = true
    @AppStorage("npColorStyle")     private var colorStyle     = 2

    @ObservedObject private var spotify = SpotifyAuth.shared

    @State private var isDraggingSeek = false
    @State private var seekPreview:    Double = 0
    @State private var iconScale: CGFloat = 1.0

    private var activeFill: AnyShapeStyle {
        switch colorStyle {
        case 0:
            return AnyShapeStyle(Color.white.opacity(0.85))
        case 1:
            return AnyShapeStyle(music.primaryColor)
        case 2:
            return music.primaryColor.spectrogramGradient()
        default:
            return AnyShapeStyle(Color.white.opacity(0.85))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(music.primaryColor.spectrogramGradient())
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
                }

                Spacer()

                if music.isPlaying && liveWaveform {
                    WaveformView(isPlaying: music.isPlaying, fill: activeFill)
                        .frame(width: 24, height: 16)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .contentShape(Rectangle())
            .onTapGesture {
                openActivePlayer()
            }

            VStack(spacing: 6) {
                GeometryReader { geo in
                    let pct: CGFloat = music.trackDuration > 0
                        ? (isDraggingSeek ? CGFloat(seekPreview / music.trackDuration) : CGFloat(music.trackPosition / music.trackDuration))
                        : 0

                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15)).frame(height: 6)
                        Capsule().fill(activeFill)
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

            // Fixed layout for buttons so they don't move around
            ZStack {
                // Left-aligned accessories
                HStack {
                    accessoryButton(type: leftAccessory)
                    Spacer()
                }

                // Center-aligned main controls
                HStack(spacing: 28) {
                    IconButton(icon: "backward.fill", size: 22) {
                        music.previousTrack()
                    }

                    Button {
                        togglePlayWithAnimation()
                    } label: {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.15)).frame(width: 44, height: 44)
                            Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .scaleEffect(iconScale)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .buttonStyle(.plain)
                    .highPriorityGesture(TapGesture().onEnded { togglePlayWithAnimation() })

                    IconButton(icon: "forward.fill", size: 22) {
                        music.nextTrack()
                    }
                }

                // Right-aligned accessories
                HStack {
                    Spacer()
                    accessoryButton(type: rightAccessory)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func accessoryButton(type: String) -> some View {
        switch type {
        case "shuffle":
            IconButton(icon: "shuffle", size: 15, opacity: music.isShuffleEnabled ? 1.0 : 0.5, color: music.isShuffleEnabled ? .green : .white) {
                music.toggleShuffle()
                music.isShuffleEnabled.toggle()
            }
        case "repeat":
            IconButton(icon: "repeat", size: 15, opacity: music.isRepeatEnabled ? 1.0 : 0.5, color: music.isRepeatEnabled ? .green : .white) {
                music.toggleRepeat()
                music.isRepeatEnabled.toggle()
            }
        case "like":
            if music.activePlayer == "Spotify" && !spotify.isConnected {
                // Likes on Spotify go through the Web API: connect first
                IconButton(icon: "heart.slash", size: 15, opacity: 0.3, color: .gray) {
                    if !spotify.clientID.isEmpty { spotify.connect() }
                }
            } else {
                let isLiked = music.isLiked
                IconButton(icon: isLiked ? "heart.fill" : "heart", size: 15, opacity: isLiked ? 1.0 : 0.5, color: isLiked ? .green : .white) {
                    music.toggleLike()
                    music.isLiked.toggle()
                }
            }
        case "devices":
            IconButton(icon: "airplayaudio", size: 15, opacity: 0.5, color: .white) { music.toggleAirPlay() }
        default:
            EmptyView()
        }
    }
    private func openActivePlayer() {
        let bundleID: String
        if music.activePlayer == "Spotify" {
            bundleID = "com.spotify.client"
        } else if music.activePlayer == "Music" {
            bundleID = "com.apple.Music"
        } else {
            return
        }

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        }
    }

    private func togglePlayWithAnimation() {
        music.playPause()
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            iconScale = 0.7
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                iconScale = 1.0
            }
        }
    }
}

// MARK: - Waveform

struct WaveformView: View {
    let isPlaying: Bool
    var fill: AnyShapeStyle = AnyShapeStyle(Color.green)

    @State private var heights: [CGFloat] = [0.4, 0.7, 0.5, 0.9, 0.6, 0.8, 0.4]
    @State private var timer: Timer?

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<heights.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(fill)
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
    var color:   Color  = .white
    let action:  () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(color.opacity(opacity))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Calendar Notch View

struct CalendarNotchView: View {
    @EnvironmentObject var calMgr: CalendarManager
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
                    if let event = calMgr.upcomingEvent {
                        HStack(alignment: .top, spacing: 6) {
                            Rectangle()
                                .fill(Color(nsColor: NSColor(cgColor: event.calendar.cgColor) ?? .red))
                                .frame(width: 3)
                                .cornerRadius(1.5)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                if let location = event.location, !location.isEmpty {
                                    Text(location)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .lineLimit(1)
                                }

                                Text("\(calMgr.formatTime(event.startDate)) - \(calMgr.formatTime(event.endDate))")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            calMgr.openCalendar(at: event.startDate)
                        }
                    } else if calMgr.hasAccess {
                        Text("No events today")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("Your schedule is clear")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    } else {
                        Text("No Calendar Access")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("Please grant permission")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.8))
                    }
                }
                .padding(.bottom, 20)
            }
            .padding(.leading, 32)
            .padding(.top, 16)

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
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if !t.isEmpty, let d = Int(t) {
                                        var comps = Calendar.current.dateComponents([.year, .month], from: Date())
                                        comps.day = d
                                        if let target = Calendar.current.date(from: comps) {
                                            calMgr.openCalendar(at: target)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.trailing, 28)
                .padding(.top, 24)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let url = URL(string: "ical://") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}
