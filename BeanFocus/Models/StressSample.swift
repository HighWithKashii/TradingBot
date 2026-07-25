import Foundation

enum StressLevel: String, Codable, CaseIterable {
    case calm = "Ruhig"
    case balanced = "Ausgeglichen"
    case stressed = "Gestresst"

    static func from(score: Double) -> StressLevel {
        switch score {
        case ..<33: return .calm
        case 33..<66: return .balanced
        default: return .stressed
        }
    }
}

/// A single point-in-time HRV-derived stress reading.
struct StressSample: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var timestamp: Date
    var score: Double // 0...100, higher = more stressed
    var hrvMilliseconds: Double

    var level: StressLevel { StressLevel.from(score: score) }
}
