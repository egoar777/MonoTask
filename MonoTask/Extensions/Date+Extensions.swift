import Foundation

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var endOfDay: Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay) ?? self
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(self)
    }

    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    /// Weekday number: 1 = Sunday, 2 = Monday, ..., 7 = Saturday
    var weekdayIndex: Int {
        Calendar.current.component(.weekday, from: self)
    }

    /// Monday of this date's week, regardless of the locale's first weekday.
    /// (Resolving week-of-year components with `weekday = 2` jumps to the *next*
    /// Monday on Sundays in locales whose week starts on Sunday.)
    var startOfWeek: Date {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: self)  // 1 = Sunday ... 7 = Saturday
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: startOfDay) ?? startOfDay
    }

    func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: self) ?? self
    }

    func daysFromNow(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    var formattedShortDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }

    var formattedMediumDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }

    var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    var formattedWeekdayAndDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: self).capitalized
    }

    /// "ПН · 19 ОКТЯБРЯ" — eyebrow date for screen headers
    var formattedEyebrowDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEEEE · d MMMM"
        return formatter.string(from: self).uppercased()
    }

    var formattedRelative: String {
        if isToday {
            return "Сегодня"
        } else if isTomorrow {
            return "Завтра"
        } else if isYesterday {
            return "Вчера"
        } else {
            return formattedMediumDate
        }
    }
}
