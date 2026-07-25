import Foundation
import Observation

@MainActor
@Observable
final class RecoveryViewModel {
    var todayRecovery: RecoveryScore?
    var history: [RecoveryScore] = []
    var isLoading = false

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
            let baseline = try await provider.fetchLatestHRVBaseline(before: today, days: 30)
            let hrvSamples = try await provider.fetchHRV(from: today.startOfDay, to: today)
            let hrv = hrvSamples.last?.hrvMilliseconds ?? baseline
            let rhr = try await provider.fetchRestingHeartRate(for: today)
            let sleep = try await provider.fetchSleepSession(for: today)

            todayRecovery = RecoveryCalculator.calculate(
                date: today,
                hrv: hrv,
                hrvBaseline: baseline,
                restingHeartRate: rhr,
                restingHeartRateBaseline: rhr + 3,
                sleepSession: sleep
            )
            history = MockData.recoveryHistory(days: 30, endingAt: today)
        } catch {
            todayRecovery = MockData.todayRecovery(reference: today)
            history = MockData.recoveryHistory(days: 30, endingAt: today)
        }
    }

    var factorBreakdown: [(title: String, value: String, systemImage: String)] {
        guard let recovery = todayRecovery else { return [] }
        return [
            ("HRV", "\(Int(recovery.hrvMilliseconds)) ms", "waveform.path.ecg"),
            ("Ruhepuls", recovery.restingHeartRate.asBPM, "heart.fill"),
            ("Schlaf-Performance", recovery.sleepPerformancePercentage.asPercentInt, "bed.double.fill")
        ]
    }
}
