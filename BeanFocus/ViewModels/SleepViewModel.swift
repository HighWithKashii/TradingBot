import Foundation
import Observation

@MainActor
@Observable
final class SleepViewModel {
    var todaySession: SleepSession?
    var history: [SleepSession] = []
    var sleepDebt: TimeInterval = 0
    var consistencyScore: Double = 0
    var recommendedBedtime: Date?
    var isLoading = false

    private let provider: HealthDataProviding

    init(provider: HealthDataProviding = AppEnvironment.shared.healthDataProvider) {
        self.provider = provider
    }

    func load(recoveryPercentage: Double = 60) async {
        isLoading = true
        defer { isLoading = false }

        let today = Date()
        let session = (try? await provider.fetchSleepSession(for: today)) ?? MockData.sleepSession(for: today)
        todaySession = session

        history = MockData.sleepHistory(days: 14, endingAt: today)
        sleepDebt = SleepAnalyzer.sleepDebt(sessions: Array(history.suffix(7)))
        consistencyScore = SleepAnalyzer.consistencyScore(sessions: history)

        let targetWake = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: today.addingDays(1)) ?? today
        recommendedBedtime = SleepAnalyzer.recommendedBedtime(
            targetWakeTime: targetWake,
            neededSleepSeconds: session.neededSleepSeconds,
            currentSleepDebtSeconds: sleepDebt,
            recoveryPercentage: recoveryPercentage
        )
    }
}
