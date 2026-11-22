import XCTest
import WhoopProtocol
@testable import Strand

/// The Liquid Today heart-rate card's window: bucket size and per-bucket means.
final class TodayHRWindowTests: XCTestCase {
    func testBucketSizeFollowsTheWindow() {
        XCTAssertEqual(TodayHRWindow.bucketSeconds(windowMinutes: 60), 60)
        XCTAssertEqual(TodayHRWindow.bucketSeconds(windowMinutes: 120), 60)
        XCTAssertEqual(TodayHRWindow.bucketSeconds(windowMinutes: TodayHRWindow.sinceMidnight), 300)
    }

    func testBucketsAreMinuteMeansFromTheWindowStart() {
        let samples = [HRSample(ts: 50, bpm: 99),            // before the window: ignored
                       HRSample(ts: 120, bpm: 60), HRSample(ts: 150, bpm: 70),
                       HRSample(ts: 179, bpm: 0),             // no reading: ignored
                       HRSample(ts: 300, bpm: 80)]
        let b = TodayHRWindow.buckets(samples, from: 100, bucketSeconds: 60)
        XCTAssertEqual(b.map(\.ts), [120, 300])
        XCTAssertEqual(b.map(\.bpm), [65, 80])
    }

    func testAWindowOfOneHourStartsAnHourAgo() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertEqual(TodayHRWindow.start(windowMinutes: 60, now: now), 10_000 - 3600)
    }
}
