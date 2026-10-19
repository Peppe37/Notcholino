// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

// MARK: - The page in the notch

/// Notchy's page in the notch: it is here, resting. Tap it to pet it. (Files, questions and the day come in the next steps.)
struct NotchyNotchView: View {
    @ObservedObject private var presence = NotchyPresence.shared
    @ObservedObject private var settings = NotchySettings.shared
    @State private var mood: NotchyMood = .calm
    @State private var gaze: CGFloat = 0
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 22) {
            NotchyCube(mood: mood, size: 78, gaze: gaze)
                .onTapGesture { pet() }
            VStack(alignment: .leading, spacing: 4) {
                Text("Notchy").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                Text(status).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var status: String {
        guard let id = settings.providerID(for: .text), let p = NotchyProvider.provider(id) else {
            return "Choose a provider in Settings → Notchy to ask it things."
        }
        return "Ready · text with \(p.name)"
    }

    private func pet() {
        resetTask?.cancel()
        mood = .happy
        gaze = 0
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            mood = .calm
        }
    }
}

// MARK: - Settings

struct NotchySettingsView: View {
    @ObservedObject private var settings = NotchySettings.shared
    @State private var savedKeys: Set<String> = []

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    NotchyCube(mood: settings.enabled ? .calm : .sleepy, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Notchy", isOn: $settings.enabled)
                            .font(.headline)
                        Text("A small glass cube that lives in the notch. It helps with files and the day when you ask, and keeps you company without getting in the way.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if settings.enabled {
                Section {
                    Picker("How lively", selection: $settings.level) {
                        ForEach(NotchyLevel.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Show its page in the notch", isOn: $settings.pageVisible)
                } footer: {
                    Text(settings.level.detail)
                }
            }

            ForEach(NotchyTask.allCases) { task in
                taskSection(task)
            }

            Section {
                ForEach(NotchyProvider.all.filter(\.needsKey)) { provider in
                    KeyRow(provider: provider, saved: savedKeys.contains(provider.id)) { await refreshKeys() }
                }
            } header: {
                Text("Keys")
            } footer: {
                Text("Keys are kept in the macOS Keychain, one for each provider, and are only sent to that provider. Notchy never reads them in the background.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Notchy")
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
                if provider.kind == .openAICompatible {
                    TextField("Address", text: Binding(get: { settings.baseURL(for: provider) },
                                                       set: { settings.setBaseURL($0, for: provider) }))
                        .textFieldStyle(.roundedBorder)
                }
                TextField("Model", text: Binding(get: { settings.model(for: provider, task: task) },
                                                 set: { settings.setModel($0, for: provider, task: task) }))
                    .textFieldStyle(.roundedBorder)
                if task == .text {
                    TestRow(provider: provider)
                }
            }
        } footer: {
            Text(task.detail)
        }
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

/// "Test": one tiny request, so the user knows the key, the address and the model work
private struct TestRow: View {
    let provider: NotchyProvider
    @State private var result: String?
    @State private var good = false
    @State private var running = false

    var body: some View {
        HStack {
            Button(running ? "Testing…" : "Test") {
                running = true; result = nil
                Task {
                    do {
                        let answer = try await NotchyClient.complete(prompt: "Answer with the single word: ready", system: "Be brief.")
                        good = true; result = "Works: “\(answer.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))”"
                    } catch {
                        good = false; result = error.localizedDescription
                    }
                    running = false
                }
            }
            .disabled(running)
            if let result {
                Text(result).font(.caption).foregroundStyle(good ? Color.green : Color.orange).lineLimit(2)
            }
        }
    }
}
