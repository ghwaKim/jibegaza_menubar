import Combine
import Foundation
import SwiftUI

@MainActor
final class TimeCalculatorViewModel: ObservableObject {
    @Published var selectedTab: WorkTab = .today
    @Published private(set) var startTime: Date
    @Published private(set) var endTime: Date
    @Published private(set) var targetWorkMinutes: Int
    @Published private(set) var menuBarDisplayMode: MenuBarDisplayMode?
    @Published private(set) var isStartTimeUnset: Bool
    @Published private(set) var isEndTimeUnset: Bool
    @Published private(set) var weeklyData: [DayWorkData]
    @Published private var currentTime: Date

    private let defaults = UserDefaults.standard
    private let calendar = Calendar.current
    private let fixedBreakMinutes = 60
    private var timerCancellable: AnyCancellable?
    private var trackedDayStart: Date
    private var autoFillTarget: AutoFillTarget?
    private var excludedAutoFillIndexes: [Int]

    private enum Keys {
        static let startTime = "startTime"
        static let endTime = "endTime"
        static let targetWorkMinutes = "targetWorkMinutes"
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

    init() {
        let now = Date()
        currentTime = now
        trackedDayStart = calendar.startOfDay(for: now)

        let defaultStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        let initialTargetWorkMinutes = defaults.object(forKey: Keys.targetWorkMinutes) as? Int ?? 8 * 60
        let initialStartTime = defaults.object(forKey: Keys.startTime) as? Date ?? defaultStart
        let savedEditedField = defaults.string(forKey: Keys.lastEditedField)
        lastEditedField = EditedField(rawValue: savedEditedField ?? "") ?? .startTime

        let initialEndTime = defaults.object(forKey: Keys.endTime) as? Date
            ?? calendar.date(byAdding: .minute, value: initialTargetWorkMinutes + fixedBreakMinutes, to: initialStartTime)
            ?? initialStartTime

        targetWorkMinutes = initialTargetWorkMinutes
        startTime = initialStartTime
        endTime = initialEndTime
        menuBarDisplayMode = Self.loadMenuBarDisplayMode(from: defaults)
        isStartTimeUnset = defaults.object(forKey: Keys.isStartTimeUnset) as? Bool ?? false
        isEndTimeUnset = defaults.object(forKey: Keys.isEndTimeUnset) as? Bool ?? false
        weeklyData = Self.loadWeeklyData(from: defaults)
        autoFillTarget = Self.loadAutoFillTarget(from: defaults)
        excludedAutoFillIndexes = defaults.array(forKey: Keys.excludedAutoFillIndexes) as? [Int] ?? []

        if shouldResetForNewDay(referenceDate: now) {
            resetTodayForNewDay(referenceDate: now)
        } else {
            defaults.set(trackedDayStart, forKey: Keys.lastActiveDayStart)
        }

        alignTimesUsingLastEditedField()
        startTimer()
    }

    var menuBarTitle: String {
        guard let mode = menuBarDisplayMode else {
            return "-- -- --"
        }

        switch mode.metric {
        case .worked:
            return compactDuration(workedMinutesToday)
        case .remaining:
            return compactDuration(remainingWorkMinutesToday)
        case .hidden:
            return ""
        }
    }

    var menuBarEmoji: String {
        menuBarDisplayMode?.menuBarEmoji ?? "❓"
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
        formatMinutesToKorean(remainingWorkMinutesToday)
    }

    var weekTotalText: String {
        formatMinutesToKorean(weeklyWorkedMinutes)
    }

    var weekRemainingText: String {
        weeklyRemainingMinutes == 0 ? "집에가자 😎" : formatMinutesToKorean(weeklyRemainingMinutes)
    }

