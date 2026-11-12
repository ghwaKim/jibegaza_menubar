import Foundation

/// Computes a suggested goal from the current week without changing either tab.
struct TodayTargetSuggestion {
    let weeklyData: [DayWorkData]
    let currentTime: Date
    let calendar: Calendar

    enum State {
        case unavailable
        case blocked(String)
        case suggested(Int)
    }

    func resolve() -> State {
        guard let todayIndex = currentWeekdayIndex else {
            return .unavailable
        }

        guard lastActualWorkingDayIndex == todayIndex else {
            return .unavailable
        }

        guard let validationMessage = weeklyAutoSuggestionBlockingMessage(excluding: todayIndex) else {
            return suggestedTargetMinutes(for: todayIndex).map(State.suggested) ?? .unavailable
        }

        return .blocked(validationMessage)
    }

    private var currentWeekdayIndex: Int? {
        let weekday = calendar.component(.weekday, from: currentTime)
        switch weekday {
        case 2...6:
            return weekday - 2
        default:
            return nil
        }
    }

    private var lastActualWorkingDayIndex: Int? {
        weeklyData.lastIndex { $0.leaveType != .annual }
    }

    private func weeklyAutoSuggestionBlockingMessage(excluding todayIndex: Int) -> String? {
        for idx in weeklyData.indices where idx != todayIndex {
            if isWeeklyDayIncompleteForAutoSuggestion(weeklyData[idx]) {
                return "자동 목표시간을 계산하려면 오늘을 제외한 이번 주 근무시간을 입력해주세요."
            }
        }
        return nil
    }

    private func isWeeklyDayIncompleteForAutoSuggestion(_ day: DayWorkData) -> Bool {
        switch day.leaveType {
        case .annual:
            return false
        case .half:
            return isIncompleteHalfDay(day)
        case .halfHalf, .none:
            return isIncompleteRequiredWorkDay(day)
        }
    }

    private func isIncompleteHalfDay(_ day: DayWorkData) -> Bool {
        if day.mode == .manual {
            return false
        }

        let hasStart = !day.start.isEmpty
        let hasEnd = !day.end.isEmpty
        return hasStart != hasEnd
    }

    private func isIncompleteRequiredWorkDay(_ day: DayWorkData) -> Bool {
        if day.mode == .manual {
            return day.manualHours.isEmpty && day.manualMinutes.isEmpty
        }

        let hasStart = !day.start.isEmpty
        let hasEnd = !day.end.isEmpty
        return !(hasStart && hasEnd)
    }

    private func suggestedTargetMinutes(for todayIndex: Int) -> Int? {
        let todayData = weeklyData[todayIndex]
        let otherTotal = weeklyData.enumerated().reduce(0) { partial, item in
            item.offset == todayIndex ? partial : partial + getDailyMinutes(item.element)
        }

        let remainingRecognizedMinutes = weeklyGoalMinutes - otherTotal
        let suggestedMinutes = clampWorkMinutesForDay(
            todayData,
            workMinutes: remainingRecognizedMinutes - getLeaveCreditMinutes(todayData)
        )

        let hasExceededDailyCapacity =
            remainingRecognizedMinutes > getLeaveCreditMinutes(todayData) + getMaxWorkMinutesForDay(todayData)
        if hasExceededDailyCapacity || suggestedMinutes <= 0 {
            return nil
        }

        return suggestedMinutes
    }
}
