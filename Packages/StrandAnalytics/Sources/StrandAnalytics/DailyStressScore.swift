import Foundation
import WhoopProtocol

// DailyStressScore.swift — the daily 0–3 autonomic-load score (personal fork).
//
// Replaces the Stress screen's earlier single-night z-sum. That version added two raw z-scores of one
// night against a 30-day mean, so a 2 bpm resting-HR rise on a stable baseline (SD ~1 bpm) read as
// HIGH on its own, a normal day sat at MEDIUM, and correlated signals were counted twice. This version
// follows the HRV-guided-training literature (Plews, Buchheit and colleagues):
//
//   • HRV is read as ln(rMSSD), the 7-day rolling mean of the nightly values, against the mean and SD
//     of the daily ln values over the 30 days before the scored day.
//   • Resting HR is the scored night's value against its 30-day baseline, with the SD floored at
//     `rhrSDFloor` bpm so ordinary night-to-night noise is not a large deviation.
//   • Each deviation is shrunk by a neutral band of `neutralSD` SDs (the smallest worthwhile change):
//     anything inside it counts as a normal day.
//   • The two shrunk deviations are AVERAGED, not summed, then squashed onto 0–3 with the same
//     logistic as before (0 → 1.5), so the bands (0–1 low, 1–2 medium, 2–3 high) keep their meaning.
//
// A wellness proxy for physiological load (training, illness, alcohol, short sleep, stress alike),
// not a clinical stress measure. Pure; no clock or I/O.
public enum DailyStressScore {

    /// Days of history before the scored day that form the baseline.
    public static let baselineDays = 30
    /// Minimum baseline values a signal needs before it is used.
    public static let minBaselineValues = 7
    /// Nights in the rolling HRV mean, the scored night included.
    public static let rollingDays = 7
    /// Minimum nights with HRV inside the rolling window.
    public static let minRollingValues = 3
    /// Neutral band, in SDs, subtracted from each deviation before it counts.
    public static let neutralSD = 0.5
    /// Floor on the resting-HR baseline SD (bpm).
    public static let rhrSDFloor = 1.5

    /// One night's inputs, oldest→newest in the list passed to `score`.
    public struct Night: Equatable, Sendable {
        public let restingHr: Int?
        public let avgHrv: Double?
        public init(restingHr: Int?, avgHrv: Double?) {
            self.restingHr = restingHr
            self.avgHrv = avgHrv
        }
    }

    /// The score for one night plus the deltas the explanation copy reads.
    public struct Result: Equatable, Sendable {
        /// 0–3 (1.5 = baseline).
        public let score: Double
        /// Scored night's resting HR minus its baseline mean (bpm); nil when RHR was not used.
        public let rhrDelta: Double?
        /// 7-day HRV (geometric mean) minus the baseline geometric mean (ms); nil when HRV was not used.
        public let hrvDelta: Double?
        public init(score: Double, rhrDelta: Double?, hrvDelta: Double?) {
            self.score = score; self.rhrDelta = rhrDelta; self.hrvDelta = hrvDelta
        }
    }

    /// Logistic squash of a combined deviation onto 0–3 (0 → 1.5). Kotlin twin: `DailyStressScore.squash`.
    public static func squash(_ raw: Double) -> Double {
        min(max(3.0 / (1.0 + exp(-raw)), 0), 3)
    }

    /// A deviation shrunk toward zero by the neutral band. Kotlin twin: `DailyStressScore.beyondNeutral`.
    static func beyondNeutral(_ z: Double) -> Double {
        let m = max(0, abs(z) - neutralSD)
        return z < 0 ? -m : m
    }

