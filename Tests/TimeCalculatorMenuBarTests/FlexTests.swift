import Foundation
import Testing
@testable import TimeCalculatorMenuBar

@MainActor
struct FlexTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }
    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 12))!
    }

    private func payload(blocks: [[String: Any]], user: String = "me") throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "userIdHash": user,
            "dailySchedules": [["date": "2026-11-02", "dayOffs": [], "timeBlocks": blocks]]
        ])
    }
    private func block(_ type: String, _ startHour: Int, _ endHour: Int) -> [String: Any] {
        let day = calendar.startOfDay(for: date(2)).timeIntervalSince1970 * 1000
        return ["type": type, "value": ["allDay": false,
            "startTimestamp": ["timestamp": day + Double(startHour) * 3_600_000],
            "endTimestampExclusive": ["timestamp": day + Double(endHour) * 3_600_000]]]
    }

    @Test func jsonSubtractsOnlyOverlappingBreaksAndMergesDuplicates() throws {
        let data = try payload(blocks: [block("WORK", 9, 18), block("WORK", 9, 18),
                                       block("REST", 12, 13), block("REST", 12, 13), block("REST", 7, 8)])
        let records = try FlexAPI.records(from: data, userID: "me", now: date(6), calendar: calendar)
        #expect(records.count == 1)
        #expect(records.first?.minutes == 480)
        #expect(records.first?.accountID == "me")
    }

    @Test func jsonRejectsUnknownTypesLeaveAndIdentityMismatch() throws {
        for type in ["UNKNOWN", "ANNUAL_TIME_OFF"] {
            let data = try payload(blocks: [block("WORK", 9, 18), block(type, 12, 13)])
            #expect(try FlexAPI.records(from: data, userID: "me", now: date(6), calendar: calendar).isEmpty)
        }
        let data = try payload(blocks: [block("WORK", 9, 18)], user: "other")
        #expect(throws: FlexAPI.Failure.self) {
            try FlexAPI.records(from: data, userID: "me", now: date(6), calendar: calendar)
        }
    }

    @Test func longWorkDayIsImportedAndUnknownTypeHasReason() throws {
        let longDay = try payload(blocks: [block("WORK", 8, 20), block("REST", 12, 13)])
        let report = try FlexAPI.report(from: longDay, userID: "me", now: date(6), calendar: calendar)
        #expect(report.records.first?.minutes == 660)
        #expect(report.receivedDays == 1)
        let unknown = try payload(blocks: [block("CUSTOM", 9, 18)])
        let excluded = try FlexAPI.report(from: unknown, userID: "me", now: date(6), calendar: calendar)
        #expect(excluded.records.isEmpty)
        #expect(excluded.diagnostic.contains("CUSTOM"))
        #expect(excluded.diagnostic.contains("2026-11-02"))
    }

    @Test func requestUsesMondayAndExplicitTimezone() throws {
        let path = FlexAPI.schedulePath(userID: "me", now: date(6), calendar: calendar)
        let parts = try #require(URLComponents(string: path))
        #expect(parts.path == "/api/v3/time-tracking/users/me/work-schedules")
        #expect(parts.queryItems?.contains(URLQueryItem(name: "from", value: "2026-11-02")) == true)
        #expect(parts.queryItems?.contains(URLQueryItem(name: "to", value: "2026-11-06")) == true)
        #expect(parts.queryItems?.contains(URLQueryItem(name: "timezone", value: "Asia/Seoul")) == true)
    }

    @Test func sessionRequestUsesOnlyFlexCookiesAndCustomerToken() throws {
        func cookie(_ name: String, _ value: String, _ domain: String = "flex.team") -> HTTPCookie {
            HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: "/"])!
        }
        let cookies = [cookie("AID", "test-token"), cookie("V2_WS_AID", "workspace-token"),
                       cookie("DEVICE_ID", "existing-device"), cookie("other", "excluded", "example.com")]
        let request = try FlexSessionClient.request(path: FlexAPI.identityPath, cookies: cookies, deviceID: "fallback")
        #expect(request.url?.host == "flex.team")
        #expect(request.value(forHTTPHeaderField: "x-flex-aid") == "test-token")
        #expect(request.value(forHTTPHeaderField: "Flexteam-Deviceid") == "existing-device")
        #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("other=") == false)
        #expect(request.value(forHTTPHeaderField: "Referer") == "https://flex.team/home")
        #expect(throws: FlexSessionClient.Failure.self) {
            try FlexSessionClient.request(path: FlexAPI.identityPath,
                                          cookies: [cookie("V2_WS_AID", "workspace-token")], deviceID: "device")
        }
        #expect(throws: FlexSessionClient.Failure.self) {
            try FlexSessionClient.request(path: "//example.com/api/", cookies: cookies, deviceID: "device")
        }
    }

    @Test func scopeRejectsOtherWeeksTodayAndWeekend() {
        #expect(FlexImportScope.index(for: date(2), now: date(6), calendar: calendar) == 0)
        #expect(FlexImportScope.index(for: date(6), now: date(6), calendar: calendar) == nil)
        #expect(FlexImportScope.index(for: date(1), now: date(6), calendar: calendar) == nil)
        #expect(FlexImportScope.index(for: date(7), now: date(9), calendar: calendar) == nil)
    }

    @Test func importRefreshesFlexValuesAndRejectsWrongWeek() {
        let defaults = UserDefaults(suiteName: "FlexTests.\(UUID())")!
        let vm = TimeCalculatorViewModel(defaults: defaults, now: date(6))
        let monday = calendar.startOfDay(for: date(2))
        _ = vm.importFlexRecords([FlexWorkRecord(date: monday, minutes: 495)], now: date(6))
        #expect(vm.weeklyData[0].manualHours == "8")
        #expect(vm.weeklyData[0].manualMinutes == "15")
        #expect(vm.weeklyData[0].isConfirmed)
        #expect(vm.weeklyData[0].isFlexAutoLocked)
        _ = vm.importFlexRecords([FlexWorkRecord(date: monday, minutes: 300)], now: date(6))
        #expect(vm.weeklyData[0].manualHours == "5")
        _ = vm.importFlexRecords([FlexWorkRecord(date: date(9), minutes: 480)], now: date(10))
        #expect(vm.weeklyData[0].manualHours == "5")
    }

    @Test func clockStatusOnlyReturnsConfirmedEndedWork() throws {
        let now = date(2).addingTimeInterval(7 * 3600)
        let dayStart = calendar.startOfDay(for: now).timeIntervalSince1970 * 1000
        func record(_ type: String, from: Int, to: Int) -> [String: Any] {
            ["workFormType": type, "eventStatus": "CONFIRMED",
             "blockTimeFrom": ["timeStamp": dayStart + Double(from) * 3_600_000],
             "blockTimeTo": ["timeStamp": dayStart + Double(to) * 3_600_000]]
        }
        func status(ongoing: Any, end: Int) throws -> FlexAPI.ClockStatus {
            let json: [String: Any] = [
                "targetDate": "2026-11-02",
                "onGoingRecordPack": ongoing,
                "targetDayWorkSchedule": [
                    "date": "2026-11-02",
                    "workRecords": [record("WORK", from: 9, to: end), record("REST", from: 12, to: 13)]
                ]
            ]
            return try JSONDecoder().decode(FlexAPI.ClockStatus.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let working = try status(ongoing: ["onGoing": true], end: 18)
        #expect(working.isWorking)
        #expect(working.completedRecord(userID: "me", now: now, calendar: calendar) == nil)
        let finished = try status(ongoing: NSNull(), end: 18)
        #expect(finished.completedRecord(userID: "me", now: now, calendar: calendar)?.minutes == 480)
        let future = try status(ongoing: NSNull(), end: 20)
        #expect(future.completedRecord(userID: "me", now: now, calendar: calendar) == nil)
    }

    @Test func automaticImportAcceptsTodayAndKeepsManualValuesOnWeekChange() {
        let defaults = UserDefaults(suiteName: "FlexTests.auto.\(UUID())")!
        let vm = TimeCalculatorViewModel(defaults: defaults, now: date(2))
        let today = FlexWorkRecord(date: date(2), minutes: 480, accountID: "me")
        _ = vm.importFlexRecords([today], now: date(2))
        #expect(!vm.weeklyData[0].importedFromFlex)
        _ = vm.importFlexRecords([today], now: date(2), automatic: true)
        #expect(vm.weeklyData[0].importedFromFlex)
        let nextMonday = FlexWorkRecord(date: date(9), minutes: 450, accountID: "me")
        _ = vm.importFlexRecords([nextMonday], now: date(9), automatic: true)
        #expect(vm.weeklyData[0].manualMinutes == "30")
        vm.toggleWeeklyConfirmation(idx: 0)
        vm.toggleWeeklyConfirmation(idx: 0)
        _ = vm.importFlexRecords([FlexWorkRecord(date: date(16), minutes: 420, accountID: "me")],
                                 now: date(16), automatic: true)
        #expect(vm.weeklyData[0].manualMinutes == "30")
    }


    @Test func completedFlexWorkReplacesManualPlansButKeepsFutureAndLocks() {
        let defaults = UserDefaults(suiteName: "FlexTests.plans.\(UUID())")!
        let vm = TimeCalculatorViewModel(defaults: defaults, now: date(6))
        vm.updateWeeklyManualHours(idx: 0, value: "8")
        vm.updateWeeklyManualHours(idx: 1, value: "8")
        vm.toggleWeeklyConfirmation(idx: 1)
        vm.toggleWeeklyMode(idx: 2)
        vm.updateWeeklyStart(idx: 2, value: "09:00")
        vm.toggleWeeklyLock(idx: 2, field: .start)
        vm.updateWeeklyManualHours(idx: 3, value: "8")
        vm.updateWeeklyManualHours(idx: 4, value: "8")

        let records = (2...6).map { FlexWorkRecord(date: date($0), minutes: 450, accountID: "me") }
        _ = vm.importFlexRecords(records, now: date(6))

        #expect(vm.weeklyData[0].manualHours == "7")
        #expect(vm.weeklyData[0].manualMinutes == "30")
        #expect(vm.weeklyData[0].importedFromFlex)
        #expect(vm.weeklyData[0].isConfirmed)
        #expect(vm.weeklyData[0].isFlexAutoLocked)
        #expect(vm.weeklyData[1].manualHours == "8")
        #expect(vm.weeklyData[1].isConfirmed)
        #expect(vm.weeklyData[2].start == "09:00")
        #expect(vm.weeklyData[2].lockStart)
        #expect(!vm.weeklyData[2].importedFromFlex)
        #expect(vm.weeklyData[3].manualMinutes == "30")
        #expect(vm.weeklyData[4].manualHours == "8")
        #expect(!vm.weeklyData[4].importedFromFlex)

        vm.toggleWeeklyConfirmation(idx: 0)
        vm.toggleWeeklyConfirmation(idx: 0)
        #expect(!vm.weeklyData[0].isFlexAutoLocked)
        _ = vm.importFlexRecords([FlexWorkRecord(date: date(2), minutes: 420, accountID: "me")], now: date(6))
        #expect(vm.weeklyData[0].manualMinutes == "30")
        vm.toggleWeeklyConfirmation(idx: 0)
        _ = vm.importFlexRecords([FlexWorkRecord(date: date(2), minutes: 420, accountID: "me")], now: date(6))
        #expect(vm.weeklyData[0].manualMinutes == "0")
    }

    @Test func flexActualRecalculatesRemainingPlanAndReleasesCalculatedTarget() {
        let defaults = UserDefaults(suiteName: "FlexTests.target.\(UUID())")!
        let vm = TimeCalculatorViewModel(defaults: defaults, now: date(6))
        for index in 0..<4 { vm.updateWeeklyManualHours(idx: index, value: "8") }
        #expect(vm.isWeeklyAutoCalculated(at: 4))
        _ = vm.importFlexRecords([FlexWorkRecord(date: date(2), minutes: 450)], now: date(6))
        #expect(vm.weeklyData[4].manualHours == "8")
        #expect(vm.weeklyData[4].manualMinutes == "30")
        _ = vm.importFlexRecords([FlexWorkRecord(date: date(6), minutes: 420)], now: date(6), automatic: true)
        #expect(!vm.isWeeklyAutoCalculated(at: 4))
        #expect(vm.weeklyData[4].manualHours == "7")
        vm.updateWeeklyManualHours(idx: 1, value: "7")
        #expect(vm.weeklyData[4].manualHours == "7")
    }

    @Test func legacyFlexAutoLockMigratesAndNewUserLockPersists() throws {
        var day = defaultWeekData()[0]
        day.manualHours = "8"
        day.importedFromFlex = true
        day.isConfirmed = true
        let encoded = try JSONEncoder().encode(day)
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "flexImportUsesManualLock")
        legacy.removeValue(forKey: "isFlexAutoLocked")
        let migrated = try JSONDecoder().decode(DayWorkData.self,
            from: JSONSerialization.data(withJSONObject: legacy))
        #expect(migrated.isConfirmed)
        #expect(migrated.isFlexAutoLocked)
        #expect(migrated.importedFromFlex)
        let current = try JSONDecoder().decode(DayWorkData.self, from: encoded)
        #expect(current.isConfirmed)
        #expect(!current.isFlexAutoLocked)
        #expect(current.importedFromFlex)
    }

}
