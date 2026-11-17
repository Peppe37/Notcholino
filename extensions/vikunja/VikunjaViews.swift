// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct VikunjaSettings: View {
    @ObservedObject var model: VikunjaModel
    @State private var address = ""
    @State private var token = ""
    @State private var useAccess = false
    @State private var clientID = ""
    @State private var clientSecret = ""

    var body: some View {
        Form {
            Section("Vikunja connection") {
                TextField("Instance URL", text: $address, prompt: Text("https://app.vikunja.cloud"))
                    .textContentType(.URL)
                SecureField("API token", text: $token, prompt: Text("Paste a Vikunja API token"))
                Link("Create a token in Vikunja", destination: URL(string: "https://vikunja.io/help/settings/#api-tokens")!)
                Text("Use your hosted or self-hosted HTTPS URL. Allow listing projects and project view tasks. To edit the board, also allow creating tasks and moving tasks between buckets.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Connect through Cloudflare Access", isOn: $useAccess)
                if useAccess {
                    TextField("Access Client ID", text: $clientID)
                    SecureField("Access Client Secret", text: $clientSecret)
                    Link("Configure a Cloudflare service token", destination: URL(string:
                        "https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/service-tokens/")!)
                }
                HStack {
                    Button("Test and save") {
                        let access = useAccess ? VikunjaConnection.CloudflareAccess(clientID: clientID, clientSecret: clientSecret) : nil
                        model.connect(address: address, token: token, access: access)
                    }
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || token.isEmpty || (useAccess && (clientID.isEmpty || clientSecret.isEmpty)))
                    if model.connection != nil {
                        Button("Disconnect") { model.disconnect() }
                    }
                    if model.busy { ProgressView().controlSize(.small) }
                }
                .disabled(model.busy)
                if let problem = model.problem {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red).font(.callout)
                } else if let saved = model.connection {
                    Label("Connected to \(saved.site.absoluteString). Credentials saved in Keychain.", systemImage: "checkmark.shield")
                        .font(.callout).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { showSavedConnection() }
        .onChange(of: model.connection) { _, _ in showSavedConnection() }
        .onChange(of: model.notice) { _, notice in
            if notice == "Connection saved." { showSavedConnection() }
        }
    }

    private func showSavedConnection() {
        let saved = model.connection
        address = saved?.site.absoluteString ?? ""
        useAccess = saved?.access != nil
        clientID = saved?.access?.clientID ?? ""
        clientSecret = ""
        token = ""
    }
}

struct VikunjaPage: View {
    @ObservedObject var model: VikunjaModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.circle").font(.caption)
                    .foregroundStyle(.yellow).lineLimit(2)
            }
            if model.connection == nil {
                message(model.busy ? "Opening connection…" : "Connect in Settings → Extensions → Vikunja.")
            } else if model.selected == nil {
                message(model.busy ? "Loading boards…" : "No Kanban boards found. Add a Kanban view in Vikunja.")
            } else if model.buckets.isEmpty {
                message(model.busy ? "Loading board…" : "This board has no columns.")
            } else {
                columns
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .task(id: model.connection?.site) {
            if model.selected == nil && model.notice == nil { model.refresh() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Vikunja", systemImage: "rectangle.split.3x1").font(.subheadline.weight(.semibold))
            if !model.boards.isEmpty {
                Picker("Kanban board", selection: Binding(get: { model.selected?.id ?? 0 }, set: model.select)) {
                    ForEach(model.boards) { board in Text(board.title).tag(board.id) }
                }
                .labelsHidden().controlSize(.small).frame(maxWidth: 235)
                .disabled(model.busy)
            }
            Spacer(minLength: 0)
            if model.busy {
                ProgressView().controlSize(.small).accessibilityLabel("Contacting Vikunja")
            } else if let notice = model.notice, model.problem == nil, model.selected != nil {
                Text(notice).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            if model.connection != nil {
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise").accessibilityLabel("Refresh board")
                }
                .help("Refresh board").disabled(model.busy)
            }
            if let board = model.selected, let site = model.connection?.site {
                Button(action: askForTitle) {
                    Image(systemName: "plus").accessibilityLabel("Add task")
                }
                .help("Add task").disabled(model.busy)
                Link(destination: site.appendingPathComponent("projects/\(board.project)/\(board.id)")) {
                    Image(systemName: "arrow.up.right.square").accessibilityLabel("Open board in Vikunja")
                }
                .help("Open board in Vikunja")
            }
        }
        .buttonStyle(.borderless)
        .frame(height: 22)
    }

    private var columns: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 7) {
                ForEach(model.buckets) { bucket in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(bucket.title).font(.caption.weight(.semibold)).lineLimit(1)
                            Spacer(minLength: 0)
                            Text((bucket.tasks ?? []).count, format: .number)
                                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                ForEach(bucket.tasks ?? []) { task in card(task, in: bucket) }
                                if (bucket.tasks ?? []).isEmpty {
                                    Text("No tasks").font(.caption2).foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .scrollIndicators(.visible)
                    }
                    .padding(7).frame(width: 140)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.bottom, 4)
        }
        .scrollIndicators(.visible)
        .id(model.selected?.id)
    }

    private func card(_ task: VikunjaTask, in bucket: VikunjaBucket) -> some View {
        HStack(spacing: 3) {
            if let site = model.connection?.site {
                Link(destination: site.appendingPathComponent("tasks/\(task.id)")) {
                    Text(task.title)
                        .strikethrough(task.done)
                        .font(.caption2).lineLimit(2).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.help(task.title)
            }
            if model.selected?.canMove == true && model.buckets.count > 1 {
                Menu {
                    ForEach(model.buckets.filter { $0.id != bucket.id }) { target in
                        Button(target.title) { model.move(task, to: target) }
                    }
                } label: {
                    Image(systemName: "ellipsis").accessibilityLabel("Move \(task.title)")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .fixedSize().disabled(model.busy)
                .help("Move to another column")
            }
        }
        .padding(.horizontal, 5).padding(.vertical, 4)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func askForTitle() {
        // The notch folds when the pointer leaves it. Keep the editor in its own window.
        let alert = NSAlert()
        alert.messageText = "Add a Vikunja task"
        alert.informativeText = "Vikunja places the task in the project's default column."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let title = NSTextField(frame: CGRect(x: 0, y: 0, width: 300, height: 24))
        title.placeholderString = "Task title"
        title.setAccessibilityLabel("Task title")
        alert.accessoryView = title
        alert.window.initialFirstResponder = title
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { model.add(title.stringValue) }
    }
}
