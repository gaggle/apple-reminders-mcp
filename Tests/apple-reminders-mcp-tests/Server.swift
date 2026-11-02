import Foundation
import Testing

let testList = ProcessInfo.processInfo.environment["REMINDERS_MCP_TEST_LIST"] ?? "Sync Test"
let serverPath = ProcessInfo.processInfo.environment["REMINDERS_MCP_TEST_SERVER"]
let serverInstalled = serverPath != nil

/// Every end-to-end suite, run one at a time: they all share the test list,
/// and one suite's creates and deletes can race another's moves.
@Suite(.enabled(if: serverInstalled, "run with scripts/test.sh"), .serialized)
struct EndToEnd {}

struct ToolFailed: Error, CustomStringConvertible {
    let description: String
}

/// The installed MCP server, spoken to over stdio: one JSON-RPC message per line.
final class Server {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffered = Data()
    private var nextID = 1

    init() throws {
        process.executableURL = URL(fileURLWithPath: serverPath!)
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        _ = try request("initialize", [
            "protocolVersion": "2025-06-18",
            "capabilities": [String: Any](),
            "clientInfo": ["name": "tests", "version": "0"],
        ])
        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])
    }

    deinit {
        process.terminate()
        process.waitUntilExit()
    }

    /// Calls a tool and decodes its JSON output; a tool error throws.
    func call(_ tool: String, _ arguments: [String: Any]) throws -> Any {
        let text = try callForText(tool, arguments)
        return try JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    /// Calls a tool expecting it to fail, and returns the error message.
    func failure(_ tool: String, _ arguments: [String: Any]) throws -> String {
        do {
            let text = try callForText(tool, arguments)
            throw ToolFailed(description: "\(tool) succeeded: \(text)")
        } catch let failed as ToolCallError {
            return failed.message
        }
    }

    /// Creates a reminder in the test list, runs body with it, and deletes it.
    func withReminder(_ extra: [String: Any] = [:], _ body: ([String: Any]) throws -> Void) throws {
        let created = try call("create_reminder", ["list": testList, "name": "test \(UUID().uuidString)"].merging(extra) { $1 })
        let reminder = created as! [String: Any]
        defer { _ = try? call("delete_reminder", ["list": testList, "id": reminder["id"]!]) }
        try body(reminder)
    }

    /// Creates several reminders in the test list, in order, runs body with
    /// them, and deletes them.
    func withReminders(_ count: Int, _ extra: [String: Any] = [:], _ body: ([[String: Any]]) throws -> Void) throws {
        var created: [[String: Any]] = []
        defer { for reminder in created { _ = try? call("delete_reminder", ["list": testList, "id": reminder["id"]!]) } }
        for _ in 0..<count {
            let reminder = try call("create_reminder", ["list": testList, "name": "test \(UUID().uuidString)"].merging(extra) { $1 })
            created.append(reminder as! [String: Any])
        }
        try body(created)
    }

    /// The ids among `ids` in the order list_reminders returns them.
    func order(of ids: [String]) throws -> [String] {
        let all = try call("list_reminders", ["list": testList]) as! [[String: Any]]
        return all.map { $0["id"] as! String }.filter(ids.contains)
    }

    /// The test list's sections, in order.
    func sections() throws -> [String] {
        let lists = try call("list_lists", [:]) as! [[String: Any]]
        return lists.first { $0["name"] as? String == testList }?["sections"] as? [String] ?? []
    }

    /// The test list's open reminders, by id.
    func reminders() throws -> [String: [String: Any]] {
        let all = try call("list_reminders", ["list": testList]) as! [[String: Any]]
        return Dictionary(uniqueKeysWithValues: all.map { ($0["id"] as! String, $0) })
    }

    private struct ToolCallError: Error { let message: String }

    private func callForText(_ tool: String, _ arguments: [String: Any]) throws -> String {
        let result = try request("tools/call", ["name": tool, "arguments": arguments]) as! [String: Any]
        let text = ((result["content"] as! [[String: Any]]).first?["text"] as? String) ?? ""
        if result["isError"] as? Bool == true { throw ToolCallError(message: text) }
        return text
    }

    private func request(_ method: String, _ params: [String: Any]) throws -> Any {
        let id = nextID
        nextID += 1
        try send(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        while true {
            let message = try JSONSerialization.jsonObject(with: readLine()) as! [String: Any]
            guard message["id"] as? Int == id else { continue }
            if let error = message["error"] { throw ToolFailed(description: "\(method): \(error)") }
            return message["result"]!
        }
    }

    private func send(_ message: [String: Any]) throws {
        input.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: message) + Data("\n".utf8))
    }

    private func readLine() throws -> Data {
        while true {
            if let newline = buffered.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffered[..<newline]
                buffered.removeSubrange(...newline)
                return Data(line)
            }
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { throw ToolFailed(description: "server exited") }
            buffered.append(chunk)
        }
    }
}
