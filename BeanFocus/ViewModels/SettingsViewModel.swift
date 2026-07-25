import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    var useMockData: Bool {
        get { AppEnvironment.shared.useMockData }
        set { AppEnvironment.shared.useMockData = newValue }
    }
    var stressNotificationsEnabled = false
    var userName = "Athlet"
    var dateOfBirth = Calendar.current.date(byAdding: .year, value: -28, to: Date()) ?? Date()

    func requestNotificationPermission() async {
        stressNotificationsEnabled = await NotificationManager.shared.requestAuthorization()
    }
}
