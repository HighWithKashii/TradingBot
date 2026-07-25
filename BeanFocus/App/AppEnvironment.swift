import Foundation
import HealthKit

/// Single place that decides whether the app talks to real HealthKit data
/// or to the deterministic mock provider.
///
/// Rationale: the iOS Simulator has no heart-rate/HRV/sleep sensors, so a
/// build running there can never produce continuous HealthKit data on its
/// own. Rather than showing an empty app in the Simulator, we default to
/// mock data whenever HealthKit is unavailable (Simulator) and always
/// prefer real HealthKit data on a physical device. Users can also force
/// mock data from Settings while developing/demoing.
@MainActor
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    @Published var useMockData: Bool {
        didSet { rebuildProvider() }
    }

    private(set) var healthDataProvider: HealthDataProviding

    private init() {
        #if targetEnvironment(simulator)
        self.useMockData = true
        #else
        self.useMockData = !HKHealthStore.isHealthDataAvailable()
        #endif
        self.healthDataProvider = Self.makeProvider(useMock: useMockData)
    }

    private func rebuildProvider() {
        healthDataProvider = Self.makeProvider(useMock: useMockData)
    }

    private static func makeProvider(useMock: Bool) -> HealthDataProviding {
        useMock ? MockHealthDataProvider() : HealthKitManager()
    }
}
