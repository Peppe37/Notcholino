import Foundation
import AppKit
import Combine

/// Reads Now Playing info by calling /usr/bin/osascript as a subprocess.
/// This avoids the NSAppleScript initialization path that causes FSFindFolder warnings.
final class MusicManager: NSObject, ObservableObject {

    @Published var trackName: String    = ""
    @Published var artistName: String   = ""
    @Published var isPlaying: Bool      = false
    @Published var activePlayer: String = "None"
    @Published var trackDuration: Double = 0
    @Published var trackPosition: Double = 0

    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var isFetching = false

    override init() {
        super.init()
        fetchNowPlaying()
        // Poll for track changes every 2 s
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.fetchNowPlaying()
        }
        // Advance position locally every 1 s (no need to re-query)
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

    // MARK: - Fetch (osascript subprocess, never on main thread)

    func fetchNowPlaying() {
        guard !isFetching else { return }
        isFetching = true
        let script = """
        set out to "None|||||||0|||0"
        if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    set d to (duration of current track) / 1000
                    set out to (name of current track) & "|||" & (artist of current track) & "|||Spotify|||" & (d as string) & "|||" & (player position as string)
                end if
            end tell
        end if
        if out is "None|||||||0|||0" and application "Music" is running then
            tell application "Music"
                if player state is playing then
                    set out to (name of current track) & "|||" & (artist of current track) & "|||Music|||" & (duration of current track as string) & "|||" & (player position as string)
                end if
            end tell
        end if
        return out
        """
        runOsascript(script) { [weak self] result in
            guard let self else { return }
            self.isFetching = false
            guard let raw = result else { return }
            let parts = raw.components(separatedBy: "|||")
            guard parts.count >= 5 else { return }
            let tName    = parts[0]
            let aName    = parts[1]
            let player   = parts[2]
            let duration = Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0
            let position = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
            let playing  = player != "None" && !tName.isEmpty

            DispatchQueue.main.async {
                if self.trackName != tName { self.trackName = tName }
                if self.artistName != aName { self.artistName = aName }
                if self.activePlayer != player { self.activePlayer = player }
                if self.isPlaying != playing { self.isPlaying = playing }
                if self.trackDuration != duration { self.trackDuration = duration }
                // Only reset position if track changed or we're off by more than 3s
                if self.trackName != tName || abs(self.trackPosition - position) > 3 {
                    self.trackPosition = position
                }
            }
        }
    }

    // MARK: - Controls

    func playPause() {
        let s = """
        if application "Spotify" is running then
            tell application "Spotify" to playpause
        else if application "Music" is running then
            tell application "Music" to playpause
        end if
        """
        runOsascript(s) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.fetchNowPlaying() }
        }
    }

    func nextTrack() {
        let s = """
        if application "Spotify" is running then
            tell application "Spotify" to next track
        else if application "Music" is running then
            tell application "Music" to next track
        end if
        """
        runOsascript(s) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.fetchNowPlaying() }
        }
    }

    func previousTrack() {
        let s = """
        if application "Spotify" is running then
            tell application "Spotify" to previous track
        else if application "Music" is running then
            tell application "Music" to previous track
        end if
        """
        runOsascript(s) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.fetchNowPlaying() }
        }
    }

    // MARK: - Helpers

    func formatTime(_ s: Double) -> String {
        guard s.isFinite && s >= 0 else { return "0:00" }
        let t = Int(s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    /// Runs AppleScript via /usr/bin/osascript on a background thread.
    /// This avoids NSAppleScript's FSFindFolder call entirely.
    private func runOsascript(_ source: String, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .background).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = Pipe() // swallow stderr

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let result = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                completion(result?.isEmpty == false ? result : nil)
            } catch {
                completion(nil)
            }
        }
    }
}
