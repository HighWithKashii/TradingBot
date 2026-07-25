import Foundation
import Observation

@MainActor
@Observable
final class StrainViewModel {
    var todayStrain: StrainScore?
    var history: [StrainScore] = []
    var workouts: [WorkoutSession] = []
    var liveHeartRate: Double?
    var isLiveWorkoutActive = false
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
            let heartRateSamples = try await provider.fetchHeartRateSamples(from: today.startOfDay, to: today)
            let recovery = MockData.todayRecovery(reference: today)
            todayStrain = StrainCalculator.calculateDailyStrain(
                date: today,
                heartRateSamples: heartRateSamples,
                maxHeartRate: 190,
                recoveryPercentage: recovery.percentage
            )
            workouts = try await provider.fetchWorkouts(for: today)
            history = MockData.strainHistory(days: 30, endingAt: today)
        } catch {
            todayStrain = MockData.todayStrain(reference: today)
            workouts = MockData.workouts(for: today)
            history = MockData.strainHistory(days: 30, endingAt: today)
        }
    }

    func startLiveWorkout() {
        isLiveWorkoutActive = true
        provider.startLiveHeartRateUpdates { [weak self] sample in
            Task { @MainActor in
                self?.liveHeartRate = sample.beatsPerMinute
            }
        }
    }

    func stopLiveWorkout() {
        isLiveWorkoutActive = false
        provider.stopLiveHeartRateUpdates()
        liveHeartRate = nil
    }

    var zoneBreakdown: [(zone: HeartRateZone, minutes: Double)] {
        guard let todayStrain else { return [] }
        return HeartRateZone.allCases.map { ($0, todayStrain.heartRateZoneMinutes[$0] ?? 0) }
    }
}
