import Foundation
import XCTest
@testable import codexAppBar

final class CodexSidebarOrderTests: XCTestCase {
    func testSidebarUsesPinnedProjectAndManualTaskOrder() throws {
        let metadata = items()
        let state: [String: Any] = [
            "pinned-thread-ids": ["old"], "project-order": ["p2", "p1"],
            "thread-project-assignments": [
                "new": ["projectId": "p1"], "middle": ["projectId": "p2"],
                "manual": ["projectId": "p2"], "old": ["projectId": "p1"]
            ],
            "sidebar-project-thread-orders": ["p2": ["threadIds": ["manual", "middle"], "sortKey": "updated_at"]],
            "electron-persisted-atom-state": ["flat-project-sidebar-preferences-v1": [
                "mode": "project", "projectSortMode": "priority", "chatSortMode": "updated_at"
            ]]
        ]
        XCTAssertEqual(try order(metadata, state), ["old", "manual", "middle", "new"])
    }

    func testFlatModeUsesCodexRecencyInsteadOfProjectOrder() throws {
        XCTAssertEqual(try order(items(), ["project-order": ["p2", "p1"]]), ["new", "middle", "manual", "old"])
    }

    func testMalformedPreferencesFallBackToRecency() {
        let result = CodexSidebarOrder.applying(to: items(), stateData: Data("{partial".utf8))
        XCTAssertEqual(names(result), ["new", "middle", "manual", "old"])
    }

    func testProjectRootMatchingRespectsDirectoryBoundariesAndProjectlessOverrides() throws {
        var metadata = items()
        metadata[CodexTaskMetadata.taskKey(for: "new")]?.cwd = "/repo/foobar"
        metadata[CodexTaskMetadata.taskKey(for: "old")]?.cwd = "/repo/foo/subdir"
        let state: [String: Any] = [
            "local-projects": ["p1": ["rootPaths": ["/repo/foo"]]],
            "project-order": ["p1"], "projectless-thread-ids": ["middle", "manual"],
            "electron-persisted-atom-state": ["flat-project-sidebar-preferences-v1": ["mode": "project"]]
        ]
        XCTAssertEqual(try order(metadata, state), ["old", "new", "middle", "manual"])
    }

    func testProjectLabelsUseSavedNamesAndRespectProjectlessOverride() throws {
        var metadata = items()
        metadata[CodexTaskMetadata.taskKey(for: "old")]?.cwd = "/repo/foo/subdir"
        metadata[CodexTaskMetadata.taskKey(for: "middle")]?.cwd = "/repo/foo"
        metadata[CodexTaskMetadata.taskKey(for: "manual")]?.cwd = "/tmp/worktree/random"
        metadata[CodexTaskMetadata.taskKey(for: "new")]?.cwd = "/repo/foobar"
        let state: [String: Any] = [
            "local-projects": ["p1": ["name": "My saved project", "rootPaths": ["/repo/foo"]]],
            "thread-project-assignments": ["manual": ["projectId": "p1"], "middle": ["projectId": "p1"]],
            "projectless-thread-ids": ["middle"]
        ]
        let result = CodexSidebarOrder.applying(to: metadata, stateData: try JSONSerialization.data(withJSONObject: state))
        XCTAssertEqual(result[CodexTaskMetadata.taskKey(for: "old")]?.projectName, "My saved project")
        XCTAssertEqual(result[CodexTaskMetadata.taskKey(for: "manual")]?.projectName, "My saved project")
        XCTAssertNil(result[CodexTaskMetadata.taskKey(for: "middle")]?.projectName)
        XCTAssertNil(result[CodexTaskMetadata.taskKey(for: "new")]?.projectName)
    }

    private func items() -> [String: CodexTaskMetadata] {
        Dictionary(uniqueKeysWithValues: ["old", "manual", "middle", "new"].enumerated().map { index, id in
            (CodexTaskMetadata.taskKey(for: id), CodexTaskMetadata(threadID: id, title: id, recency: Double(index)))
        })
    }
    private func names(_ items: [String: CodexTaskMetadata]) -> [String] {
        items.values.sorted { $0.sidebarPosition! < $1.sidebarPosition! }.map(\.threadID)
    }
    private func order(_ metadata: [String: CodexTaskMetadata], _ state: [String: Any]) throws -> [String] {
        names(CodexSidebarOrder.applying(to: metadata, stateData: try JSONSerialization.data(withJSONObject: state)))
    }
}
