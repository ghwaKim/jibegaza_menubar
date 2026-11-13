import Foundation
import Testing
@testable import TimeCalculatorMenuBar

@MainActor
struct EightHourFitTests {
    private func model(leave: LeaveType = .none) -> TimeCalculatorViewModel {
        WeeklyTests().model(leave: leave, otherHours: 7)
    }

    @Test func normalWeeklyArrivalIsClampedWithoutMovingManualDeparture() {
        let vm = model()
        vm.updateWeeklyEnd(idx: 4, value: "18:00")
        for (input, expected) in [("07:45", "08:00"), ("11:00", "10:30"), ("09:15", "09:15")] {
            vm.updateWeeklyStart(idx: 4, value: input)
            #expect(vm.weeklyData[4].start == expected)
            #expect(vm.weeklyData[4].end == "18:00")
        }
        vm.resetWeeklyDay(idx: 0)
        vm.updateWeeklyStart(idx: 4, value: "")
        #expect(vm.weeklyData[4].start.isEmpty)
    }

    @Test func leaveDayDirectArrivalClampsToAllowedRange() {
        for leave in [LeaveType.half, .halfHalf] {
            let vm = model(leave: leave)
            vm.updateWeeklyStart(idx: 4, value: "11:00")
            vm.toggleWeeklyLock(idx: 4, field: .start)
            #expect(vm.weeklyData[4].start == "10:30")
            vm.fitWeeklyDayToEightHours(idx: 4)
            #expect(vm.weeklyFitMessages[4] == nil)
            #expect(getDailyMinutes(vm.weeklyData[4]) == 480)
            vm.toggleWeeklyLock(idx: 4, field: .start)
            vm.updateWeeklyStart(idx: 4, value: "07:45")
            #expect(vm.weeklyData[4].start == "08:00")
        }
    }

    @Test func everyAllowedNormalArrivalFitsEightHoursAndCoreTime() {
        for start in earliestStartMinutes...630 {
            var day = defaultWeekData()[0]
            day.mode = .range
            day.start = minutesToTime(start)
            day.lockStart = true
            guard case .fitted(let fitted) = WeeklyWorkCalculator.fitToEightHours(day) else {
                Issue.record("Allowed arrival failed: \(day.start)")
                continue
            }
            #expect(fitted.start == day.start)
            #expect(timeToMinutes(fitted.end) >= 17 * 60)
            #expect(getDailyMinutes(fitted) == 480)
        }
    }

    @Test func legacyOutOfRangeArrivalsAndLateReversePlansRemainRejected() {
        for start in ["07:45", "11:00", "20:00"] {
            var day = defaultWeekData()[0]
            day.mode = .range
            day.start = start
            day.lockStart = true
            guard case .unavailable = WeeklyWorkCalculator.fitToEightHours(day) else {
                Issue.record("Invalid legacy arrival accepted: \(start)")
                continue
            }
        }
        let vm = model()
        vm.updateWeeklyEnd(idx: 4, value: "20:00")
        vm.toggleWeeklyLock(idx: 4, field: .end)
        vm.fitWeeklyDayToEightHours(idx: 4)
        #expect(vm.weeklyFitMessages[4]?.contains("10:30") == true)
    }

    @Test func unpinnedTimesCannotBeFittedAndUnpinningDisablesButton() {
        let vm = model()
        vm.updateWeeklyStart(idx: 4, value: "10:30")
        vm.updateWeeklyEnd(idx: 4, value: "21:30")
        #expect(!vm.canFitWeeklyDayToEightHours(idx: 4))
        vm.fitWeeklyDayToEightHours(idx: 4)
        #expect(vm.weeklyData[4].start == "10:30")
        #expect(vm.weeklyData[4].end == "21:30")
        vm.toggleWeeklyLock(idx: 4, field: .start)
        #expect(vm.canFitWeeklyDayToEightHours(idx: 4))
        vm.fitWeeklyDayToEightHours(idx: 4)
        #expect(vm.weeklyData[4].end == "19:30")
        vm.toggleWeeklyLock(idx: 4, field: .start)
        #expect(!vm.canFitWeeklyDayToEightHours(idx: 4))
    }

    @Test func halfDayEndAt1530FitsStartAt1030() {
        let vm = model(leave: .half)
        vm.updateWeeklyEnd(idx: 4, value: "15:30")
        vm.toggleWeeklyLock(idx: 4, field: .end)
        vm.fitWeeklyDayToEightHours(idx: 4)
        #expect(vm.weeklyData[4].start == "10:30")
        #expect(vm.weeklyData[4].end == "15:30")
        #expect(getDailyMinutes(vm.weeklyData[4]) == 480)
        #expect(!vm.isWeeklyAutoCalculated(at: 4))
        vm.updateWeeklyEnd(idx: 0, value: "18:00")
        #expect(vm.weeklyData[4].start == "10:30")
        #expect(vm.weeklyData[4].end == "15:30")
    }

    @Test func leaveExemptsEarlyDepartureButNotLatestArrival() {
        let half = model(leave: .half)
        half.updateWeeklyEnd(idx: 4, value: "14:00")
        half.toggleWeeklyLock(idx: 4, field: .end)
        half.fitWeeklyDayToEightHours(idx: 4)
        #expect(half.weeklyData[4].start == "09:00")
        #expect(half.weeklyData[4].end == "14:00")
        for leave in [LeaveType.half, .halfHalf] {
            let vm = model(leave: leave)
            vm.updateWeeklyEnd(idx: 4, value: "20:00")
            vm.toggleWeeklyLock(idx: 4, field: .end)
            #expect(timeToMinutes(vm.weeklyData[4].start) <= 630)
            let originalStart = vm.weeklyData[4].start
            vm.fitWeeklyDayToEightHours(idx: 4)
            #expect(vm.weeklyData[4].start == originalStart)
            #expect(vm.weeklyData[4].end == "20:00")
            #expect(vm.weeklyFitMessages[4]?.contains("10:30") == true)
        }
    }

