import EventKit
import Foundation
import RemindersCore

func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(value) else {
        eprint("encode failed")
        exit(1)
    }
    print(String(data: data, encoding: .utf8)!)
}

// Options are parsed by walking argv in strict `--key value` pairs rather
// than by scanning the whole array for a matching `--key`. A scan treats
// every element as a potential option name, including the ones that are
// really values — so a reminder titled "--all-day" or "--body" (titles and
// notes come from Todoist, i.e. outside this program's control) would be
// re-read as an option and silently change how the rest of the command
// parsed. Consuming each value positionally means a value is never
// inspected as a key, whatever it happens to contain.
//
// Names in `flagNames` take no value; everything else consumes the next
// element. First occurrence wins, so an option can't be redefined later in
// the line either.
struct ParsedArgs {
    private let values: [String: String]
    private let flags: Set<String>

    static let flagNames: Set<String> = ["all-day", "no-sections"]

    init(_ args: [String]) {
        var values: [String: String] = [:]
        var flags: Set<String> = []
        var i = 0
        while i < args.count {
            guard args[i].hasPrefix("--") else {
                i += 1
                continue
            }
            let name = String(args[i].dropFirst(2))
            if ParsedArgs.flagNames.contains(name) {
                flags.insert(name)
                i += 1
            } else if i + 1 < args.count {
                if values[name] == nil { values[name] = args[i + 1] }
                i += 2
            } else {
                i += 1
            }
        }
        self.values = values
        self.flags = flags
    }

    func opt(_ name: String) -> String? { values[name] }
    func flag(_ name: String) -> Bool { flags.contains(name) }
}

guard requestAccess() else {
    eprint("Reminders access not granted. Check System Settings > Privacy & Security > Reminders.")
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    eprint("usage: reminders-bridge <command> [options]")
    exit(1)
}
let rest = Array(args.dropFirst())
let opts = ParsedArgs(rest)

