import XCTest
@testable import StrandAnalytics
import WhoopProtocol

/// Pins `DailyStressScore` and `NocturnalHRVLenses`. The expected values come from an independent oracle of
/// the same formula; the Kotlin `DailyStressScoreTest` holds the same literals.
final class DailyStressScoreTests: XCTestCase {
    private typealias N = DailyStressScore.Night

    private var base: [N] {
        let hrv: [Double] = [55, 60, 65]
        return (0..<30).map { N(restingHr: $0 % 2 == 0 ? 54 : 56, avgHrv: hrv[$0 % 3]) }
    }

    private func check(_ nights: [N], _ score: Double, _ rhr: Double?, _ hrv: Double?,
                       file: StaticString = #filePath, line: UInt = #line) {
        guard let r = DailyStressScore.score(nights, at: nights.count - 1) else {
            return XCTFail("expected a score", file: file, line: line)
        }
        XCTAssertEqual(r.score, score, accuracy: 1e-9, file: file, line: line)
        if let rhr { XCTAssertEqual(r.rhrDelta ?? .nan, rhr, accuracy: 1e-9, file: file, line: line) }
        else { XCTAssertNil(r.rhrDelta, file: file, line: line) }
        if let hrv { XCTAssertEqual(r.hrvDelta ?? .nan, hrv, accuracy: 1e-9, file: file, line: line) }
        else { XCTAssertNil(r.hrvDelta, file: file, line: line) }
    }

    func testAOneBpmRiseOnAStableBaselineStaysMedium() {
        // The old single-night z-sum read this as HIGH (2.19).
        check(base + [N(restingHr: 56, avgHrv: 60)], 1.562463856118229, 1.0, 0.01986758383728926)
    }

    func testAWeekOfLowHRVAndARaisedRHRIsHigh() {
        check(Array(base.prefix(24)) + Array(repeating: N(restingHr: 55, avgHrv: 45), count: 6)
              + [N(restingHr: 60, avgHrv: 45)], 2.657408581335632, 5.0, -11.540083885558303)
    }

    func testAWeekOfHighHRVAndALowRHRIsLow() {
        check(Array(base.prefix(24)) + Array(repeating: N(restingHr: 55, avgHrv: 75), count: 6)
              + [N(restingHr: 52, avgHrv: 75)], 0.6283486645312374, -3.0, 12.378106043920567)
    }

    func testRestingHROnlyUsesTheSDFloor() {
        check(Array(repeating: N(restingHr: 55, avgHrv: nil), count: 30) + [N(restingHr: 57, avgHrv: nil)],
              2.0911778518962216, 2.0, nil)
    }

    func testAThinBaselineGivesNoScore() {
        let nights = Array(repeating: N(restingHr: 55, avgHrv: 60), count: 5) + [N(restingHr: 58, avgHrv: 50)]
        XCTAssertNil(DailyStressScore.score(nights, at: nights.count - 1))
    }

    func testLensesNeedASessionAndReadItsMedianWindow() {
        // Three 5-minute windows of steady beats: the lenses report; a 4-minute span reports nothing.
        let start = 1_000_000
        var rr: [RRInterval] = []
        var ts = start
        var k = 0
        while ts < start + 900 {
            let ms = 1000 + (k % 4) * 40
            rr.append(RRInterval(ts: ts, rrMs: ms))
            ts += 1; k += 1
        }
        let lenses = NocturnalHRVLenses.compute(rr: rr, from: start, to: start + 900)
        XCTAssertNotNil(lenses.index)
        let short = NocturnalHRVLenses.compute(rr: rr, from: start, to: start + 240)
        XCTAssertNil(short.index)
        XCTAssertNil(short.freq)
    }
}
