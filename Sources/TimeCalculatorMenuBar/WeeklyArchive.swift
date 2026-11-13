import Foundation

/// A single recoverable snapshot, including ownership and lock metadata.
struct WeeklyArchive: Codable {
    let weekStart: Date?
    let savedAt: Date
    let data: [DayWorkData]
    let target: AutoFillTarget?
    let excludedIndexes: [Int]
    let flexAccountID: String?
}
