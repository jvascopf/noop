import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One-off check of Apple's on-device language model (personal fork), the candidate offline fallback for the
/// Coach. Once per build it writes to the strap log whether the model is available, whether it supports
/// European Portuguese, and one timed test reply. Nothing leaves the device and nothing reads the result.
enum OnDeviceModelProbe {
    private static let doneKey = "noop.onDeviceModelProbe.build"

    @MainActor
    static func runOncePerBuild(log: @escaping (String) -> Void) async {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        guard UserDefaults.standard.string(forKey: doneKey) != build else { return }
        UserDefaults.standard.set(build, forKey: doneKey)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                log("on-device model: available")
            case .unavailable(let reason):
                log("on-device model: unavailable — \(reason)")
                return
            @unknown default:
                log("on-device model: unknown availability")
                return
            }
            log("on-device model: supports pt-PT=\(model.supportsLocale(Locale(identifier: "pt_PT"))) "
                + "pt-BR=\(model.supportsLocale(Locale(identifier: "pt_BR")))")
            let session = LanguageModelSession(instructions: "És um treinador de bem-estar. Responde sempre em português de Portugal, de forma breve.")
            let prompt = "Resumo da manhã em duas frases: recuperação 77%, sono 8 h 31 min, VFC 57 ms (o normal é 52 ms), FC em repouso 56 bpm."
            let start = Date()
            do {
                let reply = try await session.respond(to: prompt)
                log("on-device model: reply in \(Int(Date().timeIntervalSince(start) * 1000)) ms: \(reply.content)")
            } catch {
                log("on-device model: test reply failed — \(error)")
            }
        } else {
            log("on-device model: needs iOS 26 or later")
        }
        #else
        log("on-device model: SDK has no FoundationModels")
        #endif
    }
}
