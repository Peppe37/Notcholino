// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import LocalAuthentication
import Security

struct VikunjaConnection: Codable, Equatable {
    let site: URL
    let token: String
    let access: CloudflareAccess?

    struct CloudflareAccess: Codable, Equatable {
        let clientID: String
        let clientSecret: String
    }

    static func make(address: String, token: String, access: CloudflareAccess? = nil) throws -> Self {
        guard var parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
            throw VikunjaError.address
        }
        let scheme = parts.scheme?.lowercased()
        guard scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host)) else {
            throw VikunjaError.address
        }
        parts.scheme = scheme
        while parts.percentEncodedPath.hasSuffix("/") { parts.percentEncodedPath.removeLast() }
        if parts.percentEncodedPath.hasSuffix("/api/v1") { parts.percentEncodedPath.removeLast("/api/v1".count) }
        guard let site = parts.url else { throw VikunjaError.address }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validHeader(token) else { throw VikunjaError.token }
        let access = access.map {
            CloudflareAccess(clientID: $0.clientID.trimmingCharacters(in: .whitespacesAndNewlines),
                             clientSecret: $0.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let access {
            guard scheme == "https" else { throw VikunjaError.accessHTTPS }
            guard validHeader(access.clientID), validHeader(access.clientSecret) else { throw VikunjaError.accessCredentials }
        }
        return Self(site: site, token: token, access: access)
    }

    private static func validHeader(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (33...126).contains($0) }
    }
}

enum VikunjaError: LocalizedError {
    case address, token, rejected, forbidden, redirect, response, keychain(OSStatus), http(Int)
    case accessHTTPS, accessCredentials, accessRequired, accessDenied
    var errorDescription: String? {
        switch self {
        case .address: return "Enter the HTTPS URL of your Vikunja instance. HTTP is allowed only on localhost."
        case .token: return "Enter a valid Vikunja API token."
        case .rejected: return "Vikunja rejected the API token. Check that it has not expired."
        case .forbidden: return "Access denied. Check your token permissions and your access to this project or action."
        case .redirect: return "The server redirected the request. Use the final Vikunja URL and make sure its API is reachable directly."
        case .accessHTTPS: return "Cloudflare Access credentials require an HTTPS URL."
        case .accessCredentials: return "Enter both the Cloudflare Access Client ID and Client Secret."
        case .accessRequired: return "Cloudflare Access requires a service token. Enable Cloudflare Access in the Vikunja settings."
        case .accessDenied: return "Cloudflare Access rejected the request. Check the service token and its Service Auth policy."
        case .response: return "The server did not return a Vikunja API response. Check the instance URL."
        case .keychain(let status): return "Could not access the Vikunja connection in Keychain (\(status))."
        case .http(let status): return "Vikunja returned HTTP \(status)."
        }
    }
}

enum VikunjaKeychain {
    private static let item: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.giuseppe.Notcholino.extension.vikunja",
        kSecAttrAccount as String: "connection"
    ]

    static func load() throws -> VikunjaConnection? {
        var query = item
        query[kSecReturnData as String] = true
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw VikunjaError.keychain(status) }
        return try JSONDecoder().decode(VikunjaConnection.self, from: data)
    }

    static func save(_ connection: VikunjaConnection) throws {
        let data = try JSONEncoder().encode(connection)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(item as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var query = item
            query[kSecValueData as String] = data
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw VikunjaError.keychain(status) }
    }

    static func remove() throws {
        let status = SecItemDelete(item as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VikunjaError.keychain(status) }
    }
}

struct VikunjaBoard: Identifiable, Equatable {
    let project: Int
    let id: Int
    let title: String
    let canMove: Bool
}

private struct VikunjaProject: Decodable {
    struct View: Decodable {
        let id: Int
        let title: String
        let viewKind: String
        let bucketConfigurationMode: String?
    }

    let id: Int
    let title: String
    let isArchived: Bool?
    let views: [View]?
}

