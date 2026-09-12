import Foundation
import SQLite3

/// Read-only Codex metadata access. Calendar usage comes from timestamped rollout
/// increments; threads.tokens_used is a lifetime counter and cannot be grouped by updated_at.
struct CodexStatsDB {
    struct WindowStat: Equatable, Sendable {
        var threadCount: Int
        var totalTokens: Int

        nonisolated init(threadCount: Int = 0, totalTokens: Int = 0) {
            self.threadCount = threadCount
            self.totalTokens = totalTokens
        }
    }

    struct Snapshot: Sendable {
        let stat: WindowStat
        let dailyTokens: [String: Int]
        let dailyThreads: [String: Set<String>]

        nonisolated func windowStat(since: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> WindowStat {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let start = formatter.string(from: since)
            let total = dailyTokens.filter { $0.key >= start }.values.reduce(0, +)
            let threads = dailyThreads.filter { $0.key >= start }.values.reduce(into: Set<String>()) { $0.formUnion($1) }
            return WindowStat(threadCount: threads.count, totalTokens: total)
        }
    }

    nonisolated private static var homeDirectory: URL {
        if let pw = getpwuid(getuid()), let pwDir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: pwDir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    nonisolated private static var dbPaths: [String] {
        let codexHome = homeDirectory.appendingPathComponent(".codex")
        return [
            codexHome.appendingPathComponent("state_5.sqlite").path,
            codexHome.appendingPathComponent("sqlite/state_5.sqlite").path
        ]
    }

    nonisolated private static func openReadOnlyDB(at path: String) -> OpaquePointer? {
        var db: OpaquePointer?
        // 只读 + URI，WAL 库并发读安全
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let uri = "file:\(encodedPath)?mode=ro&immutable=0"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let openedDB = db else {
            if let db { sqlite3_close(db) }
            return nil
        }

        // 忙等 2s，避免 codex 写时短暂冲突直接失败
        sqlite3_busy_timeout(openedDB, 2000)
        return openedDB
    }

    /// SQLite WAL 模式下，最新写入可能只体现在 `-wal`，主库文件的 mtime 不会同步变化。
    /// 忽略 `-shm`：只读连接也会触碰它，不能用来判断哪个库仍在写入。
    nonisolated private static func contentModificationDate(at path: String) -> Date {
        let fileManager = FileManager.default
        return [path, path + "-wal"].compactMap { candidate in
            guard let attributes = try? fileManager.attributesOfItem(atPath: candidate) else {
                return nil
            }
            return attributes[.modificationDate] as? Date
        }.max() ?? .distantPast
    }

    nonisolated private static func latestThreadUpdatedAt(at path: String) -> Int64? {
        guard let db = openReadOnlyDB(at: path) else { return nil }
        defer { sqlite3_close(db) }

        let sql = "SELECT MAX(updated_at) FROM threads;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW,
              sqlite3_column_type(stmt, 0) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_int64(stmt, 0)
    }

    nonisolated private static var currentDBPath: String? {
        let fileManager = FileManager.default
        let candidates = dbPaths
            .filter { fileManager.fileExists(atPath: $0) }
            .sorted { contentModificationDate(at: $0) > contentModificationDate(at: $1) }

        // 最新写入的库若正好暂时不可读，不能静默退回旧库，否则会伪装成近期数据消失。
        guard let freshestPath = candidates.first,
              let freshestUpdatedAt = latestThreadUpdatedAt(at: freshestPath) else {
            return nil
        }

        var selectedPath = freshestPath
        var selectedUpdatedAt = freshestUpdatedAt

        for path in candidates.dropFirst() {
            guard let updatedAt = latestThreadUpdatedAt(at: path) else { continue }
            if updatedAt > selectedUpdatedAt {
                selectedPath = path
                selectedUpdatedAt = updatedAt
            }
        }
        return selectedPath
    }

    nonisolated private static func readFromCurrentDB<T>(_ read: (OpaquePointer) -> T?) -> T? {
        guard let path = currentDBPath,
              let db = openReadOnlyDB(at: path) else {
            return nil
        }
        defer { sqlite3_close(db) }

        return read(db)
    }

    /// Resolve only the active hook records; titles are never written to hook files or notifications.
    nonisolated static func taskMetadata(for keys: Set<String>) -> [String: CodexTaskMetadata] {
        guard !keys.isEmpty else { return [:] }
        var indexed: [String: CodexTaskMetadata] = [:]
        let indexURL = homeDirectory.appendingPathComponent(".codex/session_index.jsonl")
        if let handle = try? FileHandle(forReadingFrom: indexURL) {
            defer { try? handle.close() }
            if let size = try? handle.seekToEnd() {
                try? handle.seek(toOffset: size > 8_388_608 ? size - 8_388_608 : 0)
                if let data = try? handle.read(upToCount: 8_388_608) {
                    indexed = CodexTaskMetadata.fromIndex(data, matching: keys)
                }
            }
        }
        let database: [String: CodexTaskMetadata]? = readFromCurrentDB { db in
            var statement: OpaquePointer?
            // Recency tracks user-visible activity; updated_at also changes during background work.
            let modernSQL = "SELECT id, title, COALESCE(recency_at_ms / 1000.0, recency_at, updated_at), created_at, cwd FROM threads WHERE archived = 0 AND updated_at >= ?;"
            let legacySQL = "SELECT id, title, updated_at, created_at, cwd FROM threads WHERE archived = 0 AND updated_at >= ?;"
            if sqlite3_prepare_v2(db, modernSQL, -1, &statement, nil) != SQLITE_OK {
                sqlite3_finalize(statement)
                statement = nil
                guard sqlite3_prepare_v2(db, legacySQL, -1, &statement, nil) == SQLITE_OK else { return nil }
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, Int64(Date().addingTimeInterval(-48 * 60 * 60).timeIntervalSince1970))
            var result: [String: CodexTaskMetadata] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let id = sqlite3_column_text(statement, 0),
                      let title = sqlite3_column_text(statement, 1) else { continue }
                let threadID = String(cString: id)
                let key = CodexTaskMetadata.taskKey(for: threadID)
                guard keys.contains(key) else { continue }
                let text = String(cString: title).split(whereSeparator: { $0.isNewline }).joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                var item = indexed[key] ?? CodexTaskMetadata(threadID: threadID, title: String(text.prefix(240)))
                item.recency = sqlite3_column_double(statement, 2)
                item.createdAt = sqlite3_column_double(statement, 3)
                item.cwd = sqlite3_column_text(statement, 4).map { String(cString: $0) }
                result[key] = item
                if result.count == keys.count { break }
            }
            return result
        }
        // A readable DB is authoritative for live, non-archived tasks. The title
        // index alone also retains archived/deleted entries; use it only offline.
        let metadata = database ?? indexed
        let stateURL = homeDirectory.appendingPathComponent(".codex/.codex-global-state.json")
        return CodexSidebarOrder.applying(to: metadata, stateData: try? Data(contentsOf: stateURL))
    }

    /// threads.tokens_used is lifetime usage, not usage on updated_at's day.
    nonisolated static func snapshot(statSince: Date, dailySince: Date) -> Snapshot? {
        let home = homeDirectory.appendingPathComponent(".codex")
        return CodexTokenUsageIndex.shared.snapshot(
            roots: [home.appendingPathComponent("sessions"), home.appendingPathComponent("archived_sessions")],
            statSince: statSince, dailySince: dailySince)
    }
}
