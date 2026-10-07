import Foundation
import AppKit
import MediaPlayer // MRMediaRemote (private, but accessible via bridge)
import Combine

// We use the MRMediaRemote private framework via bridging to avoid
// repeated NSAppleScript invocations that cause FSFindFolder warnings.
// For commands we still use AppleScript, but we keep it on a background thread.

@objc class MusicManager: NSObject, ObservableObject {
    @Published var trackName: String = ""
    @Published var artistName: String = ""
    @Published var albumArt: NSImage? = nil
    @Published var isPlaying: Bool = false
    @Published var activePlayer: String = "None"
    @Published var trackDuration: Double = 0
    @Published var trackPosition: Double = 0

    private var timer: Timer?
    private var positionTimer: Timer?
    private var lastPositionUpdate: Date = Date()

    override init() {
        super.init()
        // Request media remote permission
        startPolling()
        // Listen for system Now Playing notifications
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(nowPlayingChanged),
            name: NSNotification.Name("com.apple.springboard.mediaControlChanged"),
            object: nil
        )
    }

    deinit {
        timer?.invalidate()
        positionTimer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func nowPlayingChanged() {
        fetchNowPlaying()
    }

    func startPolling() {
        fetchNowPlaying()
        // Poll every 2s for track changes
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.fetchNowPlaying()
        }
        // Position advances every second
        positionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            DispatchQueue.main.async {
                self.trackPosition = min(self.trackPosition + 1.0, self.trackDuration)
            }
        }
    }

    func fetchNowPlaying() {
        // Use AppleScript on a background queue — never on main thread
        let script = """
        set playerName to "None"
        set tName to ""
        set aName to ""
        set dur to 0
        set pos to 0

        if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    set playerName to "Spotify"
                    set tName to name of current track
                    set aName to artist of current track
                    set dur to (duration of current track) / 1000
                    set pos to player position
                end if
            end tell
        end if

        if playerName is "None" and application "Music" is running then
            tell application "Music"
                if player state is playing then
                    set playerName to "Music"
                    set tName to name of current track
                    set aName to artist of current track
                    set dur to duration of current track
                    set pos to player position
                end if
            end tell
        end if

        return tName & "|||" & aName & "|||" & playerName & "|||" & (dur as string) & "|||" & (pos as string)
        """

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            var err: NSDictionary?
            guard let scriptObj = NSAppleScript(source: script) else { return }
            let result = scriptObj.executeAndReturnError(&err)
            guard err == nil, let raw = result.stringValue else { return }

            let parts = raw.components(separatedBy: "|||")
            guard parts.count >= 5 else { return }

            let tName     = parts[0]
            let aName     = parts[1]
            let player    = parts[2]
            let duration  = Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0
            let position  = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
            let playing   = player != "None" && !tName.isEmpty

            DispatchQueue.main.async {
                self.trackName     = tName
                self.artistName    = aName
                self.activePlayer  = player
                self.isPlaying     = playing
                self.trackDuration = duration
                self.trackPosition = position
                self.lastPositionUpdate = Date()
            }
        }
    }

    // MARK: - Controls (background thread)
    func playPause() {
        runScript("""
        if application "Spotify" is running then
            tell application "Spotify" to playpause
        else if application "Music" is running then
            tell application "Music" to playpause
        end if
        """) { [weak self] in self?.fetchNowPlaying() }
    }

    func nextTrack() {
        runScript("""
        if application "Spotify" is running then
            tell application "Spotify" to next track
        else if application "Music" is running then
            tell application "Music" to next track
        end if
        """) { [weak self] in self?.fetchNowPlaying() }
    }

    func previousTrack() {
        runScript("""
        if application "Spotify" is running then
            tell application "Spotify" to previous track
        else if application "Music" is running then
            tell application "Music" to previous track
        end if
        """) { [weak self] in self?.fetchNowPlaying() }
    }

    private func runScript(_ source: String, completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            var err: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&err)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                completion?()
            }
        }
    }

    func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let min = totalSeconds / 60
        let sec = totalSeconds % 60
        return String(format: "%d:%02d", min, sec)
    }
}
