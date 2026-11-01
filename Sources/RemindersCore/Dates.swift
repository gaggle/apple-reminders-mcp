import Foundation

// Wire format for due dates is "yyyy-MM-ddTHH:mm:ss" with no timezone —
// local wall-clock time, as Reminders shows it. Parsing/formatting these as literal
// calendar components (never through Date/ISO8601DateFormatter, which are
// instant-based and would silently shift the date across timezone
// boundaries — exactly the bug this caused during testing) keeps it
// unambiguous.
public func parseNaiveDateTime(_ s: String) -> DateComponents? {
    let parts = s.split(separator: "T")
    guard parts.count == 2 else { return nil }
    let dateParts = parts[0].split(separator: "-").compactMap { Int($0) }
    let timeParts = parts[1].split(separator: ":").compactMap { Int($0.prefix(2)) }
    guard dateParts.count == 3, timeParts.count >= 2 else { return nil }
    var comps = DateComponents()
    comps.year = dateParts[0]
    comps.month = dateParts[1]
    comps.day = dateParts[2]
    comps.hour = timeParts[0]
    comps.minute = timeParts[1]
    comps.second = timeParts.count >= 3 ? timeParts[2] : 0
    return comps
}

public func formatNaiveDateTime(_ comps: DateComponents) -> String? {
    guard let y = comps.year, let mo = comps.month, let d = comps.day else { return nil }
    let h = comps.hour ?? 0
    let mi = comps.minute ?? 0
    let s = comps.second ?? 0
    return String(format: "%04d-%02d-%02dT%02d:%02d:%02d", y, mo, d, h, mi, s)
}

// A reminder's due date is "all-day" (date only, no specific time) when its
// dueDateComponents carry no hour — matches how EventKit itself represents
// the distinction, unlike Reminders.app's AppleScript dictionary which
// always populates a time component regardless.
public func dueDateComponents(fromWire wire: String, allDay: Bool) -> DateComponents? {
    guard var comps = parseNaiveDateTime(wire) else { return nil }
    if allDay {
        comps.hour = nil
        comps.minute = nil
        comps.second = nil
    }
    return comps
}
