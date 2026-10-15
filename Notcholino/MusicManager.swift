// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import AppKit
import SwiftUI
import Combine

final class MusicManager: NSObject, ObservableObject {

    @Published var trackName:    String   = ""
    @Published var artistName:   String   = ""
    @Published var albumArt:     NSImage? = nil
    @Published var isPlaying:    Bool     = false { didSet { updateTickTimer() } }
    @Published var activePlayer: String   = "None"
    @Published var trackDuration: Double  = 0
    @Published var trackPosition: Double  = 0
    @Published var isShuffleEnabled: Bool = false
    @Published var isRepeatEnabled:  Bool = false
    @Published var isLiked:          Bool = false
    /// True when what is shown comes from the system "Now Playing" (a browser tab, another player...) rather
    /// than from Spotify or Music: those have no shuffle, repeat or like, and are controlled through the system
    @Published var isGenericSource:  Bool = false
    /// Bundle id of the app playing, so a click on the song can bring it to the front
    @Published var activeBundleID:   String = ""
    private var spotifyTrackURI = ""

    private struct ScriptInfo {
        var player, name, artist: String
        var duration, position: Double
        var artURL: String
        var shuffle, repeating: Bool
        var loved, uri: String
        var playing: Bool
    }
    /// The two sources: what AppleScript reads from Spotify/Music, and what the system reports for everything
    private var scriptInfo: ScriptInfo?
    private var systemInfo: SystemNowPlaying?
    private var systemCancellable: AnyCancellable?
    private var identity = ""
    private var lastArtworkKey = 0

    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var isFetching    = false
    private var lastTrackName = ""

    /// Bundle ids of the players we can read
    private static let playerBundleIDs = ["com.spotify.client", "com.apple.Music"]
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    override init() {
        super.init()
        fetchNowPlaying()

        systemCancellable = SystemNowPlayingMonitor.shared.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                self?.systemInfo = info
                self?.recompute()
            }

