import Foundation
import UserNotifications

actor NotificationService {
    private let defaults = UserDefaults.standard
    private let tokenNotificationKey = "TokenIsland.Notifications.TokenThresholdDay"
    private let costNotificationKey = "TokenIsland.Notifications.CostThresholdDay"

    func requestAuthorizationIfNeeded() async {
        guard Self.canUseUserNotifications else {
            AppLog.app.info("Skipping notification authorization outside an app bundle.")
            return
        }

        do {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            AppLog.app.error("Notification authorization failed: \(error.localizedDescription)")
        }
    }

    func evaluateThresholds(summary: UsageSummary, settings: AppSettings) async {
        guard settings.enableThresholdNotifications else { return }
        let dayKey = Self.dayKey(for: Date())
        if summary.totalTokensToday >= settings.dailyTokenThreshold,
           defaults.string(forKey: tokenNotificationKey) != dayKey {
            await send(
                identifier: "token-threshold-\(dayKey)",
                title: "Token threshold reached",
                body: "Today reached \(AppFormatters.tokens(summary.totalTokensToday)) tokens."
            )
            defaults.set(dayKey, forKey: tokenNotificationKey)
        }

        if summary.estimatedCostTodayUSD >= settings.dailyCostThresholdUSD,
           defaults.string(forKey: costNotificationKey) != dayKey {
            await send(
                identifier: "cost-threshold-\(dayKey)",
                title: "Cost threshold reached",
                body: "Today reached \(AppFormatters.currency(summary.estimatedCostTodayUSD)) estimated spend."
            )
            defaults.set(dayKey, forKey: costNotificationKey)
        }
    }

    private func send(identifier: String, title: String, body: String) async {
        guard Self.canUseUserNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            AppLog.app.error("Notification delivery failed: \(error.localizedDescription)")
        }
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static var canUseUserNotifications: Bool {
        canUseUserNotifications(
            bundleURL: Bundle.main.bundleURL,
            bundleIdentifier: Bundle.main.bundleIdentifier
        )
    }

    static func canUseUserNotifications(bundleURL: URL, bundleIdentifier: String?) -> Bool {
        bundleURL.pathExtension == "app" && bundleIdentifier != nil
    }
}
