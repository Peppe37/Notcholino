import AppKit
import ApplicationServices
import EventKit

/// Where a permission stands
enum PermissionState {
    case granted
    /// Never asked: the system dialog will show when we ask
    case notDetermined
    /// Refused (or restricted): only System Settings can change it
    case denied
    /// Can't be told right now (e.g. the app to control isn't running)
    case unavailable

    var isGranted: Bool { self == .granted }
}

/// Status of every permission Notcholino can use, with the action that gets each one.
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published private(set) var calendar: PermissionState = .notDetermined
    @Published private(set) var reminders: PermissionState = .notDetermined
    @Published private(set) var spotify: PermissionState = .unavailable
    @Published private(set) var music: PermissionState = .unavailable
    @Published private(set) var accessibility = AXIsProcessTrusted()

    static let spotifyID = "com.spotify.client"
    static let musicID = "com.apple.Music"

    private let store = EKEventStore()

    /// Asking the system whether we may control Spotify or Music can take a long time, or never answer (it did, with the main
    /// thread waiting: the whole app froze). So those lookups run here, one at a time, and never on the main thread.
    private let automationQueue = DispatchQueue(label: "com.giuseppe.Notcholino.permissions", qos: .utility)
    private var automationLookupRunning = false

    init() { refresh() }

    /// Re-reads every status. Cheap, never shows a dialog, and never waits on the system.
    func refresh() {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.refresh() }; return }

        // These answer at once
        let c = Self.eventKitState(EKEventStore.authorizationStatus(for: .event))
        let r = Self.eventKitState(EKEventStore.authorizationStatus(for: .reminder))
        let ax = AXIsProcessTrusted()
        // Keep the calendar manager in step with what was just granted or revoked
        CalendarManager.shared.refreshAccess()
        if calendar != c { calendar = c }
        if reminders != r { reminders = r }
        if accessibility != ax { accessibility = ax }

        // These may not: ask in the background and show the answer when it comes. If a lookup is still waiting, skip.
        guard !automationLookupRunning else { return }
        automationLookupRunning = true
        automationQueue.async {
            let sp = Self.automationState(bundleID: Self.spotifyID, ask: false)
            let mu = Self.automationState(bundleID: Self.musicID, ask: false)
            DispatchQueue.main.async {
                self.automationLookupRunning = false
                if self.spotify != sp { self.spotify = sp }
                if self.music != mu { self.music = mu }
            }
        }
    }

    /// A running player that Notcholino isn't allowed to control yet
    var blockedPlayer: (name: String, bundleID: String, state: PermissionState)? {
        if spotify == .notDetermined || spotify == .denied { return ("Spotify", Self.spotifyID, spotify) }
        if music == .notDetermined || music == .denied { return ("Music", Self.musicID, music) }
        return nil
    }

    // MARK: - Asking

    func requestCalendar() {
        guard calendar == .notDetermined else { return openSettings(.calendars) }
        CalendarManager.shared.requestAccess { self.refresh() }
    }

    func requestReminders() {
        guard reminders == .notDetermined else { return openSettings(.reminders) }
        CalendarManager.shared.requestRemindersAccess { self.refresh() }
    }

    func requestAutomation(bundleID: String) {
        let state = bundleID == Self.spotifyID ? spotify : music
        guard state == .notDetermined else { return openSettings(.automation) }
        // The system dialog needs a moment and blocks the call, so don't hold up the UI
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Self.automationState(bundleID: bundleID, ask: true)
            self.refresh()
        }
    }

    /// macOS ties the Accessibility permission to the exact signature of the app. After an update (or a reinstall)
    /// the old entry still looks switched on in System Settings but doesn't apply to the new build, and toggling it
    /// doesn't help. So first clear our entry, then ask again: the system adds a fresh one for this build.
    func requestAccessibility() {
        if accessibility { return }
        resetAccessibilityEntry()
        MediaKeyInterceptor.shared.askForAccess()
    }

    private func resetAccessibilityEntry() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", id]
        reset.standardOutput = Pipe()
        reset.standardError = Pipe()
        try? reset.run()
        reset.waitUntilExit()
    }

    enum Pane: String {
        case calendars = "Privacy_Calendars"
        case reminders = "Privacy_Reminders"
        case automation = "Privacy_Automation"
        case accessibility = "Privacy_Accessibility"
    }

    func openSettings(_ pane: Pane) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Status lookups

    private static func eventKitState(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .fullAccess, .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied   // denied, restricted, or write-only (not enough to read)
        }
    }

    /// Apple Events permission to control another app. Needs that app to be running to be answered.
    static func automationState(bundleID: String, ask: Bool) -> PermissionState {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return .unavailable }
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return .unavailable }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .unavailable
        }
    }
}
