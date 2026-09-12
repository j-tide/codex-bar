import Foundation
import CryptoKit

/// Display-only metadata, resolved locally. Hook records retain their privacy-safe schema.
struct CodexTaskMetadata: Equatable, Sendable {
    let threadID: String
    let title: String
    var recency: TimeInterval = 0
    var createdAt: TimeInterval = 0
    var cwd: String? = nil
    var sidebarPosition: Int? = nil
    /// Saved Codex project name; directory basenames are not project identities.
    var projectName: String? = nil

    /// The append-only index has the user-visible (including renamed) title;
    /// the database title can still contain the initial prompt or attachment markup.
    nonisolated static func fromIndex(_ data: Data, matching keys: Set<String>) -> [String: CodexTaskMetadata] {
        struct Entry: Decodable {
            let id: String
            let thread_name: String
        }
        let decoder = JSONDecoder()
        var result: [String: CodexTaskMetadata] = [:]
        for line in data.split(separator: 0x0A).reversed() {
            guard let entry = try? decoder.decode(Entry.self, from: Data(line)) else { continue }
            let key = taskKey(for: entry.id)
            guard keys.contains(key), result[key] == nil else { continue }
            let title = entry.thread_name.split(whereSeparator: { $0.isNewline }).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            result[key] = CodexTaskMetadata(threadID: entry.id, title: String(title.prefix(240)))
            if result.count == keys.count { break }
        }
        return result
    }

    nonisolated static func taskKey(for threadID: String) -> String {
        SHA256.hash(data: Data(threadID.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