    @Test func todayReverseArrivalLimitDoesNotDependOnCoreTime() {
        let calendar = Calendar.current
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 13))!
        func clock(_ h: Int, _ m: Int = 0) -> Date {
            calendar.date(bySettingHour: h, minute: m, second: 0, of: day)!
        }
        let calculator = TodayWorkCalculator(calendar: calendar)
        let early = calculator.alignedTimes(start: clock(8), end: clock(14), targetWorkMinutes: 240,
            lastEditedField: .endTime, appliesCoreTime: false)
        #expect(early.start == clock(9))
        #expect(early.end == clock(14))
        for target in [240, 360] {
            let late = calculator.alignedTimes(start: clock(8), end: clock(20), targetWorkMinutes: target,
                lastEditedField: .endTime, appliesCoreTime: false)
            #expect(late.start == clock(10, 30))
            #expect(late.end == clock(20))
        }
    }

    @Test func quarterDayAndNormalWorkIncludeLunch() {
        let quarter = model(leave: .halfHalf)
        quarter.updateWeeklyEnd(idx: 4, value: "15:30")
        quarter.toggleWeeklyLock(idx: 4, field: .end)
        quarter.fitWeeklyDayToEightHours(idx: 4)
        #expect(quarter.weeklyData[4].start == "08:30")
        let normal = model()
        normal.updateWeeklyStart(idx: 4, value: "09:00")
        normal.toggleWeeklyLock(idx: 4, field: .start)
        normal.fitWeeklyDayToEightHours(idx: 4)
        #expect(normal.weeklyData[4].end == "18:00")
    }

    @Test func pinnedSourceIsPreservedAndBothPinsDisableFitting() {
        let vm = model()
        vm.updateWeeklyStart(idx: 4, value: "10:00")
        vm.updateWeeklyEnd(idx: 4, value: "18:00")
        vm.toggleWeeklyLock(idx: 4, field: .start)
        vm.fitWeeklyDayToEightHours(idx: 4)
        #expect(vm.weeklyData[4].start == "10:00")
        #expect(vm.weeklyData[4].end == "19:00")
        vm.toggleWeeklyLock(idx: 4, field: .end)
        #expect(!vm.canFitWeeklyDayToEightHours(idx: 4))
        vm.fitWeeklyDayToEightHours(idx: 4)
        #expect(vm.weeklyData[4].end == "19:00")
    }

    @Test func impossibleEightHourPlanPreservesEnteredTimes() {
        let vm = model()
        vm.updateWeeklyEnd(idx: 4, value: "16:00")
        vm.toggleWeeklyLock(idx: 4, field: .end)
        let originalStart = vm.weeklyData[4].start
        vm.fitWeeklyDayToEightHours(idx: 4)
        #expect(vm.weeklyData[4].end == "16:00")
        #expect(vm.weeklyData[4].start == originalStart)
        #expect(vm.weeklyFitMessages[4]?.contains("08:00") == true)
    }

    @Test func changingPinsClearsOutdatedFitWarning() {
        let vm = model()
        vm.updateWeeklyEnd(idx: 4, value: "21:30")
        vm.toggleWeeklyLock(idx: 4, field: .end)
        vm.fitWeeklyDayToEightHours(idx: 4)
        #expect(vm.weeklyFitMessages[4]?.contains("10:30") == true)
        vm.toggleWeeklyLock(idx: 4, field: .end)
        #expect(vm.weeklyFitMessages[4] == nil)
        vm.toggleWeeklyLock(idx: 4, field: .start)
        #expect(vm.canFitWeeklyDayToEightHours(idx: 4))
        #expect(vm.weeklyFitMessages[4] == nil)
        vm.fitWeeklyDayToEightHours(idx: 4)
        #expect(getDailyMinutes(vm.weeklyData[4]) == 480)
    }

    @Test func confirmedAnnualAndEmptyDaysCannotBeFitted() {
        let vm = model()
        #expect(!vm.canFitWeeklyDayToEightHours(idx: 4))
        vm.updateWeeklyStart(idx: 4, value: "09:00")
        vm.toggleWeeklyConfirmation(idx: 4)
        #expect(!vm.canFitWeeklyDayToEightHours(idx: 4))
        let annual = model(leave: .annual)
        #expect(!annual.canFitWeeklyDayToEightHours(idx: 4))
    }

    @Test func pinnedEndpointSurvivesSavingAndReopening() throws {
        let suite = "EightHourFitTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        let vm = TimeCalculatorViewModel(defaults: defaults, now: now)
        vm.toggleWeeklyMode(idx: 0)
        vm.updateWeeklyStart(idx: 0, value: "09:00")
        vm.updateWeeklyEnd(idx: 0, value: "19:00")
        vm.toggleWeeklyLock(idx: 0, field: .end)
        let reopened = TimeCalculatorViewModel(defaults: defaults, now: now)
        reopened.fitWeeklyDayToEightHours(idx: 0)
        #expect(reopened.weeklyData[0].start == "10:00")
        #expect(reopened.weeklyData[0].end == "19:00")
    }
}
