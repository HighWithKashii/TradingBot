import Foundation
import Observation
import SwiftData

enum TrendRange: String, CaseIterable, Identifiable {
    case week = "Woche"
    case month = "Monat"
    case year = "Jahr"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .year: return 365
        }
    }
}

enum TrendMetric: String, CaseIterable, Identifiable {
    case recovery = "Recovery"
    case strain = "Strain"
    case hrv = "HRV"
    case restingHeartRate = "Ruhepuls"
    case sleep = "Schlaf"

    var id: String { rawValue }
}

@MainActor
@Observable
final class TrendsViewModel {
    var range: TrendRange = .week
    var metric: TrendMetric = .recovery
    var dailyMetrics: [DailyMetrics] = []
    var insights: [CorrelationInsight] = []
    var shortSleepInsight: String?
    var isLoading = false

    func load(modelContext: ModelContext) async {
        isLoading = true
        defer { isLoading = false }

        let descriptor = FetchDescriptor<DailyMetrics>(sortBy: [SortDescriptor(\.date, order: .forward)])
        let stored = (try? modelContext.fetch(descriptor)) ?? []

        if stored.count >= range.days {
            dailyMetrics = Array(stored.suffix(range.days))
        } else {
            dailyMetrics = MockData.dailyMetricsHistory(days: range.days)
        }

        let journalDescriptor = FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.date, order: .forward)])
        let journalEntries = (try? modelContext.fetch(journalDescriptor)) ?? MockData.journalHistory(days: range.days)

        insights = CorrelationEngine.insights(metrics: dailyMetrics, journalEntries: journalEntries)
        shortSleepInsight = CorrelationEngine.shortSleepInsight(metrics: dailyMetrics)
    }

    func value(for metric: TrendMetric, in day: DailyMetrics) -> Double {
        switch metric {
        case .recovery: return day.recoveryPercentage
        case .strain: return day.strainValue
        case .hrv: return day.hrvMilliseconds
        case .restingHeartRate: return day.restingHeartRate
        case .sleep: return day.sleepDurationSeconds / 3600
        }
    }

    var averageValue: Double {
        guard !dailyMetrics.isEmpty else { return 0 }
        let total = dailyMetrics.reduce(0.0) { $0 + value(for: metric, in: $1) }
        return total / Double(dailyMetrics.count)
    }
}
