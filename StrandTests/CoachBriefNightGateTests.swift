import XCTest
@testable import Strand

/// The morning brief waits for last night to be scored, up to `nightWaitMinutes` past the chosen time.
@MainActor
final class CoachBriefNightGateTests: XCTestCase {
    func testWaitsForAnUnscoredNightUntilTheDeadline() {
        let seven = 7 * 60
        XCTAssertTrue(CoachBriefScheduler.shouldWaitForNight(nowMinutes: seven, scheduledMinutes: seven, nightReady: false))
        XCTAssertTrue(CoachBriefScheduler.shouldWaitForNight(
            nowMinutes: seven + CoachBriefScheduler.nightWaitMinutes - 1, scheduledMinutes: seven, nightReady: false))
        XCTAssertFalse(CoachBriefScheduler.shouldWaitForNight(
            nowMinutes: seven + CoachBriefScheduler.nightWaitMinutes, scheduledMinutes: seven, nightReady: false),
            "past the wait the brief goes out without the night")
    }

    func testAScoredNightDoesNotWait() {
        XCTAssertFalse(CoachBriefScheduler.shouldWaitForNight(nowMinutes: 7 * 60, scheduledMinutes: 7 * 60, nightReady: true))
    }
}
