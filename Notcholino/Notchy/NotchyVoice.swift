// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import AppKit
import Carbon.HIToolbox
import Speech

/// A shortcut the user recorded: a combination (hold to talk) or a single modifier key such as Fn (hold to talk, or double-tap
/// for hands-free and tap again to stop)
struct NotchyShortcut: Codable, Equatable {
    enum Kind: String, Codable { case combo, modifier }
    var kind: Kind
    var keyCode: UInt32
    var modifiers: UInt32      // Carbon mask, for combos
    var label: String

    static let fn = NotchyShortcut(kind: .modifier, keyCode: 63, modifiers: 0, label: "Fn")

    /// The flag that says a single modifier key is down
    var modifierFlag: NSEvent.ModifierFlags? {
        switch keyCode {
        case 63: return .function
        case 58, 61: return .option
        case 55, 54: return .command
        case 59, 62: return .control
        case 56, 60: return .shift
        default: return nil
        }
    }

    static func modifierName(_ code: UInt32) -> String? {
        ["63": "Fn", "58": "Left ⌥", "61": "Right ⌥", "55": "Left ⌘", "54": "Right ⌘", "59": "Left ⌃", "62": "Right ⌃", "56": "Left ⇧", "60": "Right ⇧"]["\(code)"]
    }

    static func carbonMask(_ f: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    static func comboLabel(_ event: NSEvent) -> String {
        let f = event.modifierFlags
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        let key = event.keyCode == 49 ? "Space" : (event.charactersIgnoringModifiers ?? "").uppercased()
        return s + " " + key
    }
}

/// Voice input for Notchy: hold the shortcut, speak, let go. The provider chosen for voice turns the audio into text, and the
/// text goes to Notchy like anything else. Notchy always answers in writing. Nothing listens until the shortcut is used.
final class NotchyVoice: ObservableObject {
    static let shared = NotchyVoice()

