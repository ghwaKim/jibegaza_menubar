import Foundation

struct FlexWorkRecord: Identifiable, Equatable {
    let date: Date
    let minutes: Int
    var accountID: String? = nil
    var id: Date { date }
}

