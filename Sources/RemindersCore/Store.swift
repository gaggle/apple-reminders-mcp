import EventKit
import Foundation

public func eprint(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

public let store = EKEventStore()

public func requestAccess() -> Bool {
    let sem = DispatchSemaphore(value: 0)
    var granted = false
    store.requestFullAccessToReminders { ok, error in
        granted = ok
        if let error = error {
            eprint("access request error: \(error)")
        }
        sem.signal()
    }
    sem.wait()
    return granted
}

/// Every Reminders list, in the order EventKit returns them.
public func reminderLists() -> [EKCalendar] {
    store.calendars(for: .reminder)
}

public func findCalendar(named name: String, createIfMissing: Bool) -> EKCalendar? {
    if let existing = store.calendars(for: .reminder).first(where: { $0.title == name }) {
        return existing
    }
    guard createIfMissing else { return nil }
    guard let source = store.defaultCalendarForNewReminders()?.source
        ?? store.sources.first(where: { $0.sourceType == .local })
        ?? store.sources.first
    else { return nil }
    let cal = EKCalendar(for: .reminder, eventStore: store)
    cal.title = name
    cal.source = source
    do {
        try store.saveCalendar(cal, commit: true)
        return cal
    } catch {
        eprint("saveCalendar failed: \(error)")
        return nil
    }
}

// Looks up a reminder by id, scoped to a specific list. Reminder ids are
// otherwise globally addressable via calendarItem(withIdentifier:), which
// would let a caller read/mutate any reminder anywhere if it ever received
// an id from outside the intended list (e.g. a tampered or stale state
// file) — this keeps every id-based operation confined to the list it's
// supposed to operate on.
public func findReminder(id: String, inList listName: String) -> EKReminder? {
    guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else { return nil }
    guard item.calendar.title == listName else { return nil }
    return item
}

public func fetchReminders(in calendar: EKCalendar) -> [EKReminder] {
    let predicate = store.predicateForReminders(in: [calendar])
    let sem = DispatchSemaphore(value: 0)
    var result: [EKReminder] = []
    _ = store.fetchReminders(matching: predicate) { reminders in
        result = reminders ?? []
        sem.signal()
    }
    sem.wait()
    return result
}
