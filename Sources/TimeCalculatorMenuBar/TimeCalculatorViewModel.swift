import Combine
import Foundation
import SwiftUI

@MainActor
final class TimeCalculatorViewModel: ObservableObject {
    @Published var selectedTab: WorkTab = .today
    @Published private(set) var isStartTimeFromFlex: Bool
    @Published private(set) var startTime: Date
    @Published private(set) var endTime: Date
    @Published private(set) var targetWorkMinutes: Int
    @Published private(set) var baseTargetWorkMinutes: Int
    @Published private(set) var menuBarDisplayMode: MenuBarDisplayMode?
    @Published private(set) var isStartTimeUnset: Bool
    @Published private(set) var isEndTimeUnset: Bool
    @Published private(set) var weeklyData: [DayWorkData]
    @Published private(set) var todayTargetMode: TodayTargetMode
    @Published private(set) var targetInputHours: String
    @Published private(set) var targetInputMinutes: String
    @Published private(set) var todayTargetGuideText: String?
    @Published private var currentTime: Date

    private let defaults: UserDefaults
    private let calendar = Calendar.current
    private let fixedBreakMinutes = 60
    private var timerCancellable: AnyCancellable?
    private var trackedDayStart: Date
    private var autoFillTarget: AutoFillTarget?
    private var excludedAutoFillIndexes: [Int]
    private var manualOverrideTargetMinutes: Int?
    private var autoSuggestedTargetMinutes: Int?
    private var isManualTargetSelectionActive: Bool

    private enum Keys {
        static let startTime = "startTime"
        static let isStartTimeFromFlex = "isStartTimeFromFlex"
        static let endTime = "endTime"
        static let targetWorkMinutes = "targetWorkMinutes"
        static let baseTargetWorkMinutes = "baseTargetWorkMinutes"
        static let manualOverrideTargetMinutes = "manualOverrideTargetMinutes"
        static let isManualTargetSelectionActive = "isManualTargetSelectionActive"
        static let lastEditedField = "lastEditedField"
        static let menuBarDisplayMode = "menuBarDisplayMode"
        static let lastActiveDayStart = "lastActiveDayStart"
        static let isStartTimeUnset = "isStartTimeUnset"
        static let isEndTimeUnset = "isEndTimeUnset"
        static let weeklyData = "weeklyData"
        static let autoFillTarget = "autoFillTarget"
        static let excludedAutoFillIndexes = "excludedAutoFillIndexes"
    }

    private enum EditedField: String {
        case startTime
        case endTime
    }

    private var lastEditedField: EditedField {
        didSet { defaults.set(lastEditedField.rawValue, forKey: Keys.lastEditedField) }
    }

    init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        currentTime = now
        trackedDayStart = calendar.startOfDay(for: now)

        let defaultStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        let legacyTargetMinutes = defaults.object(forKey: Keys.targetWorkMinutes) as? Int ?? 8 * 60
        let initialBaseTargetWorkMinutes = defaults.object(forKey: Keys.baseTargetWorkMinutes) as? Int ?? legacyTargetMinutes
        let initialStartTime = defaults.object(forKey: Keys.startTime) as? Date ?? defaultStart
        let savedEditedField = defaults.string(forKey: Keys.lastEditedField)
        lastEditedField = EditedField(rawValue: savedEditedField ?? "") ?? .startTime

        let initialEndTime = defaults.object(forKey: Keys.endTime) as? Date
            ?? calendar.date(byAdding: .minute, value: initialBaseTargetWorkMinutes + fixedBreakMinutes, to: initialStartTime)
            ?? initialStartTime

        targetWorkMinutes = initialBaseTargetWorkMinutes
        baseTargetWorkMinutes = initialBaseTargetWorkMinutes
        startTime = initialStartTime
        isStartTimeFromFlex = defaults.bool(forKey: Keys.isStartTimeFromFlex)
        endTime = initialEndTime
        menuBarDisplayMode = Self.loadMenuBarDisplayMode(from: defaults)
        isStartTimeUnset = defaults.object(forKey: Keys.isStartTimeUnset) as? Bool ?? false
        isEndTimeUnset = defaults.object(forKey: Keys.isEndTimeUnset) as? Bool ?? false
        weeklyData = Self.loadWeeklyData(from: defaults)
        todayTargetMode = .preset
        targetInputHours = String(initialBaseTargetWorkMinutes / 60)
        targetInputMinutes = String(format: "%02d", initialBaseTargetWorkMinutes % 60)
        todayTargetGuideText = nil
        autoFillTarget = Self.loadAutoFillTarget(from: defaults)
        excludedAutoFillIndexes = defaults.array(forKey: Keys.excludedAutoFillIndexes) as? [Int] ?? []
        manualOverrideTargetMinutes = defaults.object(forKey: Keys.manualOverrideTargetMinutes) as? Int
        isManualTargetSelectionActive = defaults.object(forKey: Keys.isManualTargetSelectionActive) as? Bool ?? false
        autoSuggestedTargetMinutes = nil

        if let target = autoFillTarget, !isValidAutoFillTarget(data: weeklyData, target: target) {
            autoFillTarget = nil
            defaults.removeObject(forKey: Keys.autoFillTarget)
        }

        if shouldResetForNewDay(referenceDate: now) {
            resetTodayForNewDay(referenceDate: now)
        } else {
            defaults.set(trackedDayStart, forKey: Keys.lastActiveDayStart)
        }

