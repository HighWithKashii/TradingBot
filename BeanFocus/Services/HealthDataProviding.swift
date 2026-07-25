import Foundation

/// Abstraction over the raw health data source (HealthKit or Mock).
///
/// The rest of the app (calculators, view models) never talks to HealthKit
/// directly - it only sees this protocol. That makes the whole app runnable
/// in the Simulator (or in SwiftUI previews) with `MockHealthDataProvider`,
/// which is important because most HealthKit metrics Whoop-style apps rely
/// on (continuous HRV, sleep stages, SpO2) cannot be produced by a Simulator
/// device on its own - there is no sensor. `HealthKitManager` implements the
/// exact same protocol for real devices.
protocol HealthDataProviding {
    /// Requests all HealthKit read/write permissions used by the app.
    /// Should be a no-op (immediately succeeding) for mock implementations.
    func requestAuthorization() async throws

    func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateSample]
    func fetchRestingHeartRate(for date: Date) async throws -> Double
    func fetchHRV(from start: Date, to end: Date) async throws -> [StressSample]
    func fetchLatestHRVBaseline(before date: Date, days: Int) async throws -> Double
    func fetchRespiratoryRate(for date: Date) async throws -> Double
    func fetchOxygenSaturation(for date: Date) async throws -> Double
    func fetchActiveCalories(for date: Date) async throws -> Double
    func fetchSleepSession(for date: Date) async throws -> SleepSession?
    func fetchWorkouts(for date: Date) async throws -> [WorkoutSession]

    /// Streams live heart rate updates while a workout / the day progresses.
    /// Mock implementations can synthesize a believable stream.
    func startLiveHeartRateUpdates(handler: @escaping (HeartRateSample) -> Void)
    func stopLiveHeartRateUpdates()
}

enum HealthDataError: LocalizedError {
    case healthKitUnavailable
    case authorizationDenied
    case noDataAvailable

    var errorDescription: String? {
        switch self {
        case .healthKitUnavailable:
            return "HealthKit ist auf diesem Gerät nicht verfügbar."
        case .authorizationDenied:
            return "Der Zugriff auf Health-Daten wurde nicht erteilt."
        case .noDataAvailable:
            return "Für diesen Zeitraum liegen keine Daten vor."
        }
    }
}
