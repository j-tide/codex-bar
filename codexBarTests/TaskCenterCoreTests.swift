import AppKit
import UserNotifications
import XCTest
@testable import codexAppBar

@MainActor
final class TaskCenterCoreTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 2_000_000_000)

    func testCachedRecordDetectsReplacementEvenWithUnchangedModificationDate() throws {
        let fixture = try Fixture(now: fixedNow)
        defer { fixture.remove() }
        let running = record(key: "cached", state: .running, phase: .processing, age: 0)
        let file = try fixture.write(running)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual(fixture.repository.load().records, [running])
        XCTAssertEqual(fixture.repository.load().records, [running])
        let completed = record(key: "cached", state: .ready, phase: .waitingInput, age: 0)
        try fixture.write(completed)
        try FileManager.default.setAttributes([.modificationDate: attributes[.modificationDate]!], ofItemAtPath: file.path)
        XCTAssertEqual(fixture.repository.load().records, [completed])
        try Data("invalid JSON".utf8).write(to: file)
        XCTAssertTrue(fixture.repository.load().records.isEmpty, "Cached valid data must not mask a corrupt replacement")
    }

    func testCachedRecordsStillExpireWithoutFileChanges() throws {
        let fixture = try Fixture(now: fixedNow)
        defer { fixture.remove() }
        var clock = fixedNow
        let repository = TaskActivityRepository(sessionsURL: fixture.sessionsURL,
            legacyStatusURL: fixture.legacyURL, now: { clock })
        let file = try fixture.write(record(key: "cached", state: .ready, phase: .waitingInput, age: 0))
        XCTAssertEqual(repository.load().records.count, 1)
        clock = clock.addingTimeInterval(25 * 60 * 60)
        XCTAssertTrue(repository.load().records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testSnapshotAggregatesByPriorityAndExcludesStaleRunningTasks() {
        let ready = record(key: "ready", state: .ready, phase: .waitingInput, age: 30)
        let running = record(key: "running", state: .running, phase: .processing, age: 60)
        let stale = record(key: "stale", state: .running, phase: .processing, age: 7 * 60 * 60)
        let attention = record(key: "attention", state: .needsAttention, phase: .awaitingPermission, age: 90)

        let snapshot = TaskCenterSnapshot(records: [ready, stale, running, attention], now: fixedNow)

        XCTAssertEqual(snapshot.aggregateLight, .needsAttention)
        XCTAssertEqual(snapshot.mostUrgent?.taskKey, "attention")
        XCTAssertEqual(snapshot.needsAttentionCount, 1)
        XCTAssertEqual(snapshot.runningCount, 1)
        XCTAssertEqual(snapshot.readyCount, 1)
        XCTAssertEqual(snapshot.staleRecords.map(\.taskKey), ["stale"])
        XCTAssertEqual(snapshot.records.map(\.taskKey), ["attention", "running", "ready", "stale"])
    }

    func testDisplayedTasksHideStaleRecordsAndReturnAfterFreshActivity() throws {
        let fixture = try Fixture(now: fixedNow)
        defer { fixture.remove() }
        let defaultsFixture = try DefaultsFixture()
        defer { defaultsFixture.remove() }
        let notifications = TaskNotificationService(
            notificationClient: MockTaskNotificationClient(status: .authorized, requestGranted: true),
            defaults: defaultsFixture.defaults)
        let service = TaskCenterService(repository: fixture.repository,
            notificationService: notifications, now: { self.fixedNow })
        defer { service.stop() }
        try fixture.write(record(key: "stale", state: .running, phase: .processing, age: 7 * 60 * 60))
        service.refresh()
        XCTAssertTrue(service.displayRecords.isEmpty)
        XCTAssertEqual(service.snapshot.staleRecords.count, 1)

        try fixture.write(record(key: "unread", state: .ready, phase: .waitingInput, age: 10))
        service.refresh()
        XCTAssertEqual(service.displayRecords.map(\.taskKey), ["unread"])
        XCTAssertEqual(service.snapshot.readyCount, 1)

        try fixture.write(record(key: "stale", state: .running, phase: .processing, age: 0))
        service.refresh()
        XCTAssertEqual(service.displayRecords.map(\.taskKey), ["stale", "unread"])
        XCTAssertTrue(service.snapshot.staleRecords.isEmpty)
    }

    func testRepositoryLoadsV2RecordsInsteadOfLegacyAndSecuresItsDirectories() throws {
        let fixture = try Fixture(now: fixedNow)
        defer { fixture.remove() }
        try fixture.write(record(key: "task-a", state: .running, phase: .processing, age: 20))
        try fixture.write(record(key: "task-b", state: .ready, phase: .waitingInput, age: 10))
        try fixture.writeLegacy(state: "needs_attention", source: "PermissionRequest", age: 5)

        let result = fixture.repository.load()

        XCTAssertEqual(Set(result.records.map(\.taskKey)), ["task-a", "task-b"])
        XCTAssertFalse(result.isLegacyFallback)
        XCTAssertEqual(try fixture.permissions(of: fixture.rootURL), 0o700)
        XCTAssertEqual(try fixture.permissions(of: fixture.sessionsURL), 0o700)
    }

    func testRepositoryDowngradesLegacyPermissionCandidateToRunning() throws {
        let fixture = try Fixture(now: fixedNow)
        defer { fixture.remove() }
        try fixture.write(
            record(
                key: "old-permission",
                state: .needsAttention,
                phase: .awaitingPermission,
                age: 5,
                source: "PermissionRequest"
            )
        )

        let result = fixture.repository.load()

        XCTAssertEqual(result.records.first?.state, .running)
        XCTAssertEqual(result.records.first?.phase, .processing)
        XCTAssertEqual(result.records.first?.source, "PermissionRequest")
    }

    func testRepositoryDowngradesLegacyPermissionFallbackToRunning() throws {
        let fixture = try Fixture(now: fixedNow)
        defer { fixture.remove() }
        try fixture.writeLegacy(state: "needs_attention", source: "PermissionRequest", age: 5)

        let result = fixture.repository.load()

        XCTAssertTrue(result.isLegacyFallback)
        XCTAssertEqual(result.records.first?.state, .running)
        XCTAssertEqual(result.records.first?.phase, .processing)
    }

    func testRepositoryDeletesRecordsOlderThanTwentyFourHours() throws {
        let fixture = try Fixture(now: fixedNow)
        defer { fixture.remove() }
        let old = record(key: "old-task", state: .ready, phase: .waitingInput, age: 25 * 60 * 60)
        let fileURL = try fixture.write(old)

        let result = fixture.repository.load()

        XCTAssertTrue(result.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testRepositoryQuarantinesMalformedAndOversizedRecords() throws {
        let fixture = try Fixture(now: fixedNow)
        defer { fixture.remove() }
        try Data("not-json".utf8).write(to: fixture.sessionsURL.appendingPathComponent("broken.json"))
        let oversized = TaskActivityRecord(
            taskKey: "oversized",
            eventKey: "event-oversized",
            state: .ready,
            phase: .waitingInput,
            projectName: String(repeating: "x", count: 121),
            updatedAt: fixedNow,
            source: "Stop"
        )
        try fixture.write(oversized)

        let result = fixture.repository.load()
        let quarantineURL = fixture.sessionsURL.appendingPathComponent(".invalid", isDirectory: true)
        let quarantined = try FileManager.default.contentsOfDirectory(atPath: quarantineURL.path)

        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.unreadableCount, 2)
        XCTAssertEqual(quarantined.count, 2)
        XCTAssertEqual(try fixture.permissions(of: quarantineURL), 0o700)
    }

    func testRepositoryFallsBackToLegacyOnlyWhenV2HasNoValidRecords() throws {
        let fixture = try Fixture(now: fixedNow)
        defer { fixture.remove() }
        try fixture.writeLegacy(state: "running", source: "SessionStart:compact", age: 60)

        let result = fixture.repository.load()

        XCTAssertTrue(result.isLegacyFallback)
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.records.first?.taskKey, TaskActivityRepository.legacyTaskKey)
        XCTAssertEqual(result.records.first?.phase, .processing)
        XCTAssertEqual(result.records.first?.projectName, "Codex")
    }

    func testAttentionPresentationOnlyExistsWhenUserActionIsRequired() throws {
        let running = TaskCenterSnapshot(
            records: [record(key: "running", state: .running, phase: .processing, age: 0)],
            now: fixedNow
        )
        let ready = TaskCenterSnapshot(
            records: [record(key: "ready", state: .ready, phase: .waitingInput, age: 0)],
            now: fixedNow
        )
        let attention = TaskCenterSnapshot(
            records: [
                record(
                    key: "permission",
                    state: .needsAttention,
                    phase: .awaitingPermission,
                    age: 0,
                    project: "fund-pulse"
                )
            ],
            now: fixedNow
        )

        XCTAssertNil(TaskAttentionPresentation(snapshot: running))
        XCTAssertNil(TaskAttentionPresentation(snapshot: ready))

        let presentation = try XCTUnwrap(TaskAttentionPresentation(snapshot: attention))
        XCTAssertEqual(presentation.count, 1)
        XCTAssertEqual(presentation.projectName, "fund-pulse")
    }

    func testDirectoryEventIsDebouncedIntoOneReload() async throws {
        let fixture = try Fixture(now: fixedNow, usesManualMonitor: true)
        defer { fixture.remove() }
        var results: [TaskActivityLoadResult] = []
        fixture.repository.start { results.append($0) }
        XCTAssertEqual(results.count, 1)

        try fixture.write(record(key: "new-task", state: .running, phase: .processing, age: 0))
        fixture.monitor?.trigger()
        fixture.monitor?.trigger()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.last?.records.map(\.taskKey), ["new-task"])
        fixture.repository.stop()
    }

    func testDirectoryInvalidationRecreatesDirectoryAndRearmsMonitor() async throws {
        let fixture = try Fixture(now: fixedNow, usesManualMonitor: true)
        defer { fixture.remove() }
        var results: [TaskActivityLoadResult] = []
        fixture.repository.start { results.append($0) }
        XCTAssertEqual(fixture.monitor?.startCount, 1)

        try FileManager.default.removeItem(at: fixture.sessionsURL)
        fixture.monitor?.trigger(requiresRearm: true)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.sessionsURL.path))
        XCTAssertEqual(fixture.monitor?.startCount, 2)

        try fixture.write(record(key: "after-rearm", state: .running, phase: .processing, age: 0))
        fixture.monitor?.trigger()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(results.last?.records.map(\.taskKey), ["after-rearm"])
    }

    func testWakeEventReevaluatesRunningStalenessAfterSystemSleep() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskCenterWakeTests-\(UUID().uuidString)", isDirectory: true)
        let sessionsURL = rootURL.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let clock = MutableClock(now: fixedNow)
        let repository = TaskActivityRepository(
            sessionsURL: sessionsURL,
            legacyStatusURL: rootURL.appendingPathComponent("session_status.json"),
            now: { clock.now }
        )
        defer { repository.stop() }
        let running = record(key: "sleeping-task", state: .running, phase: .processing, age: 0)
        try JSONEncoder().encode(running).write(
            to: sessionsURL.appendingPathComponent("sleeping-task.json"),
            options: .atomic
        )
        var results: [TaskActivityLoadResult] = []
        repository.start { results.append($0) }

        clock.now = fixedNow.addingTimeInterval(7 * 60 * 60)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await Task.yield()

        XCTAssertEqual(results.count, 2)
        let snapshot = TaskCenterSnapshot(records: try XCTUnwrap(results.last).records, now: clock.now)
        XCTAssertEqual(snapshot.runningCount, 0)
        XCTAssertEqual(snapshot.staleRecords.map(\.taskKey), ["sleeping-task"])
    }

    func testNotificationsAreOptInAndGeneric() async throws {
        let defaultsFixture = try DefaultsFixture()
        defer { defaultsFixture.remove() }
        let client = MockTaskNotificationClient(status: .authorized, requestGranted: true)
        let service = TaskNotificationService(notificationClient: client, defaults: defaultsFixture.defaults)
        let snapshot = TaskCenterSnapshot(
            records: [record(key: "secret-task", state: .needsAttention, phase: .awaitingPermission, age: 0, project: "Secret Project")],
            now: fixedNow
        )

        service.process(snapshot: snapshot)
        XCTAssertEqual(client.authorizationRequestCount, 0)
        XCTAssertTrue(client.requests.isEmpty)

        let enabled = await service.enable()
        XCTAssertTrue(enabled)
        service.process(snapshot: snapshot)
        service.process(snapshot: snapshot)
        await Task.yield()

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(client.authorizationRequestCount, 0)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertFalse(request.content.title.contains("Secret"))
        XCTAssertFalse(request.content.body.contains("Secret"))
        XCTAssertTrue(request.content.userInfo.isEmpty)
    }

    func testNotificationDedupeSurvivesServiceRecreation() async throws {
        let defaultsFixture = try DefaultsFixture()
        defer { defaultsFixture.remove() }
        let snapshot = TaskCenterSnapshot(
            records: [record(key: "task", state: .needsAttention, phase: .awaitingPermission, age: 0)],
            now: fixedNow
        )

        let firstClient = MockTaskNotificationClient(status: .authorized, requestGranted: true)
        let first = TaskNotificationService(notificationClient: firstClient, defaults: defaultsFixture.defaults)
        let enabled = await first.enable()
        XCTAssertTrue(enabled)
        first.process(snapshot: snapshot)
        await Task.yield()
        XCTAssertEqual(firstClient.requests.count, 1)

        let secondClient = MockTaskNotificationClient(status: .authorized, requestGranted: true)
        let second = TaskNotificationService(notificationClient: secondClient, defaults: defaultsFixture.defaults)
        second.refreshAuthorizationStatus()
        await Task.yield()
        second.process(snapshot: snapshot)

        XCTAssertTrue(second.isEnabled)
        XCTAssertTrue(secondClient.requests.isEmpty)
    }

    func testProvisionalPermissionNotificationIsCancelledWhenToolContinues() async throws {
        let defaultsFixture = try DefaultsFixture()
        defer { defaultsFixture.remove() }
        let client = MockTaskNotificationClient(status: .authorized, requestGranted: true)
        let service = TaskNotificationService(
            notificationClient: client,
            defaults: defaultsFixture.defaults,
            attentionDelayNanoseconds: 100_000_000
        )
        let enabled = await service.enable()
        XCTAssertTrue(enabled)

        let permission = record(
            key: "auto-approved",
            state: .needsAttention,
            phase: .awaitingPermission,
            age: 0
        )
        let continued = TaskActivityRecord(
            taskKey: permission.taskKey,
            turnKey: permission.turnKey,
            eventKey: "event-post-tool-use",
            state: .running,
            phase: .processing,
            projectName: permission.projectName,
            model: permission.model,
            updatedAt: fixedNow,
            source: "PostToolUse"
        )

        service.process(snapshot: TaskCenterSnapshot(records: [permission], now: fixedNow))
        service.process(snapshot: TaskCenterSnapshot(records: [continued], now: fixedNow))
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(client.requests.isEmpty)
    }

    func testPermissionStillWaitingAfterGracePeriodNotifies() async throws {
        let defaultsFixture = try DefaultsFixture()
        defer { defaultsFixture.remove() }
        let client = MockTaskNotificationClient(status: .authorized, requestGranted: true)
        let service = TaskNotificationService(
            notificationClient: client,
            defaults: defaultsFixture.defaults,
            attentionDelayNanoseconds: 50_000_000
        )
        let enabled = await service.enable()
        XCTAssertTrue(enabled)
        let permission = record(
            key: "manual-approval",
            state: .needsAttention,
            phase: .awaitingPermission,
            age: 0
        )

        service.process(snapshot: TaskCenterSnapshot(records: [permission], now: fixedNow))
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests.first?.content.title, L.taskPermissionNotificationTitle)
        XCTAssertEqual(client.requests.first?.content.body, L.taskPermissionNotificationBody)
    }

    func testWaitingForInputUsesReplyPrompt() async throws {
        let fixture = try DefaultsFixture()
        defer { fixture.remove() }
        let client = MockTaskNotificationClient(status: .authorized, requestGranted: true)
        let service = TaskNotificationService(notificationClient: client, defaults: fixture.defaults)
        let enabled = await service.enable()
        XCTAssertTrue(enabled)
        let waiting = record(key: "reply-needed", state: .needsAttention, phase: .waitingInput, age: 0)

        service.process(snapshot: TaskCenterSnapshot(records: [waiting], now: fixedNow))

        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests.first?.content.title, L.taskInputNotificationTitle)
        XCTAssertEqual(client.requests.first?.content.body, L.taskInputNotificationBody)
    }

    func testNotificationDedupeIsPersistedBeforeSchedulingCompletes() async throws {
        let defaultsFixture = try DefaultsFixture()
        defer { defaultsFixture.remove() }
        let snapshot = TaskCenterSnapshot(
            records: [record(key: "task", state: .needsAttention, phase: .awaitingPermission, age: 0)],
            now: fixedNow
        )

        let firstClient = MockTaskNotificationClient(status: .authorized, requestGranted: true)
        firstClient.delaysAddResponses = true
        let first = TaskNotificationService(notificationClient: firstClient, defaults: defaultsFixture.defaults)
        let enabled = await first.enable()
        XCTAssertTrue(enabled)
        first.process(snapshot: snapshot)
        XCTAssertEqual(firstClient.requests.count, 1)

        let secondClient = MockTaskNotificationClient(status: .authorized, requestGranted: true)
        let second = TaskNotificationService(notificationClient: secondClient, defaults: defaultsFixture.defaults)
        second.refreshAuthorizationStatus()
        await Task.yield()
        second.process(snapshot: snapshot)

        XCTAssertTrue(secondClient.requests.isEmpty)
        firstClient.pendingAddCallbacks.first?(nil)
    }

    func testUnreadStopCompletionNotifiesImmediatelyAndOnlyOnce() async throws {
        let fixture = try DefaultsFixture()
        defer { fixture.remove() }
        let client = MockTaskNotificationClient(status: .authorized, requestGranted: true)
        let service = TaskNotificationService(notificationClient: client, defaults: fixture.defaults,
            attentionDelayNanoseconds: 15_000_000_000)
        let enabled = await service.enable()
        XCTAssertTrue(enabled)
        let completed = record(key: "completed", state: .ready, phase: .waitingInput, age: 0)
        let snapshot = TaskCenterSnapshot(records: [completed], now: fixedNow)
        service.process(snapshot: snapshot)
        service.process(snapshot: snapshot)
        XCTAssertEqual(client.requests.count, 1, "Completions must not wait for the approval grace period")
        XCTAssertEqual(client.requests.first?.content.title, L.taskCompletedNotificationTitle)
        XCTAssertEqual(client.requests.first?.content.body, L.taskCompletedNotificationBody)
        service.process(snapshot: .empty)
        service.process(snapshot: snapshot)
        XCTAssertEqual(client.requests.count, 1)
    }

    func testResumeAndInterruptAreNotCompletionNotifications() async throws {
        let fixture = try DefaultsFixture()
        defer { fixture.remove() }
        let client = MockTaskNotificationClient(status: .authorized, requestGranted: true)
        let service = TaskNotificationService(notificationClient: client, defaults: fixture.defaults)
        _ = await service.enable()
        for source in ["SessionStart", "Interrupt", "SessionEnd"] {
            service.process(snapshot: TaskCenterSnapshot(records: [
                record(key: source, state: .ready, phase: .waitingInput, age: 0, source: source)
            ], now: fixedNow))
        }
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testRejectedNotificationRetriesAndThenPersistsSuccessfulDedupe() async throws {
        let fixture = try DefaultsFixture()
        defer { fixture.remove() }
        let client = MockTaskNotificationClient(status: .authorized, requestGranted: true,
            addError: CocoaError(.fileWriteUnknown))
        let service = TaskNotificationService(notificationClient: client, defaults: fixture.defaults,
            retryDelayNanoseconds: 50_000_000)
        _ = await service.enable()
        let snapshot = TaskCenterSnapshot(records: [record(key: "retry", state: .ready, phase: .waitingInput, age: 0)], now: fixedNow)
        service.process(snapshot: snapshot)
        try await Task.sleep(for: .milliseconds(20))
        client.addError = nil
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(client.requests.count, 2)
        let secondClient = MockTaskNotificationClient(status: .authorized, requestGranted: true)
        let restarted = TaskNotificationService(notificationClient: secondClient, defaults: fixture.defaults)
        await restarted.refreshAuthorizationStatusNow()
        restarted.process(snapshot: snapshot)
        XCTAssertTrue(secondClient.requests.isEmpty)
    }

    func testReadCompletionCancelsDeliveryRetry() async throws {
        let fixture = try DefaultsFixture()
        defer { fixture.remove() }
        let client = MockTaskNotificationClient(status: .authorized, requestGranted: true,
            addError: CocoaError(.fileWriteUnknown))
        let service = TaskNotificationService(notificationClient: client, defaults: fixture.defaults,
            retryDelayNanoseconds: 50_000_000)
        _ = await service.enable()
        service.process(snapshot: TaskCenterSnapshot(records: [record(key: "read", state: .ready, phase: .waitingInput, age: 0)], now: fixedNow))
        try await Task.sleep(for: .milliseconds(20))
        service.process(snapshot: .empty)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(client.requests.count, 1)
    }

    func testRepeatedDeliveryFailuresStopAfterThreeAttempts() async throws {
        let fixture = try DefaultsFixture()
        defer { fixture.remove() }
        let client = MockTaskNotificationClient(status: .authorized, requestGranted: true,
            addError: CocoaError(.fileWriteUnknown))
        let service = TaskNotificationService(notificationClient: client, defaults: fixture.defaults,
            retryDelayNanoseconds: 10_000_000)
        _ = await service.enable()
        let snapshot = TaskCenterSnapshot(records: [record(key: "failed", state: .ready, phase: .waitingInput, age: 0)], now: fixedNow)
        service.process(snapshot: snapshot)
        try await Task.sleep(for: .milliseconds(150))
        service.process(snapshot: snapshot)
        XCTAssertEqual(client.requests.count, 3)
    }

    func testEnableProactivelyRequestsNotificationAuthorization() async throws {
        let defaultsFixture = try DefaultsFixture()
        defer { defaultsFixture.remove() }
        let client = MockTaskNotificationClient(status: .notDetermined, requestGranted: true)
        let service = TaskNotificationService(notificationClient: client, defaults: defaultsFixture.defaults)
        XCTAssertEqual(client.authorizationRequestCount, 0)
        let enabled = await service.enable()
        XCTAssertTrue(enabled)
        XCTAssertEqual(client.authorizationRequestCount, 1)
        XCTAssertEqual(service.authorizationStatus, .authorized)
    }

    func testExistingOptInRequestsPermissionForNewNotificationIdentity() async throws {
        let fixture = try DefaultsFixture()
        defer { fixture.remove() }
        fixture.defaults.set(true, forKey: "codexbar.taskAttentionNotificationsEnabled")
        let client = MockTaskNotificationClient(status: .notDetermined, requestGranted: true)
        let service = TaskNotificationService(notificationClient: client, defaults: fixture.defaults)

        await service.refreshAuthorizationStatusNow()

        XCTAssertTrue(service.isEnabled)
        XCTAssertEqual(client.authorizationRequestCount, 1)
    }

    func testDeniedNotificationPermissionDoesNotEnableService() async throws {
        let defaultsFixture = try DefaultsFixture()
        defer { defaultsFixture.remove() }
        let client = MockTaskNotificationClient(status: .denied, requestGranted: false)
        let service = TaskNotificationService(notificationClient: client, defaults: defaultsFixture.defaults)

        let enabled = await service.enable()
        XCTAssertFalse(enabled)
        XCTAssertFalse(service.isEnabled)
        XCTAssertEqual(service.authorizationStatus, .denied)
        XCTAssertEqual(service.authorizationIssue, .denied)
        XCTAssertEqual(client.authorizationRequestCount, 0)
    }

    func testAuthorizationFailureIsNotReportedAsDenialAndCanRetry() async throws {
        let fixture = try DefaultsFixture()
        defer { fixture.remove() }
        let client = MockTaskNotificationClient(status: .notDetermined, requestGranted: true)
        client.authorizationError = NSError(domain: "PermissionTransport", code: 42)
        let service = TaskNotificationService(notificationClient: client, defaults: fixture.defaults)
        let enabled = await service.enable()
        XCTAssertFalse(enabled)
        guard case .requestFailed(let detail) = service.authorizationIssue else {
            return XCTFail("A system request error must not become permission denial")
        }
        XCTAssertTrue(detail.contains("PermissionTransport 42"))
        client.authorizationError = nil
        let retried = await service.enable()
        XCTAssertTrue(retried)
        XCTAssertNil(service.authorizationIssue)
        XCTAssertEqual(client.authorizationRequestCount, 2)
        service.disable()
        let reenabled = await service.enable()
        XCTAssertTrue(reenabled)
        XCTAssertEqual(client.authorizationRequestCount, 2, "Existing permission needs no new system prompt")
    }

    func testSystemRevocationIsRecheckedBeforeToggleAndRestoresAfterSettingsGrant() async throws {
        let fixture = try DefaultsFixture()
        defer { fixture.remove() }
        let client = MockTaskNotificationClient(status: .authorized, requestGranted: true)
        let service = TaskNotificationService(notificationClient: client, defaults: fixture.defaults)
        let enabled = await service.enable()
        XCTAssertTrue(enabled)
        client.status = .denied // System Settings changed while our icon was still cached as enabled.
        let toggled = await service.toggleFromUserAction()
        XCTAssertFalse(toggled)
        XCTAssertEqual(service.authorizationIssue, .denied)
        XCTAssertEqual(client.authorizationRequestCount, 0)
        client.status = .authorized
        await service.refreshAuthorizationStatusNow()
        XCTAssertTrue(service.isEnabled, "Blocked click must preserve the intent to enable")
        XCTAssertNil(service.authorizationIssue)
        let disabled = await service.toggleFromUserAction()
        XCTAssertFalse(disabled)
        await service.refreshAuthorizationStatusNow()
        XCTAssertFalse(service.isEnabled, "Refresh must preserve an explicit app-level off setting")
    }

    func testOlderPermissionRefreshCannotOverwriteSystemRevocation() async throws {
        let fixture = try DefaultsFixture()
        defer { fixture.remove() }
        let client = MockTaskNotificationClient(status: .authorized, requestGranted: true)
        let service = TaskNotificationService(notificationClient: client, defaults: fixture.defaults)
        _ = await service.enable()
        client.delaysStatusResponses = true
        service.refreshAuthorizationStatus()
        service.refreshAuthorizationStatus()
        XCTAssertEqual(client.pendingStatusCallbacks.count, 2)
        client.pendingStatusCallbacks[1](.denied)
        await Task.yield()
        client.pendingStatusCallbacks[0](.authorized)
        await Task.yield()
        XCTAssertFalse(service.isEnabled)
        XCTAssertEqual(service.authorizationStatus, .denied)
    }

    func testOverlappingNotificationTapsDoNotToggleTwice() async throws {
        let fixture = try DefaultsFixture()
        defer { fixture.remove() }
        let client = MockTaskNotificationClient(status: .authorized, requestGranted: true)
        let service = TaskNotificationService(notificationClient: client, defaults: fixture.defaults)
        client.delaysStatusResponses = true
        let first = Task { await service.toggleFromUserAction() }
        await Task.yield()
        XCTAssertTrue(service.isUpdatingAuthorization)
        _ = await service.toggleFromUserAction()
        XCTAssertEqual(client.pendingStatusCallbacks.count, 1)
        client.pendingStatusCallbacks[0](.authorized)
        let enabled = await first.value
        XCTAssertTrue(enabled)
        XCTAssertFalse(service.isUpdatingAuthorization)
    }

    func testDistinctPermissionEventsForOneTaskEachNotifyOnce() async throws {
        let defaultsFixture = try DefaultsFixture()
        defer { defaultsFixture.remove() }
        let client = MockTaskNotificationClient(status: .authorized, requestGranted: true)
        let service = TaskNotificationService(notificationClient: client, defaults: defaultsFixture.defaults)
        let enabled = await service.enable()
        XCTAssertTrue(enabled)

        let first = record(key: "same-task", state: .needsAttention, phase: .awaitingPermission, age: 10)
        let second = TaskActivityRecord(
            taskKey: first.taskKey,
            turnKey: "turn-second",
            eventKey: "event-second-permission",
            state: .needsAttention,
            phase: .awaitingPermission,
            projectName: first.projectName,
            model: first.model,
            updatedAt: fixedNow,
            source: "PermissionRequest"
        )

        service.process(snapshot: TaskCenterSnapshot(records: [first], now: fixedNow))
        await Task.yield()
        service.process(snapshot: TaskCenterSnapshot(records: [second], now: fixedNow))
        service.process(snapshot: TaskCenterSnapshot(records: [second], now: fixedNow))
        await Task.yield()

        XCTAssertEqual(client.requests.count, 2)
    }

    func testISO8601DateCodingTreatsTimeZoneOffsetsAsTheSameInstant() throws {
        let utc = try XCTUnwrap(TaskActivityDateCoding.date(from: "2033-05-18T03:33:20.000Z"))
        let shanghai = try XCTUnwrap(TaskActivityDateCoding.date(from: "2033-05-18T11:33:20.000+08:00"))

        XCTAssertEqual(utc, shanghai)
    }

    func testNotificationClickRequestsCodexActivation() async throws {
        let defaultsFixture = try DefaultsFixture()
        defer { defaultsFixture.remove() }
        let client = MockTaskNotificationClient(status: .authorized, requestGranted: true)
        let service = TaskNotificationService(notificationClient: client, defaults: defaultsFixture.defaults)
        var didRequestCodexActivation = false
        service.onOpenCodex = { didRequestCodexActivation = true }

        client.open()
        await Task.yield()

        XCTAssertTrue(didRequestCodexActivation)
    }

    func testTaskCenterServiceRoutesNotificationClickToCodexActivation() async throws {
        let fixture = try Fixture(now: fixedNow)
        defer { fixture.remove() }
        let defaultsFixture = try DefaultsFixture()
        defer { defaultsFixture.remove() }
        let client = MockTaskNotificationClient(status: .authorized, requestGranted: true)
        let notifications = TaskNotificationService(notificationClient: client, defaults: defaultsFixture.defaults)
        let service = TaskCenterService(
            repository: fixture.repository,
            notificationService: notifications,
            now: { self.fixedNow }
        )
        var didRequestCodexActivation = false
        service.onRequestOpenCodex = { didRequestCodexActivation = true }

        client.open()
        await Task.yield()

        XCTAssertTrue(didRequestCodexActivation)
    }

    private func record(
        key: String,
        state: TaskActivityState,
        phase: TaskActivityPhase,
        age: TimeInterval,
        project: String = "codexbar",
        source eventSource: String? = nil
    ) -> TaskActivityRecord {
        TaskActivityRecord(
            taskKey: key,
            turnKey: "turn-\(key)",
            eventKey: "event-\(key)",
            state: state,
            phase: phase,
            projectName: project,
            model: "gpt-5",
            updatedAt: fixedNow.addingTimeInterval(-age),
            source: eventSource ?? source(for: phase)
        )
    }

    private func source(for phase: TaskActivityPhase) -> String {
        switch phase {
        case .connecting: return "SessionStart"
        case .processing: return "UserPromptSubmit"
        case .compacting: return "SessionStart:compact"
        case .awaitingPermission: return "PermissionRequest"
        case .waitingInput: return "Stop"
        }
    }

    private final class Fixture {
        let rootURL: URL
        let sessionsURL: URL
        let legacyURL: URL
        let repository: TaskActivityRepository
        let now: Date
        let monitor: ManualTaskActivityMonitor?

        init(now: Date, usesManualMonitor: Bool = false) throws {
            self.now = now
            rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("TaskCenterCoreTests-\(UUID().uuidString)", isDirectory: true)
            sessionsURL = rootURL.appendingPathComponent("sessions", isDirectory: true)
            legacyURL = rootURL.appendingPathComponent("session_status.json")
            try FileManager.default.createDirectory(at: sessionsURL, withIntermediateDirectories: true)

            if usesManualMonitor {
                let monitor = ManualTaskActivityMonitor()
                self.monitor = monitor
                repository = TaskActivityRepository(
                    sessionsURL: sessionsURL,
                    legacyStatusURL: legacyURL,
                    fileManager: .default,
                    now: { now },
                    monitorFactory: { _ in monitor }
                )
            } else {
                monitor = nil
                repository = TaskActivityRepository(
                    sessionsURL: sessionsURL,
                    legacyStatusURL: legacyURL,
                    now: { now }
                )
            }
        }

        @discardableResult
        func write(_ record: TaskActivityRecord) throws -> URL {
            let url = sessionsURL.appendingPathComponent(record.taskKey).appendingPathExtension("json")
            try JSONEncoder().encode(record).write(to: url, options: .atomic)
            return url
        }

        func writeLegacy(state: String, source: String, age: TimeInterval) throws {
            let object: [String: Any] = [
                "state": state,
                "updatedAt": TaskActivityDateCoding.string(from: now.addingTimeInterval(-age)),
                "source": source
            ]
            let data = try JSONSerialization.data(withJSONObject: object)
            try data.write(to: legacyURL, options: .atomic)
        }

        func permissions(of url: URL) throws -> Int {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return try XCTUnwrap(attributes[.posixPermissions] as? Int) & 0o777
        }

        func remove() {
            repository.stop()
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    private final class DefaultsFixture {
        let suiteName = "TaskCenterCoreTests.\(UUID().uuidString)"
        let defaults: UserDefaults

        init() throws {
            defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defaults.removePersistentDomain(forName: suiteName)
        }

        func remove() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private final class MutableClock {
        var now: Date

        init(now: Date) {
            self.now = now
        }
    }
}

@MainActor
private final class ManualTaskActivityMonitor: TaskActivityDirectoryMonitoring {
    private var onChange: ((Bool) -> Void)?
    private(set) var startCount = 0

    func start(onChange: @escaping (Bool) -> Void) throws {
        startCount += 1
        self.onChange = onChange
    }

    func stop() {
        onChange = nil
    }

    func trigger(requiresRearm: Bool = false) {
        onChange?(requiresRearm)
    }
}

@MainActor
private final class MockTaskNotificationClient: TaskNotificationClient {
    var status: UNAuthorizationStatus
    var requestGranted: Bool
    var authorizationRequestCount = 0
    var authorizationError: Error?
    var delaysStatusResponses = false
    var pendingStatusCallbacks: [(UNAuthorizationStatus) -> Void] = []
    var requests: [UNNotificationRequest] = []
    var addError: Error?
    var delaysAddResponses = false
    var pendingAddCallbacks: [(Error?) -> Void] = []
    private var responseHandler: (() -> Void)?

    init(status: UNAuthorizationStatus, requestGranted: Bool, addError: Error? = nil) {
        self.status = status
        self.requestGranted = requestGranted
        self.addError = addError
    }

    func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        if delaysStatusResponses { pendingStatusCallbacks.append(completion) }
        else { completion(status) }
    }

    func requestAuthorization(completion: @escaping (Result<Bool, Error>) -> Void) {
        authorizationRequestCount += 1
        if let authorizationError { completion(.failure(authorizationError)); return }
        if status == .notDetermined { status = requestGranted ? .authorized : .denied }
        completion(.success(requestGranted))
    }

    func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
        requests.append(request)
        if delaysAddResponses { pendingAddCallbacks.append(completion) }
        else { completion(addError) }
    }

    func setResponseHandler(_ handler: @escaping () -> Void) {
        responseHandler = handler
    }

    func open() {
        responseHandler?()
    }
}
