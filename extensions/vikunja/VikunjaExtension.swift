// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

@objc(VikunjaExtension)
final class VikunjaExtension: NSObject, NotcholinoExtension {
    private let model = VikunjaModel()
    var apiVersion: Int { notcholinoExtensionAPIVersion }
    var extensionIdentifier: String { "vikunja" }
    var extensionName: String { "Vikunja" }
    var extensionVersion: String { Bundle(for: VikunjaExtension.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    var extensionAuthor: String { "Giuseppe" }
    var extensionDescription: String { "See your Vikunja Kanban boards and move or add tasks from the notch." }
    var extensionSymbol: String { "rectangle.split.3x1" }

    func makePageView() -> NSView {
        let view = NSHostingView(rootView: VikunjaPage(model: model))
        view.sizingOptions = []
        return view
    }

    func makeSettingsView() -> NSView {
        let view = NSHostingView(rootView: VikunjaSettings(model: model))
        view.sizingOptions = []
        return view
    }

    func extensionDidEnable() { model.enable() }
    func extensionWillUnload() { model.disable() }
}

/// Used on the main thread by the extension host and its two views.
final class VikunjaModel: ObservableObject {
    @Published private(set) var connection: VikunjaConnection?
    @Published private(set) var boards: [VikunjaBoard] = []
    @Published private(set) var selected: VikunjaBoard?
    @Published private(set) var buckets: [VikunjaBucket] = []
    @Published private(set) var busy = false
    @Published private(set) var problem: String?
    @Published private(set) var notice: String?
    private var work: Task<Void, Never>?
    private var enabled = false

    func enable() {
        guard !enabled else { return }
        enabled = true
        run {
            let saved = try await Task.detached { try VikunjaKeychain.load() }.value
            try Task.checkCancellation()
            self.connection = saved
        }
    }

    func disable() {
        enabled = false
        work?.cancel()
        work = nil
        busy = false
        problem = nil
        notice = nil
        clear()
    }

    func connect(address: String, token: String) {
        run {
            let next = try VikunjaConnection.make(address: address, token: token)
            let client = VikunjaClient(connection: next)
            let boards = try await client.boards()
            let first = if let board = boards.first { try await client.buckets(board) } else { [VikunjaBucket]() }
            try Task.checkCancellation()
            try VikunjaKeychain.save(next)
            self.connection = next
            self.boards = boards
            self.selected = boards.first
            self.buckets = first
            self.notice = "Connection saved."
        }
    }

    func disconnect() {
        run {
            try VikunjaKeychain.remove()
            self.clear()
        }
    }

    func refresh() {
        guard let connection else { return }
        run {
            let client = VikunjaClient(connection: connection)
            let boards = try await client.boards()
            let selected = boards.first { $0.id == self.selected?.id } ?? boards.first
            let buckets = if let selected { try await client.buckets(selected) } else { [VikunjaBucket]() }
            try Task.checkCancellation()
            self.boards = boards
            self.selected = selected
            self.buckets = buckets
        }
    }

    func select(_ id: Int) {
        guard let connection, let board = boards.first(where: { $0.id == id }), board != selected else { return }
        run {
            let buckets = try await VikunjaClient(connection: connection).buckets(board)
            try Task.checkCancellation()
            self.selected = board
            self.buckets = buckets
        }
    }

    func move(_ task: VikunjaTask, to bucket: VikunjaBucket) {
        guard selected?.canMove == true else { return }
        mutate(success: "Task moved.") { client, board in
            try await client.move(task, to: bucket, on: board)
        }
    }

    func add(_ input: String) {
        let title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        mutate(success: "Task added to the project.") { client, board in
            try await client.add(title, on: board)
        }
    }

    private func mutate(success: String, _ change: @escaping (VikunjaClient, VikunjaBoard) async throws -> Void) {
        guard let connection, let selected else { return }
        run {
            let client = VikunjaClient(connection: connection)
            try await change(client, selected)
            self.notice = success
            do {
                let buckets = try await client.buckets(selected)
                try Task.checkCancellation()
                self.buckets = buckets
            } catch {
                try Task.checkCancellation()
                self.problem = "\(success) Refresh to see the updated board."
            }
        }
    }

    private func clear() {
        connection = nil
        boards = []
        selected = nil
        buckets = []
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard enabled, !busy else { return }
        busy = true
        problem = nil
        notice = nil
        work = Task { @MainActor in
            do { try await operation() }
            catch { if !Task.isCancelled { self.problem = error.localizedDescription } }
            if !Task.isCancelled {
                self.busy = false
                self.work = nil
            }
        }
    }
}
