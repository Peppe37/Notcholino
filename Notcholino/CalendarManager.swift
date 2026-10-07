import EventKit
import Foundation

final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    @Published var upcomingEvent: EKEvent?
    @Published var hasAccess = false
    
    private let store = EKEventStore()
    private var timer: Timer?

    @Published var availableCalendars: [EKCalendar] = []
    @Published var selectedCalendarIDs: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(selectedCalendarIDs), forKey: "selectedCalendarIDs")
            fetchEvents()
        }
    }

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: "selectedCalendarIDs") {
            self.selectedCalendarIDs = Set(saved)
        }
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
                    if granted {
                        self?.fetchAvailableCalendars()
                        self?.fetchEvents()
                    }
                }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.hasAccess = granted
                    if granted {
                        self?.fetchAvailableCalendars()
                        self?.fetchEvents()
                    }
                }
            }
        }
    }
    
    func fetchAvailableCalendars() {
        let cals = store.calendars(for: .event)
        self.availableCalendars = cals
        if UserDefaults.standard.object(forKey: "selectedCalendarIDs") == nil {
            self.selectedCalendarIDs = Set(cals.map { $0.calendarIdentifier })
        }
    }

    func fetchEvents() {
        guard hasAccess else { return }
        let cal = Calendar.current
        let now = Date()
        guard let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now) else { return }
        
        let calsToSearch = store.calendars(for: .event).filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        guard !calsToSearch.isEmpty else {
            DispatchQueue.main.async { self.upcomingEvent = nil }
            return
        }
        
        let pred = store.predicateForEvents(withStart: now, end: endOfDay, calendars: calsToSearch)
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
    
    func openCalendar(at date: Date) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        
        guard let y = comps.year, let m = comps.month, let d = comps.day,
              let h = comps.hour, let min = comps.minute, let s = comps.second else { return }
              
        let scriptSource = """
        tell application "Calendar"
            activate
            set targetDate to current date
            set year of targetDate to \(y)
            set month of targetDate to \(m)
            set day of targetDate to \(d)
            set hours of targetDate to \(h)
            set minutes of targetDate to \(min)
            set seconds of targetDate to \(s)
            view calendar at targetDate
        end tell
        """
        
        if let script = NSAppleScript(source: scriptSource) {
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                script.executeAndReturnError(&error)
                if let err = error {
                    print("Calendar AppleScript Error: \(err)")
                }
            }
        }
    }
}
