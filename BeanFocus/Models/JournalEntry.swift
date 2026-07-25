import Foundation
import SwiftData

enum JournalFactor: String, Codable, CaseIterable, Identifiable {
    case alcohol = "Alkohol"
    case caffeineLate = "Koffein (spät)"
    case sick = "Krank"
    case travel = "Reise/Jetlag"
    case highStressDay = "Stressiger Tag"
    case screenBeforeBed = "Bildschirm vor dem Schlafen"
    case lateMeal = "Spätes Essen"
    case meditation = "Meditation"
    case goodMood = "Gute Stimmung"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .alcohol: return "wineglass"
        case .caffeineLate: return "cup.and.saucer"
        case .sick: return "cross.case"
        case .travel: return "airplane"
        case .highStressDay: return "bolt.heart"
        case .screenBeforeBed: return "iphone"
        case .lateMeal: return "fork.knife"
        case .meditation: return "leaf"
        case .goodMood: return "face.smiling"
        }
    }

    /// Whether this factor is generally expected to hurt recovery when present.
    var isNegative: Bool {
        switch self {
        case .meditation, .goodMood: return false
        default: return true
        }
    }
}

@Model
final class JournalEntry {
    var id: UUID
    var date: Date
    var factorRawValues: [String]
    var moodRating: Int // 1...5
    var note: String

    init(date: Date, factors: Set<JournalFactor> = [], moodRating: Int = 3, note: String = "") {
        self.id = UUID()
        self.date = date.startOfDay
        self.factorRawValues = factors.map(\.rawValue)
        self.moodRating = moodRating
        self.note = note
    }

    var factors: Set<JournalFactor> {
        get { Set(factorRawValues.compactMap(JournalFactor.init(rawValue:))) }
        set { factorRawValues = newValue.map(\.rawValue) }
    }
}
