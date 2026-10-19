// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import AppKit
import Carbon.HIToolbox
import Speech

/// Voice input for Notchy: hold the shortcut, speak, let go. The audio is turned into text by the provider chosen for voice, and
/// the text goes to Notchy like anything else. Notchy always answers in writing. Nothing listens until the key is held down.
final class NotchyVoice: ObservableObject {
    static let shared = NotchyVoice()

    struct Shortcut: Identifiable, Hashable {
        let id: String, label: String, keyCode: UInt32, modifiers: UInt32
        static let all = [
            Shortcut(id: "ctrlOptSpace", label: "⌃⌥ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)),
            Shortcut(id: "ctrlOptN", label: "⌃⌥ N", keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey)),
            Shortcut(id: "ctrlOptV", label: "⌃⌥ V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey)),
        ]
    }

    @Published var shortcutID: String { didSet { UserDefaults.standard.set(shortcutID, forKey: "notchyShortcut"); apply() } }
    @Published private(set) var listening = false

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var recorder: AVAudioRecorder?
    private var startedAt = Date()
    private var stopTask: Task<Void, Never>?

    init() { shortcutID = UserDefaults.standard.string(forKey: "notchyShortcut") ?? "ctrlOptSpace" }

    var shortcutLabel: String { Shortcut.all.first { $0.id == shortcutID }?.label ?? "" }

    /// Registers (or removes) the global shortcut. Only while Notchy is on and a voice provider is chosen.
    func apply() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        let s = NotchySettings.shared
        guard s.enabled, s.providerID(for: .speech) != nil, let sc = Shortcut.all.first(where: { $0.id == shortcutID }) else { return }
        if handler == nil {
            var spec = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                        EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                let kind = GetEventKind(event)
                DispatchQueue.main.async {
                    if kind == UInt32(kEventHotKeyPressed) { NotchyVoice.shared.begin() } else { NotchyVoice.shared.finish() }
                }
                return noErr
            }, 2, &spec, nil, &handler)
        }
        RegisterEventHotKey(sc.keyCode, sc.modifiers, EventHotKeyID(signature: OSType(0x4E54_4348), id: 1), GetApplicationEventTarget(), 0, &hotKey)
    }

    private func begin() {
        guard !listening, NotchySettings.shared.enabled else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { if ok { PopupCenter.shared.show(icon: "mic.fill", title: "Microphone allowed", subtitle: "Hold the shortcut again to talk", seconds: 4) } } }
        default:
            PopupCenter.shared.show(icon: "mic.slash.fill", title: "Notchy can't hear you", subtitle: "Allow the microphone in System Settings → Privacy & Security", tint: .orange, seconds: 6)
        }
    }

    private func start() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notchy-voice.wav")
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
                                       AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false]
        guard let r = try? AVAudioRecorder(url: url, settings: settings), r.record() else { return }
        recorder = r
        listening = true
        startedAt = Date()
        NotchyPresence.shared.peek(mood: .curious, seconds: 70)
        PopupCenter.shared.show(icon: "mic.fill", title: "Listening…", subtitle: "Let go of the keys when you are done", seconds: 15)
        // Never listen for more than a minute, even if the keys stay down
        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            if !Task.isCancelled { self?.finish() }
        }
    }

    private func finish() {
        guard listening, let r = recorder else { return }
        stopTask?.cancel()
        listening = false
        r.stop()
        recorder = nil
        PopupCenter.shared.dismiss()
        guard Date().timeIntervalSince(startedAt) > 0.5 else { NotchyPresence.shared.peek(mood: .calm, seconds: 0.1); return }
        let file = r.url
        NotchyAssistant.shared.transcribeAndAsk(file)
    }
}

// MARK: - Turning speech into text

enum NotchyTranscriber {
    static func transcribe(_ file: URL) async throws -> String {
        let (provider, key, base, model) = try await NotchyClient.resolve(.speech)
        let audio = try Data(contentsOf: file)
        switch provider.kind {
        case .system:
            return try await onDevice(file)
        case .gemini:
            var r = URLRequest(url: URL(string: "\(base)/v1beta/models/\(model):generateContent")!)
            r.httpMethod = "POST"
            r.setValue(key, forHTTPHeaderField: "x-goog-api-key"); r.setValue("application/json", forHTTPHeaderField: "content-type")
            r.httpBody = try JSONSerialization.data(withJSONObject: ["contents": [["parts": [
                ["inline_data": ["mime_type": "audio/wav", "data": audio.base64EncodedString()]],
                ["text": "Transcribe this audio exactly, in the language spoken. Reply with the transcription only."]]]]])
            let json = try await NotchyClient.send(r)
            let parts = (((json["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
            return parts.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        case .openAICompatible:
            return try await multipart(url: base + "/audio/transcriptions", headers: key.isEmpty ? [:] : ["Authorization": "Bearer \(key)"],
                                       field: "model", value: model, audio: audio)
        case .elevenLabs:
            return try await multipart(url: base + "/v1/speech-to-text", headers: ["xi-api-key": key], field: "model_id", value: model, audio: audio)
        case .anthropic:
            throw NotchyAIError(message: "\(provider.name) can't turn voice into text.")
        }
    }

    private static func multipart(url: String, headers: [String: String], field: String, value: String, audio: Data) async throws -> String {
        let boundary = "notchy-\(UUID().uuidString)"
        var body = Data()
        func add(_ s: String) { body.append(Data(s.utf8)) }
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field)\"\r\n\r\n\(value)\r\n")
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"voice.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
        body.append(audio)
        add("\r\n--\(boundary)--\r\n")
        var r = URLRequest(url: URL(string: url)!)
        r.httpMethod = "POST"
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type")
        headers.forEach { r.setValue($1, forHTTPHeaderField: $0) }
        r.httpBody = body
        let json = try await NotchyClient.send(r)
        return ((json["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The Mac's own recogniser: free, and on the device when the language allows it
    private static func onDevice(_ file: URL) async throws -> String {
        let status = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard status == .authorized else { throw NotchyAIError(message: "Allow Speech Recognition in System Settings → Privacy & Security.") }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: NotchySettings.shared.replyLanguageLocale)), recognizer.isAvailable else {
            throw NotchyAIError(message: "The Mac can't recognise speech in this language right now.")
        }
        let request = SFSpeechURLRecognitionRequest(url: file)
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        return try await withCheckedThrowingContinuation { c in
            var done = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !done else { return }
                if let result, result.isFinal { done = true; c.resume(returning: result.bestTranscription.formattedString) }
                else if let error { done = true; c.resume(throwing: error) }
            }
        }
    }
}
