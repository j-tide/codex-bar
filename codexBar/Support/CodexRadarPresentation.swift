import Foundation

enum CodexRadarModelFamily: String, CaseIterable {
    case astra
    case terra
    case luna
    case sol
    case unknown

    var displayName: String? {
        switch self {
        case .astra:
            return "Astra"
        case .terra:
            return "Terra"
        case .luna:
            return "Luna"
        case .sol:
            return "Sol"
        case .unknown:
            return nil
        }
    }

    var symbolName: String {
        switch self {
        case .astra:
            return "sparkle"
        case .terra:
            return "globe.americas"
        case .luna:
            return "moon"
        case .sol:
            return "sun.max"
        case .unknown:
            return "cpu"
        }
    }

    nonisolated var sortOrder: Int {
        switch self {
        case .astra:
            return -1
        case .sol:
            return 0
        case .terra:
            return 1
        case .luna:
            return 2
        case .unknown:
            return 3
        }
    }

    static func resolve(model: String?, label: String?, id: String?) -> Self {
        let values = [model, label, id].compactMap { $0 }

        for family in [Self.astra, .terra, .luna, .sol] {
            if values.contains(where: { tokens(in: $0).contains(family.rawValue) }) {
                return family
            }
        }

        return .unknown
    }

    private static func tokens(in value: String) -> [String] {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}

struct CodexRadarMatrixColumn: Identifiable, Hashable {
    let id: String
    let label: String
    let sortOrder: Int
}

struct CodexRadarMatrixCell: Identifiable {
    let id: String
    let sourceID: String
    let rowID: String
    let rowName: String
    let family: CodexRadarModelFamily
    let effort: String
    let score: Double
    let entry: CodexRadarModelIQEntry

    var displayName: String {
        "\(rowName) \(effort)"
    }

    var passCountText: String? {
        guard let passed = entry.passed, let tasks = entry.tasks else { return nil }
        return "\(passed)/\(tasks)"
    }

    var coverageText: String? {
        guard let coverage = entry.coverage, let required = entry.requiredTasks else { return nil }
        return "\(coverage)/\(required)"
    }
}

struct CodexRadarMatrixRow: Identifiable {
    let id: String
    let displayName: String
    let family: CodexRadarModelFamily
    let cellsByEffort: [String: CodexRadarMatrixCell]

    func cell(for effort: String) -> CodexRadarMatrixCell? {
        cellsByEffort[effort]
    }
}

struct CodexRadarMatrix {
    let columns: [CodexRadarMatrixColumn]
    let rows: [CodexRadarMatrixRow]
    let rankedCellIDs: [String]

    var bestCellID: String? {
        rankedCellIDs.first
    }

    var cells: [CodexRadarMatrixCell] {
        let cellsByID = Dictionary(uniqueKeysWithValues: rows.flatMap { $0.cellsByEffort.values }.map { ($0.id, $0) })
        return rankedCellIDs.compactMap { cellsByID[$0] }
    }

    var signature: String {
        (columns.map(\.id) + rows.map(\.id) + cells
            .map { "\($0.id):\(CodexRadarPresentation.scoreText($0.score))" }
        ).joined(separator: "|")
    }

    func cell(id: String?) -> CodexRadarMatrixCell? {
        guard let id else { return nil }
        return cells.first { $0.id == id }
    }

    func rank(of cell: CodexRadarMatrixCell) -> Int? {
        guard let index = rankedCellIDs.firstIndex(of: cell.id) else { return nil }
        return index + 1
    }
}

enum CodexRadarPresentation {
    static let standardEfforts = ["low", "medium", "high", "xhigh", "max"]
    private static let rankingEfforts = ["ultra", "max", "xhigh", "high", "medium", "low", "off"]

    private static let effortLabels: [String: String] = [
        "max": "max",
        "xhigh": "xh",
        "high": "high",
        "medium": "med",
        "low": "low"
    ]

    nonisolated private static let effortOrder = Dictionary(
        uniqueKeysWithValues: rankingEfforts.enumerated().map { ($0.element, $0.offset) }
    )

