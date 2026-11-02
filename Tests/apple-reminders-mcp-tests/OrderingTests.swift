import Foundation
import Testing

extension EndToEnd {
    @Suite struct OrderingTests {
        let server: Server
        init() throws { server = try Server() }

        private func move(_ id: Any, _ position: String, _ sibling: Any) throws -> [String: Any] {
            try server.call("move_reminder", ["list": testList, "id": id, position: sibling]) as! [String: Any]
        }

        @Test func movesBefore() throws {
            try server.withReminders(3) { created in
                let ids = created.map { $0["id"] as! String }
                let moved = try move(ids[2], "before", ids[0])
                #expect(moved["id"] as? String == ids[2])
                #expect(try server.order(of: ids) == [ids[2], ids[0], ids[1]])
            }
        }

        @Test func movesAfter() throws {
            try server.withReminders(3) { created in
                let ids = created.map { $0["id"] as! String }
                _ = try move(ids[0], "after", ids[2])
                #expect(try server.order(of: ids) == [ids[1], ids[2], ids[0]])
            }
        }

        // Holds whether or not EventKit adds new reminders to the manual
        // order: ones the order doesn't mention are listed last, oldest first.
        @Test func listsNewRemindersLastInCreationOrder() throws {
            try server.withReminders(3) { created in
                let ids = created.map { $0["id"] as! String }
                let order = try server.order(of: ids)
                #expect(order == ids)
            }
        }

        // A reminder created after a move goes after the moved one, and the
        // move holds: EventKit adds new reminders to its cached copy of the
        // list's order, which mustn't predate the move.
        @Test func creatingKeepsAMove() throws {
            try server.withReminders(3) { created in
                let ids = created.map { $0["id"] as! String }
                _ = try move(ids[0], "after", ids[2])
                try server.withReminder { later in
                    let all = ids + [later["id"] as! String]
                    let order = try server.order(of: all)
                    #expect(order == [ids[1], ids[2], ids[0], all[3]])
                }
            }
        }

        // The same, with the move made by another server: one that had
        // already read the list before it.
        @Test func creatingKeepsAnotherServersMove() throws {
            try server.withReminders(3) { created in
                let ids = created.map { $0["id"] as! String }
                _ = try server.order(of: ids)
                let other = try Server()
                _ = try other.call("move_reminder", ["list": testList, "id": ids[0], "after": ids[2]])
                try server.withReminder { later in
                    let all = ids + [later["id"] as! String]
                    let order = try server.order(of: all)
                    #expect(order == [ids[1], ids[2], ids[0], all[3]])
                }
            }
        }

        @Test func movingIsIdempotent() throws {
            try server.withReminders(3) { created in
                let ids = created.map { $0["id"] as! String }
                _ = try move(ids[2], "before", ids[0])
                _ = try move(ids[2], "before", ids[0])
                #expect(try server.order(of: ids) == [ids[2], ids[0], ids[1]])
            }
        }

        @Test func needsExactlyOneOfBeforeAndAfter() throws {
            try server.withReminders(2) { created in
                let ids = created.map { $0["id"] as! String }
                let neither = try server.failure("move_reminder", ["list": testList, "id": ids[0]])
                #expect(neither.contains("exactly one of before and after"))
                let both = try server.failure("move_reminder", ["list": testList, "id": ids[0], "before": ids[1], "after": ids[1]])
                #expect(both.contains("exactly one of before and after"))
            }
        }

        @Test func rejectsUnknownSibling() throws {
            try server.withReminder { reminder in
                let unknown = UUID().uuidString
                let message = try server.failure("move_reminder", ["list": testList, "id": reminder["id"]!, "after": unknown])
                #expect(message.contains("No reminder with id \(unknown)"))
            }
        }

        @Test func rejectsItselfAsSibling() throws {
            try server.withReminder { reminder in
                let message = try server.failure("move_reminder", ["list": testList, "id": reminder["id"]!, "before": reminder["id"]!])
                #expect(message.contains("next to itself"))
                let lowercased = try server.failure("move_reminder", ["list": testList, "id": reminder["id"]!, "before": (reminder["id"] as! String).lowercased()])
                #expect(lowercased.contains("next to itself"))
            }
        }

        // As in the Reminders app: a reminder moved next to one in another
        // section joins that section.
        @Test func joinsTheSiblingsSection() throws {
            let sections = try server.sections()
            try #require(sections.count >= 2, "the test list needs two sections")
            try server.withReminders(1, ["section": sections[0]]) { first in
                try server.withReminders(1, ["section": sections[1]]) { second in
                    let moved = try move(first[0]["id"]!, "after", second[0]["id"]!)
                    #expect(moved["section"] as? String == sections[1])
                    #expect(try server.order(of: [first[0]["id"] as! String, second[0]["id"] as! String])
                        == [second[0]["id"] as! String, first[0]["id"] as! String])
                }
            }
        }

        @Test func leavesItsSectionNextToOneInNone() throws {
            let sections = try server.sections()
            try #require(!sections.isEmpty, "the test list needs a section")
            try server.withReminders(1, ["section": sections[0]]) { first in
                try server.withReminder { second in
                    let moved = try move(first[0]["id"]!, "before", second["id"]!)
                    #expect(moved["section"] == nil || moved["section"] is NSNull)
                }
            }
        }

        @Test func listsReportTheirSortOrder() throws {
            let lists = try server.call("list_lists", [:]) as! [[String: Any]]
            let list = try #require(lists.first { $0["name"] as? String == testList })
            #expect(["manual", "dueDate", "creationDate", "priority", "title"].contains(list["sorting"] as? String ?? ""))
        }
    }
}
