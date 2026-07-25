import Foundation

struct CorrelationInsight: Identifiable, Hashable {
    var id: String { factor.rawValue }
    var factor: JournalFactor
    var averageRecoveryWithFactor: Double
    var averageRecoveryWithoutFactor: Double
    var sampleSize: Int

    var deltaPercentage: Double {
        averageRecoveryWithFactor - averageRecoveryWithoutFactor
    }

    var headline: String {
        let direction = deltaPercentage < 0 ? "niedriger" : "höher"
        return "Deine Recovery ist im Schnitt \(Int(abs(deltaPercentage).rounded()))% \(direction) an Tagen nach „\(factor.rawValue)“."
    }
}

/// Correlates journal factors logged the evening before with the following
/// day's recovery score, surfacing the strongest patterns to the user.
enum CorrelationEngine {
    static func insights(
        metrics: [DailyMetrics],
        journalEntries: [JournalEntry],
        minimumSampleSize: Int = 2
    ) -> [CorrelationInsight] {
        var metricsByDate: [Date: DailyMetrics] = [:]
        for metric in metrics {
            metricsByDate[metric.date.startOfDay] = metric
        }

        var results: [CorrelationInsight] = []

        for factor in JournalFactor.allCases {
            var withFactor: [Double] = []
            var withoutFactor: [Double] = []

            for entry in journalEntries {
                let nextDay = entry.date.addingDays(1)
                guard let nextMetric = metricsByDate[nextDay] else { continue }

                if entry.factors.contains(factor) {
                    withFactor.append(nextMetric.recoveryPercentage)
                } else {
                    withoutFactor.append(nextMetric.recoveryPercentage)
                }
            }

            guard withFactor.count >= minimumSampleSize, !withoutFactor.isEmpty else { continue }

            let avgWith = withFactor.reduce(0, +) / Double(withFactor.count)
            let avgWithout = withoutFactor.reduce(0, +) / Double(withoutFactor.count)

            results.append(
                CorrelationInsight(
                    factor: factor,
                    averageRecoveryWithFactor: avgWith,
                    averageRecoveryWithoutFactor: avgWithout,
                    sampleSize: withFactor.count
                )
            )
        }

        return results.sorted { abs($0.deltaPercentage) > abs($1.deltaPercentage) }
    }

    /// Simple, always-available insight requiring no journal data:
    /// recovery on nights with < 7h sleep vs. nights with >= 7h sleep.
    static func shortSleepInsight(metrics: [DailyMetrics]) -> String? {
        let short = metrics.filter { $0.sleepDurationSeconds < 7 * 3600 }.map(\.recoveryPercentage)
        let long = metrics.filter { $0.sleepDurationSeconds >= 7 * 3600 }.map(\.recoveryPercentage)
        guard short.count >= 2, !long.isEmpty else { return nil }

        let avgShort = short.reduce(0, +) / Double(short.count)
        let avgLong = long.reduce(0, +) / Double(long.count)
        let delta = avgLong - avgShort
        guard delta > 3 else { return nil }

        return "Dein Recovery ist im Schnitt \(Int(delta))% niedriger nach Nächten mit weniger als 7h Schlaf."
    }
}
