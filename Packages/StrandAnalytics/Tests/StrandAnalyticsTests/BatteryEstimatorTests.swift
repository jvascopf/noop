import XCTest
@testable import StrandAnalytics

final class BatteryEstimatorTests: XCTestCase {

    private let h = 3600

    func testNilWhenNoSamples() {
        XCTAssertNil(BatteryEstimator.estimate(samples: [], ratedHours: BatteryEstimator.ratedLifeHoursWhoop5))
    }

    func testMeasuredRateFromCleanDischarge() {
        // 100% to 90% over 10h is 1 %/h; at 90% that leaves 90h, from the user's own discharge.
        let e = BatteryEstimator.estimate(samples: [(0, 100), (10 * h, 90)],
                                          ratedHours: BatteryEstimator.ratedLifeHoursWhoop5)!
        XCTAssertEqual(e.source, .measured)
        XCTAssertEqual(e.remainingHours, 90, accuracy: 1e-6)
        XCTAssertEqual(e.hoursRemaining, 90, accuracy: 1e-6)
        XCTAssertEqual(e.daysRemaining, 90.0 / 24, accuracy: 1e-6)
        XCTAssertEqual(e.currentSoc, 90, accuracy: 1e-6)
    }

    func testRatedFallbackWhenSpanTooShort() {
        // A single reading has no span to fit, so it falls back to rated: 50 / (100/108) = 54h.
        let e = BatteryEstimator.estimate(samples: [(0, 50)],
                                          ratedHours: BatteryEstimator.ratedLifeHoursWhoop4)!
        XCTAssertEqual(e.source, .rated)
        XCTAssertEqual(e.remainingHours, 54, accuracy: 1e-6)
    }

    func testChargeRestartsTheDischargeRun() {
        // Discharge 100->70, then a charge back to 100, then 100->88 over 6h. The rate is fit on the
        // post-charge segment only (2 %/h), never across the charge.
        let e = BatteryEstimator.estimate(samples: [(0, 100), (4 * h, 70), (5 * h, 100), (11 * h, 88)],
                                          ratedHours: BatteryEstimator.ratedLifeHoursWhoop5)!
        XCTAssertEqual(e.source, .measured)
        XCTAssertEqual(e.remainingHours, 44, accuracy: 1e-6)   // 88 / 2
    }

    func testPartialTopUpDoesNotInflateDaysLeft() {
        // #8: a partial top-up must NOT reset the discharge run like a full charge. Buffer is a long clean
        // discharge 100%->40% over 60h (1 %/h), a quick desk top-up 40->55 at 61h, then 55->53 over 3h. The
        // old scan anchored the run on the +15pp top-up and fit ~0.67 %/h on the 3h tail, inflating the
        // estimate. With the near-full guard the top-up is stepped over, the fit prefers the long pre-top-up
        // segment (1 %/h), and at 53% that is an honest ~53h, not the inflated ~79h.
        let e = BatteryEstimator.estimate(
            samples: [(0, 100), (60 * h, 40), (61 * h, 55), (64 * h, 53)],
            ratedHours: BatteryEstimator.ratedLifeHoursWhoop5)!
        XCTAssertEqual(e.source, .measured)
        XCTAssertEqual(e.currentSoc, 53, accuracy: 1e-6)
        XCTAssertEqual(e.remainingHours, 53, accuracy: 1e-6)   // 53 / (1 %/h), pre-top-up slope
    }

    func testMeasuredFromRecentDischargeWithoutNearFullCharge() {
        // #919: a WHOOP 5.0 that never tops past 90% - SoC rises 16->52, then discharges 52->44 over 8h. The
        // old scan found no near-full anchor and fell back to the OLDEST (16%) reading, so the window netted
        // to a CHARGE (drop<0) and the estimate stayed on rated. Anchoring at the buffer's max (52%) fits the
        // real 1 %/h discharge -> measured, 44h. (Distinct from #8, whose buffer already starts at its max.)
        let e = BatteryEstimator.estimate(
            samples: [(0, 16), (4 * h, 52), (12 * h, 44)],
            ratedHours: BatteryEstimator.ratedLifeHoursWhoop5)!
        XCTAssertEqual(e.source, .measured)
        XCTAssertEqual(e.currentSoc, 44, accuracy: 1e-6)
        XCTAssertEqual(e.remainingHours, 44, accuracy: 1e-6)   // 52->44 = 8pp over 8h = 1 %/h; 44 / 1
    }

