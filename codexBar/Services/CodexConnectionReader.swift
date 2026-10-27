import Foundation
import SQLite3

struct CodexConnectionStatus: Equatable, Sendable {
    enum Mode: Sendable {
        case subscription, ccSwitchDirect, ccSwitchRouting, customAPI, unknown
    }

    let mode: Mode
    let endpoint: String?
    let provider: String?

    nonisolated init(mode: Mode = .unknown, endpoint: String? = nil, provider: String? = nil) {
        self.mode = mode
        self.endpoint = endpoint
        self.provider = provider
    }
}

/// Reports the configured global connection, not the transport of an already running turn.
enum CodexConnectionReader {
    nonisolated static func readDefault() -> CodexConnectionStatus {
        let home: URL
        if let path = getpwuid(getuid())?.pointee.pw_dir {
            home = URL(fileURLWithPath: String(cString: path))
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
        }
        let codex = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".codex")
        return read(codexDirectory: codex, ccSwitchDirectory: home.appendingPathComponent(".cc-switch"))
    }

    nonisolated static func read(codexDirectory: URL, ccSwitchDirectory: URL) -> CodexConnectionStatus {
        let configURL = codexDirectory.appendingPathComponent("config.toml")
        let config: String
        do {
            config = try String(contentsOf: configURL, encoding: .utf8)
        } catch CocoaError.fileReadNoSuchFile {
            config = ""
        } catch {
            return CodexConnectionStatus()
        }
        guard let selection = selection(in: config) else { return CodexConnectionStatus() }
        if let endpoint = selection.endpoint {
            guard let url = URLComponents(string: endpoint),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                return CodexConnectionStatus()
            }
            let display = sanitizedEndpoint(endpoint)
            let managed = managedConnection(endpoint: endpoint, directory: ccSwitchDirectory)
            return CodexConnectionStatus(mode: managed?.mode ?? .customAPI,
                                         endpoint: display, provider: managed?.provider ?? selection.provider)
        }
        guard selection.provider == "openai" else { return CodexConnectionStatus() }
        guard let data = try? Data(contentsOf: codexDirectory.appendingPathComponent("auth.json")),
              let auth = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return CodexConnectionStatus()
        }
        if auth["auth_mode"] as? String == "apikey" || !(auth["OPENAI_API_KEY"] as? String ?? "").isEmpty {
            return CodexConnectionStatus(mode: .customAPI, provider: "OpenAI API")
        }
        if let tokens = auth["tokens"] as? [String: Any],
           !(tokens["access_token"] as? String ?? "").isEmpty {
            return CodexConnectionStatus(mode: .subscription, provider: "OpenAI")
        }
        return CodexConnectionStatus()
    }

    nonisolated private static func sanitizedEndpoint(_ endpoint: String) -> String? {
        guard var url = URLComponents(string: endpoint) else { return nil }
        url.user = nil
        url.password = nil
        url.query = nil
        url.fragment = nil
        return url.string
    }

    nonisolated private static func normalizedEndpoint(_ endpoint: String) -> String? {
        guard let safe = sanitizedEndpoint(endpoint), var url = URLComponents(string: safe) else { return nil }
        url.scheme = url.scheme?.lowercased()
        url.host = url.host?.lowercased()
        while url.path.hasSuffix("/") { url.path.removeLast() }
        return url.string
    }

    nonisolated private static func managedConnection(endpoint: String, directory: URL) -> CodexConnectionStatus? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(directory.appendingPathComponent("cc-switch.db").path,
                              &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)
        let proxy = rows(db, sql: "SELECT listen_address, listen_port FROM proxy_config WHERE app_type = 'codex'").first
        if let proxy, let url = URLComponents(string: endpoint),
           let port = Int(proxy[1]), url.port == port {
            let host = url.host?.lowercased() ?? ""
            let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]
            let listener = proxy[0].lowercased()
            let sameHost = host == listener || (localHosts.contains(host)
                && (localHosts.contains(listener) || ["0.0.0.0", "::", "[::]"].contains(listener)))
            if sameHost { return CodexConnectionStatus(mode: .ccSwitchRouting) }
        }
        // Match the live endpoint, not a possibly stale selected-provider flag.
        for row in rows(db, sql: "SELECT name, settings_config FROM providers WHERE app_type = 'codex' ORDER BY is_current DESC") {
            guard let data = row[1].data(using: .utf8),
                  let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let config = settings["config"] as? String,
                  let selected = selection(in: config), let baseURL = selected.endpoint,
                  normalizedEndpoint(baseURL) == normalizedEndpoint(endpoint) else { continue }
            return CodexConnectionStatus(mode: .ccSwitchDirect, provider: row[0])
        }
        return nil
    }

    nonisolated private static func rows(_ db: OpaquePointer?, sql: String) -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append((0..<sqlite3_column_count(statement)).map { index in
                sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
            })
        }
        return result
    }

    /// Read only connection-related scalar TOML values. Unsupported values fail closed;
    /// unrelated tables and multiline strings cannot override the selected provider.
    nonisolated private static func selection(in text: String) -> (provider: String, endpoint: String?)? {
        var section: [String] = []
        var values: [[String]: String] = [:]
        var multiline: String?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let delimiter = multiline {
                if line.contains(delimiter) { multiline = nil }
                continue
            }
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") {
                guard let end = line.lastIndex(of: "]"),
                      let path = keyPath(String(line[line.index(after: line.startIndex)..<end])) else { return nil }
                section = path
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            guard let key = keyPath(String(line[..<equals])) else { return nil }
            let path = section + key
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            let relevant = (path.count == 1 && ["model_provider", "profile"].contains(path[0]))
                || (path.count == 3 && path[0] == "profiles" && path[2] == "model_provider")
                || (path.count == 3 && path[0] == "model_providers" && path[2] == "base_url")
            if value.hasPrefix("\"\"\"") || value.hasPrefix("'''") {
                if relevant { return nil }
                let delimiter = String(value.prefix(3))
                if !value.dropFirst(3).contains(delimiter) { multiline = delimiter }
                continue
            }
            if relevant {
                guard let scalar = stringValue(value) else { return nil }
                values[path] = scalar
            }
        }
        guard multiline == nil else { return nil }
        var provider = values[["model_provider"]] ?? "openai"
        if let profile = values[["profile"]], let override = values[["profiles", profile, "model_provider"]] {
            provider = override
        }
        return (provider, values[["model_providers", provider, "base_url"]])
    }

    nonisolated private static func keyPath(_ text: String) -> [String]? {
        // Quoted table keys can contain dots (e.g. projects."/path/to/repo").
        var parts: [String] = [], current = ""
        var quote: Character?
        var escaped = false
        for char in text {
            if let active = quote {
                current.append(char)
                if escaped { escaped = false }
                else if char == "\\" && active == "\"" { escaped = true }
                else if char == active { quote = nil }
            } else if char == "\"" || char == "'" {
                quote = char; current.append(char)
            } else if char == "." {
                parts.append(current.trimmingCharacters(in: .whitespaces)); current = ""
            } else { current.append(char) }
        }
        guard quote == nil else { return nil }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return parts.map { stringValue($0) ?? $0 }
    }

    nonisolated private static func stringValue(_ text: String) -> String? {
        guard let quote = text.first, quote == "\"" || quote == "'" else { return nil }
        var escaped = false
        for index in text.indices.dropFirst() {
            let char = text[index]
            if escaped { escaped = false; continue }
            if char == "\\" && quote == "\"" { escaped = true; continue }
            if char == quote {
                let tail = text[text.index(after: index)...].trimmingCharacters(in: .whitespaces)
                guard tail.isEmpty || tail.hasPrefix("#") else { return nil }
                if quote == "'" { return String(text[text.index(after: text.startIndex)..<index]) }
                return try? JSONDecoder().decode(String.self, from: Data(text[...index].utf8))
            }
        }
        return nil
    }
}
