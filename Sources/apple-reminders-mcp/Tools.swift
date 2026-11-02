import EventKit
import Foundation
import MCP
import RemindersCore

struct ToolError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct Args {
    private let raw: [String: Value]
    init(_ raw: [String: Value]) { self.raw = raw }

    func string(_ key: String) -> String? { raw[key]?.stringValue }
    func bool(_ key: String) -> Bool? { raw[key]?.boolValue }
    func require(_ key: String) throws -> String {
        guard let value = string(key) else { throw ToolError("missing argument: \(key)") }
        return value
    }
}

private func prop(_ type: String, _ description: String) -> Value {
    .object(["type": .string(type), "description": .string(description)])
}

private func schema(_ properties: [String: Value], required: [String]) -> Value {
    .object([
        "type": "object",
        "properties": .object(properties),
        "required": .array(required.map { .string($0) }),
        "additionalProperties": false,
    ])
}

private let listProp = prop("string", "The list's name, exactly as list_lists shows it.")
private let idProp = prop("string", "The reminder's id, from list_reminders or create_reminder.")
private let dueDescription = #""YYYY-MM-DD" for an all-day due date, "YYYY-MM-DDTHH:MM" for a specific local time."#

// Annotations tell the client which tools only read and which destroy, so
// it can approve the harmless ones freely and ask about the rest.
let tools: [Tool] = [
    Tool(
        name: "list_lists",
        description: "Lists the user's Reminders lists, with each list's sections and how it's sorted; the Reminders app shows the order move_reminder sets only for lists sorted \"manual\".",
        inputSchema: schema([:], required: []),
        annotations: .init(title: "List Reminders lists", readOnlyHint: true)
    ),
    Tool(
        name: "list_reminders",
        description: "Lists the reminders in one list, in the list's manual order. Open ones only, unless include_completed is true.",
        inputSchema: schema([
            "list": listProp,
            "include_completed": prop("boolean", "Also return completed reminders. Defaults to false."),
        ], required: ["list"]),
        annotations: .init(title: "List reminders", readOnlyHint: true)
    ),
    Tool(
        name: "create_reminder",
        description: "Creates a reminder in an existing list and returns it, with its id.",
        inputSchema: schema([
            "list": listProp,
            "name": prop("string", "The reminder's title."),
            "notes": prop("string", "Notes shown under the title."),
            "due": prop("string", dueDescription),
            "section": prop("string", "Section to put it in; created at the end of the list if it doesn't exist."),
            "flagged": prop("boolean", "Flag it. Defaults to false."),
        ], required: ["list", "name"]),
        annotations: .init(title: "Create reminder", readOnlyHint: false, destructiveHint: false, idempotentHint: false)
    ),
    Tool(
        name: "update_reminder",
        description: "Changes a reminder. Only the fields given are changed.",
        inputSchema: schema([
            "list": listProp,
            "id": idProp,
            "name": prop("string", "New title."),
            "notes": prop("string", "New notes; an empty string clears them."),
            "due": prop("string", dueDescription + " An empty string clears the due date."),
            "completed": prop("boolean", "Mark completed (true) or open again (false)."),
            "section": prop("string", "Move to this section, created if missing; an empty string takes it out of any section."),
            "flagged": prop("boolean", "Flag (true) or unflag (false)."),
        ], required: ["list", "id"]),
        annotations: .init(title: "Update reminder", readOnlyHint: false, destructiveHint: false, idempotentHint: true)
    ),
    Tool(
        name: "move_reminder",
        description: "Moves a reminder directly before or after another reminder in the same list, and returns it. Give exactly one of before and after.",
        inputSchema: schema([
            "list": listProp,
            "id": idProp,
            "before": prop("string", "Id of the reminder to move it directly before."),
            "after": prop("string", "Id of the reminder to move it directly after."),
        ], required: ["list", "id"]),
        annotations: .init(title: "Move reminder", readOnlyHint: false, destructiveHint: false, idempotentHint: true)
    ),
    Tool(
        name: "delete_reminder",
        description: "Deletes a reminder permanently. Reminders has no trash, so this can't be undone; completing it is usually what's wanted.",
        inputSchema: schema(["list": listProp, "id": idProp], required: ["list", "id"]),
        annotations: .init(title: "Delete reminder", readOnlyHint: false, destructiveHint: true, idempotentHint: true)
    ),
]

private struct ListOut: Encodable {
    let id: String
    let name: String
    let sections: [String]
    let sorting: String?
}

private struct ReminderOut: Encodable {
    let id: String
    let name: String
    let notes: String
    let completed: Bool
    let flagged: Bool
    let due: String?
    let allDay: Bool
    let recurrence: String?
    let section: String?

    init(_ r: ReminderJSON) {
        id = r.id
        name = r.name
        notes = r.body
        completed = r.completed
        flagged = r.flagged
        // Midnight is noise on an all-day date.
        due = r.allDay ? r.due.map { String($0.prefix(10)) } : r.due
        allDay = r.allDay
        recurrence = r.recurrence
        section = r.section
    }
}

private func json<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(data: try encoder.encode(value), encoding: .utf8)!
}

