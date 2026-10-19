// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation

/// How lively Notchy is
enum NotchyLevel: Int, CaseIterable, Identifiable {
    case silent = 0, normal = 1, lively = 2
    var id: Int { rawValue }
    var title: String { ["Silent", "Normal", "Lively"][rawValue] }
    var detail: String {
        switch self {
        case .silent: return "Only appears when you call it or send it something."
        case .normal: return "Peeks out now and then, and when you have been in one app for a long time."
        case .lively: return "Peeks out more often and reacts to more things."
        }
    }
}

/// Everything that is chosen about Notchy: on or off, how lively, and which provider does what. Keys are not here: they are in the
/// Keychain (NotchyKeychain).
final class NotchySettings: ObservableObject {
    static let shared = NotchySettings()

    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "notchyEnabled"); NotchyPresence.shared.settingsChanged() } }
    @Published var pageVisible: Bool { didSet { UserDefaults.standard.set(pageVisible, forKey: "notchyPageVisible") } }
    /// The language Notchy answers in; empty means "the language of what it was sent"
    @Published var replyLanguage: String { didSet { UserDefaults.standard.set(replyLanguage, forKey: "notchyReplyLanguage") } }
    @Published var level: NotchyLevel { didSet { UserDefaults.standard.set(level.rawValue, forKey: "notchyLevel"); NotchyPresence.shared.settingsChanged() } }
    @Published private(set) var choices: [String: String]      // task -> provider id
    @Published private(set) var models: [String: String]       // "provider/task" -> model
    @Published private(set) var urls: [String: String]         // provider -> base URL

    init() {
        let d = UserDefaults.standard
        enabled = d.bool(forKey: "notchyEnabled")
        pageVisible = d.object(forKey: "notchyPageVisible") as? Bool ?? true
        replyLanguage = d.string(forKey: "notchyReplyLanguage") ?? ""
        level = NotchyLevel(rawValue: d.object(forKey: "notchyLevel") as? Int ?? 1) ?? .normal
        choices = d.dictionary(forKey: "notchyChoices") as? [String: String] ?? [:]
        models = d.dictionary(forKey: "notchyModels") as? [String: String] ?? [:]
        urls = d.dictionary(forKey: "notchyURLs") as? [String: String] ?? [:]
    }

    func providerID(for task: NotchyTask) -> String? {
        guard let id = choices[task.rawValue], NotchyProvider.provider(id) != nil else { return nil }
        return id
    }

    func setProvider(_ id: String?, for task: NotchyTask) {
        if let id { choices[task.rawValue] = id } else { choices.removeValue(forKey: task.rawValue) }
        UserDefaults.standard.set(choices, forKey: "notchyChoices")
    }

    func baseURL(for provider: NotchyProvider) -> String {
        let custom = (urls[provider.id] ?? "").trimmingCharacters(in: .whitespaces)
        return (custom.isEmpty ? provider.defaultBaseURL : custom).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func setBaseURL(_ url: String, for provider: NotchyProvider) {
        urls[provider.id] = url
        UserDefaults.standard.set(urls, forKey: "notchyURLs")
    }

    func model(for provider: NotchyProvider, task: NotchyTask) -> String {
        let custom = (models["\(provider.id)/\(task.rawValue)"] ?? "").trimmingCharacters(in: .whitespaces)
        return custom.isEmpty ? (provider.models(for: task).first ?? "") : custom
    }

    func setModel(_ model: String, for provider: NotchyProvider, task: NotchyTask) {
        models["\(provider.id)/\(task.rawValue)"] = model
        UserDefaults.standard.set(models, forKey: "notchyModels")
    }
}

// MARK: - When Notchy shows up

/// The small "brain" that decides when Notchy appears. It runs on plain rules and events, never on a model:
/// - a coarse timer (minutes, with plenty of tolerance so macOS can group it with other work),
/// - the system's own notification when the frontmost app changes,
/// and does nothing at all while Notchy is off or Silent.
final class NotchyPresence: ObservableObject {
    static let shared = NotchyPresence()

    /// Shown beside the closed notch right now, and in what mood
    @Published private(set) var peeking = false
    @Published private(set) var mood: NotchyMood = .calm

    private var timer: Timer?
    private var frontmostSince = Date()
    private var lastFrontmost: String?
    private var lastDwellPeek = Date.distantPast
    private var nextPeek = Date.distantFuture
    private var hideTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    func settingsChanged() {
        let s = NotchySettings.shared
        if s.enabled && s.level != .silent { start() } else { stop() }
    }

    private func start() {
        guard timer == nil else { return }
        scheduleNextPeek()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard id != self?.lastFrontmost else { return }
            self?.lastFrontmost = id
            self?.frontmostSince = Date()
        }
        let t = Timer(timeInterval: 300, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = 120
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        nextPeek = .distantFuture
        hideTask?.cancel()
        peeking = false
    }

    private func scheduleNextPeek() {
        let range: ClosedRange<Double> = NotchySettings.shared.level == .lively ? 480...900 : 1200...2400
        nextPeek = Date().addingTimeInterval(Double.random(in: range))
    }

    /// Every five minutes: is it time for a peek, or has the user been in one app for too long?
    private func check() {
        // The user has to be there: no peeking at an empty chair
        guard CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved) < 120
                || CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) < 120 else { return }
        let dwellLimit: TimeInterval = NotchySettings.shared.level == .lively ? 30 * 60 : 50 * 60
        if Date().timeIntervalSince(frontmostSince) > dwellLimit, Date().timeIntervalSince(lastDwellPeek) > dwellLimit {
            lastDwellPeek = Date()
            peek(mood: .sleepy, seconds: 6)
        } else if Date() >= nextPeek {
            scheduleNextPeek()
            peek(mood: [.curious, .calm, .happy].randomElement() ?? .calm, seconds: 4)
        }
    }

    /// Shows Notchy beside the notch for a few seconds
    func peek(mood: NotchyMood, seconds: Double) {
        hideTask?.cancel()
        self.mood = mood
        peeking = true
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.peeking = false
        }
    }
}
