import Foundation
import AppKit
import SwiftUI

final class MusicManager: NSObject, ObservableObject {

    @Published var trackName:    String   = ""
    @Published var artistName:   String   = ""
    @Published var albumArt:     NSImage? = nil
    @Published var isPlaying:    Bool     = false
    @Published var activePlayer: String   = "None"
    @Published var trackDuration: Double  = 0
    @Published var trackPosition: Double  = 0
    @Published var isShuffleEnabled: Bool = false
    @Published var isRepeatEnabled:  Bool = false
    @Published var isLiked:          Bool = false
    private var spotifyTrackURI = ""

    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var isFetching    = false
    private var lastTrackName = ""

    override init() {
        super.init()
        fetchNowPlaying()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.fetchNowPlaying()
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            DispatchQueue.main.async {
                self.trackPosition = min(self.trackPosition + 1.0, self.trackDuration)
            }
        }
    }

    deinit {
        pollTimer?.invalidate()
        tickTimer?.invalidate()
    }

    // MARK: - Fetch track info

    func fetchNowPlaying() {
        guard !isFetching else { return }
        isFetching = true

        let script = """
        set out to "None|||"
        if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    set d to (duration of current track) / 1000
                    set artURL to artwork url of current track
                    set shuf to shuffling
                    set rep to repeating
                    set out to "Spotify|||" & (name of current track) & "|||" & (artist of current track) & "|||" & (d as string) & "|||" & (player position as string) & "|||" & artURL & "|||" & (shuf as string) & "|||" & (rep as string) & "|||unknown|||" & (id of current track)
                end if
            end tell
        end if
        if out is "None|||" and application "Music" is running then
            tell application "Music"
                if player state is playing then
                    set d to duration of current track
                    set shuf to shuffle enabled
                    set rep to (song repeat as string)
                    set lvd to loved of current track
                    set out to "Music|||" & (name of current track) & "|||" & (artist of current track) & "|||" & (d as string) & "|||" & (player position as string) & "|||" & "|||" & (shuf as string) & "|||" & rep & "|||" & (lvd as string)
                end if
            end tell
        end if
        return out
        """

        runOsascript(script) { [weak self] result in
            guard let self else { return }
            self.isFetching = false
            guard let raw = result, !raw.isEmpty, raw != "None|||" else {
                DispatchQueue.main.async {
                    self.isPlaying = false
                    self.trackName = ""
                    self.artistName = ""
                    self.activePlayer = "None"
                }
                return
            }

            let parts = raw.components(separatedBy: "|||")
            guard parts.count >= 5 else { return }

            let player   = parts[0]
            let tName    = parts[1]
            let aName    = parts[2]
            let duration = Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0
            let position = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
            let artURL   = parts.count > 5 ? parts[5] : ""
            
            let isShuffling = (parts.count > 6) ? (parts[6] == "true") : false
            let isRepeating = (parts.count > 7) ? (parts[7] == "true" || parts[7] == "all" || parts[7] == "one") : false
            let isLovedStr  = (parts.count > 8) ? parts[8] : "false"
            let trackURI    = (player == "Spotify" && parts.count > 9) ? parts[9] : ""

            DispatchQueue.main.async {
                self.activePlayer  = player
                self.artistName    = aName
                self.isPlaying     = true
                self.trackDuration = duration
                self.isShuffleEnabled = isShuffling
                self.isRepeatEnabled  = isRepeating
                
                // Only reset position and local states if track changed
                if self.trackName != tName {
                    self.trackPosition = position
                    self.trackName = tName
                    
                    // If unknown (Spotify), default to false until the Web API answers.
                    self.isLiked = (isLovedStr == "true")
                    self.spotifyTrackURI = trackURI
                    self.refreshSpotifyLike(uri: trackURI)
                    
                    // Load new artwork
                    self.fetchArtwork(player: player, urlString: artURL)
                } else {
                    // Track is the same. If status is unknown, preserve our local toggled state.
                    if isLovedStr != "unknown" {
                        self.isLiked = (isLovedStr == "true")
                    }
                }
            }
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

    func playPause() {
        runOsascript("""
        if application "Spotify" is running then
            tell application "Spotify" to playpause
        else if application "Music" is running then
            tell application "Music" to playpause
        end if
        """) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.isFetching = false
                self?.fetchNowPlaying()
            }
        }
    }

    func nextTrack() {
        runOsascript("""
        if application "Spotify" is running then
            tell application "Spotify" to next track
        else if application "Music" is running then
            tell application "Music" to next track
        end if
        """) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.isFetching = false
                self?.lastTrackName = ""
                self?.fetchNowPlaying()
            }
        }
    }

    func previousTrack() {
        runOsascript("""
        if application "Spotify" is running then
            tell application "Spotify" to previous track
        else if application "Music" is running then
            tell application "Music" to previous track
        end if
        """) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.isFetching = false
                self?.lastTrackName = ""
                self?.fetchNowPlaying()
            }
        }
    }

    func seek(to position: Double) {
        let pos = max(0, position)
        DispatchQueue.main.async { self.trackPosition = pos }
        runOsascript("""
        if application "Spotify" is running then
            tell application "Spotify" to set player position to \(pos)
        else if application "Music" is running then
            tell application "Music" to set player position to \(pos)
        end if
        """) { _ in }
    }

    func toggleShuffle() {
        runOsascript("""
        if application "Spotify" is running then
            tell application "Spotify" to set shuffling to not shuffling
        else if application "Music" is running then
            tell application "Music" to set shuffle enabled to not shuffle enabled
        end if
        """) { _ in }
    }

    func toggleRepeat() {
        runOsascript("""
        if application "Spotify" is running then
            tell application "Spotify"
                if repeating then
                    set repeating to false
                else
                    set repeating to true
                end if
            end tell
        else if application "Music" is running then
            tell application "Music"
                if song repeat is off then
                    set song repeat to all
                else
                    set song repeat to off
                end if
            end tell
        end if
        """) { _ in }
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
