import Foundation

enum SleepStage: String, Codable, CaseIterable, Identifiable {
    case awake = "Wach"
    case rem = "REM"
    case light = "Leicht"
    case deep = "Tief"

    var id: String { rawValue }

    var sortOrder: Int {
        switch self {
        case .awake: return 0
        case .rem: return 1
        case .light: return 2
        case .deep: return 3
        }
    }
}

struct SleepStageInterval: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var stage: SleepStage
    var start: Date
    var end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct SleepSession: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date // the "sleep night" this session belongs to (wake-up day)
    var bedtime: Date
    var wakeTime: Date
    var stages: [SleepStageInterval]
    var neededSleepSeconds: TimeInterval

    var totalDuration: TimeInterval { wakeTime.timeIntervalSince(bedtime) }

    var timeAsleep: TimeInterval {
        stages.filter { $0.stage != .awake }.reduce(0) { $0 + $1.duration }
    }

    var efficiencyPercentage: Double {
        guard totalDuration > 0 else { return 0 }
        return min((timeAsleep / totalDuration) * 100, 100)
    }

    var sleepDebtSeconds: TimeInterval {
        max(neededSleepSeconds - timeAsleep, 0)
    }

    func duration(of stage: SleepStage) -> TimeInterval {
        stages.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
    }

    var stageBreakdown: [(stage: SleepStage, duration: TimeInterval)] {
        SleepStage.allCases
            .filter { $0 != .awake }
            .map { ($0, duration(of: $0)) }
    }
}