    @Published var shortcut: NotchyShortcut? {
        didSet {
            UserDefaults.standard.set(shortcut.flatMap { try? JSONEncoder().encode($0) }, forKey: "notchyShortcutV2")
            apply()
        }
    }
    @Published private(set) var listening = false
    /// Set while the settings are waiting for the user to press a shortcut
    @Published var recording = false

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var flagMonitor: Any?
    private var localFlagMonitor: Any?
    private var keyMonitor: Any?
    private var localKeyMonitor: Any?
    private var recorder: AVAudioRecorder?
    private var startedAt = Date()
    private var stopTask: Task<Void, Never>?
    // Single-key state
    private var downAt: Date?
    private var lastTapEnd: Date?
    private var handsFree = false
    private var armTask: Task<Void, Never>?

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "notchyShortcutV2"), let s = try? JSONDecoder().decode(NotchyShortcut.self, from: data) { shortcut = s }
        else if d.object(forKey: "notchyShortcutV2") == nil { shortcut = .fn }
    }

    var shortcutLabel: String { shortcut?.label ?? "" }

    /// Registers (or removes) the global shortcut. Only while Notchy is on and a voice provider is chosen.
    func apply() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        for m in [flagMonitor, localFlagMonitor, keyMonitor, localKeyMonitor] { if let m { NSEvent.removeMonitor(m) } }
        flagMonitor = nil; localFlagMonitor = nil; keyMonitor = nil; localKeyMonitor = nil
        let s = NotchySettings.shared
        guard s.enabled, s.providerID(for: .speech) != nil, !recording, let sc = shortcut else { return }
        switch sc.kind {
        case .combo:
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
        case .modifier:
            guard let flag = sc.modifierFlag else { return }
            let handle: (NSEvent) -> Void = { [weak self] event in
                guard event.keyCode == UInt16(sc.keyCode) else { return }
                if event.modifierFlags.contains(flag) { self?.modifierDown() } else { self?.modifierUp() }
            }
            // Global events come from other apps; local ones from Notcholino's own windows (Settings), so it works in both
            flagMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handle)
            localFlagMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { handle($0); return $0 }
            // A letter pressed while the key is down means a key combination (⌘C): not for Notchy
            let other: (NSEvent) -> Void = { [weak self] _ in self?.otherKeyDuringHold() }
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: other)
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { other($0); return $0 }
        }
    }

    // MARK: A single modifier key: hold to talk, or double-tap for hands-free and tap to stop

    private func modifierDown() {
        if handsFree { handsFree = false; finish(); return }
        downAt = Date()
        if let last = lastTapEnd, Date().timeIntervalSince(last) < 0.45 {
            lastTapEnd = nil
            handsFree = true
            begin()
        } else {
            // A short tap is not for us: start only if the key stays down a moment
            armTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 280_000_000)
                if !Task.isCancelled, self?.downAt != nil { self?.begin() }
            }
        }
    }

    private func otherKeyDuringHold() {
        guard downAt != nil, !handsFree else { return }
        armTask?.cancel()
        downAt = nil
        lastTapEnd = nil
        if listening { cancelListening() }
    }

    private func cancelListening() {
        stopTask?.cancel()
        listening = false
        recorder?.stop()
        if let url = recorder?.url { try? FileManager.default.removeItem(at: url) }
        recorder = nil
        PopupCenter.shared.dismiss()
        NotchyPresence.shared.peek(mood: .calm, seconds: 0.1)
    }

    private func modifierUp() {
        guard let down = downAt else { return }
        downAt = nil
        armTask?.cancel()
        if handsFree { return }
        if Date().timeIntervalSince(down) >= 0.28 { finish() } else { lastTapEnd = Date() }
    }

    // MARK: Recording

    private func begin() {
        guard !listening, NotchySettings.shared.enabled else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { if ok { PopupCenter.shared.show(icon: "mic.fill", title: "Microphone allowed", subtitle: "Use the shortcut again to talk", seconds: 4) } } }
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
        PopupCenter.shared.show(icon: "mic.fill", title: "Listening…", subtitle: handsFree ? "Tap the key again when you are done" : "Let go when you are done", seconds: 15)
        // Never listen for more than a minute, even if the keys stay down
        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            if !Task.isCancelled { self?.handsFree = false; self?.finish() }
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
        NotchyAssistant.shared.transcribeAndAsk(r.url)
    }

    // MARK: Recording a new shortcut (the settings ask for a key; this is like Wispr Flow)

    private var localMonitor: Any?
    private var candidate: UInt32?
    private var otherKeyPressed = false

    func startRecordingShortcut() {
        stopRecordingShortcut()
        recording = true
        apply()          // the current shortcut stops reacting while a new one is being chosen
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        candidate = nil; otherKeyPressed = false
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.stopRecordingShortcut(); return nil }           // Esc cancels
                let mods = NotchyShortcut.carbonMask(event.modifierFlags.intersection([.command, .option, .control, .shift]))
                guard mods != 0 else { return nil }                                            // a bare letter is not a shortcut
                self.otherKeyPressed = true
                self.shortcut = NotchyShortcut(kind: .combo, keyCode: UInt32(event.keyCode), modifiers: mods, label: NotchyShortcut.comboLabel(event))
                self.stopRecordingShortcut()
                return nil
            }
            // flagsChanged: a modifier alone, pressed and released
            let code = UInt32(event.keyCode)
            guard let name = NotchyShortcut.modifierName(code) else { return event }
            let all = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])
            if all.isEmpty {
                if self.candidate == code, !self.otherKeyPressed {
                    self.shortcut = NotchyShortcut(kind: .modifier, keyCode: code, modifiers: 0, label: name)
                    self.stopRecordingShortcut()
                }
                self.candidate = nil
            } else if self.candidate == nil {
                self.candidate = code
            } else if self.candidate != code {
                self.otherKeyPressed = true      // two modifiers: wait for a letter to make a combination
            }
            return nil
        }
    }

    func stopRecordingShortcut() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        recording = false
        apply()
    }

    func clearShortcut() { shortcut = nil }
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
