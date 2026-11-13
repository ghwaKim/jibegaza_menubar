import Foundation

enum WorkWeek {
    static func start(for date: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: today) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: today)!
    }
}