switch command {
case "get-lists":
    printJSON(reminderLists().map { ["id": $0.calendarIdentifier, "name": $0.title] })

case "get-reminders":
    guard let listName = opts.opt("list"), let cal = findCalendar(named: listName, createIfMissing: true) else {
        print("[]")
        break
    }
    let started = Date()
    let reminders = fetchReminders(in: cal)
    let fetched = Date()
    // Sections come from ReminderKit, one lookup per reminder — skipped
    // outright for a list that has none, or when the caller doesn't sync them.
    let sections: ListSections? = opts.flag("no-sections") ? nil : ListSections(calendar: cal)
    let hasSections = sections.map { !$0.all().isEmpty } ?? false
    let rows = reminders.map {
        toJSON($0, section: hasSections ? sections?.sectionName(ofReminder: $0.calendarItemIdentifier) : nil)
    }
    // Timing goes to stderr, which the Python side logs at DEBUG.
    eprint(String(format: "get-reminders: %d reminders (%d open) fetched in %.1fs, sections %@ in %.1fs",
                  reminders.count, reminders.filter { !$0.isCompleted }.count, fetched.timeIntervalSince(started),
                  sections == nil ? "skipped" : hasSections ? "looked up" : "none", Date().timeIntervalSince(fetched)))
    printJSON(rows)

case "create-reminder":
    guard let listName = opts.opt("list"), let cal = findCalendar(named: listName, createIfMissing: true) else {
        eprint("list not found/creatable")
        exit(1)
    }
    let reminder = EKReminder(eventStore: store)
    reminder.calendar = cal
    reminder.title = opts.opt("name") ?? ""
    reminder.notes = opts.opt("body") ?? ""
    if let dueStr = opts.opt("due"), let comps = dueDateComponents(fromWire: dueStr, allDay: opts.flag("all-day")) {
        reminder.dueDateComponents = comps
    }
    do {
        try store.save(reminder, commit: true)
        printJSON(["id": reminder.calendarItemIdentifier])
    } catch {
        eprint("save failed: \(error)")
        exit(1)
    }

case "set-body":
    guard let listName = opts.opt("list"), let id = opts.opt("id"),
          let item = findReminder(id: id, inList: listName)
    else {
        printJSON(["ok": false])
        break
    }
    item.notes = opts.opt("body") ?? ""
    do {
        try store.save(item, commit: true)
        printJSON(["ok": true])
    } catch {
        eprint("save failed: \(error)")
        printJSON(["ok": false])
    }

case "set-name":
    guard let listName = opts.opt("list"), let id = opts.opt("id"),
          let item = findReminder(id: id, inList: listName)
    else {
        printJSON(["ok": false])
        break
    }
    item.title = opts.opt("name") ?? ""
    do {
        try store.save(item, commit: true)
        printJSON(["ok": true])
    } catch {
        eprint("save failed: \(error)")
        printJSON(["ok": false])
    }

case "complete":
    guard let listName = opts.opt("list"), let id = opts.opt("id"),
          let item = findReminder(id: id, inList: listName)
    else {
        printJSON(["ok": false])
        break
    }
    item.isCompleted = true
    do {
        try store.save(item, commit: true)
        printJSON(["ok": true])
    } catch {
        eprint("save failed: \(error)")
        printJSON(["ok": false])
    }

case "uncomplete":
    guard let listName = opts.opt("list"), let id = opts.opt("id"),
          let item = findReminder(id: id, inList: listName)
    else {
        printJSON(["ok": false])
        break
    }
    item.isCompleted = false
    do {
        try store.save(item, commit: true)
        printJSON(["ok": true])
    } catch {
        eprint("save failed: \(error)")
        printJSON(["ok": false])
    }

case "set-due":
    guard let listName = opts.opt("list"), let id = opts.opt("id"),
          let item = findReminder(id: id, inList: listName),
          let dueStr = opts.opt("due"), let comps = dueDateComponents(fromWire: dueStr, allDay: opts.flag("all-day"))
    else {
        printJSON(["ok": false])
        break
    }
    item.dueDateComponents = comps
    do {
        try store.save(item, commit: true)
        printJSON(["ok": true])
    } catch {
        eprint("save failed: \(error)")
        printJSON(["ok": false])
    }

case "set-section":
    // --section "" takes the reminder out of any section.
    guard let listName = opts.opt("list"), let id = opts.opt("id"),
          let item = findReminder(id: id, inList: listName), let name = opts.opt("section")
    else {
        printJSON(["ok": false])
        break
    }
    ListSections(calendar: item.calendar).move(reminder: item.calendarItemIdentifier, to: name.isEmpty ? nil : name)
    printJSON(["ok": true])

case "alert":
    // A loud reminder in the user's default list — deliberately not the
    // synced one — so a stopped sync gets noticed on every device: high
    // priority, due a minute from now, with an alarm at the due time.
    guard let cal = store.defaultCalendarForNewReminders() else {
        eprint("no default Reminders list")
        exit(1)
    }
    let alert = EKReminder(eventStore: store)
    alert.calendar = cal
    alert.title = opts.opt("name") ?? "Todoist Sync stopped"
    alert.notes = opts.opt("body") ?? ""
    alert.priority = 1
    let due = Date().addingTimeInterval(60)
    alert.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
    alert.addAlarm(EKAlarm(absoluteDate: due))
    do {
        try store.save(alert, commit: true)
        printJSON(["id": alert.calendarItemIdentifier])
    } catch {
        eprint("save failed: \(error)")
        exit(1)
    }

case "delete":
    guard let listName = opts.opt("list"), let id = opts.opt("id"),
          let item = findReminder(id: id, inList: listName)
    else {
        printJSON(["ok": false])
        break
    }
    do {
        try store.remove(item, commit: true)
        printJSON(["ok": true])
    } catch {
        eprint("remove failed: \(error)")
        printJSON(["ok": false])
    }

default:
    eprint("unknown command: \(command)")
    exit(1)
}
