// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// One file on the shelf. The shelf keeps its own copy, so the original can be moved or deleted.
struct ShelfItem: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let added: Date
}

/// The shelf: files dropped on the notch wait here until they are dragged out again (or removed).
/// Nothing lands on the Desktop. Files live in Application Support, and how long they stay is a setting.
final class ShelfManager: ObservableObject {
    static let shared = ShelfManager()

    @Published private(set) var items: [ShelfItem] = []
    /// Files being copied in right now
    @Published private(set) var pending = 0
    /// True while something is being dragged over the notch, so the shelf can open to receive it
    @Published var dragActive = false
    /// True while a file is being dragged out of the shelf: the notch must stay open until it lands
    @Published var draggingOut = false
    @Published private(set) var thumbnails: [UUID: NSImage] = [:]

    enum Retention: Int { case never = 0, day = 1, restart = 2 }

    private let folder: URL
    private let indexURL: URL
    private let queue = DispatchQueue(label: "com.giuseppe.Notcholino.shelf", qos: .userInitiated)
    private var pruneTimer: Timer?

    var retention: Retention { Retention(rawValue: UserDefaults.standard.integer(forKey: "shelfRetention")) ?? .never }
    var isEnabled: Bool { UserDefaults.standard.object(forKey: "shelfEnabled") as? Bool ?? true }

    init(folder: URL? = nil) {
        let base = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notcholino/Shelf")
        self.folder = base
        indexURL = base.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        load()
        // "At restart" also covers a restart of the Mac: the app starts again then, and the shelf is emptied at start
        if retention == .restart { removeAll() }
        prune()
        let t = Timer(timeInterval: 900, repeats: true) { [weak self] _ in self?.prune() }
        t.tolerance = 300
        RunLoop.main.add(t, forMode: .common)
        pruneTimer = t
    }

    func url(for item: ShelfItem) -> URL {
        folder.appendingPathComponent(item.id.uuidString).appendingPathComponent(item.name)
    }

    // MARK: Adding

    /// Copies a file onto the shelf (an instant clone on APFS, even for a big video)
    func add(fileURL: URL) {
        guard fileURL.isFileURL else { return }
        pending += 1
        queue.async {
            let id = UUID()
            let dir = self.folder.appendingPathComponent(id.uuidString)
            let target = dir.appendingPathComponent(fileURL.lastPathComponent)
            var ok = false
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: fileURL, to: target)
                ok = true
            } catch {
                try? FileManager.default.removeItem(at: dir)
            }
            DispatchQueue.main.async {
                self.pending -= 1
                guard ok else { return }
                self.items.append(ShelfItem(id: id, name: fileURL.lastPathComponent, added: Date()))
                self.save()
            }
        }
    }

    /// An image dragged from a web page or another app, with no file behind it
    func add(imageData: Data, suggestedName: String = "Image") {
        pending += 1
        queue.async {
            let id = UUID()
            let name = "\(suggestedName) \(Self.stamp()).png"
            let dir = self.folder.appendingPathComponent(id.uuidString)
            var ok = false
            if let image = NSImage(data: imageData), let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                ok = (try? png.write(to: dir.appendingPathComponent(name))) != nil
            }
            DispatchQueue.main.async {
                self.pending -= 1
                guard ok else { return }
                self.items.append(ShelfItem(id: id, name: name, added: Date()))
                self.save()
            }
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"; return f.string(from: Date())
    }

    // MARK: Removing

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        thumbnails[item.id] = nil
        let dir = folder.appendingPathComponent(item.id.uuidString)
        queue.async { try? FileManager.default.removeItem(at: dir) }
        save()
    }

    func removeAll() {
        let old = items
        items = []
        thumbnails = [:]
        queue.async { old.forEach { try? FileManager.default.removeItem(at: self.folder.appendingPathComponent($0.id.uuidString)) } }
        save()
    }

    /// Applies the "keep for" setting
    func prune() {
        guard retention == .day else { return }
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        items.filter { $0.added < cutoff }.forEach(remove)
    }

    // MARK: Thumbnails

    func loadThumbnail(for item: ShelfItem) {
        guard thumbnails[item.id] == nil else { return }
        let request = QLThumbnailGenerator.Request(fileAt: url(for: item), size: CGSize(width: 120, height: 120),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                   representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            let image = rep?.nsImage ?? NSWorkspace.shared.icon(forFile: self.url(for: item).path)
            DispatchQueue.main.async { self.thumbnails[item.id] = image }
        }
    }

    // MARK: Saving

    private func load() {
        guard let data = try? Data(contentsOf: indexURL), let saved = try? JSONDecoder().decode([ShelfItem].self, from: data) else { return }
        // Only what is still on disk
        items = saved.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
        // Folders without an entry (a crash in the middle of a copy) are removed
        let known = Set(items.map { $0.id.uuidString })
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in leftovers where name != "index.json" && !known.contains(name) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    /// Size on disk, for the settings page
    var totalSizeText: String {
        var bytes: Int64 = 0
        if let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) {
            for case let u as URL in e { bytes += Int64((try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0) }
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
