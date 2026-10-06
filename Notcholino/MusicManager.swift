import Foundation
import AppKit

class MusicManager: ObservableObject {
    @Published var trackName: String = "Not Playing"
    @Published var artistName: String = ""
    @Published var isPlaying: Bool = false
    @Published var activePlayer: String = "None"
    @Published var trackDuration: Double = 0
    @Published var trackPosition: Double = 0
    
    private var timer: Timer?
    
    init() {
        startPolling()
    }
    
    func startPolling() {
        // Poll every 1 second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateNowPlaying()
        }
        // Force an initial update immediately
        updateNowPlaying()
    }
    
    func updateNowPlaying() {
        let scriptSource = """
        if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    return (name of current track) & "|||" & (artist of current track) & "|||Spotify|||" & (duration of current track) & "|||" & (player position)
                end if
            end tell
        end if
        
        if application "Music" is running then
            tell application "Music"
                if player state is playing then
                    return (name of current track) & "|||" & (artist of current track) & "|||Music|||" & (duration of current track) & "|||" & (player position)
                end if
            end tell
        end if
        
        return "Not Playing||||||None|||0|||0"
        """
        
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: scriptSource) {
                let output = scriptObject.executeAndReturnError(&error)
                if let stringValue = output.stringValue {
                    let parts = stringValue.components(separatedBy: "|||")
                    if parts.count >= 5 {
                        let tName = parts[0]
                        let aName = parts[1]
                        let player = parts[2]
                        let duration = (Double(parts[3]) ?? 0) / (player == "Spotify" ? 1000.0 : 1.0)
                        let position = Double(parts[4]) ?? 0
                        
                        DispatchQueue.main.async {
                            self.trackName = tName
                            self.artistName = aName
                            self.activePlayer = player
                            self.isPlaying = (tName != "Not Playing")
                            self.trackDuration = duration
                            self.trackPosition = position
                        }
                    }
                }
            }
        }
    }
    
    // Controls
    func playPause() {
        let script = """
        if application "Spotify" is running then
            tell application "Spotify" to playpause
        else if application "Music" is running then
            tell application "Music" to playpause
        end if
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        updateNowPlaying()
    }
    
    func nextTrack() {
        let script = """
        if application "Spotify" is running then
            tell application "Spotify" to next track
        else if application "Music" is running then
            tell application "Music" to next track
        end if
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        updateNowPlaying()
    }
    
    func previousTrack() {
        let script = """
        if application "Spotify" is running then
            tell application "Spotify" to previous track
        else if application "Music" is running then
            tell application "Music" to previous track
        end if
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        updateNowPlaying()
    }
}