    /// Score `nights[index]` against the nights before it. nil when neither signal has enough data.
    /// Kotlin twin: `DailyStressScore.score`.
    public static func score(_ nights: [Night], at index: Int) -> Result? {
        guard nights.indices.contains(index) else { return nil }
        let base = nights[max(0, index - baselineDays)..<index]
        var deviations: [Double] = []
        var rhrDelta: Double?
        var hrvDelta: Double?

        let rhrBase = base.compactMap { $0.restingHr }.map(Double.init)
        if let r = nights[index].restingHr, rhrBase.count >= minBaselineValues {
            let m = mean(rhrBase)
            let sd = max(populationSD(rhrBase, mean: m), rhrSDFloor)
            deviations.append((Double(r) - m) / sd)
            rhrDelta = Double(r) - m
        }

        let lnBase = base.compactMap { $0.avgHrv }.filter { $0 > 0 }.map { log($0) }
        let lnRoll = nights[max(0, index - rollingDays + 1)...index]
            .compactMap { $0.avgHrv }.filter { $0 > 0 }.map { log($0) }
        if lnBase.count >= minBaselineValues, lnRoll.count >= minRollingValues {
            let m = mean(lnBase)
            let sd = populationSD(lnBase, mean: m)
            if sd > 1e-9 {
                let r7 = mean(lnRoll)
                deviations.append((m - r7) / sd)   // lower HRV = more load
                hrvDelta = exp(r7) - exp(m)
            }
        }

        guard !deviations.isEmpty else { return nil }
        let raw = deviations.map(beyondNeutral).reduce(0, +) / Double(deviations.count)
        return Result(score: squash(raw), rhrDelta: rhrDelta, hrvDelta: hrvDelta)
    }

    private static func mean(_ xs: [Double]) -> Double { xs.reduce(0, +) / Double(xs.count) }

    private static func populationSD(_ xs: [Double], mean m: Double) -> Double {
        guard xs.count > 1 else { return 0 }
        return (xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count)).squareRoot()
    }
}

// NocturnalHRVLenses — Baevsky's Stress Index and the LF/HF ratio, read the way their methods assume.
//
// Both were computed over every beat since midnight, mixing sleep, walking and exercise. Baevsky's index
// and frequency-domain HRV are defined on short, stationary recordings (about 5 minutes, at rest), so a
// whole-day series is not comparable with their reference values. This splits the main sleep session into
// consecutive 5-minute windows, computes each lens per window, and reports the window at the median.
public enum NocturnalHRVLenses {

    /// Window length (s), the standard short-term HRV recording.
    public static let windowSec = 300
    /// Minimum windows with a result before a median is reported.
    public static let minWindows = 3

    /// Per-window Baevsky components and frequency bands over [from, to), each the window at its median
    /// (SI for the index, LF/HF for the bands). Kotlin twin: `NocturnalHRVLenses.compute`.
    public static func compute(rr: [RRInterval], from: Int, to: Int)
        -> (index: StressIndex.Components?, freq: HRVFreqDomain.Bands?) {
        guard to - from >= windowSec else { return (nil, nil) }
        let sorted = rr.sortedByTsStable().filter { $0.ts >= from && $0.ts < to }
        var indices: [StressIndex.Components] = []
        var bands: [HRVFreqDomain.Bands] = []
        var cursor = 0
        var start = from
        while start + windowSec <= to {
            let end = start + windowSec
            while cursor < sorted.count && sorted[cursor].ts < start { cursor += 1 }
            var j = cursor
            while j < sorted.count && sorted[j].ts < end { j += 1 }
            let raw = sorted[cursor..<j].map { Double($0.rrMs) }
            if let c = StressIndex.components(rawRR: raw) { indices.append(c) }
            if let b = HRVFreqDomain.freqDomain(rawRR: raw), b.lfhf != nil { bands.append(b) }
            cursor = j
            start = end
        }
        let index = indices.count >= minWindows ? medianElement(indices, by: { $0.si }) : nil
        let freq = bands.count >= minWindows ? medianElement(bands, by: { $0.lfhf ?? 0 }) : nil
        return (index, freq)
    }

    /// The element at the lower median by `key`; ties keep the earlier window.
    static func medianElement<T>(_ xs: [T], by key: (T) -> Double) -> T {
        let order = xs.indices.sorted { key(xs[$0]) == key(xs[$1]) ? $0 < $1 : key(xs[$0]) < key(xs[$1]) }
        return xs[order[(order.count - 1) / 2]]
    }
}
