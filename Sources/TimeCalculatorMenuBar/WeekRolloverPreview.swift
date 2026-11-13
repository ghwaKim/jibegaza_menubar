import Foundation

/// Debug-only UI scenario with a separate preferences domain and no background sync.
enum WeekRolloverPreview {
    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--preview-week-rollover")
        #else
        false
        #endif
    }

    @MainActor
    static func makeViewModel() -> TimeCalculatorViewModel {
        guard isEnabled else { return TimeCalculatorViewModel() }
        let now = Date()
        let calendar = Calendar.current
        let previousMonday = calendar.date(byAdding: .day, value: -7,
            to: WorkWeek.start(for: now, calendar: calendar))!
        let suite = "com.jibegaza.preview.week-rollover"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var days = defaultWeekData()
        for index in 0..<4 {
            days[index].manualHours = "8"
            days[index].manualMinutes = "0"
            days[index].isConfirmed = true
        }
        days[4].leaveType = .annual
        let store = WorkStateStore(defaults: defaults)
        store.saveWeekly(data: days, target: nil, excluded: [])
        store.recordedWeekStart = previousMonday
        store.flexWeekStart = previousMonday
        let viewModel = TimeCalculatorViewModel(defaults: defaults, now: now, calendar: calendar)
        viewModel.selectedTab = .week
        return viewModel
    }
}
