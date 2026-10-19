// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

/// Loads extensions written by other developers. They are compiled bundles that run inside Notcholino with its permissions, so
/// nothing is loaded unless the user turns on **developer mode**, and only from one folder on their own Mac: there is no download,
/// no store and no automatic install for them. (Official extensions are part of the app.) Keys never reach an extension: asking
/// Notchy's AI goes through the app, and only for an extension the user allowed.
final class ExtensionManager: ObservableObject {
    static let shared = ExtensionManager()

    @Published var developerMode: Bool {
        didSet {
            UserDefaults.standard.set(developerMode, forKey: "extensionsDeveloperMode")
            if developerMode { loadAll() } else { loaded.forEach { $0.extensionWillUnload?() } }
        }
    }
    @Published private(set) var loaded: [NotcholinoExtension] = []
    @Published private(set) var errors: [String] = []
    @Published private(set) var enabledIDs: Set<String>
    @Published private(set) var aiAllowedIDs: Set<String>
    @Published var selectedID: String?

    let directory: URL
    private var seen = Set<String>()

    init() {
        let d = UserDefaults.standard
        developerMode = d.bool(forKey: "extensionsDeveloperMode")
        enabledIDs = Set(d.stringArray(forKey: "extensionsEnabled") ?? [])
        aiAllowedIDs = Set(d.stringArray(forKey: "extensionsAIAllowed") ?? [])
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Notcholino/Extensions")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if developerMode { loadAll() }
    }

    /// The extensions that have a page in the notch right now
    var pages: [NotcholinoExtension] { developerMode ? loaded.filter { enabledIDs.contains($0.extensionIdentifier) } : [] }

    func isEnabled(_ id: String) -> Bool { enabledIDs.contains(id) }
    func setEnabled(_ on: Bool, _ id: String) {
        if on { enabledIDs.insert(id) } else { enabledIDs.remove(id) }
        UserDefaults.standard.set(Array(enabledIDs), forKey: "extensionsEnabled")
        if !on { loaded.first { $0.extensionIdentifier == id }?.extensionWillUnload?() }
    }

    func isAIAllowed(_ id: String) -> Bool { aiAllowedIDs.contains(id) }
    func setAIAllowed(_ on: Bool, _ id: String) {
        if on { aiAllowedIDs.insert(id) } else { aiAllowedIDs.remove(id) }
        UserDefaults.standard.set(Array(aiAllowedIDs), forKey: "extensionsAIAllowed")
    }

    func loadAll() {
        guard developerMode, let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in urls where url.pathExtension == "bundle" && !seen.contains(url.path) {
            seen.insert(url.path)
            load(url)
        }
    }

    private func load(_ url: URL) {
        guard let bundle = Bundle(url: url), bundle.load(),
              let cls = bundle.principalClass as? NSObject.Type,
              let ext = cls.init() as? NotcholinoExtension else {
            errors.append("\(url.lastPathComponent): not an extension (no NotcholinoExtension principal class)"); return
        }
        guard ext.apiVersion == notcholinoExtensionAPIVersion else {
            errors.append("\(ext.extensionName): needs extension API \(ext.apiVersion), this app has \(notcholinoExtensionAPIVersion)"); return
        }
        guard !loaded.contains(where: { $0.extensionIdentifier == ext.extensionIdentifier }) else {
            errors.append("\(ext.extensionName): already loaded"); return
        }
        let id = ext.extensionIdentifier
        ext.setPopupHandler? { PopupCenter.shared.show(from: $0) }
        ext.setAskHandler? { [weak self] prompt, system, completion in
            DispatchQueue.main.async {
                guard self?.isAIAllowed(id) == true else {
                    completion(nil, "The user has not allowed this extension to use Notchy's AI."); return
                }
                guard NotchySettings.shared.enabled else { completion(nil, "Notchy is switched off."); return }
                Task { @MainActor in
                    do { completion(try await NotchyClient.complete(prompt: prompt, system: system, task: .text), nil) }
                    catch { completion(nil, error.localizedDescription) }
                }
            }
        }
        loaded.append(ext)
        if selectedID == nil { selectedID = id }
    }

