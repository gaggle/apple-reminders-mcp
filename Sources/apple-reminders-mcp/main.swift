import EventKit
import Foundation
import MCP
import RemindersCore

relaunchDisclaimedIfNeeded()

let version = "0.1.0"
let accessGranted = requestAccess()

let server = Server(
    name: "apple-reminders",
    version: version,
    title: "Apple Reminders",
    instructions: """
        Reads and manages the user's Apple Reminders. Every reminder lives in a list, \
        and every call that touches a reminder names its list; call list_lists to see \
        what exists. Lists can be divided into sections. Due dates are local wall-clock \
        time: "YYYY-MM-DD" for an all-day due date, "YYYY-MM-DDTHH:MM" for a specific time.
        """,
    capabilities: .init(tools: .init(listChanged: false))
)

await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: tools)
}

await server.withMethodHandler(CallTool.self) { params in
    do {
        guard accessGranted else {
            throw ToolError("""
                Reminders access isn't granted to Reminders MCP. \
                Allow it in System Settings > Privacy & Security > Reminders, then restart the server.
                """)
        }
        // EventKit caches what it's read, and writes some of it back: a
        // new reminder goes onto its cached copy of the list's order, so a
        // stale copy undoes any move made since. Each call starts fresh.
        store.reset()
        let args = Args(params.arguments ?? [:])
        let output: String
        switch params.name {
        case "list_lists": output = try listLists()
        case "list_reminders": output = try listReminders(args)
        case "create_reminder": output = try createReminder(args)
        case "update_reminder": output = try updateReminder(args)
        case "move_reminder": output = try moveReminder(args)
        case "delete_reminder": output = try deleteReminder(args)
        default: throw ToolError("unknown tool: \(params.name)")
        }
        return .init(content: [.text(text: output, annotations: nil, _meta: nil)], isError: false)
    } catch {
        return .init(content: [.text(text: "\(error)", annotations: nil, _meta: nil)], isError: true)
    }
}

try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()
