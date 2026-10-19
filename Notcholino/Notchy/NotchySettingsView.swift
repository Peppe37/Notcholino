// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// Notchy's settings, one topic per tab so nothing is crowded: how it behaves, which AI does what, voice and screen, day and email.
struct NotchySettingsView: View {
    @ObservedObject private var settings = NotchySettings.shared
    @State private var tab: Tab = .general

    enum Tab: String, CaseIterable, Identifiable {
        case general = "General", ai = "AI", voice = "Voice & screen", day = "Day & email"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20).padding(.bottom, 6)
            .disabled(!settings.enabled)
            Group {
                if settings.enabled {
                    switch tab {
                    case .general: GeneralTab()
                    case .ai:      AITab()
                    case .voice:   VoiceTab()
                    case .day:     DayTab()
                    }
                } else {
                    Form { Section { Text("Turn Notchy on to set it up.").foregroundStyle(.secondary) } }.formStyle(.grouped)
                }
            }
        }
        .navigationTitle("Notchy")
    }

    private var header: some View {
        HStack(spacing: 16) {
            NotchyCube(mood: settings.enabled ? .calm : .sleepy, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Toggle("Notchy", isOn: $settings.enabled).font(.headline)
                Text("A small glass cube that lives in the notch. It helps with files and your day when you ask, and keeps you company without getting in the way.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject private var settings = NotchySettings.shared

    var body: some View {
        Form {
            Section {
                Picker("How lively", selection: $settings.level) {
                    ForEach(NotchyLevel.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: { Text(settings.level.detail) }

            Section {
                Toggle("Show its page in the notch", isOn: $settings.pageVisible)
                Picker("Answer in", selection: $settings.replyLanguage) {
                    Text("The language of the text").tag("")
                    Divider()
                    ForEach(["Italiano", "English", "Español", "Français", "Deutsch", "Português", "Nederlands", "Polski", "Română", "Українська", "Русский", "Türkçe", "العربية", "हिन्दी", "日本語", "한국어", "中文"], id: \.self) { Text($0).tag($0) }
                }
            } footer: { Text("Notchy always answers in writing, in a short note under the notch. Move to the notch to read it in full.") }

            Section {
                Text("Right-click selected text, or a file in Finder → Services → Send to Notchy.")
                Text("Hold your voice shortcut and speak (Voice & screen).")
                Text("Open its page in the notch for Plan my day and Look at the screen.")
            } header: { Text("Ways to use it") }
        }
        .formStyle(.grouped)
    }
}

// MARK: - AI

private struct AITab: View {
    @ObservedObject private var settings = NotchySettings.shared
    @State private var savedKeys: Set<String> = []

    var body: some View {
        Form {
            ForEach(NotchyTask.allCases) { task in taskSection(task) }

            Section {
                ForEach(NotchyProvider.all.filter(\.needsKey)) { provider in
                    KeyRow(provider: provider, saved: savedKeys.contains(provider.id)) { await refreshKeys() }
                }
            } header: { Text("Keys") } footer: {
                Text("Keys are kept in the macOS Keychain, one for each provider, and are only sent to that provider. Notchy never reads them in the background.")
            }
        }
        .formStyle(.grouped)
        .task { await refreshKeys() }
    }

    private func refreshKeys() async {
        var found: Set<String> = []
        for p in NotchyProvider.all where p.needsKey { if await NotchyKeychain.hasKey(p.id) { found.insert(p.id) } }
        savedKeys = found
    }

    @ViewBuilder
    private func taskSection(_ task: NotchyTask) -> some View {
        let options = NotchyProvider.options(for: task)
        let current = settings.providerID(for: task)
        Section {
            Picker(task.title, selection: Binding(
                get: { current ?? "" },
                set: { settings.setProvider($0.isEmpty ? nil : $0, for: task) })) {
                Text("None").tag("")
                ForEach(options) { Text($0.name).tag($0.id) }
            }
            if let id = current, let provider = NotchyProvider.provider(id), provider.kind != .system {
                // The big providers have one fixed address; only servers you run yourself need one
                if provider.id == "ollama" || provider.id == "vllm" {
                    TextField("Address", text: Binding(get: { settings.baseURL(for: provider) },
                                                       set: { settings.setBaseURL($0, for: provider) }))
                        .textFieldStyle(.roundedBorder)
                }
                ModelRow(provider: provider, task: task)
                TestRow(provider: provider, task: task)
            }
        } footer: { Text(task.detail) }
    }
}

// MARK: - Voice & screen

private struct VoiceTab: View {
    @ObservedObject private var settings = NotchySettings.shared
    @ObservedObject private var voice = NotchyVoice.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Shortcut") {
                    HStack {
                        Text(voice.recording ? "Press the shortcut…" : (voice.shortcut?.label ?? "None"))
                            .foregroundStyle(voice.recording ? Color.accentColor : .primary)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)))
                        if voice.recording {
                            Button("Cancel") { voice.stopRecordingShortcut() }
                        } else {
                            Button("Record") { voice.startRecordingShortcut() }
                            if voice.shortcut != nil { Button("Remove") { voice.clearShortcut() } }
                        }
                    }
                }
                if let s = voice.shortcut, s.kind == .modifier {
                    Text("With a single key: hold it and speak, or double-tap to start hands-free and tap once to stop.")
                        .font(.caption).foregroundStyle(.secondary)
                    if s.keyCode == 63 {
                        Text("If the Mac starts dictation or the emoji picker, set “Press 🌐 key to” to “Do Nothing” in System Settings → Keyboard.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Talk to Notchy") } footer: {
                Text(settings.providerID(for: .speech) == nil
                     ? "Choose a provider for voice to text in the AI tab first. Notchy answers in writing."
                     : "Click Record, then press a combination (hold to talk) or tap a single key such as Fn. Notchy listens only while you use it, for at most a minute.")
            }

            Section {
                Text("“Look at the screen” (on Notchy's page) reads the text on the screen on your Mac first and sends only that text when there is enough of it. A picture goes to the provider chosen for images only when there is little text. It needs Screen Recording.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Screen") }
        }
        .formStyle(.grouped)
        .onDisappear { voice.stopRecordingShortcut() }
    }
}

// MARK: - Day & email

private struct DayTab: View {
    @ObservedObject private var mail = NotchyMail.shared
    @ObservedObject private var settings = NotchySettings.shared
    @State private var draft = ""

    var body: some View {
        Form {
            Section {
                Text("Plan my day and your spoken questions about the day use only the calendars ticked in Settings → Calendar (not the ones shown in Calendar.app), plus the reminders the notch shows. Only titles and times are sent: never places, notes or people.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("My city", text: $settings.homeCity, prompt: Text("For the weather when you do not say where"))
            } header: { Text("Your day") } footer: {
                Text("Ask Notchy about the weather (“che tempo fa a Roma domani?”) and it looks it up on Open-Meteo, a free service with no account. Only the name of the place is sent.")
            }

            Section {
                Toggle("Tell me about important emails", isOn: $mail.enabled)
                if mail.enabled {
                    HStack {
                        TextField("Sender", text: $draft, prompt: Text("Add a sender: an address or part of a name"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(add)
                        Button("Add", action: add).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if mail.senders.isEmpty {
                        Text("No senders yet.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(mail.senders, id: \.self) { sender in
                            HStack {
                                Image(systemName: "envelope.fill").foregroundStyle(.secondary)
                                Text(sender)
                                Spacer()
                                Button { mail.remove(sender) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    Toggle("Open Mail in the background when it is closed", isOn: $mail.keepMailOpen)
                    HStack {
                        Button("Check now") { mail.test() }
                        if let result = mail.testResult { Text(result).font(.caption).foregroundStyle(.secondary).lineLimit(4) }
                    }
                }
            } header: { Text("Email") } footer: {
                Text("Works with the accounts in Mail (Gmail, iCloud, Microsoft). Mail only receives email while it is open, so Notchy can open it hidden for you. It looks every few minutes (not when Notchy is Silent) and only compares the sender with your list: no email is sent anywhere. macOS asks once to let Notcholino control Mail.")
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        mail.add(draft)
        draft = ""
    }
}

private struct KeyRow: View {
    let provider: NotchyProvider
    let saved: Bool
    let changed: () async -> Void
    @State private var key = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(provider.name)
                Text(saved ? "Key saved" : "No key").font(.caption).foregroundStyle(saved ? Color.green : Color.secondary)
            }
            Spacer()
            SecureField(provider.keyHint, text: $key)
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)
            Button(saved ? "Replace" : "Save") {
                let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return }
                Task { await NotchyKeychain.save(value, for: provider.id); key = ""; await changed() }
            }
            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            if saved {
                Button("Remove", role: .destructive) { Task { await NotchyKeychain.remove(provider.id); await changed() } }
            }
        }
    }
}

/// Model choice: the models that make sense for this task first, a Refresh button that asks the provider what it really has,
/// and a field for anything else (a model of your own, a newer name).
private struct ModelRow: View {
    @ObservedObject private var settings = NotchySettings.shared
    let provider: NotchyProvider
    let task: NotchyTask
    @State private var fetched: [String] = []
    @State private var loading = false
    @State private var note: String?
    @State private var typing = false

    private static let other = "\u{0}other"

    private var options: [String] {
        var all = provider.models(for: task)
        for m in fetched where !all.contains(m) { all.append(m) }
        return all
    }

    var body: some View {
        let current = settings.model(for: provider, task: task)
        let known = options.contains(current)
        HStack {
            if options.isEmpty || typing || (!known && !current.isEmpty) {
                TextField("Model", text: Binding(get: { current }, set: { settings.setModel($0, for: provider, task: task) }))
                    .textFieldStyle(.roundedBorder)
                if !options.isEmpty {
                    Button("List") { typing = false; settings.setModel("", for: provider, task: task) }
                }
            } else {
                Picker("Model", selection: Binding(get: { current }, set: {
                    if $0 == Self.other { typing = true } else { settings.setModel($0, for: provider, task: task) }
                })) {
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                    Divider()
                    Text("Other…").tag(Self.other)
                }
            }
            if provider.listsModels {
                Button {
                    loading = true; note = nil
                    Task {
                        do {
                            fetched = try await NotchyClient.listModels(provider: provider, task: task)
                            note = fetched.isEmpty ? "The provider returned no models for this." : "\(fetched.count) models found."
                        } catch { note = error.localizedDescription }
                        loading = false
                    }
                } label: {
                    Image(systemName: loading ? "hourglass" : "arrow.clockwise")
                }
                .help("Ask \(provider.name) which models it has")
                .disabled(loading)
            }
        }
        if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
    }
}

/// "Test": one tiny request for the task, so the user knows the key, the address and the model work
private struct TestRow: View {
    let provider: NotchyProvider
    let task: NotchyTask
    @State private var result: String?
    @State private var good = false
    @State private var running = false

    var body: some View {
        HStack {
            Button(running ? "Testing…" : "Test \(task == .text ? "text" : task == .vision ? "images" : "voice")") {
                running = true; result = nil
                Task {
                    do {
                        switch task {
                        case .text:
                            let a = try await NotchyClient.complete(prompt: "Answer with the single word: ready", system: "Be brief.", task: .text)
                            good = true; result = "Works: “\(a.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))”"
                        case .vision:
                            let a = try await NotchyClient.complete(prompt: "What colour is this image? Answer with one word.", system: "Be brief.",
                                                                    task: .vision, image: NotchyClient.testImage())
                            good = a.lowercased().contains("red")
                            result = good ? "It can see images: “\(a.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))”"
                                          : "Answered, but did not see the image: “\(a.prefix(40))”"
                        case .speech:
                            let list = try await NotchyClient.listModels(provider: provider, task: .speech)
                            let model = NotchySettings.shared.model(for: provider, task: .speech)
                            good = list.isEmpty || list.contains(model)
                            result = good ? "Key and model look right. Voice itself is tested when the shortcut arrives."
                                          : "The key works but “\(model)” is not in the provider's list."
                        }
                    } catch {
                        good = false; result = error.localizedDescription
                    }
                    running = false
                }
            }
            .disabled(running)
            if let result {
                Text(result).font(.caption).foregroundStyle(good ? Color.green : Color.orange).lineLimit(3)
            }
        }
    }
}

