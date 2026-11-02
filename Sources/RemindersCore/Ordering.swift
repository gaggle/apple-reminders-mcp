// Manual reminder order, through ReminderKit.
//
// EventKit has no notion of the order a list's reminders are in, so like
// sections and flags it goes through ReminderKit, with the same checks
// before every private class and selector.
import EventKit
import Foundation

@objc protocol RKOrderingStore {
    @objc(fetchListWithObjectID:error:) func fetchList(objectID: NSObject) throws -> NSObject
    @objc(fetchReminderWithObjectID:error:) func fetchReminder(objectID: NSObject) throws -> NSObject
}
@objc protocol RKOrderedList {
    @objc(reminderIDsOrdering) func reminderIDsOrdering() -> NSObject?
}
@objc protocol RKOrderingSaveRequest {
    @objc(updateList:) func update(list: NSObject) -> NSObject
    @objc(updateReminder:) func update(reminder: NSObject) -> NSObject
    @objc(saveSynchronouslyWithError:) func saveSynchronously() throws
}
@objc protocol RKOrderingListChange {
    @objc(insertReminderChangeItem:beforeReminderChangeItem:) func insert(_ reminder: NSObject, before sibling: NSObject)
    @objc(insertReminderChangeItem:afterReminderChangeItem:) func insert(_ reminder: NSObject, after sibling: NSObject)
}

/// The manual order of one Reminders list's reminders.
public final class ReminderOrdering {
    private let store = rkStore()
    private lazy var storeAPI = rk(store, as: RKOrderingStore.self, "fetchListWithObjectID:error:", "fetchReminderWithObjectID:error:")
    private let calendar: EKCalendar
    private let listID: NSObject

    public init(calendar: EKCalendar) {
        self.calendar = calendar
        listID = ListSections.objectID("REMCDList", calendar.calendarIdentifier)
    }

    /// How the Reminders app sorts the list ("manual", "dueDate", …). The
    /// manual order is kept whatever this is, but only shown under "manual".
    public func sortingStyle() -> String? {
        let storage: NSObject = rkValue(list(), "storage")
        guard storage.responds(to: NSSelectorFromString("sortingStyle")) else { rkFail("\(type(of: storage)) has no sortingStyle") }
        return storage.value(forKey: "sortingStyle") as? String
    }

    /// Reminder ids in the list's manual order.
    public func ids() -> [String] {
        let ordering = rk(list(), as: RKOrderedList.self, "reminderIDsOrdering").reminderIDsOrdering()
        let objectIDs: [NSObject]
        switch ordering {
        case nil: objectIDs = []
        case let array as [NSObject]: objectIDs = array
        case let set as NSOrderedSet: objectIDs = set.array as! [NSObject]
        default: rkFail("reminderIDsOrdering is a \(type(of: ordering!)): \(ordering!)")
        }
        return objectIDs.map { (rkValue($0, "uuid") as UUID).uuidString }
    }

    /// Sorts reminders into the list's manual order; any the ordering
    /// doesn't mention go last, oldest first.
    public func sorted(_ reminders: [EKReminder]) -> [EKReminder] {
        var position: [String: Int] = [:]
        for (i, id) in ids().enumerated() where position[id] == nil { position[id] = i }
        return reminders.enumerated().sorted { a, b in
            let (pa, pb) = (position[a.element.calendarItemIdentifier], position[b.element.calendarItemIdentifier])
            switch (pa, pb) {
            case let (pa?, pb?): return pa < pb
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil):
                let (da, db) = (a.element.creationDate ?? .distantPast, b.element.creationDate ?? .distantPast)
                return da != db ? da < db : a.offset < b.offset
            }
        }.map(\.element)
    }

    /// Whether the reminder is a subtask, ordered under its parent rather
    /// than in the list.
    public func isSubtask(_ reminderID: String) -> Bool {
        let storage: NSObject = rkValue(reminder(reminderID), "storage")
        guard storage.responds(to: NSSelectorFromString("parentReminderID")) else { rkFail("\(type(of: storage)) has no parentReminderID") }
        return storage.value(forKey: "parentReminderID") != nil
    }

    /// Moves a reminder directly before or after another in the same list.
    /// As in the Reminders app, it joins the other's section: sections show
    /// the order within them, so otherwise the move wouldn't show.
    public func move(_ reminderID: String, after: Bool, sibling siblingID: String) {
        let request = rk(rkInit("REMSaveRequest", "initWithStore:", store), as: RKOrderingSaveRequest.self,
                         "updateList:", "updateReminder:", "saveSynchronouslyWithError:")
        let listChange = rk(request.update(list: list()), as: RKOrderingListChange.self,
                            "insertReminderChangeItem:beforeReminderChangeItem:", "insertReminderChangeItem:afterReminderChangeItem:")
        let reminderChange = request.update(reminder: reminder(reminderID))
        let siblingChange = request.update(reminder: reminder(siblingID))
        if after { listChange.insert(reminderChange, after: siblingChange) } else { listChange.insert(reminderChange, before: siblingChange) }
        do { try request.saveSynchronously() } catch { rkFail("moving the reminder failed: \(error)") }

        let sections = ListSections(calendar: calendar)
        guard !sections.all().isEmpty else { return }
        let section = sections.sectionName(ofReminder: siblingID)
        if section != sections.sectionName(ofReminder: reminderID) { sections.move(reminder: reminderID, to: section) }
    }

    private func list() -> NSObject {
        do { return try storeAPI.fetchList(objectID: listID) } catch { rkFail("fetching the list failed: \(error)") }
    }

    private func reminder(_ id: String) -> NSObject {
        do {
            return try storeAPI.fetchReminder(objectID: ListSections.objectID("REMCDReminder", id))
        } catch {
            rkFail("fetching the reminder failed: \(error)")
        }
    }
}

