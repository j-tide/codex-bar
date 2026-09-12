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

    /// threads.tokens_used is lifetime usage, not usage on updated_at's day.
    nonisolated static func snapshot(statSince: Date, dailySince: Date) -> Snapshot? {
        let home = homeDirectory.appendingPathComponent(".codex")
        return CodexTokenUsageIndex.shared.snapshot(
            roots: [home.appendingPathComponent("sessions"), home.appendingPathComponent("archived_sessions")],
            statSince: statSince, dailySince: dailySince)
    }
}
