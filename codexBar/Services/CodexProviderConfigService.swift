import Foundation

/// 读写 ~/.codex/config.toml 与 models.json，把 Codex 指向第三方
/// OpenAI Responses 兼容服务（智谱 GLM Coding Plan 等）。
/// 只动自己负责的键与段落，其余配置（sandbox、mcp_servers 等）原样保留；
/// 每次写入前留时间戳备份。
///
/// 注意：这份配置只对终端里的 codex CLI 生效。Codex 桌面端（独立 Codex App /
/// ChatGPT App）固定走登录的 ChatGPT 账号请求官方后端，不读取 model_provider。
struct CodexProviderConfigService: Sendable {
    enum ProviderError: LocalizedError {
        case unsupportedWireAPI
        case invalidProviderKey

        var errorDescription: String? {
            switch self {
            case .unsupportedWireAPI:
                return "This Codex CLI supports only the Responses API. Choose a Responses-compatible provider."
            case .invalidProviderKey:
                return "Choose a provider ID using letters, numbers, underscores, or hyphens, other than a built-in Codex provider."
            }
        }
    }

    let configURL: URL
    let modelsURL: URL

    init(configURL: URL, modelsURL: URL) {
        self.configURL = configURL
        self.modelsURL = modelsURL
    }

    // MARK: - Read

