import Foundation

/// Date calculations only; no timers, saved settings, or sync state.
struct TodayWorkCalculator {
    let calendar: Calendar

    enum EditedField: String { case startTime, endTime }

    func constrainedStart(_ date: Date) -> Date {
        let earliest = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date
        return max(date, earliest)
    }

    func constrainedEnd(_ date: Date, appliesCoreTime: Bool) -> Date {
        guard appliesCoreTime else { return date }
        let earliest = calendar.date(bySettingHour: 15, minute: 30, second: 0, of: date) ?? date
        return max(date, earliest)
    }

    func alignedTimes(
        start: Date, end: Date, targetWorkMinutes: Int, lastEditedField: EditedField, appliesCoreTime: Bool
    ) -> (start: Date, end: Date) {
        var startTime = constrainedStart(start)
        var endTime = end
        switch lastEditedField {
        case .startTime:
            let minutes = calendar.component(.hour, from: startTime) * 60 + calendar.component(.minute, from: startTime)
            let result = calculateReverseTime(baseTimeMinutes: minutes, targetMinutes: targetWorkMinutes, type: .end)
            endTime = constrainedEnd(addingMinutes(result - minutes, to: startTime), appliesCoreTime: appliesCoreTime)
        case .endTime:
            endTime = constrainedEnd(endTime, appliesCoreTime: appliesCoreTime)
            let minutes = calendar.component(.hour, from: endTime) * 60 + calendar.component(.minute, from: endTime)
            var result = calculateReverseTime(baseTimeMinutes: minutes, targetMinutes: targetWorkMinutes, type: .start)
            if appliesCoreTime { result = min(result, 10 * 60 + 30) }
            if result < earliestStartMinutes {
                startTime = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: endTime) ?? endTime
                let endMinutes = calculateReverseTime(
                    baseTimeMinutes: earliestStartMinutes, targetMinutes: targetWorkMinutes, type: .end)
                endTime = constrainedEnd(
                    addingMinutes(endMinutes - earliestStartMinutes, to: startTime), appliesCoreTime: appliesCoreTime)
            } else {
                startTime = addingMinutes(result - minutes, to: endTime)
            }
        }
        return (startTime, endTime)
    }

    private func overlapMinutes(firstStart: Date, firstEnd: Date, secondStart: Date, secondEnd: Date) -> Int {
        let overlapStart = max(firstStart, secondStart)
        let overlapEnd = min(firstEnd, secondEnd)
        guard overlapEnd > overlapStart else { return 0 }
        return Int(overlapEnd.timeIntervalSince(overlapStart) / 60)
    }

    func workMinutes(start: Date, end: Date) -> Int {
        let raw = max(0, Int(end.timeIntervalSince(start) / 60))
        let breakStart = calendar.date(bySettingHour: 12, minute: 30, second: 0, of: start) ?? start
        let breakEnd = calendar.date(bySettingHour: 13, minute: 30, second: 0, of: start) ?? start
        return max(
            0,
            raw
                - overlapMinutes(
                    firstStart: start, firstEnd: end,
                    secondStart: breakStart, secondEnd: breakEnd))
    }

    private func addingMinutes(_ minutes: Int, to date: Date) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: date) ?? date
    }
}
