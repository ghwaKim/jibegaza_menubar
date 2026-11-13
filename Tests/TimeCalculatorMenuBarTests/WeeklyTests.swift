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

    @Test func confirmedDayProtectsValuesAndCanBeUnlocked() {
        let vm = model()
        vm.updateWeeklyStart(idx: 4, value: "09:00")
        vm.toggleWeeklyConfirmation(idx: 4)
        #expect(vm.weeklyData[4].isConfirmed)
        #expect(!vm.isWeeklyAutoCalculated(at: 4))
        vm.updateWeeklyStart(idx: 4, value: "10:00")
        vm.updateWeeklyEnd(idx: 4, value: "17:00")
        vm.updateWeeklyLeaveType(idx: 4, leaveType: .annual)
        vm.toggleWeeklyMode(idx: 4)
        vm.resetWeeklyDay(idx: 4)
        vm.updateWeeklyEnd(idx: 0, value: "19:00")
        #expect(vm.weeklyData[4].start == "09:00")
        #expect(vm.weeklyData[4].end == "18:00")
        #expect(vm.weeklyData[4].leaveType == .none)
        vm.toggleWeeklyConfirmation(idx: 4)
        vm.updateWeeklyEnd(idx: 4, value: "17:00")
        #expect(vm.weeklyData[4].end == "17:00")
    }

    @Test func sourceLockProtectsStartButAllowsAutomaticEnd() {
        let vm = model()
        vm.updateWeeklyStart(idx: 4, value: "09:00")
        vm.toggleWeeklyLock(idx: 4, field: .start)
        vm.updateWeeklyStart(idx: 4, value: "10:00")
        vm.updateWeeklyEnd(idx: 0, value: "19:00")
        #expect(vm.weeklyData[4].start == "09:00")
        #expect(vm.weeklyData[4].end == "17:00")
        #expect(vm.isWeeklyAutoCalculated(at: 4))
        vm.toggleWeeklyLock(idx: 4, field: .end)
        vm.updateWeeklyEnd(idx: 1, value: "19:00")
        #expect(vm.weeklyData[4].end == "17:00")
        #expect(!vm.isWeeklyAutoCalculated(at: 4))
    }

    @Test func pinningEndpointEnablesReverseCalculation() {
        let vm = model()
        vm.updateWeeklyStart(idx: 4, value: "09:00")
        vm.updateWeeklyEnd(idx: 4, value: "18:00")
        #expect(!vm.isWeeklyAutoCalculated(at: 4))
        vm.toggleWeeklyLock(idx: 4, field: .end)
        #expect(vm.isWeeklyAutoCalculated(at: 4))
        vm.updateWeeklyEnd(idx: 0, value: "19:00")
        #expect(vm.weeklyData[4].end == "18:00")
        #expect(vm.weeklyData[4].start == "10:00")
        vm.updateWeeklyEnd(idx: 4, value: "19:00")
        #expect(vm.weeklyData[4].end == "18:00")
    }

    @Test func pinningPreservesEnteredTimesWhileOtherDaysAreIncomplete() {
        for field in [AutoFillType.start, .end] {
            let vm = model()
            vm.resetWeeklyDay(idx: 0)
            vm.updateWeeklyStart(idx: 4, value: "09:00")
            vm.updateWeeklyEnd(idx: 4, value: "18:00")
            vm.toggleWeeklyLock(idx: 4, field: field)
            #expect(vm.weeklyData[4].start == "09:00")
            #expect(vm.weeklyData[4].end == "18:00")
            #expect(vm.canFitWeeklyDayToEightHours(idx: 4))
            vm.updateWeeklyStart(idx: 0, value: "09:00")
            vm.updateWeeklyEnd(idx: 0, value: "19:00")
            #expect(vm.weeklyData[4].start == "09:00")
            #expect(vm.weeklyData[4].end == "18:00")
        }
    }

    @Test func pinnedEmptyEndpointStillResumesAutomaticCalculation() {
        let vm = model()
        vm.resetWeeklyDay(idx: 0)
        vm.updateWeeklyStart(idx: 4, value: "09:00")
        vm.toggleWeeklyLock(idx: 4, field: .start)
        #expect(vm.weeklyData[4].end.isEmpty)
        vm.updateWeeklyStart(idx: 0, value: "09:00")
        vm.updateWeeklyEnd(idx: 0, value: "18:00")
        #expect(vm.weeklyData[4].start == "09:00")
        #expect(vm.weeklyData[4].end == "18:00")
        #expect(vm.isWeeklyAutoCalculated(at: 4))
    }

    @Test func changingLeaveToNormalClampsManualDeparture() {
        for leave in [LeaveType.half, .halfHalf] {
            let vm = model(leave: leave)
            vm.updateWeeklyStart(idx: 4, value: "09:00")
            vm.updateWeeklyEnd(idx: 4, value: "14:00")
            vm.updateWeeklyLeaveType(idx: 4, leaveType: .none)
            #expect(vm.weeklyData[4].start == "09:00")
            #expect(vm.weeklyData[4].end == "15:30")
            #expect(getDailyMinutes(vm.weeklyData[4]) == 330)
        }
    }

    @Test func returningToNormalRangeClampsRetainedDeparture() {
        let vm = model(leave: .half)
        vm.updateWeeklyStart(idx: 4, value: "09:00")
        vm.updateWeeklyEnd(idx: 4, value: "14:00")
        vm.toggleWeeklyMode(idx: 4)
        vm.updateWeeklyLeaveType(idx: 4, leaveType: .none)
        vm.toggleWeeklyMode(idx: 4)
        #expect(vm.weeklyData[4].start == "09:00")
        #expect(vm.weeklyData[4].end == "15:30")
    }

    @Test func manualLockAndIncompleteConfirmation() {
        let vm = model(lastMode: .manual)
        vm.toggleWeeklyConfirmation(idx: 4)
        #expect(!vm.weeklyData[4].isConfirmed)
        vm.updateWeeklyEnd(idx: 0, value: "19:00")
        vm.toggleWeeklyLock(idx: 4, field: .manual)
        vm.updateWeeklyManualHours(idx: 4, value: "2")
        vm.updateWeeklyEnd(idx: 1, value: "19:00")
        #expect(vm.weeklyData[4].manualHours == "7")
        #expect(!vm.isWeeklyAutoCalculated(at: 4))
        vm.toggleWeeklyLock(idx: 4, field: .manual)
        vm.updateWeeklyManualHours(idx: 4, value: "2")
        #expect(vm.weeklyData[4].manualHours == "2")
        #expect(vm.weeklyCalculationNotice == nil)
    }

    @Test func confirmedShortWeekReportsDeficit() {
        let vm = model()
        vm.updateWeeklyStart(idx: 4, value: "09:00")
        vm.updateWeeklyEnd(idx: 4, value: "17:00")
        vm.toggleWeeklyConfirmation(idx: 4)
        #expect(vm.weeklyCalculationNotice?.contains("1시간") == true)
        #expect(vm.weeklyCalculationNotice?.contains("잠금을 해제") == true)
    }

    @Test func legacyManualPinMigratesToReleasableConfirmation() throws {
        var days = defaultWeekData()
        days[0].manualHours = "7"
        days[0].manualMinutes = "0"
        days[0].lockManual = true
        let defaults = UserDefaults(suiteName: "WeeklyTests.\(UUID().uuidString)")!
        defaults.set(try JSONEncoder().encode(days), forKey: "weeklyData")
        defaults.set(try JSONEncoder().encode(AutoFillTarget(idx: 0, type: .manual)), forKey: "autoFillTarget")
        let vm = TimeCalculatorViewModel(defaults: defaults)
        #expect(!vm.isWeeklyAutoCalculated(at: 0))
        #expect(vm.weeklyData[0].isConfirmed)
        #expect(!vm.weeklyData[0].lockManual)
        vm.updateWeeklyManualHours(idx: 0, value: "6")
        #expect(vm.weeklyData[0].manualHours == "7")
        vm.toggleWeeklyConfirmation(idx: 0)
        vm.updateWeeklyManualHours(idx: 0, value: "6")
        #expect(vm.weeklyData[0].manualHours == "6")
    }

    @Test func confirmationDecodingSupportsLegacyRecordsAndPersists() throws {
        var day = defaultWeekData()[0]
        day.mode = .range
        day.isConfirmed = true
        day.lockStart = true
        let encoded = try JSONEncoder().encode(day)
        let restored = try JSONDecoder().decode(DayWorkData.self, from: encoded)
        #expect(restored.isConfirmed && restored.lockStart)
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy.removeValue(forKey: "isConfirmed")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        #expect(try !JSONDecoder().decode(DayWorkData.self, from: legacyData).isConfirmed)
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

    @Test func clearingCalculatedEndRemainsManualWhenAnotherDayChanges() {
        let vm = model()
        vm.updateWeeklyStart(idx: 4, value: "09:00")
        vm.updateWeeklyEnd(idx: 4, value: "")
        vm.updateWeeklyEnd(idx: 0, value: "19:00")
        #expect(vm.weeklyData[4].start == "09:00")
        #expect(vm.weeklyData[4].end.isEmpty)
        #expect(!vm.isWeeklyAutoCalculated(at: 4))
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

    @Test func reverseCalculationUsesClampedNormalDeparture() {
        let vm = model(otherHours: 9)
        vm.updateWeeklyEnd(idx: 4, value: "12:00")
        #expect(vm.weeklyData[4].end == "15:30")
        #expect(vm.weeklyData[4].start == "10:30")
        #expect(vm.weekTotalText == "40시간")
        #expect(vm.weeklyCalculationNotice == nil)
        let late = model(otherHours: 9)
        late.updateWeeklyEnd(idx: 4, value: "18:00")
        #expect(late.weeklyData[4].start == "10:30")
        #expect(late.weeklyCalculationNotice?.contains("초과") == true)
    }

    @Test func directNormalDepartureClampsWithoutMovingArrivalAndCanBeCleared() {
        let vm = model()
        vm.updateWeeklyStart(idx: 4, value: "09:00")
        for (input, expected) in [("14:00", "15:30"), ("15:30", "15:30"), ("18:00", "18:00")] {
            vm.updateWeeklyEnd(idx: 4, value: input)
            #expect(vm.weeklyData[4].end == expected)
            #expect(vm.weeklyData[4].start == "09:00")
        }
        vm.resetWeeklyDay(idx: 0)
        vm.updateWeeklyEnd(idx: 4, value: "")
        #expect(vm.weeklyData[4].end.isEmpty)
        for leave in [LeaveType.half, .halfHalf] {
            let exempt = model(leave: leave)
            exempt.updateWeeklyStart(idx: 4, value: "09:00")
            exempt.updateWeeklyEnd(idx: 4, value: "14:00")
            #expect(exempt.weeklyData[4].end == "14:00")
            #expect(exempt.weeklyData[4].start == "09:00")
        }
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

    @Test func dailyCapacityReportsDeficitAndLateArrivalIsClamped() {
        let vm = model(otherHours: 7)
        vm.updateWeeklyStart(idx: 4, value: "09:00")
        #expect(vm.weekTotalText == "37시간")
        #expect(vm.weeklyCalculationNotice?.contains("9시간") == true)
        let late = model(leave: .half)
        late.updateWeeklyStart(idx: 4, value: "20:00")
        #expect(late.weeklyData[4].start == "10:30")
        #expect(late.weeklyData[4].end == "15:30")
        #expect(late.weeklyCalculationNotice == nil)
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
