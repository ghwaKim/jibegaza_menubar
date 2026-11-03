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
}
