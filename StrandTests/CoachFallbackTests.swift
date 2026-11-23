import XCTest
import WhoopStore
@testable import Strand

/// The Coach's retry and fallback policy (personal fork).
final class CoachFallbackTests: XCTestCase {

    func testOnlyTemporaryFailuresAreRetried() {
        XCTAssertTrue(CoachFallback.isTransient(AICoachError.server(503, "overloaded")))
        XCTAssertTrue(CoachFallback.isTransient(AICoachError.server(500, "")))
        XCTAssertTrue(CoachFallback.isTransient(AICoachError.rateLimited("")))
        XCTAssertTrue(CoachFallback.isTransient(AICoachError.network("offline")))
        XCTAssertTrue(CoachFallback.isTransient(URLError(.timedOut)))
        XCTAssertFalse(CoachFallback.isTransient(URLError(.cancelled)))
        XCTAssertFalse(CoachFallback.isTransient(AICoachError.badKey))
        XCTAssertFalse(CoachFallback.isTransient(AICoachError.server(400, "bad request")))
        XCTAssertFalse(CoachFallback.isTransient(AICoachError.server(404, "no such model")))
    }

    func testGeminiFallsBackToItsLiteModel() {
        XCTAssertEqual(CoachFallback.modelChain(provider: .gemini, model: "gemini-flash-latest"),
                       ["gemini-flash-latest", "gemini-flash-lite-latest"])
        XCTAssertEqual(CoachFallback.modelChain(provider: .gemini, model: "gemini-flash-lite-latest"),
                       ["gemini-flash-lite-latest"])
        XCTAssertEqual(CoachFallback.modelChain(provider: .openAI, model: "gpt-5-mini"), ["gpt-5-mini"])
    }

    func testRetriesThenMovesToTheNextModel() async throws {
        var tried: [String] = []
        try await CoachFallback.run(models: ["main", "lite"], delays: [0, 0]) { model, _ in
            tried.append(model)
            if model == "main" { throw AICoachError.server(503, "overloaded") }
        }
        XCTAssertEqual(tried, ["main", "main", "main", "lite"])
    }

    func testAHalfStreamedReplyIsNotRepeated() async {
        var calls = 0
        do {
            try await CoachFallback.run(models: ["main", "lite"], delays: [0, 0]) { _, delivered in
                calls += 1
                delivered = true
                throw AICoachError.server(503, "overloaded")
            }
            XCTFail("expected the failure to be thrown")
        } catch {}
        XCTAssertEqual(calls, 1)
    }

    func testARejectedKeyIsNotRetried() async {
        var calls = 0
        do {
            try await CoachFallback.run(models: ["main", "lite"], delays: [0, 0]) { _, _ in
                calls += 1
                throw AICoachError.badKey
            }
            XCTFail("expected the failure to be thrown")
        } catch {
            guard case AICoachError.badKey = error else { return XCTFail("wrong error \(error)") }
        }
        XCTAssertEqual(calls, 1)
    }

    func testContextIsCutAtALineBreak() {
        XCTAssertEqual(CoachFallback.trimmedContext("short", limit: 10), "short")
        XCTAssertEqual(CoachFallback.trimmedContext("line one\nline two\nline three", limit: 20), "line one\nline two")
    }

    private func day(recovery: Double?, hrv: Double?, rhr: Int?, sleep: Double?) -> DailyMetric {
        DailyMetric(day: "2026-11-23", totalSleepMin: sleep, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv,
                    recovery: recovery, strain: nil, exerciseCount: nil)
    }

    func testTheFixedBriefStatesTheNumbersAndABand() {
        let brief = CoachFallback.templateBrief(day: day(recovery: 76.8, hrv: 57.4, rhr: 56, sleep: 511.35),
                                                hrvAverage: 52.2)
        XCTAssertEqual(brief, """
        The online coach isn't responding, so this brief was made on your phone from today's numbers.

        Charge 77% · HRV 57 ms (30-day average 52 ms) · Resting HR 56 bpm · Sleep 8h31

        Charge is high: a good day for a harder session.
        """)
    }

    func testTheFixedBriefNeedsSomethingToSay() {
        XCTAssertNil(CoachFallback.templateBrief(day: day(recovery: nil, hrv: nil, rhr: nil, sleep: nil), hrvAverage: 50))
        XCTAssertNil(CoachFallback.templateBrief(day: nil, hrvAverage: nil))
        XCTAssertEqual(CoachFallback.templateBrief(day: day(recovery: 20, hrv: nil, rhr: nil, sleep: nil), hrvAverage: nil), """
        The online coach isn't responding, so this brief was made on your phone from today's numbers.

        Charge 20%

        Charge is low: keep today easy and put sleep first.
        """)
    }
}
