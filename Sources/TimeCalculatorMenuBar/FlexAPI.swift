import Foundation

/// Internal web API contract observed in the published Reflex 1.3.6 client.
/// No third-party code is executed or embedded. Live authenticated validation remains required.
enum FlexAPI {
    static let identityPath = "/api/v2/workspace/users/me/workspace-users"

    static func schedulePath(userID: String, now: Date, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        let offset = (calendar.component(.weekday, from: today) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -offset, to: today)!
        let friday = calendar.date(byAdding: .day, value: 4, to: monday)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var parts = URLComponents()
        parts.path = "/api/v3/time-tracking/users/\(userID)/work-schedules"
        parts.queryItems = [
            URLQueryItem(name: "from", value: formatter.string(from: monday)),
            URLQueryItem(name: "to", value: formatter.string(from: friday)),
            URLQueryItem(name: "timezone", value: calendar.timeZone.identifier)
        ]
        return parts.string!
    }

    struct Identity: Decodable {
        struct Current: Decodable {
            struct User: Decodable { let userIdHash: String; let customerIdHash: String }
            let user: User
        }
        let currentUser: Current
    }

    struct Schedules: Decodable {
        struct Day: Decodable {
            struct DayOff: Decodable { let type: String }
            struct Block: Decodable {
                struct Value: Decodable {
                    struct Timestamp: Decodable { let timestamp: Double }
                    let allDay: Bool
                    let startTimestamp: Timestamp?
                    let endTimestampExclusive: Timestamp?
                }
                let type: String
                let value: Value
            }
            let date: String
            let dayOffs: [DayOff]
            let timeBlocks: [Block]
        }
        let userIdHash: String
        let dailySchedules: [Day]
    }

    static func records(from data: Data, userID: String, now: Date,
                        calendar: Calendar = .current) throws -> [FlexWorkRecord] {
        try report(from: data, userID: userID, now: now, calendar: calendar).records
    }

    struct Report {
        let records: [FlexWorkRecord]
        let receivedDays: Int
        let excluded: [String]
        var diagnostic: String {
            (["수신 \(receivedDays)일 · 가져오기 \(records.count)일"] + excluded).joined(separator: "\n")
        }
    }

    static func report(from data: Data, userID: String, now: Date,
                       calendar: Calendar = .current) throws -> Report {
        let response = try JSONDecoder().decode(Schedules.self, from: data)
        guard response.userIdHash == userID else { throw Failure.identityMismatch }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        var records: [FlexWorkRecord] = []
        var excluded: [String] = []
        for day in response.dailySchedules {
            let label = String(day.date.prefix(10))
            guard let date = formatter.date(from: day.date), formatter.string(from: date) == day.date else {
                excluded.append("\(label): 날짜 형식 미지원"); continue
            }
            guard FlexImportScope.index(for: date, now: now, calendar: calendar) != nil else {
                excluded.append("\(label): 이번 주의 오늘 이전 평일이 아님"); continue
            }
            guard day.dayOffs.isEmpty else {
                excluded.append("\(label): 휴무/휴가 지정 있음"); continue
            }
            guard !day.timeBlocks.isEmpty else {
                excluded.append("\(label): 근무 구간 없음"); continue
            }
            let unknown = Set(day.timeBlocks.map(\.type)).subtracting(["WORK", "REST"])
            guard unknown.isEmpty else {
                excluded.append("\(label): 미지원 근무유형 \(unknown.sorted().map { String($0.prefix(60)) }.joined(separator: ", "))"); continue
            }
            let nextDay = calendar.date(byAdding: .day, value: 1, to: date)!
            var work: [Range<Double>] = [], rest: [Range<Double>] = []
            var valid = true
            for block in day.timeBlocks {
                guard !block.value.allDay,
                      let start = block.value.startTimestamp?.timestamp,
                      let end = block.value.endTimestampExclusive?.timestamp,
                      start.isFinite, end.isFinite, end > start,
                      start >= date.timeIntervalSince1970 * 1000,
                      end <= nextDay.timeIntervalSince1970 * 1000 else { valid = false; break }
                if block.type == "REST" { rest.append(start..<end) }
                else { work.append(start..<end) }
            }
            guard valid else {
                excluded.append("\(label): 종일/시각 누락/날짜 경계 밖 구간"); continue
            }
            guard !work.isEmpty else {
                excluded.append("\(label): WORK 구간 없음"); continue
            }
            let working = merged(work), breaks = merged(rest)
            let gross = working.reduce(0) { $0 + $1.upperBound - $1.lowerBound }
            let overlap = working.reduce(0.0) { sum, w in
                sum + breaks.reduce(0.0) { $0 + max(0, min(w.upperBound, $1.upperBound) - max(w.lowerBound, $1.lowerBound)) }
            }
            let minutes = Int(((gross - overlap) / 60_000).rounded(.down))
            guard (0...24 * 60).contains(minutes) else {
                excluded.append("\(label): 하루 범위를 초과한 근무시간"); continue
            }
            records.append(FlexWorkRecord(date: date, minutes: minutes, accountID: userID))
        }
        guard Set(records.map(\.date)).count == records.count else { throw Failure.duplicateDate }
        return Report(records: records, receivedDays: response.dailySchedules.count, excluded: excluded)
    }

    private static func merged(_ intervals: [Range<Double>]) -> [Range<Double>] {
        var result: [Range<Double>] = []
        for interval in intervals.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let previous = result.last, interval.lowerBound <= previous.upperBound {
                result[result.count - 1] = previous.lowerBound..<max(previous.upperBound, interval.upperBound)
            } else { result.append(interval) }
        }
        return result
    }

    enum Failure: Error { case identityMismatch, duplicateDate }
}
