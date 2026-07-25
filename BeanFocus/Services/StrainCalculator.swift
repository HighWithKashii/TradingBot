import Foundation

/// Computes a Whoop-style strain value on a 0...21 scale from time spent in
/// heart rate zones throughout the day. Whoop uses a proprietary algorithm
/// based on heart rate relative to VO2 max; here we approximate it with a
/// weighted "cardiovascular load" that we compress onto 0...21 using a log
/// curve, which reproduces the characteristic Whoop feel: strain rises fast
/// at first and requires exponentially more effort to approach the max.
enum StrainCalculator {
    /// Relative weight of each heart rate zone - higher zones count for more.
    private static let zoneWeights: [HeartRateZone: Double] = [
        .zone1: 0.5,
        .zone2: 1.0,
        .zone3: 2.0,
        .zone4: 3.5,
        .zone5: 5.0
    ]

    static func calculateDailyStrain(
        date: Date,
        heartRateSamples: [HeartRateSample],
        maxHeartRate: Double,
        recoveryPercentage: Double
    ) -> StrainScore {
        let zoneMinutes = minutesPerZone(samples: heartRateSamples, maxHeartRate: maxHeartRate)
        let load = zoneMinutes.reduce(0.0) { partial, entry in
            partial + (entry.value * (zoneWeights[entry.key] ?? 0))
        }

        // Compress the raw load onto 0...21 with a log curve.
        let value = min(21, log(load + 1) * 3.2)

        let avgHR = heartRateSamples.isEmpty ? 0 : heartRateSamples.reduce(0) { $0 + $1.beatsPerMinute } / Double(heartRateSamples.count)
        let maxHR = heartRateSamples.map(\.beatsPerMinute).max() ?? 0
        let activeCalories = load * 8.5

        return StrainScore(
            date: date,
            value: value,
            targetValue: targetStrain(forRecovery: recoveryPercentage),
            averageHeartRate: avgHR,
            maxHeartRate: maxHR,
            activeCalories: activeCalories,
            heartRateZoneMinutes: zoneMinutes
        )
    }

    /// Higher recovery unlocks a higher recommended strain target for the day.
    static func targetStrain(forRecovery recoveryPercentage: Double) -> Double {
        switch recoveryPercentage {
        case 67...: return 14 + (recoveryPercentage - 67) / 33 * 6 // 14...20
        case 34..<67: return 9 + (recoveryPercentage - 34) / 33 * 5 // 9...14
        default: return 4 + recoveryPercentage / 34 * 5 // 4...9
        }
    }

    static func strainContribution(averageHeartRate: Double, maxHeartRate: Double, duration: TimeInterval) -> Double {
        guard maxHeartRate > 0 else { return 0 }
        let intensity = averageHeartRate / maxHeartRate
        let minutes = duration / 60
        return min(21, log((intensity * minutes * 4) + 1) * 3.2)
    }

    private static func minutesPerZone(samples: [HeartRateSample], maxHeartRate: Double) -> [HeartRateZone: Double] {
        guard maxHeartRate > 0, !samples.isEmpty else {
            return Dictionary(uniqueKeysWithValues: HeartRateZone.allCases.map { ($0, 0.0) })
        }
        var minutes = Dictionary(uniqueKeysWithValues: HeartRateZone.allCases.map { ($0, 0.0) })
        // Each sample is assumed to represent ~1 minute of continuous monitoring.
        for sample in samples {
            let percentage = sample.beatsPerMinute / maxHeartRate
            if let zone = HeartRateZone.allCases.reversed().first(where: { percentage >= $0.lowerBoundPercentage }) {
                minutes[zone, default: 0] += 1
            }
        }
        return minutes
    }
}
