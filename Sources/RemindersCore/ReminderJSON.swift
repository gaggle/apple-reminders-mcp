import EventKit
import Foundation

public struct ReminderJSON: Codable {
    public let id: String
    public let name: String
    public let body: String
    public let completed: Bool
    public let flagged: Bool
    public let due: String?
    public let allDay: Bool
    public let recurrence: String?
    public let section: String?
}

// A compact, RRULE-style rendering of a reminder's repeat rules (e.g.
// "FREQ=MONTHLY;INTERVAL=3"), for logging which items repeat. Built by hand
// because EKRecurrenceRule's own description embeds an object address.
public func describeRecurrence(_ rules: [EKRecurrenceRule]?) -> String? {
    guard let rules, !rules.isEmpty else { return nil }
    let frequencies = ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"]
    let weekdays = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
    func list(_ values: [NSNumber]?) -> String? {
        guard let values, !values.isEmpty else { return nil }
        return values.map { $0.stringValue }.joined(separator: ",")
    }
    return rules.map { rule in
        var parts = ["FREQ=\(frequencies[rule.frequency.rawValue])", "INTERVAL=\(rule.interval)"]
        if let days = rule.daysOfTheWeek, !days.isEmpty {
            parts.append("BYDAY=" + days.map {
                ($0.weekNumber != 0 ? "\($0.weekNumber)" : "") + weekdays[$0.dayOfTheWeek.rawValue - 1]
            }.joined(separator: ","))
        }
        if let v = list(rule.daysOfTheMonth) { parts.append("BYMONTHDAY=\(v)") }
        if let v = list(rule.monthsOfTheYear) { parts.append("BYMONTH=\(v)") }
        if let v = list(rule.weeksOfTheYear) { parts.append("BYWEEKNO=\(v)") }
        if let v = list(rule.daysOfTheYear) { parts.append("BYYEARDAY=\(v)") }
        if let v = list(rule.setPositions) { parts.append("BYSETPOS=\(v)") }
        if let end = rule.recurrenceEnd {
            if let date = end.endDate {
                parts.append("UNTIL=\(ISO8601DateFormatter().string(from: date))")
            } else {
                parts.append("COUNT=\(end.occurrenceCount)")
            }
        }
        return parts.joined(separator: ";")
    }.joined(separator: " | ")
}

public func toJSON(_ r: EKReminder, section: String?, flagged: Bool) -> ReminderJSON {
    var due: String? = nil
    var allDay = false
    if let comps = r.dueDateComponents {
        due = formatNaiveDateTime(comps)
        allDay = comps.hour == nil
    }
    return ReminderJSON(
        id: r.calendarItemIdentifier,
        name: r.title ?? "",
        body: r.notes ?? "",
        completed: r.isCompleted,
        flagged: flagged,
        due: due,
        allDay: allDay,
        recurrence: describeRecurrence(r.recurrenceRules),
        section: section
    )
}
