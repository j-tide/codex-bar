import Foundation

struct CodexRadarSelection: Decodable, Hashable {
    let model: String
    let effort: String

    var key: String { "\(model.utf8.count):\(model)\(effort.utf8.count):\(effort)" }
}

struct CodexRadarBenchBinding: Decodable {
    let enabled: Bool
    let interfaceConfirmed: Bool
    let productionReadVerified: Bool
    let benchmark: String
    let catalogVersion: String
    let taskSetSHA256: String
    let totalTasks: Int
    let sourceCounts: [String: Int]
    let selections: [CodexRadarSelection]

    enum CodingKeys: String, CodingKey {
        case enabled, benchmark
        case interfaceConfirmed = "interface_confirmed"
        case productionReadVerified = "production_read_verified"
        case catalogVersion = "catalog_version"
        case taskSetSHA256 = "task_set_sha256"
        case totalTasks = "total_tasks"
        case sourceCounts = "source_counts"
        case selections = "model_efforts"
    }

    static func decode(_ data: Data) throws -> Self {
        let binding = try JSONDecoder().decode(Self.self, from: data)
        guard binding.enabled, binding.interfaceConfirmed, binding.productionReadVerified,
              !binding.benchmark.isEmpty, !binding.catalogVersion.isEmpty,
              binding.taskSetSHA256.count == 64,
              binding.taskSetSHA256.allSatisfy({ $0.isHexDigit }),
              binding.totalTasks > 0, !binding.sourceCounts.isEmpty,
              binding.sourceCounts.values.allSatisfy({ $0 >= 0 }),
              binding.sourceCounts.values.reduce(0, +) == binding.totalTasks,
              !binding.selections.isEmpty,
              Set(binding.selections).count == binding.selections.count,
              binding.selections.allSatisfy({ !$0.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && !$0.effort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw CodexRadarError.invalidResponse
        }
        return binding
    }
}

struct CodexRadarBenchSummary: Decodable {
    let schema: String
    let benchmark: String
    let scoreVersion: String
    let catalogVersion: String
    let taskSetSHA256: String
    let model: String
    let effort: String
    let score: Double?
    let coverage: Int
    let requiredTasks: Int
    let scoreStatus: String
    let sourceCounts: [String: Int]
    let scoringPolicyVersion: String

    enum CodingKeys: String, CodingKey {
        case schema, benchmark, model, effort, score, coverage
        case scoreVersion = "score_version"
        case catalogVersion = "catalog_version"
        case taskSetSHA256 = "task_set_sha256"
        case requiredTasks = "required_tasks"
        case scoreStatus = "score_status"
        case sourceCounts = "source_counts"
        case scoringPolicyVersion = "scoring_policy_version"
    }

    static func decode(_ data: Data, binding: CodexRadarBenchBinding, selection: CodexRadarSelection) throws -> Self {
        let summary = try JSONDecoder().decode(Self.self, from: data)
        let expectedStatus = summary.coverage == 0 ? "missing_current_result"
            : summary.coverage == binding.totalTasks ? "complete" : "provisional"
        guard summary.schema == "radar-bench-public-summary-v1",
              summary.scoreVersion == "radar-bench-v1",
              summary.scoringPolicyVersion == "radar-bench-v1-last3-per-task-equal-weight-100",
              summary.benchmark == binding.benchmark,
              summary.catalogVersion == binding.catalogVersion,
              summary.taskSetSHA256 == binding.taskSetSHA256,
              binding.selections.contains(selection),
              summary.model == selection.model, summary.effort == selection.effort,
              summary.requiredTasks == binding.totalTasks,
              (0...binding.totalTasks).contains(summary.coverage),
              summary.sourceCounts == binding.sourceCounts,
              summary.scoreStatus == expectedStatus else {
            throw CodexRadarError.invalidResponse
        }
        if summary.coverage == 0 {
            guard summary.score == nil else { throw CodexRadarError.invalidResponse }
        } else {
            guard let score = summary.score, score.isFinite, (0...100).contains(score) else {
                throw CodexRadarError.invalidResponse
            }
        }
        return summary
    }
}

struct CodexRadarIntelligenceReport {
    let binding: CodexRadarBenchBinding
    let summaries: [CodexRadarSelection: CodexRadarBenchSummary]

    var isPartial: Bool { summaries.count < binding.selections.count }

    var modelIQ: CodexRadarModelIQ {
        let comparisons = binding.selections.map { selection in
            let summary = summaries[selection]
            let entry = CodexRadarModelIQEntry(
                score: summary?.score, model: selection.model, reasoningEffort: selection.effort,
                coverage: summary?.coverage, requiredTasks: binding.totalTasks
            )
            return (selection.key, CodexRadarModelIQComparison(
                label: nil, model: selection.model, reasoningEffort: selection.effort, latest: entry
            ))
        }
        return CodexRadarModelIQ(latest: nil, comparisons: Dictionary(uniqueKeysWithValues: comparisons))
    }
}
