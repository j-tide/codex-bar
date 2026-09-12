import Combine
import Foundation

@MainActor
final class TaskCenterService: ObservableObject {
    static let shared = TaskCenterService()

    @Published private(set) var snapshot: TaskCenterSnapshot = .empty

    @Published private(set) var metadata: [String: CodexTaskMetadata] = [:]
    private var metadataTask: Task<Void, Never>?
    private var metadataRefreshedAt = Date.distantPast

    var displayRecords: [TaskActivityRecord] {
        snapshot.records.filter { !$0.isStale }.sorted {
            let left = metadata[$0.taskKey]?.sidebarPosition ?? Int.max
            let right = metadata[$1.taskKey]?.sidebarPosition ?? Int.max
            if left != right { return left < right }
            // Missing metadata must not restore status-based sorting.
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.taskKey < $1.taskKey
        }
    }

    let notificationService: TaskNotificationService
    var onRequestOpenCodex: (() -> Void)?

    private let readState: TaskReadState?
    private let codexReadState: CodexReadStateMonitor?
    private var lastLoad = TaskActivityLoadResult(records: [], isLegacyFallback: false, unreadableCount: 0)
    private let repository: TaskActivityRepository
    private let now: () -> Date
    private var started = false

    convenience init() {
        self.init(
            repository: TaskActivityRepository(),
            notificationService: TaskNotificationService.shared,
            now: Date.init,
            readState: TaskReadState(defaults: .standard),
            codexReadState: CodexReadStateMonitor()
        )
    }

    init(
        repository: TaskActivityRepository,
        notificationService: TaskNotificationService,
        now: @escaping () -> Date,
        readState: TaskReadState? = nil,
        codexReadState: CodexReadStateMonitor? = nil
    ) {
        self.readState = readState
        self.codexReadState = codexReadState
        self.repository = repository
        self.notificationService = notificationService
        self.now = now

        notificationService.onOpenCodex = { [weak self] in
            self?.onRequestOpenCodex?()
        }
    }

    func start() {
        guard !started else {
            refresh()
            return
        }
        started = true
        codexReadState?.start { [weak self] in
            guard let self else { return }
            self.apply(self.lastLoad)
        }
        notificationService.refreshAuthorizationStatus()
        repository.start { [weak self] result in
            self?.apply(result)
        }
    }

    func stop() {
        metadataTask?.cancel()
        codexReadState?.stop()
        repository.stop()
        started = false
    }

    func refresh() {
        if started {
            repository.reload()
        } else {
            apply(repository.load())
        }
    }

    func refreshMetadata() {
        metadataTask?.cancel()
        metadataRefreshedAt = now()
        let keys = Set(lastLoad.records.map(\.taskKey))
        metadataTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                CodexStatsDB.taskMetadata(for: keys)
            }.value
            guard !Task.isCancelled else { return }
            guard let self else { return }
            if self.metadata != result { self.metadata = result }
            self.apply(self.lastLoad)
        }
    }

    func markRead(_ record: TaskActivityRecord) {
        guard let readState, record.state == .ready else { return }
        readState.markRead(record)
        apply(lastLoad)
    }

    private func apply(_ result: TaskActivityLoadResult) {
        let changed = Set(lastLoad.records.map(\.taskKey)) != Set(result.records.map(\.taskKey))
        lastLoad = result
        let visibleRecords = readState?.visibleRecords(
            from: result.records, knownTaskKeys: Set(metadata.keys),
            codexUnreadTaskKeys: codexReadState?.snapshot?.unreadTaskKeys,
            requiresCodexReadState: codexReadState != nil
        ) ?? result.records
        let snapshot = TaskCenterSnapshot(
            records: visibleRecords,
            now: now(),
            staleRunningInterval: TaskActivityRepository.staleRunningInterval,
            isLegacyFallback: result.isLegacyFallback,
            unreadableCount: result.unreadableCount
        )
        if self.snapshot != snapshot { self.snapshot = snapshot }
        if changed || now().timeIntervalSince(metadataRefreshedAt) >= 5 { refreshMetadata() }
        notificationService.process(snapshot: snapshot)
    }
}
