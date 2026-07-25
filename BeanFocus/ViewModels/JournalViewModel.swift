import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class JournalViewModel {
    var entries: [JournalEntry] = []
    var selectedFactors: Set<JournalFactor> = []
    var moodRating: Int = 3
    var note: String = ""

    func load(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let stored = (try? modelContext.fetch(descriptor)) ?? []
        entries = stored.isEmpty ? MockData.journalHistory(days: 30) : stored

        if let today = stored.first(where: { $0.date.isSameDay(as: Date()) }) {
            selectedFactors = today.factors
            moodRating = today.moodRating
            note = today.note
        }
    }

    func saveTodayEntry(modelContext: ModelContext) {
        let today = Date()
        let descriptor = FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let stored = (try? modelContext.fetch(descriptor)) ?? []

        if let existing = stored.first(where: { $0.date.isSameDay(as: today) }) {
            existing.factors = selectedFactors
            existing.moodRating = moodRating
            existing.note = note
        } else {
            let entry = JournalEntry(date: today, factors: selectedFactors, moodRating: moodRating, note: note)
            modelContext.insert(entry)
        }

        try? modelContext.save()
        HapticManager.success()
        load(modelContext: modelContext)
    }

    func toggle(_ factor: JournalFactor) {
        if selectedFactors.contains(factor) {
            selectedFactors.remove(factor)
        } else {
            selectedFactors.insert(factor)
        }
        HapticManager.selection()
    }
}
