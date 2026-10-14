import EventKit
import Foundation

final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    @Published var upcomingEvent: EKEvent?
    /// Every event of today (all-day first, then by start time)
    @Published var todayEvents: [EKEvent] = []
    @Published var hasAccess = false
    /// Incomplete reminders due today or overdue (soonest first)
    @Published var todayReminders: [EKReminder] = []
    @Published var hasRemindersAccess = false
    
    private let store = EKEventStore()
    private var timer: Timer?
    private var storeObserver: NSObjectProtocol?

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
        refreshAccess()   // reminders: no dialog at launch, the user authorizes them from a button
        // Refresh every minute to keep "next event" accurate
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.fetchEvents()
            self?.fetchReminders()
        }
        // ...and right away when something changes in Calendar or Reminders
        storeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.fetchEvents()
            self?.fetchReminders()
        }
    }

    deinit {
        timer?.invalidate()
        if let storeObserver { NotificationCenter.default.removeObserver(storeObserver) }
    }

    /// Picks up permissions granted (or revoked) in System Settings while the app is running
    func refreshAccess() {
        let events = EKEventStore.authorizationStatus(for: .event)
        let eventsGranted = events == .fullAccess || events == .authorized
        if eventsGranted != hasAccess {
            hasAccess = eventsGranted
            if eventsGranted { fetchAvailableCalendars(); fetchEvents() }
        }
        let rem = EKEventStore.authorizationStatus(for: .reminder)
        let remindersGranted = rem == .fullAccess || rem == .authorized
        if remindersGranted != hasRemindersAccess {
            hasRemindersAccess = remindersGranted
            fetchReminders()
        }
    }

    func requestAccess(completion: (() -> Void)? = nil) {
        let handler: (Bool, Error?) -> Void = { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.hasAccess = granted
                if granted {
                    self?.fetchAvailableCalendars()
                    self?.fetchEvents()
                }
                completion?()
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: handler)
        } else {
            store.requestAccess(to: .event, completion: handler)
        }
    }

    func requestRemindersAccess(completion: (() -> Void)? = nil) {
        let handler: (Bool, Error?) -> Void = { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.hasRemindersAccess = granted
                if granted { self?.fetchReminders() }
                completion?()
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToReminders(completion: handler)
        } else {
            store.requestAccess(to: .reminder, completion: handler)
        }
    }

    // MARK: - Reminders

    var showsReminders: Bool { UserDefaults.standard.object(forKey: "calendarShowReminders") as? Bool ?? true }

    func fetchReminders() {
        guard hasRemindersAccess, showsReminders,
              let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) else {
            DispatchQueue.main.async { self.todayReminders = [] }
            return
        }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfDay, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let cal = Calendar.current
            let sorted = (reminders ?? []).sorted {
                let a = $0.dueDateComponents.flatMap { cal.date(from: $0) } ?? .distantFuture
                let b = $1.dueDateComponents.flatMap { cal.date(from: $0) } ?? .distantFuture
                return a < b
            }
            DispatchQueue.main.async { self?.todayReminders = sorted }
        }
    }

    /// The time a reminder is due today, nil when it has no time or isn't due today
    func dueTime(of reminder: EKReminder) -> String? {
        guard let comps = reminder.dueDateComponents, comps.hour != nil,
              let date = Calendar.current.date(from: comps), Calendar.current.isDateInToday(date) else { return nil }
        return formatTime(date)
    }

    func isOverdue(_ reminder: EKReminder) -> Bool {
        guard let comps = reminder.dueDateComponents, let date = Calendar.current.date(from: comps) else { return false }
        // A date without a time is due the whole day
        return comps.hour != nil ? date < Date() : Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date())
    }

    func complete(_ reminder: EKReminder) {
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            todayReminders.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }
        } catch {
            print("Could not complete reminder: \(error)")
            reminder.isCompleted = false
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
            DispatchQueue.main.async { self.upcomingEvent = nil; self.todayEvents = [] }
            return
        }
        
        let pred = store.predicateForEvents(withStart: now, end: endOfDay, calendars: calsToSearch)
        let events = store.events(matching: pred)
        
        // Find next non-all-day event that hasn't finished yet
        let nextEvent = events
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .first

        let startOfDay = cal.startOfDay(for: now)
        let dayPred = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: calsToSearch)
        let todays = store.events(matching: dayPred).sorted {
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            return $0.startDate < $1.startDate
        }

        DispatchQueue.main.async {
            self.upcomingEvent = nextEvent
            self.todayEvents = todays
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
