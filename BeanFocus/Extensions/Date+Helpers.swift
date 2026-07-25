import Foundation

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    func addingDays(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    /// Short weekday label, e.g. "Mo", "Di" (localized).
    var shortWeekdaySymbol: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: self)
    }

    var dayMonthLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("d. MMM")
        return formatter.string(from: self)
    }

    var timeLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("HH:mm")
        return formatter.string(from: self)
    }

    static func lastNDays(_ n: Int, endingAt end: Date = Date()) -> [Date] {
        (0..<n).reversed().map { end.startOfDay.addingDays(-$0) }
    }
}

extension TimeInterval {
    /// Formats a duration in seconds as "7h 32min".
    var hoursMinutesLabel: String {
        let totalMinutes = Int(self / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h \(minutes)min"
    }
}
