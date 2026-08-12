import Foundation
import UserNotifications

enum ReminderNotificationDeliveryResult: Equatable {
    case delivered
    case notAuthorized
    case failed
}

enum ReminderNotificationContent {
    static let requestIdentifierPrefix = "rest-required"
    static let episodeIDKey = "overloadEpisodeID"
    static let reminderMultipleKey = "reminderMultiple"

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
        language: AppLanguage = .zhHans
    ) async -> ReminderNotificationDeliveryResult {
        guard await ensureAuthorization() else {
            return .notAuthorized
        }

        clearReminder()
        let content = ReminderNotificationContent.make(
            fatigueDisplay: fatigueDisplay,
            episodeID: episodeID,
            reminderMultiple: reminderMultiple,
            language: language
        )
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
            return .delivered
        } catch {
            return .failed
        }
    }

    func clearReminder() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
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
