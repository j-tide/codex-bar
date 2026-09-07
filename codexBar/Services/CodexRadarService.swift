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
            async let softwareData = fetch(URL(string: "https://codexradar.com/api/intelligence-efficiency-metrics")!, requireCurrent: true)
            async let visualData = fetch(URL(string: "https://codexradar.com/api/visual-spatial-reasoning")!, requireCurrent: true)
            let report = try await CodexRadarIntelligenceReport.decode(software: softwareData, visual: visualData)
            intelligence = report
            lastFetchAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func fetch(_ url: URL, requireCurrent: Bool = false) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw CodexRadarError.invalidResponse
        }
        if requireCurrent {
            let cache = http.value(forHTTPHeaderField: "X-Codex-Cache") ?? ""
            guard !cache.isEmpty, !cache.hasPrefix("STALE"), cache != "ERROR" else {
                throw CodexRadarError.staleResponse
            }
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
    case modelQualityUnavailable
    case staleResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return L.zh ? "CodexRadar 响应无效" : "Invalid CodexRadar response"
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

    enum CodingKeys: String, CodingKey {
        case date
        case score
        case status
        case passed
        case tasks
        case model
        case reasoningEffort = "reasoning_effort"
    }

    init(
        date: String? = nil,
        score: Double? = nil,
        status: String? = nil,
        passed: Int? = nil,
        tasks: Int? = nil,
        model: String? = nil,
        reasoningEffort: String? = nil
    ) {
        self.date = date
        self.score = score
        self.status = status
        self.passed = passed
        self.tasks = tasks
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
}

// Mirrors codexradar.com's comprehensive score: weight both dimensions by valid tasks.
enum CodexRadarDimension: String, CaseIterable, Identifiable {
    case comprehensive, software, visual

    var id: String { rawValue }
    var title: String {
        switch self {
        case .comprehensive: return L.zh ? "综合智能" : "Overall"
        case .software: return L.zh ? "软件工程" : "Coding"
        case .visual: return L.zh ? "空间推理" : "Spatial"
        }
    }
}

struct CodexRadarMetricsPayload: Decodable {
    let schema: Int
    let mode: String
    let type: String?
    let sourceUpdatedAt: String?
    let points: [Point]

    enum CodingKeys: String, CodingKey {
        case schema, mode, type, points
        case sourceUpdatedAt = "source_updated_at"
    }

    struct Point: Decodable {
        let model: String
        let effort: String
        let iq: Double?
        let total: Double?
        let weightedTotal: Double?
        let validTasks: Double?

        enum CodingKeys: String, CodingKey {
            case model, effort, iq, total
            case weightedTotal = "weighted_total"
            case validTasks = "valid_tasks"
        }

        var key: String { "\(model)|\(effort)" }
    }
}

struct CodexRadarIntelligenceReport {
    let software: CodexRadarMetricsPayload
    let visual: CodexRadarMetricsPayload

    static func decode(software: Data, visual: Data) throws -> Self {
        let decoder = JSONDecoder()
        let report = try Self(
            software: decoder.decode(CodexRadarMetricsPayload.self, from: software),
            visual: decoder.decode(CodexRadarMetricsPayload.self, from: visual)
        )
        guard (report.software.schema == 3 && report.software.mode == "equal_latest_3"
                || report.software.schema == 2 && report.software.mode == "weighted_latest_3"),
              report.visual.type == "visual_spatial_reasoning_summary",
              !report.modelIQ(for: .comprehensive).comparisons.isEmpty else {
            throw CodexRadarError.modelQualityUnavailable
        }
        return report
    }

    func updatedAt(for dimension: CodexRadarDimension) -> Date? {
        let softwareDate = Self.date(software.sourceUpdatedAt)
        let visualDate = Self.date(visual.sourceUpdatedAt)
        switch dimension {
        case .software: return softwareDate
        case .visual: return visualDate
        case .comprehensive:
            guard let softwareDate, let visualDate else { return nil }
            return min(softwareDate, visualDate)
        }
    }

    func modelIQ(for dimension: CodexRadarDimension) -> CodexRadarModelIQ {
        let softwarePoints = validPoints(software, isSoftware: true)
        let visualPoints = validPoints(visual, isSoftware: false)
        var comparisons: [String: CodexRadarModelIQComparison] = [:]
        let points = dimension == .visual ? visualPoints : softwarePoints
        for (key, point) in points {
            guard let iq = point.iq else { continue }
            var score = iq
            if dimension == .comprehensive {
                guard let other = visualPoints[key], let visualIQ = other.iq else { continue }
                let softwareWeight = max(1, weight(point, isSoftware: true))
                let visualWeight = max(1, weight(other, isSoftware: false))
                score = (iq * softwareWeight + visualIQ * visualWeight) / (softwareWeight + visualWeight)
            }
            let entry = CodexRadarModelIQEntry(score: score, model: point.model, reasoningEffort: point.effort)
            comparisons[key] = CodexRadarModelIQComparison(
                label: nil, model: point.model, reasoningEffort: point.effort, latest: entry
            )
        }
        return CodexRadarModelIQ(latest: nil, comparisons: comparisons)
    }

    private func validPoints(_ payload: CodexRadarMetricsPayload, isSoftware: Bool) -> [String: CodexRadarMetricsPayload.Point] {
        var result: [String: CodexRadarMetricsPayload.Point] = [:]
        for point in payload.points {
            // The app's quality section covers Codex models, as in the reference board.
            guard point.model.hasPrefix("gpt-"), !point.effort.isEmpty,
                  let iq = point.iq, iq.isFinite, iq >= 0,
                  weight(point, isSoftware: isSoftware) > 0 else { continue }
            result[point.key] = point
        }
        return result
    }

    private func weight(_ point: CodexRadarMetricsPayload.Point, isSoftware: Bool) -> Double {
        if isSoftware { return (software.schema == 2 ? point.weightedTotal : point.total) ?? 0 }
        return point.validTasks ?? 0
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return DateFormatters.iso8601WithFractionalSeconds.date(from: value) ?? DateFormatters.iso8601.date(from: value)
    }
}