struct VikunjaTask: Decodable, Identifiable {
    let id: Int
    let title: String
    let done: Bool
}

struct VikunjaBucket: Decodable, Identifiable {
    let id: Int
    let title: String
    var tasks: [VikunjaTask]?
}

struct VikunjaClient {
    let connection: VikunjaConnection

    // Reject redirects so neither the Vikunja token nor Access credentials are forwarded.
    private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
    }()

    func boards() async throws -> [VikunjaBoard] {
        let projects: [VikunjaProject] = try await pages("projects")
        return projects.filter { $0.isArchived != true }.flatMap { project in
            (project.views ?? []).filter { $0.viewKind == "kanban" }.map { view in
                VikunjaBoard(project: project.id, id: view.id, title: "\(project.title) · \(view.title)",
                             canMove: view.bucketConfigurationMode == "manual")
            }
        }
    }

    func buckets(_ board: VikunjaBoard) async throws -> [VikunjaBucket] {
        let entries: [VikunjaBucket] = try await pages("projects/\(board.project)/views/\(board.id)/tasks")
        // Vikunja can return the same columns with different task slices on each page.
        var result: [VikunjaBucket] = []
        var indices: [Int: Int] = [:]
        var seen: [Int: Set<Int>] = [:]
        for var bucket in entries {
            bucket.tasks = (bucket.tasks ?? []).filter { seen[bucket.id, default: []].insert($0.id).inserted }
            if let index = indices[bucket.id] {
                result[index].tasks?.append(contentsOf: bucket.tasks ?? [])
            } else {
                indices[bucket.id] = result.count
                result.append(bucket)
            }
        }
        return result
    }

    func move(_ task: VikunjaTask, to bucket: VikunjaBucket, on board: VikunjaBoard) async throws {
        let data = try JSONEncoder().encode(["task_id": task.id, "bucket_id": bucket.id, "project_view_id": board.id])
        _ = try await request("projects/\(board.project)/views/\(board.id)/buckets/\(bucket.id)/tasks", method: "POST", body: data)
    }

    func add(_ title: String, on board: VikunjaBoard) async throws {
        let data = try JSONEncoder().encode(["title": title])
        _ = try await request("projects/\(board.project)/tasks", method: "PUT", body: data)
    }

    private func pages<T: Decodable>(_ path: String) async throws -> [T] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var result: [T] = []
        var page = 1
        while true {
            let (data, response) = try await request(path, query: [
                URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "per_page", value: "100")
            ])
            do { result += try decoder.decode([T]?.self, from: data) ?? [] }
            catch { throw VikunjaError.response }
            guard page < (response.value(forHTTPHeaderField: "x-pagination-total-pages").flatMap(Int.init) ?? 1) else { return result }
            page += 1
        }
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil,
                         query: [URLQueryItem] = []) async throws -> (Data, HTTPURLResponse) {
        let endpoint = connection.site.appendingPathComponent("api/v1").appendingPathComponent(path)
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        if let access = connection.access {
            request.setValue(access.clientID, forHTTPHeaderField: "CF-Access-Client-Id")
            request.setValue(access.clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await Self.session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw VikunjaError.response }
        switch http.statusCode {
        case 200..<300:
            guard http.mimeType == "application/json" else { throw VikunjaError.response }
            return (data, http)
        case 300..<400:
            if http.value(forHTTPHeaderField: "Location").flatMap(URLComponents.init(string:))?.path
                .hasPrefix("/cdn-cgi/access/login") == true {
                throw connection.access == nil ? VikunjaError.accessRequired : VikunjaError.accessDenied
            }
            throw VikunjaError.redirect
        case 401: throw VikunjaError.rejected
        case 403:
            if connection.access != nil && http.mimeType == "text/html" { throw VikunjaError.accessDenied }
            throw VikunjaError.forbidden
        default: throw VikunjaError.http(http.statusCode)
        }
    }
}
