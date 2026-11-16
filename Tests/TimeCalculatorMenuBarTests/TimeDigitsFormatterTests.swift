import Foundation
import Testing
@testable import TimeCalculatorMenuBar

struct TimeDigitsFormatterTests {
    @Test func editorRejectsNonDigitsAndOverlongInput() {
        for limit in [1, 2] {
            let formatter = TimeDigitsFormatter(maximumDigits: limit)
            for invalid in ["a", "한", "1a", "-1", "1.5", " ", "１２", "①", "123"] {
                #expect(!formatter.isPartialStringValid(invalid, newEditingString: nil, errorDescription: nil))
            }
            for valid in ["", "0", "9"] {
                #expect(formatter.isPartialStringValid(valid, newEditingString: nil, errorDescription: nil))
            }
            #expect(formatter.isPartialStringValid("12", newEditingString: nil, errorDescription: nil) == (limit == 2))
        }
    }
}
