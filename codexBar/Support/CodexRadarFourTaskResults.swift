import Foundation

struct CodexRadarTestInterval: Decodable {
    let displayZH: String
    let displayEN: String

    enum CodingKeys: String, CodingKey {
        case displayZH = "display_zh"
        case displayEN = "display_en"
    }
}

/// The public dataset behind Codex Radar's current homepage intelligence table.
struct CodexRadarFourTaskResults: Decodable {
    let schema: String
    let scoreProtocol: String
    let roundID: String
    let scoreMax: Double
    let configurations: Int
    let models: [String]
    let modelEfforts: [String: [String]]
    let taskWeights: [String: Double]
    let authorTestInterval: CodexRadarTestInterval?
    let rows: [Row]

    enum CodingKeys: String, CodingKey {
        case schema, configurations, models, rows
        case scoreProtocol = "protocol"
        case roundID = "round_id"
        case scoreMax = "score_max"
        case modelEfforts = "model_efforts"
        case taskWeights = "task_weights"
        case authorTestInterval = "author_test_interval"
    }

    struct Row: Decodable {
        struct Visual: Decodable { let score: Double? }
        struct Pompeii: Decodable { let reward: Double? }
        struct Candy: Decodable { let correct: Bool? }

        let model: String
        let effort: String
        let combined: Visual?
        let pompeii: Pompeii?
        let pelican: Visual?
        let candy: Candy?

        var selection: CodexRadarSelection { .init(model: model, effort: effort) }
        var normalizedScores: [String: Double] {
            var scores: [String: Double] = [:]
            // Use the final capped score, never raw_score_total.
            scores["combined"] = combined?.score.map { $0 / 100 }
            scores["pompeii"] = pompeii?.reward
            scores["pelican"] = pelican?.score.map { $0 / 100 }
            scores["candy"] = candy?.correct.map { $0 ? 1 : 0 }
            return scores
        }
    }

    private var selections: [CodexRadarSelection] {
        models.flatMap { model in
            (modelEfforts[model] ?? []).map { CodexRadarSelection(model: model, effort: $0) }
        }
    }

    static func decode(_ data: Data) throws -> Self {
        let result = try JSONDecoder().decode(Self.self, from: data)
        let selections = result.selections
        let catalog = Set(selections)
        let taskKeys: Set<String> = ["combined", "pompeii", "pelican", "candy"]
        guard result.schema == "codex-four-task-results/1",
              result.scoreProtocol == "codex-four-weighted-150-v2",
              !result.roundID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              result.scoreMax == 150,
              result.configurations > 0, result.configurations == selections.count,
              catalog.count == selections.count,
              Set(result.models).count == result.models.count,
              Set(result.models) == Set(result.modelEfforts.keys),
              result.modelEfforts.values.allSatisfy({ !$0.isEmpty }),
              selections.allSatisfy({ !$0.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && !$0.effort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(result.taskWeights.keys) == taskKeys,
              result.taskWeights.values.allSatisfy({ $0.isFinite && $0 > 0 }),
              abs(result.taskWeights.values.reduce(0, +) - result.scoreMax) < 0.000001,
              Set(result.rows.map(\.selection)).count == result.rows.count,
              result.rows.allSatisfy({ catalog.contains($0.selection)
                  && $0.normalizedScores.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) }) else {
            throw CodexRadarError.invalidResponse
        }
        return result
    }

    var report: CodexRadarIntelligenceReport {
        let rowsBySelection = Dictionary(uniqueKeysWithValues: rows.map { ($0.selection, $0) })
        var incomplete = false
        let comparisons = selections.map { selection in
            let parts = rowsBySelection[selection]?.normalizedScores ?? [:]
            let complete = parts.count == taskWeights.count
            incomplete = incomplete || !complete
            // A missing grade makes the total unavailable; a real zero remains valid.
            let score = complete ? ["combined", "pompeii", "pelican", "candy"].reduce(0.0) {
                $0 + parts[$1]! * taskWeights[$1]!
            } : nil
            let entry = CodexRadarModelIQEntry(
                score: score, model: selection.model, reasoningEffort: selection.effort,
                coverage: parts.count, requiredTasks: taskWeights.count
            )
            return (selection.key, CodexRadarModelIQComparison(
                label: nil, model: selection.model, reasoningEffort: selection.effort, latest: entry
            ))
        }
        return CodexRadarIntelligenceReport(
            modelIQ: CodexRadarModelIQ(latest: nil, comparisons: Dictionary(uniqueKeysWithValues: comparisons)),
            selectionCount: selections.count, maximumScore: scoreMax,
            isPartial: incomplete, testInterval: authorTestInterval
        )
    }
}