    static func matrix(from modelIQ: CodexRadarModelIQ?) -> CodexRadarMatrix {
        guard let modelIQ else {
            return CodexRadarMatrix(columns: standardColumns, rows: [], rankedCellIDs: [])
        }

        var cellsByID: [String: CodexRadarMatrixCell] = [:]
        var rowMetadata: [String: (name: String, family: CodexRadarModelFamily)] = [:]
        var efforts = Set<String>()

        func include(sourceID: String, entry: CodexRadarModelIQEntry?, model: String?, effort: String?, label: String?, overwrite: Bool = false) {
            let normalizedEffort = normalizeEffort(effort ?? effortFromLabel(label)) ?? "default"
            let family = CodexRadarModelFamily.resolve(model: model, label: label, id: sourceID)
            let identity = rowIdentity(model: model, label: label, effort: normalizedEffort, family: family)
            rowMetadata[identity.id] = (identity.name, family)
            efforts.insert(normalizedEffort)
            guard let entry, let cell = makeCell(sourceID: sourceID, entry: entry, model: model, effort: normalizedEffort, label: label) else { return }
            if overwrite || cellsByID[cell.id] == nil { cellsByID[cell.id] = cell }
        }

        for sourceID in modelIQ.comparisons.keys.sorted() {
            guard let comparison = modelIQ.comparisons[sourceID] else { continue }
            include(
                sourceID: sourceID, entry: comparison.latest,
                model: comparison.model ?? comparison.latest?.model,
                effort: comparison.reasoningEffort ?? comparison.latest?.reasoningEffort,
                label: comparison.label
            )
        }

        if let latest = modelIQ.latest {
            include(sourceID: "latest", entry: latest, model: latest.model, effort: latest.reasoningEffort, label: nil, overwrite: true)
        }

        let extraEfforts = efforts
            .subtracting(standardEfforts)
            .sorted()
        let columns = standardColumns + extraEfforts.enumerated().map { index, effort in
            CodexRadarMatrixColumn(
                id: effort,
                label: effort,
                sortOrder: standardEfforts.count + index
            )
        }

        let groupedRows = Dictionary(grouping: cellsByID.values, by: \.rowID)
        let rows = rowMetadata.map { id, metadata in
            let cells = groupedRows[id] ?? []
            return CodexRadarMatrixRow(
                id: id,
                displayName: metadata.name,
                family: metadata.family,
                cellsByEffort: Dictionary(uniqueKeysWithValues: cells.map { ($0.effort, $0) })
            )
        }
        .sorted(by: rowOrderedBefore)

        let allCells = rows.flatMap { $0.cellsByEffort.values }
        let rankedCellIDs = allCells.sorted(by: cellOrderedBefore).map(\.id)

        return CodexRadarMatrix(columns: columns, rows: rows, rankedCellIDs: rankedCellIDs)
    }

    static func scoreText(_ score: Double) -> String {
        if abs(score - score.rounded()) < 0.0001 {
            return String(format: "%.0f", score)
        }
        return String(format: "%.1f", score)
    }

    static func scoreHelp(for cell: CodexRadarMatrixCell, rank: Int?) -> String {
        var lines = [cell.displayName,
                     "\(L.zh ? "原始分数" : "Raw score"): \(String(format: "%.2f", cell.score))"]
        if let rank {
            lines.append(L.zh ? "第 \(rank) 名" : "Rank \(rank)")
        }
        if let coverage = cell.coverageText {
            lines.append(L.zh ? "覆盖 \(coverage) 题" : "Coverage: \(coverage) tasks")
        }
        lines.append(L.zh
                     ? "排名使用未取整分数；表格显示整数，因此相同整数可能有不同名次。"
                     : "Ranks use unrounded scores. Equal displayed integers can have different ranks.")
        lines.append(L.radarBenchScoreMethod)
        return lines.joined(separator: "\n")
    }

    private static var standardColumns: [CodexRadarMatrixColumn] {
        standardEfforts.enumerated().map { index, effort in
            CodexRadarMatrixColumn(
                id: effort,
                label: effortLabels[effort] ?? effort,
                sortOrder: index
            )
        }
    }

