import Combine
import Foundation
import SwiftUI

@MainActor
final class TimeCalculatorViewModel: ObservableObject {
    @Published private(set) var recordedWeekStart: Date?
    @Published private(set) var previousWeek: WeeklyArchive?
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

    private let store: WorkStateStore
    private let calendar: Calendar
    private let fixedBreakMinutes = 60
    private var timerCancellable: AnyCancellable?
    private var trackedDayStart: Date
    private var autoFillTarget: AutoFillTarget?
    private var excludedAutoFillIndexes: [Int]
    private var manualOverrideTargetMinutes: Int?
    private var autoSuggestedTargetMinutes: Int?
    private var isManualTargetSelectionActive: Bool

    private var lastEditedField: TodayWorkCalculator.EditedField {
        didSet { store.saveLastEditedField(lastEditedField) }
    }

    init(defaults: UserDefaults = .standard, now: Date = Date(), calendar: Calendar = .current) {
        let store = WorkStateStore(defaults: defaults)
        self.store = store
        self.calendar = calendar
        let saved = store.load(now: now, calendar: calendar)
        let today = saved.today
        let hasRecords = saved.weeklyData.contains {
            !$0.start.isEmpty || !$0.end.isEmpty || !$0.manualHours.isEmpty || !$0.manualMinutes.isEmpty
                || $0.leaveType != .none || $0.isConfirmed
        }
        recordedWeekStart = store.recordedWeekStart ?? store.flexWeekStart
            ?? (hasRecords ? nil : WorkWeek.start(for: now, calendar: calendar))
        previousWeek = store.weeklyArchive
        currentTime = now
        trackedDayStart = today.dayStart
        lastEditedField = saved.lastEditedField
        targetWorkMinutes = today.targetWorkMinutes
        baseTargetWorkMinutes = today.baseTargetWorkMinutes
        startTime = today.startTime
        endTime = today.endTime
        isStartTimeFromFlex = today.isStartTimeFromFlex
        menuBarDisplayMode = saved.menuBarDisplayMode
        isStartTimeUnset = today.isStartTimeUnset
        isEndTimeUnset = today.isEndTimeUnset
        weeklyData = saved.weeklyData
        todayTargetMode = .preset
        targetInputHours = String(today.baseTargetWorkMinutes / 60)
        targetInputMinutes = String(format: "%02d", today.baseTargetWorkMinutes % 60)
        todayTargetGuideText = nil
        autoFillTarget = saved.autoFillTarget
        excludedAutoFillIndexes = saved.excludedAutoFillIndexes
        manualOverrideTargetMinutes = today.manualOverrideTargetMinutes
        isManualTargetSelectionActive = today.isManualTargetSelectionActive
        autoSuggestedTargetMinutes = nil
        store.recordedWeekStart = recordedWeekStart

        if let target = autoFillTarget, !WeeklyWorkCalculator.isValidAutoFillTarget(data: weeklyData, target: target) {
            autoFillTarget = nil
            store.clearAutoFillTarget()
        }

        if shouldResetForNewDay(referenceDate: now) {
            resetTodayForNewDay(referenceDate: now)
        } else {
            store.lastActiveDayStart = trackedDayStart
        }

        refreshTodayTargetFromCurrentContext(syncInputFields: true)
        startTimer()
    }

    var isCurrentWorkWeek: Bool {
        recordedWeekStart == WorkWeek.start(for: currentTime, calendar: calendar)
    }

    var weeklyDateRange: String {
        guard let start = recordedWeekStart else { return "주차 미확인" }
        return weekLabel(start)
    }

    private func weekLabel(_ start: Date) -> String {
        let end = calendar.date(byAdding: .day, value: 4, to: start)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy년 M월 d일"
        let first = formatter.string(from: start)
        formatter.dateFormat = calendar.component(.year, from: start) == calendar.component(.year, from: end)
            ? "M월 d일" : "yyyy년 M월 d일"
        return first + "~" + formatter.string(from: end)
    }

    func weeklyDayTitle(at index: Int) -> String {
        guard let start = recordedWeekStart,
              let date = calendar.date(byAdding: .day, value: index, to: start) else { return weekDays[index] }
        return weekDays[index] + " \(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))"
    }

    var weekChangeNotice: String? {
        guard !isCurrentWorkWeek else { return nil }
        return recordedWeekStart == nil
            ? "기존 기록의 주차를 확인할 수 없습니다. 오늘 목표 자동 계산에는 사용하지 않습니다."
            : "이전 주 기록이 남아 있습니다. 오늘 목표 자동 계산에는 사용하지 않습니다."
    }

    var previousWeekTitle: String {
        previousWeek?.weekStart.map(weekLabel) ?? "주차 미확인 기록"
    }

    func archiveAndStartCurrentWeek() {
        archiveCurrentWeek()
        resetWeeklyState()
    }

