import Foundation

/// Computes the Whoop-style 0-100% recovery score from HRV, resting heart
/// rate and sleep quality. The exact weighting Whoop uses is proprietary;
/// this is a transparent, tunable approximation:
///
/// - HRV vs. personal baseline: 50%
/// - Resting heart rate vs. personal baseline: 20%
/// - Sleep performance (duration + efficiency vs. need): 30%
enum RecoveryCalculator {
    static func calculate(
        date: Date,
        hrv: Double,
        hrvBaseline: Double,
        restingHeartRate: Double,
        restingHeartRateBaseline: Double,
        sleepSession: SleepSession?
    ) -> RecoveryScore {
        let hrvComponent = hrvScore(hrv: hrv, baseline: hrvBaseline)
        let rhrComponent = restingHeartRateScore(rhr: restingHeartRate, baseline: restingHeartRateBaseline)
        let sleepComponent = sleepSession.map(sleepPerformance) ?? 60

        let weighted = hrvComponent * 0.5 + rhrComponent * 0.2 + sleepComponent * 0.3

        return RecoveryScore(
            date: date,
            percentage: weighted.clamped(to: 0...100),
            hrvMilliseconds: hrv,
            restingHeartRate: restingHeartRate,
            sleepPerformancePercentage: sleepComponent,
            previousHRVBaseline: hrvBaseline
        )
    }

    /// HRV above baseline is good; a ratio of 1.0 maps to ~65, higher ratios climb toward 100.
    private static func hrvScore(hrv: Double, baseline: Double) -> Double {
        guard baseline > 0 else { return 60 }
        let ratio = hrv / baseline
        let score = 50 + (ratio - 1.0) * 140
        return score.clamped(to: 0...100)
    }

    /// A resting heart rate below baseline is good.
    private static func restingHeartRateScore(rhr: Double, baseline: Double) -> Double {
        guard baseline > 0 else { return 60 }
        let delta = baseline - rhr
        let score = 65 + delta * 4
        return score.clamped(to: 0...100)
    }

    private static func sleepPerformance(_ session: SleepSession) -> Double {
        let durationRatio = session.neededSleepSeconds > 0
            ? session.timeAsleep / session.neededSleepSeconds
            : 1
        let durationScore = (durationRatio * 100).clamped(to: 0...100)
        return (durationScore * 0.7 + session.efficiencyPercentage * 0.3).clamped(to: 0...100)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
