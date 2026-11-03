import Foundation
import Testing
@testable import TimeCalculatorMenuBar

@MainActor
struct WeeklyTests {
    func model(lastMode: InputMode = .range, leave: LeaveType = .none, otherHours: Int = 8) -> TimeCalculatorViewModel {
        var days = defaultWeekData()
        for i in 0..<4 {
            days[i].mode = .range
            days[i].start = "09:00"
            days[i].end = minutesToTime(9 * 60 + otherHours * 60 + 60)
        }
        days[4].mode = lastMode
        days[4].leaveType = leave
        let defaults = UserDefaults(suiteName: "WeeklyTests.\(UUID().uuidString)")!
        defaults.set(try! JSONEncoder().encode(days), forKey: "weeklyData")
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12))!
        return TimeCalculatorViewModel(defaults: defaults, now: now)
    }

    @Test func automaticallyFilledEndTracksStartAndOtherDays() {
        let vm = model()
        vm.updateWeeklyStart(idx: 4, value: "09:00")
        #expect(vm.weeklyData[4].end == "18:00")
        vm.updateWeeklyStart(idx: 4, value: "10:00")
        #expect(vm.weeklyData[4].end == "19:00")
        vm.updateWeeklyEnd(idx: 0, value: "19:00")
        #expect(vm.weeklyData[4].end == "18:00")
        #expect(vm.weekTotalText == "40시간")
    }

    @Test func editingCalculatedFieldReleasesOwnership() {
        let vm = model()
        vm.updateWeeklyStart(idx: 4, value: "09:00")
        vm.updateWeeklyEnd(idx: 4, value: "17:00")
        #expect(!vm.isWeeklyAutoCalculated(at: 4))
        vm.updateWeeklyEnd(idx: 0, value: "19:00")
        #expect(vm.weeklyData[4].end == "17:00")
    }

    @Test func earliestStartReportsUnachievableGoal() {
        let vm = model()
        vm.updateWeeklyEnd(idx: 4, value: "16:00")
        #expect(vm.weeklyData[4].start == "08:00")
        #expect(vm.weeklyData[4].end == "16:00")
        #expect(vm.weekTotalText == "39시간")
        #expect(vm.weeklyCalculationNotice?.contains("1시간 부족") == true)
        #expect(vm.weeklyCalculationNotice?.contains("08:00") == true)
    }

    @Test func coreTimeAndLeaveExceptions() {
        let vm = model(otherHours: 9)
        vm.updateWeeklyStart(idx: 4, value: "08:00")
        #expect(vm.weeklyData[4].end == "15:30")
        #expect(vm.weeklyCalculationNotice?.contains("초과") == true)
        for leave in [LeaveType.half, .halfHalf] {
            let exempt = model(leave: leave, otherHours: 9)
            exempt.updateWeeklyStart(idx: 4, value: "08:00")
            #expect(exempt.weeklyData[4].end == (leave == .half ? "08:00" : "10:00"))
            #expect(exempt.weekTotalText == "40시간")
        }
    }

    @Test func reverseCoreLimitPreservesEnteredEndAndWarns() {
        let vm = model(otherHours: 9)
        vm.updateWeeklyEnd(idx: 4, value: "12:00")
        #expect(vm.weeklyData[4].start == "08:00")
        #expect(vm.weekTotalText == "40시간")
        #expect(vm.weeklyCalculationNotice?.contains("15:30 이후") == true)
        let late = model(otherHours: 9)
        late.updateWeeklyEnd(idx: 4, value: "18:00")
        #expect(late.weeklyData[4].start == "10:30")
        #expect(late.weeklyCalculationNotice?.contains("초과") == true)
    }

    @Test func leaveChangeRecalculatesAndAnnualRemovesTarget() {
        let vm = model()
        vm.updateWeeklyStart(idx: 4, value: "09:00")
        vm.updateWeeklyLeaveType(idx: 4, leaveType: .half)
        #expect(vm.weeklyData[4].end == "14:00")
        #expect(vm.weekTotalText == "40시간")
        vm.updateWeeklyLeaveType(idx: 4, leaveType: .annual)
        #expect(!vm.isWeeklyAutoCalculated(at: 4))
        #expect(vm.weekTotalText == "40시간")
    }

    @Test func dailyCapacityAndLateEndReportDeficit() {
        let vm = model(otherHours: 7)
        vm.updateWeeklyStart(idx: 4, value: "09:00")
        #expect(vm.weekTotalText == "37시간")
        #expect(vm.weeklyCalculationNotice?.contains("9시간") == true)
        let late = model()
        late.updateWeeklyStart(idx: 4, value: "20:00")
        #expect(late.weeklyData[4].end == "23:59")
        #expect(late.weeklyCalculationNotice?.contains("23:59") == true)
    }

    @Test func manualTargetRecalculatesAndCanBeOverridden() {
        let vm = model(lastMode: .manual)
        vm.updateWeeklyEnd(idx: 0, value: "19:00")
        #expect(vm.weeklyData[4].manualHours == "7")
        vm.updateWeeklyEnd(idx: 1, value: "19:00")
        #expect(vm.weeklyData[4].manualHours == "6")
        vm.updateWeeklyManualHours(idx: 4, value: "5")
        vm.updateWeeklyEnd(idx: 0, value: "18:00")
        #expect(vm.weeklyData[4].manualHours == "5")
        #expect(!vm.isWeeklyAutoCalculated(at: 4))
    }

    @Test func resettingOtherDayKeepsPendingTarget() {
        let vm = model()
        vm.updateWeeklyStart(idx: 4, value: "09:00")
        vm.resetWeeklyDay(idx: 0)
        #expect(vm.isWeeklyAutoCalculated(at: 4))
        #expect(vm.weeklyData[4].end.isEmpty)
        vm.updateWeeklyStart(idx: 0, value: "09:00")
        vm.updateWeeklyEnd(idx: 0, value: "18:00")
        #expect(vm.weeklyData[4].end == "18:00")
        #expect(vm.weekTotalText == "40시간")
    }

    @Test func incompleteDaySuspendsThenResumesCalculation() {
        let vm = model()
        vm.updateWeeklyStart(idx: 4, value: "09:00")
        vm.updateWeeklyEnd(idx: 0, value: "")
        #expect(vm.weeklyData[4].end.isEmpty)
        #expect(vm.weeklyCalculationNotice?.contains("모두 입력") == true)
        vm.updateWeeklyEnd(idx: 0, value: "19:00")
        #expect(vm.weeklyData[4].end == "17:00")
    }
}
