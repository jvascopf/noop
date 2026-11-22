import Foundation
import WhoopProtocol

/// The window the Liquid Today heart-rate card shows (personal fork). The card used to open on the 5-minute
/// trace loaded at the previous launch and then cut to the last ~90 seconds once live HR arrived. It now
/// always shows the chosen span of stored HR, in per-minute means, with the live stream landing in the newest
/// bucket. iOS/macOS only; the Android Today card is unchanged.
enum TodayHRWindow {
    /// `@AppStorage` key: minutes of history, or `sinceMidnight` for the whole day so far.
    static let key = "noop.todayHRWindowMinutes"
    static let defaultMinutes = 60
    static let sinceMidnight = 0
    /// The choices the setting offers, in order.
    static let options = [30, 60, 120, sinceMidnight]

    /// Seconds per point: a minute for a window of two hours or less, five minutes for a whole day.
    static func bucketSeconds(windowMinutes: Int) -> Int {
        windowMinutes == sinceMidnight || windowMinutes > 120 ? 300 : 60
    }

    /// Start of the window (unix s) for `now`.
    static func start(windowMinutes: Int, now: Date, calendar: Calendar = .current) -> Int {
        if windowMinutes == sinceMidnight { return Int(calendar.startOfDay(for: now).timeIntervalSince1970) }
        return Int(now.timeIntervalSince1970) - windowMinutes * 60
    }

    /// Mean bpm per `bucketSeconds` bucket over `samples`, oldest first, keyed by the bucket's start. Samples
    /// before `from` and non-positive bpm are ignored; a bucket with no samples is absent.
    static func buckets(_ samples: [HRSample], from: Int, bucketSeconds: Int) -> [(ts: Int, bpm: Double)] {
        guard bucketSeconds > 0 else { return [] }
        var sums: [Int: (sum: Int, n: Int)] = [:]
        for s in samples where s.ts >= from && s.bpm > 0 {
            let key = s.ts - ((s.ts % bucketSeconds) + bucketSeconds) % bucketSeconds
            let cur = sums[key] ?? (0, 0)
            sums[key] = (cur.sum + s.bpm, cur.n + 1)
        }
        return sums.keys.sorted().map { key in
            let v = sums[key]!
            return (key, Double(v.sum) / Double(v.n))
        }
    }
}
