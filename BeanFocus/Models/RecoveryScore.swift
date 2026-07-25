import Foundation

/// A single day's recovery result, computed by `RecoveryCalculator`.
struct RecoveryScore: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var percentage: Double // 0...100
    var hrvMilliseconds: Double
    var restingHeartRate: Double
    var sleepPerformancePercentage: Double
    var previousHRVBaseline: Double

    var zone: ScoreZone {
        ScoreZone(recoveryPercentage: percentage)
    }

    var summary: String {
        switch zone {
        case .high:
            return "Dein Körper ist gut erholt und bereit für Belastung."
        case .medium:
            return "Deine Erholung ist moderat. Höre auf deinen Körper."
        case .low:
            return "Dein Körper braucht Erholung. Nimm es heute ruhiger an."
        }
    }

    var hrvDeltaPercentage: Double {
        guard previousHRVBaseline > 0 else { return 0 }
        return ((hrvMilliseconds - previousHRVBaseline) / previousHRVBaseline) * 100
    }
}
