import Foundation

enum SleepAnalyzer {
    /// Accumulated sleep debt across the trailing window (positive = owed sleep).
    static func sleepDebt(sessions: [SleepSession]) -> TimeInterval {
        sessions.reduce(0) { $0 + $1.sleepDebtSeconds }
    }

    /// 0...100 score describing how consistent bed/wake times have been.
    /// Lower variance in bedtime and wake time -> higher score.
    static func consistencyScore(sessions: [SleepSession]) -> Double {
        guard sessions.count > 1 else { return 100 }

        let bedtimeMinutes = sessions.map { minutesSinceMidnight($0.bedtime) }
        let wakeMinutes = sessions.map { minutesSinceMidnight($0.wakeTime) }

        let bedtimeStdDev = standardDeviation(bedtimeMinutes)
        let wakeStdDev = standardDeviation(wakeMinutes)
        let averageStdDev = (bedtimeStdDev + wakeStdDev) / 2

        // 0 minutes deviation -> 100, 120+ minutes deviation -> ~0
        return (100 - averageStdDev * 0.83).clamped(to: 0...100)
    }

    /// Suggests a bedtime tonight so the user wakes up at `targetWakeTime`
    /// with enough sleep to pay down debt, weighted by how low recovery is.
    static func recommendedBedtime(
        targetWakeTime: Date,
        neededSleepSeconds: TimeInterval,
        currentSleepDebtSeconds: TimeInterval,
        recoveryPercentage: Double
    ) -> Date {
        let debtPayback = min(currentSleepDebtSeconds * 0.3, 45 * 60)
        let recoveryBonus = recoveryPercentage < 34 ? 30 * 60.0 : 0
        let totalNeeded = neededSleepSeconds + debtPayback + recoveryBonus
        return targetWakeTime.addingTimeInterval(-totalNeeded)
    }

    private static func minutesSinceMidnight(_ date: Date) -> Double {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance)
    }
}
