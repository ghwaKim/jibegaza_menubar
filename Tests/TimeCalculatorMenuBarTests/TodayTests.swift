import Foundation
import Testing
@testable import TimeCalculatorMenuBar

@MainActor
struct TodayTests {
    func date(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: hour, minute: minute))!
    }

    func model(now: Date) -> TimeCalculatorViewModel {
        TimeCalculatorViewModel(defaults: UserDefaults(suiteName: "TodayTests.\(UUID().uuidString)")!, now: now)
    }

    @Test func coreTimeAndOvertimeAreSeparate() {
        let vm = model(now: date(15, 10))
        vm.updateTodayTargetSelection(.sixHours)
        vm.updateStartTime(date(8))
        #expect(vm.endTime == date(15, 30))
        #expect(vm.targetWorkMinutes == 360)
        #expect(vm.formattedRemainingToday == "10분")
        #expect(vm.remainingWorkLabel == "초과 근무시간")
        #expect(vm.formattedRemainingDeparture == "20분")
        vm.menuBarMetricBinding.wrappedValue = .untilDeparture
        #expect(vm.menuBarTitle == "0h 20m")
    }


    @Test func legacyRemainingSettingMigratesToDeparture() throws {
        let saved = Data(#"{"metric":"remaining"}"#.utf8)
        let mode = try JSONDecoder().decode(MenuBarDisplayMode.self, from: saved)
        #expect(mode.metric == .untilDeparture)
        let vm = model(now: date(15, 50))
        vm.updateTodayTargetSelection(.sixHours)
        vm.updateStartTime(date(8))
        vm.menuBarMetricBinding.wrappedValue = mode.metric
        #expect(vm.menuBarTitle == "+0h 20m")
        #expect(vm.formattedRemainingToday == "50분")
    }

    @Test func earlyArrivalClampsToEight() {
        let vm = model(now: date(12))
        vm.updateStartTime(date(7, 45))
        #expect(vm.startTime == date(8))
        #expect(vm.endTime == date(17))
        vm.updateTodayTargetSelection(.manual)
        vm.updateStartTime(date(7, 45))
        #expect(vm.startTime == date(8))
        #expect(vm.targetWorkMinutes == 480)
        vm.updateWeeklyStart(idx: 0, value: "07:45")
        #expect(vm.weeklyData[0].start == "08:00")
        vm.updateWeeklyStart(idx: 0, value: "")
        #expect(vm.weeklyData[0].start.isEmpty)
    }

    @Test func reverseCalculationPreservesTargetAtEarliestStart() {
        let vm = model(now: date(12))
        vm.updateEndTime(date(15, 30))
        #expect(vm.startTime == date(8))
        #expect(vm.endTime == date(17))
        #expect(vm.targetWorkMinutes == 480)
    }

    @Test func lateArrivalIsPreserved() {
        let vm = model(now: date(12))
        vm.updateStartTime(date(11))
        #expect(vm.startTime == date(11))
        #expect(vm.endTime == date(20))
    }

    @Test func manualGoalCannotExceedNineHours() {
        let vm = model(now: date(12))
        vm.updateStartTime(date(9))
        vm.updateTodayTargetSelection(.manual)
        vm.updateTodayManualTargetMinutes("30")
        #expect(vm.targetWorkMinutes == 510)
        vm.updateTodayManualTargetHours("9")
        #expect(vm.targetWorkMinutes == 540)
        #expect(vm.targetInputMinutes == "00")
        vm.updateTodayManualTargetMinutes("59")
        #expect(vm.targetWorkMinutes == 540)
        #expect(vm.targetInputMinutes == "00")
        vm.updateTodayManualTargetHours("99")
        #expect(vm.targetInputHours == "9")
        #expect(vm.endTime == date(19))
    }

    @Test func timeEditsCapManualGoalWithoutTruncatingActualWork() {
        let vm = model(now: date(22))
        vm.updateStartTime(date(9))
        vm.updateTodayTargetSelection(.manual)
        vm.updateEndTime(date(22))
        #expect(vm.startTime == date(9))
        #expect(vm.endTime == date(22))
        #expect(vm.targetWorkMinutes == 540)
        #expect(vm.targetInputHours == "9")
        #expect(vm.targetInputMinutes == "00")
        #expect(vm.formattedWorkedToday.contains("12시간"))
    }

    @Test func savedOversizedManualGoalIsCappedOnLoad() {
        let suite = "TodayTests.legacyGoal.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(600, forKey: "manualOverrideTargetMinutes")
        defaults.set(true, forKey: "isManualTargetSelectionActive")
        let vm = TimeCalculatorViewModel(defaults: defaults, now: date(12))
        #expect(vm.targetWorkMinutes == 540)
        #expect(vm.targetInputHours == "9")
        #expect(vm.targetInputMinutes == "00")
    }

    @Test func manualTimeEditsKeepOppositeEndpoint() {
        let vm = model(now: date(12))
        vm.updateStartTime(date(9))
        vm.updateTodayTargetSelection(.manual)
        vm.updateEndTime(date(17))
        #expect(vm.startTime == date(9))
        #expect(vm.targetWorkMinutes == 420)
        #expect(vm.targetInputHours == "7")
        vm.updateStartTime(date(10))
        #expect(vm.endTime == date(17))
        #expect(vm.targetWorkMinutes == 360)
        vm.updateTodayManualTargetHours("8")
        #expect(vm.startTime == date(10))
        #expect(vm.endTime == date(19))
    }

    @Test func leaveExemptsCoreTimeAndLunchOnlyOverlaps() {
        for leave in [LeaveType.half, .halfHalf] {
            let defaults = UserDefaults(suiteName: "TodayTests.\(UUID().uuidString)")!
            var days = defaultWeekData()
            days[0].leaveType = leave
            defaults.set(try! JSONEncoder().encode(days), forKey: "weeklyData")
            let vm = TimeCalculatorViewModel(defaults: defaults, now: date(12))
            vm.updateStartTime(date(8))
            vm.updateTodayTargetSelection(.manual)
            vm.updateTodayManualTargetHours("2")
            vm.updateTodayManualTargetMinutes("0")
            #expect(vm.endTime == date(10))
            vm.updateStartTime(date(14))
            vm.updateTodayManualTargetHours("2")
            #expect(vm.endTime == date(16))
        }
    }

    @Test func workRemainingDiffersFromDepartureBeforeLunch() {
        let vm = model(now: date(12))
        vm.updateStartTime(date(9))
        #expect(vm.formattedRemainingToday == "5시간")
        #expect(vm.formattedRemainingDeparture == "6시간")
        vm.updateEndTime(date(20))
        #expect(vm.startTime == date(10, 30))
    }

    @Test func flexClockInPreservesGoalAndTracksManualEdits() {
        let vm = model(now: date(12))
        vm.updateTodayTargetSelection(.eightHours)
        vm.syncFlexClockIn(date(9, 20), now: date(12))
        #expect(vm.startTime == date(9, 20))
        #expect(vm.endTime == date(18, 20))
        #expect(vm.targetWorkMinutes == 480)
        #expect(vm.isStartTimeFromFlex)
        vm.updateTodayTargetSelection(.sevenHours)
        #expect(vm.startTime == date(9, 20))
        #expect(vm.endTime == date(17, 20))
        vm.updateStartTime(date(10))
        #expect(!vm.isStartTimeFromFlex)
        vm.syncFlexClockIn(date(9, 20), now: date(12))
        #expect(vm.startTime == date(9, 20))
        #expect(vm.targetWorkMinutes == 420)
        #expect(vm.isStartTimeFromFlex)
        vm.updateTodayTargetSelection(.manual)
        vm.updateTodayManualTargetHours("6")
        vm.updateTodayManualTargetMinutes("30")
        #expect(vm.startTime == date(9, 20))
        #expect(vm.endTime == date(16, 50))
        #expect(vm.targetWorkMinutes == 390)
    }

    @Test func flexClockInPersistsAndRejectsOtherDates() {
        let defaults = UserDefaults(suiteName: "TodayTests.flex.\(UUID())")!
        let vm = TimeCalculatorViewModel(defaults: defaults, now: date(12))
        vm.syncFlexClockIn(date(9, 20), now: date(12))
        let reloaded = TimeCalculatorViewModel(defaults: defaults, now: date(12))
        #expect(reloaded.isStartTimeFromFlex)
        #expect(reloaded.startTime == date(9, 20))
        reloaded.syncFlexClockIn(date(13), now: date(12))
        #expect(reloaded.startTime == date(9, 20))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date(12))!
        let nextDay = TimeCalculatorViewModel(defaults: defaults, now: tomorrow)
        #expect(!nextDay.isStartTimeFromFlex)
        #expect(nextDay.isStartTimeUnset)
        nextDay.syncFlexClockIn(date(9, 20), now: tomorrow)
        #expect(nextDay.isStartTimeUnset)
        vm.resetTodayState()
        #expect(!vm.isStartTimeFromFlex)
    }


    @Test func flexClockInActivatesMenuBarAfterResetWithoutReselectingSetting() {
        let vm = model(now: date(12))
        vm.resetTodayState()
        #expect(vm.menuBarDisplayMode == nil)
        #expect(vm.menuBarMetricBinding.wrappedValue == .untilDeparture)
        vm.syncFlexClockIn(date(9, 20), now: date(12))
        #expect(vm.menuBarDisplayMode?.metric == .untilDeparture)
        #expect(vm.menuBarTitle == "6h 20m")
    }

    @Test func flexClockInRetainsMenuBarChoiceAcrossDaysAndRestarts() {
        for metric in MenuBarMetric.allCases {
            let defaults = UserDefaults(suiteName: "TodayTests.menuBar.\(UUID())")!
            let vm = TimeCalculatorViewModel(defaults: defaults, now: date(12))
            vm.menuBarMetricBinding.wrappedValue = metric
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date(12))!
            let nextStart = Calendar.current.date(byAdding: .day, value: 1, to: date(9, 20))!
            vm.syncFlexClockIn(nextStart, now: tomorrow)
            #expect(vm.menuBarDisplayMode?.metric == metric)
            let reloaded = TimeCalculatorViewModel(defaults: defaults, now: tomorrow)
            #expect(reloaded.menuBarDisplayMode?.metric == metric)
            if metric == .untilDeparture {
                #expect(reloaded.menuBarTitle == "6h 20m")
            }
            let followingDay = Calendar.current.date(byAdding: .day, value: 1, to: tomorrow)!
            let reopened = TimeCalculatorViewModel(defaults: defaults, now: followingDay)
            #expect(reopened.menuBarDisplayMode?.metric == metric)
        }
    }

}
