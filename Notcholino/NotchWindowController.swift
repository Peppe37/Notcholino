import AppKit
import SwiftUI

class NotchWindowController: NSWindowController {
    
    init() {
        guard let screen = NSScreen.main else {
            super.init(window: nil)
            return
        }
        
        let windowWidth: CGFloat = 500
        let windowHeight: CGFloat = 250
        
        let windowRect = NSRect(
            x: (screen.frame.width - windowWidth) / 2,
            y: screen.frame.height - windowHeight,
            width: windowWidth,
            height: windowHeight
        )
        
        let window = NSPanel(
            contentRect: windowRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        
        super.init(window: window)
        
        let hostingView = NSHostingView(rootView: NotchContentView())
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = hostingView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Custom Shape

struct NotchShape: Shape {
    var cornerRadius: CGFloat
    var flareRadius: CGFloat
    
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadius, flareRadius) }
        set {
            cornerRadius = newValue.first
            flareRadius = newValue.second
        }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let r1 = flareRadius
        let r2 = cornerRadius
        
        path.move(to: CGPoint(x: 0, y: 0))
        // Top-left flare
        path.addArc(center: CGPoint(x: 0, y: r1), radius: r1, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        // Bottom-left corner
        path.addArc(center: CGPoint(x: r1 + r2, y: h - r2), radius: r2, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        // Bottom-right corner
        path.addArc(center: CGPoint(x: w - r1 - r2, y: h - r2), radius: r2, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        // Top-right flare
        path.addArc(center: CGPoint(x: w, y: r1), radius: r1, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        
        path.closeSubpath()
        return path
    }
}

// MARK: - Main Notch View

struct NotchContentView: View {
    @State private var isExpanded = false
    @State private var hoverDelayTask: Task<Void, Never>? = nil
    @State private var activeTab = 0 // 0: Now Playing, 1: Calendar
    @State private var dragOffset: CGFloat = 0
    
    @AppStorage("notchWidth") private var tuningWidth: Double = 0
    @AppStorage("notchHeight") private var tuningHeight: Double = 0
    
    let baseWidth: CGFloat = 160
    let baseHeight: CGFloat = 32
    let flareRadius: CGFloat = 12
    
    var currentWidth: CGFloat {
        if isExpanded {
            return 400
        }
        return baseWidth + CGFloat(tuningWidth) + (flareRadius * 2)
    }
    
    var currentHeight: CGFloat {
        if isExpanded {
            return activeTab == 0 ? 160 : 180
        }
        return baseHeight + CGFloat(tuningHeight)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Background shadow layer
                NotchShape(
                    cornerRadius: isExpanded ? 32 : 12,
                    flareRadius: flareRadius
                )
                .fill(Color.black)
                .frame(width: currentWidth, height: currentHeight)
                .shadow(color: .black.opacity(isExpanded ? 0.4 : 0), radius: 15, y: 10)
                
                // Content layer, strictly clipped to prevent ghosting
                ZStack(alignment: .top) {
                    if isExpanded {
                        Group {
                            if activeTab == 0 {
                                NowPlayingNotchView()
                                    .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                            } else {
                                CalendarNotchView()
                                    .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                            }
                        }
                        .frame(width: 400 - (flareRadius * 2))
                        .padding(.top, 10)
                        // This prevents any delay in disappearance creating ghosting out of bounds
                    }
                }
                .frame(width: currentWidth, height: currentHeight)
                .clipShape(
                    NotchShape(
                        cornerRadius: isExpanded ? 32 : 12,
                        flareRadius: flareRadius
                    )
                )
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: isExpanded)
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: activeTab)
            .onHover { hovering in
                hoverDelayTask?.cancel()
                if hovering {
                    withAnimation { isExpanded = true }
                } else {
                    hoverDelayTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        if !Task.isCancelled {
                            withAnimation { isExpanded = false }
                        }
                    }
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if isExpanded {
                            dragOffset = value.translation.width
                        }
                    }
                    .onEnded { value in
                        if isExpanded {
                            dragOffset = 0
                            if value.translation.width < -40 {
                                // Swipe left
                                withAnimation { activeTab = (activeTab + 1) % 2 }
                            } else if value.translation.width > 40 {
                                // Swipe right
                                withAnimation { activeTab = (activeTab - 1 + 2) % 2 }
                            }
                        }
                    }
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 0)
    }
}

// MARK: - Now Playing View (Replica)

struct NowPlayingNotchView: View {
    @StateObject private var musicManager = MusicManager()
    
    @AppStorage("npPlayer") private var npPlayer = 0 // 0: Auto, 1: Apple Music, 2: Spotify, 3: YT Music
    @AppStorage("npShowShuffle") private var npShowShuffle = false
    @AppStorage("npShowRepeat") private var npShowRepeat = false
    @AppStorage("npShowFavorites") private var npShowFavorites = false
    
