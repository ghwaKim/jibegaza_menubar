import Foundation
import Testing
@testable import TimeCalculatorMenuBar

struct WorkStateStoreTests {
    @Test func repairsOversizedSavedHoursWithoutClearingOtherRecords() throws {
        let suite = "WorkStateStoreTests.recovery.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var days = defaultWeekData()
        days[0].manualHours = "999999999999999999"
        days[0].isConfirmed = true
        days[1].manualHours = "8"
        days[1].manualMinutes = "30"
        days[1].isConfirmed = true
        days[2].manualHours = "10"
        days[2].importedFromFlex = true
        let original = try JSONEncoder().encode(days)
        defaults.set(original, forKey: "weeklyData")
        let saved = WorkStateStore(defaults: defaults).load(now: now, calendar: calendar)
        #expect(saved.weeklyData[0].manualHours.isEmpty)
        #expect(!saved.weeklyData[0].isConfirmed)
        #expect(getDailyMinutes(saved.weeklyData[1]) == 510)
        #expect(saved.weeklyData[1].isConfirmed)
        #expect(saved.weeklyData[2].manualHours == "10")
        #expect(saved.weeklyData[2].importedFromFlex)
        #expect(defaults.data(forKey: "weekly.invalidInputBackup") == original)
        let reloaded = WorkStateStore(defaults: defaults).load(now: now, calendar: calendar)
        #expect(reloaded.weeklyData[0].manualHours.isEmpty)
    }

    @Test func manualCalculationRejectsOverflowBeforeMultiplication() {
        for text in ["999999999999999999", String(Int.max), String(Int.max) + "0", "-1"] {
            var day = defaultWeekData()[0]
            day.manualHours = text
            #expect(getWorkMinutes(day) == 0)
            day.manualHours = "1"
            day.manualMinutes = text
            #expect(getWorkMinutes(day) == 0)
        }
        #expect(validatedManualWorkMinutes(hours: "24", minutes: "0") == 1440)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))!
    }

    @Test func readsExistingKeysAndLegacyLockedWeek() throws {
        let suite = "WorkStateStoreTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(7 * 60, forKey: "targetWorkMinutes")
        defaults.set("endTime", forKey: "lastEditedField")
        defaults.set(try JSONSerialization.data(withJSONObject: ["metric": "remaining"]), forKey: "menuBarDisplayMode")
        let legacyDay: [String: Any] = [
            "day": "월", "mode": "manual", "start": "", "end": "",
            "manualHours": "7", "manualMinutes": "30", "leaveType": "none",
            "lockStart": false, "lockEnd": false, "lockManual": true
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: Array(repeating: legacyDay, count: 5)), forKey: "weeklyData")
        let saved = WorkStateStore(defaults: defaults).load(now: now, calendar: calendar)
        #expect(saved.today.baseTargetWorkMinutes == 420)
        #expect(saved.lastEditedField == .endTime)
        #expect(saved.menuBarDisplayMode?.metric == .untilDeparture)
        #expect(saved.weeklyData[0].isConfirmed)
        #expect(!saved.weeklyData[0].lockManual)
        #expect(getDailyMinutes(saved.weeklyData[0]) == 450)
    }

    @Test func savingTodayPreservesWeeklyAndConnectionPreferences() throws {
        let suite = "WorkStateStoreTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WorkStateStore(defaults: defaults)
        var week = defaultWeekData()
        week[0].manualHours = "8"
        week[0].isConfirmed = true
        let target = AutoFillTarget(idx: 4, type: .manual)
        store.saveWeekly(data: week, target: target, excluded: [0])
        store.flexWeekStart = WorkWeek.start(for: now, calendar: calendar)
        store.flexAccountID = "same-account"
        defaults.set(false, forKey: "flex.autoSync")
        defaults.set(400, forKey: "manualOverrideTargetMinutes")
        var today = store.load(now: now, calendar: calendar).today
        today.startTime = now
        today.isStartTimeFromFlex = true
        today.manualOverrideTargetMinutes = nil
        store.saveToday(today)
        store.saveLastEditedField(.startTime)

        let reloaded = WorkStateStore(defaults: defaults)
        let saved = reloaded.load(now: now, calendar: calendar)
        #expect(saved.today.startTime == now)
        #expect(saved.today.isStartTimeFromFlex)
        #expect(saved.today.manualOverrideTargetMinutes == nil)
        #expect(defaults.object(forKey: "manualOverrideTargetMinutes") == nil)
        #expect(saved.weeklyData[0].isConfirmed)
        #expect(saved.autoFillTarget == target)
        #expect(saved.excludedAutoFillIndexes == [0])
        #expect(reloaded.flexAccountID == "same-account")
        #expect(reloaded.flexWeekStart == store.flexWeekStart)
        #expect(!defaults.bool(forKey: "flex.autoSync"))
    }
}
