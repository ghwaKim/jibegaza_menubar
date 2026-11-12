import Foundation
import Testing
@testable import TimeCalculatorMenuBar

@MainActor
struct WorkWeekTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        return c
    }
    private func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    @Test func weekDatesCrossYearAndIgnoreCalendarFirstWeekday() {
        #expect(WorkWeek.start(for: date(11, 15), calendar: calendar) == calendar.startOfDay(for: date(11, 9)))
        let suite = "WeekTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = TimeCalculatorViewModel(defaults: defaults, now: date(12, 31), calendar: calendar)
        #expect(vm.weeklyDayTitle(at: 0) == "월 12/28")
        #expect(vm.weeklyDayTitle(at: 4) == "금 1/1")
        #expect(vm.isCurrentWorkWeek)
        #expect(vm.weeklyDateRange.contains("2027년"))
    }

    @Test func oldWeekDoesNotSuggestTodayGoalAndCanBeArchived() {
        let suite = "WeekTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = TimeCalculatorViewModel(defaults: defaults, now: date(11, 13), calendar: calendar)
        for i in 0..<4 { vm.updateWeeklyManualHours(idx: i, value: "9") }
        #expect(vm.targetWorkMinutes == 240)
        vm.toggleWeeklyConfirmation(idx: 0)
        vm.syncFlexClockIn(date(11, 20), now: date(11, 20))
        #expect(!vm.isCurrentWorkWeek)
        #expect(vm.targetWorkMinutes == 480)
        let next = TimeCalculatorViewModel(defaults: defaults, now: date(11, 20), calendar: calendar)
        #expect(!next.isCurrentWorkWeek)
        #expect(next.weekChangeNotice != nil)
        #expect(next.targetWorkMinutes == 480)
        #expect(!next.canRestoreAutoSuggestedTarget)
        #expect(next.weeklyDayTitle(at: 0) == "월 11/9")
        next.archiveAndStartCurrentWeek()
        #expect(next.isCurrentWorkWeek)
        #expect(next.weekChangeNotice == nil)
        #expect(next.weekTotalText == "0분")
        #expect(next.weeklyDayTitle(at: 0) == "월 11/16")
        #expect(next.previousWeek?.data[0].isConfirmed == true)
        #expect(next.previousWeek?.data[0].manualHours == "9")
        let reopened = TimeCalculatorViewModel(defaults: defaults, now: date(11, 20), calendar: calendar)
        #expect(reopened.isCurrentWorkWeek)
        #expect(reopened.previousWeek?.data[0].manualHours == "9")
        reopened.archiveAndStartCurrentWeek()
        #expect(reopened.previousWeek?.data[0].manualHours == "9")
    }

    @Test func legacyRecordsWithUnknownWeekArePreservedButNotSuggested() throws {
        let suite = "WeekTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var days = defaultWeekData()
        for i in 0..<4 { days[i].manualHours = "9" }
        defaults.set(try JSONEncoder().encode(days), forKey: "weeklyData")
        let vm = TimeCalculatorViewModel(defaults: defaults, now: date(11, 13), calendar: calendar)
        #expect(vm.recordedWeekStart == nil)
        #expect(vm.weeklyDateRange == "주차 미확인")
        #expect(vm.targetWorkMinutes == 480)
        vm.archiveAndStartCurrentWeek()
        #expect(vm.previousWeek?.data[0].manualHours == "9")
        #expect(vm.previousWeek?.weekStart == nil)
        #expect(vm.isCurrentWorkWeek)
    }

    @Test func automaticFlexRolloverArchivesPriorWeek() {
        let suite = "WeekTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = TimeCalculatorViewModel(defaults: defaults, now: date(11, 9), calendar: calendar)
        _ = vm.importFlexRecords([FlexWorkRecord(date: date(11, 9), minutes: 480, accountID: "me")], now: date(11, 10), automatic: true)
        _ = vm.importFlexRecords([FlexWorkRecord(date: date(11, 16), minutes: 450, accountID: "me")], now: date(11, 17), automatic: true)
        #expect(vm.previousWeek?.data[0].manualHours == "8")
        #expect(vm.previousWeek?.data[0].importedFromFlex == true)
        #expect(vm.previousWeek?.flexAccountID == "me")
        #expect(vm.weeklyData[0].manualMinutes == "30")
    }
}
