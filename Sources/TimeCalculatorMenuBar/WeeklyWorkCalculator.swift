import Foundation

/// Pure weekly validation and reverse calculation; callers own state and persistence.
enum WeeklyWorkCalculator {
    enum FitResult {
        case fitted(DayWorkData)
        case unavailable(String)
    }

    static func eightHourAnchor(for day: DayWorkData) -> AutoFillType? {
        guard day.mode == .range, day.leaveType != .annual, !day.isConfirmed,
              !(day.lockStart && day.lockEnd) else { return nil }
        if day.lockStart { return day.start.isEmpty ? nil : .start }
        if day.lockEnd { return day.end.isEmpty ? nil : .end }
        return nil
    }

    static func fitToEightHours(_ day: DayWorkData) -> FitResult {
        guard let anchor = eightHourAnchor(for: day) else {
            return .unavailable("출근 또는 퇴근 중 한 시각만 고정해주세요. 반대편 시각을 계산합니다.")
        }
        let needed = 8 * 60 - getLeaveCreditMinutes(day)
        var fitted = day
        if anchor == .start {
            let start = timeToMinutes(day.start)
            let end = calculateReverseTime(baseTimeMinutes: start, targetMinutes: needed, type: .end)
            // Keep these checks for older saved records and leave-day inputs.
            guard start >= earliestStartMinutes, end <= 1439 else {
                return .unavailable("출근 08:00 이후·당일 퇴근 조건으로 8시간을 맞출 수 없습니다.")
            }
            fitted.end = minutesToTime(end)
        } else {
            let start = calculateReverseTime(baseTimeMinutes: timeToMinutes(day.end), targetMinutes: needed, type: .start)
            guard start >= earliestStartMinutes else {
                return .unavailable("8시간을 맞추려면 08:00 이전 출근이 필요합니다. 기준 시각을 조정해주세요.")
            }
            fitted.start = minutesToTime(start)
        }
        if timeToMinutes(fitted.start) > 10 * 60 + 30 {
            return .unavailable("출근 상한 10:30을 지키면서 8시간을 맞출 수 없습니다. 기준 시각을 조정해주세요.")
        }
        // Eight hours of normal work starting at or after 08:00 ends no earlier
        // than 17:00, so a separate 15:30 core-time check is unnecessary here.
        guard getDailyMinutes(fitted) == 8 * 60 else {
            return .unavailable("입력한 구간으로 인정시간 8시간을 맞출 수 없습니다.")
        }
        fitted.importedFromFlex = false
        fitted.isFlexAutoLocked = false
        return .fitted(fitted)
    }

    static func isCompleteWeeklyDay(_ day: DayWorkData) -> Bool {
        if day.leaveType == .annual { return true }
        if day.mode == .manual { return !day.manualHours.isEmpty || !day.manualMinutes.isEmpty }
        return !day.start.isEmpty && !day.end.isEmpty && timeToMinutes(day.end) >= timeToMinutes(day.start)
    }

    static func isValidAutoFillTarget(data: [DayWorkData], target: AutoFillTarget?) -> Bool {
        guard let target, data.indices.contains(target.idx) else {
            return false
        }

        let day = data[target.idx]
        if day.leaveType == .annual || day.importedFromFlex || day.isLocked(target.type) {
            return false
        }

        switch target.type {
        case .manual:
            return day.mode == .manual
        case .end:
            return day.mode == .range && !day.start.isEmpty
        case .start:
            return day.mode == .range && !day.end.isEmpty
        }
    }

    static func isSameAutoFillTarget(_ lhs: AutoFillTarget?, _ rhs: AutoFillTarget?) -> Bool {
        lhs == rhs
    }

    static func autoFillCandidates(data: [DayWorkData], excludedIndexes: [Int] = []) -> [AutoFillTarget] {
        data.enumerated().flatMap { idx, day -> [AutoFillTarget] in
            if excludedIndexes.contains(idx) || day.leaveType == .annual || day.isConfirmed {
                return []
            }

            if day.mode == .manual {
                let hasManualInput = !day.manualHours.isEmpty || !day.manualMinutes.isEmpty
                if !hasManualInput && !day.lockManual {
                    return [AutoFillTarget(idx: idx, type: .manual)]
                }
                return []
            }

            if !day.start.isEmpty && day.end.isEmpty && !day.lockEnd {
                return [AutoFillTarget(idx: idx, type: .end)]
            }

            if !day.end.isEmpty && day.start.isEmpty && !day.lockStart {
                return [AutoFillTarget(idx: idx, type: .start)]
            }

            return []
        }
    }

    static func inferAutoFillTarget(data: [DayWorkData], excludedIndexes: [Int] = []) -> AutoFillTarget? {
        let candidates = autoFillCandidates(data: data, excludedIndexes: excludedIndexes)
        return candidates.count == 1 ? candidates[0] : nil
    }

