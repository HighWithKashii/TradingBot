import Foundation

/// Central source of realistic sample data, used both by
/// `MockHealthDataProvider` (Simulator/dev builds) and directly by SwiftUI
/// `#Preview` blocks so every screen renders fully populated without ever
/// touching HealthKit.
enum MockData {
    private static var generator = SeededGenerator(seed: 7)

    // MARK: Recovery

    static func recoveryHistory(days: Int = 30, endingAt end: Date = Date()) -> [RecoveryScore] {
        Date.lastNDays(days, endingAt: end).map { day in
            let base = 55 + 30 * sin(Double(day.timeIntervalSince1970) / 900_000)
            let percentage = (base + Double.random(in: -12...12, using: &generator)).clamped(to: 8...98)
            return RecoveryScore(
                date: day,
                percentage: percentage,
                hrvMilliseconds: 45 + percentage * 0.35,
                restingHeartRate: 62 - percentage * 0.08,
                sleepPerformancePercentage: (percentage + Double.random(in: -10...10, using: &generator)).clamped(to: 0...100),
                previousHRVBaseline: 58
            )
        }
    }

    static func todayRecovery(reference: Date = Date()) -> RecoveryScore {
        recoveryHistory(days: 1, endingAt: reference).first ?? RecoveryScore(
            date: reference, percentage: 72, hrvMilliseconds: 64, restingHeartRate: 54,
            sleepPerformancePercentage: 81, previousHRVBaseline: 58
        )
    }

    // MARK: Strain

    static func strainHistory(days: Int = 30, endingAt end: Date = Date()) -> [StrainScore] {
        recoveryHistory(days: days, endingAt: end).map { recovery in
            let value = Double.random(in: 4...19, using: &generator)
            return StrainScore(
                date: recovery.date,
                value: value,
                targetValue: StrainCalculator.targetStrain(forRecovery: recovery.percentage),
                averageHeartRate: 95 + value,
                maxHeartRate: 150 + value * 2,
                activeCalories: 300 + value * 45,
                heartRateZoneMinutes: [
                    .zone1: Double.random(in: 60...240, using: &generator),
                    .zone2: Double.random(in: 20...120, using: &generator),
                    .zone3: Double.random(in: 5...60, using: &generator),
                    .zone4: Double.random(in: 0...30, using: &generator),
                    .zone5: Double.random(in: 0...12, using: &generator)
                ]
            )
        }
    }

    static func todayStrain(reference: Date = Date()) -> StrainScore {
        strainHistory(days: 1, endingAt: reference).first ?? StrainScore(
            date: reference, value: 11.4, targetValue: 14, averageHeartRate: 102, maxHeartRate: 168,
            activeCalories: 540, heartRateZoneMinutes: [.zone1: 120, .zone2: 45, .zone3: 20, .zone4: 8, .zone5: 2]
        )
    }

    // MARK: Sleep

    static func sleepSession(for date: Date) -> SleepSession {
        var localGenerator = SeededGenerator(seed: UInt64(date.startOfDay.timeIntervalSince1970))
        let bedtime = Calendar.current.date(
            bySettingHour: 23, minute: Int.random(in: 0...45, using: &localGenerator), second: 0, of: date.addingDays(-1)
        ) ?? date.addingDays(-1)
        let wakeTime = Calendar.current.date(
            bySettingHour: 7, minute: Int.random(in: 0...30, using: &localGenerator), second: 0, of: date
        ) ?? date

        var cursor = bedtime
        var stages: [SleepStageInterval] = []
        let pattern: [(SleepStage, TimeInterval)] = [
            (.light, 25 * 60), (.deep, 70 * 60), (.light, 40 * 60), (.rem, 25 * 60),
            (.light, 35 * 60), (.deep, 45 * 60), (.rem, 30 * 60), (.awake, 8 * 60),
            (.light, 50 * 60), (.rem, 35 * 60), (.light, 30 * 60)
        ]
        for (stage, duration) in pattern {
            guard cursor < wakeTime else { break }
            let end = min(cursor.addingTimeInterval(duration), wakeTime)
            stages.append(SleepStageInterval(stage: stage, start: cursor, end: end))
            cursor = end
        }

        return SleepSession(
            date: date.startOfDay,
            bedtime: bedtime,
            wakeTime: wakeTime,
            stages: stages,
            neededSleepSeconds: 8 * 3600
        )
    }

