import CryptoKit
import Combine
import Foundation
import OSLog
import UserNotifications

protocol TaskNotificationClient: AnyObject {
    func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void)
    func requestAuthorization(completion: @escaping (Result<Bool, Error>) -> Void)
    func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void)
    func setResponseHandler(_ handler: @escaping () -> Void)
}

final class SystemTaskNotificationClient: TaskNotificationClient {
    private let bridge = NotificationBridge.shared

    func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        bridge.authorizationStatus(completion: completion)
    }

    func requestAuthorization(completion: @escaping (Result<Bool, Error>) -> Void) {
        bridge.requestAuthorization(completion: completion)
    }

    func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
        bridge.add(request, route: "task", completion: completion)
    }

    func setResponseHandler(_ handler: @escaping () -> Void) {
        // The helper routes notification clicks through the app's URL callback.
        _ = handler
    }

    static let identifierPrefix = "codexbar-task-attention-"
}

enum TaskNotificationAuthorizationIssue: Equatable {
    case denied
    case requestFailed(String)
    case notDetermined
}

@MainActor
final class TaskNotificationService: ObservableObject {
    static let shared = TaskNotificationService()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    @Published private(set) var isUpdatingAuthorization = false
    private var authorizationRevision = 0

    @Published private(set) var authorizationIssue: TaskNotificationAuthorizationIssue?

    var onOpenCodex: (() -> Void)?

    private static let enabledDefaultsKey = "codexbar.taskAttentionNotificationsEnabled"
    private static let notifiedEventKeysDefaultsKey = "codexbar.taskAttentionNotifiedEventKeys"
    private static let maximumRememberedEvents = 512
    private static let productionAttentionDelayNanoseconds: UInt64 = 15_000_000_000

    private let notificationClient: TaskNotificationClient
    private let defaults: UserDefaults
    private let attentionDelayNanoseconds: UInt64
    private let retryDelayNanoseconds: UInt64
    private var deliveryAttempts: [String: Int] = [:]
    private var notifiedEventKeys: [String]
    private var notifiedEventKeySet: Set<String>
    private var latestSnapshot: TaskCenterSnapshot?
    private var pendingNotificationTasks: [String: Task<Void, Never>] = [:]

    convenience init() {
        self.init(
            notificationClient: SystemTaskNotificationClient(),
            defaults: .standard,
            attentionDelayNanoseconds: Self.productionAttentionDelayNanoseconds
        )
    }

    init(
        notificationClient: TaskNotificationClient,
        defaults: UserDefaults,
        attentionDelayNanoseconds: UInt64 = 0,
        retryDelayNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.notificationClient = notificationClient
        self.defaults = defaults
        self.attentionDelayNanoseconds = attentionDelayNanoseconds
        self.retryDelayNanoseconds = retryDelayNanoseconds
        let savedKeys = defaults.stringArray(forKey: Self.notifiedEventKeysDefaultsKey) ?? []
        notifiedEventKeys = savedKeys
        notifiedEventKeySet = Set(savedKeys)
        // A persisted opt-in is not enough: wait until the current system
        // authorization status is known before sending anything.
        isEnabled = false

        notificationClient.setResponseHandler { [weak self] in
            Task { @MainActor in
                self?.onOpenCodex?()
            }
        }
    }

    func refreshAuthorizationStatus() {
        guard !isUpdatingAuthorization else { return }
        authorizationRevision += 1
        let revision = authorizationRevision
        notificationClient.authorizationStatus { [weak self] status in
            Task { @MainActor in
                guard let self, !self.isUpdatingAuthorization,
                      self.authorizationRevision == revision else { return }
                if status == .notDetermined,
                   self.defaults.bool(forKey: Self.enabledDefaultsKey) {
                    // Existing opt-in belongs to the old app identity. Ask macOS
                    // once for the new notification helper after an update.
                    _ = await self.enable()
                    return
                }
                self.applyAuthorizationStatus(status)
            }
        }
    }

    func refreshAuthorizationStatusNow() async {
        guard !isUpdatingAuthorization else { return }
        authorizationRevision += 1
        let revision = authorizationRevision
        let status = await currentAuthorizationStatus()
        guard !isUpdatingAuthorization, authorizationRevision == revision else { return }
        if status == .notDetermined, defaults.bool(forKey: Self.enabledDefaultsKey) {
            _ = await enable()
            return
        }
        applyAuthorizationStatus(status)
    }

