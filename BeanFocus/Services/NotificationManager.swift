import Foundation
import UserNotifications

/// Local, user-opt-in push notifications for sustained high stress.
/// No remote push infrastructure is used - everything is scheduled on-device.
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    private let center = UNUserNotificationCenter.current()
    private let highStressNotificationID = "com.beanfocus.highStress"

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Call whenever a fresh stress reading comes in. Fires at most once per
    /// `cooldown` interval to avoid spamming the user.
    func notifyIfSustainedStress(recentSamples: [StressSample], threshold: Double = 66, cooldown: TimeInterval = 3600) {
        guard recentSamples.count >= 4 else { return }
        let sustained = recentSamples.suffix(4).allSatisfy { $0.score >= threshold }
        guard sustained else { return }

        center.getPendingNotificationRequests { [weak self] pending in
            guard let self, !pending.contains(where: { $0.identifier == self.highStressNotificationID }) else { return }

            let content = UNMutableNotificationContent()
            content.title = "Anhaltender Stress erkannt"
            content.body = "Deine HRV deutet seit über einer Stunde auf erhöhten Stress hin. Eine kurze Pause könnte helfen."
            content.sound = .default

            let request = UNNotificationRequest(identifier: self.highStressNotificationID, content: content, trigger: nil)
            self.center.add(request)

            // Clear the identifier again after the cooldown so future spikes can re-notify.
            DispatchQueue.main.asyncAfter(deadline: .now() + cooldown) {
                self.center.removePendingNotificationRequests(withIdentifiers: [self.highStressNotificationID])
            }
        }
    }
}
