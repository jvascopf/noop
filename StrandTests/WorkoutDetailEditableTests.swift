import XCTest
@testable import Strand

/// The workout detail offers Edit for sessions recorded on this device only (personal fork).
final class WorkoutDetailEditableTests: XCTestCase {
    func testOnDeviceSessionsAreEditable() {
        XCTAssertTrue(WorkoutDetailView.isEditable(source: "manual"))
        XCTAssertTrue(WorkoutDetailView.isEditable(source: "my-whoop-noop"))
    }

    func testImportedHistoryStaysReadOnly() {
        XCTAssertFalse(WorkoutDetailView.isEditable(source: "whoop"))
        XCTAssertFalse(WorkoutDetailView.isEditable(source: "apple-health"))
    }
}
