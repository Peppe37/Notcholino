// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Security

/// The things Notchy asks an AI for. The user picks one provider for each, so text can go to a local model while the voice goes
/// somewhere else.
enum NotchyTask: String, CaseIterable, Identifiable {
    case text, vision, speech
    var id: String { rawValue }
    var title: String {
        switch self {
        case .text: return "Text"
        case .vision: return "Images and screen"
        case .speech: return "Voice to text"
        }
    }
    var detail: String {
        switch self {
        case .text: return "Summaries, outlines, answers, planning."
        case .vision: return "Reading a screenshot or a part of the screen. Notchy sends text it has already read on the Mac when it can, which costs less."
        case .speech: return "Turning your voice into text when you call Notchy with the shortcut. Notchy always answers in writing."
        }
    }
}

/// The services Notchy can talk to. Three kinds of connection cover all of them: Anthropic, Gemini, and anything that speaks
/// the OpenAI format (OpenAI itself, Ollama, vLLM, LM Studio…).
struct NotchyProvider: Identifiable, Hashable {
    enum Kind { case anthropic, gemini, openAICompatible, elevenLabs, system }

    let id: String
    let name: String
    let kind: Kind
    let defaultBaseURL: String
    let defaultModel: String
    let needsKey: Bool
    /// Which tasks it can do
    let tasks: Set<NotchyTask>
    let keyHint: String

    static let all: [NotchyProvider] = [
        NotchyProvider(id: "anthropic", name: "Anthropic (Claude)", kind: .anthropic, defaultBaseURL: "https://api.anthropic.com",
                       defaultModel: "claude-sonnet-5-5", needsKey: true, tasks: [.text, .vision], keyHint: "sk-ant-…"),
        NotchyProvider(id: "gemini", name: "Google Gemini", kind: .gemini, defaultBaseURL: "https://generativelanguage.googleapis.com",
                       defaultModel: "gemini-2.5-flash", needsKey: true, tasks: [.text, .vision, .speech], keyHint: "AIza…"),
        NotchyProvider(id: "openai", name: "OpenAI", kind: .openAICompatible, defaultBaseURL: "https://api.openai.com/v1",
                       defaultModel: "gpt-4o-mini", needsKey: true, tasks: [.text, .vision, .speech], keyHint: "sk-…"),
        NotchyProvider(id: "ollama", name: "Ollama (on this Mac)", kind: .openAICompatible, defaultBaseURL: "http://localhost:11434/v1",
                       defaultModel: "llama3.2", needsKey: false, tasks: [.text, .vision], keyHint: "not needed"),
        NotchyProvider(id: "vllm", name: "vLLM (your server)", kind: .openAICompatible, defaultBaseURL: "http://localhost:8000/v1",
                       defaultModel: "", needsKey: false, tasks: [.text, .vision, .speech], keyHint: "if your server asks for one"),
        NotchyProvider(id: "elevenlabs", name: "ElevenLabs", kind: .elevenLabs, defaultBaseURL: "https://api.elevenlabs.io",
                       defaultModel: "scribe_v1", needsKey: true, tasks: [.speech], keyHint: "sk_…"),
        NotchyProvider(id: "system", name: "macOS (built in)", kind: .system, defaultBaseURL: "",
                       defaultModel: "", needsKey: false, tasks: [.speech], keyHint: "not needed"),
    ]

    static func provider(_ id: String) -> NotchyProvider? { all.first { $0.id == id } }
    static func options(for task: NotchyTask) -> [NotchyProvider] { all.filter { $0.tasks.contains(task) } }
}

// MARK: - Keys, in the Keychain

/// API keys live in the macOS Keychain, one item per provider, and nowhere else: not in the settings, not in a file.
/// Reads that are not the answer to a click never let macOS ask for the login password.
enum NotchyKeychain {
    private static let service = "com.giuseppe.Notcholino.notchy"
    private static let queue = DispatchQueue(label: "com.giuseppe.Notcholino.notchy.keychain", qos: .utility)

