import SwiftUI

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    var dayBounds: (start: Date, end: Date) {
        let start = startOfDay
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    /// Timestamp to use when logging food for `day`: "now" for today, midday for other days.
    static func logTimestamp(for day: Date) -> Date {
        if Calendar.current.isDateInToday(day) { return .now }
        return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Double {
    /// "1,234" — rounded, locale-aware.
    var wholeNumber: String { formatted(.number.precision(.fractionLength(0))) }
}

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