    private func archiveCurrentWeek() {
        guard weeklyData.contains(where: {
            !$0.start.isEmpty || !$0.end.isEmpty || !$0.manualHours.isEmpty || !$0.manualMinutes.isEmpty
                || $0.leaveType != .none || $0.isConfirmed
        }) else { return }
        let archive = WeeklyArchive(weekStart: recordedWeekStart, savedAt: currentTime,
            data: weeklyData, target: autoFillTarget, excludedIndexes: excludedAutoFillIndexes,
            flexAccountID: store.flexAccountID)
        store.weeklyArchive = archive
        previousWeek = archive
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
        if recordedWeekStart != nil && !isCurrentWorkWeek { return true }
        guard let index = currentWeekdayIndex else { return false }
        return weeklyData[index].leaveType == .none
    }

    func isWeeklyAutoCalculated(at index: Int) -> Bool {
        autoFillTarget?.idx == index
    }

    var weeklyCalculationNotice: String? {
        WeeklyWorkCalculator.notice(data: weeklyData, target: autoFillTarget)
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
        if menuBarDisplayMode == nil {
            setMenuBarDisplayMode(MenuBarDisplayMode(metric: .untilDeparture))
        }
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
        recordedWeekStart = WorkWeek.start(for: currentTime, calendar: calendar)
        store.recordedWeekStart = recordedWeekStart
        store.flexWeekStart = WorkWeek.start(for: currentTime, calendar: calendar)
        store.flexAccountID = nil
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
        guard weeklyData[idx].isConfirmed || WeeklyWorkCalculator.isCompleteWeeklyDay(weeklyData[idx]) else { return }
        var data = weeklyData
        data[idx].isConfirmed.toggle()
        data[idx].isFlexAutoLocked = false
        let preferred = autoFillTarget?.idx == idx && data[idx].isConfirmed ? nil : autoFillTarget
        let result = WeeklyWorkCalculator.applyAutoFill(data: data, preferredTarget: preferred,
                                  excludedIndexes: excludedAutoFillIndexes, allowPreferredOverride: true)
        commitWeeklyState(data: result.nextData, target: result.nextTarget, excludedIndexes: excludedAutoFillIndexes)
    }