    var menuBarMetricBinding: Binding<MenuBarMetric> {
        Binding(
            get: { self.menuBarDisplayMode?.metric ?? .remaining },
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

    var targetHoursBinding: Binding<Int> {
        Binding(
            get: { self.targetWorkMinutes / 60 },
            set: { self.updateTargetHours($0) }
        )
    }

    func updateStartTime(_ newValue: Date) {
        lastEditedField = .startTime
        isStartTimeUnset = false
        isEndTimeUnset = false
        startTime = newValue
        endTime = addingMinutes(targetWorkMinutes + fixedBreakMinutes, to: newValue)
        persistTodayState()
    }

    func updateEndTime(_ newValue: Date) {
        lastEditedField = .endTime
        isStartTimeUnset = false
        isEndTimeUnset = false
        endTime = newValue
        startTime = addingMinutes(-(targetWorkMinutes + fixedBreakMinutes), to: newValue)
        persistTodayState()
    }

    func updateTargetHours(_ hours: Int) {
        if isStartTimeUnset || isEndTimeUnset {
            reactivateTodayInputs()
        }
        targetWorkMinutes = hours * 60
        alignTimesUsingLastEditedField()
        persistTodayState()
    }

    func resetTodayState() {
        let now = currentTime
        targetWorkMinutes = 8 * 60
        let defaultStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        startTime = defaultStart
        endTime = addingMinutes(targetWorkMinutes + fixedBreakMinutes, to: defaultStart)
        isStartTimeUnset = true
        isEndTimeUnset = true
        lastEditedField = .startTime
        setMenuBarDisplayMode(nil)
        persistTodayState()
    }

    func activateStartTimeSelection() {
        reactivateTodayInputs()
        lastEditedField = .startTime
        endTime = addingMinutes(targetWorkMinutes + fixedBreakMinutes, to: startTime)
        persistTodayState()
    }

    func activateEndTimeSelection() {
        reactivateTodayInputs()
        lastEditedField = .endTime
        startTime = addingMinutes(-(targetWorkMinutes + fixedBreakMinutes), to: endTime)
        persistTodayState()
    }

    func resetWeeklyState() {
        weeklyData = defaultWeekData()
        autoFillTarget = nil
        excludedAutoFillIndexes = []
        persistWeeklyState()
    }

    func weeklyDay(at idx: Int) -> DayWorkData {
        weeklyData[idx]
    }

    func weeklyDayRecognizedText(at idx: Int) -> String {
        formatMinutesToKorean(getDailyMinutes(weeklyData[idx]))
    }

    func updateWeeklyLeaveType(idx: Int, leaveType: LeaveType) {
        handleWeeklyUpdate(idx: idx, updatesReason: .stateOnly) { day in
            day.leaveType = leaveType
        }
    }

    func toggleWeeklyMode(idx: Int) {
        handleWeeklyUpdate(idx: idx, updatesReason: .stateOnly) { day in
            day.mode = day.mode == .range ? .manual : .range
        }
    }

    func updateWeeklyStart(idx: Int, value: String) {
        var newData = weeklyData
        newData[idx].start = sanitizeTimeString(value)
        let nextExcluded = excludedAutoFillIndexes.filter { $0 != idx }
        let preferredTarget = getRangeAutoFillTarget(data: newData, idx: idx, editedField: .start, excludedIndexes: nextExcluded)
        let result = applyAutoFill(
            data: newData,
            preferredTarget: preferredTarget,
            excludedIndexes: nextExcluded,
            allowPreferredOverride: preferredTarget != nil
        )
        commitWeeklyState(data: result.nextData, target: result.nextTarget, excludedIndexes: nextExcluded)
    }

    func updateWeeklyEnd(idx: Int, value: String) {
        var newData = weeklyData
        newData[idx].end = sanitizeTimeString(value)
        let nextExcluded = excludedAutoFillIndexes.filter { $0 != idx }
        let preferredTarget = getRangeAutoFillTarget(data: newData, idx: idx, editedField: .end, excludedIndexes: nextExcluded)
        let result = applyAutoFill(
            data: newData,
            preferredTarget: preferredTarget,
            excludedIndexes: nextExcluded,
            allowPreferredOverride: preferredTarget != nil
        )
        commitWeeklyState(data: result.nextData, target: result.nextTarget, excludedIndexes: nextExcluded)
    }

    func updateWeeklyManualHours(idx: Int, value: String) {
        handleWeeklyManualUpdate(idx: idx) { day in
            day.manualHours = sanitizeNumberString(value)
        }
    }

    func updateWeeklyManualMinutes(idx: Int, value: String) {
        handleWeeklyManualUpdate(idx: idx) { day in
            day.manualMinutes = sanitizeNumberString(value)
        }
    }

    func resetWeeklyDay(idx: Int) {
        var newData = weeklyData
        newData[idx].start = ""
        newData[idx].end = ""
        newData[idx].manualHours = ""
        newData[idx].manualMinutes = ""
        newData[idx].leaveType = .none
        newData[idx].lockStart = false
        newData[idx].lockEnd = false
        newData[idx].lockManual = false

        let nextExcluded = Array(Set(excludedAutoFillIndexes + [idx])).sorted()
        let result = applyAutoFill(data: newData, preferredTarget: nil, excludedIndexes: nextExcluded)
        commitWeeklyState(data: result.nextData, target: result.nextTarget, excludedIndexes: nextExcluded)
    }

    func fitWeeklyDayToEightHours(idx: Int) {
        let data = weeklyData[idx]
        guard data.mode == .range, data.leaveType != .annual else {
            return
        }

        let neededWorkMinutes = max(0, 8 * 60 - getLeaveCreditMinutes(data))
        var newData = weeklyData

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
        setMenuBarDisplayMode(MenuBarDisplayMode(metric: .remaining))
    }

    private func shouldResetForNewDay(referenceDate: Date) -> Bool {
        guard let savedDayStart = defaults.object(forKey: Keys.lastActiveDayStart) as? Date else {
            return false
        }
        return !calendar.isDate(savedDayStart, inSameDayAs: referenceDate)
    }

    private func resetTodayForNewDay(referenceDate: Date) {
        trackedDayStart = calendar.startOfDay(for: referenceDate)
        let defaultStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: referenceDate) ?? referenceDate
        startTime = defaultStart
        endTime = addingMinutes(targetWorkMinutes + fixedBreakMinutes, to: defaultStart)
        isStartTimeUnset = true
        isEndTimeUnset = true
        lastEditedField = .startTime
        setMenuBarDisplayMode(nil)
        defaults.set(trackedDayStart, forKey: Keys.lastActiveDayStart)
        persistTodayState()
    }

    private func handleDayChangeIfNeeded(for now: Date) {
        if !calendar.isDate(trackedDayStart, inSameDayAs: now) {
            resetTodayForNewDay(referenceDate: now)
        }
    }

    private func alignTimesUsingLastEditedField() {
        switch lastEditedField {
        case .startTime:
            endTime = addingMinutes(targetWorkMinutes + fixedBreakMinutes, to: startTime)
        case .endTime:
            startTime = addingMinutes(-(targetWorkMinutes + fixedBreakMinutes), to: endTime)
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
        max(0, targetWorkMinutes - min(workedMinutesToday, targetWorkMinutes))
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
        defaults.set(endTime, forKey: Keys.endTime)
        defaults.set(targetWorkMinutes, forKey: Keys.targetWorkMinutes)
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

    private enum WeeklyUpdateReason {
        case dataEdit
        case stateOnly
    }

    private func handleWeeklyUpdate(
        idx: Int,
        updatesReason: WeeklyUpdateReason,
        mutation: (inout DayWorkData) -> Void
    ) {
        var newData = weeklyData
        mutation(&newData[idx])

        let nextExcluded = updatesReason == .dataEdit
            ? excludedAutoFillIndexes.filter { $0 != idx }
            : excludedAutoFillIndexes

        let preferredTarget = autoFillTarget?.idx == idx && updatesReason == .stateOnly ? nil : autoFillTarget
        let result = applyAutoFill(
            data: newData,
            preferredTarget: preferredTarget,
            excludedIndexes: nextExcluded,
            allowPreferredOverride: false
        )
        commitWeeklyState(data: result.nextData, target: result.nextTarget, excludedIndexes: nextExcluded)
    }

    private func handleWeeklyManualUpdate(idx: Int, mutation: (inout DayWorkData) -> Void) {
        handleWeeklyUpdate(idx: idx, updatesReason: .dataEdit, mutation: mutation)
    }

    private func commitWeeklyState(data: [DayWorkData], target: AutoFillTarget?, excludedIndexes: [Int]) {
        weeklyData = data
        autoFillTarget = target
        excludedAutoFillIndexes = excludedIndexes
        persistWeeklyState()
    }

    private func isValidAutoFillTarget(data: [DayWorkData], target: AutoFillTarget?) -> Bool {
        guard let target, data.indices.contains(target.idx) else {
            return false
        }

        let day = data[target.idx]
        if day.leaveType == .annual {
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

    private func inferAutoFillTarget(data: [DayWorkData], excludedIndexes: [Int] = []) -> AutoFillTarget? {
        let candidates = data.enumerated().flatMap { idx, day -> [AutoFillTarget] in
            if excludedIndexes.contains(idx) || day.leaveType == .annual {
                return []
            }

            if day.mode == .manual {
                let hasManualInput = !day.manualHours.isEmpty || !day.manualMinutes.isEmpty
                if !hasManualInput {
                    return [AutoFillTarget(idx: idx, type: .manual)]
                }
                return []
            }

            if !day.start.isEmpty && day.end.isEmpty {
                return [AutoFillTarget(idx: idx, type: .end)]
            }

            if !day.end.isEmpty && day.start.isEmpty {
                return [AutoFillTarget(idx: idx, type: .start)]
            }

            return []
        }

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

        if isValidAutoFillTarget(data: data, target: preferredTarget),
           (allowPreferredOverride || isSameAutoFillTarget(preferredTarget, inferredTarget)) {
            resolvedTarget = preferredTarget
        } else {
            resolvedTarget = inferredTarget
        }

        guard let resolvedTarget else {
            return (data, nil)
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

        switch resolvedTarget.type {
        case .manual:
            nextData[resolvedTarget.idx].manualHours = String(targetWorkMinutes / 60)
            nextData[resolvedTarget.idx].manualMinutes = String(targetWorkMinutes % 60)
        case .end:
            nextData[resolvedTarget.idx].end = minutesToTime(
                calculateReverseTime(
                    baseTimeMinutes: timeToMinutes(nextData[resolvedTarget.idx].start),
                    targetMinutes: targetWorkMinutes,
                    type: .end
                )
            )
        case .start:
            nextData[resolvedTarget.idx].start = minutesToTime(
                calculateReverseTime(
                    baseTimeMinutes: timeToMinutes(nextData[resolvedTarget.idx].end),
                    targetMinutes: targetWorkMinutes,
                    type: .start
                )
            )
        }

        return (nextData, resolvedTarget)
    }

    private func getRangeAutoFillTarget(
        data: [DayWorkData],
        idx: Int,
        editedField: AutoFillType,
        excludedIndexes: [Int]
    ) -> AutoFillTarget? {
        let day = data[idx]
        if day.mode != .range || day.leaveType == .annual {
            return nil
        }

        let targetType: AutoFillType = editedField == .start ? .end : .start
        if targetType == .end && day.start.isEmpty {
            return nil
        }
        if targetType == .start && day.end.isEmpty {
            return nil
        }

        var probeData = data
        switch targetType {
        case .end:
            probeData[idx].end = ""
        case .start:
            probeData[idx].start = ""
        case .manual:
            break
        }

        let preferredTarget = AutoFillTarget(idx: idx, type: targetType)
        let inferredTarget = inferAutoFillTarget(data: probeData, excludedIndexes: excludedIndexes)
        return isSameAutoFillTarget(inferredTarget, preferredTarget) ? preferredTarget : nil
    }

    private func sanitizeTimeString(_ value: String) -> String {
        String(value.prefix(5))
    }

    private func sanitizeNumberString(_ value: String) -> String {
        String(value.filter(\.isNumber))
    }
}
