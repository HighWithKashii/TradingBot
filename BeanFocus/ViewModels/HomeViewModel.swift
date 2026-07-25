import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    var recovery: RecoveryScore?
    var strain: StrainScore?
    var sleepSession: SleepSession?
    var last7DaysRecovery: [RecoveryScore] = []
    var isLoading = false
    var errorMessage: String?

    private let provider: HealthDataProviding

    init(provider: HealthDataProviding = AppEnvironment.shared.healthDataProvider) {
        self.provider = provider
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let today = Date()
        do {
            try await provider.requestAuthorization()

            async let hrvBaseline = provider.fetchLatestHRVBaseline(before: today, days: 30)
            async let hrvSamples = provider.fetchHRV(from: today.startOfDay, to: today)
            async let restingHR = provider.fetchRestingHeartRate(for: today)
            async let sleep = provider.fetchSleepSession(for: today)
            async let heartRateSamples = provider.fetchHeartRateSamples(from: today.startOfDay, to: today)

            let baseline = try await hrvBaseline
            let hrv = try await hrvSamples.last?.hrvMilliseconds ?? baseline
            let rhr = try await restingHR
            let sleepResult = try await sleep
            let hrSamples = try await heartRateSamples

            let recoveryScore = RecoveryCalculator.calculate(
                date: today,
                hrv: hrv,
                hrvBaseline: baseline,
                restingHeartRate: rhr,
                restingHeartRateBaseline: rhr + 3,
                sleepSession: sleepResult
            )

            self.recovery = recoveryScore
            self.sleepSession = sleepResult
            self.strain = StrainCalculator.calculateDailyStrain(
                date: today,
                heartRateSamples: hrSamples,
                maxHeartRate: 190,
                recoveryPercentage: recoveryScore.percentage
            )
            self.last7DaysRecovery = MockData.recoveryHistory(days: 7)
        } catch {
            self.errorMessage = error.localizedDescription
            loadFallbackMockData(today: today)
        }
    }

    private func loadFallbackMockData(today: Date) {
        recovery = MockData.todayRecovery(reference: today)
        strain = MockData.todayStrain(reference: today)
        sleepSession = MockData.sleepSession(for: today)
        last7DaysRecovery = MockData.recoveryHistory(days: 7, endingAt: today)
    }
}
