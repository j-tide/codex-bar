import Foundation

/// Goal continuations emit task_started without UserPromptSubmit. Reconcile the
/// hook projection with the actual turn lifecycle, without reading message text
/// into UI state or writing anything to Codex's files.
struct CodexTurnActivity: Equatable, Sendable {
    let turnID: String
    let startedAt: Date
    let endedAt: Date?

    nonisolated init(turnID: String, startedAt: Date, endedAt: Date? = nil) {
        self.turnID = turnID
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    func reconciling(_ record: TaskActivityRecord) -> TaskActivityRecord {
        // A newer hook (permission, interruption, compaction, etc.) wins.
        guard startedAt > record.updatedAt else { return record }
        let running = endedAt == nil
        let turnKey = CodexTaskMetadata.taskKey(for: turnID)
        return TaskActivityRecord(taskKey: record.taskKey, turnKey: turnKey,
            eventKey: "rollout-\(turnKey)-\(running ? "start" : "end")",
            state: running ? .running : .ready,
            phase: running ? .processing : .waitingInput,
            projectName: record.projectName, model: record.model,
            updatedAt: endedAt ?? startedAt,
            source: running ? "RolloutTaskStarted" : "RolloutTaskEnded")
    }
}

/// A serialized, incremental reader. Initial reads walk backwards to the latest
/// start event; subsequent polls read only appended bytes. Long-running tool
/// output therefore cannot push the start beyond a fixed tail window.
actor CodexTurnActivityReader {
    private struct Cache {
        var offset: UInt64
        var size: UInt64
        var modifiedAt: Date?
        var fileID: UInt64?
        var activity: CodexTurnActivity?
    }
    private var cache: [String: Cache] = [:]

    func activities(paths: [String: String]) -> [String: CodexTurnActivity] {
        let livePaths = Set(paths.values)
        cache = cache.filter { livePaths.contains($0.key) }
        var result: [String: CodexTurnActivity] = [:]
        for (key, path) in paths {
            if let activity = read(path: path) { result[key] = activity }
        }
        return result
    }

    func read(path: String) -> CodexTurnActivity? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            guard let size = (attributes[.size] as? NSNumber)?.uint64Value else { return nil }
            let modifiedAt = attributes[.modificationDate] as? Date
            let fileID = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
            let previous = cache[path]
            if let previous, previous.size == size, previous.modifiedAt == modifiedAt,
               previous.fileID == fileID { return previous.activity }
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            defer { try? handle.close() }
            var activity: CodexTurnActivity?
            var offset: UInt64 = 0
            if let previous, previous.fileID == fileID, size > previous.size {
                activity = previous.activity
                try handle.seek(toOffset: previous.offset)
                let data = try handle.readToEnd() ?? Data()
                let consumed = Self.consume(data, activity: &activity)
                offset = previous.offset + UInt64(consumed)
            } else {
                // Preserve complete line boundaries across backward blocks.
                var cursor = size
                var pending = Data()
                var events: [Event] = []
                var foundStart = false
                while cursor > 0 && !foundStart {
                    let start = cursor > 262_144 ? cursor - 262_144 : 0
                    try handle.seek(toOffset: start)
                    let block = try handle.read(upToCount: Int(cursor - start)) ?? Data()
                    pending.insert(contentsOf: block, at: pending.startIndex)
                    cursor = start
                    let firstNewline = pending.firstIndex(of: 10)
                    let boundary = cursor == 0 ? pending.startIndex : firstNewline.map { $0 + 1 }
                    guard let boundary else { continue }
                    let complete = Data(pending[boundary...])
                    if offset == 0, let last = complete.lastIndex(of: 10) {
                        offset = cursor + UInt64(boundary) + UInt64(last) + 1
                    }
                    let lines = complete.split(separator: 10, omittingEmptySubsequences: false)
                    // The last fragment may be an in-flight write.
                    for line in lines.dropLast().reversed() {
                        guard let event = Self.event(Data(line)) else { continue }
                        events.append(event)
                        if event.kind == "task_started" { foundStart = true; break }
                    }
                    pending = Data(pending[..<boundary])
                }
                for event in events.reversed() { Self.apply(event, to: &activity) }
            }
            cache[path] = Cache(offset: offset, size: size, modifiedAt: modifiedAt,
                fileID: fileID, activity: activity)
            return activity
        } catch {
            // A missing/unreadable source must not preserve a phantom running turn.
            cache[path] = nil
            return nil
        }
    }

    private struct Event {
        let kind: String
        let turnID: String
        let date: Date
    }

    private static func event(_ data: Data) -> Event? {
        // Avoid JSON decoding the (potentially large) tool and message payloads.
        guard ["task_started", "task_complete", "turn_aborted"].contains(where: {
            data.range(of: Data("\"\($0)\"".utf8)) != nil
        }), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["type"] as? String == "event_msg",
              let payload = root["payload"] as? [String: Any],
              let kind = payload["type"] as? String,
              ["task_started", "task_complete", "turn_aborted"].contains(kind),
              let turnID = payload["turn_id"] as? String, !turnID.isEmpty,
              let timestamp = root["timestamp"] as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: timestamp)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: timestamp)
        }
        guard let date else { return nil }
        return Event(kind: kind, turnID: turnID, date: date)
    }

    private static func apply(_ event: Event, to activity: inout CodexTurnActivity?) {
        if event.kind == "task_started" {
            activity = CodexTurnActivity(turnID: event.turnID, startedAt: event.date)
        } else if let current = activity, current.turnID == event.turnID {
            activity = CodexTurnActivity(turnID: current.turnID,
                startedAt: current.startedAt, endedAt: event.date)
        }
    }

    private static func consume(_ data: Data, activity: inout CodexTurnActivity?) -> Int {
        guard let lastNewline = data.lastIndex(of: 10) else { return 0 }
        for line in data[...lastNewline].split(separator: 10) {
            if let event = event(Data(line)) { apply(event, to: &activity) }
        }
        return lastNewline + 1
    }
}
