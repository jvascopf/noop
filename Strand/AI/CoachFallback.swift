import Foundation
import WhoopStore
import StrandAnalytics
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What the Coach does when its provider is busy (personal fork). In order: retry a temporary failure twice,
/// then try Gemini's lighter model, then Apple's on-device model, and for the brief, a fixed summary of the
/// day's numbers. A non-temporary failure (a rejected key, a bad request) is never retried or hidden.
enum CoachFallback {
    /// Waits before each retry of the same model. Two retries: a busy provider usually clears within seconds,
    /// and a longer wait only holds the chat spinner.
    static let retryDelaysSeconds: [Double] = [2, 6]
    /// Gemini's provider-managed alias for its lightest Flash model, which is often free while the main one
    /// is overloaded and has its own quota.
    static let geminiLiteModel = "gemini-flash-lite-latest"
    /// Characters of data context the on-device model gets. Its window is a few thousand tokens, shared with
    /// the instructions and the reply.
    static let onDeviceContextChars = 6000
    /// Chat turns, besides the question, the on-device model sees.
    static let onDeviceHistoryTurns = 4

    /// Whether `error` is worth retrying: the provider busy or rate-limiting, a server-side failure, or the
    /// network. Never a rejected key or a request the provider refused as malformed.
    static func isTransient(_ error: Error) -> Bool {
        if let urlError = error as? URLError { return urlError.code != .cancelled }
        guard let coachError = error as? AICoachError else { return false }
        switch coachError {
        case .rateLimited, .network: return true
        case .server(let code, _): return [500, 502, 503, 504].contains(code)
        default: return false
        }
    }

    /// The models to try in order for `model` on `provider`: the chosen one, then Gemini's lighter one when
    /// the chosen model is a Gemini model other than a Lite one.
    static func modelChain(provider: AIProvider, model: String) -> [String] {
        guard provider == .gemini, !model.lowercased().contains("lite") else { return [model] }
        return [model, geminiLiteModel]
    }

    /// Runs `attempt` for each model of `models`, retrying a temporary failure after each of
    /// `retryDelaysSeconds`. `attempt` returns whether it delivered any output; once it has, its failure is
    /// thrown at once, since repeating a half-streamed reply would duplicate it. Throws the last failure.
    static func run(models: [String], delays: [Double] = retryDelaysSeconds,
                    log: (String) -> Void = { _ in },
                    attempt: (String, inout Bool) async throws -> Void) async throws {
        var lastError: Error = AICoachError.network("no model to try")
        for model in models {
            for pass in 0...delays.count {
                if pass > 0 { try await Task.sleep(nanoseconds: UInt64(delays[pass - 1] * 1_000_000_000)) }
                var delivered = false
                do {
                    try await attempt(model, &delivered)
                    return
                } catch {
                    if delivered || !isTransient(error) { throw error }
                    lastError = error
                    log("coach: \(model) attempt \(pass + 1) failed — \(error.localizedDescription)")
                }
            }
        }
        throw lastError
    }

    // MARK: On-device model

    /// Whether Apple's on-device model can answer now: iOS/macOS 26 or later, an eligible device, Apple
    /// Intelligence on and the model downloaded.
    static var onDeviceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Instructions for the on-device model: short, since its window is small, and in the app's language.
    @MainActor
    static func onDeviceInstructions(languageTag: String) -> String {
        AICoachEngine.localizedSystemPrompt("""
        You are a supportive wellness coach. Use only the user's own data given in the message. \
        Interpret the numbers rather than repeating them: say what they mean for today and give one or two \
        concrete actions. Be brief. You are not a doctor and never diagnose.
        """, languageTag: languageTag)
    }

    /// One reply from the on-device model, or nil when it is unavailable or fails.
    static func onDeviceReply(instructions: String, prompt: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard onDeviceAvailable else { return nil }
            let session = LanguageModelSession(instructions: instructions)
            guard let reply = try? await session.respond(to: prompt) else { return nil }
            let clean = reply.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : clean
        }
        #endif
        return nil
    }

    /// `context` cut to `onDeviceContextChars`, at a line break.
    static func trimmedContext(_ context: String, limit: Int = onDeviceContextChars) -> String {
        guard context.count > limit else { return context }
        let head = String(context.prefix(limit))
        guard let cut = head.lastIndex(of: "\n") else { return head }
        return String(head[..<cut])
    }

    /// The note under a reply that did not come from the chosen provider.
    static var onDeviceNote: String {
        String(localized: "Answered by the on-device model because the online coach didn't respond.")
    }

    // MARK: Fixed brief

    /// A brief built from `day`'s numbers with no model at all, the last resort when no model answers.
    /// `hrvAverage` is the 30-day average HRV. Nil when `day` carries none of the numbers it reports.
    static func templateBrief(day: DailyMetric?, hrvAverage: Double?) -> String? {
        guard let day else { return nil }
        var parts: [String] = []
        if let charge = day.recovery {
            parts.append(String(format: String(localized: "Charge %lld%%"), Int(charge.rounded())))
        }
        if let hrv = day.avgHrv {
            if let avg = hrvAverage {
                parts.append(String(format: String(localized: "HRV %lld ms (30-day average %lld ms)"),
                                    Int(hrv.rounded()), Int(avg.rounded())))
            } else {
                parts.append(String(format: String(localized: "HRV %lld ms"), Int(hrv.rounded())))
            }
        }
        if let rhr = day.restingHr {
            parts.append(String(format: String(localized: "Resting HR %lld bpm"), rhr))
        }
        if let sleep = day.totalSleepMin, sleep > 0 {
            let minutes = Int(sleep.rounded())
            parts.append(String(format: String(localized: "Sleep %@"), "\(minutes / 60)h\(String(format: "%02d", minutes % 60))"))
        }
        guard !parts.isEmpty else { return nil }
        var lines = [String(localized: "The online coach isn't responding, so this brief was made on your phone from today's numbers."),
                     parts.joined(separator: " · ")]
        if let charge = day.recovery {
            if charge < RecoveryScorer.bandRedMax {
                lines.append(String(localized: "Charge is low: keep today easy and put sleep first."))
            } else if charge < RecoveryScorer.bandYellowMax {
                lines.append(String(localized: "Charge is moderate: train, but keep the intensity in check."))
            } else {
                lines.append(String(localized: "Charge is high: a good day for a harder session."))
            }
        }
        return lines.joined(separator: "\n\n")
    }
}
