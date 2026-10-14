import EventKit
import Foundation

/// The link to join an online meeting, found in an event's URL, location or notes
struct MeetingLink {
    let service: String
    let url: URL

    private static let services: [(name: String, pattern: String)] = [
        ("Zoom", #"https?://[\w.-]*zoom\.(?:us|com)/[^\s<>"')]+"#),
        ("Meet", #"https?://meet\.google\.com/[a-z0-9-]+[^\s<>"')]*"#),
        ("Teams", #"https?://teams\.(?:microsoft|live)\.com/[^\s<>"')]+"#),
        ("Webex", #"https?://[\w.-]*webex\.com/[^\s<>"')]+"#),
        ("Whereby", #"https?://whereby\.com/[^\s<>"')]+"#),
        ("Jitsi", #"https?://meet\.jit\.si/[^\s<>"')]+"#)
    ]

    static func find(in event: EKEvent) -> MeetingLink? {
        let texts = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        for text in texts {
            for service in services {
                guard let range = text.range(of: service.pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
                // Links in notes sometimes end with punctuation
                let raw = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:>"))
                if let url = URL(string: raw) { return MeetingLink(service: service.name, url: url) }
            }
        }
        return nil
    }
}