    private static func query(_ provider: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: provider]
    }

    /// Whether a key is saved: attributes only, never the secret
    static func hasKey(_ provider: String) async -> Bool {
        await withCheckedContinuation { c in
            queue.async {
                var q = query(provider)
                q[kSecReturnAttributes as String] = true
                q[kSecMatchLimit as String] = kSecMatchLimitOne
                c.resume(returning: SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess)
            }
        }
    }

    static func read(_ provider: String, interactive: Bool) async -> String? {
        await withCheckedContinuation { c in
            queue.async {
                var q = query(provider)
                q[kSecReturnData as String] = true
                q[kSecMatchLimit as String] = kSecMatchLimitOne
                if !interactive { SecKeychainSetUserInteractionAllowed(false) }
                defer { if !interactive { SecKeychainSetUserInteractionAllowed(true) } }
                var out: CFTypeRef?
                guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else {
                    c.resume(returning: nil); return
                }
                c.resume(returning: String(data: data, encoding: .utf8))
            }
        }
    }

    static func save(_ key: String, for provider: String) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async {
                let data = Data(key.utf8)
                if SecItemUpdate(query(provider) as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
                    var q = query(provider)
                    q[kSecValueData as String] = data
                    SecItemAdd(q as CFDictionary, nil)
                }
                c.resume()
            }
        }
    }

    static func remove(_ provider: String) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async { SecItemDelete(query(provider) as CFDictionary); c.resume() }
        }
    }
}

// MARK: - Talking to them

struct NotchyAIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// One text request to the provider chosen for a task. Only used when the user asks for something (or answers a peek):
/// the "when to act" part of Notchy runs on plain local rules and never calls a model.
enum NotchyClient {
    static func complete(prompt: String, system: String? = nil, task: NotchyTask = .text) async throws -> String {
        let config = NotchySettings.shared
        guard let providerID = config.providerID(for: task), let provider = NotchyProvider.provider(providerID) else {
            throw NotchyAIError(message: "Choose a provider for \(task.title.lowercased()) in Settings → Notchy.")
        }
        var key = ""
        if provider.needsKey {
            // A click asked for this, so a Keychain question is fine
            guard let k = await NotchyKeychain.read(provider.id, interactive: true), !k.isEmpty else {
                throw NotchyAIError(message: "No key saved for \(provider.name).")
            }
            key = k
        } else if let k = await NotchyKeychain.read(provider.id, interactive: false) { key = k }
        let base = config.baseURL(for: provider)
        let model = config.model(for: provider, task: task)
        switch provider.kind {
        case .anthropic:        return try await anthropic(base: base, key: key, model: model, prompt: prompt, system: system)
        case .gemini:           return try await gemini(base: base, key: key, model: model, prompt: prompt, system: system)
        case .openAICompatible: return try await openAI(base: base, key: key, model: model, prompt: prompt, system: system)
        case .elevenLabs, .system: throw NotchyAIError(message: "\(provider.name) does not write text.")
        }
    }

    private static func send(_ request: URLRequest) async throws -> [String: Any] {
        var request = request
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NotchyAIError(message: "No answer.") }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            let detail = ((json["error"] as? [String: Any])?["message"] as? String) ?? (json["error"] as? String) ?? "HTTP \(http.statusCode)"
            throw NotchyAIError(message: detail)
        }
        return json
    }

    private static func anthropic(base: String, key: String, model: String, prompt: String, system: String?) async throws -> String {
        var r = URLRequest(url: URL(string: base + "/v1/messages")!)
        r.httpMethod = "POST"
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        var body: [String: Any] = ["model": model, "max_tokens": 1024, "messages": [["role": "user", "content": prompt]]]
        if let system { body["system"] = system }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let json = try await send(r)
        let parts = (json["content"] as? [[String: Any]]) ?? []
        return parts.compactMap { $0["text"] as? String }.joined()
    }

    private static func gemini(base: String, key: String, model: String, prompt: String, system: String?) async throws -> String {
        var r = URLRequest(url: URL(string: "\(base)/v1beta/models/\(model):generateContent")!)
        r.httpMethod = "POST"
        r.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        var body: [String: Any] = ["contents": [["parts": [["text": prompt]]]]]
        if let system { body["systemInstruction"] = ["parts": [["text": system]]] }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let json = try await send(r)
        let candidates = (json["candidates"] as? [[String: Any]]) ?? []
        let parts = ((candidates.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        return parts.compactMap { $0["text"] as? String }.joined()
    }

    private static func openAI(base: String, key: String, model: String, prompt: String, system: String?) async throws -> String {
        var r = URLRequest(url: URL(string: base + "/chat/completions")!)
        r.httpMethod = "POST"
        if !key.isEmpty { r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        var messages: [[String: String]] = []
        if let system { messages.append(["role": "system", "content": system]) }
        messages.append(["role": "user", "content": prompt])
        r.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "messages": messages])
        let json = try await send(r)
        let choices = (json["choices"] as? [[String: Any]]) ?? []
        return ((choices.first?["message"] as? [String: Any])?["content"] as? String) ?? ""
    }
}
