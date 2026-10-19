// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import EventKit
import Foundation

/// What the user can ask Notchy to do out loud, besides answering: put an event in the calendar, a reminder in Reminders, a note
/// in Notes. The AI turns the sentence (in any language) into one small JSON object, and plain code does the rest, so what is
/// saved is exactly what was parsed and shown.
enum NotchyCommand {
    case event(title: String, start: Date, end: Date, allDay: Bool, location: String?, notes: String?, calendar: String?)
    case reminder(title: String, due: Date?, hasTime: Bool, notes: String?, list: String?)
    case note(title: String?, body: String)
    /// Asks what is on the calendar and in Reminders over some days: nothing is saved, it is read and then answered
    case agenda(from: Date, to: Date, ifEmpty: String?)
    case answer(String)
}

/// What was done, in words, and how to take it back
struct NotchyDone {
    let summary: String
    let undo: () async -> Void
}

enum NotchyCommands {
    /// The instructions for the AI. It is told to act only on an explicit request, to put dates in one fixed format, and to answer
    /// normally otherwise.
    static let system = """
        You are the command parser of Notchy, a small assistant on the user's Mac. The user speaks in any language. Decide if they \
        EXPLICITLY ask you to add something: a calendar event, a reminder, or a note (for example "add to the calendar…", "remind me \
        to…", "note down…", "annotati…", "ricordami…", "aggiungi un evento…", "apunta…", "rappelle-moi…", "notiere…"). If they do not \
        clearly ask for it, answer their question instead.
        Reply with ONE JSON object and nothing else (no Markdown). Exactly one of:
        {"action":"event","title":"…","start":"YYYY-MM-DDTHH:MM","end":"YYYY-MM-DDTHH:MM","all_day":false,"location":null,"notes":null,"calendar":null}
        {"action":"reminder","title":"…","due":"YYYY-MM-DDTHH:MM" or "YYYY-MM-DD" or null,"notes":null,"list":null}
        {"action":"note","title":"a short title or null","body":"the text to keep"}
        {"action":"agenda","from":"YYYY-MM-DD","to":"YYYY-MM-DD","if_empty":"a short sentence"}
        {"action":"answer","text":"a short reply"}
        Use "agenda" when they ask what is on their calendar or reminders for a day or a period ("what do I have tomorrow?", "che ho \
        in agenda oggi?", "cosa devo fare questa settimana?"): "from" and "to" are the first and last day, inclusive (the same day for \
        one day); "if_empty" is what to say if there is nothing, in the user's language. Never use "agenda" to add something.
        Rules: dates and times are the user's local time, resolved from the "Now" line (so "tomorrow at 3pm", "next Tuesday", "alle 15 di \
        domani" become real dates). An event with no end lasts one hour; with only a date it is all day (all_day true, start and end the \
        same date). Keep titles short and in the user's language, without the words of the command. If something essential is missing \
        (an event with no day), do not guess: use {"action":"answer","text":"…"} to ask for it, in the user's language. The "text" of an \
        answer is in the user's language too.
        """

