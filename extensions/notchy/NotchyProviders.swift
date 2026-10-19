// SPDX-License-Identifier: GPL-3.0-only
import AppKit
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
    /// Models that make sense for each task, best first. Only what the provider is good at for that task is listed.
    let suggestions: [NotchyTask: [String]]
    let needsKey: Bool
    /// Which tasks it can do
    let tasks: Set<NotchyTask>
    let keyHint: String

    static let all: [NotchyProvider] = [
        NotchyProvider(id: "anthropic", name: "Anthropic (Claude)", kind: .anthropic, defaultBaseURL: "https://api.anthropic.com",
                       suggestions: [.text: ["claude-sonnet-5-5", "claude-haiku-5-5", "claude-opus-5-5"],
                                     .vision: ["claude-sonnet-5-5", "claude-haiku-5-5", "claude-opus-5-5"]],
                       needsKey: true, tasks: [.text, .vision], keyHint: "sk-ant-…"),
        NotchyProvider(id: "gemini", name: "Google Gemini", kind: .gemini, defaultBaseURL: "https://generativelanguage.googleapis.com",
                       suggestions: [.text: ["gemini-flash-latest", "gemini-flash-lite-latest", "gemini-pro-latest"],
                                     .vision: ["gemini-flash-latest", "gemini-pro-latest"],
                                     .speech: ["gemini-flash-latest", "gemini-flash-lite-latest"]],
                       needsKey: true, tasks: [.text, .vision, .speech], keyHint: "AIza…"),
        NotchyProvider(id: "openai", name: "OpenAI", kind: .openAICompatible, defaultBaseURL: "https://api.openai.com/v1",
                       suggestions: [.text: ["gpt-4o-mini", "gpt-4o"],
                                     .vision: ["gpt-4o-mini", "gpt-4o"],
                                     .speech: ["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "whisper-1"]],
                       needsKey: true, tasks: [.text, .vision, .speech], keyHint: "sk-…"),
        NotchyProvider(id: "ollama", name: "Ollama (on this Mac)", kind: .openAICompatible, defaultBaseURL: "http://localhost:11434/v1",
                       suggestions: [.text: ["llama3.2", "qwen2.5", "gemma3"], .vision: ["llama3.2-vision", "llava", "gemma3"]],
                       needsKey: false, tasks: [.text, .vision], keyHint: "not needed"),
        NotchyProvider(id: "vllm", name: "vLLM (your server)", kind: .openAICompatible, defaultBaseURL: "http://localhost:8000/v1",
                       suggestions: [:], needsKey: false, tasks: [.text, .vision], keyHint: "if your server asks for one"),
        NotchyProvider(id: "elevenlabs", name: "ElevenLabs", kind: .elevenLabs, defaultBaseURL: "https://api.elevenlabs.io",
                       suggestions: [.speech: ["scribe_v1"]], needsKey: true, tasks: [.speech], keyHint: "sk_…"),
        NotchyProvider(id: "system", name: "macOS (built in)", kind: .system, defaultBaseURL: "",
                       suggestions: [:], needsKey: false, tasks: [.speech], keyHint: "not needed"),
    ]

    func models(for task: NotchyTask) -> [String] { suggestions[task] ?? [] }
    /// Whether the user can type a model name (always true for servers they run themselves)
    var listsModels: Bool { kind != .system }

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
    /// The provider chosen for a task with its key, address and model. A click or a shortcut asked for this, so a Keychain
    /// question is fine; nothing here ever runs in the background.
    static func resolve(_ task: NotchyTask) async throws -> (provider: NotchyProvider, key: String, base: String, model: String) {
        let config = NotchySettings.shared
        guard let providerID = config.providerID(for: task), let provider = NotchyProvider.provider(providerID) else {
            throw NotchyAIError(message: "Choose a provider for \(task.title.lowercased()) in Settings → Notchy.")
        }
        var key = ""
        if provider.needsKey {
            guard let k = await NotchyKeychain.read(provider.id, interactive: true), !k.isEmpty else {
                throw NotchyAIError(message: "No key saved for \(provider.name).")
            }
            key = k
        } else if let k = await NotchyKeychain.read(provider.id, interactive: false) { key = k }
        return (provider, key, config.baseURL(for: provider), config.model(for: provider, task: task))
    }

    static func complete(prompt: String, system: String? = nil, task: NotchyTask = .text, image: Data? = nil) async throws -> String {
        let (provider, key, base, model) = try await resolve(task)
        guard !model.isEmpty else { throw NotchyAIError(message: "Choose a model for \(provider.name) in Settings → Notchy.") }
        switch provider.kind {
        case .anthropic:        return try await anthropic(base: base, key: key, model: model, prompt: prompt, system: system, image: image)
        case .gemini:           return try await gemini(base: base, key: key, model: model, prompt: prompt, system: system, image: image)
        case .openAICompatible: return try await openAI(base: base, key: key, model: model, prompt: prompt, system: system, image: image)
        case .elevenLabs, .system: throw NotchyAIError(message: "\(provider.name) does not write text.")
        }
    }

    static func send(_ request: URLRequest) async throws -> [String: Any] {
        var request = request
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NotchyAIError(message: "No answer.") }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            let detail = ((json["error"] as? [String: Any])?["message"] as? String) ?? (json["error"] as? String) ?? "HTTP \(http.statusCode)"
            switch http.statusCode {
            case 429, 503, 529:
                throw NotchyAIError(message: "The provider is busy right now (\(http.statusCode)). Try again in a moment, or pick another model.")
            case 404:
                throw NotchyAIError(message: "That model was not found. Pick another from the list. (\(detail))")
            case 401, 403:
                throw NotchyAIError(message: "The key was refused: \(detail)")
            default:
                throw NotchyAIError(message: detail)
            }
        }
        return json
    }

    private static func anthropic(base: String, key: String, model: String, prompt: String, system: String?, image: Data?) async throws -> String {
        var r = URLRequest(url: URL(string: base + "/v1/messages")!)
        r.httpMethod = "POST"
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        var content: [[String: Any]] = []
        if let image { content.append(["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": image.base64EncodedString()]]) }
        content.append(["type": "text", "text": prompt])
        var body: [String: Any] = ["model": model, "max_tokens": 1024, "messages": [["role": "user", "content": content]]]
        if let system { body["system"] = system }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let json = try await send(r)
        let parts = (json["content"] as? [[String: Any]]) ?? []
        return parts.compactMap { $0["text"] as? String }.joined()
    }

    private static func gemini(base: String, key: String, model: String, prompt: String, system: String?, image: Data?) async throws -> String {
        var r = URLRequest(url: URL(string: "\(base)/v1beta/models/\(model):generateContent")!)
        r.httpMethod = "POST"
        r.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        var parts: [[String: Any]] = []
        if let image { parts.append(["inline_data": ["mime_type": "image/png", "data": image.base64EncodedString()]]) }
        parts.append(["text": prompt])
        var body: [String: Any] = ["contents": [["parts": parts]]]
        if let system { body["systemInstruction"] = ["parts": [["text": system]]] }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let json = try await send(r)
        let candidates = (json["candidates"] as? [[String: Any]]) ?? []
        let reply = ((candidates.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        return reply.compactMap { $0["text"] as? String }.joined()
    }

    private static func openAI(base: String, key: String, model: String, prompt: String, system: String?, image: Data?) async throws -> String {
        var r = URLRequest(url: URL(string: base + "/chat/completions")!)
        r.httpMethod = "POST"
        if !key.isEmpty { r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        var messages: [[String: Any]] = []
        if let system { messages.append(["role": "system", "content": system]) }
        if let image {
            messages.append(["role": "user", "content": [["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": "data:image/png;base64," + image.base64EncodedString()]]]])
        } else {
            messages.append(["role": "user", "content": prompt])
        }
        r.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "messages": messages])
        let json = try await send(r)
        let choices = (json["choices"] as? [[String: Any]]) ?? []
        return ((choices.first?["message"] as? [String: Any])?["content"] as? String) ?? ""
    }

    // MARK: Model lists

    /// The models the provider itself says it has, for the Refresh button: so the choices are never a stale guess.
    /// Only models that can do the task are returned.
    static func listModels(provider: NotchyProvider, task: NotchyTask) async throws -> [String] {
        var key = ""
        if provider.needsKey {
            guard let k = await NotchyKeychain.read(provider.id, interactive: true), !k.isEmpty else {
                throw NotchyAIError(message: "Save a key for \(provider.name) first.")
            }
            key = k
        }
        let base = NotchySettings.shared.baseURL(for: provider)
        var r: URLRequest
        switch provider.kind {
        case .anthropic:
            r = URLRequest(url: URL(string: base + "/v1/models?limit=100")!)
            r.setValue(key, forHTTPHeaderField: "x-api-key"); r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .gemini:
            r = URLRequest(url: URL(string: base + "/v1beta/models?pageSize=200")!)
            r.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        case .openAICompatible:
            let isOllama = provider.id == "ollama"
            r = URLRequest(url: URL(string: isOllama ? base.replacingOccurrences(of: "/v1", with: "") + "/api/tags" : base + "/models")!)
            if !key.isEmpty { r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        case .elevenLabs:
            r = URLRequest(url: URL(string: base + "/v1/models")!)
            r.setValue(key, forHTTPHeaderField: "xi-api-key")
        case .system:
            return []
        }
        let (data, response) = try await {
            var req = r; req.timeoutInterval = 20
            return try await URLSession.shared.data(for: req)
        }()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NotchyAIError(message: "Could not get the list of models (check the key and the address).")
        }
        let any = try? JSONSerialization.jsonObject(with: data)
        var names: [String] = []
        switch provider.kind {
        case .anthropic:
            names = ((any as? [String: Any])?["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        case .gemini:
            for m in (any as? [String: Any])?["models"] as? [[String: Any]] ?? [] {
                guard let name = (m["name"] as? String)?.replacingOccurrences(of: "models/", with: ""),
                      (m["supportedGenerationMethods"] as? [String])?.contains("generateContent") == true else { continue }
                let lower = name.lowercased()
                if ["embedding", "tts", "image", "imagen", "veo", "aqa", "live", "robotics", "computer-use", "audio-dialog"].contains(where: lower.contains) { continue }
                names.append(name)
            }
        case .openAICompatible:
            if provider.id == "ollama" {
                names = ((any as? [String: Any])?["models"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            } else {
                names = ((any as? [String: Any])?["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
                let lower: (String) -> String = { $0.lowercased() }
                if provider.id == "openai" {
                    if task == .speech {
                        names = names.filter { lower($0).contains("transcribe") || lower($0).contains("whisper") }
                    } else {
                        let off = ["audio", "realtime", "transcribe", "tts", "image", "embedding", "whisper", "moderation", "dall", "search", "codex", "instruct", "davinci", "babbage"]
                        names = names.filter { n in (lower(n).hasPrefix("gpt") || lower(n).hasPrefix("o")) && !off.contains(where: lower(n).contains) }
                    }
                }
            }
        case .elevenLabs:
            names = (any as? [[String: Any]] ?? []).compactMap { $0["model_id"] as? String }.filter { $0.contains("scribe") }
        case .system: break
        }
        return Array(Set(names)).sorted()
    }

    /// A tiny red square, for testing that a model can see images
    static func testImage() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 48, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.red.setFill(); NSBezierPath.fill(NSRect(x: 0, y: 0, width: 48, height: 48))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}
