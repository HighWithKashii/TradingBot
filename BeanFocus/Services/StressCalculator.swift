import Foundation

/// Converts instantaneous HRV readings into a 0...100 "stress" score, the
/// same inverted relationship Whoop's Stress Monitor uses: HRV meaningfully
/// below your rolling baseline reads as elevated stress, HRV at or above
/// baseline reads as calm.
enum StressCalculator {
    static func score(fromInstantHRV hrv: Double, baseline: Double) -> Double {
        guard baseline > 0 else { return 50 }
        let ratio = hrv / baseline
        // ratio 1.0 -> ~30 (balanced/calm boundary), ratio 0.5 -> ~100 (stressed)
        let score = 100 - (ratio * 70)
        return score.clamped(to: 0...100)
    }

    static func dailyTimeline(from samples: [StressSample]) -> [StressSample] {
        samples.sorted { $0.timestamp < $1.timestamp }
    }

    static func averageScore(from samples: [StressSample]) -> Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0) { $0 + $1.score } / Double(samples.count)
    }

    static func timeInState(_ level: StressLevel, samples: [StressSample], sampleInterval: TimeInterval) -> TimeInterval {
        Double(samples.filter { $0.level == level }.count) * sampleInterval
    }
}