    func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let min = totalSeconds / 60
        let sec = totalSeconds % 60
        return String(format: "%d:%02d", min, sec)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Top row
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Color.purple, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text(musicManager.isPlaying ? (musicManager.trackName.prefix(2).uppercased()) : "...")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(musicManager.trackName.isEmpty ? "Not Playing" : musicManager.trackName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(musicManager.artistName.isEmpty ? "No Artist" : musicManager.artistName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if musicManager.activePlayer == "Spotify" || npPlayer == 2 {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 18))
                } else if musicManager.activePlayer == "Music" || npPlayer == 1 {
                    Image(systemName: "applelogo")
                        .foregroundColor(.pink)
                        .font(.system(size: 16))
                }
                
                Image(systemName: "ellipsis")
                    .foregroundColor(.purple)
                    .font(.system(size: 18, weight: .bold))
                    .padding(.leading, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            
            // Progress Bar
            HStack(spacing: 8) {
                Text(formatTime(musicManager.trackPosition))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.gray)
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                            .frame(height: 6)
                        
                        let progress = musicManager.trackDuration > 0 ? (musicManager.trackPosition / musicManager.trackDuration) : 0
                        Capsule().fill(Color.purple)
                            .frame(width: max(0, geo.size.width * CGFloat(progress)), height: 6)
                    }
                }
                .frame(height: 6)
                
                let remaining = musicManager.trackDuration - musicManager.trackPosition
                Text(remaining > 0 ? "-\(formatTime(remaining))" : "0:00")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 20)
            
            // Controls
            HStack(spacing: (npShowShuffle || npShowRepeat || npShowFavorites) ? 20 : 36) {
                if npShowShuffle {
                    Image(systemName: "shuffle")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
                
                Button(action: { musicManager.previousTrack() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }.buttonStyle(.plain)
                
                Button(action: { musicManager.playPause() }) {
                    Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }.buttonStyle(.plain)
                
                Button(action: { musicManager.nextTrack() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }.buttonStyle(.plain)
                
                if npShowRepeat {
                    Image(systemName: "repeat")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
                
                if npShowFavorites {
                    Image(systemName: "heart")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                }
                
                if !npShowFavorites && !npShowRepeat {
                    Image(systemName: "airplayaudio")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                }
            }
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Calendar View (Replica)

struct CalendarNotchView: View {
    @AppStorage("calDisplayMode") private var calDisplayMode = 0 // 0: Full Month, 1: Today Only
    
    let days = ["M", "T", "W", "T", "F", "S", "S"]
    let dates = [
        ["", "", "", "1", "2", "3", "4"],
        ["5", "6", "7", "8", "9", "10", "11"],
        ["12", "13", "14", "15", "16", "17", "18"],
        ["19", "20", "21", "22", "23", "24", "25"],
        ["26", "27", "28", "29", "30", "31", ""]
    ]
    
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Left side
            VStack(alignment: calDisplayMode == 1 ? .center : .leading, spacing: 4) {
                Text("TUE")
                    .font(.system(size: calDisplayMode == 1 ? 16 : 14, weight: .bold))
                    .foregroundColor(.red)
                Text("6")
                    .font(.system(size: calDisplayMode == 1 ? 64 : 48, weight: .light))
                    .foregroundColor(.white)
                    .padding(.top, -10)
                
                Spacer()
                
                Text("No more events today")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.gray)
                Text("Your day is clear")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray.opacity(0.6))
            }
            .padding(.top, 16)
            .padding(.leading, calDisplayMode == 1 ? 0 : 20)
            .padding(.bottom, 20)
            .frame(maxWidth: calDisplayMode == 1 ? .infinity : nil)
            
            if calDisplayMode == 0 {
                Spacer()
                
                // Right side (Mini Calendar)
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        ForEach(0..<7, id: \.self) { i in
                            Text(days[i])
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(i >= 5 ? .gray : .white)
                                .frame(width: 18, alignment: .center)
                        }
                    }
                    
                    ForEach(0..<dates.count, id: \.self) { row in
                        HStack(spacing: 12) {
                            ForEach(0..<7, id: \.self) { col in
                                let text = dates[row][col]
                                if text == "6" {
                                    Text(text)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 20, height: 20)
                                        .background(Circle().fill(Color.red))
                                } else {
                                    Text(text)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(text.isEmpty ? .clear : .gray)
                                        .frame(width: 20, height: 20)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.trailing, 20)
                .overlay(
                    Text("OCT")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red)
                        .padding(.top, 16)
                        .padding(.trailing, 20)
                    , alignment: .topTrailing
                )
            }
        }
    }
}
