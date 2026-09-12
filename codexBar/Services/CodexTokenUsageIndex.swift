import Foundation

/// Only timestamped usage increments are persisted. No prompts, replies or credentials enter this cache.
nonisolated struct CodexTokenUsageEvent: Codable, Sendable {
    let timestamp: TimeInterval
    let tokens: Int
    let identity: String
}

nonisolated struct CodexTokenUsageParser: Codable, Sendable {
    var threadID = ""
    var previousTotal: Int?

    mutating func consume(_ line: Data) -> CodexTokenUsageEvent? {
        guard line.range(of: Data("\"token_count\"".utf8)) != nil
                || line.range(of: Data("\"session_meta\"".utf8)) != nil,
              let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = root["payload"] as? [String: Any] else { return nil }
        if root["type"] as? String == "session_meta" {
            threadID = payload["id"] as? String ?? threadID
            return nil
        }
        guard root["type"] as? String == "event_msg", payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let total = info["total_token_usage"] as? [String: Any],
              let cumulative = total["total_tokens"] as? Int, cumulative >= 0,
              let stamp = root["timestamp"] as? String,
              let date = try? Date(stamp, strategy: .iso8601) else { return nil }
        let last = info["last_token_usage"] as? [String: Any] ?? [:]
        let latest = max(0, last["total_tokens"] as? Int ?? 0)
        // A resumed/forked rollout may begin with a large inherited counter.
        // Only its latest request belongs to this first event. Counter resets
        // use the same rule; repeated counter snapshots contribute zero.
        let delta: Int
        if let previousTotal, cumulative >= previousTotal { delta = cumulative - previousTotal }
        else { delta = latest }
        previousTotal = cumulative
        guard delta > 0 else { return nil }
        let identity = "\(stamp)|\(cumulative)|\(latest)|\(last["input_tokens"] as? Int ?? 0)|\(last["output_tokens"] as? Int ?? 0)"
        return CodexTokenUsageEvent(timestamp: date.timeIntervalSince1970, tokens: delta, identity: identity)
    }
}

nonisolated final class CodexTokenUsageIndex: @unchecked Sendable {
    static let shared = CodexTokenUsageIndex()
    private let lock = NSLock()
    private let cacheURL: URL?
    private var files: [String: FileState] = [:]
    private var loaded = false

    private struct FileState: Codable {
        var inode: UInt64
        var size: UInt64 = 0
        var modified: TimeInterval = 0
        var offset: UInt64 = 0
        var parser = CodexTokenUsageParser()
        var events: [CodexTokenUsageEvent] = []
    }
    private struct Cache: Codable {
        let version: Int
        let files: [String: FileState]
    }

    init(cacheURL: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("codexAppBar/token-usage-v1.json")) {
        self.cacheURL = cacheURL
    }

    func snapshot(roots: [URL], statSince: Date, dailySince: Date, now: Date = Date(),
                  calendar: Calendar = Calendar(identifier: .gregorian)) -> CodexStatsDB.Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        if !loaded {
            if let cacheURL, let data = try? Data(contentsOf: cacheURL),
               let cache = try? JSONDecoder().decode(Cache.self, from: data), cache.version == 1 {
                files = cache.files
            }
            loaded = true
        }
        let lower = min(statSince, calendar.startOfDay(for: dailySince))
        var paths: Set<String> = []
        var changed = false
        var foundRoot = false
        let fm = FileManager.default
        for root in roots where fm.fileExists(atPath: root.path) {
            foundRoot = true
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let attributes = try? fm.attributesOfItem(atPath: url.path),
                      let modified = attributes[.modificationDate] as? Date,
                      let number = attributes[.size] as? NSNumber,
                      let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
                guard modified >= lower else { continue }
                let path = url.path
                paths.insert(path)
                let size = number.uint64Value
                let stamp = modified.timeIntervalSince1970
                var state = files[path] ?? FileState(inode: inode.uint64Value)
                if state.inode != inode.uint64Value || size < state.size || (size == state.size && stamp != state.modified) {
                    state = FileState(inode: inode.uint64Value)
                }
                if state.size != size || state.modified != stamp {
                    do { try read(url, through: size, into: &state) }
                    catch { return nil }
                    state.size = size
                    state.modified = stamp
                    files[path] = state
                    changed = true
                }
            }
        }
        guard foundRoot else { return nil }
        let oldCount = files.count
        files = files.filter { paths.contains($0.key) }
        changed = changed || oldCount != files.count
        if changed, let cacheURL, let encoded = try? JSONEncoder().encode(Cache(version: 1, files: files)) {
            try? fm.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? encoded.write(to: cacheURL, options: .atomic)
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var daily: [String: Int] = [:]
        var dailyThreads: [String: Set<String>] = [:]
        var seen: Set<String> = []
        var threads: Set<String> = []
        var total = 0
        for path in paths.sorted() {
            guard let state = files[path] else { continue }
            for event in state.events where event.timestamp >= lower.timeIntervalSince1970 && event.timestamp <= now.timeIntervalSince1970 {
                // Forked, migrated and archived copies can contain identical events.
                guard seen.insert(event.identity).inserted else { continue }
                let date = Date(timeIntervalSince1970: event.timestamp)
                if date >= statSince {
                    total += event.tokens
                    threads.insert(state.parser.threadID.isEmpty ? path : state.parser.threadID)
                }
                if date >= calendar.startOfDay(for: dailySince) {
                    let day = formatter.string(from: date)
                    daily[day, default: 0] += event.tokens
                    dailyThreads[day, default: []].insert(state.parser.threadID.isEmpty ? path : state.parser.threadID)
                }
            }
        }
        return CodexStatsDB.Snapshot(stat: .init(threadCount: threads.count, totalTokens: total), dailyTokens: daily, dailyThreads: dailyThreads)
    }

    private func read(_ url: URL, through size: UInt64, into state: inout FileState) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: state.offset)
        var readOffset = state.offset
        var pending = Data()
        let newline = Data([10])
        while readOffset < size {
            guard let chunk = try handle.read(upToCount: Int(min(1_048_576, size - readOffset))), !chunk.isEmpty else { break }
            readOffset += UInt64(chunk.count)
            pending.append(chunk)
            var start = pending.startIndex
            while let end = pending.range(of: newline, in: start..<pending.endIndex)?.lowerBound {
                if let event = state.parser.consume(pending.subdata(in: start..<end)) { state.events.append(event) }
                start = end + 1
            }
            if start > pending.startIndex { pending = Data(pending[start...]) }
        }
        // An incomplete tail is retried when the writer finishes its JSONL record.
        state.offset = readOffset - UInt64(pending.count)
    }
}
