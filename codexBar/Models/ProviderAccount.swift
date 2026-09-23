import Combine
import Darwin
import Foundation

/// 第三方 Responses API Key 账号（智谱 GLM 等）。
/// 与 OAuth 的 TokenAccount 走完全不同的通道：激活 = 写 ~/.codex/config.toml，
/// 不涉及 auth.json，也没有 ChatGPT 额度窗口。
/// 这份配置只对终端 codex CLI 生效；Codex 桌面端固定走 ChatGPT 账号。
struct ProviderAccount: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String          // 显示名，如「智谱 GLM」
    var providerKey: String   // config.toml 中 [model_providers.<key>] 的段名
    var baseURL: String
    var apiKey: String
    var model: String         // 如 glm-5.3
    /// 接口协议。旧数据无此字段时按 responses 处理；chat 仅用于识别旧账号并阻止激活。
    var wireAPI: String?
    var createdAt: Date

    init(id: UUID = UUID(), name: String, providerKey: String = "ZAI",
         baseURL: String, apiKey: String, model: String, wireAPI: String? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.providerKey = ProviderAccount.sanitizedProviderKey(providerKey)
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.wireAPI = wireAPI
        self.createdAt = createdAt
    }

    /// config.toml 里实际写入的 wire_api 值。
    var resolvedWireAPI: String { wireAPI == "chat" ? "chat" : "responses" }

    /// TOML 裸键只允许 ASCII 字母数字、下划线、连字符；其余字符剔除，首尾连字符裁掉。
    static func sanitizedProviderKey(_ raw: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        let cleaned = String(raw.unicodeScalars.filter { allowed.contains($0) })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return cleaned.isEmpty ? "ZAI" : cleaned
    }

    static func isValidProviderKey(_ raw: String) -> Bool {
        !raw.isEmpty && sanitizedProviderKey(raw) == raw
            && !["openai", "ollama", "lmstudio"].contains(raw.lowercased())
    }

    var maskedKey: String {
        guard apiKey.count > 8 else { return String(repeating: "•", count: apiKey.count) }
        return "\(apiKey.prefix(4))…\(apiKey.suffix(4))"
    }
}

/// 常用服务商预设，录入表单里一键填充。
struct ProviderPreset: Equatable, Sendable {
    let id: String
    let displayName: String
    let providerKey: String
    let baseURL: String
    let defaultModel: String
    let wireAPI: String

    static let zhipuCN = ProviderPreset(
        id: "zhipu-cn", displayName: "智谱 GLM（国内）", providerKey: "ZAI",
        baseURL: "https://open.bigmodel.cn/api/v1", defaultModel: "glm-5.3",
        wireAPI: "responses"
    )
    static let zaiGlobal = ProviderPreset(
        id: "zai-global", displayName: "Z.AI（海外）", providerKey: "ZAI",
        baseURL: "https://api.z.ai/api/v1", defaultModel: "glm-5.3",
        wireAPI: "responses"
    )
    static let custom = ProviderPreset(
        id: "custom", displayName: "自定义", providerKey: "ZAI",
        baseURL: "", defaultModel: "", wireAPI: "responses"
    )

    static let all: [ProviderPreset] = [zhipuCN, zaiGlobal, custom]

    static func match(baseURL: String) -> ProviderPreset? {
        all.first { $0.id != "custom" && $0.baseURL == baseURL }
    }
}

@MainActor
final class ProviderAccountStore: ObservableObject {
    static let shared = ProviderAccountStore()

    @Published private(set) var accounts: [ProviderAccount] = []
    /// 当前 config.toml 里生效的 provider 段名；nil = 官方 OpenAI 通道。
    @Published private(set) var activeProviderKey: String?
    /// 表单是否展开（面板高度计算需要）。
    @Published var isEditingForm = false
    /// 首次切到 provider 前备份的官方 model 值，切回时还原。
    private(set) var officialModelBackup: String?

    private let storeURL: URL
    private let configService: CodexProviderConfigService

    private struct PersistedState: Codable {
        var accounts: [ProviderAccount]
        var officialModelBackup: String?
    }

    private convenience init() {
        let realHome: URL
        if let pw = getpwuid(getuid()), let pwDir = pw.pointee.pw_dir {
            realHome = URL(fileURLWithPath: String(cString: pwDir))
        } else {
            realHome = FileManager.default.homeDirectoryForCurrentUser
        }
        let codexURL = realHome.appendingPathComponent(".codex", isDirectory: true)
        let dir = codexURL.appendingPathComponent("codexbar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        self.init(
            storeURL: dir.appendingPathComponent("provider_accounts.json"),
            configService: CodexProviderConfigService(
                configURL: codexURL.appendingPathComponent("config.toml"),
                modelsURL: codexURL.appendingPathComponent("models.json")
            )
        )
    }

    init(storeURL: URL, configService: CodexProviderConfigService) {
        self.storeURL = storeURL
        self.configService = configService
        load()
        refreshActiveState()
    }

    // MARK: - Persistence

    func load() {
        if FileManager.default.fileExists(atPath: storeURL.path) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
        }
        guard let data = try? Data(contentsOf: storeURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        accounts = state.accounts
        officialModelBackup = state.officialModelBackup
    }

    private func save() {
        let state = PersistedState(accounts: accounts, officialModelBackup: officialModelBackup)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: storeURL.deletingLastPathComponent().path)
        guard (try? data.write(to: storeURL, options: .atomic)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
    }

    // MARK: - CRUD

    @discardableResult
    func upsert(_ account: ProviderAccount) -> ProviderAccount {
        var account = account
        account.providerKey = ProviderAccount.sanitizedProviderKey(account.providerKey)
        // providerKey 在 config.toml 里对应唯一段落，同 key 视为同一条目。
        if let index = accounts.firstIndex(where: { $0.id == account.id || $0.providerKey == account.providerKey }) {
            account.id = accounts[index].id
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        save()
        return account
    }

    func remove(_ account: ProviderAccount) {
        accounts.removeAll { $0.id == account.id }
        save()
    }

    // MARK: - Activation

    var activeAccount: ProviderAccount? {
        guard let key = activeProviderKey else { return nil }
        return accounts.first { $0.providerKey == key }
    }

    func refreshActiveState() {
        activeProviderKey = configService.activeProviderKey()
    }

    /// 写入 config.toml / models.json 使 Codex CLI 指向该 provider。
    /// 注意：Codex 桌面端不读取此配置，UI 层负责向用户提示这一限制。
    func activate(_ account: ProviderAccount) throws {
        // 首次从官方通道切出时，记下官方 model 以便切回。
        if configService.activeProviderKey() == nil, officialModelBackup == nil {
            officialModelBackup = configService.currentModel()
            save()
        }
        try configService.activate(account)
        refreshActiveState()
        // GET /models 若返回 Codex 目录格式，则用真实元数据替换本地模板。
        Task { [configService] in
            try? await configService.refreshCatalogFromRemote(baseURL: account.baseURL, apiKey: account.apiKey)
        }
    }

    /// 恢复官方 OpenAI 通道：移除 provider 覆盖并还原官方 model。
    func deactivateProvider() throws {
        try configService.deactivate(restoreModel: officialModelBackup)
        officialModelBackup = nil
        save()
        refreshActiveState()
    }
}
