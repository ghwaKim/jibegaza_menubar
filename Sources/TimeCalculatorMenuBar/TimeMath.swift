import Foundation

let weekDays = ["월", "화", "수", "목", "금"]
let weeklyGoalMinutes = 40 * 60
let maxDailyMinutes = 9 * 60
let earliestStartMinutes = 8 * 60
let lunchStartMinutes = 12 * 60 + 30
let lunchEndMinutes = 13 * 60 + 30

func defaultWeekData() -> [DayWorkData] {
    weekDays.map { day in
        DayWorkData(
            day: day,
            mode: .manual,
            start: "",
            end: "",
            manualHours: "",
            manualMinutes: "",
            leaveType: .none,
            lockStart: false,
            lockEnd: false,
            lockManual: false
        )
    }
}

func timeToMinutes(_ time: String) -> Int {
    guard !time.isEmpty else { return 0 }
    let parts = time.split(separator: ":")
    guard parts.count == 2,
          let hours = Int(parts[0]),
          let minutes = Int(parts[1]) else {
        return 0
    }
    return hours * 60 + minutes
}

func minutesToTime(_ minutes: Int) -> String {
    let normalized = max(0, min(1439, minutes))
    let hours = normalized / 60
    let mins = normalized % 60
    return String(format: "%02d:%02d", hours, mins)
}

func formatMinutesToKorean(_ totalMinutes: Int) -> String {
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60

    if hours > 0 && minutes > 0 {
        return "\(hours)시간 \(minutes)분"
    }

    if hours > 0 {
        return "\(hours)시간"
    }

    if minutes > 0 {
        return "\(minutes)분"
    }

    return "0분"
}

func getLeaveCreditMinutes(_ data: DayWorkData) -> Int {
    switch data.leaveType {
    case .annual:
        return 8 * 60
    case .half:
        return 4 * 60
    case .halfHalf:
        return 2 * 60
    case .none:
        return 0
    }
}

func getLunchOverlapMinutes(start: Int, end: Int) -> Int {
    max(0, min(end, lunchEndMinutes) - max(start, lunchStartMinutes))
}

func getWorkMinutes(_ data: DayWorkData) -> Int {
    if data.leaveType == .annual {
        return 0
    }

    if data.mode == .manual {
        let hours = Int(data.manualHours) ?? 0
        let minutes = Int(data.manualMinutes) ?? 0
        return max(0, hours * 60 + minutes)
    }

    let start = timeToMinutes(data.start)
    let end = timeToMinutes(data.end)

    if data.start.isEmpty || data.end.isEmpty || end <= start {
        return 0
    }

    return max(0, end - start - getLunchOverlapMinutes(start: start, end: end))
}

func getDailyMinutes(_ data: DayWorkData) -> Int {
    let leaveCredit = getLeaveCreditMinutes(data)
    let workMinutes = getWorkMinutes(data)
    return min(maxDailyMinutes, leaveCredit + max(0, workMinutes))
}

func getMaxWorkMinutesForDay(_ data: DayWorkData) -> Int {
    max(0, maxDailyMinutes - getLeaveCreditMinutes(data))
}

func clampWorkMinutesForDay(_ data: DayWorkData, workMinutes: Int) -> Int {
    max(0, min(getMaxWorkMinutesForDay(data), workMinutes))
}

func calculateReverseTime(baseTimeMinutes: Int, targetMinutes: Int, type: AutoFillType) -> Int {
    switch type {
    case .end:
        var currentTime = baseTimeMinutes
        if currentTime >= lunchStartMinutes && currentTime < lunchEndMinutes {
            currentTime = lunchEndMinutes
        }

        var endTime = currentTime + targetMinutes
        if currentTime < lunchStartMinutes && endTime > lunchStartMinutes {
            endTime += lunchEndMinutes - lunchStartMinutes
        }
        return endTime

    case .start:
        var currentTime = baseTimeMinutes
        if currentTime > lunchStartMinutes && currentTime <= lunchEndMinutes {
            currentTime = lunchStartMinutes
        }

        var startTime = currentTime - targetMinutes
        if currentTime > lunchEndMinutes && startTime < lunchEndMinutes {
            startTime -= lunchEndMinutes - lunchStartMinutes
        }
        return startTime

    case .manual:
        return baseTimeMinutes
    }
}
