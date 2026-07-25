import Foundation
import Observation

@MainActor
@Observable
final class StressViewModel {
    var timeline: [StressSample] = []
    var currentScore: Double = 0
    var isLoading = false
    var notificationsEnabled = false

    private let provider: HealthDataProviding

    init(provider: HealthDataProviding = AppEnvironment.shared.healthDataProvider) {
        self.provider = provider
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let today = Date()
        let samples = (try? await provider.fetchHRV(from: today.startOfDay, to: today)) ?? []
        timeline = samples.isEmpty ? MockData.stressTimeline(for: today) : samples
        currentScore = timeline.last?.score ?? 0

        if notificationsEnabled {
            NotificationManager.shared.notifyIfSustainedStress(recentSamples: timeline)
        }
    }

    func timeSpent(in level: StressLevel) -> TimeInterval {
        StressCalculator.timeInState(level, samples: timeline, sampleInterval: 30 * 60)
    }

    func toggleNotifications() async {
        notificationsEnabled.toggle()
        if notificationsEnabled {
            notificationsEnabled = await NotificationManager.shared.requestAuthorization()
        }
    }
}
