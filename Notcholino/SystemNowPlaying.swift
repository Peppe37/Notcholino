// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation

/// What the system says is playing right now, whatever the app: Spotify, Music, but also YouTube or Netflix
/// in a browser, Amazon Music, Podcasts...
struct SystemNowPlaying: Equatable {
    var bundleID: String
    /// For web content this is the browser, `bundleID` can be a helper process
    var appBundleID: String
    var appName: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    /// Elapsed time at `timestamp`
    var elapsed: Double
    var timestamp: Date
    var rate: Double
    var playing: Bool
    var artwork: NSImage?
    /// Identifies the artwork so we only decode and set it when it changes
    var artworkKey: Int

    /// Where playback is now
    var position: Double {
        guard playing else { return elapsed }
        let p = elapsed + Date().timeIntervalSince(timestamp) * max(rate, 0)
        return duration > 0 ? min(p, duration) : p
    }

    static func == (a: SystemNowPlaying, b: SystemNowPlaying) -> Bool {
        a.bundleID == b.bundleID && a.title == b.title && a.artist == b.artist && a.playing == b.playing
            && a.elapsed == b.elapsed && a.timestamp == b.timestamp && a.artworkKey == b.artworkKey
    }
}

/// Reads the macOS "Now Playing" information with one long-lived helper process.
///
/// Since macOS 15.4 only Apple-signed binaries may use the private MediaRemote framework, so, like other apps,
/// we run the system `/usr/bin/perl` (which is allowed) with a small helper framework that prints every change as a line
/// of JSON (third_party/mediaremote-adapter). It is event driven: nothing runs between changes.
final class SystemNowPlayingMonitor: ObservableObject {
    static let shared = SystemNowPlayingMonitor()
    static let defaultsKey = "npSystemDetect"

    @Published private(set) var current: SystemNowPlaying?
    /// False if the helper can't run on this Mac (then only Spotify and Music are detected)
    @Published private(set) var isAvailable = true

    private var process: Process?
    private var pending = Data()
    private var state: [String: Any] = [:]
    private var restarts = 0
    private var wantsRunning = false
    private var terminationObserver: NSObjectProtocol?
    private var signalSources: [DispatchSourceSignal] = []

    private var scriptURL: URL? { Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl") }
    private var frameworkURL: URL? { Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework") }

    var isEnabled: Bool { UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true }

    /// Starts or stops the helper according to the setting
    func apply() {
        isEnabled ? start() : stop()
    }

    func start() {
        wantsRunning = true
        guard process == nil, let script = scriptURL, let framework = frameworkURL,
              FileManager.default.fileExists(atPath: framework.path) else {
            if process == nil { DispatchQueue.main.async { self.isAvailable = false } }
            return
        }
        killOrphans(script: script)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        // Microseconds keep the time values numeric; the debounce merges the bursts that apps send on track changes
        p.arguments = [script.path, framework.path, "stream", "--micros", "--debounce=120"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }
        p.terminationHandler = { [weak self] proc in
            out.fileHandleForReading.readabilityHandler = nil
            self?.didExit(proc)
        }
        do {
            try p.run()
            process = p
            if terminationObserver == nil {
                terminationObserver = NotificationCenter.default.addObserver(
                    forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in self?.stop() }
                // Also when the app is stopped from outside (kill, logout, installer): don't leave the helper behind
                for sig in [SIGTERM, SIGINT, SIGHUP] {
                    signal(sig, SIG_IGN)
                    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
                    source.setEventHandler { [weak self] in
                        self?.stop()
                        exit(0)
                    }
                    source.resume()
                    signalSources.append(source)
                }
            }
        } catch {
            print("Now Playing helper failed to start: \(error)")
            DispatchQueue.main.async { self.isAvailable = false }
        }
    }

    /// A helper left over from a previous run of this same copy of the app (e.g. after a crash)
    private func killOrphans(script: URL) {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-f", script.path]
        pkill.standardOutput = Pipe()
        pkill.standardError = Pipe()
        try? pkill.run()
        pkill.waitUntilExit()
    }

    func stop() {
        wantsRunning = false
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        pending.removeAll()
        state.removeAll()
        DispatchQueue.main.async { self.current = nil }
    }

    private func didExit(_ proc: Process) {
        DispatchQueue.main.async {
            guard self.process === proc else { return }
            self.process = nil
            self.pending.removeAll()
            self.state.removeAll()
            self.current = nil
            guard self.wantsRunning else { return }
            // Restart with a growing delay; give up if it keeps failing (e.g. a macOS update broke the helper)
            self.restarts += 1
            guard self.restarts <= 5 else { self.isAvailable = false; return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(self.restarts) * 2) { self.start() }
        }
    }

    // MARK: - Parsing

    private func consume(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending.subdata(in: pending.startIndex..<newline)
            pending.removeSubrange(pending.startIndex...newline)
            guard !line.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = json["payload"] as? [String: Any] else { continue }

            if json["diff"] as? Bool == true {
                // Only what changed: merge, and a null value means the key is gone
                for (key, value) in payload {
                    if value is NSNull { state.removeValue(forKey: key) } else { state[key] = value }
                }
            } else {
                state = payload
            }
            restarts = 0
            let info = makeInfo(from: state)
            DispatchQueue.main.async {
                self.isAvailable = true
                if self.current != info || self.current?.artwork == nil && info?.artwork != nil { self.current = info }
            }
        }
    }

    private func makeInfo(from s: [String: Any]) -> SystemNowPlaying? {
        guard let bundleID = s["bundleIdentifier"] as? String,
              let title = s["title"] as? String, !title.isEmpty else { return nil }
        let micros: (String) -> Double = { key in (s[key] as? NSNumber)?.doubleValue ?? 0 }
        let appID = (s["parentApplicationBundleIdentifier"] as? String) ?? bundleID

        var artwork: NSImage?
        var key = 0
        if let b64 = s["artworkData"] as? String, let data = Data(base64Encoded: b64) {
            artwork = NSImage(data: data)
            key = data.count &* 31 &+ (data.first.map(Int.init) ?? 0)
        }
        let epoch = micros("timestampEpochMicros")
        return SystemNowPlaying(
            bundleID: bundleID,
            appBundleID: appID,
            appName: Self.displayName(for: appID),
            title: title,
            artist: (s["artist"] as? String) ?? "",
            album: (s["album"] as? String) ?? "",
            duration: micros("durationMicros") / 1_000_000,
            elapsed: micros("elapsedTimeMicros") / 1_000_000,
            timestamp: epoch > 0 ? Date(timeIntervalSince1970: epoch / 1_000_000) : Date(),
            rate: (s["playbackRate"] as? NSNumber)?.doubleValue ?? 1,
            playing: (s["playing"] as? Bool) ?? false,
            artwork: artwork,
            artworkKey: key)
    }

    private static func displayName(for bundleID: String) -> String {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = running.localizedName { return name }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    // MARK: - Controls (MediaRemote command ids)

    enum Command: Int {
        case play = 0, pause = 1, togglePlayPause = 2, next = 4, previous = 5
    }

    func send(_ command: Command) { run(["send", String(command.rawValue)]) }

    func seek(to seconds: Double) { run(["seek", String(Int(max(0, seconds) * 1_000_000))]) }

    private func run(_ arguments: [String]) {
        guard let script = scriptURL, let framework = frameworkURL else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            p.arguments = [script.path, framework.path] + arguments
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            try? p.run()
            p.waitUntilExit()
        }
    }
}