        // Refresh when a player says something changed, instead of polling to find out
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            let token = distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.fetchNowPlaying()
            }
            observers.append((distributed, token))
        }
        // ...and when a player is opened or quit
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let id = app?.bundleIdentifier, Self.playerBundleIDs.contains(id) else { return }
                self?.fetchNowPlaying()
            }
            observers.append((workspace, token))
        }
    }

    deinit {
        pollTimer?.invalidate()
        tickTimer?.invalidate()
        observers.forEach { $0.center.removeObserver($0.token) }
    }

    /// True when Spotify or Music is open: with neither, there is nothing to ask (and no process to spawn)
    private var isAnyPlayerRunning: Bool {
        Self.playerBundleIDs.contains { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
    }

    /// Next safety poll (position drift, missed notifications): only while a player is open
    private func schedulePoll() {
        DispatchQueue.main.async {
            self.pollTimer?.invalidate()
            self.pollTimer = nil
            guard self.isAnyPlayerRunning else { return }
            let interval: TimeInterval = self.isPlaying ? 3 : 8
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                self?.fetchNowPlaying()
            }
        }
    }

    /// The 1 s position tick only runs while something is playing
    private func updateTickTimer() {
        if isPlaying, tickTimer == nil {
            tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.trackPosition = min(self.trackPosition + 1.0, self.trackDuration)
            }
        } else if !isPlaying {
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    // MARK: - Fetch track info

    func fetchNowPlaying() {
        guard !isFetching else { return }

        guard isAnyPlayerRunning else {
            // Nothing to read: no need to launch osascript
            DispatchQueue.main.async {
                self.scriptInfo = nil
                self.recompute()
            }
            schedulePoll()
            return
        }
        isFetching = true

        // Default player preference: 0 auto, 1 Music, 2 Spotify
        let preferred = UserDefaults.standard.integer(forKey: "npPlayer")
        let script = """
        set pref to \(preferred)
        set sOut to ""
        set mOut to ""
        if pref is not 1 and application "Spotify" is running then
            tell application "Spotify"
                if player state is playing or player state is paused then
                    try
                        set d to (duration of current track) / 1000
                    on error
                        set d to 0
                    end try
                    try
                        set artURL to artwork url of current track
                    on error
                        set artURL to ""
                    end try
                    try
                        set shuf to shuffling
                    on error
                        set shuf to false
                    end try
                    try
                        set rep to repeating
                    on error
                        set rep to false
                    end try
                    try
                        set tId to id of current track
                    on error
                        set tId to ""
                    end try
                    set sOut to "Spotify|||" & (name of current track) & "|||" & (artist of current track) & "|||" & (d as string) & "|||" & (player position as string) & "|||" & artURL & "|||" & (shuf as string) & "|||" & (rep as string) & "|||unknown|||" & tId & "|||" & (player state as string)
                end if
            end tell
        end if
        if pref is not 2 and application "Music" is running then
            tell application "Music"
                if player state is playing or player state is paused then
                    try
                        set d to duration of current track
                    on error
                        set d to 0
                    end try
                    try
                        set shuf to shuffle enabled
                    on error
                        set shuf to false
                    end try
                    try
                        set rep to (song repeat as string)
                    on error
                        set rep to "off"
                    end try
                    try
                        set lvd to loved of current track
                    on error
                        set lvd to false
                    end try
                    set mOut to "Music|||" & (name of current track) & "|||" & (artist of current track) & "|||" & (d as string) & "|||" & (player position as string) & "|||" & "|||" & (shuf as string) & "|||" & rep & "|||" & (lvd as string) & "|||" & "|||" & (player state as string)
                end if
            end tell
        end if
        -- Whatever is playing wins; otherwise show what is paused
        if sOut ends with "playing" then return sOut
        if mOut ends with "playing" then return mOut
        if sOut is not "" then return sOut
        if mOut is not "" then return mOut
        return "None|||"
        """

        runOsascript(script) { [weak self] result in
            guard let self else { return }
            self.isFetching = false
            self.schedulePoll()
            guard let raw = result, !raw.isEmpty, raw != "None|||" else {
                DispatchQueue.main.async {
                    self.scriptInfo = nil
                    self.recompute()
                }
                return
            }

            let parts = raw.components(separatedBy: "|||")
            guard parts.count >= 5 else { return }
            let number: (String) -> Double = { Double($0.replacingOccurrences(of: ",", with: ".")) ?? 0 }
            let player = parts[0]
            let info = ScriptInfo(
                player: player, name: parts[1], artist: parts[2],
                duration: number(parts[3]), position: number(parts[4]),
                artURL: parts.count > 5 ? parts[5] : "",
                shuffle: parts.count > 6 ? parts[6] == "true" : false,
                repeating: parts.count > 7 ? (parts[7] == "true" || parts[7] == "all" || parts[7] == "one") : false,
                loved: parts.count > 8 ? parts[8] : "false",
                uri: (player == "Spotify" && parts.count > 9) ? parts[9] : "",
                playing: (parts.count > 10 ? parts[10] : "playing") == "playing")
            DispatchQueue.main.async {
                self.scriptInfo = info
                self.recompute()
            }
        }
    }

    // MARK: - Choosing and showing the source

    /// Spotify and Music are read with AppleScript, which gives more (shuffle, repeat, likes). Anything else
    /// comes from the system. When both report something, the system's pick wins unless it is Spotify or Music.
    private func shouldUseSystem() -> Bool {
        guard SystemNowPlayingMonitor.shared.isEnabled, let sys = systemInfo else { return false }
        if Self.playerBundleIDs.contains(sys.appBundleID) { return scriptInfo == nil }
        return sys.playing || scriptInfo == nil
    }

    private func recompute() {
        if shouldUseSystem(), let sys = systemInfo {
            applySystem(sys)
        } else if let info = scriptInfo {
            applyScript(info)
        } else {
            isGenericSource = false
            activeBundleID = ""
            isPlaying = false
            trackName = ""
            artistName = ""
            activePlayer = "None"
            identity = ""
        }
    }

    private func applySystem(_ sys: SystemNowPlaying) {
        isGenericSource = true
        activePlayer = sys.appName
        activeBundleID = sys.appBundleID
        artistName = sys.artist
        isPlaying = sys.playing
        trackDuration = sys.duration
        isShuffleEnabled = false
        isRepeatEnabled = false
        isLiked = false

        let key = "\(sys.bundleID)|\(sys.title)|\(sys.artist)"
        if identity != key {
            identity = key
            trackName = sys.title
            trackPosition = sys.position
            spotifyTrackURI = ""
            lastArtworkKey = 0
            albumArt = nil
            primaryColor = .white
            secondaryColor = .white
        } else if abs(trackPosition - sys.position) > 1.5 || !sys.playing {
            trackPosition = sys.position
        }
        // Artwork often arrives a moment after the title
        if let art = sys.artwork, sys.artworkKey != lastArtworkKey {
            lastArtworkKey = sys.artworkKey
            albumArt = art
            updateColors(for: art)
        }
    }

    private func applyScript(_ info: ScriptInfo) {
        isGenericSource = false
        activeBundleID = info.player == "Spotify" ? PermissionsManager.spotifyID : PermissionsManager.musicID
        activePlayer = info.player
        artistName = info.artist
        isPlaying = info.playing
        trackDuration = info.duration
        isShuffleEnabled = info.shuffle
        isRepeatEnabled = info.repeating

        // Only reset position and local states if the track changed
        let key = "\(info.player)|\(info.name)|\(info.artist)"
        if identity != key {
            identity = key
            trackPosition = info.position
            trackName = info.name

            // If unknown (Spotify), default to false until the Web API answers.
            isLiked = (info.loved == "true")
            spotifyTrackURI = info.uri
            refreshSpotifyLike(uri: info.uri)

            fetchArtwork(player: info.player, urlString: info.artURL)
        } else {
            // Track is the same. If status is unknown, preserve our local toggled state.
            if info.loved != "unknown" { isLiked = (info.loved == "true") }
            if abs(trackPosition - info.position) > 1.5 || !info.playing { trackPosition = info.position }
        }
    }

    @Published var primaryColor:   Color = .white
    @Published var secondaryColor: Color = .white

    // MARK: - Album Artwork

    private func fetchArtwork(player: String, urlString: String) {
        if player == "Spotify", let url = URL(string: urlString), !urlString.isEmpty {
            // Spotify provides a CDN URL — download it
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async { 
                    self?.albumArt = img 
                    self?.updateColors(for: img)
                }
            }.resume()
        } else if player == "Music" {
            // Apple Music: extract artwork via osascript saving to temp file
            let tmp = NSTemporaryDirectory() + "notcholino_art.jpg"
            let artScript = """
            tell application "Music"
                try
                    set artData to data of artwork 1 of current track
                    set f to open for access POSIX file "\(tmp)" with write permission
                    set eof f to 0
                    write artData to f
                    close access f
                    return "ok"
                on error
                    return "err"
                end try
            end tell
            """
            runOsascript(artScript) { [weak self] result in
                guard result == "ok",
                      let img = NSImage(contentsOfFile: tmp) else { return }
                DispatchQueue.main.async { 
                    self?.albumArt = img 
                    self?.updateColors(for: img)
                }
            }
        } else {
            DispatchQueue.main.async { 
                self.albumArt = nil 
                self.primaryColor = .white
                self.secondaryColor = .white
            }
        }
    }

    private func updateColors(for image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let ciImage = CIImage(cgImage: cgImage)
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        let leftRect = CIVector(x: 0, y: 0, z: width/2, w: height)
        let rightRect = CIVector(x: width/2, y: 0, z: width/2, w: height)
        
        func averageColor(rect: CIVector) -> Color {
            guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ciImage, kCIInputExtentKey: rect]),
                  let outputImage = filter.outputImage else { return .white }
            
            var bitmap = [UInt8](repeating: 0, count: 4)
            let context = CIContext(options: [.workingColorSpace: kCFNull!])
            context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
            
            // CoreImage provides premultiplied ARGB or RGBA. Using RGBA8:
            return Color(red: Double(bitmap[0]) / 255.0, green: Double(bitmap[1]) / 255.0, blue: Double(bitmap[2]) / 255.0)
        }
        
        self.primaryColor = averageColor(rect: leftRect)
        self.secondaryColor = averageColor(rect: rightRect)
    }

    // MARK: - Controls

    /// AppleScript for the player currently shown in the notch. With both Spotify and Music open, the command
    /// goes to the one being displayed; with nothing known yet it goes to whichever is running.
    private func controlScript(spotify: String, music: String) -> String {
        func block(_ app: String, _ body: String) -> String {
            "if application \"\(app)\" is running then\n tell application \"\(app)\"\n\(body)\n end tell\nend if"
        }
        switch activePlayer {
        case "Spotify": return block("Spotify", spotify)
        case "Music":   return block("Music", music)
        default:
            return "if application \"Spotify\" is running then\n tell application \"Spotify\"\n\(spotify)\n end tell\nelse if application \"Music\" is running then\n tell application \"Music\"\n\(music)\n end tell\nend if"
        }
    }

    private func refreshSoon(forgetTrack: Bool = false) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isFetching = false
            if forgetTrack { self?.lastTrackName = "" }
            self?.fetchNowPlaying()
        }
    }

    func playPause() {
        if isGenericSource { SystemNowPlayingMonitor.shared.send(.togglePlayPause); return }
        runOsascript(controlScript(spotify: "playpause", music: "playpause")) { [weak self] _ in self?.refreshSoon() }
    }

    func nextTrack() {
        if isGenericSource { SystemNowPlayingMonitor.shared.send(.next); return }
        runOsascript(controlScript(spotify: "next track", music: "next track")) { [weak self] _ in self?.refreshSoon(forgetTrack: true) }
    }

    func previousTrack() {
        if isGenericSource { SystemNowPlayingMonitor.shared.send(.previous); return }
        runOsascript(controlScript(spotify: "previous track", music: "previous track")) { [weak self] _ in self?.refreshSoon(forgetTrack: true) }
    }

    func seek(to position: Double) {
        let pos = max(0, position)
        DispatchQueue.main.async { self.trackPosition = pos }
        if isGenericSource { SystemNowPlayingMonitor.shared.seek(to: pos); return }
        runOsascript(controlScript(spotify: "set player position to \(pos)", music: "set player position to \(pos)")) { _ in }
    }

    func toggleShuffle() {
        guard !isGenericSource else { return }
        runOsascript(controlScript(spotify: "set shuffling to not shuffling", music: "set shuffle enabled to not shuffle enabled")) { _ in }
    }

    func toggleRepeat() {
        guard !isGenericSource else { return }
        runOsascript(controlScript(
            spotify: "set repeating to not repeating",
            music: "if song repeat is off then\n set song repeat to all\n else\n set song repeat to off\n end if")) { _ in }
    }

    private func refreshSpotifyLike(uri: String) {
        guard !uri.isEmpty, SpotifyAuth.shared.isConnected else { return }
        Task {
            guard let saved = await SpotifyAuth.shared.isSaved(trackURI: uri) else { return }
            await MainActor.run {
                if self.spotifyTrackURI == uri { self.isLiked = saved }
            }
        }
    }

    func toggleLike() {
        guard !isGenericSource else { return }
        if activePlayer == "Spotify" {
            let uri = spotifyTrackURI
            let target = !isLiked   // the view flips isLiked right after this call
            guard !uri.isEmpty, SpotifyAuth.shared.isConnected else { return }
            Task {
                let auth = SpotifyAuth.shared
                _ = await auth.setSaved(target, trackURI: uri)
                // Trust the server, not the optimistic toggle: verify, retry once on legacy endpoints
                try? await Task.sleep(nanoseconds: 400_000_000)
                var actual = await auth.isSaved(trackURI: uri)
                if actual != target {
                    print("Spotify like mismatch (wanted \(target), got \(String(describing: actual))), retrying on legacy endpoint")
                    _ = await auth.setSaved(target, trackURI: uri, legacy: true)
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    actual = await auth.isSaved(trackURI: uri)
                }
                guard let actual else { return }
                await MainActor.run { if self.spotifyTrackURI == uri { self.isLiked = actual } }
            }
            return
        }
        runOsascript("""
        if application "Music" is running then
            tell application "Music"
                if loved of current track is true then
                    set loved of current track to false
                else
                    set loved of current track to true
                end if
            end tell
        end if
        """) { _ in }
    }

    func toggleAirPlay() {
        // Open Sound Settings in macOS Control Center/Settings
        runOsascript("""
        tell application "System Settings"
            activate
            reveal pane id "com.apple.Sound-Settings.extension"
        end tell
        """) { _ in }
    }


    // MARK: - Helpers

    func formatTime(_ s: Double) -> String {
        guard s.isFinite && s >= 0 else { return "0:00" }
        let t = Int(s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    private func runOsascript(_ source: String, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .background).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments     = ["-e", source]
            let pipe           = Pipe()
            proc.standardOutput = pipe
            proc.standardError  = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                let data   = pipe.fileHandleForReading.readDataToEndOfFile()
                let result = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                completion(result?.isEmpty == false ? result : nil)
            } catch {
                completion(nil)
            }
        }
    }
}

// MARK: - Color Extensions
extension Color {
    func spectrogramGradient(secondary: Color? = nil) -> AnyShapeStyle {
        if let secondary = secondary {
            return AnyShapeStyle(LinearGradient(
                colors: [self, secondary],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
        
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        nsColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        // Shift hue by 180 degrees (0.5 in 0-1 scale)
        let opposingHue = fmod(hue + 0.5, 1.0)
        let opposingColor = Color(hue: Double(opposingHue), saturation: Double(saturation), brightness: Double(brightness), opacity: Double(alpha))
        
        return AnyShapeStyle(LinearGradient(
            colors: [self, opposingColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ))
    }
}
