import Foundation
import SwiftData

/// Persisted daily rollup used for the Trends tab and correlation analysis.
/// Populated from HealthKit (or mock data) once per day and cached locally
/// so trend charts don't need to re-query HealthKit on every launch.
@Model
final class DailyMetrics {
    var id: UUID
    var date: Date

    var recoveryPercentage: Double
    var hrvMilliseconds: Double
    var restingHeartRate: Double

    var strainValue: Double
    var activeCalories: Double

    var sleepDurationSeconds: TimeInterval
    var sleepEfficiencyPercentage: Double
    var sleepDebtSeconds: TimeInterval

    var averageStressScore: Double

    init(
        date: Date,
        recoveryPercentage: Double,
        hrvMilliseconds: Double,
        restingHeartRate: Double,
        strainValue: Double,
        activeCalories: Double,
        sleepDurationSeconds: TimeInterval,
        sleepEfficiencyPercentage: Double,
        sleepDebtSeconds: TimeInterval,
        averageStressScore: Double
    ) {
        self.id = UUID()
        self.date = date.startOfDay
        self.recoveryPercentage = recoveryPercentage
        self.hrvMilliseconds = hrvMilliseconds
        self.restingHeartRate = restingHeartRate
        self.strainValue = strainValue
        self.activeCalories = activeCalories
        self.sleepDurationSeconds = sleepDurationSeconds
        self.sleepEfficiencyPercentage = sleepEfficiencyPercentage
        self.sleepDebtSeconds = sleepDebtSeconds
        self.averageStressScore = averageStressScore
    }
}
