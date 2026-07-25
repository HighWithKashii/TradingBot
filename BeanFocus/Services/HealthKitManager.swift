import Foundation
import HealthKit

/// Real HealthKit-backed implementation of `HealthDataProviding`.
///
/// NOTE: The iOS Simulator has no sensors, so heart rate, HRV, SpO2 and sleep
/// stage data will only exist here if you manually add samples via the
/// Health app on the Simulator (Health app -> Browse -> add data points), or
/// if you run this on a real device paired with an Apple Watch. For
/// day-to-day UI development use `MockHealthDataProvider` instead (see
/// `AppEnvironment.swift`).
final class HealthKitManager: HealthDataProviding {
    private let store = HKHealthStore()
    private var liveHeartRateQuery: HKQuery?

    static let readTypes: Set<HKObjectType> = [
        quantityType(.heartRate),
        quantityType(.heartRateVariabilitySDNN),
        quantityType(.restingHeartRate),
        quantityType(.respiratoryRate),
        quantityType(.oxygenSaturation),
        quantityType(.activeEnergyBurned),
        quantityType(.appleExerciseTime),
        categoryType(.sleepAnalysis),
        HKObjectType.workoutType()
    ]

    private static func quantityType(_ identifier: HKQuantityTypeIdentifier) -> HKQuantityType {
        HKQuantityType.quantityType(forIdentifier: identifier)!
    }

    private static func categoryType(_ identifier: HKCategoryTypeIdentifier) -> HKCategoryType {
        HKCategoryType.categoryType(forIdentifier: identifier)!
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthDataError.healthKitUnavailable
        }
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    // MARK: - Heart Rate

