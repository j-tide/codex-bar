import Foundation

/// Read-only projection of the local Codex sidebar preferences. Never writes Codex state.
enum CodexSidebarOrder {
    nonisolated static func applying(to metadata: [String: CodexTaskMetadata], stateData: Data?) -> [String: CodexTaskMetadata] {
        let state = stateData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let atoms = state["electron-persisted-atom-state"] as? [String: Any] ?? [:]
        let preferences = atoms["flat-project-sidebar-preferences-v1"] as? [String: Any] ?? [:]
        let grouped = preferences["mode"] as? String == "project"
        let projectMode = preferences["projectSortMode"] as? String ?? "priority"
        let chatMode = preferences["chatSortMode"] as? String ?? "updated_at"
        let pins = state["pinned-thread-ids"] as? [String] ?? []
        let projectOrder = state["project-order"] as? [String] ?? []
        let assignments = state["thread-project-assignments"] as? [String: [String: Any]] ?? [:]
        let projects = state["local-projects"] as? [String: [String: Any]] ?? [:]
        let projectless = Set(state["projectless-thread-ids"] as? [String] ?? [])
        let manualOrders = state["sidebar-project-thread-orders"] as? [String: [String: Any]] ?? [:]

        func project(_ item: CodexTaskMetadata) -> String? {
            if projectless.contains(item.threadID) { return nil }
            if let explicit = assignments[item.threadID]?["projectId"] as? String { return explicit }
            guard let cwd = item.cwd else { return nil }
            var matches: [(id: String, length: Int)] = []
            for (id, value) in projects {
                for root in value["rootPaths"] as? [String] ?? [] {
                    if cwd == root || cwd.hasPrefix(root + "/") { matches.append((id, root.count)) }
                }
            }
            matches.sort { $0.length == $1.length ? $0.id < $1.id : $0.length > $1.length }
            return matches.first?.id
        }
        let groups = Dictionary(uniqueKeysWithValues: metadata.values.map { ($0.threadID, project($0) ?? "") })
        let groupRecency = Dictionary(grouping: metadata.values, by: { groups[$0.threadID] ?? "" })
            .mapValues { $0.map(\.recency).max() ?? 0 }

        func position(_ id: String, in values: [String]) -> Int { values.firstIndex(of: id) ?? Int.max }
        func manualPosition(_ item: CodexTaskMetadata, group: String) -> Int {
            guard let order = manualOrders[group],
                  order["sortKey"] as? String == chatMode || order["sortKey"] == nil else { return Int.max }
            return position(item.threadID, in: order["threadIds"] as? [String] ?? [])
        }
        let ordered = metadata.values.sorted { left, right in
            let lp = position(left.threadID, in: pins), rp = position(right.threadID, in: pins)
            if lp != rp { return lp < rp }
            let lg = groups[left.threadID] ?? "", rg = groups[right.threadID] ?? ""
            if grouped, lg != rg {
                if lg.isEmpty != rg.isEmpty { return !lg.isEmpty }
                if projectMode == "updated_at", groupRecency[lg] != groupRecency[rg] {
                    return (groupRecency[lg] ?? 0) > (groupRecency[rg] ?? 0)
                }
                let li = position(lg, in: projectOrder), ri = position(rg, in: projectOrder)
                if li != ri { return li < ri }
                return lg < rg
            }
            if grouped {
                let li = manualPosition(left, group: lg), ri = manualPosition(right, group: rg)
                if li != ri { return li < ri }
            }
            if left.recency != right.recency { return left.recency > right.recency }
            if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
            return left.threadID > right.threadID
        }
        var result = metadata
        for (position, item) in ordered.enumerated() {
            let key = CodexTaskMetadata.taskKey(for: item.threadID)
            result[key]?.sidebarPosition = position
            let name = groups[item.threadID].flatMap { projects[$0]?["name"] as? String }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            result[key]?.projectName = name.flatMap { $0.isEmpty ? nil : $0 }
        }
        return result
    }
}
