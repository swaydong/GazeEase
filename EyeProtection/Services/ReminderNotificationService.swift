import Foundation
import UserNotifications

enum ReminderNotificationDeliveryResult: Equatable {
    case delivered
    case notAuthorized
    case failed
    case cancelled
}

@MainActor
final class ReminderNotificationDeliveryGate {
    private var currentID: UUID?
    private var isStillRelevant: (() -> Bool)?

    func begin(isStillRelevant: @escaping () -> Bool) -> UUID {
        let id = UUID()
        currentID = id
        self.isStillRelevant = isStillRelevant
        return id
    }

    func allows(_ id: UUID?) -> Bool {
        guard let id, id == currentID else { return false }
        return isStillRelevant?() == true
    }

    func invalidate() {
        currentID = nil
        isStillRelevant = nil
    }
}

enum ReminderNotificationContent {
    static let requestIdentifierPrefix = "rest-required"
    static let episodeIDKey = "overloadEpisodeID"
    static let reminderMultipleKey = "reminderMultiple"
    static let deliveryIDKey = "deliveryID"

    static func requestIdentifier(episodeID: UUID, reminderMultiple: Int) -> String {
        "\(requestIdentifierPrefix).\(episodeID.uuidString).\(max(1, reminderMultiple))"
    }

    static func make(
        fatigueDisplay: String,
        episodeID: UUID,
        reminderMultiple: Int,
        language: AppLanguage = .zhHans
    ) -> UNMutableNotificationContent {
        let normalizedMultiple = max(1, reminderMultiple)
        let content = UNMutableNotificationContent()
        content.title = AppLocalization.format(
            .notificationMilestoneTitle,
            language: language,
            arguments: [normalizedMultiple * 100]
        )
        content.body = AppLocalization.format(
            .notificationMilestoneBody,
            language: language,
            arguments: [fatigueDisplay]
        )
        content.userInfo = [
            episodeIDKey: episodeID.uuidString,
            reminderMultipleKey: normalizedMultiple,
        ]
        content.threadIdentifier = requestIdentifierPrefix
        return content
    }
}

@MainActor
final class ReminderNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderNotificationService()

    var onOpen: ((UUID) -> Void)? {
        didSet {
            guard let pendingOpenEpisodeID else { return }
            self.pendingOpenEpisodeID = nil
            onOpen?(pendingOpenEpisodeID)
        }
    }

    private let center = UNUserNotificationCenter.current()
    private var isConfigured = false
    private var pendingOpenEpisodeID: UUID?
    private let deliveryGate = ReminderNotificationDeliveryGate()

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        center.delegate = self
    }

    func ensureAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert])) == true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func deliver(
        fatigueDisplay: String,
        episodeID: UUID,
        reminderMultiple: Int = 1,
        language: AppLanguage = .zhHans,
        isStillRelevant: @escaping () -> Bool = { true }
    ) async -> ReminderNotificationDeliveryResult {
        guard isStillRelevant() else { return .cancelled }
        let authorized = await ensureAuthorization()
        guard isStillRelevant() else { return .cancelled }
        guard authorized else {
            return .notAuthorized
        }

        clearReminder()
        let deliveryID = deliveryGate.begin(isStillRelevant: isStillRelevant)
        let content = ReminderNotificationContent.make(
            fatigueDisplay: fatigueDisplay,
            episodeID: episodeID,
            reminderMultiple: reminderMultiple,
            language: language
        )
        content.userInfo[ReminderNotificationContent.deliveryIDKey] = deliveryID.uuidString
        let request = UNNotificationRequest(
            identifier: ReminderNotificationContent.requestIdentifier(
                episodeID: episodeID,
                reminderMultiple: reminderMultiple
            ),
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            guard deliveryGate.allows(deliveryID) else { return .cancelled }
            return .delivered
        } catch {
            return .failed
        }
    }

    func clearReminder() {
        deliveryGate.invalidate()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let deliveryID = (notification.request.content.userInfo[
            ReminderNotificationContent.deliveryIDKey
        ] as? String).flatMap(UUID.init(uuidString:))
        let allowed = await MainActor.run { [weak self] in
            self?.deliveryGate.allows(deliveryID) == true
        }
        return allowed ? [.banner, .list] : []
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let episodeID = (response.notification.request.content.userInfo[
            ReminderNotificationContent.episodeIDKey
        ] as? String).flatMap(UUID.init(uuidString:))
        let shouldOpen = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        completionHandler()

        guard shouldOpen, let episodeID else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let onOpen {
                onOpen(episodeID)
            } else {
                pendingOpenEpisodeID = episodeID
            }
        }
    }
}
