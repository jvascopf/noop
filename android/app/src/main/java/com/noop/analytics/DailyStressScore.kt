package com.noop.analytics

import com.noop.data.RrInterval
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.sqrt

/**
 * The daily 0–3 autonomic-load score (personal fork). Swift twin: `DailyStressScore`, which carries the
 * full method note: last night's resting HR (SD floored at [RHR_SD_FLOOR] bpm) and the 7-day mean of
 * ln(rMSSD) against the 30 days before, each shrunk by a ±[NEUTRAL_SD] SD neutral band, averaged, and
 * squashed onto 0–3 (0 → 1.5). A wellness proxy for physiological load, not a clinical stress measure.
 */
object DailyStressScore {
    const val BASELINE_DAYS = 30
    const val MIN_BASELINE_VALUES = 7
    const val ROLLING_DAYS = 7
    const val MIN_ROLLING_VALUES = 3
    const val NEUTRAL_SD = 0.5
    const val RHR_SD_FLOOR = 1.5

    data class Night(val restingHr: Int?, val avgHrv: Double?)

    data class Result(val score: Double, val rhrDelta: Double?, val hrvDelta: Double?)

    /** Logistic squash of a combined deviation onto 0–3 (0 → 1.5). Swift twin: `DailyStressScore.squash`. */
    fun squash(raw: Double): Double = (3.0 / (1.0 + exp(-raw))).coerceIn(0.0, 3.0)

    /** A deviation shrunk toward zero by the neutral band. Swift twin: `DailyStressScore.beyondNeutral`. */
    internal fun beyondNeutral(z: Double): Double {
        val m = maxOf(0.0, abs(z) - NEUTRAL_SD)
        return if (z < 0) -m else m
    }

    /**
     * Score `nights[index]` against the nights before it; null when neither signal has enough data.
     * Swift twin: `DailyStressScore.score`.
     */
    fun score(nights: List<Night>, index: Int): Result? {
        if (index !in nights.indices) return null
        val base = nights.subList(maxOf(0, index - BASELINE_DAYS), index)
        val deviations = ArrayList<Double>(2)
        var rhrDelta: Double? = null
        var hrvDelta: Double? = null

        val rhrBase = base.mapNotNull { it.restingHr?.toDouble() }
        val r = nights[index].restingHr
        if (r != null && rhrBase.size >= MIN_BASELINE_VALUES) {
            val m = mean(rhrBase)
            val sd = maxOf(populationSD(rhrBase, m), RHR_SD_FLOOR)
            deviations.add((r.toDouble() - m) / sd)
            rhrDelta = r.toDouble() - m
        }

        val lnBase = base.mapNotNull { it.avgHrv }.filter { it > 0 }.map { ln(it) }
        val lnRoll = nights.subList(maxOf(0, index - ROLLING_DAYS + 1), index + 1)
            .mapNotNull { it.avgHrv }.filter { it > 0 }.map { ln(it) }
        if (lnBase.size >= MIN_BASELINE_VALUES && lnRoll.size >= MIN_ROLLING_VALUES) {
            val m = mean(lnBase)
            val sd = populationSD(lnBase, m)
            if (sd > 1e-9) {
                val r7 = mean(lnRoll)
                deviations.add((m - r7) / sd)   // lower HRV = more load
                hrvDelta = exp(r7) - exp(m)
            }
        }

        if (deviations.isEmpty()) return null
        val raw = deviations.sumOf { beyondNeutral(it) } / deviations.size
        return Result(squash(raw), rhrDelta, hrvDelta)
    }

    private fun mean(xs: List<Double>): Double = xs.sum() / xs.size

    private fun populationSD(xs: List<Double>, m: Double): Double {
        if (xs.size <= 1) return 0.0
        return sqrt(xs.sumOf { (it - m) * (it - m) } / xs.size)
    }
}

/**
 * Baevsky's Stress Index and the LF/HF ratio from the most recent sleep session, in 5-minute windows,
 * each reported as the window at its median (personal fork). Swift twin: `NocturnalHRVLenses`, which
 * carries the method note.
 */
object NocturnalHRVLenses {
    const val WINDOW_SEC = 300L
    const val MIN_WINDOWS = 3

    /** Swift twin: `NocturnalHRVLenses.compute`. */
    fun compute(rr: List<RrInterval>, from: Long, to: Long): Pair<StressIndex.Components?, HrvFreqDomain.Bands?> {
        if (to - from < WINDOW_SEC) return null to null
        val sorted = rr.sortedBy { it.ts }.filter { it.ts >= from && it.ts < to }
        val indices = ArrayList<StressIndex.Components>()
        val bands = ArrayList<HrvFreqDomain.Bands>()
        var cursor = 0
        var start = from
        while (start + WINDOW_SEC <= to) {
            val end = start + WINDOW_SEC
            while (cursor < sorted.size && sorted[cursor].ts < start) cursor++
            var j = cursor
            while (j < sorted.size && sorted[j].ts < end) j++
            val raw = sorted.subList(cursor, j).map { it.rrMs.toDouble() }
            StressIndex.componentsRaw(raw)?.let { indices.add(it) }
            HrvFreqDomain.freqDomainRaw(raw)?.let { if (it.lfhf != null) bands.add(it) }
            cursor = j
            start = end
        }
        val index = if (indices.size >= MIN_WINDOWS) medianElement(indices) { it.si } else null
        val freq = if (bands.size >= MIN_WINDOWS) medianElement(bands) { it.lfhf ?: 0.0 } else null
        return index to freq
    }

    /** The element at the lower median by [key]; ties keep the earlier window. Swift twin: `medianElement`. */
    internal fun <T> medianElement(xs: List<T>, key: (T) -> Double): T {
        val order = xs.indices.sortedWith(compareBy<Int> { key(xs[it]) }.thenBy { it })
        return xs[order[(order.size - 1) / 2]]
    }
}
