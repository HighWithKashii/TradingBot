import SwiftUI

/// Central color palette for the app's dark, Whoop-inspired theme.
extension Color {
    // Backgrounds
    static let appBackground = Color(hex: "0A0A0A")
    static let cardBackground = Color(hex: "16171B")
    static let cardBackgroundElevated = Color(hex: "1D1E23")
    static let separator = Color.white.opacity(0.08)

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.38)

    // Score zone accents
    static let recoveryGreen = Color(hex: "16EC06")
    static let recoveryYellow = Color(hex: "FFDE00")
    static let recoveryRed = Color(hex: "FF0026")

    // Feature accents
    static let strainBlue = Color(hex: "00C2FF")
    static let sleepPurple = Color(hex: "7C5CFC")
    static let stressOrange = Color(hex: "FF8A00")

    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

/// Maps a 0-100 score (or any zone-based metric) to Whoop-style traffic light colors.
enum ScoreZone {
    case low, medium, high

    var color: Color {
        switch self {
        case .high: return .recoveryGreen
        case .medium: return .recoveryYellow
        case .low: return .recoveryRed
        }
    }

    var label: String {
        switch self {
        case .high: return "Grün"
        case .medium: return "Gelb"
        case .low: return "Rot"
        }
    }

    init(recoveryPercentage value: Double) {
        switch value {
        case 67...: self = .high
        case 34..<67: self = .medium
        default: self = .low
        }
    }
}