        refreshTodayTargetFromCurrentContext(syncInputFields: true)
        startTimer()
    }

    var menuBarTitle: String {
        guard let mode = menuBarDisplayMode else {
            return "-- -- --"
        }

        switch mode.metric {
        case .worked:
            return compactDuration(workedMinutesToday)
        case .untilDeparture:
            return signedCompactDuration(remainingDepartureMinutes)
        case .hidden:
            return ""
        }
    }

    var menuBarEmoji: String {
        {
            guard let metric = menuBarDisplayMode?.metric else { return "❓" }
            let remaining = remainingDepartureMinutes
            if metric == .untilDeparture {
                return remaining < 0 ? "✅" : (remaining == 0 ? "✅" : (menuBarDisplayMode?.menuBarEmoji ?? "⏳"))
            }
            return menuBarDisplayMode?.menuBarEmoji ?? "❓"
        }()
    }

    var formattedTargetWork: String {
        formatMinutesToKorean(targetWorkMinutes)
    }

    var formattedStartTime: String {
        isStartTimeUnset ? "-- --" : formattedClock(startTime)
    }

    var formattedEndTime: String {
        isEndTimeUnset ? "-- --" : formattedClock(endTime)
    }

    var formattedWorkedToday: String {
        let workedText = formatMinutesToKorean(workedMinutesToday)
        guard workedMinutesToday > maxDailyMinutes else {
            return workedText
        }
        return "\(workedText) (인정시간: \(formatMinutesToKorean(recognizedWorkedMinutesToday)))"
    }

    var formattedRemainingToday: String {
        remainingWorkMinutesToday < 0
            ? formatMinutesToKorean(-remainingWorkMinutesToday)
            : (remainingWorkMinutesToday == 0 ? "목표 근무 완료" : formatMinutesToKorean(remainingWorkMinutesToday))
    }

    var remainingWorkLabel: String {
        remainingWorkMinutesToday < 0 ? "초과 근무시간" : "오늘 남은 근무시간"
    }

    var formattedRemainingDeparture: String {
        guard !isStartTimeUnset && !isEndTimeUnset else { return "-- --" }
        if remainingDepartureMinutes < 0 {
            return "퇴근 가능 시각 " + formatMinutesToKorean(-remainingDepartureMinutes) + " 경과"
        }
        return remainingDepartureMinutes == 0 ? "집에가자 😎" : formatMinutesToKorean(remainingDepartureMinutes)
    }

    private var remainingDepartureMinutes: Int {
        guard !isStartTimeUnset && !isEndTimeUnset else { return 0 }
        return Int(ceil(endTime.timeIntervalSince(currentTime) / 60))
    }

    private var appliesCoreTime: Bool {
        guard let index = currentWeekdayIndex else { return false }
        return weeklyData[index].leaveType == .none
    }

    private func isCompleteWeeklyDay(_ day: DayWorkData) -> Bool {
        if day.leaveType == .annual { return true }
        if day.mode == .manual { return !day.manualHours.isEmpty || !day.manualMinutes.isEmpty }
        return !day.start.isEmpty && !day.end.isEmpty && timeToMinutes(day.end) >= timeToMinutes(day.start)
    }

    func isWeeklyAutoCalculated(at index: Int) -> Bool {
        autoFillTarget?.idx == index
    }

    var weeklyCalculationNotice: String? {
        guard let target = autoFillTarget else {
            if weeklyData.contains(where: { $0.isConfirmed || $0.lockStart || $0.lockEnd || $0.lockManual }),
               weeklyData.allSatisfy(isCompleteWeeklyDay), weeklyWorkedMinutes < weeklyGoalMinutes {
                return "주 40시간까지 " + formatMinutesToKorean(weeklyGoalMinutes - weeklyWorkedMinutes) + " 부족합니다. 고정된 값은 유지됩니다. 수정하려면 잠금을 해제해주세요."
            }
            return nil
        }
        let othersComplete = weeklyData.enumerated().allSatisfy { index, day in
            index == target.idx || isCompleteWeeklyDay(day)
        }
        guard othersComplete else { return "자동 계산하려면 다른 요일의 근무시간을 모두 입력해주세요." }
        let day = weeklyData[target.idx]
        var reasons: [String] = []
        let otherTotal = weeklyData.enumerated().reduce(0) { $0 + ($1.offset == target.idx ? 0 : getDailyMinutes($1.element)) }
        if weeklyGoalMinutes - otherTotal > maxDailyMinutes { reasons.append("일 최대 인정시간 9시간") }
        if day.mode == .range {
            if target.type == .start && timeToMinutes(day.start) == earliestStartMinutes { reasons.append("출근 하한 08:00") }
            if day.leaveType == .none { reasons.append("정상근무 코어타임 10:30~15:30") }
            if timeToMinutes(day.end) == 1439 { reasons.append("당일 종료 한도 23:59") }
        }
        let total = weeklyWorkedMinutes
        let violatesCoreEnd = day.mode == .range && day.leaveType == .none && timeToMinutes(day.end) < 15 * 60 + 30
        if violatesCoreEnd {
            let balance = total == weeklyGoalMinutes ? "합계는 40시간이지만" : "주 40시간 대비 " + formatMinutesToKorean(abs(weeklyGoalMinutes - total)) + (total < weeklyGoalMinutes ? " 부족합니다." : " 초과합니다.")
            return balance + " 정상근무 퇴근은 15:30 이후여야 합니다. 입력한 퇴근 시각을 조정해주세요."
        }
        guard total != weeklyGoalMinutes else { return nil }
        let difference = formatMinutesToKorean(abs(weeklyGoalMinutes - total))
        let reason = reasons.isEmpty ? "입력한 시각과 휴가 인정시간" : reasons.joined(separator: " · ")
        return "주 40시간 대비 \(difference) \(total < weeklyGoalMinutes ? "부족" : "초과") · \(reason) 반영. 입력값을 조정해주세요."
    }

    var weekTotalText: String {
        formatMinutesToKorean(weeklyWorkedMinutes)
    }

    var hasRemainingWeeklyWork: Bool {
        weeklyRemainingMinutes > 0
    }

    var weekRemainingText: String {
        weeklyRemainingMinutes == 0 ? "집에가자 😎" : formatMinutesToKorean(weeklyRemainingMinutes)
    }

    var menuBarMetricBinding: Binding<MenuBarMetric> {
        Binding(
            get: { self.menuBarDisplayMode?.metric ?? .untilDeparture },
            set: { self.updateMenuBarMetric($0) }
        )
    }

    var startTimeBinding: Binding<Date> {
        Binding(
            get: { self.startTime },
            set: { self.updateStartTime($0) }
        )
    }

    var endTimeBinding: Binding<Date> {
        Binding(
            get: { self.endTime },
            set: { self.updateEndTime($0) }
        )
    }

    var selectedPresetHoursBinding: Binding<Int> {
        Binding(
            get: { self.baseTargetWorkMinutes / 60 },
            set: { self.updatePresetTargetHours($0) }
        )
    }

    var todayTargetSelectionBinding: Binding<TodayTargetSelection> {
        Binding(
            get: { self.todayTargetSelection },
            set: { self.updateTodayTargetSelection($0) }
        )
    }

    var shouldShowManualTargetInputs: Bool {
        todayTargetSelection == .manual
    }

    var shouldShowTodayTargetGuideText: Bool {
        todayTargetSelection == .manual
    }

    var targetManualHoursBinding: Binding<String> {
        Binding(
            get: { self.targetInputHours },
            set: { self.updateTodayManualTargetHours($0) }
        )
    }

    var targetManualMinutesBinding: Binding<String> {
        Binding(
            get: { self.targetInputMinutes },
            set: { self.updateTodayManualTargetMinutes($0) }
        )
    }

    var canRestoreAutoSuggestedTarget: Bool {
        manualOverrideTargetMinutes != nil && autoSuggestedTargetMinutes != nil
    }

    private var todayTargetSelection: TodayTargetSelection {
        if isManualTargetSelectionActive {
            return .manual
        }

        if let manualOverrideTargetMinutes {
            return selection(for: manualOverrideTargetMinutes)
        }

        if todayTargetMode == .autoSuggested {
            return selection(for: targetWorkMinutes)
        }

        return selection(for: baseTargetWorkMinutes)
    }

    func syncFlexClockIn(_ date: Date, now: Date = Date()) {
        guard calendar.isDate(date, inSameDayAs: now), date <= now else { return }
        currentTime = now
        handleDayChangeIfNeeded(for: now)
        startTime = constrainedStart(date)
        isStartTimeUnset = false
        isEndTimeUnset = false
        isStartTimeFromFlex = true
        lastEditedField = .startTime
        alignTimesUsingLastEditedField()
        persistTodayState()
    }

    func clearFlexClockInSource() {
        isStartTimeFromFlex = false
        persistTodayState()
    }

    func updateStartTime(_ newValue: Date) {
        if constrainedStart(newValue) != startTime { isStartTimeFromFlex = false }
        lastEditedField = .startTime
        isStartTimeUnset = false
        isEndTimeUnset = false
        startTime = constrainedStart(newValue)
        if isManualTargetSelectionActive {
            syncManualTargetFromTimes()
        } else {
            alignTimesUsingLastEditedField()
        }
        persistTodayState()
    }

    func updateEndTime(_ newValue: Date) {
        let previousStart = startTime
        lastEditedField = .endTime
        isStartTimeUnset = false
        isEndTimeUnset = false
        endTime = constrainedEnd(newValue)
        if isManualTargetSelectionActive {
            syncManualTargetFromTimes()
        } else {
            alignTimesUsingLastEditedField()
        }
        if startTime != previousStart { isStartTimeFromFlex = false }
        persistTodayState()
    }

    func updatePresetTargetHours(_ hours: Int) {
        if isStartTimeUnset || isEndTimeUnset {
            reactivateTodayInputs()
        }
        baseTargetWorkMinutes = hours * 60
        isManualTargetSelectionActive = false
        if autoSuggestedTargetMinutes != nil {
            manualOverrideTargetMinutes = baseTargetWorkMinutes
        } else {
            manualOverrideTargetMinutes = nil
        }
        refreshTodayTargetFromCurrentContext(syncInputFields: true)
        persistTodayState()
    }

    func updateTodayTargetSelection(_ selection: TodayTargetSelection) {
        switch selection {
        case .manual:
            isManualTargetSelectionActive = true
            if manualOverrideTargetMinutes == nil {
                manualOverrideTargetMinutes = targetWorkMinutes
            }
            refreshTodayTargetFromCurrentContext(syncInputFields: true)
        case .sixHours, .sevenHours, .eightHours, .nineHours:
            guard let presetMinutes = selection.presetMinutes else {
                return
            }
            if isStartTimeUnset || isEndTimeUnset {
                reactivateTodayInputs()
            }
            baseTargetWorkMinutes = presetMinutes
            isManualTargetSelectionActive = false
            if autoSuggestedTargetMinutes != nil {
                manualOverrideTargetMinutes = baseTargetWorkMinutes
            } else {
                manualOverrideTargetMinutes = nil
            }
            refreshTodayTargetFromCurrentContext(syncInputFields: true)
        }
        persistTodayState()
    }

    func resetTodayState() {
        let now = currentTime
        isStartTimeFromFlex = false
        baseTargetWorkMinutes = 8 * 60
        let defaultStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        startTime = defaultStart
        endTime = addingMinutes(baseTargetWorkMinutes + fixedBreakMinutes, to: defaultStart)
        isStartTimeUnset = true
        isEndTimeUnset = true
        lastEditedField = .startTime
        manualOverrideTargetMinutes = nil
        isManualTargetSelectionActive = false
        setMenuBarDisplayMode(nil)
        refreshTodayTargetFromCurrentContext(syncInputFields: true)
        persistTodayState()
    }

    func activateStartTimeSelection() {
        reactivateTodayInputs()
        lastEditedField = .startTime
        alignTimesUsingLastEditedField()
        persistTodayState()
    }

    func activateEndTimeSelection() {
        reactivateTodayInputs()
        lastEditedField = .endTime
        alignTimesUsingLastEditedField()
        persistTodayState()
    }

    func restoreAutoSuggestedTarget() {
        guard autoSuggestedTargetMinutes != nil else {
            return
        }
        manualOverrideTargetMinutes = nil
        isManualTargetSelectionActive = false
        refreshTodayTargetFromCurrentContext(syncInputFields: true)
        persistTodayState()
    }

    func resetWeeklyState() {
        defaults.set(flexWeekStart(for: currentTime), forKey: "flex.weekStart")
        defaults.removeObject(forKey: "flex.accountID")
        weeklyData = defaultWeekData()
        autoFillTarget = nil
        excludedAutoFillIndexes = []
        refreshTodayTargetFromCurrentContext(syncInputFields: manualOverrideTargetMinutes == nil)
        persistWeeklyState()
    }

    func updateTodayManualTargetHours(_ value: String) {
        isManualTargetSelectionActive = true
        targetInputHours = sanitizeTodayHourString(value)
        applyTodayManualTargetFromInputs()
    }

    func updateTodayManualTargetMinutes(_ value: String) {
        isManualTargetSelectionActive = true
        targetInputMinutes = sanitizeTodayMinuteString(value)
        applyTodayManualTargetFromInputs()
    }

    func weeklyDay(at idx: Int) -> DayWorkData {
        weeklyData[idx]
    }

    func weeklyDayRecognizedText(at idx: Int) -> String {
        formatMinutesToKorean(getDailyMinutes(weeklyData[idx]))
    }

    func toggleWeeklyConfirmation(idx: Int) {
        guard weeklyData[idx].isConfirmed || isCompleteWeeklyDay(weeklyData[idx]) else { return }
        var data = weeklyData
        data[idx].isConfirmed.toggle()
        data[idx].isFlexAutoLocked = false
        let preferred = autoFillTarget?.idx == idx && data[idx].isConfirmed ? nil : autoFillTarget
        let result = applyAutoFill(data: data, preferredTarget: preferred,
                                  excludedIndexes: excludedAutoFillIndexes, allowPreferredOverride: true)
        commitWeeklyState(data: result.nextData, target: result.nextTarget, excludedIndexes: excludedAutoFillIndexes)
    }

    func canConfirmWeeklyDay(at index: Int) -> Bool {
        weeklyData[index].isConfirmed || isCompleteWeeklyDay(weeklyData[index])
    }

    func toggleWeeklyLock(idx: Int, field: AutoFillType) {
        if field == .manual {
            guard weeklyData[idx].mode == .manual else { return }
            toggleWeeklyConfirmation(idx: idx)
            return
        }
        guard !weeklyData[idx].isConfirmed else { return }
        var data = weeklyData
        switch field {
        case .start: guard !data[idx].start.isEmpty else { return }; data[idx].lockStart.toggle()
        case .end: guard !data[idx].end.isEmpty else { return }; data[idx].lockEnd.toggle()
        case .manual: guard !data[idx].manualHours.isEmpty || !data[idx].manualMinutes.isEmpty else { return }; data[idx].lockManual.toggle()
        }
        var preferred = autoFillTarget == AutoFillTarget(idx: idx, type: field) && data[idx].isLocked(field) ? nil : autoFillTarget
        var excluded = excludedAutoFillIndexes
        // Pinning one endpoint makes the unlocked endpoint the calculation target.
        if field != .manual, data[idx].isLocked(field), autoFillTarget == nil || autoFillTarget?.idx == idx {
            let opposite: AutoFillType = field == .start ? .end : .start
            if !data[idx].isLocked(opposite) {
                preferred = AutoFillTarget(idx: idx, type: opposite)
                excluded.removeAll { $0 == idx }
            }
        }
        let result = applyAutoFill(data: data, preferredTarget: preferred,
                                  excludedIndexes: excluded, allowPreferredOverride: true)
        commitWeeklyState(data: result.nextData, target: result.nextTarget, excludedIndexes: excluded)
    }

    func updateWeeklyLeaveType(idx: Int, leaveType: LeaveType) {
        handleWeeklyUpdate(idx: idx) { day in
            day.leaveType = leaveType
        }
    }

    func toggleWeeklyMode(idx: Int) {
        handleWeeklyUpdate(idx: idx) { day in
            day.mode = day.mode == .range ? .manual : .range
        }
    }

    func updateWeeklyStart(idx: Int, value: String) {
        updateWeeklyInput(idx: idx, field: .start) { day in
            day.start = value.isEmpty ? "" : minutesToTime(max(earliestStartMinutes, timeToMinutes(sanitizeTimeString(value))))
        }
    }

    func updateWeeklyEnd(idx: Int, value: String) {
        updateWeeklyInput(idx: idx, field: .end) { day in
            day.end = sanitizeTimeString(value)
        }
    }

    func updateWeeklyManualHours(idx: Int, value: String) {
        updateWeeklyInput(idx: idx, field: .manual) { $0.manualHours = sanitizeNumberString(value) }
    }

    func updateWeeklyManualMinutes(idx: Int, value: String) {
        updateWeeklyInput(idx: idx, field: .manual) { $0.manualMinutes = sanitizeNumberString(value) }
    }

    private func updateWeeklyInput(idx: Int, field: AutoFillType, mutation: (inout DayWorkData) -> Void) {
        guard !weeklyData[idx].isLocked(field) else { return }
        var data = weeklyData
        mutation(&data[idx])
        data[idx].importedFromFlex = false
        var excluded = excludedAutoFillIndexes.filter { $0 != idx }
        var preferred = autoFillTarget
        // Editing an automatically calculated field explicitly makes it manual.
        if preferred == AutoFillTarget(idx: idx, type: field) {
            preferred = nil
            excluded.append(idx)
        }
        let result = applyAutoFill(data: data, preferredTarget: preferred,
                                   excludedIndexes: excluded, allowPreferredOverride: true)
        commitWeeklyState(data: result.nextData, target: result.nextTarget, excludedIndexes: excluded)
    }

    func resetWeeklyDay(idx: Int) {
        guard !weeklyData[idx].isConfirmed && !weeklyData[idx].lockStart && !weeklyData[idx].lockEnd && !weeklyData[idx].lockManual else { return }
        var newData = weeklyData
        newData[idx].start = ""
        newData[idx].end = ""
        newData[idx].manualHours = ""
        newData[idx].manualMinutes = ""
        newData[idx].leaveType = .none
        newData[idx].importedFromFlex = false
        newData[idx].lockStart = false
        newData[idx].lockEnd = false
        newData[idx].lockManual = false

        let nextExcluded = Array(Set(excludedAutoFillIndexes + [idx])).sorted()
        let preferred = autoFillTarget?.idx == idx ? nil : autoFillTarget
        let result = applyAutoFill(data: newData, preferredTarget: preferred,
                                   excludedIndexes: nextExcluded, allowPreferredOverride: true)
        commitWeeklyState(data: result.nextData, target: result.nextTarget, excludedIndexes: nextExcluded)
    }

    func fitWeeklyDayToEightHours(idx: Int) {
        let data = weeklyData[idx]
        guard data.mode == .range, data.leaveType != .annual, !data.isConfirmed, !data.lockStart, !data.lockEnd else {
            return
        }

        let neededWorkMinutes = max(0, 8 * 60 - getLeaveCreditMinutes(data))
        var newData = weeklyData
        newData[idx].importedFromFlex = false

        if !data.start.isEmpty {
            newData[idx].end = minutesToTime(
                calculateReverseTime(
                    baseTimeMinutes: timeToMinutes(data.start),
                    targetMinutes: neededWorkMinutes,
                    type: .end
                )
            )
        } else if !data.end.isEmpty {
            newData[idx].start = minutesToTime(
                calculateReverseTime(
                    baseTimeMinutes: timeToMinutes(data.end),
                    targetMinutes: neededWorkMinutes,
                    type: .start
                )
            )
        }

        let result = applyAutoFill(
            data: newData,
            preferredTarget: autoFillTarget,
            excludedIndexes: excludedAutoFillIndexes,
            allowPreferredOverride: false
        )
        commitWeeklyState(data: result.nextData, target: result.nextTarget, excludedIndexes: excludedAutoFillIndexes)
    }

    private func updateMenuBarMetric(_ metric: MenuBarMetric) {
        if isStartTimeUnset || isEndTimeUnset {
            reactivateTodayInputs()
        }
        setMenuBarDisplayMode(MenuBarDisplayMode(metric: metric))
    }

    private func setMenuBarDisplayMode(_ mode: MenuBarDisplayMode?) {
        menuBarDisplayMode = mode
        let encoder = JSONEncoder()
        if let mode, let data = try? encoder.encode(mode) {
            defaults.set(data, forKey: Keys.menuBarDisplayMode)
        } else {
            defaults.removeObject(forKey: Keys.menuBarDisplayMode)
        }
    }

    private func reactivateTodayInputs() {
        isStartTimeUnset = false
        isEndTimeUnset = false
        alignTimesUsingLastEditedField()
        setMenuBarDisplayMode(MenuBarDisplayMode(metric: .untilDeparture))
    }

    private func shouldResetForNewDay(referenceDate: Date) -> Bool {
        guard let savedDayStart = defaults.object(forKey: Keys.lastActiveDayStart) as? Date else {
            return false
        }
        return !calendar.isDate(savedDayStart, inSameDayAs: referenceDate)
    }

    private func resetTodayForNewDay(referenceDate: Date) {
        isStartTimeFromFlex = false
        trackedDayStart = calendar.startOfDay(for: referenceDate)
        let defaultStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: referenceDate) ?? referenceDate
        startTime = defaultStart
        endTime = addingMinutes(baseTargetWorkMinutes + fixedBreakMinutes, to: defaultStart)
        isStartTimeUnset = true
        isEndTimeUnset = true
        lastEditedField = .startTime
        manualOverrideTargetMinutes = nil
        isManualTargetSelectionActive = false
        setMenuBarDisplayMode(nil)
        defaults.set(trackedDayStart, forKey: Keys.lastActiveDayStart)
        refreshTodayTargetFromCurrentContext(syncInputFields: true)
        persistTodayState()
    }

    private func handleDayChangeIfNeeded(for now: Date) {
        if !calendar.isDate(trackedDayStart, inSameDayAs: now) {
            resetTodayForNewDay(referenceDate: now)
        }
    }

    private func constrainedStart(_ date: Date) -> Date {
        let earliest = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date
        return max(date, earliest)
    }

    private func constrainedEnd(_ date: Date) -> Date {
        guard appliesCoreTime else { return date }
        let earliest = calendar.date(bySettingHour: 15, minute: 30, second: 0, of: date) ?? date
        return max(date, earliest)
    }

    private func syncManualTargetFromTimes() {
        let minutes = max(0, Int(endTime.timeIntervalSince(startTime) / 60)
            - overlapMinutes(firstStart: startTime, firstEnd: endTime,
                             secondStart: fixedBreakStart, secondEnd: fixedBreakEnd))
        manualOverrideTargetMinutes = minutes
        targetWorkMinutes = minutes
        todayTargetMode = .manualOverride
        syncTodayTargetInputs(with: minutes)
    }

    private func alignTimesUsingLastEditedField() {
        startTime = constrainedStart(startTime)
        switch lastEditedField {
        case .startTime:
            let minutes = calendar.component(.hour, from: startTime) * 60 + calendar.component(.minute, from: startTime)
            let result = calculateReverseTime(baseTimeMinutes: minutes, targetMinutes: targetWorkMinutes, type: .end)
            endTime = constrainedEnd(addingMinutes(result - minutes, to: startTime))
        case .endTime:
            endTime = constrainedEnd(endTime)
            let minutes = calendar.component(.hour, from: endTime) * 60 + calendar.component(.minute, from: endTime)
            var result = calculateReverseTime(baseTimeMinutes: minutes, targetMinutes: targetWorkMinutes, type: .start)
            if appliesCoreTime { result = min(result, 10 * 60 + 30) }
            if result < earliestStartMinutes {
                startTime = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: endTime) ?? endTime
                let endMinutes = calculateReverseTime(baseTimeMinutes: earliestStartMinutes, targetMinutes: targetWorkMinutes, type: .end)
                endTime = constrainedEnd(addingMinutes(endMinutes - earliestStartMinutes, to: startTime))
            } else {
                startTime = addingMinutes(result - minutes, to: endTime)
            }
        }
    }

    private func addingMinutes(_ minutes: Int, to date: Date) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: date) ?? date
    }

    private var workedMinutesToday: Int {
        if isStartTimeUnset || isEndTimeUnset || currentTime <= startTime {
            return 0
        }

        let effectiveEnd = currentTime
        let rawWorked = max(0, Int(effectiveEnd.timeIntervalSince(startTime) / 60))
        let breakOverlap = overlapMinutes(
            firstStart: startTime,
            firstEnd: effectiveEnd,
            secondStart: fixedBreakStart,
            secondEnd: fixedBreakEnd
        )
        return max(0, rawWorked - breakOverlap)
    }

    private var recognizedWorkedMinutesToday: Int {
        min(workedMinutesToday, maxDailyMinutes)
    }

    private var remainingWorkMinutesToday: Int {
        targetWorkMinutes - workedMinutesToday
    }

    private var weeklyWorkedMinutes: Int {
        weeklyData.reduce(0) { $0 + getDailyMinutes($1) }
    }

    private var weeklyRemainingMinutes: Int {
        max(0, weeklyGoalMinutes - weeklyWorkedMinutes)
    }

    private var fixedBreakStart: Date {
        calendar.date(bySettingHour: 12, minute: 30, second: 0, of: startTime) ?? startTime
    }

    private var fixedBreakEnd: Date {
        calendar.date(bySettingHour: 13, minute: 30, second: 0, of: startTime) ?? startTime
    }

    private func overlapMinutes(firstStart: Date, firstEnd: Date, secondStart: Date, secondEnd: Date) -> Int {
        let overlapStart = max(firstStart, secondStart)
        let overlapEnd = min(firstEnd, secondEnd)
        guard overlapEnd > overlapStart else { return 0 }
        return Int(overlapEnd.timeIntervalSince(overlapStart) / 60)
    }

    private func signedCompactDuration(_ minutes: Int) -> String {
        (minutes < 0 ? "+" : "") + compactDuration(abs(minutes))
    }

    private func compactDuration(_ totalMinutes: Int) -> String {
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h \(minutes)m"
    }

    private func formattedClock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter.string(from: date)
    }

    private func startTimer() {
        timerCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                self?.currentTime = now
                self?.handleDayChangeIfNeeded(for: now)
            }
    }

    private func persistTodayState() {
        defaults.set(startTime, forKey: Keys.startTime)
        defaults.set(isStartTimeFromFlex, forKey: Keys.isStartTimeFromFlex)
        defaults.set(endTime, forKey: Keys.endTime)
        defaults.set(targetWorkMinutes, forKey: Keys.targetWorkMinutes)
        defaults.set(baseTargetWorkMinutes, forKey: Keys.baseTargetWorkMinutes)
        if let manualOverrideTargetMinutes {
            defaults.set(manualOverrideTargetMinutes, forKey: Keys.manualOverrideTargetMinutes)
        } else {
            defaults.removeObject(forKey: Keys.manualOverrideTargetMinutes)
        }
        defaults.set(isManualTargetSelectionActive, forKey: Keys.isManualTargetSelectionActive)
        defaults.set(isStartTimeUnset, forKey: Keys.isStartTimeUnset)
        defaults.set(isEndTimeUnset, forKey: Keys.isEndTimeUnset)
        defaults.set(calendar.startOfDay(for: currentTime), forKey: Keys.lastActiveDayStart)
    }

    private func persistWeeklyState() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(weeklyData) {
            defaults.set(data, forKey: Keys.weeklyData)
        }
        if let target = autoFillTarget, let data = try? encoder.encode(target) {
            defaults.set(data, forKey: Keys.autoFillTarget)
        } else {
            defaults.removeObject(forKey: Keys.autoFillTarget)
        }
        defaults.set(excludedAutoFillIndexes, forKey: Keys.excludedAutoFillIndexes)
    }

    private static func loadMenuBarDisplayMode(from defaults: UserDefaults) -> MenuBarDisplayMode? {
        guard let data = defaults.data(forKey: Keys.menuBarDisplayMode) else {
            return nil
        }
        guard let decoded = try? JSONDecoder().decode(MenuBarDisplayMode.self, from: data) else {
            return nil
        }
        return MenuBarDisplayMode(metric: decoded.metric)
    }

    private static func loadWeeklyData(from defaults: UserDefaults) -> [DayWorkData] {
        guard let data = defaults.data(forKey: Keys.weeklyData),
              let decoded = try? JSONDecoder().decode([DayWorkData].self, from: data),
              decoded.count == weekDays.count else {
            return defaultWeekData()
        }
        return decoded
    }

    private static func loadAutoFillTarget(from defaults: UserDefaults) -> AutoFillTarget? {
        guard let data = defaults.data(forKey: Keys.autoFillTarget) else {
            return nil
        }
        return try? JSONDecoder().decode(AutoFillTarget.self, from: data)
    }

    private func handleWeeklyUpdate(
        idx: Int,
        mutation: (inout DayWorkData) -> Void
    ) {
        guard !weeklyData[idx].isConfirmed && !weeklyData[idx].lockStart && !weeklyData[idx].lockEnd && !weeklyData[idx].lockManual else { return }
        var newData = weeklyData
        if let target = autoFillTarget, target.idx == idx {
            switch target.type {
            case .manual: newData[idx].manualHours = ""; newData[idx].manualMinutes = ""
            case .start: newData[idx].start = ""
            case .end: newData[idx].end = ""
            }
        }
        mutation(&newData[idx])
        newData[idx].importedFromFlex = false

        let nextExcluded = excludedAutoFillIndexes
        let preferredTarget = autoFillTarget?.idx == idx ? nil : autoFillTarget
        let shouldKeepPreferredTarget = preferredTarget != nil
        let result = applyAutoFill(
            data: newData,
            preferredTarget: preferredTarget,
            excludedIndexes: nextExcluded,
            allowPreferredOverride: shouldKeepPreferredTarget
        )
        commitWeeklyState(data: result.nextData, target: result.nextTarget, excludedIndexes: nextExcluded)
    }

    private func flexWeekStart(for date: Date) -> Date {
        let today = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: today) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: today)!
    }

    func importFlexRecords(_ records: [FlexWorkRecord], now: Date = Date(), automatic: Bool = false) -> String {
        let week = flexWeekStart(for: now)
        func hasInput(_ day: DayWorkData) -> Bool {
            !day.start.isEmpty || !day.end.isEmpty || !day.manualHours.isEmpty ||
            !day.manualMinutes.isEmpty || day.leaveType != .none || day.isConfirmed ||
            day.lockStart || day.lockEnd || day.lockManual
        }
        let accounts = Set(records.compactMap(\.accountID))
        guard accounts.count <= 1 else { return "서로 다른 flex 계정의 기록입니다." }
        let occupied = weeklyData.filter(hasInput)
        let hasExisting = !occupied.isEmpty
        let savedWeek = defaults.object(forKey: "flex.weekStart") as? Date
        let canStartNewWeek = automatic && (savedWeek.map { $0 < week } ?? false) &&
            occupied.allSatisfy {
                $0.importedFromFlex && (!$0.isConfirmed || $0.isFlexAutoLocked) &&
                    !$0.lockStart && !$0.lockEnd && !$0.lockManual
            } &&
            accounts.first != nil && accounts.first == defaults.string(forKey: "flex.accountID")
        guard !hasExisting || savedWeek == nil || savedWeek == week || canStartNewWeek else {
            return "기존 기록의 주차를 확인해주세요. 주간 Reset 후 이번 주 기록을 가져올 수 있어요."
        }
        if let saved = defaults.string(forKey: "flex.accountID"),
           let incoming = accounts.first, hasExisting, saved != incoming {
            return "다른 flex 계정의 기록이 있습니다. 주간 Reset 후 다시 가져와주세요."
        }
        var data = canStartNewWeek ? defaultWeekData() : weeklyData
        var count = 0
        // Reject duplicate dates rather than picking an arbitrary record.
        let grouped = Dictionary(grouping: records, by: { calendar.startOfDay(for: $0.date) })
        for (_, values) in grouped {
            guard values.count == 1, let record = values.first,
                  (0...24 * 60).contains(record.minutes),
                  let index = FlexImportScope.index(for: record.date, now: now, calendar: calendar, includeToday: automatic) else { continue }
            let day = data[index]
            guard !day.isConfirmed || day.isFlexAutoLocked else { continue }
            guard !day.lockStart, !day.lockEnd, !day.lockManual,
                  day.leaveType == .none else { continue }
            let hours = String(record.minutes / 60)
            let minutes = String(record.minutes % 60)
            if day.importedFromFlex, day.mode == .manual,
               day.manualHours == hours, day.manualMinutes == minutes,
               day.start.isEmpty, day.end.isEmpty, day.isFlexAutoLocked { continue }
            data[index].mode = .manual
            data[index].start = ""
            data[index].end = ""
            data[index].manualHours = hours
            data[index].manualMinutes = minutes
            data[index].isConfirmed = true
            data[index].isFlexAutoLocked = true
            data[index].importedFromFlex = true
            count += 1
        }
        guard count > 0 else { return "변경할 기록이 없어요. 잠금·고정·휴가가 있는 날짜는 건너뛰어요." }
        defaults.set(week, forKey: "flex.weekStart")
        if let account = accounts.first { defaults.set(account, forKey: "flex.accountID") }
        let excluded = canStartNewWeek ? [] : excludedAutoFillIndexes
        let target = (canStartNewWeek ? nil : autoFillTarget).flatMap {
            isValidAutoFillTarget(data: data, target: $0) ? $0 : nil
        }
        let result = applyAutoFill(data: data, preferredTarget: target,
                                   excludedIndexes: excluded, allowPreferredOverride: true)
        commitWeeklyState(data: result.nextData, target: result.nextTarget, excludedIndexes: excluded)
        let skipped = records.count - count
        return skipped == 0 ? "이번 주 flex 기록 \(count)일을 반영했어요." :
            "이번 주 flex 기록 \(count)일을 반영했어요. 변경이 없거나 잠금·고정·휴가 등이 있는 \(skipped)일은 건너뛰었어요."
    }

    private func commitWeeklyState(data: [DayWorkData], target: AutoFillTarget?, excludedIndexes: [Int]) {
        weeklyData = data
        autoFillTarget = target
        excludedAutoFillIndexes = excludedIndexes
        refreshTodayTargetFromCurrentContext(syncInputFields: manualOverrideTargetMinutes == nil)
        persistWeeklyState()
    }

    private func isValidAutoFillTarget(data: [DayWorkData], target: AutoFillTarget?) -> Bool {
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

    private func isSameAutoFillTarget(_ lhs: AutoFillTarget?, _ rhs: AutoFillTarget?) -> Bool {
        lhs == rhs
    }

    private func autoFillCandidates(data: [DayWorkData], excludedIndexes: [Int] = []) -> [AutoFillTarget] {
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

    private func inferAutoFillTarget(data: [DayWorkData], excludedIndexes: [Int] = []) -> AutoFillTarget? {
        let candidates = autoFillCandidates(data: data, excludedIndexes: excludedIndexes)
        return candidates.count == 1 ? candidates[0] : nil
    }

    private func applyAutoFill(
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
           (allowPreferredOverride || isSameAutoFillTarget(preferredTarget, inferredTarget)) {
            resolvedTarget = preferredTarget
        } else {
            resolvedTarget = inferredTarget
        }

        guard let resolvedTarget else {
            return (data, nil)
        }
        guard data.enumerated().allSatisfy({ index, day in
            index == resolvedTarget.idx || isCompleteWeeklyDay(day)
        }) else {
            var pendingData = data
            switch resolvedTarget.type {
            case .manual: pendingData[resolvedTarget.idx].manualHours = ""; pendingData[resolvedTarget.idx].manualMinutes = ""
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
            var start = calculateReverseTime(baseTimeMinutes: timeToMinutes(day.end), targetMinutes: targetWorkMinutes, type: .start)
            if day.leaveType == .none { start = min(start, 10 * 60 + 30) }
            nextData[resolvedTarget.idx].start = minutesToTime(max(earliestStartMinutes, start))
        }
        return (nextData, resolvedTarget)
    }

    private enum TodayAutoSuggestionState {
        case unavailable
        case blocked(String)
        case suggested(Int)
    }

    private func applyTodayManualTargetFromInputs() {
        if isStartTimeUnset || isEndTimeUnset {
            reactivateTodayInputs()
        }

        guard let manualMinutes = parsedTodayManualTargetMinutes else {
            manualOverrideTargetMinutes = nil
            refreshTodayTargetFromCurrentContext(syncInputFields: false)
            persistTodayState()
            return
        }

        manualOverrideTargetMinutes = manualMinutes
        lastEditedField = .startTime
        refreshTodayTargetFromCurrentContext(syncInputFields: false)
        alignTimesUsingLastEditedField()
        persistTodayState()
    }

    private var parsedTodayManualTargetMinutes: Int? {
        let hoursText = targetInputHours.trimmingCharacters(in: .whitespacesAndNewlines)
        let minutesText = targetInputMinutes.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !hoursText.isEmpty || !minutesText.isEmpty else {
            return nil
        }

        let hours = Int(hoursText) ?? 0
        let minutes = min(59, Int(minutesText) ?? 0)
        return max(0, hours * 60 + minutes)
    }

    private func refreshTodayTargetFromCurrentContext(syncInputFields: Bool) {
        let autoSuggestionState = resolveTodayAutoSuggestionState()

        switch autoSuggestionState {
        case .suggested(let minutes):
            autoSuggestedTargetMinutes = minutes
        case .blocked, .unavailable:
            autoSuggestedTargetMinutes = nil
        }

        if let manualOverrideTargetMinutes {
            todayTargetMode = .manualOverride
            targetWorkMinutes = manualOverrideTargetMinutes
        } else if let autoSuggestedTargetMinutes {
            todayTargetMode = .autoSuggested
            targetWorkMinutes = autoSuggestedTargetMinutes
        } else {
            todayTargetMode = .preset
            targetWorkMinutes = baseTargetWorkMinutes
        }

        todayTargetGuideText = resolveTodayTargetGuideText(autoSuggestionState: autoSuggestionState)
        if isStartTimeFromFlex {
            lastEditedField = .startTime
            alignTimesUsingLastEditedField()
        } else if !isManualTargetSelectionActive {
            alignTimesUsingLastEditedField()
        } else {
            startTime = constrainedStart(startTime)
            endTime = constrainedEnd(endTime)
        }

        if syncInputFields {
            syncTodayTargetInputs(with: targetWorkMinutes)
        }
    }

    private func resolveTodayTargetGuideText(autoSuggestionState: TodayAutoSuggestionState) -> String? {
        switch todayTargetMode {
        case .manualOverride:
            if autoSuggestedTargetMinutes != nil {
                return "[자동계산] 버튼을 눌러 남은 근무시간을 자동으로 입력할 수 있습니다."
            }
            return nil
        case .autoSuggested:
            return "이번 주 남은 근무시간은 \(formatMinutesToKorean(targetWorkMinutes)) 입니다 😎"
        case .preset:
            return nil
        }
    }

    private func resolveTodayAutoSuggestionState() -> TodayAutoSuggestionState {
        guard let todayIndex = currentWeekdayIndex else {
            return .unavailable
        }

        guard lastActualWorkingDayIndex == todayIndex else {
            return .unavailable
        }

        guard let validationMessage = weeklyAutoSuggestionBlockingMessage(excluding: todayIndex) else {
            return suggestedTargetMinutes(for: todayIndex).map(TodayAutoSuggestionState.suggested) ?? .unavailable
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

        let hasExceededDailyCapacity = remainingRecognizedMinutes > getLeaveCreditMinutes(todayData) + getMaxWorkMinutesForDay(todayData)
        if hasExceededDailyCapacity || suggestedMinutes <= 0 {
            return nil
        }

        return suggestedMinutes
    }

    private func syncTodayTargetInputs(with minutes: Int) {
        targetInputHours = String(minutes / 60)
        targetInputMinutes = String(format: "%02d", minutes % 60)
    }

    private func sanitizeTimeString(_ value: String) -> String {
        String(value.prefix(5))
    }

    private func sanitizeNumberString(_ value: String) -> String {
        String(value.filter(\.isNumber))
    }

    private func sanitizeTodayHourString(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(2))
    }

    private func sanitizeTodayMinuteString(_ value: String) -> String {
        let filtered = String(value.filter(\.isNumber).prefix(2))
        guard let minutes = Int(filtered) else {
            return filtered
        }
        return String(format: "%02d", min(59, minutes))
    }

    private func selection(for minutes: Int) -> TodayTargetSelection {
        switch minutes {
        case 6 * 60:
            return .sixHours
        case 7 * 60:
            return .sevenHours
        case 8 * 60:
            return .eightHours
        case 9 * 60:
            return .nineHours
        default:
            return .manual
        }
    }
}
