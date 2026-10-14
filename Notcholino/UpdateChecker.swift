import Foundation

/// Tells the user when a newer version of Notcholino has been released.
///
/// It is as light as it can be: one small request to GitHub's releases list, at most once a day (and a "304 Not Modified"
/// answer when nothing changed, which costs almost nothing), never on a timer shorter than that, and never while the user
/// has switched it off. Nothing is sent but the request itself. It only tells the user: it never downloads or installs.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    struct Release: Equatable { let version: String; let url: URL }

    /// The newer release, if there is one
    @Published private(set) var available: Release?
    @Published private(set) var isChecking = false
    @Published private(set) var lastChecked: Date?

    private enum Key {
        static let enabled = "updateCheckEnabled"
        static let last = "updateLastCheck"
        static let etag = "updateETag"
        static let latestVersion = "updateLatestVersion"
        static let latestURL = "updateLatestURL"
    }
    private static let interval: TimeInterval = 24 * 3600
    private static let endpoint = URL(string: "https://api.github.com/repos/Peppe37/Notcholino/releases?per_page=10")!
    private var timer: Timer?

    var isEnabled: Bool { UserDefaults.standard.object(forKey: Key.enabled) as? Bool ?? true }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    init() {
        lastChecked = UserDefaults.standard.object(forKey: Key.last) as? Date
        applyCached()
    }

    /// Call once at launch: shows what was found last time right away, and checks if a day has passed
    func start() {
        guard timer == nil else { return }
        // A short wait, so the check never competes with the app starting up
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.checkIfDue() }
        let t = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in self?.checkIfDue() }
        t.tolerance = 600
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func checkIfDue() {
        guard isEnabled else { return }
        if let last = lastChecked, Date().timeIntervalSince(last) < Self.interval { return }
        Task { await check() }
    }

    /// Asks GitHub now (also used by the "Check now" button)
    @MainActor
    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        var request = URLRequest(url: Self.endpoint, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Notcholino/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        if let etag = UserDefaults.standard.string(forKey: Key.etag) { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return }   // offline or slow: try again later
        let d = UserDefaults.standard
        if http.statusCode == 200 {
            if let etag = http.value(forHTTPHeaderField: "ETag") { d.set(etag, forKey: Key.etag) }
            if let latest = Self.latestAppRelease(in: data) {
                d.set(latest.version, forKey: Key.latestVersion)
                d.set(latest.url.absoluteString, forKey: Key.latestURL)
            }
        } else if http.statusCode != 304 {
            return                                                       // rate limited or a hiccup: not counted as a check
        }
        let now = Date()
        d.set(now, forKey: Key.last)
        lastChecked = now
        applyCached()
    }

    /// The newest release of the app itself (tags like "v0.10.0-alpha"; plugin releases have other tags)
    private static func latestAppRelease(in data: Data) -> Release? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        var best: Release?
        for entry in list where (entry["draft"] as? Bool) != true {
            guard let tag = entry["tag_name"] as? String, tag.hasPrefix("v"),
                  let page = (entry["html_url"] as? String).flatMap(URL.init(string:)) else { continue }
            let version = String(tag.dropFirst())
            if best == nil || RemotePlugin.compare(version, best!.version) == .orderedDescending {
                best = Release(version: version, url: page)
            }
        }
        return best
    }

    private func applyCached() {
        let d = UserDefaults.standard
        guard let version = d.string(forKey: Key.latestVersion),
              let url = d.string(forKey: Key.latestURL).flatMap(URL.init(string:)),
              RemotePlugin.compare(version, currentVersion) == .orderedDescending else {
            available = nil
            return
        }
        available = Release(version: version, url: url)
    }
}
