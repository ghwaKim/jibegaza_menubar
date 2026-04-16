import Foundation

enum WorkTab: String, CaseIterable, Identifiable {
    case today
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return "오늘 근무"
        case .week:
            return "주간 시간 계산"
        }
    }
}

enum MenuBarScope: String, CaseIterable, Identifiable, Codable {
    case today
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return "오늘 근무"
        case .week:
            return "금주 근무"
        }
    }
}

enum MenuBarMetric: String, CaseIterable, Identifiable, Codable {
    case worked
    case remaining

    var id: String { rawValue }

    var title: String {
        switch self {
        case .worked:
            return "지금까지 근무시간"
        case .remaining:
            return "남은 근무시간"
        }
    }
}

struct MenuBarDisplayMode: Codable, Equatable {
    var scope: MenuBarScope
    var metric: MenuBarMetric

    var popupEmoji: String {
        switch (scope, metric) {
        case (.today, .worked):
            return "⏱️"
        case (.today, .remaining):
            return "⏳"
        case (.week, .worked):
            return "📅"
        case (.week, .remaining):
            return "🗓️"
        }
    }

    var popupLabel: String {
        switch (scope, metric) {
        case (.today, .worked):
            return "오늘 총 근무시간"
        case (.today, .remaining):
            return "오늘 남은 근무시간"
        case (.week, .worked):
            return "주간 총 근무시간"
        case (.week, .remaining):
            return "주간 남은 근무시간"
        }
    }

    var symbolName: String {
        switch (scope, metric) {
        case (.today, .worked):
            return "stopwatch"
        case (.today, .remaining):
            return "hourglass"
        case (.week, .worked):
            return "calendar"
        case (.week, .remaining):
            return "calendar.badge.clock"
        }
    }
}

enum LeaveType: String, CaseIterable, Identifiable, Codable {
    case none
    case annual
    case half
    case halfHalf = "half-half"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "정상근무"
        case .annual:
            return "연차"
        case .half:
            return "반차"
        case .halfHalf:
            return "반반차"
        }
    }
}

enum InputMode: String, CaseIterable, Identifiable, Codable {
    case range
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .range:
            return "⏰ 구간"
        case .manual:
            return "✏️ 합계"
        }
    }
}

struct DayWorkData: Codable, Identifiable {
    var day: String
    var mode: InputMode
    var start: String
    var end: String
    var manualHours: String
    var manualMinutes: String
    var leaveType: LeaveType
    var lockStart: Bool
    var lockEnd: Bool
    var lockManual: Bool

    var id: String { day }
}

enum AutoFillType: String, Codable {
    case manual
    case start
    case end
}

struct AutoFillTarget: Codable, Equatable {
    var idx: Int
    var type: AutoFillType
}
