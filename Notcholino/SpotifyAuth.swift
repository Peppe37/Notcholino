import Foundation
import AppKit
import AuthenticationServices
import CryptoKit
import Security

/// Spotify Web API access (OAuth2 Authorization Code + PKCE, no client secret).
/// Only used to read/write the "Liked" state, which AppleScript can't reach.
final class SpotifyAuth: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    static let shared = SpotifyAuth()
    static let redirectURI = "notcholino://callback"

    /// Client ID of the app registered on developer.spotify.com/dashboard.
    /// With PKCE it is public (not a secret), so it ships with the app and users never see it.
    static let bundledClientID = ""

    private let scopes = "user-library-read user-library-modify"
    private let keychainService = "com.giuseppe.Notcholino.spotify"

    @Published private(set) var isConnected = false
    @Published private(set) var lastError: String?

    private var accessToken: String?
    private var accessExpiry = Date.distantPast
    private var session: ASWebAuthenticationSession?

    override init() {
        super.init()
        isConnected = keychainRead() != nil
    }

    /// Optional override from Settings > Advanced, otherwise the bundled one.
    var clientID: String {
        let override = (UserDefaults.standard.string(forKey: "spotifyClientID") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? Self.bundledClientID : override
    }

    // MARK: - Connect / disconnect

    func connect() {
        guard !clientID.isEmpty else { setError("Missing Spotify Client ID"); return }

        let verifier = Self.randomString(64)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))

        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "scope", value: scopes),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
        ]

        let session = ASWebAuthenticationSession(url: comps.url!, callbackURLScheme: "notcholino") { [weak self] url, error in
            guard let self else { return }
            guard let url,
                  let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "code" })?.value else {
                if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                    self.setError(error?.localizedDescription ?? "Authorization failed")
                }
                return
            }
            Task { await self.exchange(code: code, verifier: verifier) }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        session.start()
    }

    func disconnect() {
        keychainDelete()
        accessToken = nil
        accessExpiry = .distantPast
        DispatchQueue.main.async { self.isConnected = false }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }

    // MARK: - Tokens

    private func exchange(code: String, verifier: String) async {
        await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
    }

    @discardableResult
    private func tokenRequest(_ form: [String: String]) async -> Bool {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let status = (resp as? HTTPURLResponse)?.statusCode else {
            setError("Network error")
            return false
        }
        guard status == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            // Refresh token revoked or expired: require a new login
            if status == 400 { disconnect() }
            setError("Token request failed (\(status))")
            return false
        }
        accessToken = token
        accessExpiry = Date().addingTimeInterval((json["expires_in"] as? Double) ?? 3600)
        if let refresh = json["refresh_token"] as? String { keychainWrite(refresh) }
        await MainActor.run { self.isConnected = true; self.lastError = nil }
        return true
    }

    private func validToken() async -> String? {
        if let t = accessToken, accessExpiry > Date().addingTimeInterval(30) { return t }
        guard let refresh = keychainRead() else { return nil }
        guard await tokenRequest([
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID,
        ]) else { return nil }
        return accessToken
    }

    // MARK: - Library API

    /// nil = unknown (not connected / request failed)
    func isSaved(trackURI: String) async -> Bool? {
        guard let (data, status) = await libraryCall("GET", uri: trackURI, contains: true), status == 200,
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Bool] else { return nil }
        return arr.first
    }

    @discardableResult
    func setSaved(_ saved: Bool, trackURI: String) async -> Bool {
        guard let (_, status) = await libraryCall(saved ? "PUT" : "DELETE", uri: trackURI, contains: false) else { return false }
        return (200..<300).contains(status)
    }

    /// Uses the newer /me/library endpoints and falls back to the legacy /me/tracks ones.
    private func libraryCall(_ method: String, uri: String, contains: Bool) async -> (Data, Int)? {
        guard let token = await validToken() else { return nil }
        let id = uri.components(separatedBy: ":").last ?? uri

        let newPath = "/v1/me/library" + (contains ? "/contains" : "")
        if let r = await apiCall(method, path: newPath, query: ("uris", uri), token: token), r.1 != 404 { return r }

        let oldPath = "/v1/me/tracks" + (contains ? "/contains" : "")
        return await apiCall(method, path: oldPath, query: ("ids", id), token: token)
    }

    private func apiCall(_ method: String, path: String, query: (String, String), token: String) async -> (Data, Int)? {
        var comps = URLComponents(string: "https://api.spotify.com")!
        comps.path = path
        comps.queryItems = [.init(name: query.0, value: query.1)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let status = (resp as? HTTPURLResponse)?.statusCode else { return nil }
        if status == 401 { accessToken = nil }
        if status == 403 { setError("Missing permissions: disconnect and reconnect Spotify") }
        return (data, status)
    }

    // MARK: - Helpers

    private func setError(_ msg: String) {
        DispatchQueue.main.async { self.lastError = msg }
    }

    private static func randomString(_ n: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return String(base64URL(Data(bytes)).prefix(n))
    }

    private static func base64URL(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Keychain (refresh token)

    private var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: "refresh_token"]
    }

    private func keychainRead() -> String? {
        var q = keychainQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainWrite(_ token: String) {
        keychainDelete()
        var q = keychainQuery
        q[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }

    private func keychainDelete() {
        SecItemDelete(keychainQuery as CFDictionary)
    }
}
