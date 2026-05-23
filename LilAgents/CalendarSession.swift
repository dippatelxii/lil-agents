import Foundation
import EventKit
import AppKit

// MARK: - CalendarEvent

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarColor: NSColor
    let location: String?
    let ekEventIdentifier: String

    var minutesUntilStart: Int {
        Int(startDate.timeIntervalSinceNow / 60)
    }

    var isAllDay: Bool {
        Calendar.current.isDate(startDate, inSameDayAs: endDate) == false &&
            Calendar.current.component(.hour, from: startDate) == 0 &&
            Calendar.current.component(.minute, from: startDate) == 0
    }

    var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: startDate)
    }

    var formattedEndTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: endDate)
    }

    var relativeTime: String {
        let mins = minutesUntilStart
        if mins < 0 {
            let elapsed = -mins
            if elapsed < 60 { return "started \(elapsed)m ago" }
            return "in progress"
        }
        if mins == 0 { return "now!" }
        if mins < 60 { return "in \(mins) min" }
        let hours = mins / 60
        let rem = mins % 60
        if rem == 0 { return "in \(hours)h" }
        return "in \(hours)h \(rem)m"
    }

    /// Short bubble-friendly label shown 5 min before event.
    var alertBubbleText: String {
        let title = self.title.count > 18 ? String(self.title.prefix(17)) + "…" : self.title
        return "\(title) in 5 min"
    }
}

// MARK: - CalendarSession

class CalendarSession {
    private let store = EKEventStore()
    private var pollTimer: Timer?
    private var alertTimers: [String: Timer] = [:]
    private(set) var authStatus: EKAuthorizationStatus = .notDetermined

    /// When non-nil, only events from calendars whose names are in this set are shown.
    /// Comparison is case-insensitive. Set to `nil` (default) to include all calendars.
    var includedCalendarNames: Set<String>? = nil

    /// Calendar names to exclude. Ignored when `includedCalendarNames` is set.
    /// Comparison is case-insensitive.
    var excludedCalendarNames: Set<String> = []

    // Callbacks
    var onEventsRefreshed: (([CalendarEvent]) -> Void)?
    var onUpcomingAlert: ((CalendarEvent) -> Void)?
    var onAuthorizationChanged: ((EKAuthorizationStatus) -> Void)?

    private(set) var events: [CalendarEvent] = []

    func start() {
        requestAccess()
    }

    func terminate() {
        pollTimer?.invalidate()
        pollTimer = nil
        alertTimers.values.forEach { $0.invalidate() }
        alertTimers.removeAll()
    }

    // MARK: - Authorization

    private func requestAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized, .fullAccess:
            authStatus = .authorized
            beginPolling()
        case .notDetermined:
            if #available(macOS 14.0, *) {
                store.requestFullAccessToEvents { [weak self] granted, _ in
                    DispatchQueue.main.async {
                        self?.authStatus = granted ? .authorized : .denied
                        self?.onAuthorizationChanged?(self?.authStatus ?? .denied)
                        if granted { self?.beginPolling() }
                    }
                }
            } else {
                store.requestAccess(to: .event) { [weak self] granted, _ in
                    DispatchQueue.main.async {
                        self?.authStatus = granted ? .authorized : .denied
                        self?.onAuthorizationChanged?(self?.authStatus ?? .denied)
                        if granted { self?.beginPolling() }
                    }
                }
            }
        default:
            authStatus = status
            onAuthorizationChanged?(status)
        }
    }

    // MARK: - Polling

    private func beginPolling() {
        fetchUpcomingEvents()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.fetchUpcomingEvents()
        }
    }

    func fetchUpcomingEvents() {
        guard authStatus == .authorized || authStatus == .fullAccess else { return }

        let now = Date()
        // Show events from 10 minutes ago (ongoing) through end of day + next day
        let start = now.addingTimeInterval(-10 * 60)
        let end = Calendar.current.startOfDay(for: now).addingTimeInterval(48 * 3600)

        // Resolve which EKCalendars to query based on the name filter
        let allCalendars = store.calendars(for: .event)
        let filteredCalendars: [EKCalendar]?
        if let included = includedCalendarNames, !included.isEmpty {
            let lowercased = included.map { $0.lowercased() }
            filteredCalendars = allCalendars.filter { lowercased.contains($0.title.lowercased()) }
        } else if !excludedCalendarNames.isEmpty {
            let lowercased = excludedCalendarNames.map { $0.lowercased() }
            filteredCalendars = allCalendars.filter { !lowercased.contains($0.title.lowercased()) }
        } else {
            filteredCalendars = nil  // nil = all calendars
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: filteredCalendars)
        let ekEvents = store.events(matching: predicate)

        let calEvents: [CalendarEvent] = ekEvents.compactMap { ek in
            guard let title = ek.title, !title.isEmpty else { return nil }
            let color: NSColor
            if let cgColor = ek.calendar.cgColor {
                color = NSColor(cgColor: cgColor) ?? .systemBlue
            } else {
                color = .systemBlue
            }
            return CalendarEvent(
                id: ek.eventIdentifier ?? UUID().uuidString,
                title: title,
                startDate: ek.startDate,
                endDate: ek.endDate,
                calendarColor: color,
                location: ek.location?.isEmpty == false ? ek.location : nil,
                ekEventIdentifier: ek.eventIdentifier ?? ""
            )
        }
        .sorted { $0.startDate < $1.startDate }

        events = calEvents
        onEventsRefreshed?(calEvents)
        scheduleAlerts(for: calEvents)
    }

    // MARK: - 5-min Alerts

    private func scheduleAlerts(for calEvents: [CalendarEvent]) {
        // Cancel timers for events no longer in the list
        let currentIDs = Set(calEvents.map { $0.id })
        for (id, timer) in alertTimers where !currentIDs.contains(id) {
            timer.invalidate()
            alertTimers.removeValue(forKey: id)
        }

        for event in calEvents {
            // Only alert for future events we haven't already fired
            let alertDate = event.startDate.addingTimeInterval(-5 * 60)
            guard alertDate > Date(), alertTimers[event.id] == nil else { continue }

            let fireInterval = alertDate.timeIntervalSinceNow
            let timer = Timer.scheduledTimer(withTimeInterval: fireInterval, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.alertTimers.removeValue(forKey: event.id)
                DispatchQueue.main.async {
                    self.onUpcomingAlert?(event)
                }
            }
            alertTimers[event.id] = timer
        }
    }
}
