import EventKit
import Foundation

final class CalendarManager: ObservableObject {
    @Published var upcomingEvent: EKEvent?
    @Published var hasAccess = false
    
    private let store = EKEventStore()
    private var timer: Timer?

    init() {
        requestAccess()
        // Refresh every minute to keep "next event" accurate
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.fetchEvents()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func requestAccess() {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.hasAccess = granted
                    if granted { self?.fetchEvents() }
                }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.hasAccess = granted
                    if granted { self?.fetchEvents() }
                }
            }
        }
    }

    func fetchEvents() {
        guard hasAccess else { return }
        let cal = Calendar.current
        let now = Date()
        guard let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now) else { return }
        
        let pred = store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)
        let events = store.events(matching: pred)
        
        // Find next non-all-day event that hasn't finished yet
        let nextEvent = events
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .first

        DispatchQueue.main.async {
            self.upcomingEvent = nextEvent
        }
    }
    
    func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}
