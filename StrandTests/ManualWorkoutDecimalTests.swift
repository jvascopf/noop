import XCTest
@testable import Strand

/// The manual workout form reads decimals typed with a comma or a point (personal fork).
final class ManualWorkoutDecimalTests: XCTestCase {
    func testCommaAndPointBothParse() {
        XCTAssertEqual(ManualWorkoutSheet.parseDecimal("5,2"), 5.2)
        XCTAssertEqual(ManualWorkoutSheet.parseDecimal("5.2"), 5.2)
        XCTAssertEqual(ManualWorkoutSheet.parseDecimal(" 12 "), 12)
    }

    func testNonNumbersStayInvalid() {
        XCTAssertNil(ManualWorkoutSheet.parseDecimal("abc"))
        XCTAssertNil(ManualWorkoutSheet.parseDecimal("5,2,1"))
    }

    func testAStoredDistanceReadsBackThroughTheParser() {
        let shown = ManualWorkoutSheet.distanceEntryString(5200, system: .metric)
        XCTAssertEqual(ManualWorkoutSheet.parseDecimal(shown), 5.2)
    }
}
