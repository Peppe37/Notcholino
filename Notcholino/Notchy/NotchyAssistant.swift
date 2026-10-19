// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import PDFKit
import SwiftUI

/// What Notchy is doing with the last thing it was sent, and what it answered
final class NotchyAssistant: ObservableObject {
    static let shared = NotchyAssistant()

    enum State: Equatable { case idle, thinking(String), reply(String), failed(String) }
    @Published private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    private static let system = """
        You are Notchy, a small, friendly assistant that lives in the Mac's notch. Be concise: at most three short sentences, \
        or a few very short bullets for an outline. No greeting, no preamble, no sign-off. Answer in the language of the text you \
        are given. Plain text only, no Markdown headings.
        """

    /// Text sent from the right-click menu, or from anywhere else
    func send(text: String, name: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let isQuestion = trimmed.count < 400 && trimmed.hasSuffix("?")
        let prompt = isQuestion ? trimmed : "Summarize this in a few short lines. If it is a list or a plan, give the outline.\n\n\(trimmed.prefix(14_000))"
        run(label: name ?? "text", prompt: prompt, image: nil)
    }

    /// Files sent from the right-click menu in Finder
    func send(files: [URL]) {
        guard let url = files.first else { return }
        let extra = files.count > 1 ? " (and \(files.count - 1) more: only the first is read)" : ""
        let name = url.lastPathComponent
        if let image = NSImage(contentsOf: url), let png = Self.png(image) {
            run(label: name + extra, prompt: "Describe what is in this image in one or two short sentences. If it contains text, say what it says.",
                image: png, task: .vision)
            return
        }
        guard let text = Self.readText(url) else {
            finish(.failed("I can't read \(name) yet. Text, code, notes and PDFs work."))
            return
        }
        run(label: name + extra, prompt: "This is the file \"\(name)\". Summarize it in a few short lines, or give its outline if it is long.\n\n\(text.prefix(14_000))", image: nil)
    }

    private func run(label: String, prompt: String, image: Data?, task kind: NotchyTask = .text) {
        guard NotchySettings.shared.enabled else {
            PopupCenter.shared.show(icon: "face.smiling", title: "Notchy is off", subtitle: "Turn it on in Settings → Notchy", seconds: 4)
            return
        }
        task?.cancel()
        state = .thinking(label)
        NotchyPresence.shared.peek(mood: .thinking, seconds: 90)
        PopupCenter.shared.show(icon: "ellipsis.bubble", title: "Notchy is reading…", subtitle: label, seconds: 4)
        task = Task { @MainActor [weak self] in
            do {
                let answer = try await NotchyClient.complete(prompt: prompt, system: Self.system, task: kind, image: image)
                guard !Task.isCancelled else { return }
                let clean = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                self?.finish(clean.isEmpty ? .failed("It had nothing to say.") : .reply(clean))
            } catch {
                guard !Task.isCancelled else { return }
                self?.finish(.failed(error.localizedDescription))
            }
        }
    }

    private func finish(_ result: State) {
        state = result
        switch result {
        case .reply(let text):
            NotchyPresence.shared.peek(mood: .happy, seconds: 8)
            let line = text.replacingOccurrences(of: "\n", with: " ")
            PopupCenter.shared.show(icon: "face.smiling", title: "Notchy", subtitle: String(line.prefix(110)) + (line.count > 110 ? "…" : ""), seconds: 12)
        case .failed(let why):
            NotchyPresence.shared.peek(mood: .sleepy, seconds: 4)
            PopupCenter.shared.show(icon: "exclamationmark.bubble", title: "Notchy could not", subtitle: String(why.prefix(110)), tint: .orange, seconds: 8)
        default: break
        }
    }

    func clear() { task?.cancel(); state = .idle; NotchyPresence.shared.peek(mood: .calm, seconds: 0.1) }

    // MARK: Reading files

    private static func readText(_ url: URL) -> String? {
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url) else { return nil }
            return (0..<min(doc.pageCount, 30)).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
        }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 3_000_000,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1).flatMap { $0.contains("\0") ? nil : $0 }
    }

    private static func png(_ image: NSImage) -> Data? {
        // Downscale: a huge screenshot costs many tokens and the answer does not need it
        let maxSide: CGFloat = 1280
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: target))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

/// "Send to Notchy" in the right-click menu (the Services menu), for selected text anywhere and for files in Finder
final class NotchyServices: NSObject {
    static let shared = NotchyServices()

    func register() {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    @objc func sendToNotchy(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            DispatchQueue.main.async { NotchyAssistant.shared.send(files: urls) }
        } else if let text = pboard.string(forType: .string) {
            DispatchQueue.main.async { NotchyAssistant.shared.send(text: text) }
        }
    }
}