    func testOldPeakDoesNotFlattenARecentFastDrain() {
        // #99: a WHOOP MG that tops up short of full every day (never trips the near-full rule), reported
        // "9% = ~3 days" when the real drain that day was ~1.5 %/h. Ten daily cycles of 30pp/20h (1.5 %/h),
        // each day's peak a little lower than the last (so the GLOBAL max sits all the way back on day
        // one), then today: a quick top-up to 25% and a 4h tail down to 9%. The old whole-buffer max scan
        // anchored on day one's peak and netted the fit across nine unseen intermediate top-ups, diluting
        // 1.5 %/h into ~0.3 %/h and reporting ~29h. Bounding the search to the last two cycles instead
        // anchors on YESTERDAY's peak (34%), fitting today's actual 1.5 %/h and landing on the honest 6h.
        var samples: [(ts: Int, soc: Double)] = []
        var t = 0
        for peak in stride(from: 70.0, through: 34.0, by: -4.0) {
            samples.append((t, peak)); t += 20 * h
            samples.append((t, peak - 30)); t += 1 * h
        }
        samples.append((t, 25)); t += 4 * h
        samples.append((t, 9))
        let e = BatteryEstimator.estimate(samples: samples, ratedHours: BatteryEstimator.ratedLifeHoursWhoop5)!
        XCTAssertEqual(e.source, .measured)
        XCTAssertEqual(e.currentSoc, 9, accuracy: 1e-6)
        XCTAssertEqual(e.remainingHours, 6, accuracy: 1e-6)   // 9 / 1.5 %/h, yesterday's real slope
    }

    func testNearFullChargeStillResetsTheRun() {
        // The guard must NOT change a genuine near-full charge: discharge 100->20, charge back to 95 (>=90,
        // near-full), then 95->85 over 5h is 2 %/h. The run still resets on the near-full charge, source
        // measured, 85 / 2 = 42.5h. This pins that the near-full anchor still fires (no regression of #713).
        let e = BatteryEstimator.estimate(
            samples: [(0, 100), (8 * h, 20), (9 * h, 95), (14 * h, 85)],
            ratedHours: BatteryEstimator.ratedLifeHoursWhoop5)!
        XCTAssertEqual(e.source, .measured)
        XCTAssertEqual(e.remainingHours, 42.5, accuracy: 1e-6)   // 85 / 2, post-near-full-charge segment
    }

    func testRatedFallbackWhenDropTooSmall() {
        // 100->99 over 10h is a 1% drop, under minDropPct(2), so it falls back to rated instead of
        // reporting a wild ~1000h. The estimate stays anchored to the latest SoC.
        let e = BatteryEstimator.estimate(samples: [(0, 100), (10 * h, 99)],
                                          ratedHours: BatteryEstimator.ratedLifeHoursWhoop5)!
        XCTAssertEqual(e.source, .rated)
        XCTAssertEqual(e.remainingHours, 285.12, accuracy: 1e-6)   // 99 / (100/288)
    }

    func testClampsToOneAndAHalfTimesRatedScaledToSoc() {
        // #99: the cap scales with CURRENT SoC (was a flat 1.5x of the FULL rated life). 100% to 90% over
        // 20h is 0.5 %/h, current 90% -> 180h raw, clamped to 108 * 1.5 * 0.90 = 145.8h (was 162h).
        let e = BatteryEstimator.estimate(samples: [(0, 100), (20 * h, 90)],
                                          ratedHours: BatteryEstimator.ratedLifeHoursWhoop4)!
        XCTAssertEqual(e.source, .measured)
        XCTAssertEqual(e.remainingHours, 145.8, accuracy: 1e-6)   // 108 * 1.5 * 0.90
    }

    func testLowSocClampScalesWithCurrentCharge() {
        // #99 (the report): a too-slow discharge (25% -> 9% over 100h ≈ 0.16 %/h, e.g. idle / off-wrist spans
        // or sparse 5/MG SoC readings) extrapolates 9% to ~56h raw — but 9% of a 12-day MG can't be ~2.3 days.
        // The SoC-scaled cap bounds it to 288 * 1.5 * 0.09 = 38.88h (~1.6 days), where the OLD flat 1.5x-rated
        // cap (432h) let the "9% = 3 days" nonsense through.
        let e = BatteryEstimator.estimate(samples: [(0, 25), (100 * h, 9)],
                                          ratedHours: BatteryEstimator.ratedLifeHoursWhoop5)!
        XCTAssertEqual(e.source, .measured)
        XCTAssertEqual(e.currentSoc, 9, accuracy: 1e-6)
        XCTAssertEqual(e.remainingHours, 38.88, accuracy: 1e-6)   // 288 * 1.5 * 0.09, not ~56h
    }