    static func applyAutoFill(
        data: [DayWorkData],
        preferredTarget: AutoFillTarget?,
        excludedIndexes: [Int] = [],
        allowPreferredOverride: Bool = false
    ) -> (nextData: [DayWorkData], nextTarget: AutoFillTarget?) {
        let inferredTarget = inferAutoFillTarget(data: data, excludedIndexes: excludedIndexes)
        let resolvedTarget: AutoFillTarget?

        if let preferredTarget,
            isValidAutoFillTarget(data: data, target: preferredTarget),
            !excludedIndexes.contains(preferredTarget.idx),
            allowPreferredOverride || isSameAutoFillTarget(preferredTarget, inferredTarget)
        {
            resolvedTarget = preferredTarget
        } else {
            resolvedTarget = inferredTarget
        }

        guard let resolvedTarget else {
            return (data, nil)
        }
        guard
            data.enumerated().allSatisfy({ index, day in
                index == resolvedTarget.idx || isCompleteWeeklyDay(day)
            })
        else {
            var pendingData = data
            switch resolvedTarget.type {
            case .manual:
                pendingData[resolvedTarget.idx].manualHours = ""
                pendingData[resolvedTarget.idx].manualMinutes = ""
            case .start: pendingData[resolvedTarget.idx].start = ""
            case .end: pendingData[resolvedTarget.idx].end = ""
            }
            return (pendingData, resolvedTarget)
        }

        var nextData = data
        let otherTotal = nextData.enumerated().reduce(0) { partial, item in
            item.offset == resolvedTarget.idx ? partial : partial + getDailyMinutes(item.element)
        }

        let targetRecognizedMinutes = weeklyGoalMinutes - otherTotal
        let leaveCreditMinutes = getLeaveCreditMinutes(nextData[resolvedTarget.idx])
        let targetWorkMinutes = clampWorkMinutesForDay(
            nextData[resolvedTarget.idx],
            workMinutes: targetRecognizedMinutes - leaveCreditMinutes
        )

        let day = nextData[resolvedTarget.idx]
        switch resolvedTarget.type {
        case .manual:
            nextData[resolvedTarget.idx].manualHours = String(targetWorkMinutes / 60)
            nextData[resolvedTarget.idx].manualMinutes = String(targetWorkMinutes % 60)
        case .end:
            let start = max(earliestStartMinutes, timeToMinutes(day.start))
            var end = calculateReverseTime(baseTimeMinutes: start, targetMinutes: targetWorkMinutes, type: .end)
            if day.leaveType == .none { end = max(end, 15 * 60 + 30) }
            nextData[resolvedTarget.idx].end = minutesToTime(end)
        case .start:
            var start = calculateReverseTime(
                baseTimeMinutes: timeToMinutes(day.end), targetMinutes: targetWorkMinutes, type: .start)
            start = min(start, 10 * 60 + 30)
            nextData[resolvedTarget.idx].start = minutesToTime(max(earliestStartMinutes, start))
        }
        return (nextData, resolvedTarget)
    }

    static func notice(data weeklyData: [DayWorkData], target autoFillTarget: AutoFillTarget?) -> String? {
        let weeklyWorkedMinutes = weeklyData.reduce(0) { $0 + getDailyMinutes($1) }
        guard let target = autoFillTarget else {
            if weeklyData.contains(where: { $0.isConfirmed || $0.lockStart || $0.lockEnd || $0.lockManual }),
                weeklyData.allSatisfy(isCompleteWeeklyDay), weeklyWorkedMinutes < weeklyGoalMinutes
            {
                return "주 40시간까지 " + formatMinutesToKorean(weeklyGoalMinutes - weeklyWorkedMinutes)
                    + " 부족합니다. 고정된 값은 유지됩니다. 수정하려면 잠금을 해제해주세요."
            }
            return nil
        }
        let othersComplete = weeklyData.enumerated().allSatisfy { index, day in
            index == target.idx || isCompleteWeeklyDay(day)
        }
        guard othersComplete else { return "자동 계산하려면 다른 요일의 근무시간을 모두 입력해주세요." }
        let day = weeklyData[target.idx]
        var reasons: [String] = []
        let otherTotal = weeklyData.enumerated().reduce(0) {
            $0 + ($1.offset == target.idx ? 0 : getDailyMinutes($1.element))
        }
        if weeklyGoalMinutes - otherTotal > maxDailyMinutes { reasons.append("일 최대 인정시간 9시간") }
        if day.mode == .range {
            if target.type == .start && timeToMinutes(day.start) == earliestStartMinutes {
                reasons.append("출근 하한 08:00")
            }
            if target.type == .start && timeToMinutes(day.start) == 10 * 60 + 30 {
                reasons.append("출근 상한 10:30")
            }
            if day.leaveType == .none { reasons.append("정상근무 최소 퇴근 15:30") }
            if timeToMinutes(day.end) == 1439 { reasons.append("당일 종료 한도 23:59") }
        }
        let total = weeklyWorkedMinutes
        let violatesCoreEnd = day.mode == .range && day.leaveType == .none && timeToMinutes(day.end) < 15 * 60 + 30
        if violatesCoreEnd {
            let balance =
                total == weeklyGoalMinutes
                ? "합계는 40시간이지만"
                : "주 40시간 대비 " + formatMinutesToKorean(abs(weeklyGoalMinutes - total))
                    + (total < weeklyGoalMinutes ? " 부족합니다." : " 초과합니다.")
            return balance + " 정상근무 퇴근은 15:30 이후여야 합니다. 입력한 퇴근 시각을 조정해주세요."
        }
        guard total != weeklyGoalMinutes else { return nil }
        let difference = formatMinutesToKorean(abs(weeklyGoalMinutes - total))
        let reason = reasons.isEmpty ? "입력한 시각과 휴가 인정시간" : reasons.joined(separator: " · ")
        return "주 40시간 대비 \(difference) \(total < weeklyGoalMinutes ? "부족" : "초과") · \(reason) 반영. 입력값을 조정해주세요."
    }
}
