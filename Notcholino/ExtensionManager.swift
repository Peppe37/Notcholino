// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import CryptoKit
import SwiftUI

/// Loads extensions. They are compiled bundles that run inside Notcholino with its permissions, so there are only two ways in:
/// - the **store**: built by the project's own pipeline from source that was reviewed on GitHub, downloaded from the project's
///   releases and checked against a published SHA-256. What was installed is hashed and checked again every time it is loaded.
/// - **developer mode**, which the user switches on by hand: bundles from one folder on their own Mac.
/// Keys never reach an extension: asking Notchy's AI goes through the app, and only for an extension the user allowed.
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
    /// Where the store puts what it installs (never loaded from by developer mode, and the other way round)
    let storeDirectory: URL
    private var seen = Set<String>()
    private var registry: [String: StoreRecord] = [:]
    @Published private(set) var storeIDs: Set<String> = []

    private struct StoreRecord: Codable { var version: String; var hash: String }
    private var registryURL: URL { storeDirectory.appendingPathComponent("registry.json") }

    init() {
        let d = UserDefaults.standard
        developerMode = d.bool(forKey: "extensionsDeveloperMode")
        enabledIDs = Set(d.stringArray(forKey: "extensionsEnabled") ?? [])
        aiAllowedIDs = Set(d.stringArray(forKey: "extensionsAIAllowed") ?? [])
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Notcholino/Extensions")
        storeDirectory = directory.appendingPathComponent("Store")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: registryURL), let r = try? JSONDecoder().decode([String: StoreRecord].self, from: data) { registry = r }
        loadStoreExtensions()
        if developerMode { loadAll() }
    }

    // MARK: From the store

    /// The version on disk (after an update this is the new one even before the restart that runs it)
    func installedVersion(of id: String) -> String? { registry[id]?.version }

    /// SHA-256 over every file of a bundle, in a fixed order, with its path: any change to the installed code changes it
    private func contentHash(of bundle: URL) -> String? {
        guard let walker = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: [.isRegularFileKey]) else { return nil }
        var files: [URL] = []
        for case let url as URL in walker where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { files.append(url) }
        var hasher = SHA256()
        let base = bundle.standardizedFileURL.path
        for file in files.sorted(by: { $0.path < $1.path }) {
            hasher.update(data: Data(String(file.standardizedFileURL.path.dropFirst(base.count)).utf8))
            guard let data = try? Data(contentsOf: file) else { return nil }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func installFromStore(_ unpacked: URL, id: String, version: String) throws {
        let dest = storeDirectory.appendingPathComponent("\(id).bundle")
        if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.moveItem(at: unpacked, to: dest)
        guard let hash = contentHash(of: dest) else { throw NSError(domain: "Notcholino", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read the installed extension."]) }
        let firstTime = registry[id] == nil
        registry[id] = StoreRecord(version: version, hash: hash)
        if let data = try? JSONEncoder().encode(registry) { try? data.write(to: registryURL) }
        storeIDs.insert(id)
        if firstTime { setEnabled(true, id) }
        if !loaded.contains(where: { $0.extensionIdentifier == id }) {
            guard load(dest) else {
                removeStoreExtension(id)
                throw NSError(domain: "Notcholino", code: 2, userInfo: [NSLocalizedDescriptionKey: "That extension is not compatible with this version of Notcholino."])
            }
        }
    }

    func removeStoreExtension(_ id: String) {
        loaded.first { $0.extensionIdentifier == id }?.extensionWillUnload?()
        loaded.removeAll { $0.extensionIdentifier == id }       // the code stays in memory until a restart, but it has no page and no settings
        try? FileManager.default.removeItem(at: storeDirectory.appendingPathComponent("\(id).bundle"))
        registry[id] = nil
        storeIDs.remove(id)
        setEnabled(false, id)
        if let data = try? JSONEncoder().encode(registry) { try? data.write(to: registryURL) }
    }

    private func loadStoreExtensions() {
        for (id, record) in registry {
            let url = storeDirectory.appendingPathComponent("\(id).bundle")
            guard FileManager.default.fileExists(atPath: url.path) else { registry[id] = nil; continue }
            guard contentHash(of: url) == record.hash else {
                errors.append("\(id): the installed files were changed since the store put them there, so it was not loaded. Remove it and install it again.")
                continue
            }
            storeIDs.insert(id)
            _ = load(url)
        }
    }

    /// The extensions that have a page in the notch right now
    var pages: [NotcholinoExtension] {
        loaded.filter { enabledIDs.contains($0.extensionIdentifier) && (storeIDs.contains($0.extensionIdentifier) || developerMode) }
    }

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

    @discardableResult
    private func load(_ url: URL) -> Bool {
        guard let bundle = Bundle(url: url), bundle.load(),
              let cls = bundle.principalClass as? NSObject.Type,
              let ext = cls.init() as? NotcholinoExtension else {
            errors.append("\(url.lastPathComponent): not an extension (no NotcholinoExtension principal class)"); return false
        }
        guard ext.apiVersion == notcholinoExtensionAPIVersion else {
            errors.append("\(ext.extensionName): needs extension API \(ext.apiVersion), this app has \(notcholinoExtensionAPIVersion)"); return false
        }
        guard !loaded.contains(where: { $0.extensionIdentifier == ext.extensionIdentifier }) else {
            errors.append("\(ext.extensionName): already loaded"); return false
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
        return true
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
                ForEach(manager.loaded.filter { !manager.storeIDs.contains($0.extensionIdentifier) }, id: \.extensionIdentifier) { ext in
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

/// What an installed extension from the store offers: on/off, its AI permission, its settings, and removal
struct ExtensionManageView: View {
    let id: String
    @ObservedObject private var manager = ExtensionManager.shared
    @State private var showSettings = false

    var body: some View {
        if let ext = manager.loaded.first(where: { $0.extensionIdentifier == id }) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Show its page in the notch", isOn: Binding(get: { manager.isEnabled(id) }, set: { manager.setEnabled($0, id) }))
                Toggle("Allow it to use Notchy's AI (it never sees your keys)", isOn: Binding(get: { manager.isAIAllowed(id) }, set: { manager.setAIAllowed($0, id) }))
                HStack {
                    if ext.responds(to: Selector(("makeSettingsView"))) { Button("Settings") { showSettings = true } }
                    Button("Remove", role: .destructive) { PluginStore.shared.remove(identifier: id) }
                }
            }
            .sheet(isPresented: $showSettings) {
                VStack(spacing: 12) {
                    Text(ext.extensionName).font(.headline)
                    ExtensionViewHost { ext.makeSettingsView?() ?? NSView() }.frame(minWidth: 380, minHeight: 120)
                    Button("Done") { showSettings = false }
                }
                .padding(20)
            }
        } else if manager.installedVersion(of: id) != nil {
            Text("Installed. Restart Notcholino to use it.").foregroundStyle(.secondary)
        }
    }
}