    /// Finds the JSON object in whatever the AI sent back (some wrap it in a code block or add a word) and reads it
    static func parse(_ raw: String) -> NotchyCommand {
        guard let open = raw.firstIndex(of: "{"), let close = raw.lastIndex(of: "}"), open < close,
              let data = String(raw[open...close]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = (json["action"] as? String)?.lowercased() else {
            return .answer(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        func text(_ key: String) -> String? {
            guard let s = (json[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, s.lowercased() != "null" else { return nil }
            return s
        }
        switch action {
        case "event":
            guard let title = text("title"), let startText = text("start"), let start = date(startText) else {
                return .answer(text("text") ?? "I did not get the day and time of the event. Say it again with the date.")
            }
            let allDay = (json["all_day"] as? Bool ?? false) || !start.hasTime
            var end = text("end").flatMap(date)?.date ?? start.date.addingTimeInterval(3600)
            if allDay { end = start.date }
            else if end <= start.date { end = start.date.addingTimeInterval(3600) }
            return .event(title: title, start: start.date, end: end, allDay: allDay, location: text("location"), notes: text("notes"), calendar: text("calendar"))
        case "reminder":
            guard let title = text("title") else { return .answer(text("text") ?? "What should I remind you of?") }
            let due = text("due").flatMap(date)
            return .reminder(title: title, due: due?.date, hasTime: due?.hasTime ?? false, notes: text("notes"), list: text("list"))
        case "agenda":
            guard let from = text("from").flatMap(date)?.date else { return .answer(text("text") ?? "Which day do you mean?") }
            return .agenda(from: from, to: text("to").flatMap(date)?.date ?? from, ifEmpty: text("if_empty"))
        case "note":
            guard let body = text("body") ?? text("title") else { return .answer(text("text") ?? "What should I write down?") }
            return .note(title: text("title"), body: body)
        default:
            return .answer(text("text") ?? raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// "2026-10-20T15:00", "2026-10-20 15:00", "2026-10-20T15:00:00+02:00" or "2026-10-20" (no time)
    static func date(_ s: String) -> (date: Date, hasTime: Bool)? {
        let text = s.trimmingCharacters(in: .whitespaces)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for (format, hasTime) in [("yyyy-MM-dd'T'HH:mm", true), ("yyyy-MM-dd'T'HH:mm:ss", true), ("yyyy-MM-dd HH:mm", true), ("yyyy-MM-dd HH:mm:ss", true), ("yyyy-MM-dd", false)] {
            f.dateFormat = format
            if let d = f.date(from: text) { return (d, hasTime) }
        }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: text) { return (d, true) }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: text).map { ($0, true) }
    }
}

/// Does what a command says. Events and reminders go through the Mac's own Calendar and Reminders (the access Notcholino already
/// asks for); notes go to Notes through AppleScript.
enum NotchyDoer {
    static func run(_ command: NotchyCommand) async throws -> NotchyDone {
        switch command {
        case .event(let title, let start, let end, let allDay, let location, let notes, let calendar):
            return try await addEvent(title: title, start: start, end: end, allDay: allDay, location: location, notes: notes, calendar: calendar)
        case .reminder(let title, let due, let hasTime, let notes, let list):
            return try await addReminder(title: title, due: due, hasTime: hasTime, notes: notes, list: list)
        case .note(let title, let body):
            return try await addNote(title: title, body: body)
        case .answer, .agenda:
            throw NotchyAIError(message: "Nothing to do.")
        }
    }

    private static func when(_ date: Date, time: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate(time ? "EEE d MMM HH:mm" : "EEE d MMM")
        return f.string(from: date)
    }

    // MARK: Calendar

    private static func addEvent(title: String, start: Date, end: Date, allDay: Bool, location: String?, notes: String?, calendar: String?) async throws -> NotchyDone {
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else {
            throw NotchyAIError(message: "Allow Calendar for Notcholino in System Settings → Privacy & Security to add events.")
        }
        let writable = store.calendars(for: .event).filter(\.allowsContentModifications)
        let wanted = [calendar, NotchySettings.shared.defaultCalendar].compactMap { $0 }.filter { !$0.isEmpty }
        let target = wanted.lazy.compactMap { name in writable.first { $0.title.localizedCaseInsensitiveContains(name) } }.first
            ?? store.defaultCalendarForNewEvents ?? writable.first
        guard let target else { throw NotchyAIError(message: "There is no calendar to put the event in.") }
        let event = EKEvent(eventStore: store)
        event.calendar = target
        event.title = title
        event.isAllDay = allDay
        event.startDate = start
        event.endDate = allDay ? start : end
        event.location = location
        event.notes = notes
        try store.save(event, span: .thisEvent, commit: true)
        let id = event.eventIdentifier
        let span = allDay ? when(start, time: false) : "\(when(start, time: true))–\(DateFormatter.localizedString(from: end, dateStyle: .none, timeStyle: .short))"
        return NotchyDone(summary: "Calendar · \(title) · \(span) (\(target.title))") {
            if let id, let e = store.event(withIdentifier: id) { try? store.remove(e, span: .thisEvent, commit: true) }
        }
    }

    // MARK: Reminders

    private static func addReminder(title: String, due: Date?, hasTime: Bool, notes: String?, list: String?) async throws -> NotchyDone {
        let store = EKEventStore()
        guard try await store.requestFullAccessToReminders() else {
            throw NotchyAIError(message: "Allow Reminders for Notcholino in System Settings → Privacy & Security to add reminders.")
        }
        let lists = store.calendars(for: .reminder).filter(\.allowsContentModifications)
        let wanted = [list, NotchySettings.shared.defaultReminderList].compactMap { $0 }.filter { !$0.isEmpty }
        let target = wanted.lazy.compactMap { name in lists.first { $0.title.localizedCaseInsensitiveContains(name) } }.first
            ?? store.defaultCalendarForNewReminders() ?? lists.first
        guard let target else { throw NotchyAIError(message: "There is no list to put the reminder in.") }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = target
        reminder.title = title
        reminder.notes = notes
        if let due {
            let parts: Set<Calendar.Component> = hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            reminder.dueDateComponents = Calendar.current.dateComponents(parts, from: due)
            if hasTime { reminder.addAlarm(EKAlarm(absoluteDate: due)) }
        }
        try store.save(reminder, commit: true)
        let id = reminder.calendarItemIdentifier
        let tail = due.map { " · \(when($0, time: hasTime))" } ?? ""
        return NotchyDone(summary: "Reminders · \(title)\(tail) (\(target.title))") {
            if let r = store.calendarItem(withIdentifier: id) as? EKReminder { try? store.remove(r, commit: true) }
        }
    }

    // MARK: Notes

    private static func addNote(title: String?, body: String) async throws -> NotchyDone {
        func html(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\n", with: "<br>")
        }
        func quoted(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        let content = (title.map { "<div><h1>\(html($0))</h1></div>" } ?? "") + "<div>\(html(body))</div>"
        let script = """
            tell application "Notes"
                set theNote to make new note with properties {body:\(quoted(content))}
                return id of theNote
            end tell
            """
        let id = try await runScript(script)
        return NotchyDone(summary: "Notes · \(title ?? String(body.prefix(40)))") {
            _ = try? await runScript("tell application \"Notes\" to delete (every note whose id is \(quoted(id)))")
        }
    }

    /// AppleScript off the main thread (Notes can be slow to start, or ask for permission)
    private static func runScript(_ source: String) async throws -> String {
        try await withCheckedThrowingContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else { c.resume(throwing: NotchyAIError(message: "Could not prepare the note.")); return }
                let result = script.executeAndReturnError(&error)
                if let error {
                    let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                    c.resume(throwing: NotchyAIError(message: code == -1743
                        ? "Allow Notcholino to control Notes in System Settings → Privacy & Security → Automation."
                        : (error[NSAppleScript.errorMessage] as? String) ?? "Notes did not answer."))
                } else {
                    c.resume(returning: result.stringValue ?? "")
                }
            }
        }
    }
}
