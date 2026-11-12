import Foundation

/// The existing UserDefaults keys and Codable migrations are kept in one place.
/// This store saves snapshots; it never calculates or changes working state.
final class WorkStateStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    struct TodayState {
        var startTime: Date
        var endTime: Date
        var isStartTimeFromFlex: Bool
        var targetWorkMinutes: Int
        var baseTargetWorkMinutes: Int
        var manualOverrideTargetMinutes: Int?
        var isManualTargetSelectionActive: Bool
        var isStartTimeUnset: Bool
        var isEndTimeUnset: Bool
        var dayStart: Date
    }

    struct LoadedState {
        let today: TodayState
        let lastEditedField: TodayWorkCalculator.EditedField
        let menuBarDisplayMode: MenuBarDisplayMode?
        let weeklyData: [DayWorkData]
        let autoFillTarget: AutoFillTarget?
        let excludedAutoFillIndexes: [Int]
    }

    func load(now: Date, calendar: Calendar) -> LoadedState {
        let defaultStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        let legacy = defaults.object(forKey: Keys.targetWorkMinutes) as? Int ?? 8 * 60
        let base = defaults.object(forKey: Keys.baseTargetWorkMinutes) as? Int ?? legacy
        let start = defaults.object(forKey: Keys.startTime) as? Date ?? defaultStart
        let end =
            defaults.object(forKey: Keys.endTime) as? Date
            ?? calendar.date(byAdding: .minute, value: base + 60, to: start) ?? start
        return LoadedState(
            today: TodayState(
                startTime: start, endTime: end,
                isStartTimeFromFlex: defaults.bool(forKey: Keys.isStartTimeFromFlex),
                targetWorkMinutes: base, baseTargetWorkMinutes: base,
                manualOverrideTargetMinutes: defaults.object(forKey: Keys.manualOverrideTargetMinutes) as? Int,
                isManualTargetSelectionActive: defaults.object(forKey: Keys.isManualTargetSelectionActive) as? Bool
                    ?? false,
                isStartTimeUnset: defaults.object(forKey: Keys.isStartTimeUnset) as? Bool ?? false,
                isEndTimeUnset: defaults.object(forKey: Keys.isEndTimeUnset) as? Bool ?? false,
                dayStart: calendar.startOfDay(for: now)),
            lastEditedField: TodayWorkCalculator.EditedField(
                rawValue: defaults.string(forKey: Keys.lastEditedField) ?? "") ?? .startTime,
            menuBarDisplayMode: Self.loadMenuBarDisplayMode(from: defaults),
            weeklyData: Self.loadWeeklyData(from: defaults),
            autoFillTarget: Self.loadAutoFillTarget(from: defaults),
            excludedAutoFillIndexes: defaults.array(forKey: Keys.excludedAutoFillIndexes) as? [Int] ?? [])
    }

    var lastActiveDayStart: Date? {
        get { defaults.object(forKey: Keys.lastActiveDayStart) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastActiveDayStart) }
    }

    var flexWeekStart: Date? {
        get { defaults.object(forKey: "flex.weekStart") as? Date }
        set { defaults.set(newValue, forKey: "flex.weekStart") }
    }

    var flexAccountID: String? {
        get { defaults.string(forKey: "flex.accountID") }
        set {
            if let newValue {
                defaults.set(newValue, forKey: "flex.accountID")
            } else {
                defaults.removeObject(forKey: "flex.accountID")
            }
        }
    }

    func saveLastEditedField(_ field: TodayWorkCalculator.EditedField) {
        defaults.set(field.rawValue, forKey: Keys.lastEditedField)
    }

    func clearAutoFillTarget() { defaults.removeObject(forKey: Keys.autoFillTarget) }

    func saveMenuBarMode(_ mode: MenuBarDisplayMode?) {
        if let mode, let data = try? JSONEncoder().encode(mode) {
            defaults.set(data, forKey: Keys.menuBarDisplayMode)
        } else {
            defaults.removeObject(forKey: Keys.menuBarDisplayMode)
        }
    }

    func saveToday(_ state: TodayState) {
        defaults.set(state.startTime, forKey: Keys.startTime)
        defaults.set(state.isStartTimeFromFlex, forKey: Keys.isStartTimeFromFlex)
        defaults.set(state.endTime, forKey: Keys.endTime)
        defaults.set(state.targetWorkMinutes, forKey: Keys.targetWorkMinutes)
        defaults.set(state.baseTargetWorkMinutes, forKey: Keys.baseTargetWorkMinutes)
        if let manualOverrideTargetMinutes = state.manualOverrideTargetMinutes {
            defaults.set(manualOverrideTargetMinutes, forKey: Keys.manualOverrideTargetMinutes)
        } else {
            defaults.removeObject(forKey: Keys.manualOverrideTargetMinutes)
        }
        defaults.set(state.isManualTargetSelectionActive, forKey: Keys.isManualTargetSelectionActive)
        defaults.set(state.isStartTimeUnset, forKey: Keys.isStartTimeUnset)
        defaults.set(state.isEndTimeUnset, forKey: Keys.isEndTimeUnset)
        defaults.set(state.dayStart, forKey: Keys.lastActiveDayStart)
    }

    func saveWeekly(
        data weeklyData: [DayWorkData], target autoFillTarget: AutoFillTarget?, excluded excludedAutoFillIndexes: [Int]
    ) {
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
            decoded.count == weekDays.count
        else {
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
}