    private static func makeCell(
        sourceID: String,
        entry: CodexRadarModelIQEntry,
        model: String?,
        effort: String?,
        label: String?
    ) -> CodexRadarMatrixCell? {
        guard let score = entry.score, score.isFinite, score >= 0 else { return nil }

        let normalizedEffort = normalizeEffort(effort ?? effortFromLabel(label)) ?? "default"
        let family = CodexRadarModelFamily.resolve(model: model, label: label, id: sourceID)
        let identity = rowIdentity(model: model, label: label, effort: normalizedEffort, family: family)

        return CodexRadarMatrixCell(
            id: CodexRadarSelection(model: identity.id, effort: normalizedEffort).key,
            sourceID: sourceID,
            rowID: identity.id,
            rowName: identity.name,
            family: family,
            effort: normalizedEffort,
            score: score,
            entry: entry
        )
    }

    private static func rowIdentity(
        model: String?,
        label: String?,
        effort: String,
        family: CodexRadarModelFamily
    ) -> (id: String, name: String) {
        let rawName = model?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? strippedModelName(from: label, effort: effort)
            ?? "Codex"
        let displayName = formattedModelName(rawName, family: family)
        let stableID = rawName.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return ("model:\(stableID)", displayName)
    }

    private static func formattedModelName(_ value: String, family: CodexRadarModelFamily) -> String {
        let normalized = value.replacingOccurrences(of: "_", with: "-")
        if let familyName = family.displayName {
            if normalized.lowercased() == family.rawValue { return familyName }
            let suffix = "-\(family.rawValue)"
            if normalized.lowercased().hasSuffix(suffix) {
                let version = String(normalized.dropLast(suffix.count))
                return formattedModelName(version, family: .unknown) + " " + familyName
            }
        }
        if normalized.lowercased().hasPrefix("gpt-") {
            return "GPT-" + normalized.dropFirst(4)
        }
        return normalized
    }

    private static func strippedModelName(from label: String?, effort: String) -> String? {
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else {
            return nil
        }
        let suffixes = [" \(effort)", "-\(effort)", "_\(effort)"]
        for suffix in suffixes where label.lowercased().hasSuffix(suffix.lowercased()) {
            return String(label.dropLast(suffix.count))
        }
        return label
    }

    private static func normalizeEffort(_ effort: String?) -> String? {
        guard let effort = effort?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !effort.isEmpty else {
            return nil
        }
        return effort
    }

    private static func effortFromLabel(_ label: String?) -> String? {
        guard let label else { return nil }
        return label
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split { !$0.isLetter && !$0.isNumber }
            .last
            .map(String.init)
    }

    nonisolated private static func rowOrderedBefore(
        _ lhs: CodexRadarMatrixRow,
        _ rhs: CodexRadarMatrixRow
    ) -> Bool {
        let leftVersion = lhs.displayName.split(separator: " ").first.map(String.init) ?? ""
        let rightVersion = rhs.displayName.split(separator: " ").first.map(String.init) ?? ""
        let leftIsGPT = leftVersion.hasPrefix("GPT-")
        let rightIsGPT = rightVersion.hasPrefix("GPT-")
        if leftIsGPT != rightIsGPT { return leftIsGPT }
        if leftIsGPT, leftVersion != rightVersion {
            return leftVersion.compare(rightVersion, options: .numeric) == .orderedDescending
        }
        if lhs.family.sortOrder != rhs.family.sortOrder {
            return lhs.family.sortOrder < rhs.family.sortOrder
        }
        let nameOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.id < rhs.id
    }

    nonisolated private static func cellOrderedBefore(
        _ lhs: CodexRadarMatrixCell,
        _ rhs: CodexRadarMatrixCell
    ) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }

        if lhs.family.sortOrder != rhs.family.sortOrder {
            return lhs.family.sortOrder < rhs.family.sortOrder
        }

        let leftEffort = effortOrder[lhs.effort] ?? Int.max
        let rightEffort = effortOrder[rhs.effort] ?? Int.max
        if leftEffort != rightEffort { return leftEffort < rightEffort }

        let nameOrder = lhs.rowName.localizedCaseInsensitiveCompare(rhs.rowName)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.sourceID < rhs.sourceID
    }
}
