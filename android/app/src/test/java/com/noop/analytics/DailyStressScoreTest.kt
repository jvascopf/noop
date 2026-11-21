package com.noop.analytics

import com.noop.data.RrInterval
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Pins [DailyStressScore] and [NocturnalHRVLenses] with the same literals as the Swift
 * `DailyStressScoreTests`, which come from an independent oracle of the formula.
 */
class DailyStressScoreTest {
    private fun n(rhr: Int?, hrv: Double?) = DailyStressScore.Night(rhr, hrv)

    private val base: List<DailyStressScore.Night> = run {
        val hrv = listOf(55.0, 60.0, 65.0)
        (0 until 30).map { n(if (it % 2 == 0) 54 else 56, hrv[it % 3]) }
    }

    private fun check(nights: List<DailyStressScore.Night>, score: Double, rhr: Double?, hrv: Double?) {
        val r = DailyStressScore.score(nights, nights.size - 1)
        assertNotNull(r)
        assertEquals(score, r!!.score, 1e-9)
        if (rhr == null) assertNull(r.rhrDelta) else assertEquals(rhr, r.rhrDelta!!, 1e-9)
        if (hrv == null) assertNull(r.hrvDelta) else assertEquals(hrv, r.hrvDelta!!, 1e-9)
    }

    @Test fun aOneBpmRiseOnAStableBaselineStaysMedium() =
        check(base + n(56, 60.0), 1.562463856118229, 1.0, 0.01986758383728926)

    @Test fun aWeekOfLowHrvAndARaisedRhrIsHigh() =
        check(base.take(24) + List(6) { n(55, 45.0) } + n(60, 45.0), 2.657408581335632, 5.0, -11.540083885558303)

    @Test fun aWeekOfHighHrvAndALowRhrIsLow() =
        check(base.take(24) + List(6) { n(55, 75.0) } + n(52, 75.0), 0.6283486645312374, -3.0, 12.378106043920567)

    @Test fun restingHrOnlyUsesTheSdFloor() =
        check(List(30) { n(55, null) } + n(57, null), 2.0911778518962216, 2.0, null)

    @Test fun aThinBaselineGivesNoScore() {
        val nights = List(5) { n(55, 60.0) } + n(58, 50.0)
        assertNull(DailyStressScore.score(nights, nights.size - 1))
    }

    @Test fun lensesNeedASessionAndReadItsMedianWindow() {
        val start = 1_000_000L
        val rr = (0 until 900).map { RrInterval("t", start + it, 1000 + (it % 4) * 40) }
        assertNotNull(NocturnalHRVLenses.compute(rr, start, start + 900).first)
        val short = NocturnalHRVLenses.compute(rr, start, start + 240)
        assertNull(short.first)
        assertNull(short.second)
    }
}
