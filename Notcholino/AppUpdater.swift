// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation

/// Installs a new version of Notcholino from inside the app: downloads the release's disk image from this project's GitHub
/// releases, checks it is signed with the same identity as the running app (so macOS keeps every permission), swaps the app
/// and opens it again. Nothing runs unless the user asks for it.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    @Published private(set) var status: String?
    @Published private(set) var failure: String?
    var isWorking: Bool { status != nil }

    private static let downloadPrefix = "https://github.com/Peppe37/Notcholino/releases/download/"

    private struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }

    func install(_ release: UpdateChecker.Release) {
        guard !isWorking else { return }
        failure = nil
        status = "Downloading \(release.version)…"
        Task {
            do {
                try await run(release)
            } catch {
                status = nil
                failure = error.localizedDescription
            }
        }
    }

    private func run(_ release: UpdateChecker.Release) async throws {
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app", FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path),
              FileManager.default.isWritableFile(atPath: app.path) else {
            throw Failure(message: "This copy of Notcholino can't be replaced from here (it is not in a folder you can write to). Download the new version instead.")
        }
        guard let url = URL(string: "\(Self.downloadPrefix)v\(release.version)/Notcholino-\(release.version).dmg"),
              url.absoluteString.hasPrefix(Self.downloadPrefix) else { throw Failure(message: "No download for this version.") }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("notcholino-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let (file, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure(message: "The download failed.") }
        let dmg = work.appendingPathComponent("update.dmg")
        try FileManager.default.moveItem(at: file, to: dmg)

        status = "Checking it…"
        let staged = work.appendingPathComponent("Notcholino.app")
        let mount = work.appendingPathComponent("mount")
        try await Task.detached(priority: .utility) { try Self.extract(dmg: dmg, mount: mount, to: staged, current: app) }.value

        status = "Restarting…"
        let script = """
            PID="$1"; DEST="$2"; NEW="$3"; WORK="$4"
            for i in $(seq 1 100); do kill -0 "$PID" 2>/dev/null || break; sleep 0.3; done
            kill -0 "$PID" 2>/dev/null && exit 1
            mv "$DEST" "$DEST.old" || exit 1
            if /usr/bin/ditto "$NEW" "$DEST"; then rm -rf "$DEST.old"; else rm -rf "$DEST"; mv "$DEST.old" "$DEST"; fi
            rm -rf "$WORK"
            /usr/bin/open "$DEST"
            """
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), app.path, staged.path, work.path]
        try helper.run()
        NSApp.terminate(nil)
    }

    /// Opens the disk image, copies the app out, and refuses anything not signed like the running app
    nonisolated private static func extract(dmg: URL, mount: URL, to staged: URL, current: URL) throws {
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let attach = shell("/usr/bin/hdiutil", ["attach", "-nobrowse", "-noverify", "-noautoopen", "-readonly", "-mountpoint", mount.path, dmg.path])
        guard attach.status == 0 else { throw Failure(message: "Could not open the update.") }
        defer { _ = shell("/usr/bin/hdiutil", ["detach", "-force", mount.path]) }

        guard let found = try? FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) else {
            throw Failure(message: "The update has no app inside.")
        }
        try FileManager.default.copyItem(at: found, to: staged)
        _ = shell("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])

        guard shell("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path]).status == 0 else {
            throw Failure(message: "The update's signature is not valid, so it was not installed.")
        }
        let mine = requirement(of: current), theirs = requirement(of: staged)
        guard let mine, mine.contains("certificate"), mine == theirs else {
            throw Failure(message: "The update is not signed with the same identity as this app, so macOS would ask for every permission again. Download it from the release page instead.")
        }
    }

    nonisolated private static func requirement(of app: URL) -> String? {
        let out = shell("/usr/bin/codesign", ["-dr", "-", app.path]).output
        return out.split(separator: "\n").first { $0.hasPrefix("designated =>") }.map(String.init)
    }

    nonisolated private static func shell(_ tool: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