    func testUnsortedSamplesAreHandled() {
        // Same two points as the clean-discharge case but out of order: result must match.
        let e = BatteryEstimator.estimate(samples: [(10 * h, 90), (0, 100)],
                                          ratedHours: BatteryEstimator.ratedLifeHoursWhoop5)!
        XCTAssertEqual(e.source, .measured)
        XCTAssertEqual(e.remainingHours, 90, accuracy: 1e-6)
        XCTAssertEqual(e.currentSoc, 90, accuracy: 1e-6)
    }

    func testLabelSwitchesHoursToDaysAt48h() {
        XCTAssertEqual(BatteryEstimator.label(hours: 14), "~14h")
        XCTAssertEqual(BatteryEstimator.label(hours: 108), "~4.5 days")
    }

    // MARK: - Learned full-charge life and spikes (personal fork)

    /// Two finished discharges (98->2 over 80h = 83.33h per full charge, 99->15 over 84h = 100h), then a new
    /// charge to 97 and 4h of discharge. The kotlin twin asserts the same literals.
    private var twoFinishedDischarges: [(ts: Int, soc: Double)] {
        [(0, 98), (80 * h, 2), (81 * h, 99), (165 * h, 15), (166 * h, 97)]
    }

    func testLearnedLifeIsTheLowerMedianOfFinishedDischarges() {
        let life = BatteryEstimator.learnedFullChargeHours(twoFinishedDischarges + [(170 * h, 93)])!
        XCTAssertEqual(life, 83.33333333333333, accuracy: 1e-9)
    }

    func testEarlyInAChargeTheLearnedLifeBeatsAFewQuietHours() {
        // 97->93 over 4h is 1 %/h and would read 93h; the strap's finished charges say 1.2 %/h.
        let e = BatteryEstimator.estimate(samples: twoFinishedDischarges + [(170 * h, 93)],
                                          ratedHours: BatteryEstimator.ratedLifeHoursWhoop4)!
        XCTAssertEqual(e.source, .learned)
        XCTAssertEqual(e.remainingHours, 77.5, accuracy: 1e-9)   // 93 / (100 / 83.33)
    }

    func testAfterTwelveHoursTheOwnSlopeTakesOver() {
        let e = BatteryEstimator.estimate(samples: twoFinishedDischarges + [(186 * h, 73)],
                                          ratedHours: BatteryEstimator.ratedLifeHoursWhoop4)!
        XCTAssertEqual(e.source, .measured)
        XCTAssertEqual(e.remainingHours, 60.833333333333336, accuracy: 1e-9)   // 24pp / 20h = 1.2 %/h
    }

    func testAnIsolatedBadReadingIsDropped() {
        // A single 40% between 88% and 87.9% ten minutes apart once read as a drain plus a partial top-up.
        let samples: [(ts: Int, soc: Double)] = [(0, 100), (10 * h, 88), (10 * h + 600, 40), (10 * h + 1200, 87.9),
                                                 (14 * h, 84)]
        let e = BatteryEstimator.estimate(samples: samples, ratedHours: BatteryEstimator.ratedLifeHoursWhoop4)!
        XCTAssertEqual(e.source, .measured)
        XCTAssertEqual(e.remainingHours, 73.5, accuracy: 1e-9)   // 16pp / 14h; 84 / (8/7)
    }

    func testADenseChargeIsSeenAsOneCharge() {
        // A charge banks a reading every 30 s, 0.5 pp apart, so no single step clears chargeStepPct. Before the
        // rises were merged, the fit anchored on the older 99.5% peak and capped at 113.4h; the real slope since
        // the 94% top is 24pp / 20h.
        var samples: [(ts: Int, soc: Double)] = [(0, 99.5), (12 * h, 84.5), (24 * h, 69.5), (36 * h, 54.5), (48 * h, 39.5)]
        for k in 1...109 { samples.append((48 * h + 30 * k, 39.5 + 0.5 * Double(k))) }
        samples.append((68 * h + 3270, 70))
        let e = BatteryEstimator.estimate(samples: samples, ratedHours: BatteryEstimator.ratedLifeHoursWhoop4)!
        XCTAssertEqual(e.source, .measured)
        XCTAssertEqual(e.remainingHours, 58.333333333333336, accuracy: 1e-9)
        XCTAssertEqual(BatteryEstimator.learnedFullChargeHours(BatteryEstimator.collapsedRises(samples))!, 80, accuracy: 1e-9)
    }
}
