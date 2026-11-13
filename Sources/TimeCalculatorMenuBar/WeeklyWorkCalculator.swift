import Foundation

/// Pure weekly validation and reverse calculation; callers own state and persistence.
enum WeeklyWorkCalculator {
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
            if day.leaveType == .none { start = min(start, 10 * 60 + 30) }
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
            if day.leaveType == .none { reasons.append("정상근무 코어타임 10:30~15:30") }
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