    /// 顶层 model_provider 的值；nil 或空 = 官方通道。
    func activeProviderKey() -> String? {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }
        return Self.topLevelValue(for: "model_provider", in: text)
    }

    func currentModel() -> String? {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }
        return Self.topLevelValue(for: "model", in: text)
    }

    // MARK: - Write

    func activate(_ account: ProviderAccount) throws {
        guard account.resolvedWireAPI == "responses" else { throw ProviderError.unsupportedWireAPI }
        guard ProviderAccount.isValidProviderKey(account.providerKey) else { throw ProviderError.invalidProviderKey }
        var text = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        try backup(text, of: configURL, named: "config.toml")

        // 只替换当前账号对应的段；其他手动配置的 provider 保留。
        text = Self.removeSection(named: "model_providers.\(account.providerKey)", from: text)
        text = Self.removeTopLevelKeys(["model_provider", "model", "model_catalog_json"], from: text)
        var topLevel = [
            "model_provider = \(Self.quoted(account.providerKey))",
            "model = \(Self.quoted(account.model))"
        ]
        topLevel.append("model_catalog_json = \(Self.quoted(modelsURL.path))")
        text = Self.insertTopLevelLines(topLevel, into: text)
        let section = """

        [model_providers.\(account.providerKey)]
        name = \(Self.quoted(account.providerKey))
        base_url = \(Self.quoted(account.baseURL))
        experimental_bearer_token = \(Self.quoted(account.apiKey))
        wire_api = \(Self.quoted(account.resolvedWireAPI))
        """
        text = text.trimmingCharacters(in: .newlines) + "\n" + section + "\n"
        try writeModelsCatalog(for: account)
        try writePrivate(text, to: configURL)
    }

    /// 移除 provider 覆盖；restoreModel 非空时还原官方 model，为空时只删除 provider 行。
    func deactivate(restoreModel: String?) throws {
        guard let original = try? String(contentsOf: configURL, encoding: .utf8) else { return }
        var text = original
        if let key = activeProviderKey() {
            text = Self.removeSection(named: "model_providers.\(key)", from: text)
        }
        text = Self.removeTopLevelKeys(["model_provider", "model_catalog_json", "model"], from: text)
        if let restoreModel, !restoreModel.isEmpty {
            text = Self.insertTopLevelLines(["model = \(Self.quoted(restoreModel))"], into: text)
        }
        guard text != original else { return }
        try backup(original, of: configURL, named: "config.toml")
        try writePrivate(text, to: configURL)
    }

    // MARK: - models.json

    /// 智谱 Coding Plan 当前可用模型；智谱域名下激活时全部写入目录，
    /// 这样 Codex 的模型切换列表里两个都能选。
    static let codingPlanModels = ["glm-5.3", "glm-5.3-flash"]

    /// 确保 models.json 含有目标模型的目录条目；已有文件则按 slug 合并。
    private func writeModelsCatalog(for account: ProviderAccount) throws {
        let isZhipu = account.baseURL.contains("bigmodel.cn") || account.baseURL.contains("z.ai")
        var wanted = isZhipu ? Self.codingPlanModels : [String]()
        if !wanted.contains(account.model) { wanted.append(account.model) }

        var models: [[String: Any]] = []
        if let data = try? Data(contentsOf: modelsURL),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let existing = root["models"] as? [[String: Any]] {
            models = existing
        }
        for slug in wanted where !models.contains(where: { $0["slug"] as? String == slug }) {
            models.append(Self.catalogEntry(slug: slug))
        }
        let root: [String: Any] = ["models": models]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: modelsURL, options: .atomic)
    }

    // MARK: - Remote catalog

    enum RemoteCatalogError: Error { case badResponse, notCatalog }

    /// 智谱的 GET {base_url}/models 直接返回 Codex 目录格式（含上下文窗口、
    /// 推理档位、输入模态等元数据），比本地模板更全更准。验证格式后原样写入 models.json。
    /// 返回写入的模型数；远端不支持或格式不符时抛错，调用方保留本地模板兜底。
    @discardableResult
    func refreshCatalogFromRemote(baseURL: String, apiKey: String) async throws -> Int {
        let data = try await Self.getModelsData(baseURL: baseURL, apiKey: apiKey)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]],
              !models.isEmpty,
              models.allSatisfy({ $0["slug"] is String }) else {
            throw RemoteCatalogError.notCatalog
        }
        try data.write(to: modelsURL, options: .atomic)
        return models.count
    }

    /// 只解析模型 slug 列表（表单下拉用），兼容 Codex 目录格式与 OpenAI 的 {data:[{id}]}。
    static func fetchModelSlugs(baseURL: String, apiKey: String) async throws -> [String] {
        let data = try await getModelsData(baseURL: baseURL, apiKey: apiKey)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RemoteCatalogError.badResponse
        }
        if let models = root["models"] as? [[String: Any]] {
            return models.compactMap { $0["slug"] as? String }
        }
        if let entries = root["data"] as? [[String: Any]] {
            return entries.compactMap { $0["id"] as? String }
        }
        throw RemoteCatalogError.notCatalog
    }

    private static func getModelsData(baseURL: String, apiKey: String) async throws -> Data {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + "/models") else { throw RemoteCatalogError.badResponse }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
            throw RemoteCatalogError.badResponse
        }
        return data
    }

    /// 智谱官方文档给出的 glm-5.3 目录条目模板，slug/display_name 按实际模型替换；
    /// glm-5.3-flash 为原生多模态，额外声明 image 输入。
    static func catalogEntry(slug: String) -> [String: Any] {
        let isFlash = slug.contains("flash")
        return [
            "slug": slug,
            "display_name": slug,
            "description": isFlash ? "GLM multimodal coding model" : "Z.ai's latest flagship model",
            "default_reasoning_level": "max",
            "supported_reasoning_levels": [
                ["effort": "low", "description": "Light reasoning"],
                ["effort": "high", "description": "Enhanced reasoning"],
                ["effort": "max", "description": "Deep reasoning"]
            ],
            "shell_type": "shell_command",
            "visibility": "list",
            "supported_in_api": true,
            "priority": 0,
            "base_instructions": "",
            "supports_reasoning_summaries": true,
            "default_reasoning_summary": "none",
            "support_verbosity": false,
            "apply_patch_tool_type": "freeform",
            "truncation_policy": ["mode": "bytes", "limit": 10000],
            "context_window": 1_048_576,
            "max_context_window": 1_048_576,
            "effective_context_window_percent": 95,
            "supports_parallel_tool_calls": true,
            "experimental_supported_tools": [String](),
            "input_modalities": isFlash ? ["text", "image"] : ["text"]
        ]
    }

    // MARK: - TOML helpers

    static func quoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    static func topLevelValue(for key: String, in text: String) -> String? {
        for line in topLevelLines(in: text) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"),
                  trimmed.hasPrefix("\(key)"),
                  let eq = trimmed.firstIndex(of: "=") else { continue }
            let head = String(trimmed[trimmed.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            guard head == key else { continue }
            var value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private static func topLevelLines(in text: String) -> [String] {
        var lines: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { break }
            lines.append(line)
        }
        return lines
    }

    /// 删除顶层（首个 [section] 之前）指定 key 的行。
    static func removeTopLevelKeys(_ keys: [String], from text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        var inTopLevel = true
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { inTopLevel = false }
            if inTopLevel,
               !trimmed.hasPrefix("#"),
               let eq = trimmed.firstIndex(of: "="),
               keys.contains(String(trimmed[trimmed.startIndex..<eq]).trimmingCharacters(in: .whitespaces)) {
                continue
            }
            result.append(line)
        }
        lines = result
        return lines.joined(separator: "\n")
    }

    /// 在顶层区末尾（首个 [section] 之前）插入键值行。
    static func insertTopLevelLines(_ newLines: [String], into text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        var insertIndex = lines.count
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                insertIndex = index
                break
            }
        }
        // 顶层区尾部空行留给段间分隔，键值行插到空行之前。
        while insertIndex > 0 && lines[insertIndex - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            insertIndex -= 1
        }
        lines.insert(contentsOf: newLines, at: insertIndex)
        return lines.joined(separator: "\n")
    }

    /// 删除整段 [name]（含子段如 [name.auth]）直到下一个不相关段或文件尾。
    static func removeSection(named name: String, from text: String) -> String {
        removeSections(where: { $0 == name || $0.hasPrefix("\(name).") }, from: text)
    }

    /// 按段名谓词删除整段（含子段）。
    static func removeSections(where shouldRemove: (String) -> Bool, from text: String) -> String {
        var result: [String] = []
        var skipping = false
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                let sectionName = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                skipping = shouldRemove(sectionName)
            }
            if !skipping { result.append(line) }
        }
        return result.joined(separator: "\n")
    }

    // MARK: - Backup

    private func backup(_ text: String, of url: URL, named base: String) throws {
        guard !text.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(base).bak-codexbar-provider-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8))")
        try writePrivate(text, to: backupURL)
    }

    private func writePrivate(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
