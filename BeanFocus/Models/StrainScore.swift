import Foundation

/// Whoop-style strain on a 0...21 logarithmic-feel scale.
struct StrainScore: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var value: Double // 0...21
    var targetValue: Double // suggested daily target based on recovery
    var averageHeartRate: Double
    var maxHeartRate: Double
    var activeCalories: Double
    var heartRateZoneMinutes: [HeartRateZone: Double]

    var progressAgainstTarget: Double {
        guard targetValue > 0 else { return 0 }
        return min(value / targetValue, 1.5)
    }

    var level: StrainLevel {
        switch value {
        case ..<10: return .light
        case 10..<14: return .moderate
        case 14..<18: return .high
        default: return .allOut
        }
    }
}

enum StrainLevel: String, Codable {
    case light = "Leicht"
    case moderate = "Moderat"
    case high = "Hoch"
    case allOut = "All Out"
}

enum HeartRateZone: Int, Codable, CaseIterable, Identifiable {
    case zone1 = 1, zone2, zone3, zone4, zone5

    var id: Int { rawValue }

    var label: String { "Zone \(rawValue)" }

    /// Approximate lower bound as a percentage of max heart rate.
    var lowerBoundPercentage: Double {
        switch self {
        case .zone1: return 0.50
        case .zone2: return 0.60
        case .zone3: return 0.70
        case .zone4: return 0.80
        case .zone5: return 0.90
        }
    }
}
