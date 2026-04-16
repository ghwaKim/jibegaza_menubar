import Foundation
import SwiftUI
import Combine

@MainActor
final class TimeCalculatorViewModel: ObservableObject {
    @Published private(set) var startTime: Date
    @Published private(set) var endTime: Date
    @Published private(set) var targetWorkMinutes: Int
    @Published private(set) var menuBarDisplayMode: MenuBarDisplayMode?
    @Published private(set) var isStartTimeUnset: Bool
    @Published private(set) var isEndTimeUnset: Bool
    @Published private var currentTime: Date

    private let defaults = UserDefaults.standard
    private let calendar = Calendar.current
    private let fixedBreakMinutes = 60
    private var timerCancellable: AnyCancellable?
    private var trackedDayStart: Date

    private enum Keys {
        static let startTime = "startTime"
        static let endTime = "endTime"
        static let targetWorkMinutes = "targetWorkMinutes"
        static let lastEditedField = "lastEditedField"
        static let menuBarDisplayMode = "menuBarDisplayMode"
        static let lastActiveDayStart = "lastActiveDayStart"
        static let isStartTimeUnset = "isStartTimeUnset"
        static let isEndTimeUnset = "isEndTimeUnset"
    }

    private enum EditedField: String {
        case startTime
        case endTime
    }

    enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
        case totalWorkedToday
        case remainingWorkToday

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .totalWorkedToday:
                return "⏱️"
            case .remainingWorkToday:
                return "⏳"
            }
        }

        var symbolName: String {
            switch self {
            case .totalWorkedToday:
                return "stopwatch"
            case .remainingWorkToday:
                return "clock.arrow.circlepath"
            }
        }

        var label: String {
            switch self {
            case .totalWorkedToday:
                return "오늘 총 근무시간"
            case .remainingWorkToday:
                return "오늘 남은 근무시간"
            }
        }
    }

    private var lastEditedField: EditedField {
        didSet { defaults.set(lastEditedField.rawValue, forKey: Keys.lastEditedField) }
    }

    init() {
        let now = Date()
        currentTime = now
        trackedDayStart = calendar.startOfDay(for: now)
        let defaultStart = calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: now
        ) ?? now

        let savedTarget = defaults.object(forKey: Keys.targetWorkMinutes) as? Int
        let initialTargetWorkMinutes = savedTarget ?? 8 * 60

        let initialStartTime = defaults.object(forKey: Keys.startTime) as? Date ?? defaultStart

        let savedEditedField = defaults.string(forKey: Keys.lastEditedField)
        lastEditedField = EditedField(rawValue: savedEditedField ?? "") ?? .startTime

        let savedDisplayMode = defaults.string(forKey: Keys.menuBarDisplayMode)
        menuBarDisplayMode = savedDisplayMode.flatMap(MenuBarDisplayMode.init(rawValue:))
        isStartTimeUnset = defaults.object(forKey: Keys.isStartTimeUnset) as? Bool ?? false
        isEndTimeUnset = defaults.object(forKey: Keys.isEndTimeUnset) as? Bool ?? false

        let initialEndTime: Date
        if let savedEnd = defaults.object(forKey: Keys.endTime) as? Date {
            initialEndTime = savedEnd
        } else {
            initialEndTime = calendar.date(
                byAdding: .minute,
                value: initialTargetWorkMinutes + fixedBreakMinutes,
                to: initialStartTime
            ) ?? initialStartTime
        }

        targetWorkMinutes = initialTargetWorkMinutes
        startTime = initialStartTime
        endTime = initialEndTime

        if shouldResetForNewDay(referenceDate: now) {
            resetForNewDay(referenceDate: now)
        } else {
            defaults.set(trackedDayStart, forKey: Keys.lastActiveDayStart)
        }

        alignTimesUsingLastEditedField()
        startTimer()
    }

    var menuBarTitle: String {
        guard let menuBarDisplayMode else {
            return "-- -- --"
        }

        switch menuBarDisplayMode {
        case .totalWorkedToday:
            return formattedDuration(min(workedMinutesToday, 9 * 60))
        case .remainingWorkToday:
            return formattedDuration(remainingWorkMinutesToday)
        }
    }

    var menuBarSymbolName: String {
        guard let menuBarDisplayMode else {
            return "questionmark.circle"
        }

        return menuBarDisplayMode.symbolName
    }

    var formattedTargetWork: String {
        formattedDuration(targetWorkMinutes)
    }

    var formattedStartTime: String {
        guard !isStartTimeUnset else {
            return "-- --"
        }
        return formattedClock(startTime)
    }

    var formattedEndTime: String {
        guard !isEndTimeUnset else {
            return "-- --"
        }
        return formattedClock(endTime)
    }

    var fixedBreakDescription: String {
        "60분 (오후 12:30 ~ 오후 1:30)"
    }

    var formattedWorkedToday: String {
        formattedDuration(workedMinutesToday)
    }

    var formattedRemainingToday: String {
        formattedDuration(remainingWorkMinutesToday)
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

    var menuBarDisplayModeBinding: Binding<MenuBarDisplayMode?> {
        Binding(
            get: { self.menuBarDisplayMode },
            set: { self.updateMenuBarDisplayMode($0) }
        )
    }

    func updateStartTime(_ newValue: Date) {
        lastEditedField = .startTime
        isStartTimeUnset = false
        isEndTimeUnset = false
        startTime = newValue
        endTime = addingMinutes(targetWorkMinutes + fixedBreakMinutes, to: newValue)
        persist()
    }

    func updateEndTime(_ newValue: Date) {
        lastEditedField = .endTime
        isStartTimeUnset = false
        isEndTimeUnset = false
        endTime = newValue
        startTime = addingMinutes(-(targetWorkMinutes + fixedBreakMinutes), to: newValue)
        persist()
    }

    func updateTargetHours(_ hours: Int) {
        if isStartTimeUnset || isEndTimeUnset {
            reactivateTimeInputs()
        }
        targetWorkMinutes = hours * 60
        alignTimesUsingLastEditedField()
        persist()
    }

    func updateMenuBarDisplayMode(_ mode: MenuBarDisplayMode?) {
        if isStartTimeUnset || isEndTimeUnset {
            reactivateTimeInputs()
        }
        menuBarDisplayMode = mode
        defaults.set(mode?.rawValue, forKey: Keys.menuBarDisplayMode)
    }

    func activateStartTimeSelection() {
        reactivateTimeInputs()
        lastEditedField = .startTime
        endTime = addingMinutes(targetWorkMinutes + fixedBreakMinutes, to: startTime)
        persist()
    }

    func activateEndTimeSelection() {
        reactivateTimeInputs()
        lastEditedField = .endTime
        startTime = addingMinutes(-(targetWorkMinutes + fixedBreakMinutes), to: endTime)
        persist()
    }

    func resetMenuBarAndTimes() {
        let now = currentTime
        targetWorkMinutes = 8 * 60
        let defaultStart = calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: now
        ) ?? now

        startTime = defaultStart
        endTime = addingMinutes(targetWorkMinutes + fixedBreakMinutes, to: defaultStart)
        isStartTimeUnset = true
        isEndTimeUnset = true
        lastEditedField = .startTime
        menuBarDisplayMode = nil
        defaults.removeObject(forKey: Keys.menuBarDisplayMode)
        persist()
    }

    private func reactivateTimeInputs() {
        isStartTimeUnset = false
        isEndTimeUnset = false
        menuBarDisplayMode = .remainingWorkToday
        defaults.set(MenuBarDisplayMode.remainingWorkToday.rawValue, forKey: Keys.menuBarDisplayMode)
        alignTimesUsingLastEditedField()
    }

    private func shouldResetForNewDay(referenceDate: Date) -> Bool {
        guard let savedDayStart = defaults.object(forKey: Keys.lastActiveDayStart) as? Date else {
            return false
        }

        return !calendar.isDate(savedDayStart, inSameDayAs: referenceDate)
    }

    private func resetForNewDay(referenceDate: Date) {
        trackedDayStart = calendar.startOfDay(for: referenceDate)
        let defaultStart = calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: referenceDate
        ) ?? referenceDate

        startTime = defaultStart
        endTime = addingMinutes(targetWorkMinutes + fixedBreakMinutes, to: defaultStart)
        isStartTimeUnset = true
        isEndTimeUnset = true
        lastEditedField = .startTime
        menuBarDisplayMode = nil

        defaults.removeObject(forKey: Keys.menuBarDisplayMode)
        defaults.set(trackedDayStart, forKey: Keys.lastActiveDayStart)
        persist()
    }

    private func handleDayChangeIfNeeded(for now: Date) {
        if !calendar.isDate(trackedDayStart, inSameDayAs: now) {
            resetForNewDay(referenceDate: now)
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
        if isStartTimeUnset || isEndTimeUnset {
            return 0
        }

        if currentTime <= startTime {
            return 0
        }

        let effectiveEnd = min(currentTime, endTime)
        let rawWorkedMinutes = max(0, minutesBetween(startTime, and: effectiveEnd))
        let breakOverlap = overlapMinutes(
            firstStart: startTime,
            firstEnd: effectiveEnd,
            secondStart: fixedBreakStart,
            secondEnd: fixedBreakEnd
        )

        return min(targetWorkMinutes, max(0, rawWorkedMinutes - breakOverlap))
    }

    private var remainingWorkMinutesToday: Int {
        max(0, targetWorkMinutes - workedMinutesToday)
    }

    private var fixedBreakStart: Date {
        calendar.date(bySettingHour: 12, minute: 30, second: 0, of: startTime) ?? startTime
    }

    private var fixedBreakEnd: Date {
        calendar.date(bySettingHour: 13, minute: 30, second: 0, of: startTime) ?? startTime
    }

    private func minutesBetween(_ start: Date, and end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start) / 60))
    }

    private func overlapMinutes(
        firstStart: Date,
        firstEnd: Date,
        secondStart: Date,
        secondEnd: Date
    ) -> Int {
        let overlapStart = max(firstStart, secondStart)
        let overlapEnd = min(firstEnd, secondEnd)

        guard overlapEnd > overlapStart else {
            return 0
        }

        return minutesBetween(overlapStart, and: overlapEnd)
    }

    private func formattedDuration(_ totalMinutes: Int) -> String {
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%dh %02dm", hours, minutes)
    }

    private func startTimer() {
        timerCancellable = Timer
            .publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                self?.currentTime = now
                self?.handleDayChangeIfNeeded(for: now)
            }
    }

    private func formattedClock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter.string(from: date)
    }

    private func persist() {
        defaults.set(startTime, forKey: Keys.startTime)
        defaults.set(endTime, forKey: Keys.endTime)
        defaults.set(targetWorkMinutes, forKey: Keys.targetWorkMinutes)
        defaults.set(isStartTimeUnset, forKey: Keys.isStartTimeUnset)
        defaults.set(isEndTimeUnset, forKey: Keys.isEndTimeUnset)
    }
}
