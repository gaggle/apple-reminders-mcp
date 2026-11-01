// Flagged reminders, through ReminderKit.
//
// EventKit doesn't expose the flag, so like sections it goes through
// ReminderKit, with the same checks before every private class and selector.
import Foundation

@objc protocol RKReminderStore {
    @objc(fetchReminderWithObjectID:error:) func fetchReminder(objectID: NSObject) throws -> NSObject
    @objc(fetchRemindersWithObjectIDs:error:) func fetchReminders(objectIDs: [NSObject]) throws -> NSObject
}
@objc protocol RKReminderSaveRequest {
    @objc(updateReminder:) func update(reminder: NSObject) -> NSObject
    @objc(saveSynchronouslyWithError:) func saveSynchronously() throws
}
@objc protocol RKFlaggedContextOwner {
    @objc(flaggedContext) func flaggedContext() -> NSObject
}
@objc protocol RKFlaggedContext {
    @objc(flagged) func flagged() -> Int
}
@objc protocol RKFlaggedChange {
    @objc(setFlagged:) func setFlagged(_ value: Int)
}

/// Reads and sets the flag on reminders, by EventKit id.
public final class ReminderFlags {
    private let store = rkStore()
    private lazy var storeAPI = rk(store, as: RKReminderStore.self,
                                   "fetchReminderWithObjectID:error:", "fetchRemindersWithObjectIDs:error:")

    public init() {}

    /// The ids among `reminderIDs` that are flagged, in one fetch.
    public func flagged(among reminderIDs: [String]) -> Set<String> {
        guard !reminderIDs.isEmpty else { return [] }
        let objectIDs = reminderIDs.map { ListSections.objectID("REMCDReminder", $0) }
        let fetched: NSObject
        do { fetched = try storeAPI.fetchReminders(objectIDs: objectIDs) } catch { rkFail("fetching reminders failed: \(error)") }
        // Keyed by object id; a reminder ReminderKit can't see is just absent.
        guard let byID = fetched as? [NSObject: NSObject] else { rkFail("fetchRemindersWithObjectIDs: didn't return a dictionary") }
        var result: Set<String> = []
        for (id, objectID) in zip(reminderIDs, objectIDs) {
            if let reminder = byID[objectID], isFlagged(reminder) { result.insert(id) }
        }
        return result
    }

    public func setFlagged(_ reminderID: String, _ flagged: Bool) {
        let reminder: NSObject
        do {
            reminder = try storeAPI.fetchReminder(objectID: ListSections.objectID("REMCDReminder", reminderID))
        } catch {
            rkFail("fetching the reminder failed: \(error)")
        }
        let request = rk(rkInit("REMSaveRequest", "initWithStore:", store), as: RKReminderSaveRequest.self,
                         "updateReminder:", "saveSynchronouslyWithError:")
        let change = rk(request.update(reminder: reminder), as: RKFlaggedContextOwner.self, "flaggedContext")
        rk(change.flaggedContext(), as: RKFlaggedChange.self, "setFlagged:").setFlagged(flagged ? 1 : 0)
        do { try request.saveSynchronously() } catch { rkFail("flagging the reminder failed: \(error)") }
    }

    private func isFlagged(_ reminder: NSObject) -> Bool {
        let context = rk(reminder, as: RKFlaggedContextOwner.self, "flaggedContext").flaggedContext()
        return rk(context, as: RKFlaggedContext.self, "flagged").flagged() != 0
    }
}
