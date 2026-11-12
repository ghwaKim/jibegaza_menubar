import Foundation

struct FlexWorkRecord: Identifiable, Equatable {
    let date: Date
    let minutes: Int
    var accountID: String? = nil
    var id: Date { date }
}

/// Import policy is independent of the browser, network transport, and saved preferences.
enum FlexImportPolicy {
    enum Result {
        case unchanged(String)
        case applied(data: [DayWorkData], week: Date, account: String?, startsNewWeek: Bool, message: String)
    }

    static func apply(
        _ records: [FlexWorkRecord], to weeklyData: [DayWorkData],
        savedWeek: Date?, savedAccount: String?, now: Date,
        automatic: Bool, calendar: Calendar
    ) -> Result {
        let week = WorkWeek.start(for: now, calendar: calendar)
        func hasInput(_ day: DayWorkData) -> Bool {
            !day.start.isEmpty || !day.end.isEmpty || !day.manualHours.isEmpty || !day.manualMinutes.isEmpty
                || day.leaveType != .none || day.isConfirmed || day.lockStart || day.lockEnd || day.lockManual
        }
        let accounts = Set(records.compactMap(\.accountID))
        guard accounts.count <= 1 else { return .unchanged("서로 다른 flex 계정의 기록입니다.") }
        let occupied = weeklyData.filter(hasInput)
        let hasExisting = !occupied.isEmpty
        let canStartNewWeek =
            automatic && (savedWeek.map { $0 < week } ?? false)
            && occupied.allSatisfy {
                $0.importedFromFlex && (!$0.isConfirmed || $0.isFlexAutoLocked) && !$0.lockStart && !$0.lockEnd
                    && !$0.lockManual
            } && accounts.first != nil && accounts.first == savedAccount
        guard !hasExisting || savedWeek == nil || savedWeek == week || canStartNewWeek else {
            return .unchanged("기존 기록의 주차를 확인해주세요. 주간 Reset 후 이번 주 기록을 가져올 수 있어요.")
        }
        if let saved = savedAccount,
            let incoming = accounts.first, hasExisting, saved != incoming
        {
            return .unchanged("다른 flex 계정의 기록이 있습니다. 주간 Reset 후 다시 가져와주세요.")
        }
        var data = canStartNewWeek ? defaultWeekData() : weeklyData
        var count = 0
        // Reject duplicate dates rather than picking an arbitrary record.
        let grouped = Dictionary(grouping: records, by: { calendar.startOfDay(for: $0.date) })
        for (_, values) in grouped {
            guard values.count == 1, let record = values.first,
                (0...24 * 60).contains(record.minutes),
                let index = FlexImportScope.index(
                    for: record.date, now: now, calendar: calendar, includeToday: automatic)
            else { continue }
            let day = data[index]
            guard !day.isConfirmed || day.isFlexAutoLocked else { continue }
            guard !day.lockStart, !day.lockEnd, !day.lockManual,
                day.leaveType == .none
            else { continue }
            let hours = String(record.minutes / 60)
            let minutes = String(record.minutes % 60)
            if day.importedFromFlex, day.mode == .manual,
                day.manualHours == hours, day.manualMinutes == minutes,
                day.start.isEmpty, day.end.isEmpty, day.isFlexAutoLocked
            {
                continue
            }
            data[index].mode = .manual
            data[index].start = ""
            data[index].end = ""
            data[index].manualHours = hours
            data[index].manualMinutes = minutes
            data[index].isConfirmed = true
            data[index].isFlexAutoLocked = true
            data[index].importedFromFlex = true
            count += 1
        }
        guard count > 0 else { return .unchanged("변경할 기록이 없어요. 잠금·고정·휴가가 있는 날짜는 건너뛰어요.") }
        let skipped = records.count - count
        let message =
            skipped == 0
            ? "이번 주 flex 기록 \(count)일을 반영했어요."
            : "이번 주 flex 기록 \(count)일을 반영했어요. 변경이 없거나 잠금·고정·휴가 등이 있는 \(skipped)일은 건너뛰었어요."
        return .applied(
            data: data, week: week, account: accounts.first,
            startsNewWeek: canStartNewWeek, message: message)
    }
}

enum FlexImportScope {
    static func index(for date: Date, now: Date, calendar: Calendar = .current, includeToday: Bool = false) -> Int? {
        let today = calendar.startOfDay(for: now)
        let offset = (calendar.component(.weekday, from: today) + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -offset, to: today),
            date < today || (includeToday && calendar.isDate(date, inSameDayAs: today)),
            let days = calendar.dateComponents([.day], from: monday, to: calendar.startOfDay(for: date)).day,
            (0..<5).contains(days)
        else { return nil }
        return days
    }
}
