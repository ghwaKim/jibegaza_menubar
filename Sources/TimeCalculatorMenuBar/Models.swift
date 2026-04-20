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

enum MenuBarMetric: String, CaseIterable, Identifiable, Codable {
    case worked
    case remaining
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .worked:
            return "지금까지 근무시간"
        case .remaining:
            return "남은 근무시간"
        case .hidden:
            return "시간 숨기기"
        }
    }
}

struct MenuBarDisplayMode: Codable, Equatable {
    var metric: MenuBarMetric

    init(metric: MenuBarMetric) {
        self.metric = metric
    }

    private enum CodingKeys: String, CodingKey {
        case metric
        case scope
    }

    var popupEmoji: String {
        switch metric {
        case .worked:
            return "⏱️"
        case .remaining:
            return "⏳"
        case .hidden:
            return "🌍"
        }
    }

    var popupLabel: String {
        switch metric {
        case .worked:
            return "오늘 총 근무시간"
        case .remaining:
            return "오늘 남은 근무시간"
        case .hidden:
            return "시간 숨기기"
        }
    }

    var menuBarEmoji: String {
        switch metric {
        case .worked:
            return "⏱️"
        case .remaining:
            return "⏳"
        case .hidden:
            return "🌍"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metric = try container.decode(MenuBarMetric.self, forKey: .metric)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metric, forKey: .metric)
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