    func canConfirmWeeklyDay(at index: Int) -> Bool {
        weeklyData[index].isConfirmed || WeeklyWorkCalculator.isCompleteWeeklyDay(weeklyData[index])
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
        let result = WeeklyWorkCalculator.applyAutoFill(data: data, preferredTarget: preferred,
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

    private func autoFillExclusionsAfterEditing(_ data: [DayWorkData], editedIndex: Int? = nil) -> [Int] {
        excludedAutoFillIndexes.filter { index in
            guard data.indices.contains(index), index != editedIndex else { return false }
            let day = data[index]
            // Reset suppresses immediate refilling, not future reverse calculations.
            // Keep exclusions for partially filled fields explicitly made manual.
            return !day.start.isEmpty || !day.end.isEmpty
                || !day.manualHours.isEmpty || !day.manualMinutes.isEmpty
        }
    }

    private func updateWeeklyInput(idx: Int, field: AutoFillType, mutation: (inout DayWorkData) -> Void) {
        guard !weeklyData[idx].isLocked(field) else { return }
        var data = weeklyData
        mutation(&data[idx])
        data[idx].importedFromFlex = false
        var excluded = autoFillExclusionsAfterEditing(data, editedIndex: idx)
        var preferred = autoFillTarget
        // Editing an automatically calculated field explicitly makes it manual.
        if preferred == AutoFillTarget(idx: idx, type: field) {
            preferred = nil
            excluded.append(idx)
        }
        let result = WeeklyWorkCalculator.applyAutoFill(data: data, preferredTarget: preferred,
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
        let result = WeeklyWorkCalculator.applyAutoFill(data: newData, preferredTarget: preferred,
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

        let result = WeeklyWorkCalculator.applyAutoFill(
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
        store.saveMenuBarMode(mode)
    }

    private func reactivateTodayInputs() {
        isStartTimeUnset = false
        isEndTimeUnset = false
        alignTimesUsingLastEditedField()
        setMenuBarDisplayMode(MenuBarDisplayMode(metric: .untilDeparture))
    }

    private func shouldResetForNewDay(referenceDate: Date) -> Bool {
        guard let savedDayStart = store.lastActiveDayStart else {
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
        store.lastActiveDayStart = trackedDayStart
        refreshTodayTargetFromCurrentContext(syncInputFields: true)
        persistTodayState()
    }

    private func handleDayChangeIfNeeded(for now: Date) {
        if !calendar.isDate(trackedDayStart, inSameDayAs: now) {
            resetTodayForNewDay(referenceDate: now)
        }
    }

    private var todayCalculator: TodayWorkCalculator { TodayWorkCalculator(calendar: calendar) }

    private func constrainedStart(_ date: Date) -> Date {
        todayCalculator.constrainedStart(date)
    }

    private func constrainedEnd(_ date: Date) -> Date {
        todayCalculator.constrainedEnd(date, appliesCoreTime: appliesCoreTime)
    }

    private func alignTimesUsingLastEditedField() {
        let times = todayCalculator.alignedTimes(start: startTime, end: endTime,
            targetWorkMinutes: targetWorkMinutes, lastEditedField: lastEditedField, appliesCoreTime: appliesCoreTime)
        startTime = times.start
        endTime = times.end
    }

    private func syncManualTargetFromTimes() {
        let minutes = todayCalculator.workMinutes(start: startTime, end: endTime)
        manualOverrideTargetMinutes = minutes
        targetWorkMinutes = minutes
        todayTargetMode = .manualOverride
        syncTodayTargetInputs(with: minutes)
    }

    private func addingMinutes(_ minutes: Int, to date: Date) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: date) ?? date
    }

    private var workedMinutesToday: Int {
        guard !isStartTimeUnset, !isEndTimeUnset, currentTime > startTime else { return 0 }
        return todayCalculator.workMinutes(start: startTime, end: currentTime)
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
        store.saveToday(.init(startTime: startTime, endTime: endTime,
            isStartTimeFromFlex: isStartTimeFromFlex, targetWorkMinutes: targetWorkMinutes,
            baseTargetWorkMinutes: baseTargetWorkMinutes, manualOverrideTargetMinutes: manualOverrideTargetMinutes,
            isManualTargetSelectionActive: isManualTargetSelectionActive,
            isStartTimeUnset: isStartTimeUnset, isEndTimeUnset: isEndTimeUnset,
            dayStart: calendar.startOfDay(for: currentTime)))
    }

    private func persistWeeklyState() {
        store.saveWeekly(data: weeklyData, target: autoFillTarget, excluded: excludedAutoFillIndexes)
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

        let nextExcluded = autoFillExclusionsAfterEditing(newData)
        let preferredTarget = autoFillTarget?.idx == idx ? nil : autoFillTarget
        let shouldKeepPreferredTarget = preferredTarget != nil
        let result = WeeklyWorkCalculator.applyAutoFill(
            data: newData,
            preferredTarget: preferredTarget,
            excludedIndexes: nextExcluded,
            allowPreferredOverride: shouldKeepPreferredTarget
        )
        commitWeeklyState(data: result.nextData, target: result.nextTarget, excludedIndexes: nextExcluded)
    }

    func importFlexRecords(_ records: [FlexWorkRecord], now: Date = Date(), automatic: Bool = false) -> String {
        let imported = FlexImportPolicy.apply(records, to: weeklyData,
            savedWeek: store.recordedWeekStart ?? store.flexWeekStart, savedAccount: store.flexAccountID,
            now: now, automatic: automatic, calendar: calendar)
        switch imported {
        case .unchanged(let message):
            return message
        case let .applied(data, week, account, startsNewWeek, message):
            if startsNewWeek { archiveCurrentWeek() }
            recordedWeekStart = week
            store.recordedWeekStart = week
            store.flexWeekStart = week
            if let account { store.flexAccountID = account }
            let excluded = startsNewWeek ? [] : excludedAutoFillIndexes
            let target = (startsNewWeek ? nil : autoFillTarget).flatMap {
                WeeklyWorkCalculator.isValidAutoFillTarget(data: data, target: $0) ? $0 : nil
            }
            let result = WeeklyWorkCalculator.applyAutoFill(data: data, preferredTarget: target,
                excludedIndexes: excluded, allowPreferredOverride: true)
            commitWeeklyState(data: result.nextData, target: result.nextTarget, excludedIndexes: excluded)
            return message
        }
    }

    private func commitWeeklyState(data: [DayWorkData], target: AutoFillTarget?, excludedIndexes: [Int]) {
        weeklyData = data
        autoFillTarget = target
        excludedAutoFillIndexes = excludedIndexes
        refreshTodayTargetFromCurrentContext(syncInputFields: manualOverrideTargetMinutes == nil)
        persistWeeklyState()
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
        let autoSuggestionState: TodayTargetSuggestion.State = isCurrentWorkWeek
            ? TodayTargetSuggestion(weeklyData: weeklyData, currentTime: currentTime, calendar: calendar).resolve()
            : .unavailable

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

    private func resolveTodayTargetGuideText(autoSuggestionState: TodayTargetSuggestion.State) -> String? {
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

    private var currentWeekdayIndex: Int? {
        let weekday = calendar.component(.weekday, from: currentTime)
        switch weekday {
        case 2...6:
            return weekday - 2
        default:
            return nil
        }
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
