import Foundation

/// Acknowledgements are scoped to one completion event, not the lifetime of a task.
@MainActor
final class TaskReadState {
    private let defaults: UserDefaults
    private let eventsKey = "taskCenter.readCompletionEvents.v1"
    private let initializedKey = "taskCenter.unreadInitialized.v1"
    private var readEvents: [String: String]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        readEvents = defaults.dictionary(forKey: eventsKey) as? [String: String] ?? [:]
    }

    func visibleRecords(from records: [TaskActivityRecord], knownTaskKeys: Set<String>? = nil,
                        codexUnreadTaskKeys: Set<String>? = nil,
                        requiresCodexReadState: Bool = false) -> [TaskActivityRecord] {
        if !defaults.bool(forKey: initializedKey) {
            // Start unread tracking now; the pre-upgrade backlog has already been seen.
            for record in records where record.state == .ready { readEvents[record.taskKey] = record.eventKey }
            defaults.set(true, forKey: initializedKey)
        }
        // A transient empty/partial filesystem read must not erase acknowledgements.
        if readEvents.count > 4096 {
            let retained = Set(records.map(\.taskKey))
            readEvents = readEvents.filter { retained.contains($0.key) }
        }
        defaults.set(readEvents, forKey: eventsKey)
        return records.filter {
            guard $0.state == .ready else { return true }
            if let knownTaskKeys, !knownTaskKeys.contains($0.taskKey) { return false }
            // Starting, resuming, interrupting or closing a session is not a completion.
            guard $0.source == "Stop" else { return false }
            if let codexUnreadTaskKeys { return codexUnreadTaskKeys.contains($0.taskKey) }
            // Do not advertise inferred unread completions while desktop state is loading.
            if requiresCodexReadState { return false }
            return readEvents[$0.taskKey] != $0.eventKey
        }
    }

    func markRead(_ record: TaskActivityRecord) {
        guard record.state == .ready else { return }
        readEvents[record.taskKey] = record.eventKey
        defaults.set(readEvents, forKey: eventsKey)
    }
}
