import Combine
import Foundation

@MainActor
final class CodexRadarService: ObservableObject {
    static let shared = CodexRadarService()

    @Published private(set) var intelligence: CodexRadarIntelligenceReport?
    @Published private(set) var snapshot: CodexRadarSnapshot?
    @Published private(set) var lastFetchAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    private let statusURL = URL(string: "https://codexradar.com/current.json")!
    private let websiteURL = URL(string: "https://codexradar.com/")!
    private let refreshInterval: TimeInterval = 15 * 60
    private var timer: Timer?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    var homepageURL: URL { websiteURL }

    var needsVisibleRefresh: Bool {
        guard !isRefreshing else { return false }
        guard let lastFetchAt else { return true }
        return Date().timeIntervalSince(lastFetchAt) >= refreshInterval
    }

    func start(runImmediately: Bool = true) {
        guard timer == nil else { return }
        if runImmediately {
            Task { await refresh() }
        }
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Reset windows and intelligence scores have independent availability.
        async let reset: () = refreshResetWindow()
        async let quality: () = refreshIntelligence()
        _ = await (reset, quality)
    }

    private func refreshResetWindow() async {
        do {
            let data = try await fetch(statusURL)
            snapshot = try Self.decoder.decode(CodexRadarSnapshot.self, from: data)
        } catch {
            // A failed reset check must not prevent the quality leaderboard loading.
        }
    }

    private func refreshIntelligence() async {
        do {
            let bindingData = try await fetch(URL(string: "https://codexradar.com/data/radar-bench-binding.json")!)
            let binding = try CodexRadarBenchBinding.decode(bindingData)
            var summaries: [CodexRadarSelection: CodexRadarBenchSummary] = [:]
            var firstError: Error?
            await withTaskGroup(of: (CodexRadarSelection, Result<Data, Error>).self) { group in
                for selection in binding.selections {
                    var url = URLComponents(string: "https://codexradar.com/api/radar-bench-score")!
                    url.queryItems = [
                        URLQueryItem(name: "model", value: selection.model),
                        URLQueryItem(name: "effort", value: selection.effort),
                        URLQueryItem(name: "view", value: "summary")
                    ]
                    let requestURL = url.url!
                    group.addTask { (selection, await self.fetchQualityData(requestURL)) }
                }
                for await (selection, result) in group {
                    do {
                        summaries[selection] = try CodexRadarBenchSummary.decode(
                            result.get(), binding: binding, selection: selection
                        )
                    } catch {
                        if firstError == nil { firstError = error }
                    }
                }
            }
            guard !summaries.isEmpty else { throw firstError ?? CodexRadarError.modelQualityUnavailable }
            intelligence = CodexRadarIntelligenceReport(binding: binding, summaries: summaries)
            lastFetchAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func fetchQualityData(_ url: URL) async -> Result<Data, Error> {
        do { return .success(try await fetch(url)) }
        catch { return .failure(error) }
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexRadarError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CodexRadarError.httpStatus(http.statusCode)
        }
        let cache = http.value(forHTTPHeaderField: "X-Radar-Bench-Cache") ?? ""
        if cache.hasPrefix("STALE") || cache == "ERROR" {
            throw CodexRadarError.staleResponse
        }
        return data
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = DateFormatters.iso8601WithFractionalSeconds.date(from: value)
                ?? DateFormatters.iso8601.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid CodexRadar date: \(value)"
            )
        }
        return decoder
    }()
}

enum CodexRadarError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case modelQualityUnavailable
    case staleResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return L.zh ? "CodexRadar 响应无效" : "Invalid CodexRadar response"
        case .httpStatus(let status):
            return L.zh ? "CodexRadar 服务暂不可用 (HTTP \(status))" : "CodexRadar unavailable (HTTP \(status))"
        case .staleResponse:
            return L.zh ? "数据源暂未更新，请稍后重试" : "Source data is stale. Try again later."
        case .modelQualityUnavailable:
            return L.zh ? "CodexRadar 暂无可用评分数据" : "CodexRadar model quality is unavailable"
        }
    }
}

private enum DateFormatters {
    static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct CodexRadarSnapshot: Decodable {
    let monitoredAt: Date?
    let windowOpen: Bool?
    let status: String?
    let window: CodexRadarResetWindow?
    var modelIQ: CodexRadarModelIQ?

    enum CodingKeys: String, CodingKey {
        case monitoredAt = "monitored_at"
        case windowOpen = "window_open"
        case status
        case window
        case modelIQ = "model_iq"
    }
}

struct CodexRadarResetWindow: Decodable {
    let open: Bool?
    let status: String?
    let message: String?
    let openedAt: Date?
    let closedAt: Date?
    let sourceURL: URL?

    enum CodingKeys: String, CodingKey {
        case open
        case status
        case message
        case openedAt = "opened_at"
        case closedAt = "closed_at"
        case sourceURL = "source_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        open = try container.decodeIfPresent(Bool.self, forKey: .open)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        openedAt = try container.decodeIfPresent(Date.self, forKey: .openedAt)
        closedAt = try container.decodeIfPresent(Date.self, forKey: .closedAt)

        if let rawSourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL) {
            sourceURL = URL(string: rawSourceURL)
        } else {
            sourceURL = nil
        }
    }

    var isOpen: Bool {
        if let open { return open }
        return status?.lowercased() == "open"
    }

    var expectedResetAt: Date? {
        if let closedAt { return closedAt }
        return openedAt?.addingTimeInterval(24 * 60 * 60)
    }
}

struct CodexRadarModelIQ: Decodable {
    let latest: CodexRadarModelIQEntry?
    let comparisons: [String: CodexRadarModelIQComparison]

    enum CodingKeys: String, CodingKey {
        case latest
        case comparisons
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latest = try container.decodeIfPresent(CodexRadarModelIQEntry.self, forKey: .latest)
        comparisons = try container.decodeIfPresent([String: CodexRadarModelIQComparison].self, forKey: .comparisons) ?? [:]
    }

    init(latest: CodexRadarModelIQEntry?, comparisons: [String: CodexRadarModelIQComparison]) {
        self.latest = latest
        self.comparisons = comparisons
    }
}

struct CodexRadarModelIQComparison: Decodable {
    let label: String?
    let model: String?
    let reasoningEffort: String?
    let latest: CodexRadarModelIQEntry?

    enum CodingKeys: String, CodingKey {
        case label
        case model
        case reasoningEffort = "reasoning_effort"
        case latest
    }

    init(label: String?, model: String?, reasoningEffort: String?, latest: CodexRadarModelIQEntry?) {
        self.label = label
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.latest = latest
    }
}

struct CodexRadarModelIQEntry: Decodable {
    let date: String?
    let score: Double?
    let status: String?
    let passed: Int?
    let tasks: Int?
    let model: String?
    let reasoningEffort: String?
    let coverage: Int?
    let requiredTasks: Int?

    enum CodingKeys: String, CodingKey {
        case date
        case score
        case status
        case passed
        case tasks
        case model
        case reasoningEffort = "reasoning_effort"
        case coverage
        case requiredTasks = "required_tasks"
    }

    init(
        date: String? = nil,
        score: Double? = nil,
        status: String? = nil,
        passed: Int? = nil,
        tasks: Int? = nil,
        model: String? = nil,
        reasoningEffort: String? = nil,
        coverage: Int? = nil,
        requiredTasks: Int? = nil
    ) {
        self.date = date
        self.score = score
        self.status = status
        self.passed = passed
        self.tasks = tasks
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.coverage = coverage
        self.requiredTasks = requiredTasks
    }
}