private func list(_ args: Args) throws -> EKCalendar {
    let name = try args.require("list")
    guard let cal = findCalendar(named: name, createIfMissing: false) else {
        let names = reminderLists().map(\.title).joined(separator: ", ")
        throw ToolError("No list named \"\(name)\". Lists: \(names)")
    }
    return cal
}

private func reminder(_ args: Args) throws -> EKReminder {
    let cal = try list(args)
    let id = try args.require("id")
    guard let item = findReminder(id: id, inList: cal.title) else {
        throw ToolError("No reminder with id \(id) in \"\(cal.title)\".")
    }
    return item
}

private func parseDue(_ s: String) throws -> DateComponents {
    let comps = s.contains("T")
        ? dueDateComponents(fromWire: s, allDay: false)
        : dueDateComponents(fromWire: s + "T00:00:00", allDay: true)
    guard let comps else { throw ToolError("Can't read due date \"\(s)\". \(dueDescription)") }
    return comps
}

private func out(_ item: EKReminder) -> ReminderOut {
    let sections = ListSections(calendar: item.calendar)
    let section = sections.all().isEmpty ? nil : sections.sectionName(ofReminder: item.calendarItemIdentifier)
    let flagged = ReminderFlags().flagged(among: [item.calendarItemIdentifier]).contains(item.calendarItemIdentifier)
    return ReminderOut(toJSON(item, section: section, flagged: flagged))
}

private func save(_ item: EKReminder) throws {
    do { try store.save(item, commit: true) } catch { throw ToolError("Saving failed: \(error)") }
}

func listLists() throws -> String {
    try json(reminderLists().map { cal in
        ListOut(id: cal.calendarIdentifier, name: cal.title, sections: ListSections(calendar: cal).all().map(\.name),
                sorting: ReminderOrdering(calendar: cal).sortingStyle())
    })
}

func listReminders(_ args: Args) throws -> String {
    let cal = try list(args)
    let includeCompleted = args.bool("include_completed") ?? false
    let reminders = ReminderOrdering(calendar: cal).sorted(fetchReminders(in: cal).filter { includeCompleted || !$0.isCompleted })
    let sections = ListSections(calendar: cal)
    let hasSections = !sections.all().isEmpty
    let flagged = ReminderFlags().flagged(among: reminders.map(\.calendarItemIdentifier))
    return try json(reminders.map {
        let id = $0.calendarItemIdentifier
        return ReminderOut(toJSON($0, section: hasSections ? sections.sectionName(ofReminder: id) : nil, flagged: flagged.contains(id)))
    })
}

func createReminder(_ args: Args) throws -> String {
    let cal = try list(args)
    let item = EKReminder(eventStore: store)
    item.calendar = cal
    item.title = try args.require("name")
    item.notes = args.string("notes")
    if let due = args.string("due") { item.dueDateComponents = try parseDue(due) }
    try save(item)
    if let section = args.string("section"), !section.isEmpty {
        ListSections(calendar: cal).move(reminder: item.calendarItemIdentifier, to: section)
    }
    if args.bool("flagged") == true { ReminderFlags().setFlagged(item.calendarItemIdentifier, true) }
    return try json(out(item))
}

func updateReminder(_ args: Args) throws -> String {
    let item = try reminder(args)
    if let name = args.string("name") { item.title = name }
    if let notes = args.string("notes") { item.notes = notes }
    if let due = args.string("due") { item.dueDateComponents = due.isEmpty ? nil : try parseDue(due) }
    if let completed = args.bool("completed") { item.isCompleted = completed }
    try save(item)
    if let section = args.string("section") {
        ListSections(calendar: item.calendar).move(reminder: item.calendarItemIdentifier, to: section.isEmpty ? nil : section)
    }
    if let flagged = args.bool("flagged") { ReminderFlags().setFlagged(item.calendarItemIdentifier, flagged) }
    return try json(out(item))
}

func moveReminder(_ args: Args) throws -> String {
    let item = try reminder(args)
    let (before, after) = (args.string("before"), args.string("after"))
    guard (before == nil) != (after == nil), let siblingID = before ?? after else {
        throw ToolError("Give exactly one of before and after.")
    }
    guard let sibling = findReminder(id: siblingID, inList: item.calendar.title) else {
        throw ToolError("No reminder with id \(siblingID) in \"\(item.calendar.title)\".")
    }
    // Ids match case-insensitively, so compare the reminders found.
    let (id, siblingItemID) = (item.calendarItemIdentifier, sibling.calendarItemIdentifier)
    guard siblingItemID != id else { throw ToolError("Can't move a reminder next to itself.") }
    let ordering = ReminderOrdering(calendar: item.calendar)
    guard !ordering.isSubtask(id), !ordering.isSubtask(siblingItemID) else {
        throw ToolError("Subtasks can't be moved, or moved next to.")
    }
    ordering.move(id, after: after != nil, sibling: siblingItemID)
    return try json(out(item))
}

func deleteReminder(_ args: Args) throws -> String {
    let item = try reminder(args)
    let deleted = out(item)
    do { try store.remove(item, commit: true) } catch { throw ToolError("Deleting failed: \(error)") }
    return try json(["deleted": deleted])
}
