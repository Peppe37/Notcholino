// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation

/// Tells you when an email arrives from someone you said matters. It looks in Mail.app, which already holds Gmail, iCloud and
/// Microsoft accounts, so Notchy needs no account of its own. Only while Mail is open, only every few minutes, and never with AI:
/// it compares the sender with your list on the Mac and nothing about the email leaves it.
final class NotchyMail: ObservableObject {
    static let shared = NotchyMail()

    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "notchyMailEnabled"); settingsChanged() } }
    /// The senders that matter: each an address, or part of a name
    @Published private(set) var senders: [String]
    /// Mail only receives email while it is open, so Notchy opens it (hidden, in the background) when it is closed
    @Published var keepMailOpen: Bool { didSet { UserDefaults.standard.set(keepMailOpen, forKey: "notchyMailKeepOpen") } }
    @Published private(set) var testResult: String?

    private var timer: Timer?
    private var seen: Set<String>
    private var lastCheck = Date()
    private let queue = DispatchQueue(label: "com.giuseppe.Notcholino.notchy.mail", qos: .utility)

    init() {
        let d = UserDefaults.standard
        enabled = d.bool(forKey: "notchyMailEnabled")
        senders = d.stringArray(forKey: "notchyMailSendersList") ?? []
        keepMailOpen = d.object(forKey: "notchyMailKeepOpen") as? Bool ?? true
        seen = Set(d.stringArray(forKey: "notchyMailSeen") ?? [])
    }

    private var wanted: [String] { senders.map { $0.lowercased() } }

    func add(_ raw: String) {
        // Several at once are fine: separated by commas, semicolons, spaces or lines
        let parts = raw.split(whereSeparator: { ",;\n ".contains($0) }).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for p in parts where !senders.contains(where: { $0.caseInsensitiveCompare(p) == .orderedSame }) { senders.append(p) }
        UserDefaults.standard.set(senders, forKey: "notchyMailSendersList")
        if enabled { check(soon: true) }
    }

    func remove(_ sender: String) {
        senders.removeAll { $0 == sender }
        UserDefaults.standard.set(senders, forKey: "notchyMailSendersList")
    }

    func settingsChanged() {
        timer?.invalidate(); timer = nil
        let s = NotchySettings.shared
        guard enabled, s.enabled, s.level != .silent else { return }
        lastCheck = Date().addingTimeInterval(-600)     // the first look also catches what arrived a few minutes ago
        let t = Timer(timeInterval: 180, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = 60
        check(soon: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var mailIsRunning: Bool { NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.mail" } }

    /// Opens Mail without showing it or taking the focus
    private func openMailQuietly(then: @escaping () -> Void) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.mail") else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        config.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            // Give it a moment to load its accounts
            DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: then)
        }
    }

    private func check(soon: Bool = false) {
        guard !wanted.isEmpty else { return }
        if !mailIsRunning {
            guard keepMailOpen else { return }
            openMailQuietly { [weak self] in self?.check() }
            return
        }
        let since = max(lastCheck.addingTimeInterval(-60), Date().addingTimeInterval(-3600))
        lastCheck = Date()
        let wanted = self.wanted
        queue.async { [weak self] in
            guard let found = try? Self.unread(since: since) else { return }
            let matches = found.filter { m in wanted.contains { m.sender.lowercased().contains($0) } }
            DispatchQueue.main.async { self?.announce(matches) }
        }
    }

    private func announce(_ matches: [(id: String, sender: String, subject: String)]) {
        let fresh = matches.filter { !seen.contains($0.id) }
        guard let first = fresh.first else { return }
        fresh.forEach { seen.insert($0.id) }
        if seen.count > 300 { seen = Set(fresh.map(\.id)) }
        UserDefaults.standard.set(Array(seen), forKey: "notchyMailSeen")
        let who = Self.name(of: first.sender)
        let more = fresh.count > 1 ? " (+\(fresh.count - 1) more)" : ""
        NotchyAssistant.shared.note("\(who): \(first.subject)\(more)", title: "Email from \(who)")
    }

    /// "Check now" in settings: shows what it can see, so the user knows the permission and the list work
    func test() {
        testResult = "Looking…"
        let wanted = self.wanted
        if !mailIsRunning {
            guard keepMailOpen else { testResult = "Mail is closed. Open it, or let Notchy open it in the background."; return }
            testResult = "Opening Mail in the background…"
            openMailQuietly { [weak self] in self?.test() }
            return
        }
        queue.async { [weak self] in
            var text: String
            do {
                let found = try Self.unread(since: Date().addingTimeInterval(-86_400))
                let hits = found.filter { m in wanted.contains { m.sender.lowercased().contains($0) } }
                let who = found.prefix(3).map { Self.name(of: $0.sender) }.joined(separator: ", ")
                text = "Works: \(found.count) unread in the last day, \(hits.count) from your list." + (who.isEmpty ? "" : " Latest from: \(who).")
            } catch {
                text = error.localizedDescription
            }
            DispatchQueue.main.async { self?.testResult = text }
        }
    }

    private static func name(of sender: String) -> String {
        if let open = sender.firstIndex(of: "<") {
            let n = sender[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            if !n.isEmpty { return n }
        }
        return sender.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
    }

    /// Unread messages in the inbox(es) received since a date. Runs off the main thread: Mail can be slow, or ask for permission.
    private static func unread(since date: Date) throws -> [(id: String, sender: String, subject: String)] {
        let secs = max(60, Int(Date().timeIntervalSince(date)))
        let source = """
            tell application "Mail"
                set cutoff to (current date) - \(secs)
                set out to {}
                repeat with m in (messages of inbox whose read status is false and date received > cutoff)
                    set end of out to {(message id of m) as text, (sender of m) as text, (subject of m) as text}
                end repeat
                return out
            end tell
            """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw NotchyAIError(message: "Could not prepare the Mail check.") }
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 { throw NotchyAIError(message: "Notcholino is not allowed to control Mail. Allow it in System Settings → Privacy & Security → Automation.") }
            throw NotchyAIError(message: (error[NSAppleScript.errorMessage] as? String) ?? "Mail did not answer.")
        }
        var out: [(String, String, String)] = []
        guard result.numberOfItems > 0 else { return [] }
        for i in 1...result.numberOfItems {
            guard let item = result.atIndex(i), item.numberOfItems >= 3 else { continue }
            out.append((item.atIndex(1)?.stringValue ?? "", item.atIndex(2)?.stringValue ?? "", item.atIndex(3)?.stringValue ?? ""))
        }
        return out
    }
}