    func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateSample] {
        let type = Self.quantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
                }
            }
            store.execute(query)
        }
        let unit = HKUnit.count().unitDivided(by: .minute())
        return samples.map {
            HeartRateSample(timestamp: $0.startDate, beatsPerMinute: $0.quantity.doubleValue(for: unit))
        }
    }

    func fetchRestingHeartRate(for date: Date) async throws -> Double {
        try await averageQuantity(
            type: Self.quantityType(.restingHeartRate),
            unit: HKUnit.count().unitDivided(by: .minute()),
            date: date
        )
    }

    func fetchHRV(from start: Date, to end: Date) async throws -> [StressSample] {
        let type = Self.quantityType(.heartRateVariabilitySDNN)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
                }
            }
            store.execute(query)
        }
        let unit = HKUnit.secondUnit(with: .milli)
        return samples.map { sample in
            let hrv = sample.quantity.doubleValue(for: unit)
            return StressSample(
                timestamp: sample.startDate,
                score: StressCalculator.score(fromInstantHRV: hrv, baseline: hrv),
                hrvMilliseconds: hrv
            )
        }
    }

    func fetchLatestHRVBaseline(before date: Date, days: Int) async throws -> Double {
        let start = date.addingDays(-days)
        let samples = try await fetchHRV(from: start, to: date)
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0) { $0 + $1.hrvMilliseconds } / Double(samples.count)
    }

    func fetchRespiratoryRate(for date: Date) async throws -> Double {
        try await averageQuantity(
            type: Self.quantityType(.respiratoryRate),
            unit: HKUnit.count().unitDivided(by: .minute()),
            date: date
        )
    }

    func fetchOxygenSaturation(for date: Date) async throws -> Double {
        let value = try await averageQuantity(
            type: Self.quantityType(.oxygenSaturation),
            unit: .percent(),
            date: date
        )
        return value * 100
    }

    func fetchActiveCalories(for date: Date) async throws -> Double {
        try await sumQuantity(
            type: Self.quantityType(.activeEnergyBurned),
            unit: .kilocalorie(),
            date: date
        )
    }

    // MARK: - Sleep

    func fetchSleepSession(for date: Date) async throws -> SleepSession? {
        let windowStart = date.startOfDay.addingDays(-1)
        let windowEnd = date.startOfDay.addingDays(1)
        let type = Self.categoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: .strictStartDate)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
                }
            }
            store.execute(query)
        }

        guard !samples.isEmpty else { return nil }

        let intervals: [SleepStageInterval] = samples.compactMap { sample in
            guard let stage = SleepStage(hkValue: sample.value) else { return nil }
            return SleepStageInterval(stage: stage, start: sample.startDate, end: sample.endDate)
        }
        guard let bedtime = intervals.map(\.start).min(),
              let wakeTime = intervals.map(\.end).max() else { return nil }

        return SleepSession(
            date: date.startOfDay,
            bedtime: bedtime,
            wakeTime: wakeTime,
            stages: intervals,
            neededSleepSeconds: 8 * 3600
        )
    }

    // MARK: - Workouts

    func fetchWorkouts(for date: Date) async throws -> [WorkoutSession] {
        let predicate = HKQuery.predicateForSamples(
            withStart: date.startOfDay,
            end: date.startOfDay.addingDays(1),
            options: .strictStartDate
        )
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (results as? [HKWorkout]) ?? [])
                }
            }
            store.execute(query)
        }

        var sessions: [WorkoutSession] = []
        for workout in workouts {
            let heartRates = try await fetchHeartRateSamples(from: workout.startDate, to: workout.endDate)
            let avgHR = heartRates.isEmpty ? 0 : heartRates.reduce(0) { $0 + $1.beatsPerMinute } / Double(heartRates.count)
            let maxHR = heartRates.map(\.beatsPerMinute).max() ?? 0
            let calories = workout.statistics(for: Self.quantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            sessions.append(
                WorkoutSession(
                    activityName: workout.workoutActivityType.displayName,
                    start: workout.startDate,
                    end: workout.endDate,
                    averageHeartRate: avgHR,
                    maxHeartRate: maxHR,
                    activeCalories: calories,
                    strainContribution: StrainCalculator.strainContribution(
                        averageHeartRate: avgHR,
                        maxHeartRate: maxHR,
                        duration: workout.endDate.timeIntervalSince(workout.startDate)
                    )
                )
            )
        }
        return sessions
    }

    // MARK: - Live updates

    func startLiveHeartRateUpdates(handler: @escaping (HeartRateSample) -> Void) {
        let type = Self.quantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil, options: .strictStartDate)
        let query = HKAnchoredObjectQuery(
            type: type,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { _, samples, _, _, _ in
            Self.emit(samples: samples, handler: handler)
        }
        query.updateHandler = { _, samples, _, _, _ in
            Self.emit(samples: samples, handler: handler)
        }
        store.execute(query)
        liveHeartRateQuery = query
    }

    func stopLiveHeartRateUpdates() {
        if let liveHeartRateQuery {
            store.stop(liveHeartRateQuery)
        }
        liveHeartRateQuery = nil
    }

    private static func emit(samples: [HKSample]?, handler: @escaping (HeartRateSample) -> Void) {
        guard let quantitySamples = samples as? [HKQuantitySample] else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        for sample in quantitySamples {
            handler(HeartRateSample(timestamp: sample.startDate, beatsPerMinute: sample.quantity.doubleValue(for: unit)))
        }
    }

    // MARK: - Helpers

    private func averageQuantity(type: HKQuantityType, unit: HKUnit, date: Date) async throws -> Double {
        let predicate = HKQuery.predicateForSamples(
            withStart: date.startOfDay,
            end: date.startOfDay.addingDays(1),
            options: .strictStartDate
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: statistics?.averageQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    private func sumQuantity(type: HKQuantityType, unit: HKUnit, date: Date) async throws -> Double {
        let predicate = HKQuery.predicateForSamples(
            withStart: date.startOfDay,
            end: date.startOfDay.addingDays(1),
            options: .strictStartDate
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }
}

private extension SleepStage {
    init?(hkValue: Int) {
        switch HKCategoryValueSleepAnalysis(rawValue: hkValue) {
        case .awake: self = .awake
        case .asleepREM: self = .rem
        case .asleepCore: self = .light
        case .asleepDeep: self = .deep
        case .asleepUnspecified: self = .light
        default: return nil
        }
    }
}

private extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running: return "Laufen"
        case .cycling: return "Radfahren"
        case .swimming: return "Schwimmen"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Krafttraining"
        case .yoga: return "Yoga"
        case .walking: return "Gehen"
        case .highIntensityIntervalTraining: return "HIIT"
        default: return "Training"
        }
    }
}