    func willQuit() { loaded.forEach { $0.extensionWillUnload?() } }
}

/// Hosts an extension's own NSView inside SwiftUI
struct ExtensionViewHost: NSViewRepresentable {
    let make: () -> NSView
    func makeNSView(context: Context) -> NSView { make() }
    func updateNSView(_ view: NSView, context: Context) {}
}

/// The notch page that shows the extension the user picked
struct ExtensionNotchView: View {
    @ObservedObject private var manager = ExtensionManager.shared

    var body: some View {
        let pages = manager.pages
        let current = pages.first { $0.extensionIdentifier == manager.selectedID } ?? pages.first
        VStack(spacing: 6) {
            if pages.count > 1 {
                HStack(spacing: 6) {
                    ForEach(pages, id: \.extensionIdentifier) { ext in
                        Button { manager.selectedID = ext.extensionIdentifier } label: {
                            Label(ext.extensionName, systemImage: ext.extensionSymbol).font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(.white.opacity(ext.extensionIdentifier == current?.extensionIdentifier ? 0.22 : 0.08)))
                                .foregroundStyle(.white)
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 28)
            }
            if let current {
                ExtensionViewHost { current.makePageView() }
                    .id(current.extensionIdentifier)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, 6)
    }
}

/// The developer part of the Extensions shelf: the switch, the folder, and what was loaded from it
struct DeveloperExtensionsView: View {
    @ObservedObject private var manager = ExtensionManager.shared
    @State private var settingsFor: NotcholinoExtension?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $manager.developerMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Developer mode").font(.headline)
                    Text("Load extensions you built yourself from a folder on this Mac.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if manager.developerMode {
                Label("An extension is code that runs inside Notcholino with its permissions. Only load ones you built or trust. After turning this off, restart Notcholino to unload them.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                HStack {
                    Button("Open the folder") { NSWorkspace.shared.open(manager.directory) }
                    Button("Look again") { manager.loadAll() }
                    Text("Build one with scripts/dev-extension.sh. See extensions/GUIDE.md in the repository.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(manager.loaded, id: \.extensionIdentifier) { ext in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: ext.extensionSymbol).font(.title3).frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.18)))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(ext.extensionName).font(.headline)
                                Text("v\(ext.extensionVersion) · \(ext.extensionAuthor)").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(ext.extensionDescription).font(.callout).foregroundStyle(.secondary)
                            Toggle("Allow it to use Notchy's AI (never sees your keys)", isOn: Binding(
                                get: { manager.isAIAllowed(ext.extensionIdentifier) },
                                set: { manager.setAIAllowed($0, ext.extensionIdentifier) }))
                                .font(.caption)
                            if ext.responds(to: Selector(("makeSettingsView"))) {
                                Button("Settings") { settingsFor = ext }.controlSize(.small)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { manager.isEnabled(ext.extensionIdentifier) },
                                                 set: { manager.setEnabled($0, ext.extensionIdentifier) })).labelsHidden()
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.secondary.opacity(0.1)))
                }
                ForEach(manager.errors, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                if manager.loaded.isEmpty && manager.errors.isEmpty {
                    Text("Nothing in the folder yet.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .sheet(item: Binding(get: { settingsFor.map { ExtensionBox(ext: $0) } }, set: { if $0 == nil { settingsFor = nil } })) { box in
            VStack(spacing: 12) {
                Text(box.ext.extensionName).font(.headline)
                ExtensionViewHost { box.ext.makeSettingsView?() ?? NSView() }.frame(minWidth: 380, minHeight: 120)
                Button("Done") { settingsFor = nil }
            }
            .padding(20)
        }
    }
}

private struct ExtensionBox: Identifiable {
    let ext: NotcholinoExtension
    var id: String { ext.extensionIdentifier }
}