    /// Decide from current system permission, never from the icon's cached state.
    @discardableResult
    func toggleFromUserAction() async -> Bool {
        guard !isUpdatingAuthorization else { return isEnabled }
        isUpdatingAuthorization = true
        authorizationRevision += 1
        defer { isUpdatingAuthorization = false }
        let status = await currentAuthorizationStatus()
        applyAuthorizationStatus(status)
        if isEnabled {
            disable()
            return false
        }
        return await enable(afterChecking: status)
    }

    @discardableResult
    func enable() async -> Bool {
        guard !isUpdatingAuthorization else { return isEnabled }
        isUpdatingAuthorization = true
        authorizationRevision += 1
        defer { isUpdatingAuthorization = false }
        let status = await currentAuthorizationStatus()
        return await enable(afterChecking: status)
    }

    private func enable(afterChecking initialStatus: UNAuthorizationStatus) async -> Bool {
        authorizationIssue = nil
        defaults.set(true, forKey: Self.enabledDefaultsKey)
        applyAuthorizationStatus(initialStatus)
        if Self.isAuthorized(initialStatus) { return true }
        if initialStatus == .denied {
            authorizationIssue = .denied
            return false
        }
        let result: Result<Bool, Error> = await withCheckedContinuation { continuation in
            notificationClient.requestAuthorization { result in
                continuation.resume(returning: result)
            }
        }
        let status = await currentAuthorizationStatus()
        applyAuthorizationStatus(status)
        switch result {
        case .failure(let error):
            let error = error as NSError
            let detail = "\(error.localizedDescription) (\(error.domain) \(error.code))"
            authorizationIssue = .requestFailed(detail)
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "codexbar", category: "TaskNotifications")
                .error("Notification authorization failed: \(detail, privacy: .public)")
            return false
        case .success(let granted):
            if granted, status == .notDetermined {
                // The grant callback can arrive before getNotificationSettings catches up.
                applyAuthorizationStatus(.authorized)
            }
            if isEnabled { return true }
            authorizationIssue = status == .denied ? .denied : .notDetermined
            return false
        }
    }

    func disable() {
        authorizationRevision += 1
        defaults.set(false, forKey: Self.enabledDefaultsKey)
        isEnabled = false
        authorizationIssue = nil
        cancelAllPendingNotifications()
        deliveryAttempts.removeAll()
    }

    func process(snapshot: TaskCenterSnapshot) {
        latestSnapshot = snapshot
        let candidates = Self.notificationRecords(in: snapshot)
        let activeDedupeKeys = Set(candidates.map { Self.digest($0.eventKey) })
        deliveryAttempts = deliveryAttempts.filter { activeDedupeKeys.contains($0.key) }
        for (dedupeKey, task) in pendingNotificationTasks where !activeDedupeKeys.contains(dedupeKey) {
            task.cancel()
            pendingNotificationTasks.removeValue(forKey: dedupeKey)
        }

        guard isEnabled else {
            cancelAllPendingNotifications()
            return
        }

        for record in candidates {
            let dedupeKey = Self.digest(record.eventKey)
            guard !notifiedEventKeySet.contains(dedupeKey),
                  deliveryAttempts[dedupeKey, default: 0] < 3,
                  pendingNotificationTasks[dedupeKey] == nil else { continue }

            // Only attention candidates need the auto-approval grace period.
            // The task center has already filtered read/unknown completions.
            if record.state == .ready || attentionDelayNanoseconds == 0 {
                sendNotification(for: record, dedupeKey: dedupeKey)
                continue
            }

            let delay = attentionDelayNanoseconds
            pendingNotificationTasks[dedupeKey] = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
                guard let self else { return }
                self.pendingNotificationTasks.removeValue(forKey: dedupeKey)
                guard self.isEnabled,
                      !self.notifiedEventKeySet.contains(dedupeKey),
                      self.isCurrentNotification(dedupeKey) else { return }
                self.sendNotification(for: record, dedupeKey: dedupeKey)
            }
        }
    }

    private func sendNotification(for record: TaskActivityRecord, dedupeKey: String) {
        // Persist before handing the request to the notification center.
        // This provides at-most-once scheduling even if the app exits
        // between system acceptance and the completion callback.
        remember(dedupeKey)
        deliveryAttempts[dedupeKey, default: 0] += 1
        let request = notificationRequest(for: record, dedupeKey: dedupeKey)
        notificationClient.add(request) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "codexbar", category: "TaskNotifications")
                guard let error else {
                    self.deliveryAttempts.removeValue(forKey: dedupeKey)
                    logger.notice("Notification accepted: state=\(record.state.rawValue, privacy: .public)")
                    return
                }
                // A definite rejection is not a delivered notification. Keep
                // successful/in-flight dedupe persistent, but allow failures to retry.
                self.forget(dedupeKey)
                logger.error("Notification rejected: \(error.localizedDescription, privacy: .public)")
                let attempts = self.deliveryAttempts[dedupeKey, default: 0]
                guard self.isEnabled, attempts < 3, self.isCurrentNotification(dedupeKey) else { return }
                let delay = self.retryDelayNanoseconds * UInt64(max(1, attempts))
                self.pendingNotificationTasks[dedupeKey] = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: delay) } catch { return }
                    guard let self else { return }
                    self.pendingNotificationTasks.removeValue(forKey: dedupeKey)
                    guard self.isEnabled, self.isCurrentNotification(dedupeKey),
                          !self.notifiedEventKeySet.contains(dedupeKey) else { return }
                    self.sendNotification(for: record, dedupeKey: dedupeKey)
                }
            }
        }
    }

    private static func notificationRecords(in snapshot: TaskCenterSnapshot) -> [TaskActivityRecord] {
        snapshot.needsAttentionRecords + snapshot.readyRecords.filter { $0.source == "Stop" }
    }

    private func isCurrentNotification(_ dedupeKey: String) -> Bool {
        guard let latestSnapshot else { return false }
        return Self.notificationRecords(in: latestSnapshot).contains { Self.digest($0.eventKey) == dedupeKey }
    }

    private func forget(_ key: String) {
        notifiedEventKeySet.remove(key)
        notifiedEventKeys.removeAll { $0 == key }
        defaults.set(notifiedEventKeys, forKey: Self.notifiedEventKeysDefaultsKey)
    }

    private func cancelAllPendingNotifications() {
        pendingNotificationTasks.values.forEach { $0.cancel() }
        pendingNotificationTasks.removeAll()
    }

    private func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            notificationClient.authorizationStatus { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func applyAuthorizationStatus(_ status: UNAuthorizationStatus) {
        let wasEnabled = isEnabled
        authorizationStatus = status
        isEnabled = defaults.bool(forKey: Self.enabledDefaultsKey) && Self.isAuthorized(status)
        if Self.isAuthorized(status) { authorizationIssue = nil }
        else if status == .denied, defaults.bool(forKey: Self.enabledDefaultsKey) {
            authorizationIssue = .denied
        }
        if !isEnabled {
            cancelAllPendingNotifications()
        }
        if !wasEnabled, isEnabled, let latestSnapshot {
            deliveryAttempts.removeAll()
            process(snapshot: latestSnapshot)
        }
    }

    private func notificationRequest(for record: TaskActivityRecord, dedupeKey: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        if record.state == .ready {
            content.title = L.taskCompletedNotificationTitle
            content.body = L.taskCompletedNotificationBody
        } else {
            switch record.phase {
            case .awaitingPermission:
                content.title = L.taskPermissionNotificationTitle
                content.body = L.taskPermissionNotificationBody
            case .waitingInput:
                content.title = L.taskInputNotificationTitle
                content.body = L.taskInputNotificationBody
            case .connecting, .processing, .compacting:
                content.title = L.taskAttentionNotificationTitle
                content.body = L.taskAttentionNotificationBody
            }
        }
        content.sound = .default
        return UNNotificationRequest(
            identifier: SystemTaskNotificationClient.identifierPrefix + dedupeKey,
            content: content,
            trigger: nil
        )
    }

    private func remember(_ key: String) {
        guard notifiedEventKeySet.insert(key).inserted else { return }
        notifiedEventKeys.append(key)
        if notifiedEventKeys.count > Self.maximumRememberedEvents {
            let overflow = notifiedEventKeys.count - Self.maximumRememberedEvents
            let removed = notifiedEventKeys.prefix(overflow)
            notifiedEventKeys.removeFirst(overflow)
            for key in removed {
                notifiedEventKeySet.remove(key)
            }
        }
        defaults.set(notifiedEventKeys, forKey: Self.notifiedEventKeysDefaultsKey)
    }

    private static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
