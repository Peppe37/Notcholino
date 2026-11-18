// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct ControlCenterSettingsView: View {
    @AppStorage("controlCenterEnabled") private var controlCenterEnabled = true
    @ObservedObject private var manager = PluginManager.shared
    @ObservedObject private var shortcuts = PluginShortcuts.shared
    @State private var selectedID: String?

    private var ids: [String] { manager.loadedPlugins.map(\.pluginIdentifier) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Show Control Center in the notch", isOn: $controlCenterEnabled)
                    .help("Configured shortcuts still work when the Control Center is hidden.")
                Spacer()
                Button {
                    NotificationCenter.default.post(name: .openPluginStore, object: nil)
                } label: {
                    Label("Plugin Store", systemImage: "bag")
                }
            }
            .padding(14)
            Divider()

            if ids.isEmpty {
                ContentUnavailableView("No plugins installed", systemImage: "puzzlepiece.extension",
                                       description: Text("Browse the Plugin Store to add plugins to your notch."))
            } else {
                HStack(spacing: 0) {
                    List(selection: $selectedID) {
                        Section("Installed Plugins") {
                            ForEach(manager.loadedPlugins, id: \.pluginIdentifier) { plugin in
                                HStack(spacing: 8) {
                                    Image(systemName: plugin.controlCenterIcon.isEmpty ? "puzzlepiece.extension" : plugin.controlCenterIcon)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(plugin.pluginName).lineLimit(1)
                                        if let key = shortcuts.key(for: plugin.pluginIdentifier) {
                                            Text(key.label).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 3)
                                .tag(plugin.pluginIdentifier)
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .frame(width: 158)
                    Divider()
                    if let plugin = manager.loadedPlugins.first(where: { $0.pluginIdentifier == selectedID }) {
                        InstalledPluginDetail(plugin: plugin).id(plugin.pluginIdentifier)
                    }
                }
            }

            if !manager.loadErrors.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(manager.loadErrors.enumerated()), id: \.offset) { _, error in
                            Label(error, systemImage: "exclamationmark.circle").font(.caption)
                        }
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 65)
            }
        }
        .navigationTitle("Control Center")
        .onChange(of: ids, initial: true) { _, ids in
            if !ids.contains(selectedID ?? "") { selectedID = ids.first }
        }
    }
}

private struct InstalledPluginDetail: View {
    let plugin: NotcholinoPlugin
    @ObservedObject private var manager = PluginManager.shared
    @ObservedObject private var shortcuts = PluginShortcuts.shared
    @State private var revision = 0
    @State private var confirmingRemoval = false

    private var id: String { plugin.pluginIdentifier }

    var body: some View {
        let _ = revision
        let options = PluginPreferences.settings(for: plugin)
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: plugin.controlCenterIcon.isEmpty ? "puzzlepiece.extension" : plugin.controlCenterIcon)
                        .font(.title2)
                        .frame(width: 42, height: 42)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plugin.pluginName).font(.title2.weight(.semibold))
                        Text("\(plugin.pluginVersion) · \(plugin.pluginAuthor)").font(.caption).foregroundStyle(.secondary)
                        Text(plugin.pluginDescription).font(.callout).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("How to use") {
                Text(PluginPreferences.guide(for: plugin)).font(.callout)
                Button("Open in the notch") { shortcuts.openPlugin(id) }
            }
            Section("Keyboard shortcut") {
                shortcutControls
            }
            Section("Plugin settings") {
                if plugin.controlCenterHidden != true {
                    Toggle("Show button in Control Center", isOn: Binding(
                        get: { !manager.hiddenButtons.contains(id) },
                        set: { manager.setButtonVisible($0, for: id) }
                    ))
                    if manager.buttonPlugins.contains(where: { $0.pluginIdentifier == id }) {
                        LabeledContent("Button order") {
                            Button { manager.move(identifier: id, by: -1) } label: {
                                Image(systemName: "chevron.up")
                            }.help("Move earlier").accessibilityLabel("Move earlier")
                                .disabled(manager.buttonPlugins.first?.pluginIdentifier == id)
                            Button { manager.move(identifier: id, by: 1) } label: {
                                Image(systemName: "chevron.down")
                            }.help("Move later").accessibilityLabel("Move later")
                                .disabled(manager.buttonPlugins.last?.pluginIdentifier == id)
                        }
                    }
                }
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    setting(option)
                }
                if options.isEmpty && plugin.controlCenterHidden == true {
                    Text("This plugin runs automatically and has no additional options.").font(.callout).foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Remove plugin…", role: .destructive) { confirmingRemoval = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Remove \(plugin.pluginName)?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { PluginStore.shared.remove(identifier: id) }
        } message: {
            Text("This also clears its keyboard shortcut.")
        }
        .onDisappear {
            if shortcuts.recordingID == id { shortcuts.stopRecording() }
        }
    }

    @ViewBuilder private var shortcutControls: some View {
        let actions = PluginShortcutAction.actions(for: plugin)
        let selected = shortcuts.action(for: id)
        let recording = shortcuts.recordingID == id
        if actions.count > 1 {
            Picker("Action", selection: Binding(
                get: { actions.contains { $0.id == selected } ? selected : "open" },
                set: { shortcuts.setAction($0, for: id) }
            )) {
                ForEach(actions) { action in Text(action.title).tag(action.id) }
            }
        }
        LabeledContent("Shortcut") {
            HStack(spacing: 6) {
                Text(shortcuts.key(for: id)?.label ?? "None").font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                if recording {
                    Button("Cancel") { shortcuts.stopRecording() }
                } else {
                    Button(shortcuts.key(for: id) == nil ? "Record…" : "Change…") { shortcuts.record(id) }
                    if shortcuts.key(for: id) != nil {
                        Button { shortcuts.clear(id) } label: { Image(systemName: "xmark.circle") }
                            .help("Clear shortcut").accessibilityLabel("Clear shortcut")
                    }
                }
            }
        }
        if recording {
            Text("Press a key with Control, Option or Command. Esc cancels.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if let error = shortcuts.errors[id] {
            Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder private func setting(_ raw: [String: Any]) -> some View {
        if let label = raw["stepper"] as? String, let key = raw["id"] as? String,
           let value = raw["value"] as? Int, let min = raw["min"] as? Int, let max = raw["max"] as? Int, min <= max {
            let unit = raw["unit"] as? String ?? ""
            Stepper(value: Binding(get: { value }, set: { perform("\(key)=\($0)") }),
                    in: min...max, step: Swift.max(1, raw["step"] as? Int ?? 1)) {
                LabeledContent(label, value: unit.isEmpty ? "\(value)" : "\(value) \(unit)")
            }
        } else if let title = raw["title"] as? String, let key = raw["id"] as? String {
            Button { perform(key) } label: {
                Label(title, systemImage: raw["checked"] as? Bool == true ? "checkmark.circle.fill" : "circle")
            }.buttonStyle(.borderless)
                .accessibilityAddTraits(raw["checked"] as? Bool == true ? .isSelected : [])
        } else if let label = raw["info"] as? String, let value = raw["value"] as? String {
            LabeledContent(label, value: value)
        } else if let header = raw["header"] as? String {
            Text(header).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func perform(_ key: String) {
        plugin.performMenuAction(key)
        revision += 1
    }
}
