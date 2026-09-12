import CryptoKit
import Foundation

struct CodexReadStateSnapshot: Equatable, Sendable {
    let identityKey: String
    let unreadTaskKeys: Set<String>

    nonisolated init(identityKey: String, unreadTaskKeys: Set<String>) {
        self.identityKey = identityKey
        self.unreadTaskKeys = unreadTaskKeys
    }
}

/// Read-only adapter for the desktop app's versioned, identity-scoped read state.
/// Never edits Codex's global state: opening a task lets Codex acknowledge it.
enum CodexReadStateReader {
    nonisolated static func identityKey(authData: Data) -> String? {
        guard let auth = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
              let tokens = auth["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String else { return nil }
        let components = token.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else { return nil }
        var payload = String(components[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let principal = claims["https://api.openai.com/auth"] as? [String: Any],
              let account = (principal["chatgpt_account_id"] ?? principal["account_id"]) as? String,
              let user = (principal["user_id"] ?? principal["chatgpt_user_id"]) as? String,
              !account.isEmpty, !user.isEmpty else { return nil }
        // Mirrors Codex's SHA256(JSON.stringify([kind, accountId, userId])).
        guard let keyData = try? JSONSerialization.data(withJSONObject: ["chatgpt", account, user],
                                                        options: [.withoutEscapingSlashes]) else { return nil }
        return hash(keyData)
    }

    nonisolated static func snapshot(stateData: Data, identityKey: String) -> CodexReadStateSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: stateData) as? [String: Any],
              let state = root["electron-thread-read-state-v1"] as? [String: Any],
              state["version"] as? Int == 1,
              let identities = state["unreadByIdentity"] as? [String: Any] else { return nil }
        // Local stdio host: SHA256(JSON.stringify(["local", "local", null])).
        // Do not merge remote hosts, alternate transports, accounts or legacyMigration.
        let hostKey = "local:" + hash(Data("[\"local\",\"local\",null]".utf8))
        var threadIDs: [String] = []
        if let value = identities[identityKey] {
            guard let hosts = value as? [String: Any] else { return nil }
            if let value = hosts[hostKey] {
                guard let ids = value as? [String], ids.allSatisfy({ UUID(uuidString: $0) != nil }) else { return nil }
                threadIDs = ids
            }
        }
        return CodexReadStateSnapshot(identityKey: identityKey,
            unreadTaskKeys: Set(threadIDs.map { hash(Data($0.utf8)) }))
    }

    nonisolated static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static var defaultDirectory: URL {
        if let directory = getpwuid(getuid())?.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory)).appendingPathComponent(".codex")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }
}

@MainActor
final class CodexReadStateMonitor {
    private let directory: URL
    private var task: Task<Void, Never>?
    private(set) var snapshot: CodexReadStateSnapshot?

    init(directory: URL = CodexReadStateReader.defaultDirectory) { self.directory = directory }

    func start(onChange: @escaping () -> Void) {
        guard task == nil else { return }
        let directory = directory
        task = Task { [weak self] in
            var previousAuth: Data?
            var previousState: Data?
            while !Task.isCancelled {
                // File I/O stays off the main thread and continues with the popup closed.
                let bytes = await Task.detached(priority: .utility) {
                    (try? Data(contentsOf: directory.appendingPathComponent("auth.json")),
                     try? Data(contentsOf: directory.appendingPathComponent(".codex-global-state.json")))
                }.value
                guard !Task.isCancelled else { return }
                if bytes.0 != previousAuth || bytes.1 != previousState {
                    previousAuth = bytes.0
                    previousState = bytes.1
                    let result = await Task.detached(priority: .utility) {
                        guard let auth = bytes.0, let identity = CodexReadStateReader.identityKey(authData: auth) else {
                            return (String?.none, CodexReadStateSnapshot?.none)
                        }
                        return (Optional(identity), bytes.1.flatMap {
                            CodexReadStateReader.snapshot(stateData: $0, identityKey: identity)
                        })
                    }.value
                    guard !Task.isCancelled else { return }
                    if let self {
                        // A partial write must not flash old local unread flags. A changed
                        // or unavailable identity must never inherit the previous account.
                        let next = result.1 ?? (result.0 == self.snapshot?.identityKey ? self.snapshot : nil)
                        if next != self.snapshot {
                            self.snapshot = next
                            onChange()
                        }
                    } else { return }
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    func stop() { task?.cancel(); task = nil }
    deinit { task?.cancel() }
}
