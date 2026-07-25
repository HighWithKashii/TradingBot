import Foundation

/// Deterministic, believable fake health data so every screen looks fully
/// populated in SwiftUI previews, the Simulator, or on a fresh install
/// before HealthKit permissions are granted.
final class MockHealthDataProvider: HealthDataProviding {
    private var liveTimer: Timer?
    private var seedGenerator = SeededGenerator(seed: 42)

    func requestAuthorization() async throws {
        // No-op: mock data needs no permissions.
    }

    func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateSample] {
        var samples: [HeartRateSample] = []
        var cursor = start
        while cursor < end {
            let hour = Calendar.current.component(.hour, from: cursor)
            let base: Double = (9...19).contains(hour) ? 78 : 58
            samples.append(HeartRateSample(timestamp: cursor, beatsPerMinute: base + Double.random(in: -6...10, using: &seedGenerator)))
            cursor = cursor.addingTimeInterval(15 * 60)
        }
        return samples
    }

    func fetchRestingHeartRate(for date: Date) async throws -> Double {
        52 + Double.random(in: -4...6, using: &seedGenerator)
    }

    func fetchHRV(from start: Date, to end: Date) async throws -> [StressSample] {
        var samples: [StressSample] = []
        var cursor = start
        let baseline = 62.0
        while cursor < end {
            let hrv = max(20, baseline + Double.random(in: -18...18, using: &seedGenerator))
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

    func fetchLatestHRVBaseline(before date: Date, days: Int) async throws -> Double {
        58 + Double.random(in: -3...5, using: &seedGenerator)
    }

    func fetchRespiratoryRate(for date: Date) async throws -> Double {
        14.5 + Double.random(in: -1.2...1.2, using: &seedGenerator)
    }

    func fetchOxygenSaturation(for date: Date) async throws -> Double {
        97 + Double.random(in: -1...1.5, using: &seedGenerator)
    }

    func fetchActiveCalories(for date: Date) async throws -> Double {
        420 + Double.random(in: -80...260, using: &seedGenerator)
    }

    func fetchSleepSession(for date: Date) async throws -> SleepSession? {
        MockData.sleepSession(for: date)
    }

    func fetchWorkouts(for date: Date) async throws -> [WorkoutSession] {
        MockData.workouts(for: date)
    }

    func startLiveHeartRateUpdates(handler: @escaping (HeartRateSample) -> Void) {
        liveTimer?.invalidate()
        liveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let bpm = 90 + Double.random(in: -15...35, using: &self.seedGenerator)
            handler(HeartRateSample(timestamp: Date(), beatsPerMinute: bpm))
        }
    }

    func stopLiveHeartRateUpdates() {
        liveTimer?.invalidate()
        liveTimer = nil
    }
}

/// A tiny deterministic PRNG so mock data looks the same across app launches
/// and previews instead of flickering with every re-render.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
