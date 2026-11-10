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
    case untilDeparture
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .worked:
            return "지금까지 근무시간"
        case .untilDeparture:
            return "퇴근까지 남은 시간"
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
        case .untilDeparture:
            return "⏳"
        case .hidden:
            return "🌍"
        }
    }

    var popupLabel: String {
        switch metric {
        case .worked:
            return "오늘 총 근무시간"
        case .untilDeparture:
            return "퇴근까지 남은 시간"
        case .hidden:
            return "시간 숨기기"
        }
    }

    var menuBarEmoji: String {
        switch metric {
        case .worked:
            return "⏱️"
        case .untilDeparture:
            return "⏳"
        case .hidden:
            return "🌍"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let savedMetric = try container.decode(String.self, forKey: .metric)
        if savedMetric == "remaining" {
            metric = .untilDeparture
        } else {
            metric = try container.decode(MenuBarMetric.self, forKey: .metric)
        }
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

enum TodayTargetMode: String, Codable {
    case preset
    case autoSuggested
    case manualOverride
}

enum TodayTargetSelection: String, CaseIterable, Identifiable {
    case sixHours
    case sevenHours
    case eightHours
    case nineHours
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sixHours:
            return "6h"
        case .sevenHours:
            return "7h"
        case .eightHours:
            return "8h"
        case .nineHours:
            return "9h"
        case .manual:
            return "직접입력"
        }
    }

    var presetMinutes: Int? {
        switch self {
        case .sixHours:
            return 6 * 60
        case .sevenHours:
            return 7 * 60
        case .eightHours:
            return 8 * 60
        case .nineHours:
            return 9 * 60
        case .manual:
            return nil
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
    var isConfirmed: Bool = false
    var importedFromFlex = false

    func isLocked(_ field: AutoFillType) -> Bool {
        if isConfirmed { return true }
        switch field {
        case .start: return lockStart
        case .end: return lockEnd
        case .manual: return lockManual
        }
    }

    private enum CodingKeys: String, CodingKey {
        case day, mode, start, end, manualHours, manualMinutes, leaveType
        case lockStart, lockEnd, lockManual, isConfirmed, importedFromFlex
    }

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

// Keep records saved before day confirmation was introduced readable.
extension DayWorkData {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        day = try values.decode(String.self, forKey: .day)
        mode = try values.decode(InputMode.self, forKey: .mode)
        start = try values.decode(String.self, forKey: .start)
        end = try values.decode(String.self, forKey: .end)
        manualHours = try values.decode(String.self, forKey: .manualHours)
        manualMinutes = try values.decode(String.self, forKey: .manualMinutes)
        leaveType = try values.decode(LeaveType.self, forKey: .leaveType)
        lockStart = try values.decodeIfPresent(Bool.self, forKey: .lockStart) ?? false
        lockEnd = try values.decodeIfPresent(Bool.self, forKey: .lockEnd) ?? false
        lockManual = try values.decodeIfPresent(Bool.self, forKey: .lockManual) ?? false
        isConfirmed = try values.decodeIfPresent(Bool.self, forKey: .isConfirmed) ?? false
        importedFromFlex = try values.decodeIfPresent(Bool.self, forKey: .importedFromFlex) ?? false
        // Hidden legacy pins must remain releasable through the day lock.
        if lockManual { isConfirmed = true; lockManual = false }
        if mode == .manual || leaveType == .annual {
            if lockStart || lockEnd { isConfirmed = true }
            lockStart = false
            lockEnd = false
        }
    }
}
