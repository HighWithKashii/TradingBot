import Foundation

struct HeartRateSample: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var timestamp: Date
    var beatsPerMinute: Double
}

struct WorkoutSession: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var activityName: String
    var start: Date
    var end: Date
    var averageHeartRate: Double
    var maxHeartRate: Double
    var activeCalories: Double
    var strainContribution: Double

    var duration: TimeInterval { end.timeIntervalSince(start) }
}
