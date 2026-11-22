import XCTest
import WhoopStore
@testable import Strand

/// Night-average HR under the sleeping-HR chart: the rounded mean of the night's minute buckets.
final class SleepNightAverageHRTests: XCTestCase {
    func testMeanOfMinuteBucketsRounded() {
        let b = [HRBucket(ts: 0, bpm: 52, minBpm: 50, maxBpm: 54),
                 HRBucket(ts: 60, bpm: 55, minBpm: 53, maxBpm: 57),
                 HRBucket(ts: 120, bpm: 58.5, minBpm: 56, maxBpm: 61)]
        XCTAssertEqual(SleepView.nightAverageHR(b), 55)   // 165.5 / 3 = 55.17
        XCTAssertNil(SleepView.nightAverageHR([]))
    }
}