    static func sleepHistory(days: Int = 14, endingAt end: Date = Date()) -> [SleepSession] {
        Date.lastNDays(days, endingAt: end).map(sleepSession(for:))
    }

    // MARK: Stress

    static func stressTimeline(for date: Date = Date()) -> [StressSample] {
        var localGenerator = SeededGenerator(seed: UInt64(date.startOfDay.timeIntervalSince1970) &+ 99)
        let baseline = 60.0
        var samples: [StressSample] = []
        var cursor = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: date) ?? date
        let end = min(Date(), Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: date) ?? date)
        while cursor < end {
            let hour = Calendar.current.component(.hour, from: cursor)
            let stressBias: Double = (11...16).contains(hour) ? -18 : 0
            let hrv = max(15, baseline + stressBias + Double.random(in: -14...14, using: &localGenerator))
            samples.append(
                StressSample(
                    timestamp: cursor,
                    score: StressCalculator.score(fromInstantHRV: hrv, baseline: baseline),
                    hrvMilliseconds: hrv
                )
            )
            cursor = cursor.addingTimeInterval(30 * 60)
        }
        return samples
    }

    // MARK: Workouts

    static func workouts(for date: Date) -> [WorkoutSession] {
        var localGenerator = SeededGenerator(seed: UInt64(date.startOfDay.timeIntervalSince1970) &+ 55)
        guard Double.random(in: 0...1, using: &localGenerator) > 0.4 else { return [] }
        let start = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date
        let duration = TimeInterval(Int.random(in: 30...75, using: &localGenerator) * 60)
        return [
            WorkoutSession(
                activityName: ["Laufen", "Krafttraining", "Radfahren", "HIIT"].randomElement(using: &localGenerator) ?? "Training",
                start: start,
                end: start.addingTimeInterval(duration),
                averageHeartRate: Double.random(in: 120...155, using: &localGenerator),
                maxHeartRate: Double.random(in: 155...182, using: &localGenerator),
                activeCalories: Double.random(in: 250...650, using: &localGenerator),
                strainContribution: Double.random(in: 6...15, using: &localGenerator)
            )
        ]
    }

    // MARK: Daily metrics (Trends tab, correlation engine)

    static func dailyMetricsHistory(days: Int = 90, endingAt end: Date = Date()) -> [DailyMetrics] {
        let recoveries = recoveryHistory(days: days, endingAt: end)
        let strains = strainHistory(days: days, endingAt: end)
        return zip(recoveries, strains).map { recovery, strain in
            let sleep = sleepSession(for: recovery.date)
            return DailyMetrics(
                date: recovery.date,
                recoveryPercentage: recovery.percentage,
                hrvMilliseconds: recovery.hrvMilliseconds,
                restingHeartRate: recovery.restingHeartRate,
                strainValue: strain.value,
                activeCalories: strain.activeCalories,
                sleepDurationSeconds: sleep.timeAsleep,
                sleepEfficiencyPercentage: sleep.efficiencyPercentage,
                sleepDebtSeconds: sleep.sleepDebtSeconds,
                averageStressScore: StressCalculator.averageScore(from: stressTimeline(for: recovery.date))
            )
        }
    }

    // MARK: Journal

    static func journalHistory(days: Int = 30, endingAt end: Date = Date()) -> [JournalEntry] {
        var localGenerator = SeededGenerator(seed: 123)
        return Date.lastNDays(days, endingAt: end).compactMap { day in
            guard Double.random(in: 0...1, using: &localGenerator) > 0.25 else { return nil }
            let possible = JournalFactor.allCases
            let count = Int.random(in: 0...3, using: &localGenerator)
            let factors = Set(possible.shuffled(using: &localGenerator).prefix(count))
            return JournalEntry(
                date: day,
                factors: factors,
                moodRating: Int.random(in: 2...5, using: &localGenerator),
                note: ""
            )
        }
    }
}
