import CryptoKit
import Combine
import Foundation
import UserNotifications

protocol TaskNotificationClient: AnyObject {
    func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void)
    func requestAuthorization(completion: @escaping (Bool) -> Void)
    func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void)
    func setResponseHandler(_ handler: @escaping () -> Void)
}

final class SystemTaskNotificationClient: NSObject, TaskNotificationClient, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    private var responseHandler: (() -> Void)?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
    }

    func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { settings in
            completion(settings.authorizationStatus)
        }
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            completion(granted)
        }
    }

    func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
        center.add(request, withCompletionHandler: completion)
    }

    func setResponseHandler(_ handler: @escaping () -> Void) {
        responseHandler = handler
        center.delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        guard notification.request.identifier.hasPrefix(Self.identifierPrefix) else {
            completionHandler([])
            return
        }
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.notification.request.identifier.hasPrefix(Self.identifierPrefix) else {
            completionHandler()
            return
        }
        responseHandler?()
        completionHandler()
    }

    static let identifierPrefix = "codexbar-task-attention-"
}

@MainActor
final class TaskNotificationService: ObservableObject {
    static let shared = TaskNotificationService()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var onOpenCodex: (() -> Void)?

    private static let enabledDefaultsKey = "codexbar.taskAttentionNotificationsEnabled"
    private static let notifiedEventKeysDefaultsKey = "codexbar.taskAttentionNotifiedEventKeys"
    private static let maximumRememberedEvents = 512
    private static let productionAttentionDelayNanoseconds: UInt64 = 15_000_000_000

    private let notificationClient: TaskNotificationClient
    private let defaults: UserDefaults
    private let attentionDelayNanoseconds: UInt64
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
        attentionDelayNanoseconds: UInt64 = 0
    ) {
        self.notificationClient = notificationClient
        self.defaults = defaults
        self.attentionDelayNanoseconds = attentionDelayNanoseconds
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
        notificationClient.authorizationStatus { [weak self] status in
            Task { @MainActor in
                self?.applyAuthorizationStatus(status)
            }
        }
    }

    @discardableResult
    func enable() async -> Bool {
        defaults.set(true, forKey: Self.enabledDefaultsKey)
        let granted = await withCheckedContinuation { continuation in
            notificationClient.requestAuthorization { granted in
                continuation.resume(returning: granted)
            }
        }
        let status = await currentAuthorizationStatus()
        applyAuthorizationStatus(status)
        return granted && Self.isAuthorized(status)
    }

    func disable() {
        defaults.set(false, forKey: Self.enabledDefaultsKey)
        isEnabled = false
        cancelAllPendingNotifications()
    }

    func process(snapshot: TaskCenterSnapshot) {
        latestSnapshot = snapshot
        let activeDedupeKeys = Set(snapshot.needsAttentionRecords.map { Self.digest($0.eventKey) })
        for (dedupeKey, task) in pendingNotificationTasks where !activeDedupeKeys.contains(dedupeKey) {
            task.cancel()
            pendingNotificationTasks.removeValue(forKey: dedupeKey)
        }

        guard isEnabled else {
            cancelAllPendingNotifications()
            return
        }

        for record in snapshot.needsAttentionRecords {
            let dedupeKey = Self.digest(record.eventKey)
            guard !notifiedEventKeySet.contains(dedupeKey),
                  pendingNotificationTasks[dedupeKey] == nil else { continue }

            if attentionDelayNanoseconds == 0 {
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
                      self.latestSnapshot?.needsAttentionRecords.contains(where: {
                          Self.digest($0.eventKey) == dedupeKey
                      }) == true else { return }
                self.sendNotification(for: record, dedupeKey: dedupeKey)
            }
        }
    }

    private func sendNotification(for record: TaskActivityRecord, dedupeKey: String) {
        // Persist before handing the request to the notification center.
        // This provides at-most-once scheduling even if the app exits
        // between system acceptance and the completion callback.
        remember(dedupeKey)
        let request = notificationRequest(for: record, dedupeKey: dedupeKey)
        notificationClient.add(request) { _ in }
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
        if !isEnabled {
            cancelAllPendingNotifications()
        }
        if !wasEnabled, isEnabled, let latestSnapshot {
            process(snapshot: latestSnapshot)
        }
    }

    private func notificationRequest(for record: TaskActivityRecord, dedupeKey: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = L.taskAttentionNotificationTitle
        content.body = L.taskAttentionNotificationBody
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
