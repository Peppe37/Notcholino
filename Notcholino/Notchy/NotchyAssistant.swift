// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import EventKit
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
        or a few very short bullets for an outline. No greeting, no preamble, no sign-off. When the message carries facts you were \
        given (the time, the weather, the agenda), use them and never say you cannot access them. \
        Plain text only, no Markdown headings.
        """

    private static func systemPrompt() -> String {
        let language = NotchySettings.shared.replyLanguage
        return system + (language.isEmpty ? " Answer in the language of the text you are given."
                                          : " Always answer in \(language), whatever the language of the text.")
    }

    /// Text sent from the right-click menu, or from anywhere else
    func send(text: String, name: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let isQuestion = trimmed.count < 400 && trimmed.hasSuffix("?")
        let prompt = isQuestion ? trimmed : "Summarize this in a few short lines. If it is a list or a plan, give the outline.\n\n\(trimmed.prefix(14_000))"
        run(label: name ?? "text", prompt: prompt, image: nil, tools: isQuestion ? trimmed : nil)
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

    /// What is left of today, from the calendars ticked in Notcholino's own Calendar settings (not the ones shown in Calendar.app)
    /// and the reminders it shows. Titles and times only.
    static func agendaLines() -> [String] {
        let cal = CalendarManager.shared
        let now = Date()
        let clock = DateFormatter(); clock.dateFormat = "HH:mm"
        var lines: [String] = []
        for event in cal.todayEvents where event.isAllDay || event.endDate > now {
            let when = event.isAllDay ? "all day" : "\(clock.string(from: event.startDate))–\(clock.string(from: event.endDate))"
            lines.append("- \(when): \(event.title ?? "Event")")
        }
        for reminder in cal.todayReminders {
            let due = cal.dueTime(of: reminder).map { "due \($0)" } ?? (cal.isOverdue(reminder) ? "overdue" : "today")
            lines.append("- to do (\(due)): \(reminder.title ?? "Reminder")")
        }
        return lines
    }

    /// Voice: turn the recording into text, then answer it
    func transcribeAndAsk(_ file: URL) {
        guard NotchySettings.shared.enabled else { return }
        task?.cancel()
        state = .thinking("what you said")
        NotchyPresence.shared.peek(mood: .thinking, seconds: 90)
        task = Task { @MainActor [weak self] in
            defer { try? FileManager.default.removeItem(at: file) }
            do {
                let said = try await NotchyTranscriber.transcribe(file)
                guard !Task.isCancelled else { return }
                guard !said.isEmpty else { self?.finish(.failed("I didn't catch that.")); return }
                self?.ask(spoken: said)
            } catch {
                guard !Task.isCancelled else { return }
                self?.finish(.failed(error.localizedDescription))
            }
        }
    }

    /// Something said out loud. The day's agenda is added only when the words are about the day, so most questions cost nothing extra.
    func ask(spoken: String) {
        let lower = spoken.lowercased()
        let aboutDay = ["calendar", "calendario", "agenda", "today", "oggi", "giornata", "day", "impegn", "meeting", "riunion", "appuntament",
                        "schedule", "free time", "libero", "reminder", "promemoria"].contains { lower.contains($0) }
        var prompt = "I said this to you out loud: \"\(spoken)\". Answer it."
        if aboutDay {
            let lines = Self.agendaLines()
            prompt += lines.isEmpty ? "\n\nNothing is left on my calendar today." : "\n\nWhat is left of my day:\n\(lines.joined(separator: "\n"))"
        }
        run(label: "“\(spoken.prefix(40))”", prompt: prompt, image: nil, tools: spoken)
    }

    /// "Look at the screen": the text on the screen is read on the Mac; a picture is sent only if there is almost no text
    func lookAtScreen() {
        guard NotchySettings.shared.enabled else { return }
        task?.cancel()
        state = .thinking("your screen")
        NotchyPresence.shared.peek(mood: .thinking, seconds: 90)
        task = Task { @MainActor [weak self] in
            do {
                let look = try await NotchyScreen.capture()
                guard !Task.isCancelled else { return }
                if let png = look.png {
                    self?.run(label: "your screen", prompt: "Tell me in a couple of short sentences what I am looking at, and anything I should notice.", image: png, task: .vision)
                } else {
                    self?.run(label: "your screen", prompt: "This is the text on my screen, read on my Mac:\n\n\(look.text.prefix(10_000))\n\nTell me in a couple of short sentences what I am looking at, and anything I should notice.", image: nil)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.finish(.failed(error.localizedDescription))
            }
        }
    }

    /// "Plan my day": Notchy reads today's events and reminders from the Mac, and only if there is something to plan does it ask
    /// the text provider. Only titles and times are sent: no places, notes or attendees.
    func planDay() {
        let cal = CalendarManager.shared
        guard cal.hasAccess || cal.hasRemindersAccess else {
            finish(.failed("I can't see your calendar yet. Allow Calendar in Settings → General → Permissions."))
            return
        }
        let now = Date()
        let clock = DateFormatter(); clock.dateFormat = "HH:mm"
        let lines = Self.agendaLines()
        guard !lines.isEmpty else {
            finish(.reply("Nothing left on your calendar today. The rest of the day is yours."))
            return
        }
        let prompt = """
            It is \(clock.string(from: now)). This is what is left of my day:
            \(lines.joined(separator: "\n"))

            Help me organise it: what comes next, where there is free time, and one useful suggestion. \
            Three or four short lines at most.
            """
        run(label: "your day", prompt: prompt, image: nil)
    }

    private func run(label: String, prompt: String, image: Data?, task kind: NotchyTask = .text, tools: String? = nil) {
        guard NotchySettings.shared.enabled else {
            PopupCenter.shared.show(icon: "face.smiling", title: "Notchy is off", subtitle: "Turn it on in Settings → Notchy", seconds: 4)
            return
        }
        task?.cancel()
        state = .thinking(label)
        NotchyPresence.shared.peek(mood: .thinking, seconds: 90)
        PopupCenter.shared.show(icon: "ellipsis.bubble", title: "Notchy is reading…", subtitle: label, seconds: 4, opensNotchy: true)
        task = Task { @MainActor [weak self] in
            do {
                var full = prompt
                // Before answering a question, find out what it needs: the time, and the weather if that is the subject
                if let tools { full += "\n\n" + (await NotchyTools.context(for: tools)) }
                let answer = try await NotchyClient.complete(prompt: full, system: Self.systemPrompt(), task: kind, image: image)
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
            PopupCenter.shared.show(icon: "face.smiling", title: "Notchy", subtitle: String(line.prefix(110)) + (line.count > 110 ? "…" : ""), seconds: 12, opensNotchy: true)
        case .failed(let why):
            NotchyPresence.shared.peek(mood: .sleepy, seconds: 4)
            PopupCenter.shared.show(icon: "exclamationmark.bubble", title: "Notchy could not", subtitle: String(why.prefix(110)), tint: .orange, seconds: 8, opensNotchy: true)
        default: break
        }
    }

    /// Something Notchy noticed by itself (an email from someone on your list): shown like an answer, without asking any AI
    func note(_ text: String, title: String) {
        guard NotchySettings.shared.enabled else { return }
        state = .reply(text)
        NotchyPresence.shared.peek(mood: .curious, seconds: 8)
        PopupCenter.shared.show(icon: "envelope.fill", title: title, subtitle: String(text.prefix(110)), seconds: 10, opensNotchy: true)
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
