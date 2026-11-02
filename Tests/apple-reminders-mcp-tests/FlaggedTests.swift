import Testing

extension EndToEnd {
    @Suite struct FlaggedTests {
        let server: Server
        init() throws { server = try Server() }

        @Test func newRemindersAreUnflagged() throws {
            try server.withReminder { reminder in
                #expect(reminder["flagged"] as? Bool == false)
            }
        }

        @Test func createsFlagged() throws {
            try server.withReminder(["flagged": true]) { reminder in
                #expect(reminder["flagged"] as? Bool == true)
                let listed = try server.reminders()[reminder["id"] as! String]
                #expect(listed?["flagged"] as? Bool == true)
            }
        }

        @Test func flagsAndUnflags() throws {
            try server.withReminder { reminder in
                let id = reminder["id"] as! String
                let flagged = try server.call("update_reminder", ["list": testList, "id": id, "flagged": true]) as! [String: Any]
                #expect(flagged["flagged"] as? Bool == true)
                let listedFlagged = try server.reminders()[id]
                #expect(listedFlagged?["flagged"] as? Bool == true)

                let unflagged = try server.call("update_reminder", ["list": testList, "id": id, "flagged": false]) as! [String: Any]
                #expect(unflagged["flagged"] as? Bool == false)
                let listedUnflagged = try server.reminders()[id]
                #expect(listedUnflagged?["flagged"] as? Bool == false)
            }
        }

        @Test func otherUpdatesKeepTheFlag() throws {
            try server.withReminder(["flagged": true]) { reminder in
                let id = reminder["id"] as! String
                let renamed = try server.call("update_reminder", ["list": testList, "id": id, "name": "renamed \(id)"]) as! [String: Any]
                #expect(renamed["flagged"] as? Bool == true)
            }
        }
    }
}
